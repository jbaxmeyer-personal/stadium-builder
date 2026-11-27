extends Node3D
## The crowd's own show, built from a match report:
##   flags   - waving in each stand, more the louder the stand
##   banners - hung along the front of every stand, in club colours
##   tifo    - (renderer.build_crowd) a card display on the home end for big, loud matches
##   flares  - red flares and club-coloured smoke on terraces when the atmosphere is high
## Flags and banners stay after the match; flares only burn during the matchday moment.

const StadiumRenderer := preload("res://view/stadium_renderer.gd")
const ULTRA_SLOGANS := ["CURVA %s", "ULTRAS %s", "ULTRAS", "%s 1887", "NO SURRENDER", "SEMPRE %s", "%s ULTRAS"]
## How each football culture shows up in the stands:
##   flags (amount), big (share of huge swinging flags), flares (min atmosphere, -1 none),
##   giant (a huge flag passed over the crowd), streamers (paper rolls)
const CULTURES := {
	"british": { "flags": 0.6, "big": 0.0, "flares": -1.0, "giant": false, "streamers": false, "ultra": false },
	"ultras": { "flags": 1.0, "big": 0.08, "flares": 0.3, "giant": true, "streamers": false, "ultra": true },
	"latin": { "flags": 1.4, "big": 0.05, "flares": 0.4, "giant": true, "streamers": true, "ultra": false },
	"german": { "flags": 1.2, "big": 0.18, "flares": -1.0, "giant": false, "streamers": false, "ultra": false },
	"asian": { "flags": 0.8, "big": 0.0, "flares": -1.0, "giant": false, "streamers": false, "ultra": false },
}
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
	var cult: Dictionary = CULTURES.get(layout.crowd_culture, CULTURES["british"])
	var giant_done := false
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
				var pool: Array = ULTRA_SLOGANS if bool(cult["ultra"]) else SLOGANS
				var text: String = pool[rng.randi_range(0, pool.size() - 1)]
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
		var count := int(st["attendance"] / 90.0 * t.noise * (0.3 + a) * float(cult["flags"]))
		if live and i == r.tifo_stand(layout, config, report):
			count = 0  # hands are busy holding up the tifo cards
		var tiles := s.lower_tiles(layout.pitch)
		for k in mini(count, 400):
			var tile: Vector2i = tiles[rng.randi_range(0, tiles.size() - 1)]
			var v := _row_of(s, tile, layout.pitch)
			var p := Vector2(tile) + Vector2(rng.randf(), rng.randf())
			var y := StadiumRenderer.row_height(v, s) + 0.75
			var basis := Basis(Vector3.UP, face + rng.randf_range(-0.4, 0.4))
			if rng.randf() < float(cult["big"]):
				basis = basis.scaled(Vector3(3.2, 2.6, 1.0))   # a big swinging flag on a long pole
				y += 0.5
			flag_tf.append(Transform3D(basis, Vector3(p.x, y, p.y)))
			var pick := rng.randf()
			flag_col.append(club.primary_color if pick < 0.6 else (club.secondary_color if pick < 0.9 else Color.from_hsv(rng.randf(), 0.6, 0.8)))
			flag_phase.append(Color(rng.randf(), 0, 0, 0))
		# flares and smoke on loud terraces, during the match only
		var flare_at := float(cult["flares"])
		if live and flare_at >= 0.0 and a >= flare_at and s.type_id in ["terrace", "safe_standing", "bank"] and st["attendance"] > 0:
			var flares := clampi(int((a - flare_at + 0.1) * 10.0 * s.length / 10.0), 1, 10)
			for k in flares:
				var tile: Vector2i = tiles[rng.randi_range(0, tiles.size() - 1)]
				var v := _row_of(s, tile, layout.pitch)
				var pc := club.primary_color if k % 2 == 0 else club.secondary_color
				if layout.pyro_color != "" and Color.html_is_valid(layout.pyro_color):
					pc = Color.html(layout.pyro_color)
				_flare(Vector3(tile.x + 0.5, StadiumRenderer.row_height(v, s) + 0.6, tile.y + 0.5), pc, rng)
		# the capo on his platform at the front, back to the pitch, with the drums
		if live and s.type_id in ["terrace", "safe_standing"] and not s.is_corner() and (bool(cult["ultra"]) or float(cult["flags"]) >= 1.2) and st["attendance"] > 500:
			var front := s.row_tiles(layout.pitch, 0)
			if not front.is_empty():
				var mid: Vector2i = front[front.size() / 2]
				var cp := Vector2(mid) + Vector2(0.5, 0.5) + tp * 0.35
				var plat := Node3D.new()
				plat.position = Vector3(cp.x, 0.0, cp.y)
				plat.rotation.y = face + PI
				add_child(plat)
				r.lbox(plat, Vector3(0, 0.45, 0), Vector3(0.6, 0.06, 0.5), r.mat(Color(0.3, 0.3, 0.32), 0.5, 0.6))
				for e in [-0.25, 0.25]:
					r.lbox(plat, Vector3(e, 0.22, 0), Vector3(0.04, 0.45, 0.04), r.mat(Color(0.3, 0.3, 0.32), 0.5, 0.6))
				r.lbox(plat, Vector3(0, 0.75, 0), Vector3(0.18, 0.5, 0.12), r.mat(club.primary_color.darkened(0.3), 0.8))
				r.lbox(plat, Vector3(0, 1.08, 0), Vector3(0.12, 0.12, 0.12), r.mat(Color(0.8, 0.62, 0.5), 0.8))
				r.lbox(plat, Vector3(0.12, 1.05, 0.08), Vector3(0.08, 0.08, 0.16), r.mat(Color(0.9, 0.9, 0.9), 0.5))   # megaphone
				# drums a row behind
				for k in 3:
					var dp := cp + tp * -1.2 + Vector2(-tp.y, tp.x) * (k - 1) * 0.6
					var drum := MeshInstance3D.new()
					var cm := CylinderMesh.new()
					cm.top_radius = 0.16
					cm.bottom_radius = 0.16
					cm.height = 0.22
					drum.mesh = cm
					drum.material_override = r.mat(club.secondary_color if k % 2 == 0 else club.primary_color, 0.5)
					drum.position = Vector3(dp.x, StadiumRenderer.row_height(1, s) + 0.75, dp.y)
					drum.rotation.x = PI / 2.0
					add_child(drum)
		# the giant flag passed over the loudest end, and paper streamers
		if live and not s.is_corner() and st["attendance"] > 0 and s.type_id != "premium" and s.depth >= 3:
			var disp := s.extra("display")
			var mode := String(disp["giant"])
			var auto_flag := mode == "auto" and bool(cult["giant"]) and not giant_done and float(st["fill"]) > 0.5
			if (mode == "on" or auto_flag) and i != r.tifo_stand(layout, config, report):
				giant_done = true
				_giant_flag(s, layout.pitch, club, String(disp["flag"]), float(disp["spread"]))
			if bool(cult["streamers"]):
				_streamers(s, layout.pitch, rng)
	_add_flags(flag_tf, flag_col, flag_phase)
	if live and report.evening:
		_phone_lights(layout, config, report, rng)
	_people_outside(layout, config, rng, 60 if live else 14, clampi(report.attendance / 60, 20, 260) if live else 0)
	if live:
		_queues(layout, config, report, rng, club)
		if report.attendance > 3000:
			_police(layout, config, rng)
		_sellers(layout, config, rng, club)
		_warmup(layout)
	if live and report.attendance > 0:
		_stewards(layout, report.attendance)
	if live:
		_make_players(layout, club)
		_start_walkout(layout, config)


var _walkers: MultiMeshInstance3D
var _walk_data := []     # [start, end, speed, phase]
var _walk_mat: ShaderMaterial


## Supporters outside the ground, using the same fan model as the stands:
## most walk to and fro along the streets toward the ground, some stand about.
func _people_outside(layout: Layout, config: SimConfig, rng: RandomNumberGenerator, count: int, arriving := 0) -> void:
	var blocked := layout.stand_tile_map()
	var pl := Rect2(layout.plot)
	_walk_data.clear()
	var cols: Array[Color] = []
	var custom: Array[Color] = []
	var club_cols := [r._club.primary_color, r._club.secondary_color] if r._club else [Color.RED, Color.WHITE]
	# matchday: streams of fans from the car parks and bus stops to the stands,
	# along the paths where there are paths
	var links: Array[Rect2] = []
	for f in layout.facilities:
		var ft := config.facility_type(f.type_id)
		if ft.layer == "outside" and ft.capacity > 0.0:
			links.append(Rect2(Vector2(f.pos), Vector2(f.size(ft))))
	var stand_edges: Array[Vector2] = []
	for st in layout.stands:
		var foot := StadiumRenderer.tiles_xz(st.tiles(layout.pitch))
		var tp := StadiumRenderer.to_pitch(st.side)
		stand_edges.append(foot.get_center() - tp * (foot.size.y if tp.x == 0.0 else foot.size.x) / 2.0 - tp * 0.6)
	# the cheapest walk to the stands (paving is quicker than grass), so fans
	# coming from transport follow the player's paths
	var field: Dictionary = layout._walk_from_stands(config) if not links.is_empty() else {}
	if not links.is_empty() and not field.is_empty():
		for i in arriving:
			var src: Rect2 = links[rng.randi_range(0, links.size() - 1)]
			var start := Vector2i(src.position + Vector2(rng.randf(), rng.randf()) * src.size)
			# step off the building onto the nearest walkable tile
			var cur := start
			var best_d := INF
			for dy in range(-int(src.size.y) - 1, int(src.size.y) + 2):
				for dx in range(-int(src.size.x) - 1, int(src.size.x) + 2):
					var t := start + Vector2i(dx, dy)
					if field.has(t) and float(field[t]) + Vector2(dx, dy).length() * 0.3 < best_d:
						best_d = float(field[t]) + Vector2(dx, dy).length() * 0.3
						cur = t
			if not field.has(cur):
				continue
			var path: Array = [Vector2(start) + Vector2(0.5, 0.5)]
			var guard := 0
			while float(field[cur]) > 0.0 and guard < 200:
				guard += 1
				var nxt := cur
				for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
					var n: Vector2i = cur + d
					if field.has(n) and float(field[n]) < float(field[nxt]):
						nxt = n
				if nxt == cur:
					break
				path.append(Vector2(cur) + Vector2(0.5, 0.5) + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)))
				cur = nxt
			path.append(Vector2(cur) + Vector2(0.5, 0.5))
			_walk_data.append([path[0], path[-1], rng.randf_range(0.7, 1.0), rng.randf() * 60.0, path])
			cols.append(club_cols[0] if rng.randf() < 0.65 else (club_cols[1] if rng.randf() < 0.5 else Color.from_hsv(rng.randf(), 0.4, rng.randf_range(0.2, 0.7))))
			custom.append(Color(rng.randf(), 0.0, rng.randf(), 0.5 if rng.randf() < 0.5 else 0.0))
	elif not links.is_empty() and not stand_edges.is_empty():
		for i in arriving:
			var src: Rect2 = links[rng.randi_range(0, links.size() - 1)]
			var a := src.position + Vector2(rng.randf(), rng.randf()) * src.size
			var best := stand_edges[0]
			for e in stand_edges:
				if e.distance_to(a) < best.distance_to(a):
					best = e
			var b := best + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
			_walk_data.append([a, b, rng.randf_range(0.5, 0.8), rng.randf() * 30.0])
			cols.append(club_cols[0] if rng.randf() < 0.65 else (club_cols[1] if rng.randf() < 0.5 else Color.from_hsv(rng.randf(), 0.4, rng.randf_range(0.2, 0.7))))
			custom.append(Color(rng.randf(), 0.0, rng.randf(), 0.5 if rng.randf() < 0.5 else 0.0))
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


## Half-time queues on the concourse: a line of fans at each kiosk, bar and
## toilet, as long as the wait the sim worked out (capped so it stays tidy).
func _queues(layout: Layout, config: SimConfig, report: MatchdayReport, rng: RandomNumberGenerator, club: ClubState) -> void:
	var by_label := {}
	for q in report.facilities:
		by_label[String(q.get("label", ""))] = q
	var conc := layout.concourse_tile_map(config)
	var tf: Array[Transform3D] = []
	var cols: Array[Color] = []
	var custom: Array[Color] = []
	for f in layout.facilities:
		if not by_label.has(f.label()):
			continue
		var q: Dictionary = by_label[f.label()]
		var n := clampi(int(float(q.get("wait_max_min", 0.0)) * 1.2), 0, 14)
		if n == 0:
			continue
		var ft := config.facility_type(f.type_id)
		var sz := f.size(ft)
		var y := StadiumRenderer.level_height(layout, f.level) if f.level > 0 else 0.05
		# queue out along the concourse, away from the stand
		var dir := Vector2(1, 0)
		if conc.has(f.pos):
			var st: Stand = layout.stands[conc[f.pos]]
			var tp := StadiumRenderer.to_pitch(st.side)
			dir = Vector2(-tp.y, tp.x) if not st.is_corner() else -tp.normalized()
		var start := Vector2(f.pos) + Vector2(sz) / 2.0 + dir * (maxf(sz.x, sz.y) / 2.0 + 0.3)
		for k in n:
			var p := start + dir * (k * 0.32) + Vector2(-dir.y, dir.x) * (0.06 * sin(k * 1.7))
			tf.append(Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(p.x, y, p.y)))
			cols.append(club.primary_color if rng.randf() < 0.6 else (club.secondary_color if rng.randf() < 0.5 else Color.from_hsv(rng.randf(), 0.4, rng.randf_range(0.2, 0.7))))
			custom.append(Color(rng.randf(), 0.0, rng.randf(), 0.5 if rng.randf() < 0.4 else 0.0))
	if tf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = r._fan_mesh(false)
	mm.instance_count = tf.size()
	for i in tf.size():
		mm.set_instance_transform(i, tf[i])
		mm.set_instance_color(i, cols[i])
		mm.set_instance_custom_data(i, custom[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	if _walk_mat == null:
		_walk_mat = ShaderMaterial.new()
		_walk_mat.shader = load("res://view/crowd.gdshader")
		_walk_mat.set_shader_parameter("hip", 0.25)
	mi.material_override = _walk_mat
	add_child(mi)


## The substitutes warming up in bibs along the touchline by the corner flag.
func _warmup(layout: Layout) -> void:
	var pr := Rect2(layout.pitch)
	var tf: Array[Transform3D] = []
	var cols: Array[Color] = []
	var custom: Array[Color] = []
	for k in 4:
		var p := Vector2(pr.position.x + 2.0 + k * 0.7, pr.end.y + 0.6 + (k % 2) * 0.3)
		tf.append(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(p.x, 0.02, p.y)))
		cols.append(Color(1.0, 0.45, 0.1))
		custom.append(Color(float(k) / 4.0, 1.0, 0.2, 0.0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = r._fan_mesh(false)
	mm.instance_count = tf.size()
	for i in tf.size():
		mm.set_instance_transform(i, tf[i])
		mm.set_instance_color(i, cols[i])
		mm.set_instance_custom_data(i, custom[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _walk_mat
	add_child(mi)


## Programme sellers and scarf stalls outside the stands: a little booth or a
## seller with a bag, and a rack of half-and-half scarves.
func _sellers(layout: Layout, config: SimConfig, rng: RandomNumberGenerator, club: ClubState) -> void:
	var blocked := layout.solid_tiles(config)
	for s in layout.stands:
		if s.is_corner():
			continue
		var foot := StadiumRenderer.tiles_xz(s.tiles(layout.pitch))
		var tp := StadiumRenderer.to_pitch(s.side)
		var along := Vector2(-tp.y, tp.x)
		var p := foot.get_center() - tp * ((foot.size.y if tp.x == 0.0 else foot.size.x) / 2.0 + 1.6) + along * rng.randf_range(-3.0, 3.0)
		var t := Vector2i(floori(p.x), floori(p.y))
		if blocked.has(t) or not layout.plot.has_point(t):
			continue
		var st := Node3D.new()
		st.position = Vector3(p.x, 0, p.y)
		st.rotation.y = atan2(-tp.x, -tp.y)
		add_child(st)
		# the stall: a trestle and a rack of scarves in the club's colours
		r.lbox(st, Vector3(0, 0.3, 0), Vector3(0.9, 0.04, 0.4), r.mat(Color(0.55, 0.4, 0.25), 0.8))
		for e in [-0.4, 0.4]:
			r.lbox(st, Vector3(e, 0.15, 0), Vector3(0.04, 0.3, 0.35), r.mat(Color(0.3, 0.3, 0.32), 0.5))
		r.lbox(st, Vector3(0, 0.6, -0.15), Vector3(0.9, 0.03, 0.03), r.mat(Color(0.3, 0.3, 0.32), 0.5))
		for k in 6:
			r.lbox(st, Vector3(-0.38 + k * 0.15, 0.46, -0.15), Vector3(0.07, 0.28, 0.02), r.mat(club.primary_color if k % 2 == 0 else club.secondary_color, 0.8))


## Big games: police vans parked behind the away end, and a few mounted officers.
func _police(layout: Layout, config: SimConfig, rng: RandomNumberGenerator) -> void:
	var ai := r._away_stand(layout, config)
	if ai < 0:
		return
	var s := layout.stands[ai]
	var foot := StadiumRenderer.tiles_xz(s.tiles(layout.pitch))
	var tp := StadiumRenderer.to_pitch(s.side)
	var along := Vector2(-tp.y, tp.x)
	var back := foot.get_center() - tp * ((foot.size.y if tp.x == 0.0 else foot.size.x) / 2.0 + 3.0)
	var blocked := layout.solid_tiles(config)
	var yellow := r.mat(Color(0.95, 0.85, 0.1), 0.5)
	var blue := r.mat(Color(0.1, 0.2, 0.6), 0.5)
	var white := r.mat(Color(0.95, 0.95, 0.95), 0.5)
	for k in 3:
		var p := back + along * (k - 1) * 2.2
		if blocked.has(Vector2i(floori(p.x), floori(p.y))) or not layout.plot.has_point(Vector2i(floori(p.x), floori(p.y))):
			continue
		var van := Node3D.new()
		van.position = Vector3(p.x, 0, p.y)
		van.rotation.y = atan2(along.x, along.y)
		add_child(van)
		r.lbox(van, Vector3(0, 0.45, 0), Vector3(0.75, 0.7, 1.7), white)
		# battenberg checks along the side
		for i in 6:
			r.lbox(van, Vector3(0.38, 0.35, -0.7 + i * 0.28), Vector3(0.02, 0.16, 0.26), yellow if i % 2 == 0 else blue)
		r.lbox(van, Vector3(0, 0.83, 0.3), Vector3(0.3, 0.06, 0.1), r.mat(Color(0.2, 0.4, 1.0), 0.3, 0.0, 2.0))
	# two mounted officers
	for k in 2:
		var hp := back + along * (k * 2.0 - 1.0) * 4.0 + tp * 1.0
		var horse := Node3D.new()
		horse.position = Vector3(hp.x, 0, hp.y)
		horse.rotation.y = atan2(tp.x, tp.y) + rng.randf_range(-0.4, 0.4)
		add_child(horse)
		var hm := r.mat(Color(0.3, 0.2, 0.12), 0.7)
		r.lbox(horse, Vector3(0, 0.5, 0), Vector3(0.25, 0.25, 0.8), hm)
		r.lbox(horse, Vector3(0, 0.68, 0.45), Vector3(0.15, 0.3, 0.2), hm)
		for lx in [-0.08, 0.08]:
			for lz in [-0.3, 0.3]:
				r.lbox(horse, Vector3(lx, 0.2, lz), Vector3(0.06, 0.4, 0.06), hm)
		r.lbox(horse, Vector3(0, 0.82, -0.05), Vector3(0.18, 0.35, 0.16), yellow)
		r.lbox(horse, Vector3(0, 1.05, -0.05), Vector3(0.12, 0.12, 0.12), r.mat(Color(0.1, 0.1, 0.12), 0.5))


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


var _walkout := 99.0
var _tunnel := Vector2.ZERO
var _mascot: MultiMeshInstance3D
var _mascot_p := Vector2.ZERO


## The teams come out of the tunnel side by side, line up on halfway facing
## the main stand, then break to their positions.
func _start_walkout(layout: Layout, config: SimConfig) -> void:
	var ms := r._main_stand(layout, config)
	var c := Vector2(layout.pitch.get_center())
	if ms < 0:
		_walkout = 99.0
		return
	var tp := StadiumRenderer.to_pitch(layout.stands[ms].side)
	var half := Vector2(layout.pitch.size) / 2.0
	_tunnel = c - tp * (absf(tp.x) * half.x + absf(tp.y) * half.y + 0.8)
	_walkout = 0.0
	# the club mascot: a big furry figure in club colours who leads the teams out
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = r._fan_mesh(false)
	mm.instance_count = 1
	mm.set_instance_color(0, r._club.primary_color if r._club else Color.RED)
	mm.set_instance_custom_data(0, Color(0.3, 1.0, 0.1, 0.5))
	_mascot = MultiMeshInstance3D.new()
	_mascot.multimesh = mm
	_mascot.material_override = _walk_mat
	add_child(_mascot)
	_mascot_p = _tunnel + (c - _tunnel).normalized() * 1.0
	for i in _pl.size():
		_pl[i][0] = _tunnel + Vector2(-tp.y, tp.x) * (0.25 if _pl[i][1] == 0 else -0.25) - tp * (i % 11) * 0.3


func _update_walkout(dt: float) -> void:
	_walkout += dt
	var mm := _players.multimesh
	var c := _pitch.get_center()
	var tp := (c - _tunnel).normalized()
	var along := Vector2(-tp.y, tp.x)
	for i in _pl.size():
		var d: Array = _pl[i]
		var p: Vector2 = d[0]
		var team: int = d[1]
		# line up along halfway: home on one side of the referee, away on the other
		var slot := (i % 11) + 1
		var target := c - tp * 1.5 + along * (0.0 if team == 2 else (-1.0 if team == 0 else 1.0) * (0.4 + slot * 0.42))
		if _walkout > 4.2:
			target = d[2]
		var step := (target - p).limit_length(1.5 * dt)
		p += step
		d[0] = p
		var face := atan2(step.x, step.y) if step.length() > 0.002 else atan2(-tp.x, -tp.y)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, face).scaled(Vector3(1.15, 1.15, 1.15)), Vector3(p.x, 0.04, p.y)))
	_ball.position = Vector3(c.x, 0.08, c.y)
	_ball_p = c
	if _mascot and is_instance_valid(_mascot):
		# out in front of the teams, a wave at the crowd, then back off
		var mt := c - tp * 3.0 if _walkout < 4.0 else _tunnel
		var ms := (mt - _mascot_p).limit_length(1.6 * dt)
		_mascot_p += ms
		var wave := Basis(Vector3.UP, atan2(ms.x, ms.y) if ms.length() > 0.002 else atan2(-tp.x, -tp.y))
		_mascot.multimesh.set_instance_transform(0, Transform3D(wave.scaled(Vector3(1.7, 1.7, 1.7)), Vector3(_mascot_p.x, 0.04 + absf(sin(_walkout * 6.0)) * 0.06, _mascot_p.y)))
		_mascot.visible = _walkout < 6.8


func _update_match(dt: float) -> void:
	if _walkout < 7.0:
		_update_walkout(dt)
		return
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
		if d.size() > 4 and (d[4] as Array).size() > 1:
			var pts: Array = d[4]
			var total := 0.0
			for k in range(1, pts.size()):
				total += (pts[k] as Vector2).distance_to(pts[k - 1])
			var s := fposmod((t + float(d[3])) * float(d[2]), total + 2.0)
			var pos2: Vector2 = pts[-1]
			var dir2 := Vector2.DOWN
			for k in range(1, pts.size()):
				var seg := (pts[k] as Vector2).distance_to(pts[k - 1])
				if s <= seg:
					pos2 = (pts[k - 1] as Vector2).lerp(pts[k], s / maxf(seg, 0.001))
					dir2 = (pts[k] as Vector2) - (pts[k - 1] as Vector2)
					break
				s -= seg
			var bob2 := absf(sin((t + float(d[3])) * 9.0)) * 0.02
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, atan2(dir2.x, dir2.y)), Vector3(pos2.x, bob2, pos2.y)))
			continue
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


## Evening games: a scatter of phone torches held up in the stands, twinkling.
func _phone_lights(layout: Layout, config: SimConfig, report: MatchdayReport, rng: RandomNumberGenerator) -> void:
	var tf: Array[Transform3D] = []
	for i in layout.stands.size():
		if i >= report.stands.size():
			continue
		var s := layout.stands[i]
		var st: Dictionary = report.stands[i]
		var n := mini(int(float(st["attendance"]) / 140.0), 120)
		var tiles := s.lower_tiles(layout.pitch)
		if tiles.is_empty():
			continue
		for k in n:
			var t: Vector2i = tiles[rng.randi_range(0, tiles.size() - 1)]
			var v := _row_of(s, t, layout.pitch)
			tf.append(Transform3D(Basis().scaled(Vector3(0.05, 0.05, 0.05)), Vector3(t.x + rng.randf(), StadiumRenderer.row_height(v, s) + 0.95, t.y + rng.randf())))
	if tf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = SphereMesh.new()
	mm.instance_count = tf.size()
	for i in tf.size():
		mm.set_instance_transform(i, tf[i])
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 1.0, 0.95)
	m.emission_enabled = true
	m.emission = Color(1.0, 1.0, 0.95)
	m.emission_energy_multiplier = 3.0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


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


## Stewards in hi-vis along the touchlines on matchday, facing the crowd:
## one for every few hundred fans, spaced round the pitch.
func _stewards(layout: Layout, crowd: int) -> void:
	var p := Rect2(layout.pitch).grow(-0.25)
	var n := clampi(crowd / 400, 4, 60)
	var perim := 2.0 * (p.size.x + p.size.y)
	var xf: Array[Transform3D] = []
	for i in n:
		var d := (i + 0.5) * perim / n
		var pos: Vector2
		var face := 0.0
		if d < p.size.x:
			pos = Vector2(p.position.x + d, p.position.y)
			face = PI
		elif d < p.size.x + p.size.y:
			pos = Vector2(p.end.x, p.position.y + d - p.size.x)
			face = PI / 2.0
		elif d < 2.0 * p.size.x + p.size.y:
			pos = Vector2(p.end.x - (d - p.size.x - p.size.y), p.end.y)
			face = 0.0
		else:
			pos = Vector2(p.position.x, p.end.y - (d - 2.0 * p.size.x - p.size.y))
			face = -PI / 2.0
		# keep the goalmouths and the halfway line clear
		if absf(pos.y - p.get_center().y) < 2.5 and (absf(pos.x - p.position.x) < 0.5 or absf(pos.x - p.end.x) < 0.5):
			continue
		xf.append(Transform3D(Basis(Vector3.UP, face), Vector3(pos.x, 0.0, pos.y)))
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = r._fan_mesh(false)
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, Color(0.85, 1.0, 0.15))   # hi-vis yellow
		mm.set_instance_custom_data(i, Color(float(i) * 0.37, 0.0, 0.0, 0.0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _walk_mat
	add_child(mi)


## A huge flag in club stripes rolled out over the crowd on the front rows.
func _giant_flag(s: Stand, pitch: Rect2i, club: ClubState, pattern := "stripes", size := 0.6) -> void:
	var tp := StadiumRenderer.to_pitch(s.side)
	var foot := StadiumRenderer.tiles_xz(s.lower_tiles(pitch))
	var L := foot.size.x if tp.x == 0.0 else foot.size.y
	var D := foot.size.y if tp.x == 0.0 else foot.size.x
	var f := Node3D.new()
	f.position = Vector3(foot.get_center().x, 0, foot.get_center().y)
	f.rotation.y = atan2(tp.x, tp.y)
	add_child(f)
	# the bigger the flag, the more rows it covers (a whole-stand flag covers them all)
	var rows := mini(s.depth - 1, maxi(3, roundi((s.depth - 1) * clampf(size, 0.2, 1.0))))
	var y0 := StadiumRenderer.row_height(0, s) + 1.0
	var y1 := StadiumRenderer.row_height(rows, s) + 1.0
	var run := float(rows)
	var m := StandardMaterial3D.new()
	if pattern == "stripes":
		var img := Image.create(8, 2, false, Image.FORMAT_RGB8)
		for x in 8:
			for yy in 2:
				img.set_pixel(x, yy, club.primary_color if x % 2 == 0 else club.secondary_color)
		m.albedo_texture = ImageTexture.create_from_image(img)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	else:
		m.albedo_texture = r._banner_tex(pattern if pattern != "crest" else "plain", club.primary_color, club.secondary_color)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	var q := QuadMesh.new()
	var fw := L * clampf(size, 0.2, 1.0) * 0.98
	q.size = Vector2(fw, sqrt(run * run + (y1 - y0) * (y1 - y0)))
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position = Vector3(0, (y0 + y1) / 2.0, D / 2.0 - 0.5 - run / 2.0)
	mi.rotation.x = -PI / 2.0 + atan2(y1 - y0, run)
	f.add_child(mi)
	if pattern == "crest":
		var crest := Node3D.new()
		mi.add_child(crest)
		r._crest(crest, Vector3(0, 0, 0.05), minf(fw, q.size.y) * 0.7, 0.0, false, "flat", "none")


## Paper streamers thrown from the front: ribbons hanging over the wall and
## a white litter of paper on the grass in front.
func _streamers(s: Stand, pitch: Rect2i, rng: RandomNumberGenerator) -> void:
	var tp := StadiumRenderer.to_pitch(s.side)
	var front := s.row_tiles(pitch, 0)
	var ribbons: Array[Transform3D] = []
	var bits: Array[Transform3D] = []
	for t in front:
		for k in 2:
			# hanging over the front wall from the parapet
			var p := Vector2(t) + Vector2(0.5, 0.5) + tp * 0.53 + Vector2(-tp.y, tp.x) * rng.randf_range(-0.45, 0.45)
			var len := rng.randf_range(0.25, s.plinth + 0.15)
			var face := atan2(tp.x, tp.y)
			ribbons.append(Transform3D(Basis(Vector3.UP, face).scaled(Vector3(0.08, len, 0.008)), Vector3(p.x, s.plinth + 0.25 - len / 2.0, p.y)))
		for k in 3:
			var g := Vector2(t) + Vector2(rng.randf(), rng.randf()) + tp * rng.randf_range(0.8, 2.0)
			bits.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.12, 0.01, 0.05)), Vector3(g.x, 0.03, g.y)))
	var white := r.mat(Color(0.96, 0.96, 0.94), 0.9)
	for set in [ribbons, bits]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = BoxMesh.new()
		mm.instance_count = set.size()
		for i in set.size():
			mm.set_instance_transform(i, set[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = white
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## A burning flare: a bright red light and a column of coloured smoke.
func _flare(pos: Vector3, smoke: Color, rng: RandomNumberGenerator) -> void:
	var g := Node3D.new()
	g.position = pos
	add_child(g)
	var glow_c := Color(1.0, 0.25, 0.1).lerp(smoke, 0.5) if smoke.get_luminance() < 0.9 else Color(1.0, 0.25, 0.1)
	r.box(g, Vector3(-0.05, -0.05, -0.05), Vector3(0.05, 0.05, 0.05), r.mat(glow_c, 0.3, 0.0, 6.0), false)
	var light := OmniLight3D.new()
	light.light_color = glow_c
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
