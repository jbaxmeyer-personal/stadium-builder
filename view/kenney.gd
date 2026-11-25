extends RefCounted
## Helpers for the Kenney (CC0) models in assets/kenney/.
## mesh(path) flattens a model's whole node tree into one ArrayMesh, so many
## copies can go into a MultiMesh. Its materials multiply by the instance colour,
## so copies can be tinted (e.g. white for snow, or a car's paint).

const ROOT := "res://assets/kenney/"

static var _cache := {}
static var _aabbs := {}


static func mesh(path: String, fade := false) -> ArrayMesh:
	var key := path + ("|fade" if fade else "")
	if _cache.has(key):
		return _cache[key]
	if fade:
		# a copy whose materials dissolve when the camera gets close, so tall
		# buildings never block the view of the ground
		var base := mesh(path)
		var m := base.duplicate() as ArrayMesh
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			if mat is BaseMaterial3D:
				var d: BaseMaterial3D = mat.duplicate()
				d.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
				d.distance_fade_min_distance = 35.0
				d.distance_fade_max_distance = 70.0
				m.surface_set_material(i, d)
		_cache[key] = m
		return m
	var scene: PackedScene = load(ROOT + path + ".glb")
	var out := ArrayMesh.new()
	if scene == null:
		push_warning("Kenney model missing: " + path)
		_cache[path] = out
		return out
	var root := scene.instantiate()
	_collect(root, Transform3D(), out)
	root.free()
	_cache[path] = out
	_aabbs[path] = out.get_aabb()
	return out


## Size of a model in its own units.
static func size(path: String) -> Vector3:
	mesh(path)
	return (_aabbs.get(path, AABB()) as AABB).size


## Uniform scale that makes the model `target` long in its longest horizontal side.
static func scale_to(path: String, target: float) -> float:
	var s := size(path)
	return target / maxf(0.001, maxf(s.x, s.z))


static func _collect(n: Node, xf: Transform3D, out: ArrayMesh) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		var m := mi.mesh
		for i in m.get_surface_count():
			var arrays := m.surface_get_arrays(i)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for k in verts.size():
				verts[k] = t * verts[k]
			arrays[Mesh.ARRAY_VERTEX] = verts
			if arrays[Mesh.ARRAY_NORMAL] != null:
				var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for k in norms.size():
					norms[k] = (t.basis * norms[k]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_TANGENT] = null
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mat: Material = mi.get_active_material(i)
			if mat is BaseMaterial3D:
				var d: BaseMaterial3D = mat.duplicate()
				d.vertex_color_use_as_albedo = true
				out.surface_set_material(out.get_surface_count() - 1, d)
	for c in n.get_children():
		_collect(c, t, out)


## A MultiMeshInstance3D of `path` at the given transforms (and optional tints).
static func batch(path: String, transforms: Array[Transform3D], colors: Array[Color] = [], fade := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh(path, fade)
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i] if i < colors.size() else Color.WHITE)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	return mi
