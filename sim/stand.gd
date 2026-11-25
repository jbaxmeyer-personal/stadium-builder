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
const ROOF_STYLES := ["cantilever", "gable", "barrel", "truss", "open"]
const CORNER_SHAPES := ["square", "rounded"]

var side: String = "N"
var type_id: String = "seated"
var offset: int = 0
var length: int = 1
var depth: int = 1
var setback: int = 0
# Cosmetic only (the sim ignores these):
var roof: String = "cantilever"
var seat_color: String = ""   # html colour; "" = default for the type / club
var tiers: int = 1            # 1 = single tier; upper tiers stack above with their own concourse level
var shape: String = "square"  # corners only: "square" or "rounded" (quarter-circle outer edge)


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


func tiles(pitch: Rect2i) -> Array[Vector2i]:
	if is_corner():
		return _corner_band(pitch, setback, depth)
	return _band(pitch, setback, depth)


## Concourse tiles. Small stands have it behind them; big ones (internal = true)
## have it inside, under the raised back rows, like real stadiums.
func concourse_tiles(pitch: Rect2i, concourse_depth: int, internal := false) -> Array[Vector2i]:
	var start := setback + depth - concourse_depth if internal else setback + depth
	if is_corner():
		return _corner_band(pitch, start, concourse_depth)
	return _band(pitch, start, concourse_depth)


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
		return floori(Vector2(a + 0.5, b + 0.5).length())
	return maxi(a, b)


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


## Places across all tiers (each tier matches the footprint of the lower one).
func capacity(t: StandType) -> int:
	return tier_capacity(t) * tiers


## Splits the stand into sections of up to section_length tiles. Each section's
## fans start walking from the concourse tile directly behind its middle.
## Returns [{ "source": Vector2i, "weight": float }], weights sum to 1.
func sections(pitch: Rect2i, section_length: int, internal := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var row := setback + depth - 1 if internal else setback + depth
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
		"roof": roof, "seat_color": seat_color, "shape": shape, "tiers": tiers,
	}


static func from_dict(d: Dictionary) -> Stand:
	var s := make(d["side"], d["type"], int(d["offset"]), int(d["length"]),
		int(d["depth"]), int(d.get("setback", 0)))
	s.roof = d.get("roof", "cantilever")
	s.seat_color = d.get("seat_color", "")
	s.shape = d.get("shape", "square")
	s.tiers = int(d.get("tiers", 1))
	return s
