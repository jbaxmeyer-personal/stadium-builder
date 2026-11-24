class_name Stand
extends RefCounted
## A stand along one pitch side. Geometry is in local coords:
##   u = position along the side (0 = pitch corner, left-to-right / top-to-bottom)
##   v = rows outward from the pitch edge (0 = row touching the touchline)
## Rows [setback, setback+depth) are the stand; the concourse sits right behind it.

const SIDES := ["N", "E", "S", "W"]

var side: String = "N"
var type_id: String = "seated"
var offset: int = 0
var length: int = 1
var depth: int = 1
var setback: int = 0


static func make(p_side: String, p_type: String, p_offset: int, p_length: int, p_depth: int, p_setback := 0) -> Stand:
	var s := Stand.new()
	s.side = p_side
	s.type_id = p_type
	s.offset = p_offset
	s.length = p_length
	s.depth = p_depth
	s.setback = p_setback
	return s


func label() -> String:
	return "%s %s" % [side, type_id]


static func side_length(p_side: String, pitch: Rect2i) -> int:
	return pitch.size.x if p_side == "N" or p_side == "S" else pitch.size.y


static func local_to_grid(p_side: String, pitch: Rect2i, u: int, v: int) -> Vector2i:
	match p_side:
		"N": return Vector2i(pitch.position.x + u, pitch.position.y - 1 - v)
		"S": return Vector2i(pitch.position.x + u, pitch.end.y + v)
		"W": return Vector2i(pitch.position.x - 1 - v, pitch.position.y + u)
		_: return Vector2i(pitch.end.x + v, pitch.position.y + u)  # "E"


func tiles(pitch: Rect2i) -> Array[Vector2i]:
	return _band(pitch, setback, depth)


func concourse_tiles(pitch: Rect2i, concourse_depth: int) -> Array[Vector2i]:
	return _band(pitch, setback + depth, concourse_depth)


func _band(pitch: Rect2i, v_start: int, rows: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for v in range(v_start, v_start + rows):
		for u in range(offset, offset + length):
			out.append(local_to_grid(side, pitch, u, v))
	return out


func capacity(t: StandType) -> int:
	return length * depth * t.capacity_per_tile


## Splits the stand into sections of up to section_length tiles. Each section's
## fans start walking from the concourse tile directly behind its middle.
## Returns [{ "source": Vector2i, "weight": float }], weights sum to 1.
func sections(pitch: Rect2i, section_length: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var u := offset
	while u < offset + length:
		var n: int = min(section_length, offset + length - u)
		var mid := u + floori(n / 2.0)
		out.append({
			"source": local_to_grid(side, pitch, mid, setback + depth),
			"weight": float(n) / float(length),
		})
		u += n
	return out


func to_dict() -> Dictionary:
	return {
		"side": side, "type": type_id, "offset": offset,
		"length": length, "depth": depth, "setback": setback,
	}


static func from_dict(d: Dictionary) -> Stand:
	return make(d["side"], d["type"], int(d["offset"]), int(d["length"]),
		int(d["depth"]), int(d.get("setback", 0)))
