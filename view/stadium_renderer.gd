extends Node3D
## Builds the 3D stadium from sim state. Read-only on the sim.
## World units: 1 unit = 1 tile. Tile (x, y) covers [x, x+1] x [y, y+1] in X/Z.

const Kenney := preload("res://view/kenney.gd")
const ProcTrees := preload("res://view/proc_trees.gd")
const ProcBuildings := preload("res://view/proc_buildings.gd")
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
# Layer groups
var _ground: Node3D
var _pitch_node: Node3D
var _pitch_ghost: Node3D
var _lights: Node3D
var _trees: Node3D
var _solids: Node3D       # stands as built
var _ghosts: Node3D       # see-through stand outlines for the concourse / underground views
var _concourse: Node3D    # paving + concourse facilities
var _bowl: Node3D
var _outside: Node3D
var _under: Node3D        # underground floor + items
var _markers: Node3D      # surface entrances of underground items
var _offers: Node3D       # land for sale
var _spots: Array[SpotLight3D] = []
var layer := "stadium"
var level := 0
var _levels := {}         # level -> Node3D (concourse paving/decks + items on that level)
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
	for g in ["_ground", "_pitch_node", "_pitch_ghost", "_lights", "_trees"]:
		var n := Node3D.new()
		_static.add_child(n)
		set(g, n)
	for g in ["_solids", "_ghosts", "_concourse", "_bowl", "_outside", "_under", "_markers", "_offers"]:
		var n := Node3D.new()
		_stands.add_child(n)
		set(g, n)
	_overlay = Node3D.new()
	add_child(_overlay)
	_crowd = MultiMeshInstance3D.new()
	add_child(_crowd)
	_display = load("res://view/crowd_display.gd").new(self)
	add_child(_display)
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
	m.metallic_specular = 0.3 if metal < 0.3 else 0.5
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


const TEX_DIR := "res://assets/polyhaven/"


## A Poly Haven (CC0) PBR material, mapped in world space so any box or
## generated mesh gets real-world-sized texture with no UV work.
## `tiles` = metres (tiles) per texture repeat.
func tex_mat(name: String, tint := Color.WHITE, tiles := 4.0, normal_only := false) -> StandardMaterial3D:
	var key := "tex|%s|%s|%s|%s" % [name, tint.to_html(), tiles, normal_only]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	if not normal_only:
		m.albedo_texture = load(TEX_DIR + name + "/diff.jpg")
	m.normal_enabled = true
	m.normal_texture = load(TEX_DIR + name + "/nor.jpg")
	m.normal_scale = 0.6 if name == "rough_concrete" else 1.0
	m.roughness_texture = load(TEX_DIR + name + "/rough.jpg")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tiles
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
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
	return stand_top(s) + ROOF_CLEARANCE + 0.6


const TIER_GAP := 2.3        # headroom between a tier's rows and the tier above
const DECK_DROP := 1.6       # an upper concourse deck sits this far below its tier


## Height of the front row base of tier k (0 = ground tier).
static func tier_base(s: Stand, k: int) -> float:
	if k <= 0:
		return 0.0
	return tier_base(s, k - 1) + row_height(s.depth / 2) + TIER_GAP


static func tier_front(s: Stand, k: int) -> int:
	return s.tier_front(k)


## Top of the highest tier's back row.
static func stand_top(s: Stand) -> float:
	return tier_base(s, s.tiers - 1) + row_height(s.depth - 1)


## Height of the concourse floor for a level of this stand.
static func deck_y(s: Stand, level: int) -> float:
	return 0.05 if level <= 0 else tier_base(s, level) - DECK_DROP


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
	for g in [_ground, _pitch_node, _pitch_ghost, _lights, _trees]:
		for c in g.get_children():
			c.queue_free()
	var pl := Rect2(layout.plot)
	_setup_terrain(layout)
	_build_terrain(layout)
	_build_horizon(layout)
	box(_ground, Vector3(pl.position.x, -0.01, pl.position.y), Vector3(pl.end.x, 0.0, pl.end.y), tex_mat("square_concrete_pavers", Color(1.05, 1.25, 1.5), 2.5), false)
	var pr := layout.pitch
	box(_pitch_ghost, Vector3(pr.position.x, 0, pr.position.y), Vector3(pr.end.x, 0.02, pr.end.y), mat(C_PITCH_B, 1.0, 0.0, 0.0, 0.25), false)
	_rect_outline(_pitch_ghost, pl, 0.02, mat(Color(0.9, 0.9, 0.9), 1.0, 0.0, 0.0, 0.5))
	_build_pitch(layout.pitch)
	_build_streetlights(layout)
	_build_pitchside(layout.pitch)
	_build_trees(layout)


func _build_pitch(p: Rect2i) -> void:
	var x0 := float(p.position.x)
	var z0 := float(p.position.y)
	var x1 := float(p.end.x)
	var z1 := float(p.end.y)
	# the surround (between the pitch and the stands) in a duller green, then the pitch
	box(_pitch_node, Vector3(x0 - 0.02, -0.005, z0 - 0.02), Vector3(x1 + 0.02, 0.025, z1 + 0.02), tex_mat("grass_ground", Color(0.3, 0.45, 0.2), 2.0, true), false)
	var pm := PlaneMesh.new()
	pm.size = Vector2(x1 - x0 - 0.3, z1 - z0 - 0.3)
	var pi := MeshInstance3D.new()
	pi.mesh = pm
	pi.position = Vector3((x0 + x1) / 2.0, 0.03, (z0 + z1) / 2.0)
	pi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _pitch_mat == null:
		_pitch_mat = ShaderMaterial.new()
		_pitch_mat.shader = load("res://view/pitch.gdshader")
		_pitch_mat.set_shader_parameter("grass_n", load(TEX_DIR + "grass_ground/nor.jpg"))
		var nt := NoiseTexture2D.new()
		nt.seamless = true
		var fn := FastNoiseLite.new()
		fn.frequency = 0.03
		nt.noise = fn
		_pitch_mat.set_shader_parameter("noise", nt)
	_pitch_mat.set_shader_parameter("pattern", ["stripes", "wide_stripes", "checks", "plain"].find(pitch_pattern))
	_pitch_mat.set_shader_parameter("origin", Vector2(x0, z0))
	_pitch_mat.set_shader_parameter("size", Vector2(x1 - x0, z1 - z0))
	pi.material_override = _pitch_mat
	_pitch_node.add_child(pi)
	var line := mat(Color(0.95, 0.95, 0.95), 0.7)
	var y0 := 0.031
	var y1 := 0.042
	var t := 0.09
	var lx0 := x0 + 0.6
	var lx1 := x1 - 0.6
	var lz0 := z0 + 0.6
	var lz1 := z1 - 0.6
	var cx := (x0 + x1) / 2.0
	var cz := (z0 + z1) / 2.0
	_rect_lines(lx0, lz0, lx1, lz1, y0, y1, t, line)
	box(_pitch_node, Vector3(cx - t / 2, y0, lz0), Vector3(cx + t / 2, y1, lz1), line, false)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.55
	torus.outer_radius = 2.55 + t
	torus.rings = 48
	ring.mesh = torus
	ring.scale = Vector3(1, 0.08, 1)
	ring.position = Vector3(cx, y0, cz)
	ring.material_override = line
	_pitch_node.add_child(ring)
	for end in [0, 1]:
		var gx := lx0 if end == 0 else lx1
		var dir := 1.0 if end == 0 else -1.0
		_rect_lines(min(gx, gx + dir * 4.7), cz - 5.8, max(gx, gx + dir * 4.7), cz + 5.8, y0, y1, t, line)
		_rect_lines(min(gx, gx + dir * 1.6), cz - 2.6, max(gx, gx + dir * 1.6), cz + 2.6, y0, y1, t, line)
		# goal: posts, crossbar, net
		var post := mat(Color.WHITE, 0.4)
		var gh := 0.7
		for zz in [cz - 1.05, cz + 1.05]:
			box(_pitch_node, Vector3(gx - 0.04, 0, zz - 0.04), Vector3(gx + 0.04, gh, zz + 0.04), post)
		box(_pitch_node, Vector3(gx - 0.04, gh - 0.04, cz - 1.05), Vector3(gx + 0.04, gh + 0.04, cz + 1.05), post)
		var back := gx - dir * 0.6
		box(_pitch_node, Vector3(min(gx, back), 0, cz - 1.05), Vector3(max(gx, back), gh, cz + 1.05),
			mat(Color(1, 1, 1), 1.0, 0.0, 0.0, 0.25), false)


const AD_BRANDS := ["VOLTLINE", "SKYHAVEN AIRWAYS", "BRIGHTBANK", "FIZZ COLA", "NORTHWIND BET", "KICKSTAR", "GOALPOST PIZZA", "METRO TELECOM", "PEAK SPORTS"]


## Streetlights around the edge of the plot (Kenney City kit).
func _build_streetlights(layout: Layout) -> void:
	var pl := layout.plot
	var arr: Array[Transform3D] = []
	var sc := 2.3 / maxf(0.01, Kenney.size("city-kit-roads/light-curved").y)
	for x in range(pl.position.x + 3, pl.end.x - 2, 7):
		arr.append(Transform3D(Basis(Vector3.UP, 0.0).scaled(Vector3(sc, sc, sc)), Vector3(x, 0, pl.position.y + 0.3)))
		arr.append(Transform3D(Basis(Vector3.UP, PI).scaled(Vector3(sc, sc, sc)), Vector3(x, 0, pl.end.y - 0.3)))
	for z in range(pl.position.y + 3, pl.end.y - 2, 7):
		arr.append(Transform3D(Basis(Vector3.UP, -PI / 2.0).scaled(Vector3(sc, sc, sc)), Vector3(pl.position.x + 0.3, 0, z)))
		arr.append(Transform3D(Basis(Vector3.UP, PI / 2.0).scaled(Vector3(sc, sc, sc)), Vector3(pl.end.x - 0.3, 0, z)))
	_ground.add_child(Kenney.batch("city-kit-roads/light-curved", arr))


## LED advertising boards round the pitch and the two dugouts.
func _build_pitchside(p: Rect2i) -> void:
	var x0 := float(p.position.x) + 0.2
	var x1 := float(p.end.x) - 0.2
	var z0 := float(p.position.y) + 0.2
	var z1 := float(p.end.y) - 0.2
	var cz := (z0 + z1) / 2.0
	var k := 0
	var segs := []
	# touchlines (leave the halfway line clear on the dugout side)
	var seg_len := 4.5
	var x := x0 + 0.6
	while x + seg_len <= x1 - 0.6:
		segs.append([Vector3(x + seg_len / 2.0, 0, z0), seg_len, 0.0])
		if absf(x + seg_len / 2.0 - (x0 + x1) / 2.0) > 3.5:
			segs.append([Vector3(x + seg_len / 2.0, 0, z1), seg_len, PI])
		x += seg_len + 0.15
	# byelines, either side of the goal
	for gx in [x0, x1]:
		for zz in [z0 + 2.3, z1 - 2.3]:
			segs.append([Vector3(gx, 0, zz), 4.0, PI / 2.0 if gx == x0 else -PI / 2.0])
	for sgm in segs:
		var g := Node3D.new()
		g.position = sgm[0]
		g.rotation.y = sgm[2]
		_pitch_node.add_child(g)
		var L: float = sgm[1]
		lbox(g, Vector3(0, 0.16, 0), Vector3(L, 0.32, 0.06), mat(Color(0.05, 0.05, 0.06), 0.4))
		var col := Color.from_hsv(float(k % 7) / 7.0, 0.75, 0.9)
		var face := lbox(g, Vector3(0, 0.17, 0.035), Vector3(L - 0.08, 0.26, 0.01), mat(col, 0.3, 0.0, 1.6))
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var lab := Label3D.new()
		lab.text = AD_BRANDS[k % AD_BRANDS.size()]
		lab.font_size = 48
		lab.pixel_size = 0.0042
		lab.outline_size = 0
		lab.modulate = Color(1, 1, 1)
		lab.position = Vector3(0, 0.17, 0.045)
		g.add_child(lab)
		k += 1
	# dugouts either side of halfway on the far touchline
	for side in [-1, 1]:
		var g := Node3D.new()
		g.position = Vector3((x0 + x1) / 2.0 + side * 2.2, 0, z1 - 0.05)
		g.rotation.y = PI
		_pitch_node.add_child(g)
		lbox(g, Vector3(0, 0.02, -0.25), Vector3(2.4, 0.04, 0.55), mat(Color(0.2, 0.2, 0.22), 0.6))
		lbox(g, Vector3(0, 0.12, -0.42), Vector3(2.3, 0.08, 0.18), mat(Color(0.1, 0.1, 0.12), 0.5))
		lbox(g, Vector3(0, 0.26, -0.5), Vector3(2.3, 0.2, 0.06), mat(Color(0.1, 0.1, 0.12), 0.5))
		lbox(g, Vector3(0, 0.55, -0.25), Vector3(2.5, 0.03, 0.6), mat(Color(0.75, 0.85, 0.95), 0.05, 0.2, 0.0, 0.45), 0.12)
		for e in [-1, 1]:
			lbox(g, Vector3(e * 1.22, 0.28, -0.25), Vector3(0.03, 0.56, 0.6), mat(Color(0.75, 0.85, 0.95), 0.05, 0.2, 0.0, 0.45))


func _rect_outline(parent: Node3D, r: Rect2, y: float, m: Material, t := 0.08) -> void:
	box(parent, Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y + 0.02, r.position.y + t), m, false)
	box(parent, Vector3(r.position.x, y, r.end.y - t), Vector3(r.end.x, y + 0.02, r.end.y), m, false)
	box(parent, Vector3(r.position.x, y, r.position.y), Vector3(r.position.x + t, y + 0.02, r.end.y), m, false)
	box(parent, Vector3(r.end.x - t, y, r.position.y), Vector3(r.end.x, y + 0.02, r.end.y), m, false)


func _rect_lines(x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, t: float, m: Material) -> void:
	box(_pitch_node, Vector3(x0, y0, z0 - t / 2), Vector3(x1, y1, z0 + t / 2), m, false)
	box(_pitch_node, Vector3(x0, y0, z1 - t / 2), Vector3(x1, y1, z1 + t / 2), m, false)
	box(_pitch_node, Vector3(x0 - t / 2, y0, z0), Vector3(x0 + t / 2, y1, z1), m, false)
	box(_pitch_node, Vector3(x1 - t / 2, y0, z0), Vector3(x1 + t / 2, y1, z1), m, false)


## Floodlights in the layout's style: tall corner pylons (kept clear of the
## stands), light bars along the front of each roof, or rows of side masts.
func _build_floodlights(layout: Layout) -> void:
	for c in _lights.get_children():
		c.free()
	_spots.clear()
	var p := layout.pitch
	var centre := Vector3(p.get_center().x, 0, p.get_center().y)
	var steel := mat(Color(0.35, 0.36, 0.38), 0.5, 0.7)
	var style := layout.floodlights
	if layout.shell != "none" and not layout.stands.is_empty():
		# with a shell the lights hang along the front edge of the continuous roof
		var g := shell_geometry(layout)
		var inner: Rect2 = g["inner"]
		var y: float = g["h"] + 0.9 - 0.35
		var k := 0
		for side in [[inner.position, Vector2(inner.end.x, inner.position.y)], [Vector2(inner.position.x, inner.end.y), inner.end],
				[inner.position, Vector2(inner.position.x, inner.end.y)], [Vector2(inner.end.x, inner.position.y), inner.end]]:
			var a: Vector2 = side[0]
			var b: Vector2 = side[1]
			var n := maxi(2, int(a.distance_to(b) / 3.5))
			for i in n:
				var q := a.lerp(b, (i + 0.5) / n)
				_lamp_head(Vector3(q.x, y, q.y), centre, Vector3(1.4, 0.45, 0.2), k % 3 == 0)
				k += 1
		style = "shell"
	match style:
		"shell":
			pass
		"roof":
			for s in layout.stands:
				if s.is_corner() or s.roof == "open":
					continue
				var tp := to_pitch(s.side)
				var foot := tiles_xz(s.lower_tiles(layout.pitch))
				var along := Vector2(abs(tp.y), abs(tp.x))
				var length := foot.size.x if tp.x == 0.0 else foot.size.y
				var front := foot.get_center() + tp * ((foot.size.y if tp.x == 0.0 else foot.size.x) / 2.0 + 0.6)
				var y := stand_top(s) + ROOF_CLEARANCE + 0.9
				var n := maxi(1, int(length / 3.0))
				for k in n:
					var q := front + along * ((k + 0.5) / n - 0.5) * (length - 1.0)
					_lamp_head(Vector3(q.x, y, q.y), centre, Vector3(1.6, 0.5, 0.2), k % 2 == 0)
		"masts":
			for side in ["N", "S"]:
				var reach := 2.0
				for s in layout.stands:
					if s.side == side:
						reach = maxf(reach, s.footprint_depth() + s.setback + 2.5)
				var z := p.position.y - reach if side == "N" else p.end.y + reach
				for u in [0.15, 0.5, 0.85]:
					var x: float = p.position.x + p.size.x * u
					var height := 11.0 + reach * 0.6
					box(_lights, Vector3(x - 0.12, 0, z - 0.12), Vector3(x + 0.12, height, z + 0.12), steel)
					_lamp_head(Vector3(x, height + 0.5, z), centre, Vector3(1.8, 1.1, 0.2), true)
		_:
			for corner in Stand.CORNERS:
				var reach := 3.5
				for s in layout.stands:
					if corner.contains(s.side) or s.side == corner:
						reach = maxf(reach, s.footprint_depth() + s.setback + 3.0)
				var cf := corner_frame(corner, p)
				var c: Vector2 = cf["centre"] + Vector2(cf["sx"], cf["sz"]) * reach * 0.75
				var height := 17.0 + reach * 0.7
				_lattice_pylon(Vector2(c.x, c.y), height, steel)
				_lamp_head(Vector3(c.x, height + 1.0, c.y), centre, Vector3(3.2, 2.0, 0.25), true)
	set_night(_night)


## A tapering four-legged lattice tower with cross bracing.
func _lattice_pylon(c: Vector2, height: float, steel: Material) -> void:
	var base := 0.9
	var tip := 0.3
	var levels := int(height / 1.6)
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var at := func(k: int, h: float) -> Vector3:
		var w := lerpf(base, tip, h / height)
		var d: Vector2 = corners[k]
		return Vector3(c.x + d.x * w, h, c.y + d.y * w)
	var strut := func(a: Vector3, b: Vector3, t: float) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(t, t, a.distance_to(b))
		mi.mesh = bm
		mi.material_override = steel
		_lights.add_child(mi)
		mi.position = (a + b) / 2.0
		mi.look_at_from_position(mi.position, b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
	for k in 4:
		strut.call(at.call(k, 0.0), at.call(k, height), 0.12)
	for l in levels:
		var h0 := float(l) / levels * height
		var h1 := float(l + 1) / levels * height
		for k in 4:
			var k2 := (k + 1) % 4
			strut.call(at.call(k, h1), at.call(k2, h1), 0.05)
			strut.call(at.call(k, h0), at.call(k2, h1), 0.04)
	# platform at the top
	box(_lights, Vector3(c.x - 0.6, height - 0.05, c.y - 0.6), Vector3(c.x + 0.6, height + 0.05, c.y + 0.6), steel)


## A lamp panel aimed at the pitch, optionally with a real spotlight.
func _lamp_head(pos: Vector3, aim: Vector3, size: Vector3, with_light: bool) -> void:
	var head := Node3D.new()
	head.position = pos
	_lights.add_child(head)
	head.look_at(aim, Vector3.UP)
	var panel := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	panel.mesh = bm
	panel.material_override = mat(Color(0.35, 0.36, 0.38), 0.5, 0.7)
	head.add_child(panel)
	# a grid of individual lamps, each a round reflector with a bright face
	var cols := maxi(2, roundi(size.x / 0.42))
	var rows := maxi(1, roundi(size.y / 0.42))
	var lamp := CylinderMesh.new()
	lamp.top_radius = 0.17
	lamp.bottom_radius = 0.2
	lamp.height = 0.12
	lamp.radial_segments = 12
	lamp.rings = 1
	var face := CylinderMesh.new()
	face.top_radius = 0.15
	face.bottom_radius = 0.15
	face.height = 0.02
	face.radial_segments = 12
	face.rings = 1
	var xf_l: Array[Transform3D] = []
	var xf_f: Array[Transform3D] = []
	var tilt := Basis(Vector3.RIGHT, PI / 2.0)
	for r in rows:
		for c in cols:
			var p := Vector3((c + 0.5) / cols * size.x - size.x / 2.0, (r + 0.5) / rows * size.y - size.y / 2.0, -size.z / 2.0 - 0.06)
			xf_l.append(Transform3D(tilt, p))
			xf_f.append(Transform3D(tilt, p + Vector3(0, 0, -0.07)))
	for pair in [[lamp, xf_l, mat(Color(0.3, 0.31, 0.33), 0.4, 0.8)], [face, xf_f, mat(Color(1.0, 0.97, 0.88), 0.3, 0.0, 4.0)]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pair[0]
		var arr: Array = pair[1]
		mm.instance_count = arr.size()
		for k in arr.size():
			mm.set_instance_transform(k, arr[k])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = pair[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head.add_child(mi)
	# a maintenance walkway along the bottom
	var walk := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(size.x + 0.2, 0.05, 0.4)
	walk.mesh = wm
	walk.position = Vector3(0, -size.y / 2.0 - 0.1, 0.1)
	walk.material_override = mat(Color(0.35, 0.36, 0.38), 0.5, 0.7)
	head.add_child(walk)
	if with_light:
		var spot := SpotLight3D.new()
		_spots.append(spot)
		spot.light_color = Color(1.0, 0.96, 0.88)
		spot.spot_range = 60.0
		spot.spot_angle = 32.0
		spot.spot_attenuation = 0.6
		head.add_child(spot)


# --- terrain ---------------------------------------------------------------------

var _clear := Rect2()
var _n_hills := FastNoiseLite.new()
var _n_far := FastNoiseLite.new()
var _n_ridge := FastNoiseLite.new()
var _terrain_mat: ShaderMaterial
var _pitch_mat: ShaderMaterial
const URBAN := ["town", "suburban", "city"]


func _setup_terrain(layout: Layout) -> void:
	_clear = Rect2(layout.base_plot).grow(float(layout.strip_tiles * 3 + 3))
	_n_hills.seed = 21
	_n_hills.frequency = 0.011
	_n_hills.fractal_octaves = 4
	_n_far.seed = 22
	_n_far.frequency = 0.004
	_n_far.fractal_octaves = 3
	_n_ridge.seed = 5
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_ridge.fractal_octaves = 5
	_n_ridge.frequency = 0.008


## Ground height at a world point. Flat (just below 0) on and around the plot,
## so the stadium and all buyable land are level; rolling country beyond,
## bigger hills toward the horizon, and carved beds for rivers, lakes and streams.
func terrain_h(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var flat := _clear.grow(3.0)
	var d := maxf(maxf(flat.position.x - x, x - flat.end.x), maxf(flat.position.y - z, z - flat.end.y))
	if d <= 0.0:
		return -0.02
	var side := _side_mode(surroundings, p, _clear)
	var amp: float = { "city": 2.5, "town": 4.0, "suburban": 6.0, "fields": 8.0, "forest": 11.0 }.get(side, 6.0)
	var start := 55.0 if side in URBAN else 6.0
	var ramp := smoothstep(start, start + 45.0, d)
	var h := ramp * amp * (_n_hills.get_noise_2d(x, z) * 0.5 + 0.5)
	var dist := p.distance_to(_clear.get_center())
	h += smoothstep(170.0, 360.0, dist) * 45.0 * (_n_far.get_noise_2d(x, z) * 0.5 + 0.5)
	if surroundings == "mountains":
		var edge := _clear.position.y - 30.0 - 6.0 * sin(x * 0.04)
		var away := clampf((edge - z) / 150.0, 0.0, 1.0)
		h += pow(away, 1.3) * (40.0 + 80.0 * (_n_ridge.get_noise_2d(x, z) * 0.5 + 0.5)) + away * 6.0
	h += 0.4 * smoothstep(0.0, 12.0, d) * _n_hills.get_noise_2d(x * 4.0, z * 4.0)   # small bumps
	# water beds
	var bed := _water_dist(p)
	if bed < 1e8:
		var carve := smoothstep(bed_width(p) + 5.0, bed_width(p) * 0.6, bed)
		h = lerpf(h, -1.6, carve)
	return minf(h, 400.0)


func _slope(x: float, z: float) -> float:
	var e := 1.5
	return Vector2(terrain_h(x + e, z) - terrain_h(x - e, z), terrain_h(x, z + e) - terrain_h(x, z - e)).length() / (2.0 * e)


func _river_z(x: float) -> float:
	return _clear.position.y - 22.0 + sin(x * 0.025) * 9.0


func _stream_z(x: float) -> float:
	return _clear.end.y + 62.0 + sin(x * 0.031 + 1.7) * 14.0 + sin(x * 0.011) * 10.0


func _lake_q(p: Vector2) -> float:
	var c := Vector2(_clear.end.x + 75.0, _clear.get_center().y + 10.0)
	var q := (p - c) / Vector2(62.0, 85.0)
	return q.length() / (1.0 + 0.12 * sin(atan2(q.y, q.x) * 5.0))


## Distance from a water centre-line (or the lake's edge, as a fraction) or a large number.
func _water_dist(p: Vector2) -> float:
	var best := 1e9
	if surroundings == "riverside":
		best = minf(best, absf(p.y - _river_z(p.x)))
	if surroundings == "lakeside":
		var lq := _lake_q(p)
		best = minf(best, maxf(0.0, (lq - 1.0) * 70.0))
	if surroundings != "city" and surroundings != "riverside":
		best = minf(best, absf(p.y - _stream_z(p.x)))
	return best


func bed_width(p: Vector2) -> float:
	if surroundings == "riverside" and absf(p.y - _river_z(p.x)) < 20.0:
		return 9.5
	if surroundings == "lakeside" and _lake_q(p) < 1.4:
		return 2.0
	return 3.0


## Foliage tint for the Kenney trees (their base green is minty): natural,
## varied greens with the odd yellowing or copper tree.
func _leaf(rng: RandomNumberGenerator) -> Color:
	var r := rng.randf()
	if r < 0.06:
		return Color(1.0, 0.72, 0.42)
	if r < 0.12:
		return Color(1.0, 0.9, 0.55)
	return Color(1.0, 1.0, 0.95).lerp(Color(0.78, 0.84, 0.76), rng.randf())


## A flat patch that follows the terrain (fields, crop rows), `lift` above it.
func _drape(r: Rect2, lift: float, m: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_drape_add(st, r, lift)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Adds a terrain-following patch to a SurfaceTool (so many can share one mesh).
func _drape_add(st: SurfaceTool, r: Rect2, lift: float, cell := 2.5) -> void:
	var nx := maxi(1, int(ceil(r.size.x / cell)))
	var nz := maxi(1, int(ceil(r.size.y / cell)))
	var pts: Array[Vector3] = []
	for iz in nz + 1:
		for ix in nx + 1:
			var x := r.position.x + r.size.x * ix / nx
			var z := r.position.y + r.size.y * iz / nz
			pts.append(Vector3(x, maxf(terrain_h(x, z), -0.02) + lift, z))
	for iz in nz:
		for ix in nx:
			var a := pts[iz * (nx + 1) + ix]
			var b := pts[iz * (nx + 1) + ix + 1]
			var d := pts[(iz + 1) * (nx + 1) + ix]
			var e := pts[(iz + 1) * (nx + 1) + ix + 1]
			for v in [a, b, d, b, e, d]:
				st.add_vertex(v)


func _build_terrain(layout: Layout) -> void:
	var c := _clear.get_center()
	var half := 720.0
	var step := 5.0
	var n := int(2.0 * half / step) + 1
	var verts := PackedVector3Array()
	verts.resize(n * n)
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for iz in n:
		for ix in n:
			var x := c.x - half + ix * step
			var z := c.y - half + iz * step
			var h := terrain_h(x, z)
			hs[iz * n + ix] = h
			verts[iz * n + ix] = Vector3(x, h, z)
	var norms := PackedVector3Array()
	norms.resize(n * n)
	for iz in n:
		for ix in n:
			var l := hs[iz * n + maxi(ix - 1, 0)]
			var r := hs[iz * n + mini(ix + 1, n - 1)]
			var u := hs[maxi(iz - 1, 0) * n + ix]
			var dn := hs[mini(iz + 1, n - 1) * n + ix]
			norms[iz * n + ix] = Vector3(l - r, 2.0 * step, u - dn).normalized()
	var idx := PackedInt32Array()
	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if _terrain_mat == null:
		_terrain_mat = ShaderMaterial.new()
		_terrain_mat.shader = load("res://view/terrain.gdshader")
		var T := TEX_DIR
		for pair in [["grass_a", "grass_ground/diff.jpg"], ["grass_a_n", "grass_ground/nor.jpg"], ["grass_b", "sparse_grass/diff.jpg"],
				["dirt", "forrest_ground_01/diff.jpg"], ["dirt_n", "forrest_ground_01/nor.jpg"], ["rock", "rocky_terrain_02/diff.jpg"], ["rock_n", "rocky_terrain_02/nor.jpg"]]:
			_terrain_mat.set_shader_parameter(pair[0], load(T + pair[1]))
		var vt := NoiseTexture2D.new()
		vt.seamless = true
		vt.width = 256
		vt.height = 256
		var vn := FastNoiseLite.new()
		vn.frequency = 0.02
		vt.noise = vn
		_terrain_mat.set_shader_parameter("variation", vt)
	_terrain_mat.set_shader_parameter("snow", 0.0)
	mi.material_override = _terrain_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_ground.add_child(mi)
	# water: lake / river surfaces sit in the carved beds; streams in the countryside
	if surroundings != "city" and surroundings != "riverside":
		var pts := PackedVector2Array()
		var x := c.x - half
		while x <= c.x + half:
			pts.append(Vector2(x, _stream_z(x)))
			x += 4.0
		_water_strip(pts, 3.0, _ground)


## Rolling hills and a tree line on the horizon, so the land fades into the
## distance (with the fog) instead of stopping dead.
func _build_horizon(layout: Layout) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var c := Vector2(layout.base_plot.get_center())
	# a ring of distant woodland between the town and the hills
	var trees: Array[Transform3D] = []
	var cols: Array[Color] = []
	for k in 2600:
		var a := rng.randf() * TAU
		var r := rng.randf_range(170.0, 340.0)
		if sin(a * 5.0 + 1.3) * cos(a * 3.0) > 0.45 and rng.randf() < 0.85:
			continue  # clearings, so the tree line isn't a wall
		var p := c + Vector2(cos(a), sin(a)) * r
		var sc := rng.randf_range(3.5, 5.5) / maxf(0.01, Kenney.size("proc/far").y)
		var hy := terrain_h(p.x, p.y)
		if hy < -0.2 or _slope(p.x, p.y) > 0.9:
			continue
		trees.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(p.x, hy - 0.2, p.y)))
		cols.append(_leaf(rng))
	var tl := Kenney.batch("proc/far", trees, cols)
	tl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground.add_child(tl)


## The world around the ground, in the layout's chosen style. The land is laid
## out in street blocks (roads between them) and each block is filled by style:
##   town     - low shops and flats near the ground, houses further out
##   suburban - houses with gardens and fences, lots of trees
##   city     - mid-rise blocks, a few towers far out that fade near the camera
##   fields   - crops, hedges, fences and a farmhouse or two
##   forest   - dense woodland
## Buildings keep their real proportions (1 tile is about 3.5 m).
func _build_trees(layout: Layout) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mode := layout.surroundings
	var reach := float(layout.strip_tiles * 3 + 3)
	var clear := Rect2(layout.base_plot).grow(reach)
	var batches := {}       # path|fade -> [transforms, colours]
	var add := func(path: String, xf: Transform3D, col := Color.WHITE, fade := false) -> void:
		var hy := terrain_h(xf.origin.x, xf.origin.z)
		if hy < -0.3:
			return  # in the water
		var is_tree := path.begins_with("nature-kit") or path.begins_with("proc/")
		if not is_tree and _slope(xf.origin.x, xf.origin.z) > 0.18:
			return  # no buildings on hillsides
		xf.origin.y += hy - (0.15 if is_tree else 0.05)
		var key := path + ("|fade" if fade else "")
		if not batches.has(key):
			batches[key] = [[], [], path, fade]
		batches[key][0].append(xf)
		batches[key][1].append(col)
	var tree_kinds := ["proc/oak", "proc/lime", "proc/birch", "proc/oak", "proc/poplar"]
	var pines := ["proc/fir", "proc/spruce"]
	var town := ProcBuildings.new()
	town.night = _night
	var bld := func(kind: String, p: Vector2, yaw: float, fade := false) -> void:
		var hy := terrain_h(p.x, p.y)
		if hy < -0.3 or _slope(p.x, p.y) > 0.18:
			return
		town.add(kind, p, hy - 0.05, yaw, rng, fade)
	var houses := []
	for c in "abcdefghijklmnopqrstu":
		houses.append("city-kit-suburban/building-type-" + c)
	var low_shops := ["city-kit-commercial/building-c", "city-kit-commercial/building-e", "city-kit-commercial/building-j", "city-kit-commercial/building-k", "city-kit-commercial/building-n"]
	var mid_blocks := ["city-kit-commercial/building-a", "city-kit-commercial/building-b", "city-kit-commercial/building-d", "city-kit-commercial/building-f",
		"city-kit-commercial/building-g", "city-kit-commercial/building-h", "city-kit-commercial/building-i", "city-kit-commercial/building-l"]
	var towers := ["city-kit-commercial/building-skyscraper-a", "city-kit-commercial/building-skyscraper-c", "city-kit-commercial/building-skyscraper-e", "city-kit-commercial/building-m"]
	var facades := [Color(0.86, 0.62, 0.52), Color(0.92, 0.88, 0.8), Color(0.72, 0.74, 0.78), Color(0.85, 0.8, 0.7), Color(0.7, 0.55, 0.48), Color(0.95, 0.95, 0.93)]
	var road_m := tex_mat("asphalt_01", Color(0.42, 0.42, 0.44), 4.0)
	var field_cols := [Color(0.6, 0.54, 0.34), Color(0.4, 0.48, 0.26), Color(0.36, 0.29, 0.22), Color(0.48, 0.54, 0.3)]
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.03
	var road := 2.0
	var road_st := SurfaceTool.new()
	road_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pave_st := SurfaceTool.new()
	pave_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roads := 0
	var span := 150.0
	# irregular street grid: every column and row of blocks has its own width
	var xs := []
	var x := clear.position.x - span
	while x < clear.end.x + span:
		xs.append(x)
		x += rng.randf_range(9.0, 20.0) + road
	var zs := []
	var z := clear.position.y - span
	while z < clear.end.y + span:
		zs.append(z)
		z += rng.randf_range(9.0, 20.0) + road
	for ix in xs.size() - 1:
		for iz in zs.size() - 1:
			var cell := Rect2(xs[ix], zs[iz], xs[ix + 1] - xs[ix] - road, zs[iz + 1] - zs[iz] - road)
			var centre := cell.get_center()
			var dist := maxf(maxf(clear.position.x - centre.x, centre.x - clear.end.x), maxf(clear.position.y - centre.y, centre.y - clear.end.y))
			if cell.intersects(clear.grow(1.0)):
				continue
			if _feature_at(centre, clear) != "" or _feature_at(cell.position, clear) != "" or _feature_at(cell.end, clear) != "":
				continue
			var block_mode := _side_mode(mode, centre, clear)
			var n := noise.get_noise_2d(centre.x, centre.y)
			# thin out towards the horizon, and leave natural gaps (parks, scrub)
			var keep := 1.0 - smoothstep(60.0, 150.0, dist)
			if n < -0.35 or rng.randf() > keep + 0.15:
				_park_block(cell, rng, add, tree_kinds, pines, dist)
				continue
			var dry := true
			for q in [cell.position, cell.end, centre, Vector2(cell.position.x, cell.end.y), Vector2(cell.end.x, cell.position.y)]:
				if _water_dist(q) < bed_width(q) + 6.0:
					dry = false
			if block_mode in ["town", "suburban", "city"] and dry and rng.randf() < keep + 0.2:
				# street along the north and west of the block, with a pavement either side;
				# both follow the ground over hills
				var n_road := Rect2(cell.position.x - road, cell.position.y - road, cell.size.x + road, road)
				var w_road := Rect2(cell.position.x - road, cell.position.y, road, cell.size.y)
				_drape_add(pave_st, n_road.grow(0.55), 0.05)
				_drape_add(pave_st, w_road.grow_individual(0.55, 0.0, 0.55, 0.0), 0.05)
				_drape_add(road_st, n_road, 0.09)
				_drape_add(road_st, w_road, 0.09)
				roads += 1
			_fill_block(cell, block_mode, dist, rng, add, houses, low_shops, mid_blocks, towers, tree_kinds, pines, facades, field_cols, bld)
	town.build(_trees)
	for pair in [[road_st, road_m], [pave_st, tex_mat("rough_concrete", Color(0.86, 0.88, 0.98), 3.0)]]:
		if roads == 0:
			break
		var st: SurfaceTool = pair[0]
		st.generate_normals()
		var rm := MeshInstance3D.new()
		rm.mesh = st.commit()
		rm.material_override = pair[1]
		rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_trees.add_child(rm)
	_build_features(mode, clear, rng, add, tree_kinds, pines)
	# the land you could still buy: rough grass, scrub and copses, not a void
	var plot := Rect2(layout.plot)
	for k in 260:
		var p := Vector2(rng.randf_range(clear.position.x, clear.end.x), rng.randf_range(clear.position.y, clear.end.y))
		if plot.grow(1.5).has_point(p):
			continue
		var cluster := noise.get_noise_2d(p.x * 3.0, p.y * 3.0)
		if cluster < -0.1 and rng.randf() < 0.6:
			continue
		_tree(add, rng, p, tree_kinds if rng.randf() < 0.7 else pines, rng.randf_range(2.5, 5.0))
	for k in 160:
		var p := Vector2(rng.randf_range(clear.position.x, clear.end.x), rng.randf_range(clear.position.y, clear.end.y))
		if plot.grow(0.8).has_point(p):
			continue
		var kind: String = ["proc/bush", "proc/bush", "nature-kit/grass_large", "proc/bush"][rng.randi_range(0, 3)]
		var sc := Kenney.scale_to(kind, rng.randf_range(0.6, 1.4))
		add.call(kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(p.x, 0, p.y)), _leaf(rng))
	for key in batches:
		var b: Array = batches[key]
		var arr: Array[Transform3D] = []
		arr.assign(b[0])
		var cols: Array[Color] = []
		cols.assign(b[1])
		var mi := Kenney.batch(b[2], arr, cols, b[3])
		if String(b[2]).begins_with("nature-kit/tree") or (String(b[2]).begins_with("proc/") and b[2] != "proc/bush"):
			mi.set_meta("tree", true)
		_trees.add_child(mi)


func _tree(add: Callable, rng: RandomNumberGenerator, p: Vector2, kinds: Array, h: float) -> void:
	var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
	var sz := Kenney.size(kind)
	var sc := h / maxf(0.01, sz.y) * rng.randf_range(0.85, 1.15)
	add.call(kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(p.x, 0, p.y)), _leaf(rng))


## Which way a point lies from the ground: "N", "S", "E" or "W".
static func _dir(p: Vector2, clear: Rect2) -> String:
	var d := p - clear.get_center()
	if absf(d.x) / clear.size.x > absf(d.y) / clear.size.y:
		return "E" if d.x > 0 else "W"
	return "S" if d.y > 0 else "N"


## Landscape presets give each side its own character.
const SIDE_MODES := {
	"riverside": { "N": "town", "S": "suburban", "E": "town", "W": "fields" },
	"lakeside": { "N": "forest", "S": "suburban", "E": "suburban", "W": "town" },
	"mountains": { "N": "forest", "S": "fields", "E": "forest", "W": "suburban" },
	"city_edge": { "N": "town", "S": "fields", "E": "suburban", "W": "city" },
}


func _side_mode(mode: String, p: Vector2, clear: Rect2) -> String:
	if SIDE_MODES.has(mode):
		return SIDE_MODES[mode][_dir(p, clear)]
	return mode


## Natural features that blocks avoid: "water", "mountain" or "".
func _feature_at(p: Vector2, clear: Rect2) -> String:
	match surroundings:
		"riverside":
			var zc := clear.position.y - 22.0 + sin(p.x * 0.025) * 9.0
			return "water" if absf(p.y - zc) < 9.0 else ""
		"lakeside":
			var c := Vector2(clear.end.x + 75.0, clear.get_center().y + 10.0)
			var q := (p - c) / Vector2(62.0, 85.0)
			return "water" if q.length() < 1.0 + 0.12 * sin(atan2(q.y, q.x) * 5.0) else ""
		"mountains":
			return "mountain" if p.y < clear.position.y - 28.0 - 6.0 * sin(p.x * 0.04) else ""
	return ""


## Rivers, lakes and mountains for the landscape presets.
func _build_features(mode: String, clear: Rect2, rng: RandomNumberGenerator, add: Callable, tree_kinds: Array, pines: Array) -> void:
	match mode:
		"riverside":
			# a meandering river across the north, with a road bridge in line with the ground
			var pts := PackedVector2Array()
			var x := clear.position.x - 260.0
			while x <= clear.end.x + 260.0:
				pts.append(Vector2(x, clear.position.y - 22.0 + sin(x * 0.025) * 9.0))
				x += 4.0
			_water_strip(pts, 9.5)
			var bx := clear.get_center().x
			var bz := clear.position.y - 22.0 + sin(bx * 0.025) * 9.0
			box(_trees, Vector3(bx - 2.0, 0.0, bz - 12.0), Vector3(bx + 2.0, 0.55, bz + 12.0), tex_mat("concrete_floor_02", Color(0.72, 0.72, 0.7), 4.0, true))
			box(_trees, Vector3(bx - 2.1, 0.55, bz - 12.0), Vector3(bx - 1.9, 0.95, bz + 12.0), mat(Color(0.5, 0.52, 0.55), 0.4, 0.7))
			box(_trees, Vector3(bx + 1.9, 0.55, bz - 12.0), Vector3(bx + 2.1, 0.95, bz + 12.0), mat(Color(0.5, 0.52, 0.55), 0.4, 0.7))
			for k in 120:
				var px := rng.randf_range(clear.position.x - 200.0, clear.end.x + 200.0)
				var pz := clear.position.y - 22.0 + sin(px * 0.025) * 9.0 + (11.0 if rng.randf() < 0.5 else -11.0) + rng.randf_range(-1.5, 1.5)
				if absf(px - bx) > 3.0:
					_tree(add, rng, Vector2(px, pz), tree_kinds, rng.randf_range(3.0, 5.5))
		"lakeside":
			var c := Vector2(clear.end.x + 75.0, clear.get_center().y + 10.0)
			var ring := PackedVector2Array()
			for k in 72:
				var a := TAU * k / 72.0
				var r := 1.0 + 0.12 * sin(a * 5.0)
				ring.append(c + Vector2(cos(a) * 62.0, sin(a) * 85.0) * r)
			_water_disc(c, ring)
			for k in 160:
				var a := rng.randf() * TAU
				var r := (1.0 + 0.12 * sin(a * 5.0)) * rng.randf_range(1.04, 1.18)
				var p := c + Vector2(cos(a) * 62.0, sin(a) * 85.0) * r
				if not clear.grow(2.0).has_point(p):
					_tree(add, rng, p, tree_kinds + pines, rng.randf_range(3.0, 6.0))
			# a little jetty
			var j := c + Vector2(-62.0, 0.0)
			box(_trees, Vector3(j.x - 1.0, 0.1, j.y - 0.5), Vector3(j.x + 9.0, 0.22, j.y + 0.5), mat(Color(0.45, 0.32, 0.2), 0.8))
		"mountains":
			_mountains(clear, rng, add, pines)


func _water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://view/water.gdshader")
	var tex := NoiseTexture2D.new()
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 4.0
	tex.width = 256
	tex.height = 256
	var n := FastNoiseLite.new()
	n.frequency = 0.04
	tex.noise = n
	m.set_shader_parameter("ripple", tex)
	return m


## A water ribbon along a centre line (river), deeper in the middle.
func _water_strip(pts: PackedVector2Array, half: float, parent: Node3D = null) -> void:
	if parent == null:
		parent = _trees
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var nrm := (b - a).orthogonal().normalized()
		var quads := [[-1.0, -0.4], [-0.4, 0.4], [0.4, 1.0]]
		for q in quads:
			var w0: float = q[0]
			var w1: float = q[1]
			var d0 := 1.0 - absf(w0)
			var d1 := 1.0 - absf(w1)
			var v := [Vector3(a.x + nrm.x * w0 * half, -0.55, a.y + nrm.y * w0 * half), Vector3(a.x + nrm.x * w1 * half, -0.55, a.y + nrm.y * w1 * half),
				Vector3(b.x + nrm.x * w1 * half, -0.55, b.y + nrm.y * w1 * half), Vector3(b.x + nrm.x * w0 * half, -0.55, b.y + nrm.y * w0 * half)]
			var dd := [d0, d1, d1, d0]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(Color(1, 1, 1, dd[k]))
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(v[k].x, v[k].z) * 0.1)
				st.add_vertex(v[k])
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _water_material()
	parent.add_child(mi)


## A lake: a fan of triangles from the centre (deep) to the shore (shallow).
func _water_disc(c: Vector2, ring: PackedVector2Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var mid_a := c.lerp(a, 0.7)
		var mid_b := c.lerp(b, 0.7)
		for tri in [[c, mid_a, mid_b, 1.0, 0.6, 0.6], [mid_a, a, b, 0.6, 0.0, 0.0], [mid_a, b, mid_b, 0.6, 0.0, 0.6]]:
			for k in 3:
				var p: Vector2 = tri[k]
				st.set_color(Color(1, 1, 1, tri[3 + k]))
				st.set_normal(Vector3.UP)
				st.set_uv(p * 0.1)
				st.add_vertex(Vector3(p.x, -0.55, p.y))
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _water_material()
	_trees.add_child(mi)
	pass


## A mountain range rising behind the north side: grassy foothills with pine
## forest, grey rock higher up, snow on the peaks.
func _mountains(clear: Rect2, rng: RandomNumberGenerator, add: Callable, pines: Array) -> void:
	# the range itself is part of the terrain (terrain_h); dress its lower slopes with pine forest
	for k in 2600:
		var p := Vector2(rng.randf_range(clear.position.x - 380.0, clear.end.x + 380.0), rng.randf_range(clear.position.y - 400.0, clear.position.y - 30.0))
		var h := terrain_h(p.x, p.y)
		if h < 1.0 or h > 42.0 or _slope(p.x, p.y) > 0.9:
			continue
		var kind: String = pines[rng.randi_range(0, pines.size() - 1)]
		var sc := rng.randf_range(4.0, 8.0) / maxf(0.01, Kenney.size(kind).y)
		add.call(kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(p.x, 0.0, p.y)), _leaf(rng))

## Parkland / scrub: clumps of trees with open grass between them.
func _park_block(cell: Rect2, rng: RandomNumberGenerator, add: Callable, tree_kinds: Array, pines: Array, dist: float) -> void:
	var clumps := rng.randi_range(1, 3)
	for c in clumps:
		var centre := cell.position + Vector2(rng.randf(), rng.randf()) * cell.size
		for k in rng.randi_range(3, 9):
			var p := centre + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
			if cell.has_point(p):
				_tree(add, rng, p, tree_kinds if rng.randf() < 0.7 else pines, rng.randf_range(3.0, 6.0))


func _fill_block(cell: Rect2, mode: String, dist: float, rng: RandomNumberGenerator, add: Callable,
		houses: Array, low_shops: Array, mid_blocks: Array, towers: Array, tree_kinds: Array, pines: Array, facades: Array, field_cols: Array, bld: Callable) -> void:
	var pick := func(a: Array) -> String: return a[rng.randi_range(0, a.size() - 1)]
	var place := func(path: String, p: Vector2, width_tiles: float, yaw: float, col: Color, fade := false) -> void:
		if rng.randf() < 0.12 or not cell.grow(-0.5).has_point(p):
			return  # empty plot
		p += Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))
		yaw += rng.randf_range(-0.05, 0.05)
		var kind := "house"
		if path in low_shops:
			kind = "shops"
		elif path in mid_blocks:
			kind = "flats" if rng.randf() < 0.65 else "shops"
		elif path in towers:
			kind = "office"
		elif rng.randf() < 0.3:
			kind = "terrace"
		elif rng.randf() < 0.04:
			kind = "shed"
		bld.call(kind, p, yaw, fade)
	var tree := func(p: Vector2, kinds: Array, h: float) -> void:
		var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
		var sz := Kenney.size(kind)
		var sc := h / maxf(0.01, sz.y)
		add.call(kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(p.x, 0, p.y)), _leaf(rng))
	match mode:
		"forest":
			for k in int(cell.get_area() / 7.0):
				tree.call(cell.position + Vector2(rng.randf(), rng.randf()) * cell.size, pines + tree_kinds, rng.randf_range(3.5, 6.5))
		"fields":
			var c: Color = field_cols[rng.randi_range(0, field_cols.size() - 1)]
			_trees.add_child(_drape(Rect2(cell.position, cell.size), 0.08, tex_mat("forrest_ground_01" if c.g < 0.32 else "sparse_grass", c * 1.6, 4.0)))
			# crop rows: thin strips draped over the ground
			if c.r < 0.7:
				for k in range(int(cell.size.x / 1.6)):
					var rx := cell.position.x + k * 1.6 + 0.4
					_trees.add_child(_drape(Rect2(rx, cell.position.y + 0.6, 0.5, cell.size.y - 1.2), 0.12, mat(c.darkened(0.3), 0.95)))
			# hedgerow with trees along one edge
			for k in 8:
				tree.call(Vector2(cell.position.x + rng.randf() * cell.size.x, cell.position.y - 1.0), tree_kinds, rng.randf_range(2.5, 4.5))
			if rng.randf() < 0.12:
				place.call(pick.call(houses), cell.get_center(), 3.2, rng.randi_range(0, 3) * PI / 2.0, Color(0.95, 0.93, 0.9))
		"suburban":
			for gx in int(cell.size.x / 4.6):
				for gz in 2:
					var p := cell.position + Vector2(2.4 + gx * 4.6, 3.4 + gz * (cell.size.y - 6.8))
					place.call(pick.call(houses), p, 3.3, (0.0 if gz == 0 else PI), Color(0.97, 0.96, 0.94))
					if rng.randf() < 0.8:
						tree.call(p + Vector2(rng.randf_range(-1.6, 1.6), 2.6 if gz == 0 else -2.6), tree_kinds, rng.randf_range(3.0, 5.0))
		"city":
			var far := dist > 45.0
			for gx in int(cell.size.x / 4.7):
				for gz in int(cell.size.y / 4.7):
					var p := cell.position + Vector2(2.3 + gx * 4.7, 2.3 + gz * 4.7)
					if far and rng.randf() < 0.18:
						place.call(pick.call(towers), p, 4.4, rng.randi_range(0, 3) * PI / 2.0, facades[rng.randi_range(0, facades.size() - 1)], true)
					else:
						place.call(pick.call(mid_blocks if dist > 18.0 else low_shops), p, 4.3, rng.randi_range(0, 3) * PI / 2.0, facades[rng.randi_range(0, facades.size() - 1)], dist > 18.0)
		_:  # town
			if dist < 30.0:
				for gx in int(cell.size.x / 4.7):
					for gz in int(cell.size.y / 4.7):
						var p := cell.position + Vector2(2.3 + gx * 4.7, 2.3 + gz * 4.7)
						if rng.randf() < 0.8:
							place.call(pick.call(low_shops), p, 4.2, rng.randi_range(0, 3) * PI / 2.0, facades[rng.randi_range(0, facades.size() - 1)])
						elif rng.randf() < 0.7:
							tree.call(p, tree_kinds, rng.randf_range(3.0, 4.5))
			else:
				for gx in int(cell.size.x / 4.6):
					for gz in 2:
						var p := cell.position + Vector2(2.4 + gx * 4.6, 3.4 + gz * (cell.size.y - 6.8))
						place.call(pick.call(houses), p, 3.3, (0.0 if gz == 0 else PI), Color(0.97, 0.96, 0.94))
						if rng.randf() < 0.5:
							tree.call(p + Vector2(rng.randf_range(-1.6, 1.6), 2.6 if gz == 0 else -2.6), tree_kinds, rng.randf_range(3.0, 4.5))


# --- stands, concourse, facilities ---------------------------------------

var _club: ClubState
var ground_name := ""
var show_stand_labels := false
var show_offers := false:   # land-for-sale strips, only while buying land
	set(v):
		show_offers = v
		if _offers:
			_offers.visible = v and layer == "stadium" and not _night   # crowd numbers now live in the hover tip
var matchday_live := false   # true during the matchday moment: flares and tifo
var _display: Node3D
var pitch_pattern := "stripes"
var surroundings := "town"     # shown on the main stand (stadium or sponsor name)
var _hollow_from := 999   # rows from this index back are raised over an internal concourse


func build_layout(layout: Layout, config: SimConfig, report: MatchdayReport, selected: int, club: ClubState) -> void:
	_club = club
	for g in [_solids, _ghosts, _concourse, _bowl, _outside, _under, _markers]:
		for c in g.get_children():
			c.free()
	_roofs.clear()
	_levels.clear()
	var cd := config.integer("layout/concourse_depth")
	var main_stand := _main_stand(layout, config)
	var ghost_m := mat(Color(0.85, 0.9, 1.0), 1.0, 0.0, 0.0, 0.14)
	for i in layout.stands.size():
		var s := layout.stands[i]
		var root := Node3D.new()
		_solids.add_child(root)
		_hollow_from = s.depth - cd if Layout.internal_concourse(s, config) and s.tiers == 1 else 999
		if s.is_corner():
			_build_corner(root, s, layout.pitch, i == selected, _stand_label(s, i, config, report))
		else:
			_build_stand(root, s, layout.pitch, i == selected, _stand_label(s, i, config, report), i == main_stand)
		var top := stand_top(s) + 0.6
		if s.shape == "rounded":
			sector(_ghosts, corner_frame(s.side, layout.pitch), 0.0, float(s.depth), 0.0, top, ghost_m)
		else:
			var r := tiles_xz(s.tiles(layout.pitch))
			box(_ghosts, Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, top, r.end.y), ghost_m, false)
		for lv in s.tiers:
			var y := deck_y(s, lv)
			var deck_m := tex_mat("concrete_floor_02", Color(0.68, 0.67, 0.65), 3.0, true) if lv == 0 else tex_mat("concrete_floor_02", Color(0.62, 0.61, 0.6), 3.0, true)
			for t in layout.stand_concourse(s, config):
				if layout.in_plot(t):
					box(_level_node(lv), Vector3(t.x, y - (0.05 if lv == 0 else 0.25), t.y), Vector3(t.x + 1, y, t.y + 1), deck_m, lv > 0)
			if lv > 0:
				# deck edge rail in club colour so levels read clearly
				var cr := tiles_xz(layout.stand_concourse(s, config))
				_rect_outline(_level_node(lv), cr, y, mat(_club.primary_color, 0.5), 0.06)
	var stand_tiles := layout.stand_tile_map()
	var conc_map := layout.concourse_tile_map(config)
	for f in layout.facilities:
		var ft := config.facility_type(f.type_id)
		match ft.layer:
			"bowl":
				if stand_tiles.has(f.pos):
					_build_bowl_item(f, ft, layout.stands[stand_tiles[f.pos]], layout.pitch)
			"underground":
				_build_underground_item(f, ft, layout)
			"outside":
				_build_outside_item(f, ft)
			_:
				var y := 0.05
				if conc_map.has(f.pos):
					y = deck_y(layout.stands[conc_map[f.pos]], f.level)
				_build_facility(f, ft, y)
	if layout.shell != "none" and not layout.stands.is_empty():
		# one building: the stands' own roofs give way to the continuous roof
		for r in _roofs:
			r.queue_free()
		_roofs.clear()
		var ms := main_stand
		_build_shell(layout, layout.stands[ms].side if ms >= 0 else "S")
	_build_landscape(layout, config)
	_build_underground_floor(layout)
	_build_floodlights(layout)
	build_crowd(layout, config, report)
	_display.build(layout, config, report, club, matchday_live)
	_display.visible = layer == "stadium"
	_offers.visible = layer == "stadium" and not _night and not matchday_live and show_offers
	set_layer(layer)


## Which groups show in each view: the overall stadium, the concourse level
## (stands go see-through) and underground (the ground is lifted away).
func _level_node(lv: int) -> Node3D:
	if not _levels.has(lv):
		var n := Node3D.new()
		_concourse.add_child(n)
		_levels[lv] = n
	return _levels[lv]


## Concourse floor height for a level, averaged over stands that have it.
static func level_height(layout: Layout, lv: int) -> float:
	var sum := 0.0
	var n := 0
	for s in layout.stands:
		if s.tiers > lv:
			sum += deck_y(s, lv)
			n += 1
	return sum / n if n > 0 else 0.0


## Floodlights up full for night games.
var _night := false
var _weather_node: Node3D


## Snowy versions of the trees while it snows.
func _snow_trees(layout: Layout) -> void:
	for c in _trees.get_children():
		if c is MultiMeshInstance3D and c.has_meta("tree"):
			var mm: MultiMesh = (c as MultiMeshInstance3D).multimesh
			var copy := MultiMeshInstance3D.new()
			var m2 := MultiMesh.new()
			m2.transform_format = MultiMesh.TRANSFORM_3D
			m2.use_colors = true
			m2.mesh = mm.mesh
			m2.instance_count = mm.instance_count
			for i in mm.instance_count:
				m2.set_instance_transform(i, mm.get_instance_transform(i))
				m2.set_instance_color(i, mm.get_instance_color(i).lerp(Color(0.92, 0.95, 1.0), 0.65))
			copy.multimesh = m2
			_weather_node.add_child(copy)


## Rain or snow falling over the ground ("clear" removes it). Snow also dusts the pitch.
func set_weather(w: String, layout: Layout) -> void:
	if _weather_node:
		_weather_node.free()
		_weather_node = null
	_trees.visible = layer != "underground"
	for c in _trees.get_children():
		c.visible = true
	if _terrain_mat:
		_terrain_mat.set_shader_parameter("snow", 0.0)
	if w == "clear":
		return
	_weather_node = Node3D.new()
	add_child(_weather_node)
	var pl := Rect2(layout.plot)
	var p := CPUParticles3D.new()
	p.position = Vector3(pl.get_center().x, 26.0, pl.get_center().y)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(pl.size.x / 2.0 + 10.0, 1.0, pl.size.y / 2.0 + 10.0)
	p.direction = Vector3(0.15, -1, 0.05)
	p.spread = 4.0
	p.gravity = Vector3.ZERO
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if w == "rain":
		p.amount = 5000
		p.lifetime = 1.0
		p.initial_velocity_min = 26.0
		p.initial_velocity_max = 30.0
		var q := BoxMesh.new()
		q.size = Vector3(0.02, 0.6, 0.02)
		m.albedo_color = Color(0.75, 0.8, 0.9, 0.45)
		q.material = m
		p.mesh = q
	else:
		p.amount = 4000
		p.lifetime = 9.0
		p.preprocess = 9.0
		p.initial_velocity_min = 2.5
		p.initial_velocity_max = 3.5
		p.spread = 25.0
		var q := SphereMesh.new()
		q.radius = 0.06
		q.height = 0.12
		q.radial_segments = 4
		q.rings = 2
		m.albedo_color = Color(1, 1, 1, 0.9)
		q.material = m
		p.mesh = q
		var pr := layout.pitch
		box(_weather_node, Vector3(pr.position.x, 0.035, pr.position.y), Vector3(pr.end.x, 0.045, pr.end.y), mat(Color(0.95, 0.97, 1.0), 1.0, 0.0, 0.0, 0.55), false)
		# snow over the whole landscape (under the pitch dusting), and on the roofs
		if _terrain_mat:
			_terrain_mat.set_shader_parameter("snow", 0.85)
		for s in layout.stands:
			if s.roof == "open":
				continue
			var foot := tiles_xz(s.tiles(layout.pitch))
			var y := stand_top(s) + ROOF_CLEARANCE + 0.55
			box(_weather_node, Vector3(foot.position.x, y, foot.position.y), Vector3(foot.end.x, y + 0.06, foot.end.y), mat(Color(0.95, 0.96, 1.0), 0.9, 0.0, 0.0, 0.8), false)
		for c in _trees.get_children():
			if c.has_meta("tree"):
				c.visible = false
		_snow_trees(layout)
	if w == "rain":
		p.preprocess = 1.0
	_weather_node.add_child(p)


func set_night(on: bool) -> void:
	_night = on
	ProcBuildings.set_night(on)
	_offers.visible = layer == "stadium" and not on and show_offers
	for s in _spots:
		s.light_energy = 14.0 if on else 3.0
		s.spot_range = 75.0 if on else 60.0


## Show the next strip of land for sale on each side, with its price.
func show_land_offers(layout: Layout, prices: Dictionary) -> void:
	for c in _offers.get_children():
		c.free()
	var pl := layout.plot
	var k := layout.strip_tiles
	for side in prices:
		var cost: float = prices[side]
		if cost < 0.0:
			continue
		var r: Rect2
		match side:
			"N": r = Rect2(pl.position.x, pl.position.y - k, pl.size.x, k)
			"S": r = Rect2(pl.position.x, pl.end.y, pl.size.x, k)
			"W": r = Rect2(pl.position.x - k, pl.position.y, k, pl.size.y)
			_: r = Rect2(pl.end.x, pl.position.y, k, pl.size.y)
		box(_offers, Vector3(r.position.x, 0.0, r.position.y), Vector3(r.end.x, 0.03, r.end.y), mat(Color(0.5, 0.9, 0.4), 1.0, 0.0, 0.0, 0.18), false)
		_rect_outline(_offers, r, 0.04, mat(Color(0.7, 1.0, 0.5), 1.0, 0.0, 0.0, 0.6), 0.1)
		var lab := _label(_offers, "FOR SALE  %s" % Season.money(cost), Vector3(r.get_center().x, 1.5, r.get_center().y), 40, Color(0.8, 1.0, 0.6))
		lab.fixed_size = true
		lab.pixel_size = 0.0007


func set_layer(name: String, lv := 0) -> void:
	layer = name
	level = lv
	for k in _levels:
		_levels[k].visible = name == "stadium" or k == lv
	var st := name == "stadium"
	var co := name == "concourse"
	var un := name == "underground"
	_ground.visible = not un
	_offers.visible = st and not _night and show_offers
	_pitch_node.visible = not un
	_pitch_ghost.visible = un
	_lights.visible = not un
	_trees.visible = not un
	_solids.visible = st
	_ghosts.visible = not st
	_concourse.visible = not un
	_bowl.visible = st
	_outside.visible = not un
	_crowd.visible = st
	if _crowd_standing:
		_crowd_standing.visible = st
	if _seat_node:
		_seat_node.visible = st
	if _display:
		_display.visible = st
	_under.visible = un
	_markers.visible = not un
	if _land:
		_land.visible = not un


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


## Cladding for a stand's outer walls. `trim` = the end walls.
func facade_mat(s: Stand, trim := false) -> StandardMaterial3D:
	match s.facade:
		"brick": return tex_mat("red_brick_03", Color.WHITE if not trim else Color(0.8, 0.8, 0.8), 2.0)
		"glass": return mat(Color(0.55, 0.7, 0.8), 0.08, 0.4) if not trim else mat(Color(0.3, 0.32, 0.36), 0.4, 0.6)
		"steel": return tex_mat("metal_plate", Color(0.85, 0.87, 0.9), 2.0)
		"club": return mat(_club.primary_color, 0.6) if not trim else mat(_club.primary_color.darkened(0.3), 0.6)
	if s.type_id == "premium" and not trim:
		return mat(Color(0.55, 0.45, 0.3), 0.2, 0.0, 0.35)
	return tex_mat("rough_concrete", Color(0.74, 0.74, 0.72), 3.0, true)


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
	var concrete := tex_mat("rough_concrete", Color(0.76, 0.76, 0.74), 3.0, true)
	var seat := mat(seat_color(s), 0.7) if not has_seats(s) else tex_mat("rough_concrete", Color(0.68, 0.68, 0.67), 3.0, true)
	var rail := mat(Color(0.85, 0.75, 0.2), 0.5, 0.5) if s.type_id == "terrace" else mat(Color(0.25, 0.26, 0.28), 0.4, 0.7)
	var top := 0.0
	for v in s.depth:
		var r := tiles_xz(s.row_tiles(pitch, v))
		var hgt := row_height(v)
		top = hgt
		if v >= _hollow_from:
			# raised over the internal concourse: a slab on columns
			box(root, Vector3(r.position.x, hgt - 0.5, r.position.y), Vector3(r.end.x, hgt, r.end.y), concrete)
			var along := Vector2(abs(tp.y), abs(tp.x))
			var length := r.size.x if tp.x == 0.0 else r.size.y
			for k in range(0, int(length) + 1, 4):
				var c := r.position + along * minf(k, length - 0.15) + (r.size - along * length) / 2.0
				box(root, Vector3(c.x - 0.08, 0, c.y - 0.08), Vector3(c.x + 0.08, hgt - 0.5, c.y + 0.08), mat(C_CONCRETE_DARK, 0.8))
		else:
			box(root, Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, hgt, r.end.y), concrete)
		var sr := _shrink_away_from_pitch(r, tp, 0.5 if s.type_id == "safe_standing" else 0.3)
		box(root, Vector3(sr.position.x + 0.03, hgt, sr.position.y + 0.03), Vector3(sr.end.x - 0.03, hgt + 0.07, sr.end.y - 0.03), seat)
		if (s.type_id == "terrace" and v % 2 == 1) or s.type_id == "safe_standing":
			var b := _shrink_away_from_pitch(r, tp, 0.92 if s.type_id == "terrace" else 0.6)
			box(root, Vector3(b.position.x, hgt, b.position.y), Vector3(b.end.x, hgt + 0.3, b.end.y), rail)
	var foot := tiles_xz(s.lower_tiles(pitch))
	var fr := _frame(root, foot, tp)
	var L := foot.size.x if tp.x == 0.0 else foot.size.y
	var D := foot.size.y if tp.x == 0.0 else foot.size.x
	var dark := mat(C_CONCRETE_DARK, 0.9)
	# back wall (glazed hospitality for premium) and end walls
	var wall_m := facade_mat(s)
	dark = facade_mat(s, true)
	lbox(fr, Vector3(0, (top + 1.1) / 2.0, -D / 2.0 + 0.07), Vector3(L, top + 1.1, 0.14), wall_m)
	if s.tiers <= 1:
		_facade_detail(fr, s, L, -D / 2.0, top + 1.1, is_main)
	_gangways(fr, s, L, D)
	# front parapet along the touchline edge
	lbox(fr, Vector3(0, ROW_BASE + 0.12, D / 2.0 - 0.04), Vector3(L, 0.24, 0.08), mat(Color(0.18, 0.18, 0.2), 0.5))
	for e in [-1, 1]:
		lbox(fr, Vector3(e * (L / 2.0 - 0.06), (top + 0.5) / 2.0, 0), Vector3(0.12, top + 0.5, D), dark)
	# upper tiers: stepped slabs further back and higher, with a club-coloured
	# fascia along the front, end walls and a full-height back wall
	for k in range(1, s.tiers):
		var base := tier_base(s, k)
		var tf := tier_front(s, k)
		for i in s.depth:
			var zf := D / 2.0 - tf - i
			var y := base + row_height(i)
			lbox(fr, Vector3(0, y - 0.3, zf - 0.5), Vector3(L, 0.6, 1.0), concrete)
			lbox(fr, Vector3(0, y + 0.035, zf - 0.35), Vector3(L - 0.06, 0.07, 0.68), seat)
			if s.type_id == "safe_standing" or (s.type_id == "terrace" and i % 2 == 1):
				lbox(fr, Vector3(0, y + 0.15, zf - 0.6), Vector3(L - 0.06, 0.3, 0.05), rail)
		var front_z := D / 2.0 - tf
		lbox(fr, Vector3(0, base - 0.2, front_z + 0.03), Vector3(L, 0.75, 0.08), mat(_club.primary_color, 0.5))
		var t_top := base + row_height(s.depth - 1)
		for e in [-1, 1]:
			lbox(fr, Vector3(e * (L / 2.0 - 0.06), (base - 0.6 + t_top + 0.5) / 2.0, front_z - s.depth / 2.0),
				Vector3(0.12, t_top + 0.5 - base + 0.6, float(s.depth)), dark)
		top = t_top
	var extra := float(tier_front(s, s.tiers - 1))
	if s.tiers > 1:
		var bz := -D / 2.0 - extra + 0.07
		lbox(fr, Vector3(0, (top + 1.1) / 2.0, bz), Vector3(L, top + 1.1, 0.14), wall_m)
		_facade_detail(fr, s, L, bz - 0.07, top + 1.1, is_main)
		for e in [-1, 1]:
			lbox(fr, Vector3(e * (L / 2.0 - 0.06), (top + 1.1) / 2.0, -D / 2.0 - extra / 2.0), Vector3(0.12, top + 1.1, extra), dark)
	# roof (covers every tier: a frame shifted back by the upper tiers' setback)
	var roof := Node3D.new()
	fr.add_child(roof)
	roof.position.z = -extra / 2.0
	D += extra
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
		n.text = (ground_name if ground_name != "" else _club.club_name).to_upper()
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
	l.visible = show_stand_labels
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 40
	l.fixed_size = true
	l.pixel_size = 0.0006
	l.outline_size = 12
	l.modulate = Color(0.6, 1.0, 0.6) if label["full"] else Color.WHITE
	l.position = Vector3(foot.get_center().x, stand_top(s) + ROOF_CLEARANCE + 1.6, foot.get_center().y)
	root.add_child(l)
	if selected:
		box(root, Vector3(foot.position.x - 0.1, 0, foot.position.y - 0.1), Vector3(foot.end.x + 0.1, top + 0.4, foot.end.y + 0.1),
			mat(Color(1.0, 0.85, 0.2), 1.0, 0.0, 0.0, 0.28), false)


const SIDE_NAMES := { "N": "NORTH", "S": "SOUTH", "E": "EAST", "W": "WEST" }


## The stand's name on its back wall, the way grounds label their stands.
func stand_title(s: Stand, is_main: bool) -> String:
	if is_main:
		return "MAIN STAND"
	match s.type_id:
		"family": return "FAMILY STAND"
		"terrace", "safe_standing": return "%s TERRACE" % SIDE_NAMES.get(s.side, "")
	return "%s STAND" % SIDE_NAMES.get(s.side, "")


## The outside of a stand: a dark plinth, the facade's own surface (precast
## panels, brick, steel ribs or glazing), a club-coloured band, the stand's name,
## turnstile entrances with shutters, canopies and signs, and downpipes.
func _facade_detail(fr: Node3D, s: Stand, L: float, z: float, h: float, is_main := false) -> void:
	var out := z - 0.08
	var pil := facade_mat(s, true)
	var joint := mat(Color(0.32, 0.32, 0.31), 0.9)
	var plinth_m := tex_mat("concrete_tile_facade", Color(1.5, 1.5, 1.5), 2.0)
	var glazing := mat(Color(0.16, 0.2, 0.24), 0.12, 0.5)
	var frame_m := mat(Color(0.24, 0.25, 0.27), 0.4, 0.7)
	var club_c := _club.primary_color
	# plinth: a heavier base course along the bottom
	lbox(fr, Vector3(0, 0.6, out - 0.02), Vector3(L + 0.04, 1.2, 0.14), plinth_m)
	lbox(fr, Vector3(0, 1.22, out - 0.05), Vector3(L + 0.06, 0.06, 0.2), joint)
	match s.facade:
		"glass":
			for k in range(0, int(L) + 1, 2):
				var x := -L / 2.0 + float(k)
				lbox(fr, Vector3(x, (h + 1.2) / 2.0, out), Vector3(0.06, h - 1.2, 0.06), frame_m)
			for y in range(2, int(h)):
				lbox(fr, Vector3(0, float(y), out), Vector3(L, 0.04, 0.05), frame_m)
		"steel":
			for k in range(0, int(L * 4)):
				lbox(fr, Vector3(-L / 2.0 + 0.125 + k * 0.25, (h + 1.2) / 2.0, out + 0.02), Vector3(0.04, h - 1.2, 0.04), mat(Color(0.6, 0.62, 0.66), 0.35, 0.8))
		"brick":
			for k in range(0, int(L) + 1, 3):
				lbox(fr, Vector3(-L / 2.0 + float(k), h / 2.0, out), Vector3(0.3, h, 0.16), pil)
			# stone string courses
			for y in [h * 0.55, h - 0.55]:
				if y > 1.5:
					lbox(fr, Vector3(0, y, out - 0.03), Vector3(L, 0.1, 0.1), mat(Color(0.78, 0.74, 0.66), 0.85))
			_window_band(fr, L, h, out, glazing, frame_m, 3.0)
		"club":
			for k in range(0, int(L) + 1, 3):
				lbox(fr, Vector3(-L / 2.0 + float(k), h / 2.0, out), Vector3(0.22, h, 0.12), pil)
			_window_band(fr, L, h, out, glazing, frame_m, 3.0)
		_:
			# precast concrete panels: joints every 1.5 tiles and between storeys
			var k := 0.0
			while k <= L + 0.01:
				lbox(fr, Vector3(-L / 2.0 + k, (h + 1.2) / 2.0, out - 0.005), Vector3(0.03, h - 1.2, 0.03), joint)
				k += 1.5
			var y := 1.2 + 1.4
			while y < h - 0.5:
				lbox(fr, Vector3(0, y, out - 0.005), Vector3(L, 0.03, 0.03), joint)
				y += 1.4
			# deep pilasters every 6 tiles, so the wall has rhythm and shadow
			for p in range(0, int(L) + 1, 6):
				lbox(fr, Vector3(-L / 2.0 + float(p), h / 2.0, out - 0.04), Vector3(0.28, h, 0.2), pil)
			_window_band(fr, L, h, out, glazing, frame_m, 6.0)
	# club-coloured band and coping
	if h > 2.2:
		lbox(fr, Vector3(0, h - 0.42, out - 0.03), Vector3(L + 0.02, 0.24, 0.06), mat(club_c, 0.55))
	lbox(fr, Vector3(0, h - 0.06, out - 0.03), Vector3(L + 0.12, 0.14, 0.24), mat(club_c.darkened(0.25), 0.5))
	# the stand's name, big letters on the back wall
	if h > 3.0 and L > 8.0:
		var t := Label3D.new()
		t.text = stand_title(s, is_main)
		t.font_size = 128
		t.pixel_size = 0.0085
		t.outline_size = 10
		t.outline_modulate = _club.primary_color.darkened(0.3)
		t.modulate = _club.secondary_color if s.facade != "glass" else Color(0.95, 0.95, 0.95)
		t.position = Vector3(0, h - 1.2, out - 0.07)
		t.rotation.y = PI
		fr.add_child(t)
	# turnstile entrances: recessed, half-raised shutters, a canopy and a lit sign
	var n_ent := maxi(1, int(L / 7.0))
	var shutter := tex_mat("corrugated_iron", Color(0.62, 0.64, 0.66), 1.0)
	for e in n_ent:
		var cx := -L / 2.0 + (e + 0.5) * L / n_ent
		lbox(fr, Vector3(cx, 0.5, out - 0.04), Vector3(1.5, 1.0, 0.04), mat(Color(0.05, 0.05, 0.06), 0.8))
		lbox(fr, Vector3(cx, 0.82, out - 0.07), Vector3(1.4, 0.36, 0.03), shutter)
		for side in [-1, 1]:
			lbox(fr, Vector3(cx + side * 0.78, 0.55, out - 0.08), Vector3(0.08, 1.1, 0.1), frame_m)
		lbox(fr, Vector3(cx, 1.12, out - 0.3), Vector3(1.9, 0.05, 0.56), mat(club_c.darkened(0.35), 0.5))
		lbox(fr, Vector3(cx, 1.36, out - 0.07), Vector3(1.2, 0.24, 0.05), mat(club_c, 0.4, 0.0, 0.5))
		var sign := Label3D.new()
		sign.text = "TURNSTILES %s" % char(65 + e)
		sign.font_size = 32
		sign.pixel_size = 0.0045
		sign.outline_size = 0
		sign.modulate = Color(1, 1, 1)
		sign.position = Vector3(cx, 1.36, out - 0.1)
		sign.rotation.y = PI
		fr.add_child(sign)
		lbox(fr, Vector3(cx, 0.03, out - 0.35), Vector3(1.8, 0.06, 0.6), plinth_m)
	# downpipes between the entrances
	for e in n_ent + 1:
		var cx := -L / 2.0 + e * L / n_ent
		cx = clampf(cx, -L / 2.0 + 0.2, L / 2.0 - 0.2)
		lbox(fr, Vector3(cx, h / 2.0, out - 0.12), Vector3(0.06, h, 0.06), mat(Color(0.2, 0.21, 0.22), 0.5, 0.4))


## Bands of windows: one near the top, and one per storey below it on tall walls.
func _window_band(fr: Node3D, L: float, h: float, out: float, glass: Material, frame_m: Material, bay: float) -> void:
	if h < 3.0:
		return
	var top_y := h - 1.0 - (0.6 if h > 3.6 else 0.0)
	var rows: Array[float] = [top_y]
	var y := top_y - 2.4
	while y > 2.2:
		rows.append(y)
		y -= 2.4
	var n := maxi(1, int(L / bay))
	var w := minf(bay - 0.9, 2.6)
	for wy in rows:
		for k in n:
			var cx := -L / 2.0 + (k + 0.5) * L / n
			lbox(fr, Vector3(cx, wy, out - 0.02), Vector3(w, 0.5, 0.04), glass)
			lbox(fr, Vector3(cx, wy - 0.28, out - 0.05), Vector3(w + 0.1, 0.05, 0.1), frame_m)
			for m in range(1, int(w / 0.7) + 1):
				lbox(fr, Vector3(cx - w / 2.0 + m * w / (int(w / 0.7) + 1), wy, out - 0.04), Vector3(0.03, 0.5, 0.03), frame_m)


## Stair gangways up through the seating every ~7 tiles, with handrails.
func _gangways(fr: Node3D, s: Stand, L: float, D: float) -> void:
	var n := maxi(1, int(L / 7.0))
	var step_m := mat(Color(0.86, 0.86, 0.84), 0.8)
	var rail := mat(Color(0.75, 0.77, 0.8), 0.3, 0.8)
	for g in n:
		var x := -L / 2.0 + (g + 0.5) * L / n
		for v in s.depth:
			var zf := D / 2.0 - v
			var y := row_height(v)
			# two steps per row, a lighter colour so the aisle reads
			lbox(fr, Vector3(x, y - ROW_RISE * 0.5 + 0.01, zf - 0.25), Vector3(0.42, 0.04, 0.5), step_m)
			lbox(fr, Vector3(x, y + 0.01, zf - 0.75), Vector3(0.42, 0.04, 0.5), step_m)
		for e in [-1, 1]:
			var h0 := row_height(0) + 0.35
			var h1 := row_height(s.depth - 1) + 0.35
			var len := sqrt(float(s.depth * s.depth) + (h1 - h0) * (h1 - h0))
			lbox(fr, Vector3(x + e * 0.24, (h0 + h1) / 2.0, D / 2.0 - s.depth / 2.0), Vector3(0.03, 0.03, len), rail, atan2(h1 - h0, float(s.depth)))


## Modern roof on columns at the back, pitched gently backwards so rain runs
## away from the pitch, with a club-coloured fascia. Returns fascia height.
func _roof_cantilever(roof: Node3D, L: float, D: float, top: float, length: int) -> float:
	var front_y := top + ROOF_CLEARANCE + 0.25
	var back_y := top + ROOF_CLEARANCE - 0.35
	var z0 := -D / 2.0
	var z1 := D / 2.0 + 0.7
	var run := z1 - z0
	var tilt := -atan2(front_y - back_y, run)
	lbox(roof, Vector3(0, (front_y + back_y) / 2.0 + 0.07, (z0 + z1) / 2.0), Vector3(L, 0.14, sqrt(run * run + 0.36)), tex_mat("corrugated_iron", Color(0.74, 0.76, 0.78), 2.0), tilt)
	lbox(roof, Vector3(0, front_y - 0.08, z1 - 0.06), Vector3(L, 0.55, 0.12), mat(_club.primary_color, 0.5))
	# gutter along the back
	lbox(roof, Vector3(0, back_y, z0 - 0.05), Vector3(L, 0.12, 0.16), mat(Color(0.3, 0.32, 0.35), 0.5, 0.6))
	# steel rafters under the sheeting, every 2.5 tiles, and a purlin along the front
	var steel := mat(Color(0.55, 0.57, 0.6), 0.35, 0.8)
	var nr := maxi(2, int(L / 2.5) + 1)
	for k in nr:
		var x := (float(k) / float(nr - 1) - 0.5) * (L - 0.3)
		lbox(roof, Vector3(x, (front_y + back_y) / 2.0 - 0.12, (z0 + z1) / 2.0), Vector3(0.09, 0.22, sqrt(run * run + 0.36)), steel, tilt)
	lbox(roof, Vector3(0, front_y - 0.4, z1 - 0.3), Vector3(L, 0.08, 0.08), steel)
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
	var skin := tex_mat("corrugated_iron", Color(0.7, 0.73, 0.76), 1.5)
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
	# tie bars across each rib and a leading-edge beam
	var steel := mat(Color(0.5, 0.52, 0.56), 0.35, 0.8)
	for k in ribs:
		var x := (float(k) / float(ribs - 1) - 0.5) * (L - 0.1)
		lbox(roof, Vector3(x, base_y - 0.05, centre_z), Vector3(0.06, 0.06, z1 - z0), steel)
	lbox(roof, Vector3(0, base_y - 0.12, z1 - 0.05), Vector3(L, 0.22, 0.14), mat(_club.primary_color, 0.5))
	return base_y - 0.1


## "Goalpost" roof: no pillars in the way, the front hangs from a big steel
## truss spanning the whole stand on two tall end towers.
func _roof_truss(roof: Node3D, L: float, D: float, top: float) -> float:
	var front_y := top + ROOF_CLEARANCE + 0.2
	var back_y := top + ROOF_CLEARANCE - 0.3
	var z0 := -D / 2.0
	var z1 := D / 2.0 + 0.7
	var run := z1 - z0
	lbox(roof, Vector3(0, (front_y + back_y) / 2.0, (z0 + z1) / 2.0), Vector3(L, 0.14, sqrt(run * run + 0.25)), tex_mat("corrugated_iron", Color(0.74, 0.76, 0.78), 2.0), -atan2(front_y - back_y, run))
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
	var tin := tex_mat("corrugated_iron", Color(0.55, 0.6, 0.55), 2.0)
	for side in [[front, ridge_z], [back, ridge_z]]:
		var z0: float = side[0]
		var z1: float = side[1]
		var run := absf(z1 - z0)
		var slope := sqrt(run * run + RIDGE_RISE * RIDGE_RISE)
		var ang := atan2(RIDGE_RISE, run) * (1.0 if z0 > z1 else -1.0)
		lbox(roof, Vector3(0, (eave + ridge) / 2.0, (z0 + z1) / 2.0), Vector3(L, 0.1, slope + 0.1), tin, ang)
	# ridge cap
	lbox(roof, Vector3(0, ridge + 0.04, ridge_z), Vector3(L + 0.05, 0.1, 0.22), mat(Color(0.3, 0.32, 0.3), 0.5, 0.4))
	# king-post trusses under the roof every ~3 tiles: tie beam, king post and struts
	var timber := mat(Color(0.45, 0.47, 0.5), 0.4, 0.7)
	var nt := maxi(2, int(L / 3.0) + 1)
	for k in nt:
		var x := (float(k) / float(nt - 1) - 0.5) * (L - 0.2)
		lbox(roof, Vector3(x, eave - 0.02, ridge_z), Vector3(0.08, 0.1, front - back), timber)
		lbox(roof, Vector3(x, (eave + ridge) / 2.0 - 0.05, ridge_z), Vector3(0.08, ridge - eave, 0.08), timber)
		for side in [front, back]:
			var mid: float = (side + ridge_z) / 2.0
			var run := absf(mid - ridge_z)
			var rise := (ridge - eave) * 0.5
			var ang := atan2(rise, run) * (1.0 if side > ridge_z else -1.0)
			lbox(roof, Vector3(x, eave + rise / 2.0, (mid + ridge_z) / 2.0), Vector3(0.06, 0.06, sqrt(run * run + rise * rise)), timber, ang)
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
	# mirrored quadrants reverse the winding; keep every face front-facing outward
	var flip := sx * sz < 0.0
	var quad := func(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, n: Vector3) -> void:
		for v in ([a, cc, b, a, d, cc] if flip else [a, b, cc, a, cc, d]):
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


## A gangway up the diagonal of a corner stand: lighter steps on each row, with handrails.
func _corner_gangway(root: Node3D, s: Stand, pitch: Rect2i) -> void:
	var cf := corner_frame(s.side, pitch)
	var c: Vector2 = cf["centre"]
	var d := Vector2(float(cf["sx"]), float(cf["sz"])).normalized()
	var step_m := mat(Color(0.86, 0.86, 0.84), 0.8)
	var rail := mat(Color(0.75, 0.77, 0.8), 0.3, 0.8)
	var g := Node3D.new()
	g.position = Vector3(c.x, 0, c.y)
	g.rotation.y = atan2(d.x, d.y)
	root.add_child(g)
	# in this frame +Z runs out from the pitch corner along the diagonal
	var scale_r := 1.0 if s.shape == "rounded" else sqrt(2.0)
	for v in s.depth:
		var r0 := v * scale_r
		var y := row_height(v)
		lbox(g, Vector3(0, y + 0.01, r0 + scale_r * 0.5), Vector3(0.44, 0.04, scale_r * 0.9), step_m)
	var h0 := row_height(0) + 0.35
	var h1 := row_height(s.depth - 1) + 0.35
	var run := s.depth * scale_r
	for e in [-1, 1]:
		lbox(g, Vector3(e * 0.25, (h0 + h1) / 2.0, run / 2.0), Vector3(0.03, 0.03, sqrt(run * run + (h1 - h0) * (h1 - h0))), rail, -atan2(h1 - h0, run))


func _build_rounded_corner(root: Node3D, s: Stand, pitch: Rect2i, selected: bool, label: Dictionary) -> void:
	var cf := corner_frame(s.side, pitch)
	var concrete := tex_mat("rough_concrete", Color(0.76, 0.76, 0.74), 3.0, true)
	var seat := mat(seat_color(s), 0.7) if not has_seats(s) else tex_mat("rough_concrete", Color(0.68, 0.68, 0.67), 3.0, true)
	var top := 0.0
	for v in s.depth:
		var hgt := row_height(v)
		top = hgt
		sector(root, cf, float(v), float(v + 1), hgt - 0.5 if v >= _hollow_from else 0.0, hgt, concrete)
		sector(root, cf, v + 0.04, v + 0.7, hgt, hgt + 0.07, seat)
	for k in range(1, s.tiers):
		var base := tier_base(s, k)
		var tf := float(tier_front(s, k))
		for v in s.depth:
			var y := base + row_height(v)
			sector(root, cf, tf + v, tf + v + 1, y - 0.6, y, concrete)
			sector(root, cf, tf + v + 0.04, tf + v + 0.7, y, y + 0.07, seat)
		sector(root, cf, tf - 0.06, tf + 0.04, base - 0.55, base + 0.2, mat(_club.primary_color, 0.5))
		top = base + row_height(s.depth - 1)
	var R := float(s.depth + tier_front(s, s.tiers - 1))
	sector(root, cf, R - 0.14, R, 0.0, top + 1.1, facade_mat(s))
	sector(root, cf, R - 0.04, R + 0.12, top + 1.0, top + 1.16, mat(_club.primary_color.darkened(0.15), 0.5))
	var cc: Vector2 = cf["centre"]
	for k in range(1, 6):
		var phi := PI / 2.0 * k / 6.0
		var p := cc + Vector2(float(cf["sx"]) * cos(phi), float(cf["sz"]) * sin(phi)) * (R + 0.05)
		box(root, Vector3(p.x - 0.14, 0, p.y - 0.14), Vector3(p.x + 0.14, top + 1.1, p.y + 0.14), facade_mat(s, true))
	_corner_gangway(root, s, pitch)
	if s.roof != "open":
		var roof := Node3D.new()
		root.add_child(roof)
		_roofs.append(roof)
		roof.visible = show_roofs
		var ry := top + ROOF_CLEARANCE
		sector(roof, cf, 0.0, R, ry, ry + 0.14, tex_mat("corrugated_iron", Color(0.74, 0.76, 0.78), 2.0), 18)
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
	l.visible = show_stand_labels
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
	var concrete := tex_mat("rough_concrete", Color(0.76, 0.76, 0.74), 3.0, true)
	var seat := mat(seat_color(s), 0.7) if not has_seats(s) else tex_mat("rough_concrete", Color(0.68, 0.68, 0.67), 3.0, true)
	var top := 0.0
	for v in s.depth:
		var hgt := row_height(v)
		top = hgt
		for t in s.row_tiles(pitch, v):
			box(root, Vector3(t.x, hgt - 0.5 if v >= _hollow_from else 0.0, t.y), Vector3(t.x + 1, hgt, t.y + 1), concrete)
			box(root, Vector3(t.x + 0.06, hgt, t.y + 0.06), Vector3(t.x + 0.94, hgt + 0.07, t.y + 0.94), seat)
	for k in range(1, s.tiers):
		var base := tier_base(s, k)
		var tf := tier_front(s, k)
		for v in s.depth:
			var y := base + row_height(v)
			for ab in s._corner_cells(tf + v, 1):
				var t := Stand.corner_to_grid(s.side, pitch, ab.x, ab.y)
				box(root, Vector3(t.x, y - 0.6, t.y), Vector3(t.x + 1, y, t.y + 1), concrete)
				box(root, Vector3(t.x + 0.06, y, t.y + 0.06), Vector3(t.x + 0.94, y + 0.07, t.y + 0.94), seat)
		top = base + row_height(s.depth - 1)
	var R := s.depth + tier_front(s, s.tiers - 1)
	var outer: Array[Vector2i] = [Stand.corner_to_grid(s.side, pitch, 0, 0), Stand.corner_to_grid(s.side, pitch, R - 1, R - 1)]
	var foot := tiles_xz(outer)
	var dark := facade_mat(s)
	for axis in [Vector2(tp.x, 0), Vector2(0, tp.y)]:
		var w := _strip_away_from_pitch(foot, axis, 0.14)
		box(root, Vector3(w.position.x, 0, w.position.y), Vector3(w.end.x, top + 1.1, w.end.y), dark)
		# pilasters and a club-colour coping on the outer walls
		var out: Vector2 = -axis * 0.1
		var long := w.size.x > w.size.y
		var n := int((w.size.x if long else w.size.y) / 3.0)
		for k in n + 1:
			var p: Vector2 = w.position + (Vector2(k * 3.0, 0) if long else Vector2(0, k * 3.0)) + out
			box(root, Vector3(p.x - 0.14, 0, p.y - 0.14), Vector3(p.x + 0.14 , top + 1.1, p.y + 0.14), facade_mat(s, true))
		box(root, Vector3(w.position.x + out.x - 0.05, top + 1.0, w.position.y + out.y - 0.05), Vector3(w.end.x + out.x + 0.05, top + 1.16, w.end.y + out.y + 0.05), mat(_club.primary_color.darkened(0.15), 0.5))
	_corner_gangway(root, s, pitch)
	if s.roof != "open":
		var roof := Node3D.new()
		root.add_child(roof)
		_roofs.append(roof)
		roof.visible = show_roofs
		var ry := top + ROOF_CLEARANCE
		var rr := _grow_toward_pitch(_grow_toward_pitch(foot, Vector2(tp.x, 0), 0.7), Vector2(0, tp.y), 0.7)
		box(roof, Vector3(rr.position.x, ry, rr.position.y), Vector3(rr.end.x, ry + 0.14, rr.end.y), tex_mat("corrugated_iron", Color(0.74, 0.76, 0.78), 2.0))
		for axis in [Vector2(tp.x, 0), Vector2(0, tp.y)]:
			var f := _strip_toward_pitch(rr, axis, 0.12)
			box(roof, Vector3(f.position.x, ry - 0.35, f.position.y), Vector3(f.end.x, ry + 0.2, f.end.y), mat(_club.primary_color, 0.5))
		var c := Vector2(foot.position.x if tp.x > 0 else foot.end.x, foot.position.y if tp.y > 0 else foot.end.y)
		c -= tp * 0.15
		box(roof, Vector3(c.x - 0.12, 0, c.y - 0.12), Vector3(c.x + 0.12, ry, c.y + 0.12), mat(C_ROOF, 0.4, 0.6))
	var l := Label3D.new()
	l.text = label["text"]
	l.visible = show_stand_labels
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 40
	l.fixed_size = true
	l.pixel_size = 0.0006
	l.outline_size = 12
	l.modulate = Color(0.6, 1.0, 0.6) if label["full"] else Color.WHITE
	l.position = Vector3(foot.get_center().x, stand_top(s) + ROOF_CLEARANCE + 1.6, foot.get_center().y)
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


func _style(f: Facility, ft: FacilityType) -> String:
	return f.style if f.style != "" else ft.styles[0]


func _label(parent: Node3D, text: String, pos: Vector3, size := 48, color := Color.WHITE, billboard := true, px := 0.006) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.outline_size = 8
	l.modulate = color
	l.position = pos
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(l)
	return l


# --- concourse level -----------------------------------------------------------

func _build_facility(f: Facility, ft: FacilityType, y := 0.05) -> void:
	var g := Node3D.new()
	g.position = Vector3(f.pos.x, y, f.pos.y)
	_level_node(f.level).add_child(g)
	var w := float(ft.size.x)
	var d := float(ft.size.y)
	var st := _style(f, ft)
	var home := _club.primary_color
	match ft.id:
		"kiosk":
			match st:
				"food_truck":
					box(g, Vector3(0.05, 0.12, 0.2), Vector3(0.7, 0.75, 0.8), mat(Color(0.95, 0.95, 0.92), 0.5))
					box(g, Vector3(0.7, 0.12, 0.25), Vector3(0.95, 0.55, 0.75), mat(home, 0.5))
					box(g, Vector3(0.15, 0.4, 0.17), Vector3(0.6, 0.62, 0.2), mat(Color(1.0, 0.8, 0.4), 0.3, 0.0, 1.5))
					for x in [0.2, 0.75]:
						box(g, Vector3(x - 0.08, 0.0, 0.18), Vector3(x + 0.08, 0.16, 0.82), mat(Color(0.1, 0.1, 0.1)))
				"pie_hut":
					box(g, Vector3(0.12, 0.0, 0.15), Vector3(0.88, 0.6, 0.85), mat(Color(0.55, 0.38, 0.22), 0.9))
					lbox(g, Vector3(0.5, 0.75, 0.33), Vector3(0.9, 0.06, 0.45), mat(Color(0.3, 0.18, 0.1)), 0.5)
					lbox(g, Vector3(0.5, 0.75, 0.67), Vector3(0.9, 0.06, 0.45), mat(Color(0.3, 0.18, 0.1)), -0.5)
					box(g, Vector3(0.25, 0.3, 0.12), Vector3(0.75, 0.45, 0.16), mat(Color(1.0, 0.75, 0.35), 0.3, 0.0, 1.5))
				_:
					box(g, Vector3(0.1, 0.0, 0.15), Vector3(0.9, 0.7, 0.85), mat(Color(0.93, 0.9, 0.82), 0.8))
					box(g, Vector3(0.02, 0.67, 0.05), Vector3(0.98, 0.75, 0.95), mat(Color(0.95, 0.55, 0.12), 0.6))
					box(g, Vector3(0.2, 0.35, 0.1), Vector3(0.8, 0.5, 0.16), mat(Color(1.0, 0.8, 0.4), 0.3, 0.0, 1.5))
		"bar":
			if st == "modern":
				box(g, Vector3(0.05, 0.0, 0.1), Vector3(0.95, 0.75, 0.9), mat(Color(0.5, 0.8, 0.9), 0.1, 0.3, 0.0, 0.55))
				box(g, Vector3(0.1, 0.0, 0.15), Vector3(0.9, 0.4, 0.4), mat(Color(0.15, 0.15, 0.18), 0.3))
				box(g, Vector3(0.1, 0.62, 0.08), Vector3(0.9, 0.72, 0.12), mat(Color(0.2, 0.9, 1.0), 0.2, 0.0, 2.0))
			else:
				box(g, Vector3(0.05, 0.0, 0.1), Vector3(0.95, 0.75, 0.9), mat(Color(0.3, 0.18, 0.1), 0.8))
				box(g, Vector3(0.0, 0.75, 0.05), Vector3(1.0, 0.82, 0.95), mat(Color(0.12, 0.25, 0.12), 0.7))
				box(g, Vector3(0.2, 0.5, 0.06), Vector3(0.8, 0.65, 0.1), mat(Color(0.3, 1.0, 0.4), 0.3, 0.0, 1.5))
				for x in [0.2, 0.8]:
					var b := MeshInstance3D.new()
					var cm := CylinderMesh.new()
					cm.top_radius = 0.1
					cm.bottom_radius = 0.1
					cm.height = 0.25
					b.mesh = cm
					b.material_override = mat(Color(0.45, 0.28, 0.12))
					b.position = Vector3(x, 0.12, 0.0)
					g.add_child(b)
		"merch":
			if st == "megastore":
				box(g, Vector3(0.05, 0.0, 0.1), Vector3(w - 0.05, 1.0, d - 0.1), mat(home, 0.5))
				box(g, Vector3(0.2, 0.05, 0.06), Vector3(w - 0.2, 0.6, 0.12), mat(Color(0.85, 0.9, 1.0), 0.1, 0.0, 0.6))
				_label(g, "CLUB STORE", Vector3(w / 2.0, 0.82, 0.02), 40, _club.secondary_color, false, 0.006)
			else:
				for x in range(int(w)):
					box(g, Vector3(x + 0.1, 0.0, 0.3), Vector3(x + 0.9, 0.35, 0.7), mat(Color(0.4, 0.3, 0.2)))
					box(g, Vector3(x + 0.2, 0.35, 0.4), Vector3(x + 0.45, 0.42, 0.6), mat(home))
					box(g, Vector3(x + 0.55, 0.35, 0.4), Vector3(x + 0.8, 0.42, 0.6), mat(_club.secondary_color))
				box(g, Vector3(0.0, 0.8, 0.1), Vector3(w, 0.86, d - 0.1), mat(home, 0.6))
				for x in [0.1, w - 0.15]:
					box(g, Vector3(x, 0.0, 0.15), Vector3(x + 0.05, 0.8, 0.2), mat(Color(0.3, 0.3, 0.3)))
		"restroom":
			if st == "modern":
				box(g, Vector3(0.08, 0.0, 0.08), Vector3(0.92, 0.85, 0.92), mat(Color(0.92, 0.93, 0.95), 0.4))
				box(g, Vector3(0.08, 0.55, 0.06), Vector3(0.92, 0.65, 0.1), mat(Color(0.1, 0.75, 0.7), 0.4, 0.0, 0.8))
			else:
				box(g, Vector3(0.08, 0.0, 0.08), Vector3(0.92, 0.8, 0.92), mat(Color(0.75, 0.82, 0.9), 0.8))
				box(g, Vector3(0.02, 0.8, 0.02), Vector3(0.98, 0.88, 0.98), mat(Color(0.15, 0.35, 0.75), 0.6))
			_label(g, "WC", Vector3(0.5, 1.15, 0.5), 40, Color(0.7, 0.85, 1.0))
		"first_aid":
			box(g, Vector3(0.1, 0.0, 0.1), Vector3(0.9, 0.7, 0.9), mat(Color(0.97, 0.97, 0.97), 0.6))
			box(g, Vector3(0.42, 0.7, 0.2), Vector3(0.58, 0.74, 0.8), mat(Color(0.9, 0.1, 0.1), 0.5, 0.0, 0.6))
			box(g, Vector3(0.2, 0.7, 0.42), Vector3(0.8, 0.74, 0.58), mat(Color(0.9, 0.1, 0.1), 0.5, 0.0, 0.6))
		"fan_zone":
			box(g, Vector3(0.0, 0.0, 0.0), Vector3(w, 0.03, d), mat(Color(0.25, 0.45, 0.25) if st == "beer_garden" else Color(0.35, 0.55, 0.9), 0.9))
			if st == "family_zone":
				var cols := [Color(1, 0.3, 0.3), Color(1, 0.85, 0.2), Color(0.3, 0.8, 0.4), Color(0.4, 0.6, 1)]
				for k in 4:
					var px := 0.3 + (k % 2) * 1.0
					var pz := 0.3 + (k / 2) * 1.0
					box(g, Vector3(px, 0.0, pz), Vector3(px + 0.5, 0.35 + 0.15 * k, pz + 0.5), mat(cols[k], 0.6))
			else:
				for k in 4:
					var px := 0.25 + (k % 2) * 1.0
					var pz := 0.3 + (k / 2) * 1.0
					box(g, Vector3(px, 0.25, pz), Vector3(px + 0.55, 0.3, pz + 0.3), mat(Color(0.45, 0.3, 0.15)))
					var um := MeshInstance3D.new()
					var cone := CylinderMesh.new()
					cone.top_radius = 0.0
					cone.bottom_radius = 0.4
					cone.height = 0.25
					um.mesh = cone
					um.material_override = mat(home if k % 2 == 0 else _club.secondary_color, 0.7)
					um.position = Vector3(px + 0.27, 0.85, pz + 0.15)
					g.add_child(um)
					box(g, Vector3(px + 0.25, 0.0, pz + 0.13), Vector3(px + 0.3, 0.75, pz + 0.18), mat(Color(0.3, 0.3, 0.3)))
			box(g, Vector3(w / 2.0 - 0.5, 0.6, 0.0), Vector3(w / 2.0 + 0.5, 1.2, 0.06), mat(Color(0.3, 0.6, 1.0), 0.2, 0.0, 1.5))
		_:
			box(g, Vector3(0.1, 0.0, 0.1), Vector3(w - 0.1, 0.7, d - 0.1), mat(Color(0.8, 0.8, 0.8)))


# --- in the bowl -------------------------------------------------------------------

## A frame on a stand (side or corner): origin at the footprint centre, local +Z
## toward the pitch, plus the stand's length along local X, depth and top height.
func _stand_frame(s: Stand, pitch: Rect2i) -> Dictionary:
	var foot := tiles_xz(s.lower_tiles(pitch))
	var tp := to_pitch(s.side).normalized()
	var fr := Node3D.new()
	fr.position = Vector3(foot.get_center().x, 0, foot.get_center().y)
	fr.rotation.y = atan2(tp.x, tp.y)
	_bowl.add_child(fr)
	var L := float(s.depth) if s.is_corner() else (foot.size.x if tp.x == 0.0 else foot.size.y)
	var D := float(s.depth) if s.is_corner() else (foot.size.y if tp.x == 0.0 else foot.size.x)
	var extra := float(tier_front(s, s.tiers - 1))
	fr.position -= Vector3(tp.x, 0, tp.y) * extra / 2.0
	return { "node": fr, "L": L, "D": D + extra, "top": stand_top(s) }


func _build_bowl_item(f: Facility, ft: FacilityType, s: Stand, pitch: Rect2i) -> void:
	var sf := _stand_frame(s, pitch)
	var fr: Node3D = sf["node"]
	var L: float = sf["L"]
	var D: float = sf["D"]
	var top: float = sf["top"]
	var roof_y := top + ROOF_CLEARANCE + (0.3 if s.roof != "open" else -1.2)
	var st := _style(f, ft)
	var dark := mat(Color(0.08, 0.08, 0.1), 0.4, 0.3)
	var steel := mat(Color(0.3, 0.32, 0.35), 0.4, 0.7)
	match ft.id:
		"video_board":
			var sw := minf(L * 0.45, 9.0) if st == "classic" else minf(L * 0.8, 16.0)
			var sh := 2.4 if st == "classic" else 1.2
			var base := roof_y + (0.8 if st == "classic" else 0.2)
			var z := -D / 2.0 + 0.4 if st == "classic" else D / 2.0 + 0.6
			if st == "classic":
				for e in [-1, 1]:
					lbox(fr, Vector3(e * sw * 0.35, base / 2.0, z - 0.1), Vector3(0.25, base, 0.25), steel)
			lbox(fr, Vector3(0, base + sh / 2.0, z), Vector3(sw + 0.3, sh + 0.3, 0.25), dark)
			var screen := lbox(fr, Vector3(0, base + sh / 2.0, z + 0.14), Vector3(sw, sh, 0.04), mat(Color(0.04, 0.06, 0.1), 0.2, 0.0, 1.0))
			# LED graphic: club-colour band, trim stripe and the crest-ish disc
			var band := lbox(fr, Vector3(0, base + sh * 0.5, z + 0.165), Vector3(sw * 0.94, sh * 0.42, 0.01), mat(_club.primary_color, 0.3, 0.0, 1.6))
			band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lbox(fr, Vector3(0, base + sh * 0.27, z + 0.168), Vector3(sw * 0.94, sh * 0.05, 0.01), mat(_club.secondary_color, 0.3, 0.0, 1.4))
			screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var lab := _label(fr, _club.club_name.to_upper(), Vector3(0, base + sh / 2.0, z + 0.18), 64, Color.WHITE, false, minf(0.01, sw / 900.0))
			lab.outline_size = 0
		"ribbon_board":
			var y := row_height(maxi(0, s.depth / 2)) + 0.25
			var z := D / 2.0 - (s.depth / 2 + 0.5) - 0.02
			lbox(fr, Vector3(0, y, z), Vector3(L - 0.2, 0.28, 0.05), mat(_club.primary_color.lerp(Color(1, 1, 1), 0.15), 0.2, 0.0, 2.0))
			var lab := _label(fr, "%s  •  MATCHDAY  •  %s" % [_club.club_name.to_upper(), _club.club_name.to_upper()], Vector3(0, y, z + 0.04), 36, _club.secondary_color, false, 0.005)
			lab.outline_size = 0
		"scoreboard":
			var y := roof_y + 0.5
			var z := D / 2.0 + 0.5
			if st == "retro":
				lbox(fr, Vector3(0, y + 0.6, z), Vector3(3.2, 1.2, 0.15), mat(Color(0.1, 0.3, 0.15), 0.8))
				_label(fr, "HOME  1   AWAY  0", Vector3(0, y + 0.6, z + 0.09), 48, Color(0.95, 0.95, 0.85), false, 0.005)
			else:
				lbox(fr, Vector3(0, y + 0.5, z), Vector3(2.6, 1.0, 0.2), dark)
				_label(fr, "1 - 0", Vector3(0, y + 0.5, z + 0.11), 96, Color(1.0, 0.6, 0.1), false, 0.007)
			for e in [-1, 1]:
				lbox(fr, Vector3(e * 1.0, y / 2.0, z - 0.1), Vector3(0.12, y, 0.12), steel)
		"exec_boxes":
			if s.tiers < 2:
				return
			var tf := float(s.tier_front(1))
			var zf := D / 2.0 - tf + 0.05
			var y0 := row_height(int(tf)) + 0.35
			var y1 := tier_base(s, 1) - 0.65
			if y1 - y0 < 0.4:
				y0 = y1 - 0.8
			var glass := mat(Color(1.0, 0.85, 0.55), 0.15, 0.0, 1.1) if st == "glass" else mat(Color(0.95, 0.8, 0.5), 0.6, 0.0, 0.7)
			lbox(fr, Vector3(0, (y0 + y1) / 2.0, zf), Vector3(L - 0.3, y1 - y0, 0.06), glass)
			var frame_m := mat(Color(0.15, 0.15, 0.17), 0.4, 0.6) if st == "glass" else mat(Color(0.35, 0.22, 0.12), 0.8)
			var n := int(L / 2.0)
			for k in n + 1:
				var x := -L / 2.0 + 0.15 + k * (L - 0.3) / n
				lbox(fr, Vector3(x, (y0 + y1) / 2.0, zf + 0.04), Vector3(0.08, y1 - y0, 0.06), frame_m)
			lbox(fr, Vector3(0, y0 - 0.05, zf + 0.15), Vector3(L - 0.3, 0.1, 0.35), frame_m)
		"sound_system":
			var y := roof_y - 0.5
			var n := maxi(2, int(L / 6.0) + 1)
			for k in n:
				var x := (float(k) / float(n - 1) - 0.5) * (L - 1.0)
				lbox(fr, Vector3(x, y, D / 2.0 + 0.2), Vector3(0.45, 0.7, 0.4), dark)
				lbox(fr, Vector3(x, y, D / 2.0 + 0.41), Vector3(0.3, 0.3, 0.02), mat(Color(0.25, 0.25, 0.28), 0.3, 0.5))
				lbox(fr, Vector3(x, y + 0.5, D / 2.0 + 0.2), Vector3(0.04, 0.4, 0.04), steel)


# --- outside -----------------------------------------------------------------------

func _build_outside_item(f: Facility, ft: FacilityType) -> void:
	var g := Node3D.new()
	g.position = Vector3(f.pos.x, 0.0, f.pos.y)
	_outside.add_child(g)
	var w := float(ft.size.x)
	var d := float(ft.size.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = f.pos.x * 1000 + f.pos.y
	match ft.id:
		"car_park":
			box(g, Vector3(0.05, 0.0, 0.05), Vector3(w - 0.05, 0.03, d - 0.05), tex_mat("asphalt_01", Color(0.55, 0.55, 0.58), 3.0), false)
			var bay := 0.85
			var n := int((w - 0.2) / bay)
			var cars := ["car-kit/sedan", "car-kit/suv", "car-kit/hatchback-sports", "car-kit/van", "car-kit/taxi", "car-kit/sedan-sports", "car-kit/suv-luxury"]
			var by_kind := {}
			for row in [0, 1]:
				var cz := 0.8 if row == 0 else d - 0.8
				for k in n + 1:
					var lx := 0.1 + k * bay
					box(g, Vector3(lx - 0.02, 0.03, cz - 0.7), Vector3(lx + 0.02, 0.035, cz + 0.7), mat(Color(0.92, 0.92, 0.9)), false)
				for k in n:
					if rng.randf() < 0.82:
						var kind: String = cars[rng.randi_range(0, cars.size() - 1)]
						var sc := Kenney.scale_to(kind, 1.3)
						var yaw := 0.0 if row == 0 else PI
						if not by_kind.has(kind):
							by_kind[kind] = []
						by_kind[kind].append(Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.05, 0.05)).scaled(Vector3(sc, sc, sc)), Vector3(0.1 + (k + 0.5) * bay, 0.03, cz)))
			for kind in by_kind:
				var arr: Array[Transform3D] = []
				arr.assign(by_kind[kind])
				g.add_child(Kenney.batch(kind, arr))
		"statue":
			var st := _style(f, ft)
			box(g, Vector3(0.25, 0.0, 0.25), Vector3(0.75, 0.6, 0.75), mat(Color(0.55, 0.55, 0.55), 0.8))
			var bronze := mat(Color(0.55, 0.38, 0.2), 0.35, 0.8)
			box(g, Vector3(0.42, 0.6, 0.42), Vector3(0.58, 1.3, 0.58), bronze)
			var head := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = 0.11
			sph.height = 0.22
			head.mesh = sph
			head.material_override = bronze
			head.position = Vector3(0.5, 1.42, 0.5)
			g.add_child(head)
			if st == "celebration":
				lbox(g, Vector3(0.36, 1.35, 0.5), Vector3(0.06, 0.4, 0.06), bronze, 0.0)
				lbox(g, Vector3(0.64, 1.35, 0.5), Vector3(0.06, 0.4, 0.06), bronze, 0.0)
			elif st == "founder":
				box(g, Vector3(0.4, 0.6, 0.38), Vector3(0.6, 1.0, 0.62), mat(Color(0.4, 0.28, 0.15), 0.4, 0.8))
			else:
				var ball := MeshInstance3D.new()
				var bs := SphereMesh.new()
				bs.radius = 0.08
				bs.height = 0.16
				ball.mesh = bs
				ball.material_override = bronze
				ball.position = Vector3(0.65, 0.68, 0.5)
				g.add_child(ball)
		"ticket_office":
			box(g, Vector3(0.05, 0.0, 0.1), Vector3(w - 0.05, 0.9, d - 0.1), mat(_club.primary_color, 0.6))
			for k in 4:
				box(g, Vector3(0.2 + k * 0.42, 0.35, d - 0.12), Vector3(0.5 + k * 0.42, 0.65, d - 0.08), mat(Color(1.0, 0.9, 0.6), 0.2, 0.0, 1.2))
			_label(g, "TICKETS", Vector3(w / 2.0, 1.2, d / 2.0), 40, Color.WHITE)
		"museum":
			var stone := mat(Color(0.85, 0.82, 0.75), 0.8)
			if _style(f, ft) == "modern":
				box(g, Vector3(0.2, 0.0, 0.2), Vector3(w - 0.2, 1.6, d - 0.2), mat(Color(0.75, 0.85, 0.95), 0.1, 0.3, 0.0, 0.7))
				box(g, Vector3(0.1, 1.6, 0.1), Vector3(w - 0.1, 1.75, d - 0.1), mat(_club.primary_color, 0.5))
			else:
				box(g, Vector3(0.2, 0.0, 0.6), Vector3(w - 0.2, 1.5, d - 0.2), stone)
				box(g, Vector3(0.1, 1.5, 0.3), Vector3(w - 0.1, 1.7, d - 0.1), stone)
				for k in 5:
					var cx := 0.4 + k * (w - 0.8) / 4.0
					box(g, Vector3(cx - 0.08, 0.0, 0.35), Vector3(cx + 0.08, 1.5, 0.5), stone)
				var ped := MeshInstance3D.new()
				var pm := PrismMesh.new()
				pm.size = Vector3(w - 0.2, 0.6, d - 0.4)
				ped.mesh = pm
				ped.material_override = stone
				ped.position = Vector3(w / 2.0, 2.0, d / 2.0 + 0.1)
				g.add_child(ped)
			_label(g, "MUSEUM", Vector3(w / 2.0, 2.6, d / 2.0), 44, _club.secondary_color)
		"hotel":
			var floors := 7
			box(g, Vector3(0.3, 0.0, 0.3), Vector3(w - 0.3, floors * 0.6, d - 0.3), mat(Color(0.3, 0.33, 0.38), 0.4, 0.3))
			var rng2 := RandomNumberGenerator.new()
			rng2.seed = f.pos.x * 7 + f.pos.y
			for fl in floors:
				for k in 5:
					if rng2.randf() < 0.65:
						var wx := 0.5 + k * (w - 1.0) / 4.0
						box(g, Vector3(wx - 0.15, fl * 0.6 + 0.2, d - 0.31), Vector3(wx + 0.15, fl * 0.6 + 0.45, d - 0.28), mat(Color(1.0, 0.88, 0.6), 0.2, 0.0, 1.0))
			_label(g, "HOTEL", Vector3(w / 2.0, floors * 0.6 + 0.6, d / 2.0), 48, _club.primary_color.lightened(0.3))
		"train_station":
			box(g, Vector3(0.0, 0.0, 0.0), Vector3(w, 0.35, d * 0.45), mat(Color(0.6, 0.6, 0.58), 0.9))
			box(g, Vector3(0.0, 0.0, d * 0.5), Vector3(w + 6.0, 0.06, d * 0.5 + 0.12), mat(Color(0.4, 0.35, 0.3), 0.6, 0.6))
			box(g, Vector3(0.0, 0.0, d * 0.85), Vector3(w + 6.0, 0.06, d * 0.85 + 0.12), mat(Color(0.4, 0.35, 0.3), 0.6, 0.6))
			for k in range(0, int(w) + 1, 2):
				box(g, Vector3(k + 0.4, 0.35, d * 0.2), Vector3(k + 0.5, 1.5, d * 0.3), mat(Color(0.25, 0.25, 0.28), 0.4, 0.6))
			box(g, Vector3(-0.2, 1.5, -0.1), Vector3(w + 0.2, 1.62, d * 0.5), mat(_club.primary_color, 0.5, 0.3))
			var tsc := Kenney.scale_to("train-kit/train-electric-city-a", 2.9)
			var cars_t: Array[Transform3D] = []
			for k in 4:
				cars_t.append(Transform3D(Basis(Vector3.UP, PI / 2.0).scaled(Vector3(tsc, tsc, tsc)), Vector3(1.6 + k * 2.95, 0.06, d * 0.67)))
			g.add_child(Kenney.batch("train-kit/train-electric-city-a", cars_t))
			_label(g, "STATION", Vector3(w / 2.0, 2.1, d * 0.25), 48, Color.WHITE)
		"bus_stop":
			box(g, Vector3(0.05, 0.0, 0.05), Vector3(w - 0.05, 0.03, d - 0.05), mat(Color(0.5, 0.5, 0.5)), false)
			box(g, Vector3(0.2, 0.0, 0.2), Vector3(0.9, 0.7, 0.35), mat(Color(0.7, 0.85, 0.95), 0.1, 0.2, 0.0, 0.5))
			box(g, Vector3(0.15, 0.7, 0.15), Vector3(0.95, 0.76, 0.6), mat(Color(0.2, 0.2, 0.22)))
			box(g, Vector3(1.0, 0.05, 0.25), Vector3(w + 0.8, 0.75, 0.8), mat(_club.primary_color, 0.5))
			box(g, Vector3(1.05, 0.4, 0.24), Vector3(w + 0.75, 0.6, 0.26), mat(Color(0.8, 0.9, 1.0), 0.1, 0.0, 0.8))
			_label(g, "BUS", Vector3(0.5, 1.1, 0.3), 40, Color(1.0, 0.9, 0.3))


# --- underground -------------------------------------------------------------------

const UNDER_Y := -3.4


func _build_underground_floor(layout: Layout) -> void:
	var pl := layout.plot
	box(_under, Vector3(pl.position.x, UNDER_Y - 0.3, pl.position.y), Vector3(pl.end.x, UNDER_Y, pl.end.y), mat(Color(0.22, 0.17, 0.13), 1.0), false)
	var grid := mat(Color(0.4, 0.32, 0.25), 1.0)
	for x in range(pl.position.x, pl.end.x + 1, 5):
		box(_under, Vector3(x - 0.03, UNDER_Y, pl.position.y), Vector3(x + 0.03, UNDER_Y + 0.01, pl.end.y), grid, false)
	for z in range(pl.position.y, pl.end.y + 1, 5):
		box(_under, Vector3(pl.position.x, UNDER_Y, z - 0.03), Vector3(pl.end.x, UNDER_Y + 0.01, z + 0.03), grid, false)
	_rect_outline(_under, Rect2(Vector2(layout.pitch.position), Vector2(layout.pitch.size)).grow(1), UNDER_Y + 0.01, mat(Color(0.9, 0.3, 0.2), 1.0, 0.0, 0.0, 0.6), 0.12)


func _build_underground_item(f: Facility, ft: FacilityType, layout: Layout) -> void:
	var g := Node3D.new()
	g.position = Vector3(f.pos.x, UNDER_Y, f.pos.y)
	_under.add_child(g)
	var w := float(ft.size.x)
	var d := float(ft.size.y)
	var concrete := mat(Color(0.6, 0.6, 0.58), 0.9)
	match ft.id:
		"garage":
			var rng := RandomNumberGenerator.new()
			rng.seed = f.pos.x * 31 + f.pos.y
			for lvl in 3:
				var y := 0.1 + lvl * 1.05
				box(g, Vector3(0, y - 0.1, 0), Vector3(w, y, d), concrete)
				for k in 6:
					if rng.randf() < 0.75:
						var cx := 0.4 + (k % 3) * (w - 0.8) / 2.0
						var cz := 0.6 if k < 3 else d - 0.6
						box(g, Vector3(cx - 0.18, y, cz - 0.32), Vector3(cx + 0.18, y + 0.28, cz + 0.32), mat(Color.from_hsv(rng.randf(), 0.5, 0.8), 0.4, 0.3))
			for cx in [0.1, w - 0.2]:
				for cz in [0.1, d - 0.2]:
					box(g, Vector3(cx, 0, cz), Vector3(cx + 0.1, 3.2, cz + 0.1), concrete)
			lbox(g, Vector3(w / 2.0, 1.6, d / 2.0), Vector3(0.8, 0.08, d * 0.6), mat(Color(0.95, 0.8, 0.2), 0.6), 0.35)
			_label(g, "P", Vector3(w / 2.0, 3.8, d / 2.0), 96, Color(0.3, 0.6, 1.0))
			_marker(Vector3(f.pos.x + 0.5, 0, f.pos.y + 0.5), "P", Color(0.2, 0.45, 0.9))
		"subway":
			box(g, Vector3(0, 0, 0), Vector3(w, 0.6, d * 0.45), concrete)
			box(g, Vector3(0, 0, d * 0.55), Vector3(w, 0.6, d), concrete)
			box(g, Vector3(0, 0, d * 0.45), Vector3(w, 0.05, d * 0.55), mat(Color(0.25, 0.2, 0.18)))
			# tunnel to the edge of the plot and a train
			box(g, Vector3(w, 0, d * 0.35), Vector3(layout.plot.end.x - f.pos.x, 1.4, d * 0.65), mat(Color(0.3, 0.3, 0.32), 0.9, 0.0, 0.0, 0.6), false)
			var ssc := Kenney.scale_to("train-kit/train-electric-subway-a", 2.4) * 0.8
			var sub_t: Array[Transform3D] = []
			for k in 4:
				sub_t.append(Transform3D(Basis(Vector3.UP, PI / 2.0).scaled(Vector3(ssc, ssc, ssc)), Vector3(1.0 + k * 1.95, 0.05, d * 0.5)))
			g.add_child(Kenney.batch("train-kit/train-electric-subway-a", sub_t))
			_label(g, "M", Vector3(w / 2.0, 2.3, d / 2.0), 96, Color(1.0, 0.25, 0.2))
			_marker(Vector3(f.pos.x + 0.5, 0, f.pos.y + 0.5), "M", Color(0.85, 0.15, 0.12))


## A street-level entrance for an underground item, seen from the stadium view.
func _marker(p: Vector3, letter: String, color: Color) -> void:
	box(_markers, p + Vector3(-0.4, 0, -0.4), p + Vector3(0.4, 0.5, 0.4), mat(Color(0.25, 0.25, 0.27), 0.7))
	box(_markers, p + Vector3(-0.1, 0.5, -0.1), p + Vector3(0.1, 1.6, 0.1), mat(Color(0.3, 0.3, 0.3), 0.5, 0.6))
	box(_markers, p + Vector3(-0.3, 1.6, -0.05), p + Vector3(0.3, 2.2, 0.05), mat(color, 0.4, 0.0, 1.0))
	_label(_markers, letter, p + Vector3(0, 1.9, 0), 64, Color.WHITE, true, 0.006)


# --- crowd -----------------------------------------------------------------

## Stand types with individual seats (the rest stand on terrace steps).
static func has_seats(s: Stand) -> bool:
	return s.type_id in ["seated", "premium", "family"]


## Every place in a stand: [position (xz), floor height, tier, row, toward-pitch dir, along dir].
## Fans and seats share these slots, so fans sit in seats.
func _stand_slots(layout: Layout, s: Stand, per_tile: int) -> Array:
	var out := []
	var cols := ceili(per_tile / 2.0)
	var tp := to_pitch(s.side).normalized()
	var along := Vector2(-tp.y, tp.x)
	# aisle centres (distance along the stand) to keep clear for the gangways
	var aisles := []
	var along_abs := along.abs()
	var lower := tiles_xz(s.lower_tiles(layout.pitch))
	var origin := lower.position
	if not s.is_corner():
		var L := lower.size.x if tp.x == 0.0 else lower.size.y
		var n := maxi(1, int(L / 7.0))
		for g in n:
			aisles.append((g + 0.5) * L / n)
	for tier in s.tiers:
		for v in s.depth:
			var row_tiles: Array[Vector2i] = []
			var tf := tier_front(s, tier)
			if tier == 0:
				row_tiles = s.row_tiles(layout.pitch, v)
			elif s.is_corner():
				for ab in s._corner_cells(tf + v, 1):
					row_tiles.append(Stand.corner_to_grid(s.side, layout.pitch, ab.x, ab.y))
			else:
				row_tiles = s._band(layout.pitch, s.setback + tf + v, 1)
			var y_row := tier_base(s, tier) + row_height(v)
			for tile in row_tiles:
				var centre := Vector2(tile) + Vector2(0.5, 0.5)
				for k in per_tile:
					var a := (float(k % cols) + 0.5) / cols - 0.5
					var depth_off := 0.22 - (k / cols) * 0.32
					var pos := centre + along * a * 0.9 + tp * depth_off
					if s.is_corner():
						# keep the diagonal gangway clear
						var cf := corner_frame(s.side, layout.pitch)
						var rel: Vector2 = pos - cf["centre"]
						if absf(rel.x * float(cf["sx"]) - rel.y * float(cf["sz"])) < 0.36:
							continue
					if not aisles.is_empty():
						var u := (pos - origin).dot(along_abs)
						var in_aisle := false
						for ax in aisles:
							if absf(u - ax) < 0.24:
								in_aisle = true
						if in_aisle:
							continue
					out.append([pos, y_row, tier, v, tp, along])
	return out


var _seat_node: MultiMeshInstance3D


## Fold-down seats (pan + backrest) in every seated stand, in the stand's seat colour.
func build_seats(layout: Layout, config: SimConfig) -> void:
	if _seat_node == null:
		_seat_node = MultiMeshInstance3D.new()
		_solids.get_parent().add_child(_seat_node)
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	for s in layout.stands:
		if not has_seats(s):
			continue
		var t := config.stand_type(s.type_id)
		var c := seat_color(s)
		for slot in _stand_slots(layout, s, maxi(1, roundi(t.capacity_per_tile / FIGURES_PER_PLACES))):
			var p: Vector2 = slot[0]
			var tp: Vector2 = slot[4]
			xf.append(Transform3D(Basis(Vector3.UP, atan2(tp.x, tp.y)), Vector3(p.x, slot[1], p.y)))
			cols.append(c)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _seat_mesh()
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
	_seat_node.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.55
	_seat_node.material_override = m


var _seat_mesh_cache: Mesh


## A seat facing local +Z (toward the pitch): pan, backrest and a stem.
func _seat_mesh() -> Mesh:
	if _seat_mesh_cache:
		return _seat_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in [[Vector3(0, 0.13, 0.0), Vector3(0.2, 0.03, 0.17)], [Vector3(0, 0.25, -0.09), Vector3(0.2, 0.22, 0.03)], [Vector3(0, 0.06, -0.02), Vector3(0.04, 0.12, 0.04)]]:
		var bm := BoxMesh.new()
		bm.size = part[1]
		st.append_from(bm, 0, Transform3D(Basis(), part[0]))
	_seat_mesh_cache = st.commit()
	return _seat_mesh_cache


var _fan_meshes := {}


## A fan, built from primitives, with each body part tagged in UV2.x for the
## crowd shader (see crowd.gdshader). `seated` bends the legs onto a seat.
## The mesh origin is the floor (standing) or the seat pan (seated).
func _fan_mesh(seated: bool) -> Mesh:
	if _fan_meshes.has(seated):
		return _fan_meshes[seated]
	var H := 0.0 if seated else 0.25   # hip height above the origin
	var parts := []
	var torso := CapsuleMesh.new()
	torso.radius = 0.062
	torso.height = 0.21
	torso.radial_segments = 10
	torso.rings = 3
	parts.append([torso, Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.62)), Vector3(0, H + 0.095, 0)), 0])
	var head := SphereMesh.new()
	head.radius = 0.048
	head.height = 0.1
	head.radial_segments = 10
	head.rings = 6
	parts.append([head, Transform3D(Basis(), Vector3(0, H + 0.245, 0.004)), 1])
	var hair := SphereMesh.new()
	hair.radius = 0.051
	hair.height = 0.075
	hair.is_hemisphere = true
	hair.radial_segments = 10
	hair.rings = 4
	parts.append([hair, Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, H + 0.255, -0.004)), 2])
	var scarf := TorusMesh.new()
	scarf.inner_radius = 0.03
	scarf.outer_radius = 0.052
	scarf.rings = 10
	scarf.ring_segments = 6
	parts.append([scarf, Transform3D(Basis().scaled(Vector3(1.0, 0.6, 0.8)), Vector3(0, H + 0.19, 0.0)), 5])
	for side in [-1.0, 1.0]:
		var arm := CapsuleMesh.new()
		arm.radius = 0.019
		arm.height = 0.17
		arm.radial_segments = 6
		arm.rings = 2
		parts.append([arm, Transform3D(Basis(Vector3.FORWARD, side * 0.12), Vector3(side * 0.083, H + 0.085, 0.0)), 3])
		var hand := SphereMesh.new()
		hand.radius = 0.02
		hand.height = 0.04
		hand.radial_segments = 6
		hand.rings = 3
		parts.append([hand, Transform3D(Basis(), Vector3(side * 0.093, H + 0.0, 0.01)), 4])
		var leg := CapsuleMesh.new()
		leg.radius = 0.026
		leg.radial_segments = 6
		leg.rings = 2
		if seated:
			leg.height = 0.15
			parts.append([leg, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(side * 0.034, 0.0, 0.065)), 6])
			var shin := CapsuleMesh.new()
			shin.radius = 0.024
			shin.height = 0.14
			shin.radial_segments = 6
			shin.rings = 2
			parts.append([shin, Transform3D(Basis(), Vector3(side * 0.034, -0.06, 0.14)), 6])
		else:
			leg.height = 0.26
			parts.append([leg, Transform3D(Basis(), Vector3(side * 0.033, 0.125, 0.0)), 6])
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for pt in parts:
		var arr: Array = (pt[0] as PrimitiveMesh).get_mesh_arrays()
		var xf: Transform3D = pt[1]
		var base := verts.size()
		var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for k in pv.size():
			verts.append(xf * pv[k])
			norms.append((xf.basis * pn[k]).normalized())
			uv2.append(Vector2(float(pt[2]), 0.0))
		for k in (arr[Mesh.ARRAY_INDEX] as PackedInt32Array):
			idx.append(base + k)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	out[Mesh.ARRAY_TEX_UV2] = uv2
	out[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	_fan_meshes[seated] = m
	return m


var _crowd_standing: MultiMeshInstance3D
var _crowd_mat_standing: ShaderMaterial


func build_crowd(layout: Layout, config: SimConfig, report: MatchdayReport) -> void:
	build_seats(layout, config)
	if _crowd_standing == null:
		_crowd_standing = MultiMeshInstance3D.new()
		_crowd.get_parent().add_child(_crowd_standing)
		_crowd_mat_standing = ShaderMaterial.new()
		_crowd_mat_standing.shader = _crowd_mat.shader
	var sets := { true: [[], [], []], false: [[], [], []] }   # seated? -> [transforms, colours, customs]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	if report != null:
		for i in layout.stands.size():
			var s := layout.stands[i]
			var t := config.stand_type(s.type_id)
			if i >= report.stands.size() or report.stands[i]["capacity"] != s.capacity(t):
				continue
			var fill: float = report.stands[i]["fill"]
			var tifo := matchday_live and i == tifo_stand(layout, config, report)
			if tifo:
				fill = maxf(fill, 0.98)
			var seated := has_seats(s)
			var bucket: Array = sets[seated]
			var origin := tiles_xz(s.lower_tiles(layout.pitch)).position
			for slot in _stand_slots(layout, s, maxi(1, roundi(t.capacity_per_tile / FIGURES_PER_PLACES))):
				if rng.randf() >= fill:
					continue
				var p: Vector2 = slot[0] + Vector2(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03))
				var tp: Vector2 = slot[4]
				var along: Vector2 = slot[5]
				var sc := rng.randf_range(0.88, 1.1)
				var y: float = slot[1] + (0.16 if seated else 0.0)
				var basis := Basis(Vector3.UP, atan2(tp.x, tp.y) + rng.randf_range(-0.25, 0.25)).scaled(Vector3(sc, sc, sc))
				var kind := 0.5 if rng.randf() < 0.3 else 0.0
				if tifo and slot[2] == 0:
					basis = Basis(Vector3.UP, atan2(tp.x, tp.y)).scaled(Vector3(2.2, 1.0, 2.2))
					bucket[1].append(_tifo_color(report.seed, slot[3], s.depth, (p - origin).dot(along.abs())))
					kind = 1.0
				else:
					bucket[1].append(_shirt(s.type_id, rng))
				bucket[0].append(Transform3D(basis, Vector3(p.x, y, p.y)))
				bucket[2].append(Color(rng.randf(), t.noise / 1.5, rng.randf(), kind))
	var cheer := 0.0 if report == null else clampf((report.atmosphere - 25.0) / 60.0, 0.0, 1.0) * (1.0 if matchday_live else 0.35)
	for seated in [true, false]:
		var node: MultiMeshInstance3D = _crowd if seated else _crowd_standing
		var smat: ShaderMaterial = _crowd_mat if seated else _crowd_mat_standing
		var b: Array = sets[seated]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _fan_mesh(seated)
		mm.instance_count = b[0].size()
		for i in b[0].size():
			mm.set_instance_transform(i, b[0][i])
			mm.set_instance_color(i, b[1][i])
			mm.set_instance_custom_data(i, b[2][i])
		node.multimesh = mm
		node.material_override = smat
		smat.set_shader_parameter("bounce", 0.0 if report == null else report.atmosphere / 100.0 * 0.12)
		smat.set_shader_parameter("cheer", cheer)
		smat.set_shader_parameter("hip", 0.0 if seated else 0.25)
		smat.set_shader_parameter("scarf_color", _club.secondary_color if _club else Color.WHITE)


## Which stand shows a tifo: big, loud matches only; the biggest home end
## (terrace / safe standing first), else the biggest stand.
func tifo_stand(layout: Layout, config: SimConfig, report: MatchdayReport) -> int:
	if report == null or not report.big_match or report.atmosphere < 40.0:
		return -1
	var best := -1
	var best_score := 0.0
	for i in layout.stands.size():
		var s := layout.stands[i]
		if s.is_corner() or i >= report.stands.size():
			continue
		var score := float(s.capacity(config.stand_type(s.type_id))) * (2.0 if s.type_id in ["terrace", "safe_standing"] else 1.0)
		if score > best_score:
			best_score = score
			best = i
	return best


## Card colour at (row v, position along the stand). Pattern picked per match.
func _tifo_color(seed: int, v: int, depth: int, along: float) -> Color:
	var home := _club.primary_color
	var away := _club.secondary_color
	match seed % 4:
		0: return home if (v / 2) % 2 == 0 else away                      # horizontal bands
		1: return home if int(along / 3.0) % 2 == 0 else away             # vertical stripes
		2: return home if (int(along) + v) % 6 < 3 else away              # diagonal sash
	return away if v >= depth / 3 and v < depth * 2 / 3 else home         # one big band


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

const C_OK := Color(0.4, 1.0, 0.45)
const C_NO := Color(1.0, 0.38, 0.3)


## Where a dragged item will land: a glowing footprint with a bright outline on
## the ground, a see-through block, and a bobbing arrow above it.
func _drop_marker(r: Rect2, y: float, h: float, ok: bool) -> void:
	var col := C_OK if ok else C_NO
	box(_overlay, Vector3(r.position.x, y + 0.02, r.position.y), Vector3(r.end.x, y + 0.05, r.end.y), mat(col, 1.0, 0.0, 0.0, 0.5), false)
	_rect_outline(_overlay, r.grow(0.08), y + 0.06, mat(col, 1.0, 0.0, 0.0, 0.95), 0.2)
	if h > 0.0:
		box(_overlay, Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y + maxf(h, 0.6), r.end.y), mat(col, 1.0, 0.0, 0.0, 0.35), false)
	var arrow := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.7
	cone.bottom_radius = 0.0
	cone.height = 1.2
	arrow.mesh = cone
	arrow.material_override = mat(col, 1.0, 0.0, 0.0, 0.95)
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var top := y + h + 1.6
	arrow.position = Vector3(r.get_center().x, top, r.get_center().y)
	_overlay.add_child(arrow)
	var tw := arrow.create_tween().set_loops()
	tw.tween_property(arrow, "position:y", top + 0.5, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_property(arrow, "position:y", top, 0.45).set_trans(Tween.TRANS_SINE)


func show_ghost_stand(s: Stand, pitch: Rect2i, ok: bool) -> void:
	clear_overlay()
	_drop_marker(tiles_xz(s.tiles(pitch)), 0.0, row_height(s.depth - 1), ok)


func show_ghost_tile(tile: Vector2i, ok: bool, size := Vector2i.ONE, underground := false, y_base := 0.0) -> void:
	clear_overlay()
	var y0 := UNDER_Y if underground else y_base
	_drop_marker(Rect2(Vector2(tile), Vector2(size)), y0, 3.2 if underground else 0.9, ok)


func show_hover_tile(tile: Vector2i) -> void:
	clear_overlay()
	box(_overlay, Vector3(tile.x, 0.06, tile.y), Vector3(tile.x + 1, 0.09, tile.y + 1), mat(Color(1, 1, 1), 1.0, 0.0, 0.0, 0.3), false)


func clear_overlay() -> void:
	for c in _overlay.get_children():
		c.free()


# --- stadium shell: one outer skin and a continuous roof round the whole ground ---

## Points round a rounded rectangle, clockwise from the top-left of the top edge.
## Inner and outer rings built with the same counts pair up point for point.
static func _rr(r: Rect2, rad: float, nx: int, nz: int, na: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var l := r.position.x + rad
	var rt := r.end.x - rad
	var t := r.position.y + rad
	var b := r.end.y - rad
	var corners := [[Vector2(rt, t), -PI / 2.0], [Vector2(rt, b), 0.0], [Vector2(l, b), PI / 2.0], [Vector2(l, t), PI]]
	var sides := [[Vector2(l, r.position.y), Vector2(rt, r.position.y), nx], [Vector2(r.end.x, t), Vector2(r.end.x, b), nz],
		[Vector2(rt, r.end.y), Vector2(l, r.end.y), nx], [Vector2(r.position.x, b), Vector2(r.position.x, t), nz]]
	for k in 4:
		var sd: Array = sides[k]
		var n: int = sd[2]
		for i in n:
			pts.append((sd[0] as Vector2).lerp(sd[1], float(i) / n))
		var c: Vector2 = corners[k][0]
		var a0: float = corners[k][1]
		for i in na:
			var a := a0 + PI / 2.0 * float(i) / na
			pts.append(c + Vector2(cos(a), sin(a)) * rad)
	return pts


## Outer footprint, inner (roof) edge, roof height and corner radius of the shell.
func shell_geometry(layout: Layout) -> Dictionary:
	var pr := Rect2(layout.pitch)
	var outer := pr.grow(4.0)
	var top := 0.0
	var rounded := false
	for s in layout.stands:
		outer = outer.merge(tiles_xz(s.tiles(layout.pitch)))
		top = maxf(top, stand_top(s))
		rounded = rounded or s.shape == "rounded"
	outer = outer.grow(0.7)
	var margin := minf(minf(pr.position.x - outer.position.x, outer.end.x - pr.end.x), minf(pr.position.y - outer.position.y, outer.end.y - pr.end.y))
	var rad := clampf(margin * (1.0 if rounded else 0.55), 2.0, minf(outer.size.x, outer.size.y) * 0.45)
	var inner := pr.grow(1.2)
	return { "outer": outer, "inner": inner, "h": top + ROOF_CLEARANCE, "rad": rad, "inner_rad": minf(rad * 0.5, 4.0) }


func _shell_rings(g: Dictionary) -> Array:
	var o: Rect2 = g["outer"]
	var nx := maxi(8, int((o.size.x - 2.0 * g["rad"]) / 1.0))
	var nz := maxi(6, int((o.size.y - 2.0 * g["rad"]) / 1.0))
	var na := 10
	return [_rr(o, g["rad"], nx, nz, na), _rr(g["inner"], g["inner_rad"], nx, nz, na)]


## A box spanning a to b (ground plan), from y0 to y1, thickness th, pushed out by `off`
## along the outward normal n; collected into `xf` for one MultiMesh.
static func _seg_xf(a: Vector2, b: Vector2, y0: float, y1: float, th: float, n: Vector2, off: float) -> Transform3D:
	var d := b - a
	var mid := (a + b) / 2.0 + n * off
	var bas := Basis(Vector3.UP, atan2(-d.y, d.x)).scaled(Vector3(d.length() + 0.02, y1 - y0, th))
	return Transform3D(bas, Vector3(mid.x, (y0 + y1) / 2.0, mid.y))


func _mm(parent: Node3D, xf: Array[Transform3D], m: Material, shadows := true) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = m
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## A vertical band following the ring from y0 to y1, `out` metres outside it,
## optionally bulging outward in the middle (an oval, bowl-like skin).
func _band(parent: Node3D, ring: PackedVector2Array, centre: Vector2, y0: float, y1: float, out: float, m: Material, bulge := 0.0, rows := 1) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := ring.size()
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var na := (a - centre).normalized()
		var nb := (b - centre).normalized()
		for r in rows:
			var v0 := float(r) / rows
			var v1 := float(r + 1) / rows
			var o0 := out + bulge * sin(PI * v0)
			var o1 := out + bulge * sin(PI * v1)
			var ya := lerpf(y0, y1, v0)
			var yb := lerpf(y0, y1, v1)
			var p := [Vector3(a.x + na.x * o0, ya, a.y + na.y * o0), Vector3(b.x + nb.x * o0, ya, b.y + nb.y * o0),
				Vector3(b.x + nb.x * o1, yb, b.y + nb.y * o1), Vector3(a.x + na.x * o1, yb, a.y + na.y * o1)]
			var nn := Vector3(na.x + nb.x, -(o1 - o0) / maxf(0.01, yb - ya) * 0.0, na.y + nb.y).normalized()
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(nn)
				st.set_uv(Vector2(float(i) * 0.5, (p[k] as Vector3).y * 0.5))
				st.add_vertex(p[k])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _double_sided(m)
	parent.add_child(mi)


func _build_shell(layout: Layout, main_side: String) -> void:
	var g := shell_geometry(layout)
	var rings := _shell_rings(g)
	var outer: PackedVector2Array = rings[0]
	var inner: PackedVector2Array = rings[1]
	var o: Rect2 = g["outer"]
	var c := o.get_center()
	var H: float = g["h"]
	var wall_h := H - 0.2
	var node := Node3D.new()
	_solids.add_child(node)
	var club_c := _club.primary_color
	var dark_glass := mat(Color(0.1, 0.13, 0.17), 0.08, 0.5)
	var steel := mat(Color(0.3, 0.31, 0.33), 0.4, 0.7)
	var concrete := tex_mat("rough_concrete", Color(0.76, 0.76, 0.74), 3.0, true)
	var n := outer.size()
	# ground floor: a recessed glazed base with entrances all round
	_band(node, outer, c, 0.0, 2.6, -0.6, dark_glass)
	var posts: Array[Transform3D] = []
	var canopies: Array[Transform3D] = []
	for i in range(0, n, 3):
		var a := outer[i]
		var b := outer[(i + 1) % n]
		var nn := ((a + b) / 2.0 - c).normalized()
		posts.append(_seg_xf(a, a + (b - a).normalized() * 0.15, 0.0, 2.6, 0.15, nn, -0.5))
	_mm(node, posts, steel)
	# the main skin, by style
	var xf: Array[Transform3D] = []
	var xf2: Array[Transform3D] = []
	match layout.shell:
		"fins":
			# a dark wall behind close-set bronze louvres, each twisting a little
			_band(node, outer, c, 2.6, wall_h, -0.3, mat(Color(0.14, 0.15, 0.17), 0.7))
			for i in n:
				var a := outer[i]
				var b := outer[(i + 1) % n]
				var nn := ((a + b) / 2.0 - c).normalized()
				for k in 2:
					var p := a.lerp(b, 0.25 + 0.5 * k)
					var t := Transform3D(Basis(Vector3.UP, atan2(-nn.y, nn.x)) * Basis(Vector3.FORWARD, 0.18).scaled(Vector3(0.9, wall_h - 1.6, 0.07)),
						Vector3(p.x + nn.x * 0.2, (wall_h + 1.6) / 2.0 + 0.4, p.y + nn.y * 0.2))
					xf.append(t)
			_mm(node, xf, mat(Color(0.5, 0.38, 0.26), 0.55, 0.35))
		"skin":
			# a smooth oval bowl of metal panels, swelling outward, with panel joints
			var skin := mat(club_c.lerp(Color(0.62, 0.36, 0.24), 0.65), 0.45, 0.55)
			_band(node, outer, c, 2.6, wall_h, -0.2, skin, 1.1, 8)
			var y := 3.2
			while y < wall_h - 0.3:
				var v := (y - 2.6) / (wall_h - 2.6)
				_band(node, outer, c, y, y + 0.05, -0.2 + 1.1 * sin(PI * v) + 0.03, mat(club_c.lerp(Color(0.3, 0.18, 0.12), 0.7), 0.6))
				y += 0.9
		"glass":
			_band(node, outer, c, 2.6, wall_h, 0.0, mat(Color(0.32, 0.45, 0.56), 0.06, 0.6))
			for i in range(0, n, 2):
				var a := outer[i]
				var b := outer[(i + 1) % n]
				var nn := ((a + b) / 2.0 - c).normalized()
				xf.append(_seg_xf(a, a + (b - a).normalized() * 0.07, 2.6, wall_h, 0.1, nn, 0.05))
			var y := 3.8
			while y < wall_h:
				for i in n:
					var nn := ((outer[i] + outer[(i + 1) % n]) / 2.0 - c).normalized()
					xf2.append(_seg_xf(outer[i], outer[(i + 1) % n], y, y + 0.08, 0.1, nn, 0.06))
				y += 1.4
			_mm(node, xf, mat(Color(0.8, 0.82, 0.85), 0.35, 0.7))
			_mm(node, xf2, mat(Color(0.8, 0.82, 0.85), 0.35, 0.7))
		"brick":
			_band(node, outer, c, 2.6, wall_h, 0.0, tex_mat("red_brick_03", Color.WHITE, 2.0))
			for i in range(0, n, 3):
				var a := outer[i]
				var b := outer[(i + 1) % n]
				var nn := ((a + b) / 2.0 - c).normalized()
				# tall windows with stone heads, and pilasters between them
				xf.append(_seg_xf(a.lerp(b, 0.2), a.lerp(b, 0.8), 3.4, wall_h - 1.2, 0.05, nn, 0.04))
				xf2.append(_seg_xf(a, a + (b - a).normalized() * 0.3, 2.6, wall_h, 0.2, nn, 0.08))
			_mm(node, xf, dark_glass)
			_mm(node, xf2, tex_mat("red_brick_03", Color(0.85, 0.85, 0.85), 2.0))
			_band(node, outer, c, wall_h - 0.9, wall_h - 0.75, 0.12, mat(Color(0.82, 0.78, 0.7), 0.85))
		_:  # "arcade": a solid upper band over an open colonnade, like a classic bowl
			_band(node, outer, c, 4.6, wall_h, 0.0, concrete)
			_band(node, outer, c, 4.4, 4.7, 0.15, mat(Color(0.85, 0.84, 0.8), 0.8))
			for i in range(0, n, 2):
				var a := outer[i]
				var b := outer[(i + 1) % n]
				var nn := ((a + b) / 2.0 - c).normalized()
				xf.append(_seg_xf(a, a + (b - a).normalized() * 0.4, 0.0, 4.5, 0.4, nn, 0.05))
			var y := 5.6
			while y < wall_h - 0.4:
				for i in n:
					var nn := ((outer[i] + outer[(i + 1) % n]) / 2.0 - c).normalized()
					xf2.append(_seg_xf(outer[i], outer[(i + 1) % n], y, y + 0.1, 0.1, nn, 0.05))
				y += 1.2
			_mm(node, xf, mat(Color(0.86, 0.85, 0.82), 0.8))
			_mm(node, xf2, mat(Color(0.6, 0.6, 0.6), 0.8))
	# a club-coloured crown band, and the ground's name on the main side
	_band(node, outer, c, wall_h - 0.35, wall_h + 0.05, 0.25 if layout.shell != "skin" else 0.25, mat(club_c, 0.5))
	var label := Label3D.new()
	label.text = (ground_name if ground_name != "" else _club.stadium_name).to_upper()
	label.font_size = 160
	label.pixel_size = 0.011
	label.outline_size = 0
	label.modulate = _club.secondary_color if layout.shell != "glass" else Color(1, 1, 1)
	var sides := { "N": [Vector3(c.x, 0, o.position.y), 0.0], "S": [Vector3(c.x, 0, o.end.y), PI], "E": [Vector3(o.end.x, 0, c.y), -PI / 2.0], "W": [Vector3(o.position.x, 0, c.y), PI / 2.0] }
	var sd: Array = sides.get(main_side, sides["S"])
	var dir := Vector3(sin(sd[1]), 0, cos(sd[1])) * -1.0
	label.position = (sd[0] as Vector3) + Vector3(0, wall_h - 1.4, 0) - dir * (1.4 if layout.shell == "skin" else 0.4)
	label.rotation.y = sd[1] + PI
	node.add_child(label)
	_build_shell_roof(layout, outer, inner, c, H)


func _build_shell_roof(layout: Layout, outer: PackedVector2Array, inner: PackedVector2Array, c: Vector2, H: float) -> void:
	var roof := Node3D.new()
	_solids.add_child(roof)
	_roofs.append(roof)
	roof.visible = show_roofs
	var n := outer.size()
	var rise := 0.9
	var sheet := tex_mat("corrugated_iron", Color(0.8, 0.82, 0.84), 2.0)
	if layout.shell_roof == "ribs":
		sheet = mat(Color(0.5, 0.52, 0.55), 0.6, 0.3)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var j := (i + 1) % n
		var p := [Vector3(outer[i].x, H, outer[i].y), Vector3(outer[j].x, H, outer[j].y),
			Vector3(inner[j].x, H + rise, inner[j].y), Vector3(inner[i].x, H + rise, inner[i].y)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.add_vertex(p[k])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _double_sided(sheet)
	roof.add_child(mi)
	var club_c := _club.primary_color
	var steel := mat(Color(0.82, 0.83, 0.85), 0.35, 0.6)
	# fascia round the inner edge, gutter round the outer edge
	_band(roof, inner, c, H + rise - 0.45, H + rise + 0.05, 0.0, mat(club_c, 0.5))
	_band(roof, outer, c, H - 0.1, H + 0.15, 0.1, mat(Color(0.25, 0.26, 0.28), 0.5, 0.5))
	var xf: Array[Transform3D] = []
	var xf2: Array[Transform3D] = []
	match layout.shell_roof:
		"truss":
			# a big lattice girder along each side of the opening
			var ii := inner
			for i in n:
				var a := ii[i]
				var b := ii[(i + 1) % n]
				var nn := ((a + b) / 2.0 - c).normalized()
				var y0 := H + rise
				xf.append(_seg_xf(a, b, y0 + 1.6, y0 + 1.75, 0.18, nn, -0.6))
				xf.append(_seg_xf(a, b, y0 + 0.05, y0 + 0.2, 0.18, nn, -0.6))
				if i % 2 == 0:
					var mid := (a + b) / 2.0 - nn * 0.6
					var d := b - a
					var t := Transform3D(Basis(Vector3.UP, atan2(-d.y, d.x)) * Basis(Vector3.BACK, 0.55 * (1.0 if i % 4 == 0 else -1.0)) .scaled(Vector3(0.08, 1.9, 0.08)),
						Vector3(mid.x, y0 + 0.9, mid.y))
					xf2.append(t)
			_mm(roof, xf, steel)
			_mm(roof, xf2, steel)
		"masts":
			# leaning masts round the back edge, with tie cables to the front
			for i in range(0, n, 6):
				var a := outer[i]
				var nn := (a - c).normalized()
				var foot := Vector3(a.x + nn.x * 0.3, H, a.y + nn.y * 0.3)
				var head := foot + Vector3(nn.x * 1.2, 5.5, nn.y * 1.2)
				xf.append(_rod(foot, head, 0.22))
				var tip := Vector3(inner[i].x, H + rise, inner[i].y)
				xf2.append(_rod(head, tip, 0.04))
				xf2.append(_rod(head, foot + Vector3(nn.x * 3.0, -H, nn.y * 3.0) * 0.0 + Vector3(nn.x * 2.0, -1.5, nn.y * 2.0), 0.04))
			_mm(roof, xf, mat(club_c, 0.45, 0.3))
			_mm(roof, xf2, mat(Color(0.2, 0.2, 0.22), 0.4, 0.6), false)
		"ribs":
			# light radial ribs across the roof, close together
			for i in n:
				var a := Vector3(outer[i].x, H + 0.12, outer[i].y)
				var b := Vector3(inner[i].x, H + rise + 0.12, inner[i].y)
				xf.append(_rod(a, b, 0.22, 0.12))
			_mm(roof, xf, mat(Color(0.92, 0.93, 0.94), 0.5))
		_:  # "ring": a translucent band of polycarbonate along the front
			var st2 := SurfaceTool.new()
			st2.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in n:
				var j := (i + 1) % n
				var oi := Vector3(inner[i].x, H + rise, inner[i].y).lerp(Vector3(outer[i].x, H, outer[i].y), 0.22)
				var oj := Vector3(inner[j].x, H + rise, inner[j].y).lerp(Vector3(outer[j].x, H, outer[j].y), 0.22)
				var p := [oi + Vector3.UP * 0.02, oj + Vector3.UP * 0.02, Vector3(inner[j].x, H + rise + 0.02, inner[j].y), Vector3(inner[i].x, H + rise + 0.02, inner[i].y)]
				for k in [0, 1, 2, 0, 2, 3]:
					st2.set_normal(Vector3.UP)
					st2.add_vertex(p[k])
			var band := MeshInstance3D.new()
			band.mesh = st2.commit()
			band.material_override = _double_sided(mat(Color(0.9, 0.93, 0.95), 0.2, 0.0, 0.0, 0.55))
			roof.add_child(band)


## A beam from a to b with square section `w` (or w x h).
static func _rod(a: Vector3, b: Vector3, w: float, h := -1.0) -> Transform3D:
	var d := b - a
	var len := d.length()
	var y := d / maxf(len, 0.001)
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x * w, y * len, z * (h if h > 0.0 else w)), (a + b) / 2.0)


# --- landscaping on the plot ---------------------------------------------------

var _land: Node3D

## The free ground on the plot, laid out like a real stadium precinct: a paved
## plaza round the building, lawns beyond it with clipped hedges, paved walks
## out to the streets, an avenue of trees along the edge and copses on the lawns.
func _build_landscape(layout: Layout, config: SimConfig) -> void:
	if _land == null:
		_land = Node3D.new()
		add_child(_land)
	for c in _land.get_children():
		c.free()
	var plot := layout.plot
	var busy := {}
	for t in layout.stand_tile_map():
		busy[t] = true
	for t in layout.concourse_tile_map(config):
		busy[t] = true
	var used := {}
	for f in layout.facilities:
		var ft := config.facility_type(f.type_id)
		if ft.layer == "outside" or ft.layer == "concourse":
			for t in f.tiles(ft):
				used[t] = true
	var pr := layout.pitch
	for x in range(pr.position.x, pr.end.x):
		for y in range(pr.position.y, pr.end.y):
			busy[Vector2i(x, y)] = true
	if layout.shell != "none" and not layout.stands.is_empty():
		var o: Rect2 = shell_geometry(layout)["outer"]
		for x in range(floori(o.position.x), ceili(o.end.x)):
			for y in range(floori(o.position.y), ceili(o.end.y)):
				busy[Vector2i(x, y)] = true
	# distance (in tiles) from the building, by breadth-first search
	var dist := {}
	var queue: Array[Vector2i] = []
	for t in busy:
		if plot.has_point(t):
			dist[t] = 0
			queue.append(t)
	var qi := 0
	while qi < queue.size():
		var t := queue[qi]
		qi += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var n: Vector2i = t + d
			if plot.has_point(n) and not dist.has(n):
				dist[n] = int(dist[t]) + 1
				queue.append(n)
	var centre := Vector2i(pr.get_center())
	var plaza_w := 3
	var lawn := {}
	for x in range(plot.position.x, plot.end.x):
		for y in range(plot.position.y, plot.end.y):
			var t := Vector2i(x, y)
			var d: int = dist.get(t, 99)
			if d <= plaza_w or used.has(t):
				continue
			# walks out to the streets on the halfway line and the pitch's long axis
			if absi(x - centre.x) <= 1 or absi(y - centre.y) <= 1:
				continue
			# a pavement along the plot's edge
			if x == plot.position.x or y == plot.position.y or x == plot.end.x - 1 or y == plot.end.y - 1:
				continue
			lawn[t] = true
	# lawns, merged into strips row by row, raised a touch so the edge reads as a kerb
	var grass := tex_mat("grass_ground", Color(0.36, 0.55, 0.22), 2.5, true)
	var kerb := mat(Color(0.72, 0.72, 0.7), 0.85)
	for y in range(plot.position.y, plot.end.y):
		var x := plot.position.x
		while x < plot.end.x:
			if not lawn.has(Vector2i(x, y)):
				x += 1
				continue
			var x0 := x
			while x < plot.end.x and lawn.has(Vector2i(x, y)):
				x += 1
			box(_land, Vector3(x0, 0.0, y), Vector3(x, 0.05, y + 1), grass, false)
	# kerbs and hedges where lawn meets paving
	var hedge_xf: Array[Transform3D] = []
	var kerb_xf: Array[Transform3D] = []
	for t in lawn:
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var d: Vector2i = dv
			var n: Vector2i = t + d
			if lawn.has(n):
				continue
			var edge_c := Vector3(t.x + 0.5 + d.x * 0.47, 0.0, t.y + 0.5 + d.y * 0.47)
			var along_x: bool = d.y != 0
			kerb_xf.append(Transform3D(Basis().scaled(Vector3(1.0 if along_x else 0.08, 0.08, 0.08 if along_x else 1.0)), edge_c + Vector3(0, 0.04, 0)))
			# clipped hedges face the plaza (not the walks), with gaps every few tiles
			if int(dist.get(n, 99)) <= plaza_w and (t.x + t.y) % 5 != 0:
				var hc := edge_c - Vector3(d.x, 0, d.y) * 0.3
				hedge_xf.append(Transform3D(Basis().scaled(Vector3(1.02 if along_x else 0.45, 0.55, 0.45 if along_x else 1.02)), hc + Vector3(0, 0.3, 0)))
	_mm(_land, kerb_xf, kerb, false)
	if not hedge_xf.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _hedge_mesh()
		mm.instance_count = hedge_xf.size()
		for i in hedge_xf.size():
			mm.set_instance_transform(i, hedge_xf[i])
			mm.set_instance_color(i, Color(0.85, 0.95, 0.85))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		_land.add_child(mi)
	# trees: an avenue one tile in from the edge, and copses on the bigger lawns
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + plot.size.x * 7 + plot.size.y
	var by_kind := {}
	for t in lawn:
		var d: int = dist.get(t, 99)
		var edge_d := mini(mini(t.x - plot.position.x, plot.end.x - 1 - t.x), mini(t.y - plot.position.y, plot.end.y - 1 - t.y))
		var kind := ""
		var h := 0.0
		if edge_d == 1 and (t.x + t.y) % 3 == 0:
			kind = "proc/lime"
			h = 5.2
		elif d >= plaza_w + 3 and edge_d >= 2 and rng.randf() < 0.07:
			kind = ["proc/oak", "proc/birch", "proc/oak", "proc/fir"][rng.randi_range(0, 3)]
			h = rng.randf_range(4.0, 6.5)
		elif d == plaza_w + 1 and (t.x * 3 + t.y) % 7 == 0:
			kind = "proc/poplar"
			h = 5.5
		if kind == "":
			continue
		var sc := h / maxf(0.01, Kenney.size(kind).y) * rng.randf_range(0.9, 1.1)
		if not by_kind.has(kind):
			by_kind[kind] = [[], []]
		by_kind[kind][0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(t.x + 0.5, 0.04, t.y + 0.5)))
		by_kind[kind][1].append(_leaf(rng))
	for kind in by_kind:
		var arr: Array[Transform3D] = []
		arr.assign(by_kind[kind][0])
		var cols: Array[Color] = []
		cols.assign(by_kind[kind][1])
		var mi := Kenney.batch(kind, arr, cols)
		mi.set_meta("tree", true)
		_land.add_child(mi)
	_land.visible = layer != "underground"


## A clipped hedge block: a box of lumpy foliage, one unit each way.
var _hedge: ArrayMesh
func _hedge_mesh() -> ArrayMesh:
	if _hedge == null:
		var bm := BoxMesh.new()
		bm.subdivide_width = 3
		bm.subdivide_height = 2
		bm.subdivide_depth = 3
		var arrays := bm.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cols := PackedColorArray()
		for v in verts:
			var shade := lerpf(0.55, 1.05, v.y + 0.5)
			cols.append(Color(0.24 * shade, 0.34 * shade, 0.15 * shade))
		arrays[Mesh.ARRAY_COLOR] = cols
		_hedge = ArrayMesh.new()
		_hedge.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_hedge.surface_set_material(0, ProcTrees.material())
	return _hedge
