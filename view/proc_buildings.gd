extends RefCounted
## Procedural town buildings: walls are scaled unit boxes drawn by
## facade.gdshader (storeys, windows, shopfronts, curtain walls), with pitched
## tiled roofs, flat roofs with plant on top, chimneys and the odd porch.
## Collect buildings with add(), then build() makes a handful of MultiMeshes.

const STYLE := { "house": 0, "terrace": 0, "flats": 1, "shops": 2, "office": 3, "shed": 4, "church": 0, "pub": 2 }

const WALLS := {
	"house": [Color(0.72, 0.4, 0.3), Color(0.86, 0.8, 0.68), Color(0.93, 0.91, 0.86), Color(0.66, 0.46, 0.34), Color(0.8, 0.74, 0.62), Color(0.62, 0.34, 0.26)],
	"flats": [Color(0.86, 0.84, 0.8), Color(0.74, 0.68, 0.6), Color(0.62, 0.38, 0.3), Color(0.8, 0.8, 0.82), Color(0.9, 0.86, 0.76)],
	"shops": [Color(0.86, 0.78, 0.64), Color(0.7, 0.42, 0.32), Color(0.9, 0.9, 0.88), Color(0.78, 0.72, 0.66), Color(0.6, 0.62, 0.66)],
	"office": [Color(0.46, 0.55, 0.62), Color(0.6, 0.64, 0.68), Color(0.4, 0.46, 0.5), Color(0.72, 0.74, 0.76)],
	"shed": [Color(0.62, 0.66, 0.7), Color(0.55, 0.6, 0.56), Color(0.72, 0.7, 0.66)],
}
const ROOFS := [Color(0.42, 0.24, 0.2), Color(0.3, 0.3, 0.33), Color(0.5, 0.3, 0.22), Color(0.36, 0.33, 0.32), Color(0.55, 0.32, 0.24)]

static var _wall_mat: ShaderMaterial
static var _roof_mat: ShaderMaterial
static var _box: ArrayMesh
static var _prism: ArrayMesh

var walls: Array[Transform3D] = []
var wall_cols: Array[Color] = []
var wall_cust: Array[Color] = []
var roofs: Array[Transform3D] = []
var roof_cols: Array[Color] = []
var units: Array[Transform3D] = []
var chimneys: Array[Vector3] = []   # chimney tops, for winter smoke
var night := false


## Adds a building of `kind` centred at p (ground height y), facing `yaw`.
## Returns its footprint radius so callers can space things.
func add(kind: String, p: Vector2, y: float, yaw: float, rng: RandomNumberGenerator, fade := false) -> void:
	var pal: Array = WALLS[{ "terrace": "house", "church": "house", "pub": "shops" }.get(kind, kind)]
	var wall: Color = pal[rng.randi_range(0, pal.size() - 1)]
	var roof: Color = ROOFS[rng.randi_range(0, ROOFS.size() - 1)]
	var basis := Basis(Vector3.UP, yaw)
	var seed := rng.randf() * 100.0
	match kind:
		"house":
			var w := rng.randf_range(2.4, 3.2)
			var d := rng.randf_range(2.2, 2.8)
			var floors := 2 if rng.randf() < 0.8 else 1
			var h := floors * 0.95
			_wall(basis, p, y, Vector3(w, h, d), wall, "house", seed, 0.95, fade)
			_roof(basis, p, y + h, Vector3(w + 0.3, rng.randf_range(0.8, 1.1), d + 0.3), roof)
			if rng.randf() < 0.6:
				var c := basis * Vector3(w * 0.25, 0, d * 0.1)
				units.append(Transform3D(basis.scaled(Vector3(0.25, 0.9, 0.25)), Vector3(p.x + c.x, y + h + 0.5, p.y + c.z)))
				chimneys.append(Vector3(p.x + c.x, y + h + 0.95, p.y + c.z))
			# a porch over the front door, dormers in the roof, a garden behind
			var front := basis * Vector3(0, 0, d * 0.5 + 0.25)
			if rng.randf() < 0.6:
				var pc := p + Vector2(front.x, front.z)
				_wall(basis, pc, y, Vector3(0.9, 0.7, 0.5), wall.darkened(0.06), "house", seed + 4.0, 0.7, fade)
				_roof(basis, pc, y + 0.7, Vector3(1.0, 0.35, 0.6), roof)
			if rng.randf() < 0.45:
				for k in (2 if w > 2.7 else 1):
					var dx := (k - 0.5) * 1.0 if w > 2.7 else 0.0
					var dp := basis * Vector3(dx, 0, d * 0.18)
					_wall(basis, p + Vector2(dp.x, dp.z), y + h, Vector3(0.55, 0.42, 0.5), wall.lightened(0.05), "house", seed + 6.0 + k, 0.42, fade)
					_roof(basis * Basis(Vector3.UP, PI / 2.0), p + Vector2(dp.x, dp.z), y + h + 0.42, Vector3(0.62, 0.25, 0.62), roof)
			# garden fence and shed out the back
			var back := basis * Vector3(0, 0, -d * 0.5 - 1.2)
			var bc := p + Vector2(back.x, back.z)
			for side in [-1.0, 1.0]:
				var fp := basis * Vector3(side * (w * 0.5 + 0.1), 0, -d * 0.5 - 1.2)
				units.append(Transform3D(basis.scaled(Vector3(0.05, 0.35, 2.3)), Vector3(p.x + fp.x, y + 0.17, p.y + fp.z)))
			var fb := basis * Vector3(0, 0, -d * 0.5 - 2.35)
			units.append(Transform3D(basis.scaled(Vector3(w + 0.2, 0.35, 0.05)), Vector3(p.x + fb.x, y + 0.17, p.y + fb.z)))
			if rng.randf() < 0.55:
				var sp := basis * Vector3(w * 0.3, 0, -d * 0.5 - 1.9)
				_wall(basis, p + Vector2(sp.x, sp.z), y, Vector3(0.6, 0.45, 0.5), Color(0.45, 0.36, 0.26), "shed", seed + 9.0, 0.45, fade)
			if rng.randf() < 0.4:
				# a side extension
				var off := basis * Vector3(w * 0.5 + 0.6, 0, rng.randf_range(-0.4, 0.4))
				_wall(basis, p + Vector2(off.x, off.z), y, Vector3(1.2, 0.95, 1.6), wall.darkened(0.05), "house", seed + 1.0, 0.95, fade)
				_roof(basis, p + Vector2(off.x, off.z), y + 0.95, Vector3(1.4, 0.5, 1.8), roof)
		"terrace":
			# a row of narrow houses sharing a roofline, each its own colour
			var n := rng.randi_range(2, 3)
			var each := rng.randf_range(1.3, 1.5)
			var d := rng.randf_range(2.2, 2.6)
			var h := rng.randf_range(1.8, 2.0)
			for i in n:
				var off := basis * Vector3((i - (n - 1) / 2.0) * each, 0, 0)
				var c: Color = pal[rng.randi_range(0, pal.size() - 1)] if rng.randf() < 0.5 else wall
				_wall(basis, p + Vector2(off.x, off.z), y, Vector3(each + 0.01, h, d), c, "terrace", seed + i, 0.95, fade)
				if i % 2 == 0:
					var ch := basis * Vector3((i - (n - 1) / 2.0) * each + each * 0.5, 0, 0)
					units.append(Transform3D(basis.scaled(Vector3(0.3, 0.7, 0.4)), Vector3(p.x + ch.x, y + h + 0.6, p.y + ch.z)))
					chimneys.append(Vector3(p.x + ch.x, y + h + 0.95, p.y + ch.z))
			_roof(basis, p, y + h, Vector3(n * each + 0.2, 0.9, d + 0.3), roof)
		"flats":
			var w := rng.randf_range(3.6, 5.0)
			var d := rng.randf_range(3.0, 4.0)
			var h := rng.randi_range(4, 7) * 0.95
			_wall(basis, p, y, Vector3(w, h, d), wall, "flats", seed, 0.95, fade)
			_plant(basis, p, y + h, w, d, rng)
		"shops":
			var w := rng.randf_range(3.6, 4.6)
			var d := rng.randf_range(3.0, 3.8)
			var h := rng.randi_range(2, 4) * 0.95
			_wall(basis, p, y, Vector3(w, h, d), wall, "shops", seed, 0.95, fade)
			if rng.randf() < 0.5:
				_roof(basis, p, y + h, Vector3(w + 0.2, 0.9, d + 0.2), roof)
			else:
				_plant(basis, p, y + h, w, d, rng)
		"office":
			var w := rng.randf_range(3.8, 4.6)
			var d := rng.randf_range(3.8, 4.6)
			var h := rng.randi_range(8, 18) * 0.95
			_wall(basis, p, y, Vector3(w, h, d), wall, "office", seed, 0.95, fade)
			# a setback crown on taller towers
			if h > 11.0:
				_wall(basis, p, y + h, Vector3(w * 0.7, 1.9, d * 0.7), wall.darkened(0.1), "office", seed + 3.0, 0.95, fade)
				h += 1.9
			_plant(basis, p, y + h, w * 0.6, d * 0.6, rng)
		"church":
			# a stone nave with a steep roof and a square tower with a spire
			var stone := Color(0.7, 0.66, 0.58)
			var w := 2.6
			var d := 5.0
			_wall(basis, p, y, Vector3(w, 1.9, d), stone, "house", seed, 1.9, fade)
			_roof(basis * Basis(Vector3.UP, PI / 2.0), p, y + 1.9, Vector3(d + 0.2, 1.6, w + 0.3), Color(0.32, 0.33, 0.36))
			var tp := basis * Vector3(0, 0, d * 0.5 + 0.7)
			var tc := p + Vector2(tp.x, tp.z)
			_wall(basis, tc, y, Vector3(1.4, 4.2, 1.4), stone.darkened(0.05), "house", seed + 2.0, 1.4, fade)
			units.append(Transform3D(basis.scaled(Vector3(0.9, 2.6, 0.9)), Vector3(tc.x, y + 5.5, tc.y)))
		"pub":
			# a corner pub: two storeys, a dark painted ground floor and a hanging sign
			var w := rng.randf_range(3.0, 3.6)
			var d := rng.randf_range(2.6, 3.0)
			_wall(basis, p, y, Vector3(w, 1.9, d), wall, "shops", seed, 0.95, fade)
			_roof(basis, p, y + 1.9, Vector3(w + 0.3, 0.9, d + 0.3), roof)
			var front := basis * Vector3(0, 0, d * 0.5 + 0.02)
			units.append(Transform3D(basis.scaled(Vector3(w, 0.9, 0.06)), Vector3(p.x + front.x, y + 0.45, p.y + front.z)))
			var sg := basis * Vector3(w * 0.5 + 0.15, 0, d * 0.5)
			units.append(Transform3D(basis.scaled(Vector3(0.05, 0.4, 0.3)), Vector3(p.x + sg.x, y + 1.3, p.y + sg.z)))
		"shed":
			var w := rng.randf_range(5.0, 8.0)
			var d := rng.randf_range(4.0, 6.0)
			var h := rng.randf_range(1.6, 2.4)
			_wall(basis, p, y, Vector3(w, h, d), wall, "shed", seed, h, fade)
			var nr := int(w / 2.0)
			for i in nr:
				var off := basis * Vector3((i - (nr - 1) / 2.0) * (w / nr), 0, 0)
				_roof(basis * Basis(Vector3.UP, PI / 2.0), p + Vector2(off.x, off.z), y + h, Vector3(d + 0.1, 0.6, w / nr + 0.05), Color(0.55, 0.57, 0.6))


func _wall(basis: Basis, p: Vector2, y: float, size: Vector3, col: Color, kind: String, seed: float, storey: float, fade: bool) -> void:
	walls.append(Transform3D(basis.scaled(size), Vector3(p.x, y, p.y)))
	wall_cols.append(col)
	wall_cust.append(Color(STYLE[kind], seed, storey, 1.0 if fade else 0.0))


## A pitched roof: ridge along the building's long side.
func _roof(basis: Basis, p: Vector2, y: float, size: Vector3, col: Color) -> void:
	var b := basis
	var s := size
	if size.x > size.z:
		b = basis * Basis(Vector3.UP, PI / 2.0)
		s = Vector3(size.z, size.y, size.x)
	roofs.append(Transform3D(b.scaled(s), Vector3(p.x, y, p.y)))
	roof_cols.append(col)


## Rooftop plant on a flat roof: air-handling boxes, a lift overrun.
func _plant(basis: Basis, p: Vector2, y: float, w: float, d: float, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(1, 3):
		var off := basis * Vector3(rng.randf_range(-w, w) * 0.3, 0, rng.randf_range(-d, d) * 0.3)
		var sz := Vector3(rng.randf_range(0.4, 0.9), rng.randf_range(0.25, 0.5), rng.randf_range(0.4, 0.8))
		units.append(Transform3D(basis.scaled(sz), Vector3(p.x + off.x, y + sz.y / 2.0, p.y + off.z)))


func build(parent: Node3D) -> void:
	_setup()
	_wall_mat.set_shader_parameter("night", 1.0 if night else 0.0)
	if not walls.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _box
		mm.instance_count = walls.size()
		for i in walls.size():
			mm.set_instance_transform(i, walls[i])
			mm.set_instance_color(i, wall_cols[i])
			mm.set_instance_custom_data(i, wall_cust[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _wall_mat
		parent.add_child(mi)
	if not roofs.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _prism
		mm.instance_count = roofs.size()
		for i in roofs.size():
			mm.set_instance_transform(i, roofs[i])
			mm.set_instance_color(i, roof_cols[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _roof_mat
		parent.add_child(mi)
	if not units.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = BoxMesh.new()
		mm.instance_count = units.size()
		for i in units.size():
			mm.set_instance_transform(i, units[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		var um := StandardMaterial3D.new()
		um.albedo_color = Color(0.55, 0.54, 0.52)
		um.roughness = 0.8
		mi.material_override = um
		parent.add_child(mi)


## Wisps of smoke from the chimneys (one particle system for the whole
## town, emitting from every chimney top). Hidden until winter.
func build_smoke(parent: Node3D) -> GPUParticles3D:
	if chimneys.is_empty():
		return null
	var n := chimneys.size()
	var img := Image.create(n, 1, false, Image.FORMAT_RGBF)
	for i in n:
		img.set_pixel(i, 0, Color(chimneys[i].x, chimneys[i].y, chimneys[i].z))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_texture = ImageTexture.create_from_image(img)
	pm.emission_point_count = n
	pm.direction = Vector3(0.3, 1, 0.1)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.45
	pm.gravity = Vector3(0.12, 0.05, 0.04)   # a light breeze carries it off
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.3))
	grow.add_point(Vector2(1, 1.6))
	var gt := CurveTexture.new()
	gt.curve = grow
	pm.scale_curve = gt
	var fade := Gradient.new()
	fade.set_color(0, Color(0.85, 0.85, 0.87, 0.0))
	fade.set_color(1, Color(0.85, 0.85, 0.87, 0.0))
	fade.add_point(0.15, Color(0.82, 0.82, 0.84, 0.35))
	fade.add_point(0.6, Color(0.8, 0.8, 0.82, 0.18))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _puff()
	quad.material = m
	var ps := GPUParticles3D.new()
	ps.process_material = pm
	ps.draw_pass_1 = quad
	ps.amount = mini(4000, n * 10)
	ps.lifetime = 7.0
	ps.preprocess = 7.0
	ps.visibility_aabb = AABB(Vector3(-600, -20, -600), Vector3(1200, 120, 1200))
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ps)
	return ps


static var _puff_tex: Texture2D


## A soft round puff.
static func _puff() -> Texture2D:
	if _puff_tex:
		return _puff_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 16.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 2))
	_puff_tex = ImageTexture.create_from_image(img)
	return _puff_tex


static func set_night(on: bool) -> void:
	_setup()
	_wall_mat.set_shader_parameter("night", 1.0 if on else 0.0)


static func _setup() -> void:
	if _wall_mat != null:
		return
	_wall_mat = ShaderMaterial.new()
	_wall_mat.shader = load("res://view/facade.gdshader")
	var nt := NoiseTexture2D.new()
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.08
	nt.noise = fn
	_wall_mat.set_shader_parameter("grain", nt)
	_roof_mat = ShaderMaterial.new()
	_roof_mat.shader = load("res://view/roof_tiles.gdshader")
	# unit box standing on y = 0
	var bm := BoxMesh.new()
	var arr := bm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i].y += 0.5
	arr[Mesh.ARRAY_VERTEX] = v
	_box = ArrayMesh.new()
	_box.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# gable roof, ridge along z, standing on y = 0
	var pm := PrismMesh.new()
	var parr := pm.get_mesh_arrays()
	var pv: PackedVector3Array = parr[Mesh.ARRAY_VERTEX]
	for i in pv.size():
		pv[i].y += 0.5
	parr[Mesh.ARRAY_VERTEX] = pv
	_prism = ArrayMesh.new()
	_prism.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, parr)
