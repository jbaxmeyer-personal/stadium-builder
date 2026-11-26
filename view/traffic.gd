extends Node3D
## Cars driving the town's streets. Each street is a lane polyline (heights
## baked from the terrain); cars run along their lane, slow to turn off near
## the ends (they shrink away at a junction) and reappear at the start of
## another lane. One MultiMesh per car model, updated every frame.

const Kenney := preload("res://view/kenney.gd")
const KINDS := ["car-kit/sedan", "car-kit/suv", "car-kit/hatchback-sports", "car-kit/van", "car-kit/taxi", "car-kit/delivery", "car-kit/sedan-sports"]
const TINTS := [Color(1, 1, 1), Color(0.55, 0.6, 0.7), Color(0.25, 0.25, 0.28), Color(0.85, 0.85, 0.85), Color(0.6, 0.15, 0.12), Color(0.2, 0.3, 0.55)]

var lanes: Array = []          # [PackedVector3Array points, PackedFloat32Array cumulative length]
var cars: Array = []           # [kind index, lane, distance, speed]
var _mms: Array[MultiMesh] = []
var _slots: Array = []         # per kind: car indices
var _scale := 1.0
var rng := RandomNumberGenerator.new()


## A street centre line from a to b; two lanes either side, opposite ways.
func add_street(a: Vector2, b: Vector2, height: Callable, offset := 0.45) -> void:
	var d := (b - a)
	var n := Vector2(-d.y, d.x).normalized() * offset
	for side in [1.0, -1.0]:
		var pa: Vector2 = a + n * side if side > 0 else b + n * side
		var pb: Vector2 = b + n * side if side > 0 else a + n * side
		var steps := maxi(2, int(pa.distance_to(pb) / 1.0))
		var pts := PackedVector3Array()
		var cum := PackedFloat32Array()
		var acc := 0.0
		for i in steps + 1:
			var q := pa.lerp(pb, float(i) / steps)
			var p3 := Vector3(q.x, float(height.call(q.x, q.y)) + 0.07, q.y)
			if i > 0:
				acc += p3.distance_to(pts[i - 1])
			pts.append(p3)
			cum.append(acc)
		lanes.append([pts, cum])


func populate(count: int, seed: int) -> void:
	rng.seed = seed
	for m in _mms:
		pass
	for c in get_children():
		c.queue_free()
	_mms.clear()
	_slots.clear()
	cars.clear()
	if lanes.is_empty():
		return
	_scale = Kenney.scale_to(KINDS[0], 1.15)
	for k in KINDS.size():
		_slots.append([])
	for i in count:
		var kind := rng.randi_range(0, KINDS.size() - 1)
		var lane := rng.randi_range(0, lanes.size() - 1)
		var cum: PackedFloat32Array = lanes[lane][1]
		cars.append([kind, lane, rng.randf() * cum[cum.size() - 1], rng.randf_range(2.2, 3.6)])
		_slots[kind].append(i)
	for k in KINDS.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = Kenney.mesh(KINDS[k])
		mm.instance_count = _slots[k].size()
		for j in _slots[k].size():
			mm.set_instance_color(j, TINTS[rng.randi_range(0, TINTS.size() - 1)])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		add_child(mi)
		_mms.append(mm)
	_update(0.0)


func _process(delta: float) -> void:
	if visible and not cars.is_empty():
		_update(delta)


func _update(delta: float) -> void:
	for k in _slots.size():
		var mm := _mms[k]
		var list: Array = _slots[k]
		for j in list.size():
			var c: Array = cars[list[j]]
			var lane: Array = lanes[c[1]]
			var pts: PackedVector3Array = lane[0]
			var cum: PackedFloat32Array = lane[1]
			var total := cum[cum.size() - 1]
			c[2] += c[3] * delta
			if c[2] >= total:
				c[1] = rng.randi_range(0, lanes.size() - 1)
				c[2] = 0.0
				lane = lanes[c[1]]
				pts = lane[0]
				cum = lane[1]
				total = cum[cum.size() - 1]
			var dist: float = c[2]
			var i := cum.bsearch(dist)
			i = clampi(i, 1, pts.size() - 1)
			var t := (dist - cum[i - 1]) / maxf(0.001, cum[i] - cum[i - 1])
			var p := pts[i - 1].lerp(pts[i], t)
			var dir := (pts[i] - pts[i - 1]).normalized()
			# shrink away / grow in at the ends, as if turning at a junction
			var edge := clampf(minf(dist, total - dist) / 0.8, 0.0, 1.0)
			var sc := _scale * edge
			var basis := Basis.looking_at(-dir, Vector3.UP).scaled(Vector3(sc, sc, sc))
			mm.set_instance_transform(j, Transform3D(basis, p))
