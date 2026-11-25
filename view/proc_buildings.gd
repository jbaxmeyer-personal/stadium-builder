extends RefCounted
## Procedural town buildings: walls are scaled unit boxes drawn by
## facade.gdshader (storeys, windows, shopfronts, curtain walls), with pitched
## tiled roofs, flat roofs with plant on top, chimneys and the odd porch.
## Collect buildings with add(), then build() makes a handful of MultiMeshes.

const STYLE := { "house": 0, "terrace": 0, "flats": 1, "shops": 2, "office": 3, "shed": 4 }

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
var night := false


## Adds a building of `kind` centred at p (ground height y), facing `yaw`.
## Returns its footprint radius so callers can space things.
func add(kind: String, p: Vector2, y: float, yaw: float, rng: RandomNumberGenerator, fade := false) -> void:
	var pal: Array = WALLS["house" if kind == "terrace" else kind]
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
