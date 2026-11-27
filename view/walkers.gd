extends "res://view/traffic.gd"
## People out in the town: walkers on the pavements (both ways, at a stroll,
## bobbing as they go) and cyclists along the kerb. Same lane machinery as
## the cars; the meshes are simple figures made here.

const SHIRTS := [Color(0.75, 0.2, 0.2), Color(0.2, 0.35, 0.7), Color(0.9, 0.9, 0.88), Color(0.25, 0.25, 0.28), Color(0.85, 0.7, 0.25), Color(0.3, 0.55, 0.35), Color(0.55, 0.4, 0.6)]

var _people: Array = []     # [lane, distance, speed, bob phase, cyclist?]
var _body_mm: MultiMesh
var _head_mm: MultiMesh
var _bike_mm: MultiMesh
var _t := 0.0


## Pavement lanes either side of a street (and the kerb for bikes).
func add_pavement(a: Vector2, b: Vector2, height: Callable) -> void:
	add_street(a, b, height, 1.05)


func populate_people(count: int, seed: int) -> void:
	rng.seed = seed
	for c in get_children():
		c.queue_free()
	_people.clear()
	if lanes.is_empty():
		return
	for i in count:
		var lane := rng.randi_range(0, lanes.size() - 1)
		var cum: PackedFloat32Array = lanes[lane][1]
		var bike := rng.randf() < 0.15
		_people.append([lane, rng.randf() * cum[cum.size() - 1], rng.randf_range(1.2, 2.2) if bike else rng.randf_range(0.3, 0.45), rng.randf() * TAU, bike])
	var body := CapsuleMesh.new()
	body.radius = 0.055
	body.height = 0.36
	var head := SphereMesh.new()
	head.radius = 0.045
	head.height = 0.09
	var bike := BoxMesh.new()
	bike.size = Vector3(0.03, 0.14, 0.42)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.68, 0.55)
	var cloth := StandardMaterial3D.new()
	cloth.vertex_color_use_as_albedo = true
	cloth.roughness = 0.9
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.15, 0.15, 0.17)
	steel.metallic = 0.6
	_body_mm = _make_mm(body, cloth, _people.size(), true)
	_head_mm = _make_mm(head, skin, _people.size(), false)
	var bikes := 0
	for p in _people:
		if p[4]:
			bikes += 1
	_bike_mm = _make_mm(bike, steel, bikes, false)
	for i in _people.size():
		_body_mm.set_instance_color(i, SHIRTS[rng.randi_range(0, SHIRTS.size() - 1)])
	_update_people(0.0)


func _make_mm(mesh: Mesh, m: Material, n: int, colours: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colours
	mm.mesh = mesh
	mm.instance_count = n
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mm


func _process(delta: float) -> void:
	if visible and not _people.is_empty():
		_update_people(delta)


func _update_people(delta: float) -> void:
	_t += delta
	var b := 0
	for i in _people.size():
		var c: Array = _people[i]
		var lane: Array = lanes[c[0]]
		var pts: PackedVector3Array = lane[0]
		var cum: PackedFloat32Array = lane[1]
		var total := cum[cum.size() - 1]
		c[1] += c[2] * delta
		if c[1] >= total:
			c[0] = rng.randi_range(0, lanes.size() - 1)
			c[1] = 0.0
			lane = lanes[c[0]]
			pts = lane[0]
			cum = lane[1]
			total = cum[cum.size() - 1]
		var dist: float = c[1]
		var k := clampi(cum.bsearch(dist), 1, pts.size() - 1)
		var t := (dist - cum[k - 1]) / maxf(0.001, cum[k] - cum[k - 1])
		var p := pts[k - 1].lerp(pts[k], t)
		var dir := (pts[k] - pts[k - 1]).normalized()
		var side := Vector3(-dir.z, 0, dir.x)
		var edge := clampf(minf(dist, total - dist) / 0.5, 0.0, 1.0)
		var bike: bool = c[4]
		if bike:
			p -= side * 0.3   # out in the road by the kerb
		var basis := Basis.looking_at(-dir, Vector3.UP)
		var bob := 0.0 if bike else absf(sin(_t * 7.0 + float(c[3]))) * 0.015
		var y0 := 0.24 if bike else 0.18
		_body_mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * edge), p + Vector3(0, (y0 + bob) * edge, 0)))
		_head_mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * edge), p + Vector3(0, (y0 + 0.24 + bob) * edge, 0)))
		if bike:
			_bike_mm.set_instance_transform(b, Transform3D(basis.scaled(Vector3.ONE * edge), p + Vector3(0, 0.08 * edge, 0)))
			b += 1
