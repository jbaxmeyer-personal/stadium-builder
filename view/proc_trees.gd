extends RefCounted
## Procedural trees and bushes, generated once per kind and shared by every
## MultiMesh. A canopy is a cluster of lumpy, noise-displaced blobs with soft
## normals (so it lights like foliage, not facets), shaded by foliage.gdshader
## (leafy detail, ragged silhouette, translucency). Vertex colours carry the
## greens and fake ambient occlusion; the instance colour tints each tree.

const KINDS := ["proc/oak", "proc/lime", "proc/birch", "proc/poplar", "proc/fir", "proc/spruce", "proc/bush", "proc/far"]

static var _cache := {}
static var _mat: ShaderMaterial
static var _bark: StandardMaterial3D


static func mesh(kind: String) -> ArrayMesh:
	if _cache.has(kind):
		return _cache[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.6
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"proc/oak":
			_trunk(trunk, 0.0, 0.5, 0.07, 0.04, rng, 3)
			_crown(leaves, Vector3(0, 0.66, 0), Vector3(0.36, 0.3, 0.36), 9, 0.2, Color(0.27, 0.36, 0.14), rng, noise, 2)
		"proc/lime":
			_trunk(trunk, 0.0, 0.42, 0.06, 0.035, rng, 2)
			_crown(leaves, Vector3(0, 0.64, 0), Vector3(0.28, 0.34, 0.28), 8, 0.18, Color(0.3, 0.42, 0.16), rng, noise, 2)
		"proc/birch":
			_trunk(trunk, 0.0, 0.6, 0.035, 0.02, rng, 2, Color(0.82, 0.8, 0.74))
			_crown(leaves, Vector3(0, 0.68, 0), Vector3(0.22, 0.3, 0.22), 7, 0.14, Color(0.4, 0.5, 0.2), rng, noise, 2)
		"proc/poplar":
			_trunk(trunk, 0.0, 0.25, 0.04, 0.03, rng, 0)
			_crown(leaves, Vector3(0, 0.6, 0), Vector3(0.13, 0.4, 0.13), 7, 0.11, Color(0.28, 0.38, 0.15), rng, noise, 2)
		"proc/fir":
			_trunk(trunk, 0.0, 0.25, 0.04, 0.03, rng, 0)
			_cones(leaves, 0.12, 1.0, 0.3, 5, Color(0.2, 0.32, 0.19), rng, noise)
		"proc/spruce":
			_trunk(trunk, 0.0, 0.2, 0.035, 0.03, rng, 0)
			_cones(leaves, 0.08, 1.0, 0.22, 7, Color(0.17, 0.28, 0.18), rng, noise)
		"proc/bush":
			_crown(leaves, Vector3(0, 0.4, 0), Vector3(0.45, 0.32, 0.45), 6, 0.3, Color(0.27, 0.36, 0.15), rng, noise, 1)
		_:  # "proc/far": cheap, for the distant woodland
			_trunk(trunk, 0.0, 0.45, 0.06, 0.04, rng, 0)
			_crown(leaves, Vector3(0, 0.66, 0), Vector3(0.3, 0.3, 0.3), 4, 0.24, Color(0.26, 0.36, 0.15), rng, noise, 1)
	var out := ArrayMesh.new()
	leaves.commit(out)
	out.surface_set_material(0, material())
	trunk.generate_normals()
	trunk.commit(out)
	if out.get_surface_count() > 1:
		out.surface_set_material(1, bark())
	_cache[kind] = out
	return out


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://view/foliage.gdshader")
		var nt := NoiseTexture2D.new()
		nt.seamless = true
		nt.width = 256
		nt.height = 256
		var fn := FastNoiseLite.new()
		fn.frequency = 0.09
		fn.fractal_octaves = 3
		nt.noise = fn
		_mat.set_shader_parameter("leaf_noise", nt)
	return _mat


static func bark() -> StandardMaterial3D:
	if _bark == null:
		_bark = StandardMaterial3D.new()
		_bark.vertex_color_use_as_albedo = true
		_bark.roughness = 0.95
		_bark.vertex_color_is_srgb = true
		_bark.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _bark


## A tapered trunk from y0 to y1 with a few branches into the crown.
static func _trunk(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, rng: RandomNumberGenerator, branches: int, col := Color(0.3, 0.24, 0.18)) -> void:
	_tube(st, Vector3(0, y0, 0), Vector3(rng.randf_range(-0.02, 0.02), y1, rng.randf_range(-0.02, 0.02)), r0, r1, col)
	for b in branches:
		var a := rng.randf() * TAU
		var from := Vector3(0, y1 * rng.randf_range(0.7, 0.95), 0)
		var to := from + Vector3(cos(a) * 0.16, rng.randf_range(0.1, 0.2), sin(a) * 0.16)
		_tube(st, from, to, r1 * 0.8, r1 * 0.35, col)


static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, col: Color) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var up := axis.cross(side)
	var n := 6
	for i in n:
		var t0 := TAU * i / n
		var t1 := TAU * (i + 1) / n
		var d0 := side * cos(t0) + up * sin(t0)
		var d1 := side * cos(t1) + up * sin(t1)
		var p := [a + d0 * ra, a + d1 * ra, b + d1 * rb, b + d0 * rb]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_color(col.darkened(0.15 * float(k % 2)))
			st.add_vertex(p[k])


## A crown of `puffs` lumpy blobs filling an ellipsoid of radii `size` around `c`.
static func _crown(st: SurfaceTool, c: Vector3, size: Vector3, puffs: int, puff_r: float, col: Color,
		rng: RandomNumberGenerator, noise: FastNoiseLite, detail: int) -> void:
	var centres: Array[Vector3] = [c + Vector3(0, size.y * 0.15, 0)]
	for i in puffs - 1:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.45, 0.85)
		centres.append(c + d * size)
	var bottom := c.y - size.y
	var top := c.y + size.y + puff_r
	for pc in centres:
		var r := puff_r * rng.randf_range(0.8, 1.2)
		var sph := _icosphere(detail)
		var tris: PackedVector3Array = sph
		for i in tris.size():
			var dir: Vector3 = tris[i]
			var p := pc + dir * r
			p += dir * r * 0.35 * noise.get_noise_3dv(p * 3.0)
			# soft normals: mostly away from the crown's centre
			var n := ((p - c) / size).normalized().lerp(dir, 0.35).normalized()
			# fake AO: darker low down and deep inside the crown
			var h := clampf((p.y - bottom) / (top - bottom), 0.0, 1.0)
			var outer := clampf(((p - c) / size).length(), 0.0, 1.2)
			var shade := lerpf(0.6, 1.12, h) * lerpf(0.78, 1.0, outer)
			var tint := col.lerp(Color(col.r * 1.15, col.g * 1.1, col.b * 0.8), noise.get_noise_3dv(pc * 0.7) * 0.5 + 0.5)
			st.set_color(Color(tint.r * shade, tint.g * shade, tint.b * shade))
			st.set_normal(n)
			st.add_vertex(p)


## Stacked drooping cones for conifers, from y0 to y1, base radius r.
static func _cones(st: SurfaceTool, y0: float, y1: float, r: float, tiers: int, col: Color, rng: RandomNumberGenerator, noise: FastNoiseLite) -> void:
	var segs := 10
	for t in tiers:
		var f := float(t) / tiers
		var base_y := lerpf(y0, y1 * 0.78, f)
		var tip_y := base_y + (y1 - y0) * 0.38
		var rad := r * (1.0 - f * 0.78)
		var shade := lerpf(0.6, 1.0, f)
		var rot := rng.randf() * TAU
		for i in segs:
			var a0 := rot + TAU * i / segs
			var a1 := rot + TAU * (i + 1) / segs
			var am := (a0 + a1) / 2.0
			var j0 := rad * (1.0 + 0.25 * noise.get_noise_2d(a0 * 3.0, t * 5.0))
			var j1 := rad * (1.0 + 0.25 * noise.get_noise_2d(a1 * 3.0, t * 5.0))
			var p0 := Vector3(cos(a0) * j0, base_y - 0.03, sin(a0) * j0)
			var p1 := Vector3(cos(a1) * j1, base_y - 0.03, sin(a1) * j1)
			var pm := Vector3(cos(am) * rad * 0.55, base_y + 0.05, sin(am) * rad * 0.55)
			var tip := Vector3(0, tip_y, 0)
			for tri in [[p0, p1, tip], [p0, pm, p1]]:
				for v in tri:
					var vv: Vector3 = v
					var n := Vector3(vv.x, rad * 0.9, vv.z).normalized()
					var s := shade * (0.8 if vv == tip else 1.0)
					st.set_color(Color(col.r * s, col.g * s, col.b * s))
					st.set_normal(n)
					st.add_vertex(vv)


static var _ico := {}


## Unit icosphere as a flat triangle list (each vertex is also its direction).
static func _icosphere(detail: int) -> PackedVector3Array:
	if _ico.has(detail):
		return _ico[detail]
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var f := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var tris := []
	for tri in f:
		tris.append([v[tri[0]].normalized(), v[tri[1]].normalized(), v[tri[2]].normalized()])
	for d in detail:
		var next := []
		for tri in tris:
			var a: Vector3 = tri[0]
			var b: Vector3 = tri[1]
			var c: Vector3 = tri[2]
			var ab := ((a + b) / 2.0).normalized()
			var bc := ((b + c) / 2.0).normalized()
			var ca := ((c + a) / 2.0).normalized()
			next.append_array([[a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]])
		tris = next
	var out := PackedVector3Array()
	for tri in tris:
		# Godot's front faces wind clockwise seen from outside
		out.append(tri[0])
		out.append(tri[2])
		out.append(tri[1])
	_ico[detail] = out
	return out
