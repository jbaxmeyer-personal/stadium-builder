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
	_players = null
	_ball = null


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
	_people_outside(layout, config, rng, 60 if live else 14)
	if live:
		_make_players(layout, club)


var _walkers: MultiMeshInstance3D
var _walk_data := []     # [start, end, speed, phase]
var _walk_mat: ShaderMaterial


## Supporters outside the ground, using the same fan model as the stands:
## most walk to and fro along the streets toward the ground, some stand about.
func _people_outside(layout: Layout, config: SimConfig, rng: RandomNumberGenerator, count: int) -> void:
	var blocked := layout.stand_tile_map()
	var pl := Rect2(layout.plot)
	_walk_data.clear()
	var cols: Array[Color] = []
	var custom: Array[Color] = []
	var club_cols := [r._club.primary_color, r._club.secondary_color] if r._club else [Color.RED, Color.WHITE]
	for i in count:
		var pos := Vector2.ZERO
		for attempt in 20:
			pos = Vector2(rng.randf_range(pl.position.x + 0.5, pl.end.x - 0.5), rng.randf_range(pl.position.y + 0.5, pl.end.y - 0.5))
			var t := Vector2i(floori(pos.x), floori(pos.y))
			if not blocked.has(t) and not layout.pitch.grow(1).has_point(t):
				break
		var walker := i % 4 != 0
		var dest := pos
		if walker:
			var dir := (Vector2(layout.pitch.get_center()) - pos).normalized().rotated(rng.randf_range(-0.6, 0.6))
			dest = pos + dir * rng.randf_range(3.0, 7.0)
		_walk_data.append([pos, dest, rng.randf_range(0.35, 0.55), rng.randf() * 10.0])
		cols.append(club_cols[0] if rng.randf() < 0.6 else (club_cols[1] if rng.randf() < 0.5 else Color.from_hsv(rng.randf(), 0.4, rng.randf_range(0.2, 0.7))))
		custom.append(Color(rng.randf(), 0.0, rng.randf(), 0.5 if rng.randf() < 0.4 else 0.0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = r._fan_mesh(false)
	mm.instance_count = _walk_data.size()
	for i in _walk_data.size():
		mm.set_instance_color(i, cols[i])
		mm.set_instance_custom_data(i, custom[i])
	_walkers = MultiMeshInstance3D.new()
	_walkers.multimesh = mm
	if _walk_mat == null:
		_walk_mat = ShaderMaterial.new()
		_walk_mat.shader = load("res://view/crowd.gdshader")
		_walk_mat.set_shader_parameter("hip", 0.25)
	_walk_mat.set_shader_parameter("scarf_color", club_cols[1])
	_walkers.material_override = _walk_mat
	add_child(_walkers)
	_update_walkers(0.0)


var _clock := 0.0
var _players: MultiMeshInstance3D
var _ball: MeshInstance3D
var _pl := []          # [pos Vector2, home(0/1) or ref(2), base Vector2 (formation spot)]
var _ball_p := Vector2.ZERO
var _ball_v := Vector2.ZERO
var _holder := -1
var _pitch := Rect2()
var _prng := RandomNumberGenerator.new()


## The match itself: two teams of eleven in a 4-4-2 shape, a referee and the
## ball. Players drift with their team's shape, the nearest chase the ball,
## and whoever has it dribbles, passes forward or shoots.
func _make_players(layout: Layout, club: ClubState) -> void:
	_pitch = Rect2(layout.pitch).grow(-0.8)
	_prng.seed = 5
	_pl.clear()
	var shape := [Vector2(0.05, 0.5), Vector2(0.22, 0.15), Vector2(0.2, 0.38), Vector2(0.2, 0.62), Vector2(0.22, 0.85),
		Vector2(0.4, 0.15), Vector2(0.38, 0.4), Vector2(0.38, 0.6), Vector2(0.4, 0.85), Vector2(0.48, 0.38), Vector2(0.48, 0.62)]
	for team in 2:
		for sp in shape:
			var u: float = sp.x if team == 0 else 1.0 - sp.x
			var base := Vector2(_pitch.position.x + u * _pitch.size.x, _pitch.position.y + sp.y * _pitch.size.y)
			_pl.append([base, team, base])
	_pl.append([_pitch.get_center() + Vector2(2, 2), 2, _pitch.get_center()])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = r._fan_mesh(false)
	mm.instance_count = _pl.size()
	var away := Color(0.95, 0.95, 0.95) if club.primary_color.get_luminance() < 0.6 else Color(0.1, 0.2, 0.55)
	for i in _pl.size():
		var team: int = _pl[i][1]
		var shirt: Color = club.primary_color if team == 0 else (away if team == 1 else Color(0.08, 0.08, 0.08))
		if i == 0 or i == 11:
			shirt = Color(0.2, 0.75, 0.3) if i == 0 else Color(0.95, 0.75, 0.1)   # keepers
		mm.set_instance_color(i, shirt)
		mm.set_instance_custom_data(i, Color(_prng.randf(), _prng.randf(), 0.0, 0.0))
	_players = MultiMeshInstance3D.new()
	_players.multimesh = mm
	_players.material_override = _walk_mat
	add_child(_players)
	_ball = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	_ball.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.97, 0.97, 0.97)
	_ball.material_override = bm
	add_child(_ball)
	_ball_p = _pitch.get_center()
	_holder = 9


func _update_match(dt: float) -> void:
	var mm := _players.multimesh
	var ballside := (_ball_p.x - _pitch.get_center().x) / (_pitch.size.x * 0.5)
	# the ball rolls and slows
	if _holder < 0:
		_ball_p += _ball_v * dt
		_ball_v *= pow(0.35, dt)
		if not _pitch.grow(0.6).has_point(_ball_p):
			_ball_p = _ball_p.clamp(_pitch.position, _pitch.end)
			_ball_v = -_ball_v * 0.3
	for i in _pl.size():
		var d: Array = _pl[i]
		var p: Vector2 = d[0]
		var team: int = d[1]
		var base: Vector2 = d[2]
		# the team's shape shifts with the ball
		var target := base + Vector2(ballside * _pitch.size.x * 0.18, (_ball_p.y - _pitch.get_center().y) * 0.35)
		if team == 2:
			target = _ball_p + Vector2(-2.5, 2.0)
		elif i == 0 or i == 11:
			target = Vector2(base.x, clampf(_ball_p.y, _pitch.get_center().y - 1.5, _pitch.get_center().y + 1.5))
		var to_ball := _ball_p - p
		if team < 2 and i != 0 and i != 11 and to_ball.length() < 5.0:
			target = _ball_p
		var speed := 2.4 if target == _ball_p else 1.4
		var step := (target - p).limit_length(speed * dt)
		p += step
		d[0] = p
		# whoever reaches the loose ball takes it
		if team < 2 and _holder < 0 and p.distance_to(_ball_p) < 0.25 and _ball_v.length() < 4.0:
			_holder = i
		var face := atan2(step.x, step.y) if step.length() > 0.001 else (PI / 2.0 if team == 0 else -PI / 2.0)
		var bob := absf(sin(_clock * 10.0 + i)) * 0.03 * minf(step.length() / maxf(dt, 0.001) / 2.0, 1.0)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, face).scaled(Vector3(1.15, 1.15, 1.15)), Vector3(p.x, 0.04 + bob, p.y)))
	if _holder >= 0:
		var h: Array = _pl[_holder]
		var hp: Vector2 = h[0]
		var goal_x := _pitch.end.x if int(h[1]) == 0 else _pitch.position.x
		var dir := Vector2(signf(goal_x - hp.x), 0.0)
		h[0] = hp + dir * 1.6 * dt
		_ball_p = (h[0] as Vector2) + dir * 0.25
		if _prng.randf() < dt * 0.9:
			var near_goal := absf(goal_x - hp.x) < 7.0
			if near_goal:
				_ball_v = (Vector2(goal_x, _pitch.get_center().y + _prng.randf_range(-1.2, 1.2)) - hp).normalized() * 12.0
			else:
				var mate := _prng.randi_range(0, 10) + (0 if int(h[1]) == 0 else 11)
				_ball_v = ((_pl[mate][0] as Vector2) - hp + dir * 2.0) * 1.1
			_holder = -1
			_ball_p += _ball_v.normalized() * 0.4
	if _ball_p.x <= _pitch.position.x + 0.05 or _ball_p.x >= _pitch.end.x - 0.05:
		_ball_p = _pitch.get_center()
		_ball_v = Vector2.ZERO
		_holder = 9 if _prng.randf() < 0.5 else 20
	_ball.position = Vector3(_ball_p.x, 0.1, _ball_p.y)


func _process(delta: float) -> void:
	if _walkers and is_instance_valid(_walkers):
		_clock += delta
		_update_walkers(_clock)
	if _players and is_instance_valid(_players):
		_update_match(minf(delta, 0.1))


## Ping-pong each walker between its two points, facing the way it goes,
## with a little step bob.
func _update_walkers(t: float) -> void:
	var mm := _walkers.multimesh
	for i in _walk_data.size():
		var d: Array = _walk_data[i]
		var a: Vector2 = d[0]
		var b: Vector2 = d[1]
		var length := a.distance_to(b)
		var p := a
		var facing := 0.0
		var bob := 0.0
		if length > 0.01:
			var cycle := 2.0 * length / float(d[2])
			var u := fposmod(t + float(d[3]), cycle) / cycle
			var going := u < 0.5
			var k := u * 2.0 if going else (1.0 - u) * 2.0
			p = a.lerp(b, k)
			var dir := (b - a) if going else (a - b)
			facing = atan2(dir.x, dir.y)
			bob = absf(sin((t + float(d[3])) * 9.0)) * 0.02
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, facing), Vector3(p.x, bob, p.y)))


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
	var sm := QuadMesh.new()
	sm.size = Vector2(0.7, 0.7)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/kenney/particle-pack/smoke_04.png")
	m.albedo_color = Color(smoke.lightened(0.2), 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	sm.material = m
	p.mesh = sm
	p.angle_min = 0.0
	p.angle_max = 360.0
	# the flame itself: a bright sprite
	var fire := Sprite3D.new()
	fire.texture = load("res://assets/kenney/particle-pack/fire_01.png")
	fire.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fire.pixel_size = 0.0012
	fire.modulate = Color(1.0, 0.45, 0.2)
	fire.shaded = false
	fire.position = Vector3(0, 0.12, 0)
	g.add_child(fire)
	g.add_child(p)
