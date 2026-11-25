class_name Facility
extends RefCounted
## A placed facility. `pos` is its top-left tile; it covers its type's `size`.
## Bowl items sit on a stand tile and belong to that stand.

var type_id: String
var pos: Vector2i
var style: String = ""   # cosmetic; "" = the type's first style
var level: int = 0       # concourse items: 0 = ground concourse, 1+ = an upper tier's concourse
var opts: Dictionary = {} # cosmetic options (see FacilityType.options)


static func make(p_type: String, p_pos: Vector2i, p_style := "") -> Facility:
	var f := Facility.new()
	f.type_id = p_type
	f.pos = p_pos
	f.style = p_style
	return f


func label() -> String:
	return "%s@%d,%d" % [type_id, pos.x, pos.y]


## A cosmetic option's value, or the type's default.
func opt(t: FacilityType, key: String) -> String:
	return String(opts.get(key, (t.options.get(key, [""]) as Array)[0]))


func tiles(t: FacilityType) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in t.size.x:
		for dy in t.size.y:
			out.append(pos + Vector2i(dx, dy))
	return out


func to_dict() -> Dictionary:
	return { "type": type_id, "x": pos.x, "y": pos.y, "style": style, "level": level, "opts": opts.duplicate() }


static func from_dict(d: Dictionary) -> Facility:
	var f := make(d["type"], Vector2i(int(d["x"]), int(d["y"])), d.get("style", ""))
	f.level = int(d.get("level", 0))
	var o: Variant = d.get("opts", {})
	if o is Dictionary:
		f.opts = (o as Dictionary).duplicate()
	return f
