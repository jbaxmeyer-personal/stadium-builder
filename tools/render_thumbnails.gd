extends SceneTree
## Renders a 3D preview of every buildable thing with the game's own renderer
## (stands, bowl gear, outside buildings, concourse stalls, underground) into
## assets/thumbs/<id>.png, for the build menus. Run after changing how
## something looks:
##   VK_ICD_FILENAMES=... xvfb-run -a godot --rendering-driver vulkan -s tools/render_thumbnails.gd

const StadiumRenderer := preload("res://view/stadium_renderer.gd")
const SIZE := 256

var vp: SubViewport
var cam: Camera3D
var renderer: StadiumRenderer
var config: SimConfig


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	config = SimConfig.load_default()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/thumbs"))
	vp = SubViewport.new()
	vp.size = Vector2i(SIZE * 2, SIZE * 2)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -140, 0)
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	vp.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	renderer = StadiumRenderer.new()
	vp.add_child(renderer)
	await process_frame
	var club := ClubState.create(config)
	# the pitch
	var lp := Layout.create(config, "thumb")
	renderer.build_static(lp)
	await _shoot(lp, club, "pitch", Vector3(lp.pitch.get_center().x, 0, lp.pitch.get_center().y), 34.0, false, true)
	# stands
	for t in config.stand_type_ids():
		var l := Layout.create(config, "thumb")
		l.stands.append(Stand.make("S", t, 10, 8, 4))
		l.stands[0].roof = "gable" if t == "terrace" else "cantilever"
		var bb := StadiumRenderer.stand_aabb(l.stands[0], l.pitch)
		await _shoot(l, club, t, bb.get_center() + Vector3(0, 0.3, 0), 16.0)
	# facilities
	for id in config.facility_types:
		var ft := config.facility_type(id)
		var l := Layout.create(config, "thumb")
		var target := Vector3.ZERO
		var dist := 8.0
		match ft.layer:
			"bowl":
				l.stands.append(Stand.make("S", "seated", 10, 8, 4))
				if id == "exec_boxes":
					l.stands[0].tiers = 2
				var tiles: Array[Vector2i] = l.stands[0].tiles(l.pitch)
				l.facilities.append(Facility.make(id, tiles[tiles.size() / 2]))
				var bb := StadiumRenderer.stand_aabb(l.stands[0], l.pitch)
				# the gear hangs off the roof front; frame the top of the stand
				target = Vector3(bb.get_center().x, bb.end.y + 1.6, bb.position.z + 0.5)
				dist = 9.0 if id != "exec_boxes" else 12.0
				if id == "ribbon_board":
					target.y = bb.position.y + bb.size.y * 0.45
			_:
				var pos := Vector2i(l.plot.position.x + 2, l.plot.position.y + 2)
				var f := Facility.make(id, pos)
				l.facilities.append(f)
				target = Vector3(pos.x + ft.size.x / 2.0, 0.6, pos.y + ft.size.y / 2.0)
				dist = 3.5 + maxf(ft.size.x, ft.size.y) * 1.6
		await _shoot(l, club, id, target, dist, ft.layer == "underground")
	quit(0)


func _shoot(l: Layout, club: ClubState, id: String, target: Vector3, dist: float, under := false, show_pitch := false) -> void:
	renderer.surroundings = "none"
	renderer.build_layout(l, config, null, -1, club)
	renderer.set_layer("underground" if under else "stadium")
	for n in ["_ground", "_trees", "_lights", "_land", "_pitch_node", "_display", "_offers", "_markers", "_ghosts"]:
		var node = renderer.get(n)
		if node and node is Node3D:
			(node as Node3D).visible = false
	if under:
		renderer.get("_under").visible = true
	if show_pitch:
		renderer.get("_pitch_node").visible = true
	# stands face north (toward the pitch), so look at them from the pitch side
	var front_north := ["kiosk", "bar", "restroom", "first_aid", "museum", "merch", "fan_zone"]
	var yaw := deg_to_rad(215.0) if (l.stands.size() > 0 or id in front_north) else deg_to_rad(35.0)
	var pitch := deg_to_rad(-28.0)
	cam.position = target + Vector3(0, 0, dist).rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
	cam.look_at(target, Vector3.UP)
	for i in 8:
		await process_frame
	var img := vp.get_texture().get_image()
	img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	img.save_png("res://assets/thumbs/%s.png" % id)
	print("thumb ", id)
