class_name Facility
extends RefCounted
## A single-tile facility (kiosk, restroom block) placed on a concourse tile.

var type_id: String
var pos: Vector2i


static func make(p_type: String, p_pos: Vector2i) -> Facility:
	var f := Facility.new()
	f.type_id = p_type
	f.pos = p_pos
	return f


func label() -> String:
	return "%s@%d,%d" % [type_id, pos.x, pos.y]


func to_dict() -> Dictionary:
	return { "type": type_id, "x": pos.x, "y": pos.y }


static func from_dict(d: Dictionary) -> Facility:
	return make(d["type"], Vector2i(int(d["x"]), int(d["y"])))
