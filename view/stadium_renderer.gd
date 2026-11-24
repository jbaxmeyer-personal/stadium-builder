extends Node3D
## Builds the 3D stadium from sim state. Read-only on the sim.
## World units: 1 unit = 1 tile. Tile (x, y) covers [x, x+1] x [y, y+1] in X/Z.

const ROW_BASE := 0.35        # height of the front row
const ROW_RISE := 0.45        # extra height per row back
const ROOF_CLEARANCE := 2.3
const FIGURES_PER_PLACES := 5.0

const C_CONCRETE := Color(0.66, 0.66, 0.64)
const C_CONCRETE_DARK := Color(0.45, 0.45, 0.44)
const C_PAVING := Color(0.52, 0.51, 0.49)
const C_PLOT := Color(0.30, 0.31, 0.30)
const C_GRASS_OUT := Color(0.16, 0.27, 0.13)
const C_PITCH_A := Color(0.20, 0.47, 0.18)
const C_PITCH_B := Color(0.25, 0.55, 0.22)
const C_ROOF := Color(0.58, 0.60, 0.64)
const C_CLUB := Color(0.75, 0.08, 0.10)
const C_CLUB_2 := Color(0.97, 0.97, 0.97)
const C_SEAT := { "terrace": Color(0.55, 0.55, 0.56), "seated": Color(0.70, 0.07, 0.09), "premium": Color(0.10, 0.14, 0.32) }

var _mats := {}
var _static: Node3D
var _stands: Node3D
var _overlay: Node3D
var _crowd: MultiMeshInstance3D
var _crowd_mat: ShaderMaterial
var _roofs: Array[Node3D] = []
var show_roofs := true:
	set(v):
		show_roofs = v
		for r in _roofs:
			r.visible = v


func _ready() -> void:
	_static = Node3D.new()
	add_child(_static)
	_stands = Node3D.new()
	add_child(_stands)
	_overlay = Node3D.new()
	add_child(_overlay)
	_crowd = MultiMeshInstance3D.new()
	add_child(_crowd)
	_crowd_mat = ShaderMaterial.new()
	_crowd_mat.shader = load("res://view/crowd.gdshader")


# --- helpers -----------------------------------------------------------------

func mat(color: Color, rough := 0.85, metal := 0.0, emission := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s" % [color.to_html(), rough, metal, emission, alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.roughness = rough
	m.metallic = metal
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


## Axis-aligned box from min corner to max corner.
func box(parent: Node3D, from: Vector3, to: Vector3, m: Material, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = (to - from).abs()
	mi.mesh = bm
	mi.material_override = m
	mi.position = (from + to) / 2.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Tile-rect (min tile, max tile inclusive) -> world XZ min/max.
static func tiles_xz(tiles: Array[Vector2i]) -> Rect2:
	var lo := tiles[0]
	var hi := tiles[0]
	for t in tiles:
		lo = Vector2i(mini(lo.x, t.x), mini(lo.y, t.y))
		hi = Vector2i(maxi(hi.x, t.x), maxi(hi.y, t.y))
	return Rect2(Vector2(lo), Vector2(hi - lo + Vector2i.ONE))


static func row_height(v: int) -> float:
	return ROW_BASE + v * ROW_RISE


static func stand_height(s: Stand) -> float:
	return row_height(s.depth - 1) + ROOF_CLEARANCE + 0.6


## Unit vector pointing from the stand toward the pitch, in XZ.
static func to_pitch(side: String) -> Vector2:
	return { "N": Vector2(0, 1), "S": Vector2(0, -1), "W": Vector2(1, 0), "E": Vector2(-1, 0) }[side]


## The world AABB of a stand (for mouse picking).
static func stand_aabb(s: Stand, pitch: Rect2i) -> AABB:
	var r := tiles_xz(s.tiles(pitch))
	return AABB(Vector3(r.position.x, 0, r.position.y), Vector3(r.size.x, row_height(s.depth - 1), r.size.y))


# --- static scenery ------------------------------------------------------------

func build_static(layout: Layout) -> void:
	for c in _static.get_children():
		c.queue_free()
	var w := float(layout.width)
	var h := float(layout.height)
	box(_static, Vector3(-200, -0.2, -200), Vector3(260, -0.01, 240), mat(C_GRASS_OUT), false)
	box(_static, Vector3(0, -0.01, 0), Vector3(w, 0.0, h), mat(C_PLOT, 0.95), false)
	_build_pitch(layout.pitch)
	_build_floodlights(layout)
	_build_trees(layout)


func _build_pitch(p: Rect2i) -> void:
	var x0 := float(p.position.x)
	var z0 := float(p.position.y)
	var x1 := float(p.end.x)
	var z1 := float(p.end.y)
	var stripes := 12
	var sw := (x1 - x0) / stripes
	for i in stripes:
		box(_static, Vector3(x0 + i * sw, 0.0, z0), Vector3(x0 + (i + 1) * sw, 0.03, z1),
			mat(C_PITCH_A if i % 2 == 0 else C_PITCH_B, 0.95), false)
	var line := mat(Color(0.95, 0.95, 0.95), 0.7)
	var y0 := 0.03
	var y1 := 0.045
	var t := 0.09
	var lx0 := x0 + 0.6
	var lx1 := x1 - 0.6
	var lz0 := z0 + 0.6
	var lz1 := z1 - 0.6
	var cx := (x0 + x1) / 2.0
	var cz := (z0 + z1) / 2.0
	_rect_lines(lx0, lz0, lx1, lz1, y0, y1, t, line)
	box(_static, Vector3(cx - t / 2, y0, lz0), Vector3(cx + t / 2, y1, lz1), line, false)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.55
	torus.outer_radius = 2.55 + t
	torus.rings = 48
	ring.mesh = torus
	ring.scale = Vector3(1, 0.08, 1)
	ring.position = Vector3(cx, y0, cz)
	ring.material_override = line
	_static.add_child(ring)
	for end in [0, 1]:
		var gx := lx0 if end == 0 else lx1
		var dir := 1.0 if end == 0 else -1.0
		_rect_lines(min(gx, gx + dir * 4.7), cz - 5.8, max(gx, gx + dir * 4.7), cz + 5.8, y0, y1, t, line)
		_rect_lines(min(gx, gx + dir * 1.6), cz - 2.6, max(gx, gx + dir * 1.6), cz + 2.6, y0, y1, t, line)
		# goal: posts, crossbar, net
		var post := mat(Color.WHITE, 0.4)
		var gh := 0.7
		for zz in [cz - 1.05, cz + 1.05]:
			box(_static, Vector3(gx - 0.04, 0, zz - 0.04), Vector3(gx + 0.04, gh, zz + 0.04), post)
		box(_static, Vector3(gx - 0.04, gh - 0.04, cz - 1.05), Vector3(gx + 0.04, gh + 0.04, cz + 1.05), post)
		var back := gx - dir * 0.6
		box(_static, Vector3(min(gx, back), 0, cz - 1.05), Vector3(max(gx, back), gh, cz + 1.05),
			mat(Color(1, 1, 1), 1.0, 0.0, 0.0, 0.25), false)


func _rect_lines(x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, t: float, m: Material) -> void:
	box(_static, Vector3(x0, y0, z0 - t / 2), Vector3(x1, y1, z0 + t / 2), m, false)
	box(_static, Vector3(x0, y0, z1 - t / 2), Vector3(x1, y1, z1 + t / 2), m, false)
	box(_static, Vector3(x0 - t / 2, y0, z0), Vector3(x0 + t / 2, y1, z1), m, false)
	box(_static, Vector3(x1 - t / 2, y0, z0), Vector3(x1 + t / 2, y1, z1), m, false)


func _build_floodlights(layout: Layout) -> void:
	var p := layout.pitch
	var centre := Vector3(p.get_center().x, 0, p.get_center().y)
	var steel := mat(Color(0.35, 0.36, 0.38), 0.5, 0.7)
	var lamp := mat(Color(1.0, 0.97, 0.88), 0.3, 0.0, 4.0)
	for c in [Vector2(p.position.x - 3.5, p.position.y - 3.5), Vector2(p.end.x + 3.5, p.position.y - 3.5),
			Vector2(p.position.x - 3.5, p.end.y + 3.5), Vector2(p.end.x + 3.5, p.end.y + 3.5)]:
		var height := 17.0
		box(_static, Vector3(c.x - 0.2, 0, c.y - 0.2), Vector3(c.x + 0.2, height, c.y + 0.2), steel)
		var head := Node3D.new()
		head.position = Vector3(c.x, height + 0.8, c.y)
		_static.add_child(head)
		head.look_at(centre, Vector3.UP)
		var panel := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(3.0, 1.8, 0.25)
		panel.mesh = bm
		panel.material_override = steel
		head.add_child(panel)
		var glow := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(2.7, 1.5, 0.05)
		glow.mesh = gm
		glow.position = Vector3(0, 0, -0.15)
		glow.material_override = lamp
		head.add_child(glow)
		var spot := SpotLight3D.new()
		spot.light_color = Color(1.0, 0.96, 0.88)
		spot.light_energy = 3.0
		spot.spot_range = 60.0
		spot.spot_angle = 32.0
		spot.spot_attenuation = 0.6
		head.add_child(spot)


func _build_trees(layout: Layout) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var leaves := MultiMesh.new()
	leaves.transform_format = MultiMesh.TRANSFORM_3D
	leaves.use_colors = true
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 2.6
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.vertex_color_use_as_albedo = true
	leaf_mat.roughness = 0.9
	cone.material = leaf_mat
	leaves.mesh = cone
	var spots: Array[Transform3D] = []
	var plot := Rect2(-3, -3, layout.width + 6, layout.height + 6)
	while spots.size() < 220:
		var p := Vector2(rng.randf_range(-45, layout.width + 45), rng.randf_range(-35, layout.height + 35))
		if plot.has_point(p):
			continue
		var s := rng.randf_range(0.8, 1.8)
		spots.append(Transform3D(Basis().scaled(Vector3(s, s * rng.randf_range(0.9, 1.4), s)), Vector3(p.x, 1.3 * s + 0.6, p.y)))
	leaves.instance_count = spots.size()
	for i in spots.size():
		leaves.set_instance_transform(i, spots[i])
		leaves.set_instance_color(i, Color(0.12, rng.randf_range(0.28, 0.4), 0.12))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = leaves
	_static.add_child(mmi)


# --- stands, concourse, facilities ---------------------------------------

func build_layout(layout: Layout, config: SimConfig, report: MatchdayReport, selected: int) -> void:
	for c in _stands.get_children():
		c.queue_free()
	_roofs.clear()
	var cd := config.integer("layout/concourse_depth")
	for i in layout.stands.size():
		var s := layout.stands[i]
		var root := Node3D.new()
		_stands.add_child(root)
		_build_stand(root, s, layout.pitch, i == selected, _stand_label(s, i, config, report))
		var conc := tiles_xz(s.concourse_tiles(layout.pitch, cd))
		box(root, Vector3(conc.position.x, 0, conc.position.y), Vector3(conc.end.x, 0.05, conc.end.y), mat(C_PAVING, 0.9), false)
	for f in layout.facilities:
		_build_facility(f, config.facility_type(f.type_id))
	build_crowd(layout, config, report)


func _stand_label(s: Stand, i: int, config: SimConfig, report: MatchdayReport) -> Dictionary:
	var t := config.stand_type(s.type_id)
	var cap := s.capacity(t)
	if report != null and i < report.stands.size() and report.stands[i]["capacity"] == cap:
		var st: Dictionary = report.stands[i]
		return { "text": "%d / %d" % [st["attendance"], cap], "full": st["fill"] >= 0.99 }
	return { "text": "%s  %d" % [t.display_name, cap], "full": false }


func _build_stand(root: Node3D, s: Stand, pitch: Rect2i, selected: bool, label: Dictionary) -> void:
	var tp := to_pitch(s.side)
	var concrete := mat(C_CONCRETE, 0.9)
	var seat := mat(C_SEAT[s.type_id], 0.7)
	var top := 0.0
	for v in s.depth:
		var row: Array[Vector2i] = []
		for u in range(s.offset, s.offset + s.length):
			row.append(Stand.local_to_grid(s.side, pitch, u, s.setback + v))
		var r := tiles_xz(row)
		var hgt := row_height(v)
		top = hgt
		box(root, Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, hgt, r.end.y), concrete)
		# seats: front 70% of the step, toward the pitch
		var sr := _shrink_away_from_pitch(r, tp, 0.3)
		box(root, Vector3(sr.position.x + 0.03, hgt, sr.position.y + 0.03), Vector3(sr.end.x - 0.03, hgt + 0.07, sr.end.y - 0.03), seat)
		if s.type_id == "terrace" and v % 2 == 1:
			# crush barrier along the step
			var b := _shrink_away_from_pitch(r, tp, 0.92)
			box(root, Vector3(b.position.x, hgt, b.position.y), Vector3(b.end.x, hgt + 0.28, b.end.y), mat(Color(0.85, 0.75, 0.2), 0.5, 0.5))
	var foot := tiles_xz(s.tiles(pitch))
	# back wall (glazed hospitality for premium)
	var back := _strip_away_from_pitch(foot, tp, 0.14)
	var wall_m := mat(Color(1.0, 0.85, 0.55), 0.2, 0.0, 1.2) if s.type_id == "premium" else mat(C_CONCRETE_DARK, 0.9)
	box(root, Vector3(back.position.x, 0, back.position.y), Vector3(back.end.x, top + 1.1, back.end.y), wall_m)
	# side walls
	for end in [0, 1]:
		var sw := _end_strip(foot, tp, end, 0.12)
		box(root, Vector3(sw.position.x, 0, sw.position.y), Vector3(sw.end.x, top + 0.5, sw.end.y), mat(C_CONCRETE_DARK, 0.9))
	# roof
	var roof := Node3D.new()
	root.add_child(roof)
	_roofs.append(roof)
	roof.visible = show_roofs
	var ry := top + ROOF_CLEARANCE
	var rr := _grow_toward_pitch(foot, tp, 0.7)
	box(roof, Vector3(rr.position.x, ry, rr.position.y), Vector3(rr.end.x, ry + 0.14, rr.end.y), mat(C_ROOF, 0.7, 0.25))
	var fascia := _strip_toward_pitch(rr, tp, 0.12)
	box(roof, Vector3(fascia.position.x, ry - 0.35, fascia.position.y), Vector3(fascia.end.x, ry + 0.2, fascia.end.y), mat(C_CLUB, 0.5))
	var along := Vector2(abs(tp.y), abs(tp.x))  # direction along the stand
	var n := maxi(2, ceili(s.length / 5.0) + 1)
	for k in n:
		var f := float(k) / float(n - 1)
		var p := back.position + back.size / 2.0 + along * (f - 0.5) * (s.length - 0.4)
		box(roof, Vector3(p.x - 0.1, 0, p.y - 0.1), Vector3(p.x + 0.1, ry, p.y + 0.1), mat(C_ROOF, 0.4, 0.6))
	# label
	var l := Label3D.new()
	l.text = label["text"]
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 40
	l.fixed_size = true
	l.pixel_size = 0.0006
	l.outline_size = 12
	l.modulate = Color(0.6, 1.0, 0.6) if label["full"] else Color.WHITE
	l.position = Vector3(foot.get_center().x, ry + 1.2, foot.get_center().y)
	root.add_child(l)
	if selected:
		box(root, Vector3(foot.position.x - 0.1, 0, foot.position.y - 0.1), Vector3(foot.end.x + 0.1, top + 0.4, foot.end.y + 0.1),
			mat(Color(1.0, 0.85, 0.2), 1.0, 0.0, 0.0, 0.28), false)


## Sub-rect of r keeping the part nearest the pitch (drops `frac` of depth at the back).
static func _shrink_away_from_pitch(r: Rect2, tp: Vector2, frac: float) -> Rect2:
	if tp.x != 0.0:
		var d := r.size.x * frac
		return Rect2(r.position.x + (0.0 if tp.x > 0 else d), r.position.y, r.size.x - d, r.size.y)
	var dz := r.size.y * frac
	return Rect2(r.position.x, r.position.y + (0.0 if tp.y > 0 else dz), r.size.x, r.size.y - dz)


static func _strip_away_from_pitch(r: Rect2, tp: Vector2, t: float) -> Rect2:
	if tp.x > 0: return Rect2(r.position.x, r.position.y, t, r.size.y)
	if tp.x < 0: return Rect2(r.end.x - t, r.position.y, t, r.size.y)
	if tp.y > 0: return Rect2(r.position.x, r.position.y, r.size.x, t)
	return Rect2(r.position.x, r.end.y - t, r.size.x, t)


static func _strip_toward_pitch(r: Rect2, tp: Vector2, t: float) -> Rect2:
	return _strip_away_from_pitch(r, -tp, t)


static func _grow_toward_pitch(r: Rect2, tp: Vector2, d: float) -> Rect2:
	if tp.x > 0: return Rect2(r.position.x, r.position.y, r.size.x + d, r.size.y)
	if tp.x < 0: return Rect2(r.position.x - d, r.position.y, r.size.x + d, r.size.y)
	if tp.y > 0: return Rect2(r.position.x, r.position.y, r.size.x, r.size.y + d)
	return Rect2(r.position.x, r.position.y - d, r.size.x, r.size.y + d)


static func _end_strip(r: Rect2, tp: Vector2, end: int, t: float) -> Rect2:
	if tp.x != 0.0:  # stand runs along Z
		return Rect2(r.position.x, r.position.y if end == 0 else r.end.y - t, r.size.x, t)
	return Rect2(r.position.x if end == 0 else r.end.x - t, r.position.y, t, r.size.y)


func _build_facility(f: Facility, ft: FacilityType) -> void:
	var x := float(f.pos.x)
	var z := float(f.pos.y)
	if ft.kind == "food":
		box(_stands, Vector3(x + 0.1, 0.05, z + 0.15), Vector3(x + 0.9, 0.75, z + 0.85), mat(Color(0.93, 0.9, 0.82), 0.8))
		box(_stands, Vector3(x + 0.02, 0.72, z + 0.05), Vector3(x + 0.98, 0.8, z + 0.95), mat(Color(0.95, 0.55, 0.12), 0.6))
		box(_stands, Vector3(x + 0.2, 0.4, z + 0.1), Vector3(x + 0.8, 0.55, z + 0.16), mat(Color(1.0, 0.8, 0.4), 0.3, 0.0, 1.5))
	else:
		box(_stands, Vector3(x + 0.08, 0.05, z + 0.08), Vector3(x + 0.92, 0.85, z + 0.92), mat(Color(0.75, 0.82, 0.9), 0.8))
		box(_stands, Vector3(x + 0.02, 0.85, z + 0.02), Vector3(x + 0.98, 0.93, z + 0.98), mat(Color(0.15, 0.35, 0.75), 0.6))


# --- crowd -----------------------------------------------------------------

func build_crowd(layout: Layout, config: SimConfig, report: MatchdayReport) -> void:
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var customs: Array[Color] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	if report != null:
		for i in layout.stands.size():
			var s := layout.stands[i]
			var t := config.stand_type(s.type_id)
			if i >= report.stands.size() or report.stands[i]["capacity"] != s.capacity(t):
				continue
			var fill: float = report.stands[i]["fill"]
			var per_tile := maxi(1, roundi(t.capacity_per_tile / FIGURES_PER_PLACES))
			var cols := ceili(per_tile / 2.0)
			var tp := to_pitch(s.side)
			var along := Vector2(abs(tp.y), abs(tp.x))
			for v in s.depth:
				for u in range(s.offset, s.offset + s.length):
					var tile := Stand.local_to_grid(s.side, layout.pitch, u, s.setback + v)
					var centre := Vector2(tile) + Vector2(0.5, 0.5)
					for k in per_tile:
						if rng.randf() >= fill:
							continue
						var c := k % cols
						var r := k / cols
						var a := (float(c) + 0.5) / cols - 0.5
						var depth_off := 0.22 - r * 0.32   # rows within the step, toward pitch first
						var p := centre + along * a * 0.9 + tp * depth_off + Vector2(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.04, 0.04))
						var sc := rng.randf_range(0.9, 1.1)
						transforms.append(Transform3D(Basis().scaled(Vector3(sc, sc, sc)), Vector3(p.x, row_height(v) + 0.07 + 0.2 * sc, p.y)))
						colors.append(_shirt(s.type_id, rng))
						customs.append(Color(rng.randf(), t.noise / 1.5, 0, 0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var cap := CapsuleMesh.new()
	cap.radius = 0.075
	cap.height = 0.4
	cap.radial_segments = 6
	cap.rings = 2
	mm.mesh = cap
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
		mm.set_instance_custom_data(i, customs[i])
	_crowd.multimesh = mm
	_crowd.material_override = _crowd_mat
	_crowd_mat.set_shader_parameter("bounce", 0.0 if report == null else report.atmosphere / 100.0 * 0.22)


static func _shirt(type_id: String, rng: RandomNumberGenerator) -> Color:
	var r := rng.randf()
	if type_id == "premium":
		return Color(0.12, 0.12, 0.16) if r < 0.6 else Color(0.25, 0.25, 0.3) if r < 0.85 else C_CLUB
	if r < 0.55:
		return C_CLUB.lightened(rng.randf_range(-0.1, 0.1))
	if r < 0.75:
		return C_CLUB_2
	return Color.from_hsv(rng.randf(), rng.randf_range(0.1, 0.5), rng.randf_range(0.2, 0.7))


# --- hover / ghost ------------------------------------------------------------

func show_ghost_stand(s: Stand, pitch: Rect2i, ok: bool) -> void:
	clear_overlay()
	var r := tiles_xz(s.tiles(pitch))
	box(_overlay, Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, row_height(s.depth - 1), r.end.y),
		mat(Color(0.4, 1.0, 0.4) if ok else Color(1, 0.4, 0.3), 1.0, 0.0, 0.0, 0.45), false)


func show_ghost_tile(tile: Vector2i, ok: bool) -> void:
	clear_overlay()
	box(_overlay, Vector3(tile.x, 0, tile.y), Vector3(tile.x + 1, 0.9, tile.y + 1),
		mat(Color(0.4, 1.0, 0.4) if ok else Color(1, 0.4, 0.3), 1.0, 0.0, 0.0, 0.45), false)


func show_hover_tile(tile: Vector2i) -> void:
	clear_overlay()
	box(_overlay, Vector3(tile.x, 0.06, tile.y), Vector3(tile.x + 1, 0.09, tile.y + 1), mat(Color(1, 1, 1), 1.0, 0.0, 0.0, 0.3), false)


func clear_overlay() -> void:
	for c in _overlay.get_children():
		c.free()
