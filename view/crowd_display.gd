extends Node3D
## The crowd's own show, built from a match report:
##   flags   - waving in each stand, more the louder the stand
##   banners - hung along the front of every stand, in club colours
##   tifo    - (renderer.build_crowd) a card display on the home end for big, loud matches
##   flares  - red flares and club-coloured smoke on terraces when the atmosphere is high
## Flags and banners stay after the match; flares only burn during the matchday moment.

const StadiumRenderer := preload("res://view/stadium_renderer.gd")
const SLOGANS := ["%s TILL I DIE", "WE ARE %s", "HOME OF %s", "%s ARMY", "NEVER SURRENDER", "OUR CLUB OUR CITY", "ONE CLUB  ONE LOVE", "%s FOREVER"]

var r: StadiumRenderer
var _flag_mat: ShaderMaterial


func _init(renderer: StadiumRenderer) -> void:
	r = renderer
	_flag_mat = ShaderMaterial.new()
	_flag_mat.shader = load("res://view/flag.gdshader")


func clear() -> void:
	for c in get_children():
		c.free()


func build(layout: Layout, config: SimConfig, report: MatchdayReport, club: ClubState, live: bool) -> void:
	clear()
	if report == null or club == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = report.seed
	var short := club.club_name.split(" ")[0].to_upper()
	var a := report.atmosphere / 100.0
	var flag_tf: Array[Transform3D] = []
	var flag_col: Array[Color] = []
	var flag_phase: Array[Color] = []
	for i in layout.stands.size():
		var s := layout.stands[i]
		if i >= report.stands.size():
			continue
		var st: Dictionary = report.stands[i]
		var t := config.stand_type(s.type_id)
		var tp := StadiumRenderer.to_pitch(s.side).normalized()
		var along := Vector2(-tp.y, tp.x)
		var face := atan2(tp.x, tp.y)
		# banners along the front wall, one per ~6 tiles
		if not s.is_corner() and st["attendance"] > 0 and s.type_id != "premium":
			var front := s.row_tiles(layout.pitch, 0)
			var n := maxi(1, front.size() / 7)
			for k in n:
				var tile: Vector2i = front[int((k + 0.5) * front.size() / n)]
				var c := Vector2(tile) + Vector2(0.5, 0.5) + tp * 0.52
				var text: String = SLOGANS[rng.randi_range(0, SLOGANS.size() - 1)]
				if text.contains("%s"):
					text = text % short
				var w := clampf(text.length() * 0.17, 1.6, 4.6)
				var swap := k % 2 == 1
				var bn := Node3D.new()
				bn.position = Vector3(c.x, 0.2, c.y)
				bn.rotation.y = face
				add_child(bn)
				r.lbox(bn, Vector3(0, 0, 0), Vector3(w, 0.36, 0.03), r.mat(club.secondary_color if swap else club.primary_color, 0.9))
				r.lbox(bn, Vector3(0, 0.155, 0.005), Vector3(w, 0.05, 0.03), r.mat(club.primary_color if swap else club.secondary_color, 0.9))
				var lab := Label3D.new()
				lab.text = text
				lab.font_size = 48
				lab.pixel_size = 0.0045
				lab.outline_size = 0
				lab.modulate = club.primary_color if swap else club.secondary_color
				lab.position = Vector3(0, -0.02, 0.02)
				bn.add_child(lab)
		# flags: louder stands wave more
		var count := int(st["attendance"] / 90.0 * t.noise * (0.3 + a))
		if live and i == r.tifo_stand(layout, config, report):
			count = 0  # hands are busy holding up the tifo cards
		var tiles := s.lower_tiles(layout.pitch)
		for k in mini(count, 400):
			var tile: Vector2i = tiles[rng.randi_range(0, tiles.size() - 1)]
			var v := _row_of(s, tile, layout.pitch)
			var p := Vector2(tile) + Vector2(rng.randf(), rng.randf())
			var y := StadiumRenderer.row_height(v) + 0.75
			var basis := Basis(Vector3.UP, face + rng.randf_range(-0.4, 0.4))
			flag_tf.append(Transform3D(basis, Vector3(p.x, y, p.y)))
			var pick := rng.randf()
			flag_col.append(club.primary_color if pick < 0.6 else (club.secondary_color if pick < 0.9 else Color.from_hsv(rng.randf(), 0.6, 0.8)))
			flag_phase.append(Color(rng.randf(), 0, 0, 0))
		# flares and smoke on loud terraces, during the match only
		if live and a >= 0.5 and (s.type_id == "terrace" or s.type_id == "safe_standing") and st["attendance"] > 0:
			var flares := clampi(int((a - 0.4) * 10.0 * s.length / 10.0), 1, 8)
			for k in flares:
				var tile: Vector2i = tiles[rng.randi_range(0, tiles.size() - 1)]
				var v := _row_of(s, tile, layout.pitch)
				_flare(Vector3(tile.x + 0.5, StadiumRenderer.row_height(v) + 0.6, tile.y + 0.5),
					club.primary_color if k % 2 == 0 else club.secondary_color, rng)
	_add_flags(flag_tf, flag_col, flag_phase)


func _row_of(s: Stand, tile: Vector2i, pitch: Rect2i) -> int:
	for v in s.depth:
		if tile in s.row_tiles(pitch, v):
			return v
	return 0


func _add_flags(tf: Array[Transform3D], col: Array[Color], phase: Array[Color]) -> void:
	if tf.is_empty():
		return
	var q := QuadMesh.new()
	q.size = Vector2(0.42, 0.28)
	q.center_offset = Vector3(0.21, 0, 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = tf.size()
	for i in tf.size():
		mm.set_instance_transform(i, tf[i])
		mm.set_instance_color(i, col[i])
		mm.set_instance_custom_data(i, phase[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _flag_mat
	add_child(mi)
	# poles
	var pole := BoxMesh.new()
	pole.size = Vector3(0.02, 0.6, 0.02)
	var pm := MultiMesh.new()
	pm.transform_format = MultiMesh.TRANSFORM_3D
	pm.mesh = pole
	pm.instance_count = tf.size()
	for i in tf.size():
		pm.set_instance_transform(i, Transform3D(tf[i].basis, tf[i].origin - Vector3(0, 0.12, 0)))
	var pi := MultiMeshInstance3D.new()
	pi.multimesh = pm
	pi.material_override = r.mat(Color(0.3, 0.3, 0.3), 0.6)
	add_child(pi)


## A burning flare: a bright red light and a column of coloured smoke.
func _flare(pos: Vector3, smoke: Color, rng: RandomNumberGenerator) -> void:
	var g := Node3D.new()
	g.position = pos
	add_child(g)
	r.box(g, Vector3(-0.05, -0.05, -0.05), Vector3(0.05, 0.05, 0.05), r.mat(Color(1.0, 0.25, 0.1), 0.3, 0.0, 6.0), false)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.3, 0.12)
	light.light_energy = 2.5
	light.omni_range = 3.0
	g.add_child(light)
	var p := CPUParticles3D.new()
	p.amount = 60
	p.lifetime = 3.5
	p.preprocess = 3.5
	p.direction = Vector3(0, 1, 0)
	p.spread = 20.0
	p.gravity = Vector3(rng.randf_range(-0.3, 0.3), 0.6, rng.randf_range(-0.3, 0.3))
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.2
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(smoke, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = m
	p.mesh = sm
	g.add_child(p)
