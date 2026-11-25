extends Node3D
## Builds the 3D stadium from sim state. Read-only on the sim.
## World units: 1 unit = 1 tile. Tile (x, y) covers [x, x+1] x [y, y+1] in X/Z.

const ROW_BASE := 0.35        # height of the front row
const ROW_RISE := 0.45        # extra height per row back
const ROOF_CLEARANCE := 2.3
const RIDGE_RISE := 1.6
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
	return { "N": Vector2(0, 1), "S": Vector2(0, -1), "W": Vector2(1, 0), "E": Vector2(-1, 0),
		"NW": Vector2(1, 1), "NE": Vector2(-1, 1), "SW": Vector2(1, -1), "SE": Vector2(-1, -1) }[side]


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

var _club: ClubState


func build_layout(layout: Layout, config: SimConfig, report: MatchdayReport, selected: int, club: ClubState) -> void:
	_club = club
	for c in _stands.get_children():
		c.queue_free()
	_roofs.clear()
	var cd := config.integer("layout/concourse_depth")
	var main_stand := _main_stand(layout, config)
	for i in layout.stands.size():
		var s := layout.stands[i]
		var root := Node3D.new()
		_stands.add_child(root)
		if s.is_corner():
			_build_corner(root, s, layout.pitch, i == selected, _stand_label(s, i, config, report))
		else:
			_build_stand(root, s, layout.pitch, i == selected, _stand_label(s, i, config, report), i == main_stand)
		for t in s.concourse_tiles(layout.pitch, cd):
			if layout.in_plot(t):
				box(root, Vector3(t.x, 0, t.y), Vector3(t.x + 1, 0.05, t.y + 1), mat(C_PAVING, 0.9), false)
	for f in layout.facilities:
		_build_facility(f, config.facility_type(f.type_id))
	build_crowd(layout, config, report)


## The biggest roofed side stand carries the club name.
func _main_stand(layout: Layout, config: SimConfig) -> int:
	var best := -1
	var best_cap := 0
	for i in layout.stands.size():
		var s := layout.stands[i]
		if s.is_corner() or s.roof == "open" or s.length < 8:
			continue
		var cap := s.capacity(config.stand_type(s.type_id))
		if cap > best_cap:
			best_cap = cap
			best = i
	return best


func _stand_label(s: Stand, i: int, config: SimConfig, report: MatchdayReport) -> Dictionary:
	var t := config.stand_type(s.type_id)
	var cap := s.capacity(t)
	if report != null and i < report.stands.size() and report.stands[i]["capacity"] == cap:
		var st: Dictionary = report.stands[i]
		return { "text": "%d / %d" % [st["attendance"], cap], "full": st["fill"] >= 0.99 }
	return { "text": "%s  %d" % [t.display_name, cap], "full": false }


func seat_color(s: Stand) -> Color:
	if s.seat_color != "":
		return Color.html(s.seat_color)
	match s.type_id:
		"terrace": return Color(0.55, 0.55, 0.56)
		"premium": return Color(0.10, 0.14, 0.32)
		"family": return _club.secondary_color
		"safe_standing": return _club.primary_color.darkened(0.35)
	return _club.primary_color


## A local frame for a side stand: origin at the footprint centre on the ground,
## local +Z points at the pitch, local +X runs along the stand.
func _frame(parent: Node3D, foot: Rect2, tp: Vector2) -> Node3D:
	var f := Node3D.new()
	f.position = Vector3(foot.get_center().x, 0, foot.get_center().y)
	f.rotation.y = atan2(tp.x, tp.y)
	parent.add_child(f)
	return f


## Box in a local frame: centre, size, optional tilt about local X.
func lbox(parent: Node3D, centre: Vector3, size: Vector3, m: Material, tilt := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = centre
	mi.rotation.x = tilt
	parent.add_child(mi)
	return mi


func _build_stand(root: Node3D, s: Stand, pitch: Rect2i, selected: bool, label: Dictionary, is_main: bool) -> void:
	var tp := to_pitch(s.side)
	var concrete := mat(C_CONCRETE, 0.9)
	var seat := mat(seat_color(s), 0.7)
	var rail := mat(Color(0.85, 0.75, 0.2), 0.5, 0.5) if s.type_id == "terrace" else mat(Color(0.25, 0.26, 0.28), 0.4, 0.7)
	var top := 0.0
	for v in s.depth:
		var r := tiles_xz(s.row_tiles(pitch, v))
		var hgt := row_height(v)
		top = hgt
		box(root, Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, hgt, r.end.y), concrete)
		var sr := _shrink_away_from_pitch(r, tp, 0.5 if s.type_id == "safe_standing" else 0.3)
		box(root, Vector3(sr.position.x + 0.03, hgt, sr.position.y + 0.03), Vector3(sr.end.x - 0.03, hgt + 0.07, sr.end.y - 0.03), seat)
		if (s.type_id == "terrace" and v % 2 == 1) or s.type_id == "safe_standing":
			var b := _shrink_away_from_pitch(r, tp, 0.92 if s.type_id == "terrace" else 0.6)
			box(root, Vector3(b.position.x, hgt, b.position.y), Vector3(b.end.x, hgt + 0.3, b.end.y), rail)
	var foot := tiles_xz(s.tiles(pitch))
	var fr := _frame(root, foot, tp)
	var L := foot.size.x if tp.x == 0.0 else foot.size.y
	var D := foot.size.y if tp.x == 0.0 else foot.size.x
	var dark := mat(C_CONCRETE_DARK, 0.9)
	# back wall (glazed hospitality for premium) and end walls
	var wall_m := mat(Color(1.0, 0.85, 0.55), 0.2, 0.0, 0.45) if s.type_id == "premium" else dark
	lbox(fr, Vector3(0, (top + 1.1) / 2.0, -D / 2.0 + 0.07), Vector3(L, top + 1.1, 0.14), wall_m)
	for e in [-1, 1]:
		lbox(fr, Vector3(e * (L / 2.0 - 0.06), (top + 0.5) / 2.0, 0), Vector3(0.12, top + 0.5, D), dark)
	# roof
	var roof := Node3D.new()
	fr.add_child(roof)
	_roofs.append(roof)
	roof.visible = show_roofs
	var name_y := 0.0
	var name_z := 0.0
	match s.roof:
		"gable":
			name_y = _roof_gable(roof, L, D, top)
			name_z = D / 2.0 + 0.82
		"cantilever":
			name_y = _roof_cantilever(roof, L, D, top, s.length)
			name_z = D / 2.0 + 0.72
		"barrel":
			name_y = _roof_barrel(roof, L, D, top, s.length)
			name_z = D / 2.0 + 0.72
		"truss":
			name_y = _roof_truss(roof, L, D, top)
			name_z = D / 2.0 + 0.85
	if is_main and s.roof != "open" and _club != null:
		var n := Label3D.new()
		n.text = _club.club_name.to_upper()
		n.font_size = 64
		n.pixel_size = 0.0065
		n.outline_size = 8
		n.modulate = _club.secondary_color
		n.outline_modulate = _club.primary_color.darkened(0.4)
		n.position = Vector3(0, name_y, name_z)
		roof.add_child(n)
	# floating label
	var l := Label3D.new()
	l.text = label["text"]
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 40
	l.fixed_size = true
	l.pixel_size = 0.0006
	l.outline_size = 12
	l.modulate = Color(0.6, 1.0, 0.6) if label["full"] else Color.WHITE
	l.position = Vector3(foot.get_center().x, top + ROOF_CLEARANCE + 1.6, foot.get_center().y)
	root.add_child(l)
	if selected:
		box(root, Vector3(foot.position.x - 0.1, 0, foot.position.y - 0.1), Vector3(foot.end.x + 0.1, top + 0.4, foot.end.y + 0.1),
			mat(Color(1.0, 0.85, 0.2), 1.0, 0.0, 0.0, 0.28), false)


## Modern roof on columns at the back, pitched gently backwards so rain runs
## away from the pitch, with a club-coloured fascia. Returns fascia height.
func _roof_cantilever(roof: Node3D, L: float, D: float, top: float, length: int) -> float:
	var front_y := top + ROOF_CLEARANCE + 0.25
	var back_y := top + ROOF_CLEARANCE - 0.35
	var z0 := -D / 2.0
	var z1 := D / 2.0 + 0.7
	var run := z1 - z0
	var tilt := -atan2(front_y - back_y, run)
	lbox(roof, Vector3(0, (front_y + back_y) / 2.0 + 0.07, (z0 + z1) / 2.0), Vector3(L, 0.14, sqrt(run * run + 0.36)), mat(C_ROOF, 0.7, 0.25), tilt)
	lbox(roof, Vector3(0, front_y - 0.08, z1 - 0.06), Vector3(L, 0.55, 0.12), mat(_club.primary_color, 0.5))
	# gutter along the back
	lbox(roof, Vector3(0, back_y, z0 - 0.05), Vector3(L, 0.12, 0.16), mat(Color(0.3, 0.32, 0.35), 0.5, 0.6))
	var n := maxi(2, ceili(length / 5.0) + 1)
	for k in n:
		var x := (float(k) / float(n - 1) - 0.5) * (L - 0.4)
		lbox(roof, Vector3(x, back_y / 2.0, z0 + 0.07), Vector3(0.2, back_y, 0.2), mat(C_ROOF, 0.4, 0.6))
	return front_y - 0.08


## Curved barrel-vault roof (arched front to back) on back columns.
func _roof_barrel(roof: Node3D, L: float, D: float, top: float, length: int) -> float:
	var base_y := top + ROOF_CLEARANCE
	var z0 := -D / 2.0
	var z1 := D / 2.0 + 0.7
	var half := (z1 - z0) / 2.0
	var rise := clampf(half * 0.45, 0.8, 2.2)
	var radius := (half * half + rise * rise) / (2.0 * rise)
	var centre_y := base_y + rise - radius
	var centre_z := (z0 + z1) / 2.0
	var theta := asin(clampf(half / radius, -1.0, 1.0))
	var segs := 10
	var skin := mat(Color(0.78, 0.82, 0.86), 0.35, 0.5)
	for i in segs:
		var a0 := lerpf(theta, -theta, float(i) / segs)
		var a1 := lerpf(theta, -theta, float(i + 1) / segs)
		var p0 := Vector2(centre_z + sin(a0) * radius, centre_y + cos(a0) * radius)
		var p1 := Vector2(centre_z + sin(a1) * radius, centre_y + cos(a1) * radius)
		var mid := (p0 + p1) / 2.0
		var d := p0 - p1
		lbox(roof, Vector3(0, mid.y, mid.x), Vector3(L, 0.1, d.length() + 0.04), skin, -atan2(d.y, d.x) if d.x != 0.0 else 0.0)
	# arched ribs at each end and every few tiles, in club colour
	var ribs := maxi(2, ceili(length / 6.0) + 1)
	for k in ribs:
		var x := (float(k) / float(ribs - 1) - 0.5) * (L - 0.1)
		for i in segs:
			var a0 := lerpf(theta, -theta, float(i) / segs)
			var a1 := lerpf(theta, -theta, float(i + 1) / segs)
			var p0 := Vector2(centre_z + sin(a0) * radius, centre_y + cos(a0) * radius)
			var p1 := Vector2(centre_z + sin(a1) * radius, centre_y + cos(a1) * radius)
			var mid := (p0 + p1) / 2.0
			var d := p0 - p1
			lbox(roof, Vector3(x, mid.y + 0.06, mid.x), Vector3(0.12, 0.12, d.length() + 0.04), mat(_club.primary_color, 0.5), -atan2(d.y, d.x))
		lbox(roof, Vector3(x, base_y / 2.0, z0 + 0.1), Vector3(0.2, base_y, 0.2), mat(C_ROOF, 0.4, 0.6))
	return base_y - 0.1


## "Goalpost" roof: no pillars in the way, the front hangs from a big steel
## truss spanning the whole stand on two tall end towers.
func _roof_truss(roof: Node3D, L: float, D: float, top: float) -> float:
	var front_y := top + ROOF_CLEARANCE + 0.2
	var back_y := top + ROOF_CLEARANCE - 0.3
	var z0 := -D / 2.0
	var z1 := D / 2.0 + 0.7
	var run := z1 - z0
	lbox(roof, Vector3(0, (front_y + back_y) / 2.0, (z0 + z1) / 2.0), Vector3(L, 0.14, sqrt(run * run + 0.25)), mat(C_ROOF, 0.7, 0.25), -atan2(front_y - back_y, run))
	var steel := mat(_club.primary_color.darkened(0.15), 0.4, 0.6)
	var tz := z1 - 0.1
	var lo := front_y + 0.1
	var hi := front_y + 1.3
	var span := L + 1.2
	lbox(roof, Vector3(0, lo, tz), Vector3(span, 0.14, 0.18), steel)
	lbox(roof, Vector3(0, hi, tz), Vector3(span, 0.14, 0.18), steel)
	var bays := maxi(4, int(span / 1.6))
	var bw := span / bays
	for k in bays:
		var x := -span / 2.0 + (k + 0.5) * bw
		var diag := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09, sqrt(bw * bw + (hi - lo) * (hi - lo)), 0.09)
		diag.mesh = bm
		diag.material_override = steel
		diag.position = Vector3(x, (lo + hi) / 2.0, tz)
		diag.rotation.z = atan2(bw, hi - lo) * (1.0 if k % 2 == 0 else -1.0)
		roof.add_child(diag)
	for e in [-1, 1]:
		lbox(roof, Vector3(e * (span / 2.0), (hi + 0.4) / 2.0, tz), Vector3(0.35, hi + 0.4, 0.35), steel)
	lbox(roof, Vector3(0, back_y / 2.0, z0 + 0.07), Vector3(L - 0.4, 0.06, 0.06), mat(C_ROOF, 0.4, 0.6))
	return lo - 0.25


## Classic pitched roof: two slopes meeting at a ridge, pillars along the front,
## and a gable over the middle. Returns the height for the name board.
func _roof_gable(roof: Node3D, L: float, D: float, top: float) -> float:
	var eave := top + ROOF_CLEARANCE - 0.2
	var ridge := eave + RIDGE_RISE
	var front := D / 2.0 + 0.8
	var back := -D / 2.0
	var ridge_z := (front + back) / 2.0
	var tin := mat(Color(0.42, 0.45, 0.42), 0.6, 0.3)
	for side in [[front, ridge_z], [back, ridge_z]]:
		var z0: float = side[0]
		var z1: float = side[1]
		var run := absf(z1 - z0)
		var slope := sqrt(run * run + RIDGE_RISE * RIDGE_RISE)
		var ang := atan2(RIDGE_RISE, run) * (1.0 if z0 > z1 else -1.0)
		lbox(roof, Vector3(0, (eave + ridge) / 2.0, (z0 + z1) / 2.0), Vector3(L, 0.1, slope + 0.1), tin, ang)
	# gutter board along the front in club colour
	lbox(roof, Vector3(0, eave - 0.1, front), Vector3(L, 0.3, 0.1), mat(_club.primary_color, 0.5))
	# front pillars
	var n := maxi(2, ceili(L / 4.0) + 1)
	for k in n:
		var x := (float(k) / float(n - 1) - 0.5) * (L - 0.3)
		lbox(roof, Vector3(x, eave / 2.0, front - 0.1), Vector3(0.12, eave, 0.12), mat(Color(0.2, 0.22, 0.25), 0.5, 0.5))
	# central gable
	var g := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(minf(L * 0.35, 7.0), 1.8, 0.16)
	g.mesh = pm
	g.material_override = mat(_club.secondary_color, 0.7)
	g.position = Vector3(0, eave + 0.9, front + 0.02)
	roof.add_child(g)
	return eave + 0.45


## Pitch corner point and the outward x / z signs for a corner stand.
static func corner_frame(side: String, pitch: Rect2i) -> Dictionary:
	var sx := -1.0 if side.ends_with("W") else 1.0
	var sz := -1.0 if side.begins_with("N") else 1.0
	var cx := float(pitch.position.x) if sx < 0 else float(pitch.end.x)
	var cz := float(pitch.position.y) if sz < 0 else float(pitch.end.y)
	return { "centre": Vector2(cx, cz), "sx": sx, "sz": sz }


## A quarter-annulus prism: radii r0..r1 around `centre`, heights y0..y1,
## spanning from the outward-x axis to the outward-z axis.
func sector(parent: Node3D, cf: Dictionary, r0: float, r1: float, y0: float, y1: float, m: StandardMaterial3D, segs := 14) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c: Vector2 = cf["centre"]
	var sx: float = cf["sx"]
	var sz: float = cf["sz"]
	var pt := func(r: float, phi: float, y: float) -> Vector3:
		return Vector3(c.x + sx * cos(phi) * r, y, c.y + sz * sin(phi) * r)
	var quad := func(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, n: Vector3) -> void:
		for v in [a, b, cc, a, cc, d]:
			st.set_normal(n)
			st.add_vertex(v)
	for i in segs:
		var p0 := PI / 2.0 * i / segs
		var p1 := PI / 2.0 * (i + 1) / segs
		var pm := (p0 + p1) / 2.0
		var out := Vector3(sx * cos(pm), 0, sz * sin(pm))
		quad.call(pt.call(r0, p0, y1), pt.call(r1, p0, y1), pt.call(r1, p1, y1), pt.call(r0, p1, y1), Vector3.UP)
		quad.call(pt.call(r1, p0, y0), pt.call(r1, p1, y0), pt.call(r1, p1, y1), pt.call(r1, p0, y1), out)
		if r0 > 0.0:
			quad.call(pt.call(r0, p0, y0), pt.call(r0, p0, y1), pt.call(r0, p1, y1), pt.call(r0, p1, y0), -out)
	quad.call(pt.call(r0, 0.0, y0), pt.call(r1, 0.0, y0), pt.call(r1, 0.0, y1), pt.call(r0, 0.0, y1), Vector3(0, 0, -sz))
	quad.call(pt.call(r0, PI / 2, y0), pt.call(r0, PI / 2, y1), pt.call(r1, PI / 2, y1), pt.call(r1, PI / 2, y0), Vector3(-sx, 0, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _double_sided(m)
	parent.add_child(mi)


func _double_sided(m: StandardMaterial3D) -> StandardMaterial3D:
	var key := "ds|%d" % m.get_instance_id()
	if not _mats.has(key):
		var d: StandardMaterial3D = m.duplicate()
		d.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = d
	return _mats[key]


func _build_rounded_corner(root: Node3D, s: Stand, pitch: Rect2i, selected: bool, label: Dictionary) -> void:
	var cf := corner_frame(s.side, pitch)
	var concrete := mat(C_CONCRETE, 0.9)
	var seat := mat(seat_color(s), 0.7)
	var top := 0.0
	for v in s.depth:
		var hgt := row_height(v)
		top = hgt
		sector(root, cf, float(v), float(v + 1), 0.0, hgt, concrete)
		sector(root, cf, v + 0.04, v + 0.7, hgt, hgt + 0.07, seat)
	var R := float(s.depth)
	sector(root, cf, R - 0.14, R, 0.0, top + 1.1, mat(C_CONCRETE_DARK, 0.9))
	if s.roof != "open":
		var roof := Node3D.new()
		root.add_child(roof)
		_roofs.append(roof)
		roof.visible = show_roofs
		var ry := top + ROOF_CLEARANCE
		sector(roof, cf, 0.0, R, ry, ry + 0.14, mat(C_ROOF, 0.7, 0.25), 18)
		sector(roof, cf, R - 0.12, R, ry - 0.35, ry + 0.2, mat(_club.primary_color, 0.5), 18)
		var c: Vector2 = cf["centre"]
		for phi in [PI / 8, PI / 4, 3 * PI / 8]:
			var p := c + Vector2(cf["sx"] * cos(phi), cf["sz"] * sin(phi)) * (R - 0.25)
			box(roof, Vector3(p.x - 0.1, 0, p.y - 0.1), Vector3(p.x + 0.1, ry, p.y + 0.1), mat(C_ROOF, 0.4, 0.6))
	var foot := tiles_xz(s.tiles(pitch))
	_stand_label_node(root, label, Vector3(foot.get_center().x, top + ROOF_CLEARANCE + 1.6, foot.get_center().y))
	if selected:
		sector(root, cf, 0.0, R + 0.1, 0.0, top + 0.4, mat(Color(1.0, 0.85, 0.2), 1.0, 0.0, 0.0, 0.28))


func _stand_label_node(root: Node3D, label: Dictionary, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = label["text"]
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 40
	l.fixed_size = true
	l.pixel_size = 0.0006
	l.outline_size = 12
	l.modulate = Color(0.6, 1.0, 0.6) if label["full"] else Color.WHITE
	l.position = pos
	root.add_child(l)


func _build_corner(root: Node3D, s: Stand, pitch: Rect2i, selected: bool, label: Dictionary) -> void:
	if s.shape == "rounded":
		_build_rounded_corner(root, s, pitch, selected, label)
		return
	var tp := to_pitch(s.side)
	var concrete := mat(C_CONCRETE, 0.9)
	var seat := mat(seat_color(s), 0.7)
	var top := 0.0
	for v in s.depth:
		var hgt := row_height(v)
		top = hgt
		for t in s.row_tiles(pitch, v):
			box(root, Vector3(t.x, 0, t.y), Vector3(t.x + 1, hgt, t.y + 1), concrete)
			box(root, Vector3(t.x + 0.06, hgt, t.y + 0.06), Vector3(t.x + 0.94, hgt + 0.07, t.y + 0.94), seat)
	var foot := tiles_xz(s.tiles(pitch))
	var dark := mat(C_CONCRETE_DARK, 0.9)
	for axis in [Vector2(tp.x, 0), Vector2(0, tp.y)]:
		var w := _strip_away_from_pitch(foot, axis, 0.14)
		box(root, Vector3(w.position.x, 0, w.position.y), Vector3(w.end.x, top + 1.1, w.end.y), dark)
	if s.roof != "open":
		var roof := Node3D.new()
		root.add_child(roof)
		_roofs.append(roof)
		roof.visible = show_roofs
		var ry := top + ROOF_CLEARANCE
		var rr := _grow_toward_pitch(_grow_toward_pitch(foot, Vector2(tp.x, 0), 0.7), Vector2(0, tp.y), 0.7)
		box(roof, Vector3(rr.position.x, ry, rr.position.y), Vector3(rr.end.x, ry + 0.14, rr.end.y), mat(C_ROOF, 0.7, 0.25))
		for axis in [Vector2(tp.x, 0), Vector2(0, tp.y)]:
			var f := _strip_toward_pitch(rr, axis, 0.12)
			box(roof, Vector3(f.position.x, ry - 0.35, f.position.y), Vector3(f.end.x, ry + 0.2, f.end.y), mat(_club.primary_color, 0.5))
		var c := Vector2(foot.position.x if tp.x > 0 else foot.end.x, foot.position.y if tp.y > 0 else foot.end.y)
		c -= tp * 0.15
		box(roof, Vector3(c.x - 0.12, 0, c.y - 0.12), Vector3(c.x + 0.12, ry, c.y + 0.12), mat(C_ROOF, 0.4, 0.6))
	var l := Label3D.new()
	l.text = label["text"]
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 40
	l.fixed_size = true
	l.pixel_size = 0.0006
	l.outline_size = 12
	l.modulate = Color(0.6, 1.0, 0.6) if label["full"] else Color.WHITE
	l.position = Vector3(foot.get_center().x, top + ROOF_CLEARANCE + 1.6, foot.get_center().y)
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
			var tp := to_pitch(s.side).normalized()
			var along := Vector2(-tp.y, tp.x)
			for v in s.depth:
				for tile in s.row_tiles(layout.pitch, v):
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


func _shirt(type_id: String, rng: RandomNumberGenerator) -> Color:
	var r := rng.randf()
	var home := _club.primary_color if _club else C_CLUB
	var away := _club.secondary_color if _club else C_CLUB_2
	if type_id == "premium":
		return Color(0.12, 0.12, 0.16) if r < 0.6 else Color(0.25, 0.25, 0.3) if r < 0.85 else home
	if r < 0.55:
		return home.lightened(rng.randf_range(-0.1, 0.1))
	if r < 0.75:
		return away
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
