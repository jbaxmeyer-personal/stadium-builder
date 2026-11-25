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


## Build cost of one stand: upper tiers cost more per place than the first.
static func stand_cost(s: Stand, config: SimConfig) -> float:
	var t := config.stand_type(s.type_id)
	var factor := 1.0 + (s.tiers - 1) * config.num("layout/upper_tier_cost_factor")
	return s.tier_capacity(t) * t.build_cost_per_place * factor


func build_cost(config: SimConfig) -> float:
	var cost := 0.0
	for s in stands:
		cost += stand_cost(s, config)
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
		if not (s.side in Stand.SIDES or s.side in Stand.CORNERS):
			errors.append("%s: bad side" % s.label())
			continue
		if not config.stand_types.has(s.type_id):
			errors.append("%s: unknown stand type" % s.label())
			continue
		if s.is_corner():
			if s.offset != 0 or s.length != s.depth or s.setback != 0:
				errors.append("%s: corner stands are square with no setback" % s.label())
		elif s.length < 1 or s.offset < 0 or s.offset + s.length > Stand.side_length(s.side, pitch):
			errors.append("%s: offset/length outside the pitch side" % s.label())
		if s.depth < 1 or s.depth > max_depth:
			errors.append("%s: depth must be 1..%d" % [s.label(), max_depth])
		if s.tiers < 1 or s.tiers > config.integer("layout/max_tiers"):
			errors.append("%s: tiers must be 1..%d" % [s.label(), config.integer("layout/max_tiers")])
		if not s.shape in Stand.CORNER_SHAPES or (s.shape != "square" and not s.is_corner()):
			errors.append("%s: bad shape" % s.label())
		if not s.roof in Stand.ROOF_STYLES:
			errors.append("%s: unknown roof style" % s.label())
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
	var ctx := placement_context(config)
	for f in facilities:
		var err := facility_error(f, config, ctx)
		if err != "":
			errors.append(err)
	if budget >= 0.0 and build_cost(config) > budget:
		errors.append("build cost %.0f exceeds budget %.0f" % [build_cost(config), budget])
	return errors


## Shared lookups for checking facility placement.
func placement_context(config: SimConfig) -> Dictionary:
	return { "stands": stand_tile_map(), "concourse": concourse_tile_map(config), "used": {} }


## "" if f can sit where it is; otherwise why not. Records f's tiles in ctx["used"]
## (per layer) so later facilities can't overlap it.
func facility_error(f: Facility, config: SimConfig, ctx: Dictionary) -> String:
	if not config.facility_types.has(f.type_id):
		return "%s: unknown facility type" % f.label()
	var t := config.facility_type(f.type_id)
	if f.style != "" and not f.style in t.styles:
		return "%s: unknown style" % f.label()
	if f.level < 0 or (f.level > 0 and t.layer != "concourse"):
		return "%s: only concourse items go on upper levels" % f.label()
	var used: Dictionary = ctx["used"]
	var used_key := "%s#%d" % [t.layer, f.level]
	if not used.has(used_key):
		used[used_key] = {}
	var taken: Dictionary = used[used_key]
	var stand_tiles: Dictionary = ctx["stands"]
	if t.layer == "bowl":
		if not stand_tiles.has(f.pos):
			return "%s: must be placed on a stand" % f.label()
		var key := "%s#%d" % [t.id, stand_tiles[f.pos]]
		if taken.has(key):
			return "%s: that stand already has one" % f.label()
		taken[key] = true
		return ""
	for tile in f.tiles(t):
		if not in_plot(tile):
			return "%s: off the plot" % f.label()
		if taken.has(tile):
			return "%s: overlaps another %s item" % [f.label(), t.layer]
		match t.layer:
			"concourse":
				if not ctx["concourse"].has(tile):
					return "%s: must be on the concourse (paved area behind a stand)" % f.label()
				if stands[ctx["concourse"][tile]].tiers <= f.level:
					return "%s: that stand has no level %d concourse (add a tier)" % [f.label(), f.level]
			"outside":
				if pitch.has_point(tile) or stand_tiles.has(tile) or ctx["concourse"].has(tile):
					return "%s: needs open ground outside the stands" % f.label()
			"underground":
				if pitch.grow(1).has_point(tile):
					return "%s: can't dig under the pitch" % f.label()
	for tile in f.tiles(t):
		taken[tile] = true
	return ""


## Fans who can get to the ground: local streets and walking plus transport links.
func transport_capacity(config: SimConfig) -> float:
	var cap := config.num("transport/base_capacity")
	for f in facilities:
		cap += config.facility_type(f.type_id).capacity
	return cap


## Utility use per match (power and water units).
func utilities(config: SimConfig) -> Dictionary:
	var places := capacity_total(config) / 1000.0
	var power := places * config.num("utilities/power_per_1000_places")
	var water := places * config.num("utilities/water_per_1000_places")
	if not stands.is_empty():
		power += config.num("utilities/floodlight_power")
	for f in facilities:
		var t := config.facility_type(f.type_id)
		power += t.power
		water += t.water
	return { "power": power, "water": water }


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
