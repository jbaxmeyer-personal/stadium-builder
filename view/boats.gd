extends Node3D
## Boats on the river: narrowboats, launches and the odd barge, cruising up
## and down either side of the channel and turning round out of sight.

var river_z: Callable          # x -> z of the river's centre line
var x0 := 0.0
var x1 := 0.0
var water_y := 0.0
var _boats: Array = []         # [node, x, speed (signed), lane offset]


func populate(count: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in count:
		var dir := 1.0 if i % 2 == 0 else -1.0
		var node := _boat(rng)
		add_child(node)
		_boats.append([node, rng.randf_range(x0, x1), dir * rng.randf_range(1.0, 2.2), -dir * rng.randf_range(1.8, 3.0)])
	_update(0.0)


func _boat(rng: RandomNumberGenerator) -> Node3D:
	var g := Node3D.new()
	var kind := rng.randi_range(0, 2)
	var hull_c := [Color(0.12, 0.3, 0.2), Color(0.55, 0.12, 0.12), Color(0.12, 0.18, 0.4), Color(0.85, 0.85, 0.82)][rng.randi_range(0, 3)] as Color
	var length := [4.0, 2.2, 6.5][kind] as float
	var width := [0.6, 0.8, 1.3][kind] as float
	_part(g, Vector3(0, 0.12, 0), Vector3(width, 0.3, length), hull_c, 0.5)
	# a pointed bow
	var bow := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(width, length * 0.12, 0.3)
	bow.mesh = pm
	bow.rotation = Vector3(-PI / 2.0, 0, 0)
	bow.position = Vector3(0, 0.12, length / 2.0 + length * 0.06)
	bow.material_override = _mat(hull_c, 0.5)
	g.add_child(bow)
	match kind:
		0:
			# narrowboat: a long cabin with a roof line and windows
			_part(g, Vector3(0, 0.42, -0.2), Vector3(width * 0.85, 0.32, length * 0.7), Color(0.9, 0.86, 0.72), 0.6)
			_part(g, Vector3(0, 0.6, -0.2), Vector3(width * 0.9, 0.04, length * 0.72), hull_c.darkened(0.2), 0.6)
			for k in 5:
				_part(g, Vector3(width * 0.43, 0.45, -0.2 - length * 0.3 + k * length * 0.15), Vector3(0.02, 0.1, 0.18), Color(0.15, 0.2, 0.25), 0.1)
		1:
			# a little launch: a windscreen and a canopy
			_part(g, Vector3(0, 0.38, 0.1), Vector3(width * 0.8, 0.2, 0.05), Color(0.6, 0.75, 0.85), 0.05)
			_part(g, Vector3(0, 0.62, -0.4), Vector3(width * 0.85, 0.03, 0.9), Color(0.92, 0.92, 0.9), 0.6)
		2:
			# a working barge: a long low hold and a wheelhouse at the stern
			_part(g, Vector3(0, 0.3, 0.4), Vector3(width * 0.9, 0.12, length * 0.6), Color(0.3, 0.28, 0.25), 0.9)
			_part(g, Vector3(0, 0.55, -length * 0.38), Vector3(width * 0.7, 0.55, 0.9), Color(0.92, 0.9, 0.85), 0.6)
			_part(g, Vector3(0, 0.62, -length * 0.38 + 0.46), Vector3(width * 0.6, 0.15, 0.02), Color(0.15, 0.2, 0.25), 0.1)
	return g


func _part(g: Node3D, at: Vector3, size: Vector3, c: Color, rough: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	mi.material_override = _mat(c, rough)
	g.add_child(mi)


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _process(delta: float) -> void:
	if visible:
		_update(delta)


func _update(delta: float) -> void:
	for b in _boats:
		var x: float = b[1] + float(b[2]) * delta
		if x > x1:
			x = x0
		elif x < x0:
			x = x1
		b[1] = x
		var z := float(river_z.call(x)) + float(b[3])
		var ahead := float(river_z.call(x + signf(b[2]) * 1.0)) + float(b[3])
		var node: Node3D = b[0]
		node.position = Vector3(x, water_y + sin(Time.get_ticks_msec() * 0.002 + x) * 0.02, z)
		node.rotation.y = atan2(signf(b[2]) * 1.0, ahead - z)
