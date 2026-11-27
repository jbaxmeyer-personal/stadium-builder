class_name Layout
extends RefCounted
## The stadium design: a plot (which grows as you buy land), a pitch the
## player places (until then pitch_placed is false and nothing else can go up),
## stands on the pitch sides and facilities on the concourse behind them.

const LAND_SIDES := ["N", "S", "E", "W"]
const FLOODLIGHT_STYLES := ["slim", "slim6", "pylons", "candles", "roof", "masts"]
const CROWD_CULTURES := ["british", "ultras", "latin", "german", "asian"]
const PITCH_PATTERNS := ["stripes", "wide_stripes", "checks", "diagonal", "diamonds", "circles", "plain"]
const SKIES := ["sunny", "cloudy", "overcast", "golden", "dusk"]
const GRASS_TYPES := ["classic", "lush", "emerald", "summer", "hybrid"]
const GOAL_STYLES := ["classic", "box", "stanchion"]
const NET_PATTERNS := ["none", "square", "hexagon", "striped"]
const AD_BOARDS := ["none", "rainbow", "club", "sponsor", "dark", "led"]
const DUGOUTS := ["none", "perspex", "brick", "stadium"]
const FLAG_PATTERNS := ["plain", "halves", "quarters", "stripes", "diagonal", "badge"]
const SURROUNDS := ["grass", "artificial", "track", "gravel", "hardstanding"]
const BARRIERS := ["none", "rail", "wall", "fence", "moat", "moat_water"]
const SURROUNDINGS := ["town", "riverside", "lakeside", "mountains", "city_edge", "suburban", "city", "fields", "forest"]

var name: String = "Untitled"
var base_plot: Rect2i                    # the plot you start with
var land := { "N": 0, "S": 0, "E": 0, "W": 0 }  # strips of land bought on each side
var strip_tiles: int = 6
var plot: Rect2i                         # current plot (base + land bought)
var width: int:
	get: return plot.size.x
var height: int:
	get: return plot.size.y
var pitch: Rect2i
var pitch_placed := true   # a new game starts with an empty plot (false) until the pitch goes down
var floodlights: String = "slim"         # cosmetic: a new ground has four slim masts
var pitch_pattern: String = "plain"      # cosmetic
var surroundings: String = "town"        # cosmetic: what's around the ground
var sky: String = "sunny"                # cosmetic: daylight preset
var pitch_grass: String = "classic"      # cosmetic: grass type (colour)
var goal_style: String = "classic"       # cosmetic
var net_color: String = "ffffff"         # cosmetic: html colour of the nets
var goal_color: String = "ffffff"        # cosmetic: html colour of the posts and crossbar
var line_color: String = "ffffff"        # cosmetic: html colour of the pitch markings
var paving_tint: String = ""            # cosmetic: a tint over the concrete paving ("" = natural)
var line_width: float = 1.0              # cosmetic: pitch markings, thinner or bolder
var mow_stripes: int = 12                # cosmetic: mown stripes across the pitch
var mow_contrast: float = 1.0            # cosmetic: how strongly they show
var net_depth: float = 1.0               # cosmetic: how far the nets run back (x the style's depth)
var net_sag: float = 0.3                 # cosmetic: 0 = taut, 1 = baggy
var tifo: String = "auto"               # cosmetic: the big-match card display: auto, bands, stripes, sash, band, checks, crest
var pitch_care: String = "none"         # cosmetic, between matches: none, sprinklers, lights (grow lights), covers
var heating: bool = false               # cosmetic: undersoil heating keeps snow off the pitch
var barrier_color: String = ""          # cosmetic: pitch-side barrier ("" = its own)
var surround_color: String = ""         # cosmetic: tint of the strip round the pitch ("" = its own)
var dugout_color: String = ""           # cosmetic: dugout seats and shell ("" = club colour)
var pyro_color: String = ""             # cosmetic: flare colour ("" = the club's colours)
var centre_crest: bool = false           # cosmetic: the club crest painted in the centre circle
var ad_texts: Array = []                 # cosmetic: the player's own words for the ad boards (empty = made-up sponsors)
var net_pattern: String = "none"         # cosmetic ("none" = goals without nets)
var ad_boards: String = "none"           # cosmetic: pitchside boards
var dugout: String = "none"              # cosmetic
var surround: String = "grass"           # cosmetic: ground between pitch and stands
var crowd_culture: String = "british"   # cosmetic: how the fans support (flags, flares, streamers, giant flags)
var dugout_side: String = "S"            # cosmetic: which touchline the dugouts sit on
var dugout_gap: int = 2                  # cosmetic: tiles from halfway to each dugout
var post_scoreboard: bool = false        # cosmetic: a scoreboard on posts behind a goal
var roof_ring: bool = false              # cosmetic: every roof at one height, one continuous ring
var roof_lid: String = "open"           # cosmetic, with a roof ring: "open", or "closed" (a lattice lid over the pitch)
var video_ring: bool = false             # cosmetic: a 360° screen hanging round the inner edge of the roof
var ring_reach: float = 0.0             # cosmetic: with a ring, how far every roof reaches in (0 = each stand's own)
var barrier: String = "none"             # cosmetic: rail, low wall, tall fence or moat round the pitch
## Corner flags (cosmetic). Colours are html; "" = the club's colours.
var corner_flags: Dictionary = { "on": false, "pole": "", "flag": "", "flag2": "", "pattern": "plain" }
const CORNER_FLAG_DEFAULTS := { "on": false, "pole": "", "flag": "", "flag2": "", "pattern": "plain" }
## Floodlight options (cosmetic): masts per side (0 = the style's own number),
## a height multiplier, and the paint of the masts ("" = galvanised grey).
const FLOOD_DEFAULTS := { "per_side": 0, "height": 1.0, "color": "", "lamp": "round" }
const LAMP_HEADS := ["round", "flood", "led"]
var flood: Dictionary = FLOOD_DEFAULTS.duplicate()
var stands: Array[Stand] = []
var facilities: Array[Facility] = []
## Tiles the player has painted: roads, paths and landscaping (tile -> item id
## from data/site_items.json).
var site: Dictionary = {}
## Saves from before roads existed: every transport link counts as connected.
var legacy_access := false

# Walking-distance cache. Keyed on the layout's contents, so any build or
# demolish (which changes to_dict) invalidates it automatically.
var _walk_cache := {}
var _walk_cache_sig := 0


static func create(config: SimConfig, p_name := "Untitled") -> Layout:
	var l := Layout.new()
	l.name = p_name
	var w := config.integer("plot/width")
	var h := config.integer("plot/height")
	l.base_plot = Rect2i(0, 0, w, h)
	l.strip_tiles = config.integer("land/strip_tiles")
	l.update_plot()
	var pw := config.integer("plot/pitch_width")
	var ph := config.integer("plot/pitch_height")
	l.pitch = Rect2i(floori((w - pw) / 2.0), floori((h - ph) / 2.0), pw, ph)
	return l


## Recompute the plot from the base and the land bought. Land to the north
## or west takes negative coordinates, so nothing already built moves.
func update_plot() -> void:
	var k := strip_tiles
	plot = Rect2i(base_plot.position - Vector2i(land["W"] * k, land["N"] * k),
		base_plot.size + Vector2i((land["W"] + land["E"]) * k, (land["N"] + land["S"]) * k))


func in_plot(p: Vector2i) -> bool:
	return plot.has_point(p)


## tile -> stand index
func stand_tile_map() -> Dictionary:
	var m := {}
	for i in stands.size():
		for t in stands[i].tiles(pitch):
			m[t] = i
	return m


## Big stands (deep enough) have their concourse inside, under the back rows.
static func internal_concourse(s: Stand, config: SimConfig) -> bool:
	return s.tiers > 1 or s.depth >= config.integer("layout/internal_concourse_min_depth")


func stand_concourse(s: Stand, config: SimConfig) -> Array[Vector2i]:
	return s.concourse_tiles(pitch, config.integer("layout/concourse_depth"), internal_concourse(s, config))


## tile -> stand index whose concourse it belongs to (first stand wins).
## An internal concourse sits on its own stand's tiles.
func concourse_tile_map(config: SimConfig) -> Dictionary:
	var m := {}
	var stand_tiles := stand_tile_map()
	for i in stands.size():
		for t in stand_concourse(stands[i], config):
			if in_plot(t) and not m.has(t) and (not stand_tiles.has(t) or stand_tiles[t] == i):
				m[t] = i
	return m


## Tiles fans can't walk through: stands, except their internal concourses.
func blocked_tiles(config: SimConfig) -> Dictionary:
	var m := stand_tile_map()
	for t in concourse_tile_map(config):
		m.erase(t)
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
	var cost := s.tier_capacity(t) * t.build_cost_per_place * factor
	if s.gates >= 0:
		cost += s.gates * config.num("ingress/gate_cost")
	# steeper and higher stands need more structure; shallow ones are cheaper
	cost *= 1.0 + config.num("layout/rake_cost_per_degree") * (s.rake - 24.0) + config.num("layout/plinth_cost_per_metre") * (s.plinth - 0.35)
	if s.roof != "open":
		# a roof covers every place in the stand
		cost += s.capacity(t) * config.num("layout/roof_cost_per_place")
	return cost


func build_cost(config: SimConfig) -> float:
	var cost := 0.0
	for s in stands:
		cost += stand_cost(s, config)
	for f in facilities:
		cost += config.facility_type(f.type_id).build_cost
	for t in site:
		cost += float(config.site_items[site[t]]["cost"])
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
	var occupied := {}
	if not pitch_placed and not stands.is_empty():
		errors.append("place the pitch first")
	if pitch_placed and not plot.encloses(pitch):
		errors.append("the pitch must be on the plot")
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
		if s.type_id == "bank" and (s.is_corner() or s.tiers > 1 or s.roof != "open"):
			errors.append("%s: a grass bank goes along a side, with no roof and no tiers" % s.label())
		if s.rake < config.num("layout/rake_min") or s.rake > config.num("layout/rake_max"):
			errors.append("%s: rake must be %d..%d degrees" % [s.label(), config.integer("layout/rake_min"), config.integer("layout/rake_max")])
		if s.plinth < 0.1 or s.plinth > config.num("layout/plinth_max"):
			errors.append("%s: front height out of range" % s.label())
		if s.concourse_extra < 0 or s.concourse_extra > config.integer("layout/concourse_extra_max"):
			errors.append("%s: concourse width out of range" % s.label())
		if s.depth < 1 or s.depth > max_depth:
			errors.append("%s: depth must be 1..%d" % [s.label(), max_depth])
		if s.tiers < 1 or s.tiers > config.integer("layout/max_tiers"):
			errors.append("%s: tiers must be 1..%d" % [s.label(), config.integer("layout/max_tiers")])
		if not s.shape in Stand.CORNER_SHAPES or (s.shape != "square" and not s.is_corner()):
			errors.append("%s: bad shape" % s.label())
		if s.roundness < 0.15 or s.roundness > 1.0:
			errors.append("%s: corner roundness out of range" % s.label())
		if not s.facade in Stand.FACADES:
			errors.append("%s: unknown facade" % s.label())
		if not s.roof in Stand.ROOF_STYLES:
			errors.append("%s: unknown roof style" % s.label())
		if s.setback < 0 or s.setback > max_setback:
			errors.append("%s: setback must be 0..%d" % [s.label(), max_setback])
		for t in s.tiles(pitch) + stand_concourse(s, config):
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
		if stands[stand_tiles[f.pos]].tiers < t.requires_tiers:
			return "%s: needs a stand with %d tiers" % [f.label(), t.requires_tiers]
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
				if t.kind == "circulation" and f.level == 0 and not ctx["concourse"].has(tile):
					# stair towers and ramps can also stand against the outside of a stand
					if pitch.has_point(tile) or stand_tiles.has(tile) or _touching_stand(tile, stand_tiles) < 0:
						return "%s: must be on a concourse or against the back of a stand" % f.label()
					continue
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


## The stand a tile touches (any of its 8 neighbours), or -1.
func _touching_stand(tile: Vector2i, stand_tiles: Dictionary) -> int:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var n := tile + Vector2i(dx, dy)
			if stand_tiles.has(n):
				return stand_tiles[n]
	return -1


## The stand a stair tower, ramp, escalator or lift serves: the one whose
## concourse it's on, or the one it stands against. -1 for none.
func circulation_stand(f: Facility, config: SimConfig, conc := {}, stand_tiles := {}) -> int:
	if conc.is_empty():
		conc = concourse_tile_map(config)
	if conc.has(f.pos):
		return conc[f.pos]
	if stand_tiles.is_empty():
		stand_tiles = stand_tile_map()
	var ft := config.facility_type(f.type_id)
	for tile in f.tiles(ft):
		var i := _touching_stand(tile, stand_tiles)
		if i >= 0:
			return i
	return -1


## Fans who can get to the ground: local streets and walking plus transport links.
func transport_capacity(config: SimConfig) -> float:
	var cap := config.num("transport/base_capacity")
	var status := transport_status(config)
	for f in facilities:
		var ft := config.facility_type(f.type_id)
		if status.has(f):
			var st: Dictionary = status[f]
			cap += ft.capacity * float(st["factor"])
		else:
			cap += ft.capacity
	return cap


# --- the site: roads, paths, landscaping -----------------------------------------

func site_group(t: Vector2i, config: SimConfig) -> String:
	return String(config.site_items[site[t]]["group"]) if site.has(t) else ""


## Tiles taken by things that aren't painted on: the pitch and its margin,
## stands, their concourses and outside buildings.
func solid_tiles(config: SimConfig) -> Dictionary:
	var m := {}
	if pitch_placed:
		var g := pitch.grow(1)
		for x in range(g.position.x, g.end.x):
			for y in range(g.position.y, g.end.y):
				m[Vector2i(x, y)] = true
	for t in stand_tile_map():
		m[t] = true
	for t in concourse_tile_map(config):
		m[t] = true
	for f in facilities:
		var ft := config.facility_type(f.type_id)
		if ft.layer == "outside":
			for t in f.tiles(ft):
				m[t] = true
	return m


## Painted tiles that something has since been built over are cleared.
func prune_site(config: SimConfig) -> void:
	var solid := solid_tiles(config)
	for t in site.keys():
		if solid.has(t) or not in_plot(t) or not config.site_items.has(site[t]):
			site.erase(t)


func _on_edge(t: Vector2i) -> bool:
	return t.x == plot.position.x or t.y == plot.position.y or t.x == plot.end.x - 1 or t.y == plot.end.y - 1


## Road tiles joined (through other road tiles) to the street round the plot.
func connected_roads(config: SimConfig) -> Dictionary:
	var seen := {}
	var queue: Array[Vector2i] = []
	for t in site:
		if _on_edge(t) and site_group(t, config) == "road":
			seen[t] = true
			queue.append(t)
	var i := 0
	while i < queue.size():
		var p := queue[i]
		i += 1
		for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var n: Vector2i = p + d
			if not seen.has(n) and site_group(n, config) == "road":
				seen[n] = true
				queue.append(n)
	return seen


## The tiles just outside a footprint (its four sides).
static func ring(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(r.position.x, r.end.x):
		out.append(Vector2i(x, r.position.y - 1))
		out.append(Vector2i(x, r.end.y))
	for y in range(r.position.y, r.end.y):
		out.append(Vector2i(r.position.x - 1, y))
		out.append(Vector2i(r.end.x, y))
	return out


## Per outside transport link: { connected, walk, factor }. A link counts only
## with a road to the street (or if it sits on the plot edge, on the street
## itself); fans then walk to the stands, quicker on paths than over grass, and
## a long walk puts some of them off. Keyed by the Facility object.
func transport_status(config: SimConfig) -> Dictionary:
	var out := {}
	var links: Array[Facility] = []
	var entrances: Array[Rect2i] = []
	for f in facilities:
		var ft := config.facility_type(f.type_id)
		if ft.layer in ["outside", "underground"] and ft.kind == "transport" and ft.capacity > 0.0:
			links.append(f)
		if ft.kind == "access":
			entrances.append(Rect2i(f.pos, f.size(ft)))
	if links.is_empty():
		return out
	var roads := connected_roads(config)
	var walk := _walk_from_stands(config)
	var free := config.num("site/walk_free")
	var span := config.num("site/walk_span")
	var max_loss := config.num("site/walk_max_loss")
	for f in links:
		var ft := config.facility_type(f.type_id)
		var r := Rect2i(f.pos, f.size(ft))
		if ft.layer == "underground":
			# underground: needs a way up to the surface over or beside it
			var up := legacy_access
			for e in entrances:
				if r.grow(2).intersects(e):
					up = true
			out[f] = { "connected": up, "walk": 0.0, "factor": 1.0 if up else 0.0, "entrance": up }
			continue
		var connected := legacy_access
		var best := INF
		for t in ring(r):
			if not in_plot(t) or roads.has(t):
				connected = true
			if walk.has(t):
				best = minf(best, float(walk[t]))
		var factor := 1.0
		if legacy_access or stands.is_empty():
			best = 0.0
		elif best == INF:
			factor = 1.0 - max_loss
		else:
			factor = 1.0 - max_loss * clampf((best - free) / span, 0.0, 1.0)
		out[f] = { "connected": connected, "walk": best, "factor": factor if connected else 0.0 }
	return out


## Walking cost from the nearest stand entrance to every reachable tile
## (paved tiles cost 1, grass costs more). Cached per layout state.
var _walk2_sig := 0
var _walk2 := {}


func _walk_from_stands(config: SimConfig) -> Dictionary:
	var sig := hash([site, stands.size(), to_dict()["stands"], pitch, plot, facilities.size()])
	if sig == _walk2_sig:
		return _walk2
	var grass := int(round(config.num("site/grass_walk_cost") * 2.0))
	var blocked := {}
	if pitch_placed:
		var g := pitch
		for x in range(g.position.x, g.end.x):
			for y in range(g.position.y, g.end.y):
				blocked[Vector2i(x, y)] = true
	var stand_tiles := blocked_tiles(config)
	for t in stand_tiles:
		blocked[t] = true
	for f in facilities:
		var ft := config.facility_type(f.type_id)
		if ft.layer == "outside":
			for t in f.tiles(ft):
				blocked[t] = true
	var paved := concourse_tile_map(config)
	# start from every open tile touching a stand (its entrances)
	var dist := {}
	var buckets: Array = [[]]
	for t in stand_tile_map():
		for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var n: Vector2i = t + d
			if in_plot(n) and not blocked.has(n) and not dist.has(n):
				dist[n] = 0
				buckets[0].append(n)
	var b := 0
	while b < buckets.size():
		var bucket: Array = buckets[b]
		var i := 0
		while i < bucket.size():
			var p: Vector2i = bucket[i]
			i += 1
			if int(dist[p]) < b:
				continue
			for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				var n: Vector2i = p + d
				if not in_plot(n) or blocked.has(n):
					continue
				var step := 2 if (paved.has(n) or site_group(n, config) in ["road", "path"]) else grass
				var nd := b + step
				if not dist.has(n) or int(dist[n]) > nd:
					dist[n] = nd
					while buckets.size() <= nd:
						buckets.append([])
					buckets[nd].append(n)
		b += 1
	# back to tile units
	for t in dist:
		dist[t] = float(dist[t]) / 2.0
	_walk2 = dist
	_walk2_sig = sig
	return dist


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
	# a plant room makes some of its own power (negative power), never below zero
	return { "power": maxf(0.0, power), "water": water }


func to_dict() -> Dictionary:
	var s := []
	for st in stands:
		s.append(st.to_dict())
	var f := []
	for fa in facilities:
		f.append(fa.to_dict())
	return { "name": name, "plot": [width, height], "pitch_at": [pitch.position.x, pitch.position.y], "pitch_placed": pitch_placed, "land": land.duplicate(), "floodlights": floodlights, "pitch_pattern": pitch_pattern, "surroundings": surroundings, "sky": sky, "pitch_grass": pitch_grass, "goal_style": goal_style, "net_color": net_color, "goal_color": goal_color, "line_color": line_color, "centre_crest": centre_crest, "pyro_color": pyro_color, "dugout_color": dugout_color, "surround_color": surround_color, "barrier_color": barrier_color, "heating": heating, "pitch_care": pitch_care, "tifo": tifo, "mow_stripes": mow_stripes, "line_width": line_width, "paving_tint": paving_tint, "mow_contrast": mow_contrast, "net_depth": net_depth, "net_sag": net_sag, "ad_texts": ad_texts.duplicate(), "net_pattern": net_pattern, "ad_boards": ad_boards, "dugout": dugout, "surround": surround, "barrier": barrier, "roof_ring": roof_ring, "ring_reach": ring_reach, "roof_lid": roof_lid, "video_ring": video_ring, "dugout_side": dugout_side, "dugout_gap": dugout_gap, "post_scoreboard": post_scoreboard, "crowd_culture": crowd_culture, "corner_flags": corner_flags.duplicate(), "flood": flood.duplicate(), "site": _site_list(), "stands": s, "facilities": f }


func _site_list() -> Array:
	var out := []
	var keys := site.keys()
	keys.sort()
	for t in keys:
		out.append([t.x, t.y, site[t]])
	return out


## Plot size and pitch size come from config; "plot" in the JSON is informational.
static func from_dict(d: Dictionary, config: SimConfig) -> Layout:
	var l := create(config, d.get("name", "Untitled"))
	var bought: Dictionary = d.get("land", {})
	for side in LAND_SIDES:
		l.land[side] = int(bought.get(side, 0))
	l.update_plot()
	if d.has("pitch_at"):
		var at: Array = d["pitch_at"]
		l.pitch.position = Vector2i(int(at[0]), int(at[1]))
	l.pitch_placed = bool(d.get("pitch_placed", true))
	l.floodlights = d.get("floodlights", "pylons")
	l.pitch_pattern = d.get("pitch_pattern", "stripes")
	l.surroundings = d.get("surroundings", "town")
	l.sky = d.get("sky", "sunny")
	l.pitch_grass = d.get("pitch_grass", "classic")
	l.goal_style = d.get("goal_style", "classic")
	l.net_color = d.get("net_color", "ffffff")
	l.goal_color = d.get("goal_color", "ffffff")
	l.line_color = d.get("line_color", "ffffff")
	l.centre_crest = bool(d.get("centre_crest", false))
	l.pyro_color = String(d.get("pyro_color", ""))
	l.dugout_color = String(d.get("dugout_color", ""))
	l.surround_color = String(d.get("surround_color", ""))
	l.barrier_color = String(d.get("barrier_color", ""))
	l.heating = bool(d.get("heating", false))
	l.pitch_care = String(d.get("pitch_care", "none"))
	l.tifo = String(d.get("tifo", "auto"))
	l.mow_stripes = int(d.get("mow_stripes", 12))
	l.line_width = float(d.get("line_width", 1.0))
	l.paving_tint = String(d.get("paving_tint", ""))
	l.mow_contrast = float(d.get("mow_contrast", 1.0))
	l.net_depth = float(d.get("net_depth", 1.0))
	l.net_sag = float(d.get("net_sag", 0.3))
	var at: Variant = d.get("ad_texts", [])
	if at is Array:
		for x in at:
			l.ad_texts.append(String(x))
	l.net_pattern = d.get("net_pattern", "square")
	l.ad_boards = d.get("ad_boards", "rainbow")
	l.dugout = d.get("dugout", "perspex")
	l.surround = d.get("surround", "grass")
	l.barrier = d.get("barrier", "none")
	l.roof_ring = bool(d.get("roof_ring", false))
	l.ring_reach = float(d.get("ring_reach", 0.0))
	l.roof_lid = String(d.get("roof_lid", "open"))
	l.video_ring = bool(d.get("video_ring", false))
	l.dugout_side = d.get("dugout_side", "S")
	l.dugout_gap = int(d.get("dugout_gap", 2))
	l.post_scoreboard = bool(d.get("post_scoreboard", false))
	l.crowd_culture = d.get("crowd_culture", "british")
	# saves from before pitch items started switched off always had flags
	var fl: Variant = d.get("flood", {})
	if fl is Dictionary:
		l.flood = FLOOD_DEFAULTS.duplicate()
		l.flood.merge(fl, true)
		l.flood["per_side"] = int(l.flood["per_side"])
		l.flood["height"] = float(l.flood["height"])
	var cf: Variant = d.get("corner_flags", { "on": true })
	if cf is Dictionary:
		l.corner_flags = CORNER_FLAG_DEFAULTS.duplicate()
		l.corner_flags.merge(cf, true)
	l.legacy_access = not d.has("site")
	for e in d.get("site", []):
		var row: Array = e
		l.site[Vector2i(int(row[0]), int(row[1]))] = String(row[2])
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
