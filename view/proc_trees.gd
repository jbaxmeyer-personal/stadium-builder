extends RefCounted
## Procedural trees, built the way game trees are: a tapered trunk with real
## branches, and a crown of leaf-cluster cards (textured quads with cut-out
## edges) placed along the branch tips. Card normals point out from the crown,
## so it lights as one soft volume while the cut-outs give a ragged, leafy
## silhouette. The leaf and needle textures are painted procedurally once
## (no assets needed). Meshes are ~1 unit tall and shared by every MultiMesh;
## the instance colour tints each tree.

const KINDS := ["proc/oak", "proc/lime", "proc/birch", "proc/poplar", "proc/fir", "proc/spruce", "proc/bush", "proc/far"]

static var _cache := {}
static var _mat: ShaderMaterial        # blob foliage (hedges)
static var _card_mat: ShaderMaterial   # leaf cards
static var _bark: StandardMaterial3D
static var _atlas: ImageTexture


static func mesh(kind: String) -> ArrayMesh:
	if _cache.has(kind):
		return _cache[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark := Color(0.36, 0.32, 0.27)
	match kind:
		"proc/oak":
			_broadleaf(leaves, wood, rng, 0.36, Vector3(0.36, 0.32, 0.36), 0.62, 5, 230, 0.17, Color(0.42, 0.52, 0.24), bark)
		"proc/lime":
			_broadleaf(leaves, wood, rng, 0.32, Vector3(0.27, 0.38, 0.27), 0.6, 5, 210, 0.15, Color(0.46, 0.58, 0.26), bark)
		"proc/birch":
			_broadleaf(leaves, wood, rng, 0.5, Vector3(0.2, 0.32, 0.2), 0.62, 4, 150, 0.12, Color(0.55, 0.64, 0.3), Color(0.85, 0.83, 0.78))
		"proc/poplar":
			_broadleaf(leaves, wood, rng, 0.2, Vector3(0.12, 0.44, 0.12), 0.56, 6, 150, 0.1, Color(0.42, 0.54, 0.24), bark)
		"proc/fir":
			_conifer(leaves, wood, rng, 0.28, 10, Color(0.3, 0.42, 0.26), bark)
		"proc/spruce":
			_conifer(leaves, wood, rng, 0.21, 13, Color(0.24, 0.36, 0.24), bark)
		"proc/bush":
			_crown_cards(leaves, rng, Vector3(0, 0.38, 0), Vector3(0.45, 0.33, 0.45), [], 70, 0.28, Color(0.4, 0.5, 0.24), 0)
		_:  # "proc/far": cheap, for the distant woodland
			_tube(wood, Vector3.ZERO, Vector3(0, 0.45, 0), 0.05, 0.03, bark, 5)
			_crown_cards(leaves, rng, Vector3(0, 0.66, 0), Vector3(0.32, 0.3, 0.32), [], 34, 0.26, Color(0.42, 0.52, 0.24), 0)
	var out := ArrayMesh.new()
	leaves.commit(out)
	out.surface_set_material(0, card_material())
	wood.generate_normals()
	wood.commit(out)
	if out.get_surface_count() > 1:
		out.surface_set_material(1, bark_material())
	_cache[kind] = out
	return out


## A deciduous tree: trunk to `split`, a few main limbs forking into the crown,
## leaf cards clustered around the limb tips and filling the crown's shell.
static func _broadleaf(leaves: SurfaceTool, wood: SurfaceTool, rng: RandomNumberGenerator, split: float, crown: Vector3,
		crown_y: float, limbs: int, cards: int, card: float, green: Color, bark: Color) -> void:
	var base := Vector3(rng.randf_range(-0.01, 0.01), split, rng.randf_range(-0.01, 0.01))
	_tube(wood, Vector3.ZERO, base, 0.038, 0.028, bark, 7)
	var c := Vector3(0, crown_y, 0)
	var tips: Array[Vector3] = []
	for i in limbs:
		var a := TAU * i / limbs + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), 0, sin(a))
		var mid := base + dir * crown.x * 0.45 + Vector3(0, (c.y - base.y) * 0.6 + crown.y * rng.randf_range(0.0, 0.5), 0)
		_tube(wood, base, mid, 0.022, 0.013, bark, 5)
		for k in 2:
			var b := a + rng.randf_range(-0.6, 0.6)
			var tip := c + Vector3(cos(b) * crown.x * rng.randf_range(0.55, 0.9), crown.y * rng.randf_range(-0.2, 0.75), sin(b) * crown.z * rng.randf_range(0.55, 0.9))
			_tube(wood, mid, tip, 0.016, 0.006, bark, 4)
			tips.append(tip)
	# a leader up the middle
	var top := c + Vector3(0, crown.y * 0.8, 0)
	_tube(wood, base, top, 0.03, 0.008, bark, 5)
	tips.append(top)
	_crown_cards(leaves, rng, c, crown, tips, cards, card, green, 0)


## Leaf cards: most hug the branch tips, the rest fill the crown's outer shell.
static func _crown_cards(st: SurfaceTool, rng: RandomNumberGenerator, c: Vector3, crown: Vector3, tips: Array[Vector3],
		count: int, size: float, green: Color, cell: int) -> void:
	for i in count:
		var p: Vector3
		if not tips.is_empty() and rng.randf() < 0.55:
			var t: Vector3 = tips[rng.randi_range(0, tips.size() - 1)]
			p = t + Vector3(rng.randfn(0, 1), rng.randfn(0, 1), rng.randfn(0, 1)) * size * 0.6
		else:
			var d := Vector3(rng.randfn(0, 1), rng.randfn(0, 1) * 0.8 + 0.15, rng.randfn(0, 1)).normalized()
			p = c + d * crown * rng.randf_range(0.6, 1.0)
		var out := ((p - c) / crown)
		var n := out.normalized() if out.length() > 0.01 else Vector3.UP
		# shade: darker low and deep inside, lighter on top and outside
		var shade := clampf(0.55 + 0.35 * (out.y * 0.5 + 0.5) + 0.25 * clampf(out.length(), 0.0, 1.0), 0.4, 1.15)
		var tint := green.lerp(Color(green.r * 1.25, green.g * 1.15, green.b * 0.8), rng.randf())
		_card(st, p, size * rng.randf_range(0.8, 1.25), rng, n, Color(tint.r * shade, tint.g * shade, tint.b * shade), cell)


## A conifer: a straight trunk with tiers of drooping needle sprays.
static func _conifer(leaves: SurfaceTool, wood: SurfaceTool, rng: RandomNumberGenerator, radius: float, tiers: int, green: Color, bark: Color) -> void:
	_tube(wood, Vector3.ZERO, Vector3(0, 0.98, 0), 0.04, 0.008, bark, 6)
	for t in tiers:
		var f := float(t) / tiers
		var y := lerpf(0.14, 0.95, f)
		var r := radius * (1.0 - f * 0.9) + 0.02
		var n := maxi(4, int(10 * (1.0 - f)) + 3)
		var rot := rng.randf() * TAU
		for i in n:
			var a := rot + TAU * i / n
			var dir := Vector3(cos(a), 0, sin(a))
			var p := Vector3(0, y, 0) + dir * r * 0.55 + Vector3(0, -r * 0.18, 0)
			var shade := lerpf(0.6, 1.08, f) * rng.randf_range(0.9, 1.05)
			var col := Color(green.r * shade, green.g * shade, green.b * shade)
			# the spray lies along the branch, drooping out and down
			var along := (dir + Vector3(0, -0.35, 0)).normalized()
			var side := along.cross(Vector3.UP).normalized()
			_card_axes(leaves, p, along * r * 1.1, side * r * 0.55, (dir + Vector3(0, 0.6, 0)).normalized(), col, 1)
	# a tuft on top
	_card_axes(leaves, Vector3(0, 0.97, 0), Vector3(0, 0.08, 0), Vector3(0.04, 0, 0), Vector3.UP, green, 1)


## A camera-agnostic card: a quad of `size` at p, randomly turned.
static func _card(st: SurfaceTool, p: Vector3, size: float, rng: RandomNumberGenerator, n: Vector3, col: Color, cell: int) -> void:
	var a := Vector3(rng.randfn(0, 1), rng.randfn(0, 1), rng.randfn(0, 1)).normalized()
	var u := a.cross(n)
	if u.length() < 0.1:
		u = Vector3.RIGHT
	u = u.normalized() * size * 0.5
	var v := n.cross(u).normalized() * size * 0.5
	# tilt the card part-way toward the outward normal so it isn't edge-on to the light
	_card_axes(st, p, u, v.lerp(n * size * 0.5, 0.3), n, col, cell)


static func _card_axes(st: SurfaceTool, p: Vector3, u: Vector3, v: Vector3, n: Vector3, col: Color, cell: int) -> void:
	var u0 := 0.5 * cell
	var corners := [p - u - v, p + u - v, p + u + v, p - u + v]
	var uvs := [Vector2(u0, 1), Vector2(u0 + 0.5, 1), Vector2(u0 + 0.5, 0), Vector2(u0, 0)]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(uvs[k])
		st.add_vertex(corners[k])


static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, col: Color, sides: int) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var up := axis.cross(side)
	for i in sides:
		var t0 := TAU * i / sides
		var t1 := TAU * (i + 1) / sides
		var d0 := side * cos(t0) + up * sin(t0)
		var d1 := side * cos(t1) + up * sin(t1)
		var p := [a + d0 * ra, a + d1 * ra, b + d1 * rb, b + d0 * rb]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.add_vertex(p[k])


# --- materials and the painted leaf atlas ---------------------------------------------

static func card_material() -> ShaderMaterial:
	if _card_mat == null:
		_card_mat = ShaderMaterial.new()
		_card_mat.shader = load("res://view/leaf_cards.gdshader")
		_card_mat.set_shader_parameter("leaves", atlas())
	return _card_mat


## Two cells, 256 px each: a cluster of broad leaves, and a spray of needles.
static func atlas() -> ImageTexture:
	if _atlas != null:
		return _atlas
	var w := 256
	var img := Image.create(w * 2, w, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.22, 0.3, 0.12, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	# broad leaves: overlapping ellipses with a midrib and a lit edge
	for i in 170:
		var r := sqrt(rng.randf()) * 104.0
		var a := rng.randf() * TAU
		var c := Vector2(128, 128) + Vector2(cos(a), sin(a)) * r
		var ang := a + rng.randf_range(-0.8, 0.8)
		_leaf(img, c, rng.randf_range(11, 18), rng.randf_range(5, 8), ang, rng.randf_range(0.75, 1.15), rng, 0)
	# needles: thin strokes along a few twigs
	for t in 7:
		var a := -PI / 2.0 + rng.randf_range(-0.9, 0.9)
		var start := Vector2(128, 240)
		for s in 40:
			var k := float(s) / 40.0
			var p := start + Vector2(cos(a), sin(a)) * k * 220.0
			for side in [-1, 1]:
				_leaf(img, p + Vector2(cos(a + side * 1.1), sin(a + side * 1.1)) * 9.0, 10.0, 1.4, a + side * 1.0, rng.randf_range(0.8, 1.1), rng, w)
	img.generate_mipmaps()
	_atlas = ImageTexture.create_from_image(img)
	return _atlas


static func _leaf(img: Image, c: Vector2, a: float, b: float, ang: float, light: float, rng: RandomNumberGenerator, x_off: int) -> void:
	var ca := cos(ang)
	var sa := sin(ang)
	var ext := int(a) + 2
	var base := Color(0.3, 0.42, 0.16).lerp(Color(0.45, 0.55, 0.2), rng.randf()) * light
	for y in range(int(c.y) - ext, int(c.y) + ext + 1):
		for x in range(int(c.x) - ext, int(c.x) + ext + 1):
			if x < 0 or y < 0 or x >= 256 or y >= 256:
				continue
			var d := Vector2(x, y) - c
			var lx := d.x * ca + d.y * sa
			var ly := -d.x * sa + d.y * ca
			var e := (lx * lx) / (a * a) + (ly * ly) / (b * b)
			if e > 1.0:
				continue
			# lit on one side of the midrib, a darker rib, a soft rim
			var col := base * (1.08 if ly < 0.0 else 0.88)
			if absf(ly) < 0.7:
				col = col * 0.8
			col = col * lerpf(1.0, 0.82, e)
			col.a = 1.0
			img.set_pixel(x + x_off, y, col)


static func bark_material() -> StandardMaterial3D:
	if _bark == null:
		_bark = StandardMaterial3D.new()
		_bark.vertex_color_use_as_albedo = true
		_bark.vertex_color_is_srgb = true
		_bark.roughness = 0.95
		_bark.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _bark


## Blob foliage, used for clipped hedges.
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
