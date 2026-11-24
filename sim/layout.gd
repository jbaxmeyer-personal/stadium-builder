class_name Layout
extends RefCounted
## The stadium design: a fixed plot, a fixed centred pitch, stands on the
## pitch sides and facilities on the concourse behind them.

var name: String = "Untitled"
var width: int
var height: int
var pitch: Rect2i
var stands: Array[Stand] = []
var facilities: Array[Facility] = []

# Walking-distance cache. Keyed on the layout's contents, so any build or
# demolish (which changes to_dict) invalidates it automatically.
var _walk_cache := {}
var _walk_cache_sig := 0


static func create(config: SimConfig, p_name := "Untitled") -> Layout:
	var l := Layout.new()
	l.name = p_name
	l.width = config.integer("plot/width")
	l.height = config.integer("plot/height")
	var pw := config.integer("plot/pitch_width")
	var ph := config.integer("plot/pitch_height")
	l.pitch = Rect2i(floori((l.width - pw) / 2.0), floori((l.height - ph) / 2.0), pw, ph)
	return l


func in_plot(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


## tile -> stand index
func stand_tile_map() -> Dictionary:
	var m := {}
	for i in stands.size():
		for t in stands[i].tiles(pitch):
			m[t] = i
	return m


## tile -> stand index whose concourse it belongs to (first stand wins)
func concourse_tile_map(config: SimConfig) -> Dictionary:
	var m := {}
	var stand_tiles := stand_tile_map()
	var cd := config.integer("layout/concourse_depth")
	for i in stands.size():
		for t in stands[i].concourse_tiles(pitch, cd):
			if in_plot(t) and not stand_tiles.has(t) and not m.has(t):
				m[t] = i
	return m


func capacity_total(config: SimConfig) -> int:
	var c := 0
	for s in stands:
		c += s.capacity(config.stand_type(s.type_id))
	return c


func build_cost(config: SimConfig) -> float:
	var cost := 0.0
	for s in stands:
		var t := config.stand_type(s.type_id)
		cost += s.capacity(t) * t.build_cost_per_place
	for f in facilities:
		cost += config.facility_type(f.type_id).build_cost
	return cost


## Per-match maintenance: per place for stands, flat per facility.
func upkeep(config: SimConfig) -> Dictionary:
	var stand_upkeep := 0.0
	for s in stands:
		var t := config.stand_type(s.type_id)
		stand_upkeep += s.capacity(t) * t.upkeep_per_place
	var facility_upkeep := 0.0
	for f in facilities:
		facility_upkeep += config.facility_type(f.type_id).upkeep_per_match
	return { "stands": stand_upkeep, "facilities": facility_upkeep }


## Fans walk anywhere on the plot except the pitch and stand tiles.
func is_walkable(p: Vector2i, stand_tiles: Dictionary) -> bool:
	return in_plot(p) and not pitch.has_point(p) and not stand_tiles.has(p)


## Cached walk_distances() for this layout as it currently stands.
func walk_distances_cached(source: Vector2i, stand_tiles: Dictionary) -> Dictionary:
	var sig := hash(to_dict())
	if sig != _walk_cache_sig:
		_walk_cache.clear()
		_walk_cache_sig = sig
	if not _walk_cache.has(source):
		_walk_cache[source] = walk_distances(source, stand_tiles)
	return _walk_cache[source]


## BFS walking distance (in tiles) from source to every reachable tile.
func walk_distances(source: Vector2i, stand_tiles: Dictionary) -> Dictionary:
	var dist := {}
	if not is_walkable(source, stand_tiles):
		return dist
	dist[source] = 0
	var queue: Array[Vector2i] = [source]
	var head := 0
	var dirs := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	while head < queue.size():
		var p: Vector2i = queue[head]
		head += 1
		for d in dirs:
			var n: Vector2i = p + d
			if not dist.has(n) and is_walkable(n, stand_tiles):
				dist[n] = dist[p] + 1
				queue.append(n)
	return dist


## Returns a list of human-readable problems; empty means valid.
func validate(config: SimConfig, budget := -1.0) -> PackedStringArray:
	var errors := PackedStringArray()
	var max_depth := config.integer("layout/max_depth")
	var max_setback := config.integer("layout/max_setback")
	var cd := config.integer("layout/concourse_depth")
	var occupied := {}
	for s in stands:
		if not s.side in Stand.SIDES:
			errors.append("%s: bad side" % s.label())
			continue
		if not config.stand_types.has(s.type_id):
			errors.append("%s: unknown stand type" % s.label())
			continue
		if s.length < 1 or s.offset < 0 or s.offset + s.length > Stand.side_length(s.side, pitch):
			errors.append("%s: offset/length outside the pitch side" % s.label())
		if s.depth < 1 or s.depth > max_depth:
			errors.append("%s: depth must be 1..%d" % [s.label(), max_depth])
		if s.setback < 0 or s.setback > max_setback:
			errors.append("%s: setback must be 0..%d" % [s.label(), max_setback])
		for t in s.tiles(pitch) + s.concourse_tiles(pitch, cd):
			if not in_plot(t):
				errors.append("%s: stand or its concourse leaves the plot" % s.label())
				break
		for t in s.tiles(pitch):
			if occupied.has(t):
				errors.append("%s: overlaps another stand" % s.label())
				break
			occupied[t] = true
	var concourse := concourse_tile_map(config)
	var used := {}
	for f in facilities:
		if not config.facility_types.has(f.type_id):
			errors.append("%s: unknown facility type" % f.label())
		elif not concourse.has(f.pos):
			errors.append("%s: not on a concourse tile" % f.label())
		elif used.has(f.pos):
			errors.append("%s: tile already used" % f.label())
		used[f.pos] = true
	if budget >= 0.0 and build_cost(config) > budget:
		errors.append("build cost %.0f exceeds budget %.0f" % [build_cost(config), budget])
	return errors


func to_dict() -> Dictionary:
	var s := []
	for st in stands:
		s.append(st.to_dict())
	var f := []
	for fa in facilities:
		f.append(fa.to_dict())
	return { "name": name, "plot": [width, height], "stands": s, "facilities": f }


## Plot and pitch always come from config; "plot" in the JSON is informational.
static func from_dict(d: Dictionary, config: SimConfig) -> Layout:
	var l := create(config, d.get("name", "Untitled"))
	for sd in d.get("stands", []):
		l.stands.append(Stand.from_dict(sd))
	for fd in d.get("facilities", []):
		l.facilities.append(Facility.from_dict(fd))
	return l


func to_json() -> String:
	return JSON.stringify(to_dict(), "  ")


func save_json(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(to_json())
	return OK


static func load_json(path: String, config: SimConfig) -> Layout:
	var data: Variant = SimConfig.read_json(path)
	return from_dict(data, config)
