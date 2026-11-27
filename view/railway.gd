extends Node3D
## A railway line across the countryside: ballast, sleepers and two rails
## following the land, and trains passing through every so often (both ways).

const Kenney := preload("res://view/kenney.gd")

var height: Callable          # (x, z) -> ground height
var z := 0.0                  # the line runs along x at this z
var x0 := 0.0
var x1 := 0.0
var _trains: Array = []       # [node, x, speed (signed), cars]
var _car_len := 2.9


func build(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var ballast := StandardMaterial3D.new()
	ballast.albedo_color = Color(0.45, 0.42, 0.38)
	ballast.roughness = 1.0
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.5, 0.48, 0.46)
	steel.metallic = 0.8
	steel.roughness = 0.35
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.25, 0.2)
	wood.roughness = 0.9
	for track in [-0.75, 0.75]:
		var zz: float = z + track
		_strip(zz, 0.75, 0.05, ballast)
		for rail in [-0.25, 0.25]:
			_strip(zz + rail, 0.035, 0.16, steel)
		var sleepers: Array[Transform3D] = []
		var x := x0
		while x < x1:
			sleepers.append(Transform3D(Basis().scaled(Vector3(0.12, 0.05, 0.7)), Vector3(x, _h(x, zz) + 0.09, zz)))
			x += 0.55
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = BoxMesh.new()
		mm.instance_count = sleepers.size()
		for i in sleepers.size():
			mm.set_instance_transform(i, sleepers[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = wood
		add_child(mi)
	# two trains, one each way
	_car_len = 2.9
	for dir in [1.0, -1.0]:
		var n := rng.randi_range(4, 7)
		var node := Node3D.new()
		var sc := Kenney.scale_to("train-kit/train-electric-city-a", _car_len)
		var cars: Array[Transform3D] = []
		for k in n:
			cars.append(Transform3D(Basis(Vector3.UP, PI / 2.0 if dir > 0 else -PI / 2.0).scaled(Vector3(sc, sc, sc)), Vector3(-dir * k * (_car_len + 0.05), 0, 0)))
		node.add_child(Kenney.batch("train-kit/train-electric-city-a", cars))
		add_child(node)
		_trains.append([node, x0 + rng.randf() * (x1 - x0), dir * rng.randf_range(9.0, 14.0), n, z + (0.75 if dir > 0 else -0.75)])


## The ground under the line, smoothed a little (railways don't follow every bump).
func _h(x: float, zz: float) -> float:
	return (float(height.call(x - 3.0, zz)) + float(height.call(x, zz)) * 2.0 + float(height.call(x + 3.0, zz))) / 4.0


## A strip along the line (ballast or a rail) following the ground.
func _strip(zz: float, half: float, top: float, m: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x := x0
	while x < x1:
		var xb := minf(x + 2.0, x1)
		var ya := _h(x, zz) + top
		var yb := _h(xb, zz) + top
		var q := [Vector3(x, ya, zz - half), Vector3(xb, yb, zz - half), Vector3(xb, yb, zz + half), Vector3(x, ya, zz + half),
			Vector3(x, ya - top - 0.1, zz - half - 0.3), Vector3(xb, yb - top - 0.1, zz - half - 0.3), Vector3(xb, yb - top - 0.1, zz + half + 0.3), Vector3(x, ya - top - 0.1, zz + half + 0.3)]
		for t in [[0, 1, 2], [0, 2, 3], [4, 5, 1], [4, 1, 0], [3, 2, 6], [3, 6, 7]]:
			for k in t:
				st.add_vertex(q[k])
		x = xb
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	add_child(mi)


func _process(delta: float) -> void:
	if not visible:
		return
	for t in _trains:
		var x: float = t[1] + float(t[2]) * delta
		var span := float(t[3]) * (_car_len + 0.05) + 20.0
		if x > x1 + span:
			x = x0 - span
		elif x < x0 - span:
			x = x1 + span
		t[1] = x
		var node: Node3D = t[0]
		var zz: float = t[4]
		node.position = Vector3(x, _h(x, zz) + 0.14, zz)
