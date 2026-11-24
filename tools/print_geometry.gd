extends SceneTree
## Debug helper: prints an ASCII map of a layout.
##   godot --headless -s tools/print_geometry.gd -- data/layouts/x.json
## . open  # pitch  T/S/P stands  : concourse  K kiosk  R restroom

func _init() -> void:
	var config := SimConfig.load_default()
	var path: String = OS.get_cmdline_user_args()[0]
	var layout := Layout.load_json(path if path.begins_with("res://") else "res://" + path, config)
	var stand_tiles := layout.stand_tile_map()
	var concourse := layout.concourse_tile_map(config)
	var fac := {}
	for f in layout.facilities:
		fac[f.pos] = "K" if config.facility_type(f.type_id).kind == "food" else "R"
	for y in layout.height:
		var row := ""
		for x in layout.width:
			var p := Vector2i(x, y)
			if fac.has(p): row += fac[p]
			elif stand_tiles.has(p): row += layout.stands[stand_tiles[p]].type_id.left(1).to_upper()
			elif layout.pitch.has_point(p): row += "#"
			elif concourse.has(p): row += ":"
			else: row += "."
		print(row)
	quit(0)
