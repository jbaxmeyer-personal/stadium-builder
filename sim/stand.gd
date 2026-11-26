class_name Stand
extends RefCounted
## A stand along one pitch side. Geometry is in local coords:
##   u = position along the side (0 = pitch corner, left-to-right / top-to-bottom)
##   v = rows outward from the pitch edge (0 = row touching the touchline)
## Rows [setback, setback+depth) are the stand; the concourse sits right behind it.
##
## Corner stands (side NW/NE/SW/SE) fill the square between two side stands.
## They use (a, b) = tiles outward in x and in y from the pitch corner; a tile's
## row is max(a, b), so tiers step up diagonally. A corner is depth x depth
## tiles; offset is always 0 and length always equals depth.

const SIDES := ["N", "E", "S", "W"]
const CORNERS := ["NW", "NE", "SW", "SE"]
const ROOF_STYLES := ["cantilever", "gable", "shed", "barrel", "truss", "mast", "membrane", "translucent", "solar", "sawtooth", "open"]
const FACADES := ["concrete", "brick", "glass", "steel", "club", "fins", "panels", "arcade", "painted", "heritage", "stacked"]
## Cosmetic add-ons each stand can switch on and off, with their defaults.
##   name: lettering on the stand (text "" = the stand's own name)
##   flags: flagpoles along the roof   lights: an LED strip along the roof edge
##   clock: a clock on the roof        banners: fan banners along the front
const EXTRAS := {
	"name": { "on": false, "text": "", "line2": "", "where": "roof", "size": "M", "scale": 1.0, "color": "", "lit": true,
		"mount": "letters", "font": "classic", "depth": 0.08, "panel": "", "light": "", "light_color": "", "align": "centre" },
	"flags": { "on": false },
	"lights": { "on": false },
	"clock": { "on": false },
	"banners": { "on": false },
	"logo": { "on": false, "size": "M", "where": "centre", "lit": true, "mount": "flat", "light": "", "scale": 0.0 },
	"seats": { "pattern": "plain", "text": "", "color2": "" },
	"display": { "giant": "auto", "flag": "stripes", "spread": 0.6 },
	"uplight": { "on": false, "color": "", "spacing": 4.0 },
	"detail": { "seat_style": "tipup", "back": "standard", "aisles": -1, "rail": "", "nosing": "", "barrier": "", "steps": "", "boxes": false, "box_every": 2, "voms": -1 },
	"roof_shape": { "reach": 1.0, "tilt": 1.0, "fascia_h": 0.55, "columns": "round", "pylons": "none", "pylon_count": 2, "pylon_h": 1.0, "top_truss": "none", "truss_h": 1.0, "edge": "straight", "ends": "open", "clear_strip": 0.0 },
	"paint": { "roof": "", "fascia": "", "steel": "", "wall": "", "trim": "", "band": "", "front": "", "pylon": "",
		"roof_mat": "", "fascia_mat": "", "steel_mat": "", "wall_mat": "", "trim_mat": "", "band_mat": "", "front_mat": "", "pylon_mat": "" },
}
const LOGO_WHERE := ["centre", "left", "right"]
const CREST_MOUNTS := ["flat", "solid"]
const COLUMN_STYLES := ["round", "ibeam", "lattice", "none"]
## Finishes a player can give any part of a stand ("" = the part's default).
const FINISHES := ["concrete", "precast", "render", "plaster", "brick", "sandstone", "granite", "wood", "cladding",
	"metal_sheet", "corrugated", "steel_plate", "tiles", "rusty", "glass", "paint"]
## Steel on top of the roof: girders front to back, one long girder along the front, or a space frame.
const TOP_TRUSSES := ["none", "cross", "long", "space_frame"]
const ROOF_EDGES := ["straight", "wave", "arch", "sawtooth"]
const ROOF_ENDS := ["open", "closed", "glazed", "cranked"]
## Structure that carries the roof from outside the stand.
const PYLON_STYLES := ["none", "steel_pylon", "lattice_tower", "concrete_tower", "a_frame", "box_girder"]
## Signs placed on a stand's walls (cosmetic), kept in extras["signs"] as a list.
const SIGN_KINDS := ["text", "crest", "banner", "player", "mural"]
const SIGN_SURFACES := ["back", "end_left", "end_right", "inner_left", "inner_right", "front", "tier"]
const SIGN_DEFAULTS := { "kind": "text", "surface": "back", "u": 0.5, "v": 0.5, "scale": 1.0, "text": "", "line2": "",
	"mount": "letters", "font": "future", "depth": 0.08, "color": "", "panel": "", "light": "none", "light_color": "",
	"pattern": "stripes", "count": 1, "seed": 0, "fill": false }
const BANNER_PATTERNS := ["stripes", "halves", "hoops", "crest", "plain", "fans", "waves", "sunburst"]
const SEAT_STYLES := ["tipup", "bucket", "padded", "bench"]
const SEAT_BACKS := ["low", "standard", "high"]
const SEAT_PATTERNS := ["plain", "stripes", "blocks", "checks", "mosaic", "text", "crest"]
const NAME_WHERE := ["roof", "roof_top", "wall", "tier"]
const SIGN_MOUNTS := ["painted", "letters", "panel", "box", "frame"]
const SIGN_FONTS := ["classic", "future", "narrow", "blocks", "rocket", "high", "pixel"]
const SIGN_LIGHTS := ["", "none", "flood", "halo", "inside", "neon"]
const SIGN_ALIGNS := ["left", "centre", "right"]
const NAME_SIZES := ["S", "M", "L"]
const CORNER_SHAPES := ["square", "rounded"]

var side: String = "N"
var type_id: String = "seated"
var offset: int = 0
var length: int = 1
var depth: int = 1
var setback: int = 0
## The seating's shape: rake (degrees; shallow is cheap but far, steep is close
## but intimidating), front height above the pitch (metres-ish), and extra
## concourse behind the stand (tiles) for walking room and vendors.
var rake: float = 24.0
var plinth: float = 0.35
var concourse_extra: int = 0
var overhang: int = 0  # rows each upper tier reaches out over the one below (cantilevered tiers)
var gates: int = -1    # turnstile entrances; -1 = one per 7 tiles of frontage
# Cosmetic only (the sim ignores these):
var roof: String = "open"   # a new stand starts open to the sky
var seat_color: String = ""   # html colour; "" = default for the type / club
var facade: String = "concrete"  # cosmetic cladding on the back and end walls
var tiers: int = 1            # 1 = single tier; upper tiers stack above with their own concourse level
var shape: String = "square"  # corners only: "square" or "rounded" (quarter-circle outer edge)
var roundness: float = 1.0    # rounded corners: 1 = a quarter circle, towards 0 = squarer with a tight radius
var extras: Dictionary = {}   # cosmetic add-ons, only what differs from EXTRAS defaults


## The wall signs on this stand, defaults filled in.
func signs() -> Array:
	var out := []
	for d in extras.get("signs", []):
		var o: Dictionary = SIGN_DEFAULTS.duplicate()
		o.merge(d, true)
		out.append(o)
	return out


## An add-on's settings, defaults filled in.
func extra(key: String) -> Dictionary:
	var out: Dictionary = (EXTRAS[key] as Dictionary).duplicate()
	if extras.has(key):
		out.merge(extras[key], true)
	return out


static func make(p_side: String, p_type: String, p_offset: int, p_length: int, p_depth: int, p_setback := 0) -> Stand:
	var s := Stand.new()
	s.side = p_side
	s.type_id = p_type
	s.offset = p_offset
	s.length = p_length
	s.depth = p_depth
	s.setback = p_setback
	if s.is_corner():
		s.offset = 0
		s.length = p_depth
	return s


static func make_corner(p_corner: String, p_type: String, p_depth: int) -> Stand:
	return make(p_corner, p_type, 0, p_depth, p_depth)


func is_corner() -> bool:
	return side.length() == 2


func label() -> String:
	return "%s %s" % [side, type_id]


static func side_length(p_side: String, pitch: Rect2i) -> int:
	if p_side.length() == 2:
		return 1
	return pitch.size.x if p_side == "N" or p_side == "S" else pitch.size.y


## Corner coords: a tiles outward in x, b tiles outward in y from the pitch corner.
static func corner_to_grid(corner: String, pitch: Rect2i, a: int, b: int) -> Vector2i:
	var x := pitch.position.x - 1 - a if corner.ends_with("W") else pitch.end.x + a
	var y := pitch.position.y - 1 - b if corner.begins_with("N") else pitch.end.y + b
	return Vector2i(x, y)


static func local_to_grid(p_side: String, pitch: Rect2i, u: int, v: int) -> Vector2i:
	match p_side:
		"N": return Vector2i(pitch.position.x + u, pitch.position.y - 1 - v)
		"S": return Vector2i(pitch.position.x + u, pitch.end.y + v)
		"W": return Vector2i(pitch.position.x - 1 - v, pitch.position.y + u)
		_: return Vector2i(pitch.end.x + v, pitch.position.y + u)  # "E"


## Rows back from the stand front where tier k starts: each upper tier sits
## further back, so bigger stands need more ground, not just more height.
func tier_front(k: int) -> int:
	return k * maxi(1, depth / 2 - overhang)


## Rows of ground the whole stand covers (lower tier plus upper tiers' setback).
func footprint_depth() -> int:
	return depth + tier_front(tiers - 1)


## Every tile the stand stands on.
func tiles(pitch: Rect2i) -> Array[Vector2i]:
	if is_corner():
		return _corner_band(pitch, setback, footprint_depth())
	return _band(pitch, setback, footprint_depth())


## Tiles of the bottom tier only.
func lower_tiles(pitch: Rect2i) -> Array[Vector2i]:
	if is_corner():
		return _corner_band(pitch, setback, depth)
	return _band(pitch, setback, depth)


## Concourse tiles. Small stands have it behind them; big ones (internal = true)
## have it inside, under the raised back rows, like real stadiums.
func concourse_tiles(pitch: Rect2i, concourse_depth: int, internal := false) -> Array[Vector2i]:
	var start := concourse_start(concourse_depth, internal)
	var rows := concourse_depth
	if concourse_extra > 0:
		# extra walking room behind the stand: the concourse runs past the back
		rows = maxi(rows, setback + footprint_depth() - start) + concourse_extra
	if is_corner():
		return _corner_band(pitch, start, rows)
	return _band(pitch, start, rows)


## Corner tiles whose row lies in [r_start, r_start + rows).
func _corner_band(pitch: Rect2i, r_start: int, rows: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ab in _corner_cells(r_start, rows):
		out.append(corner_to_grid(side, pitch, ab.x, ab.y))
	return out


## Row of corner cell (a, b): square corners step by max(a, b); rounded ones
## by distance from the pitch corner, so the outer edge is a quarter circle.
func corner_row(a: int, b: int) -> int:
	if shape == "rounded":
		var p := corner_power()
		if is_equal_approx(p, 2.0):
			return floori(Vector2(a + 0.5, b + 0.5).length())
		return floori(pow(pow(a + 0.5, p) + pow(b + 0.5, p), 1.0 / p))
	return maxi(a, b)


## The superellipse power of a rounded corner's outline: 2 is a quarter
## circle; higher is squarer (a big square with a rounded-off tip).
func corner_power() -> float:
	return 2.0 / clampf(roundness, 0.15, 1.0)


func _corner_cells(r_start: int, rows: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for a in r_start + rows:
		for b in r_start + rows:
			var r := corner_row(a, b)
			if r >= r_start and r < r_start + rows:
				out.append(Vector2i(a, b))
	return out


## Tiles of one row (v counted from the front of the stand), for rendering.
func row_tiles(pitch: Rect2i, v: int) -> Array[Vector2i]:
	if is_corner():
		return _corner_band(pitch, setback + v, 1)
	return _band(pitch, setback + v, 1)


func _band(pitch: Rect2i, v_start: int, rows: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for v in range(v_start, v_start + rows):
		for u in range(offset, offset + length):
			out.append(local_to_grid(side, pitch, u, v))
	return out


## Places in one tier.
func tier_capacity(t: StandType) -> int:
	if is_corner():
		return _corner_cells(setback, depth).size() * t.capacity_per_tile
	return length * depth * t.capacity_per_tile


## Turnstile entrances: the player's number, or by default enough for the
## stand's frontage and size (one per gates_per_tiles tiles, at least one per
## `places_per_gate` places).
func gate_count(per_tiles: int, places_per_gate := 0, places := 0) -> int:
	if gates >= 0:
		return gates
	var by_len := maxi(1, int(length / float(per_tiles)))
	if places_per_gate > 0:
		return maxi(by_len, ceili(places / float(places_per_gate)))
	return by_len


## Places across all tiers (each tier matches the footprint of the lower one).
func capacity(t: StandType) -> int:
	return tier_capacity(t) * tiers


## Splits the stand into sections of up to section_length tiles. Each section's
## fans start walking from the concourse tile directly behind its middle.
## Returns [{ "source": Vector2i, "weight": float }], weights sum to 1.
## First concourse row: behind the stand; or, for big stands, inside it: under
## the upper tier (multi-tier) or under the raised back rows (deep single tier).
func concourse_start(concourse_depth: int, internal: bool) -> int:
	if not internal:
		return setback + footprint_depth()
	if tiers > 1:
		return setback + depth
	return setback + depth - concourse_depth


func sections(pitch: Rect2i, section_length: int, internal := false, concourse_depth := 2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var row := concourse_start(concourse_depth, internal) + (concourse_depth - 1 if internal and tiers == 1 else 0)
	if is_corner():
		var k := 0
		while corner_row(k, k) < row:
			k += 1
		return [{ "source": corner_to_grid(side, pitch, k, k), "weight": 1.0 }]
	var u := offset
	while u < offset + length:
		var n: int = min(section_length, offset + length - u)
		var mid := u + floori(n / 2.0)
		out.append({
			"source": local_to_grid(side, pitch, mid, row),
			"weight": float(n) / float(length),
		})
		u += n
	return out


func to_dict() -> Dictionary:
	return {
		"side": side, "type": type_id, "offset": offset,
		"length": length, "depth": depth, "setback": setback,
		"roof": roof, "seat_color": seat_color, "shape": shape, "roundness": roundness, "tiers": tiers, "facade": facade,
		"rake": rake, "plinth": plinth, "concourse_extra": concourse_extra, "gates": gates, "overhang": overhang,
		"extras": extras.duplicate(true), "v": 2,
	}


static func from_dict(d: Dictionary) -> Stand:
	var s := make(d["side"], d["type"], int(d["offset"]), int(d["length"]),
		int(d["depth"]), int(d.get("setback", 0)))
	s.roof = d.get("roof", "cantilever")
	s.seat_color = d.get("seat_color", "")
	s.shape = d.get("shape", "square")
	s.roundness = float(d.get("roundness", 1.0))
	s.tiers = int(d.get("tiers", 1))
	s.facade = d.get("facade", "concrete")
	s.rake = float(d.get("rake", 24.0))
	s.plinth = float(d.get("plinth", 0.35))
	s.concourse_extra = int(d.get("concourse_extra", 0))
	s.gates = int(d.get("gates", -1))
	s.overhang = int(d.get("overhang", 0))
	var ex: Variant = d.get("extras", {})
	if ex is Dictionary:
		s.extras = (ex as Dictionary).duplicate(true)
	# before v2 a side stand's name was on unless switched off
	if int(d.get("v", 1)) < 2 and not s.is_corner():
		var nm: Dictionary = s.extras.get("name", {})
		if not nm.has("on"):
			nm["on"] = true
			s.extras["name"] = nm
	return s
