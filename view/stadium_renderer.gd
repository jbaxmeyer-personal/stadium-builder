extends Node3D
## Builds the 3D stadium from sim state. Read-only on the sim.
## World units: 1 unit = 1 tile. Tile (x, y) covers [x, x+1] x [y, y+1] in X/Z.

const Kenney := preload("res://view/kenney.gd")
const ProcTrees := preload("res://view/proc_trees.gd")
const ProcBuildings := preload("res://view/proc_buildings.gd")
const Traffic := preload("res://view/traffic.gd")
const Signs := preload("res://view/signs.gd")
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
	elif emission <= 0.0:
		# weathering: blotchy grime and faint rain streaks, mapped in world
		# space, so plain painted surfaces don't look like fresh plastic
		m.detail_enabled = true
		m.detail_albedo = grime_texture()
		m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / 3.0
	_mats[key] = m
	return m


static var _grime: ImageTexture


## A tileable grey texture (0.8-1.0) of soft blotches and vertical streaks.
static func grime_texture() -> ImageTexture:
	if _grime:
		return _grime
	var sz := 256
	var n := FastNoiseLite.new()
	n.seed = 11
	n.frequency = 0.012
	n.fractal_octaves = 4
	var blot: Image = n.get_seamless_image(sz, sz)
	var cols := FastNoiseLite.new()
	cols.seed = 23
	cols.frequency = 0.08
	var stripe: Image = cols.get_seamless_image(sz, 4)
	var img := Image.create(sz, sz, false, Image.FORMAT_RGB8)
	for y in sz:
		for x in sz:
			var b := blot.get_pixel(x, y).r
			var c := stripe.get_pixel(x, 0).r
			# streaks run down the wall: strong in some columns, fading in and out
			var st := maxf(0.0, c - 0.55) * (0.6 + 0.4 * sin(TAU * y / sz * 2.0 + c * 9.0))
			var v := 0.86 + 0.14 * b - 0.18 * st
			img.set_pixel(x, y, Color(v, v, v * 0.985))
	img.generate_mipmaps()
	_grime = ImageTexture.create_from_image(img)
	return _grime


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


## Height of row v (0 = front). Per stand: the front height (plinth) and the
## rake (angle of the seating) are the player's choice.
static func _rise(s: Stand) -> float:
	return tan(deg_to_rad(s.rake))


static func row_height(v: int, s: Stand = null) -> float:
	if s == null:
		return ROW_BASE + v * ROW_RISE
	return s.plinth + v * tan(deg_to_rad(s.rake))


static func stand_height(s: Stand) -> float:
	return stand_top(s) + ROOF_CLEARANCE + 0.6


const TIER_GAP := 2.3        # headroom between a tier's rows and the tier above
const DECK_DROP := 1.6       # an upper concourse deck sits this far below its tier


## Height of the front row base of tier k (0 = ground tier).
static func tier_base(s: Stand, k: int) -> float:
	if k <= 0:
		return 0.0
	return tier_base(s, k - 1) + row_height(s.depth / 2, s) + TIER_GAP


static func tier_front(s: Stand, k: int) -> int:
	return s.tier_front(k)


## Top of the highest tier's back row.
static func stand_top(s: Stand) -> float:
	return tier_base(s, s.tiers - 1) + row_height(s.depth - 1, s)


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
	return AABB(Vector3(r.position.x, 0, r.position.y), Vector3(r.size.x, row_height(s.depth - 1, s), r.size.y))


# --- static scenery ------------------------------------------------------------

func build_static(layout: Layout) -> void:
	for g in [_ground, _pitch_node, _pitch_ghost, _lights, _trees]:
		for c in g.get_children():
			c.queue_free()
	_goals = null
	_side_node = null
	_led_boards.clear()
	var pl := Rect2(layout.plot)
	_setup_terrain(layout)
	_build_terrain(layout)
	_build_horizon(layout)
	# the plot itself is open grass (the terrain); paving comes with what you build
	var pr := layout.pitch
	if layout.pitch_placed:
		box(_pitch_ghost, Vector3(pr.position.x, 0, pr.position.y), Vector3(pr.end.x, 0.02, pr.end.y), mat(C_PITCH_B, 1.0, 0.0, 0.0, 0.25), false)
	_rect_outline(_pitch_ghost, pl, 0.02, mat(Color(0.9, 0.9, 0.9), 1.0, 0.0, 0.0, 0.5))
	if layout.pitch_placed:
		_line_col = Color.html(layout.line_color) if Color.html_is_valid(layout.line_color) else Color(0.95, 0.95, 0.95)
		_centre_crest = layout.centre_crest
		_build_pitch(layout.pitch)
	_build_streetlights(layout)
	if _club != null and layout.pitch_placed:
		apply_pitch_look(layout)
	_build_trees(layout)


var _line_col := Color(0.95, 0.95, 0.95)
var _centre_crest := false


func _build_pitch(p: Rect2i) -> void:
	var x0 := float(p.position.x)
	var z0 := float(p.position.y)
	var x1 := float(p.end.x)
	var z1 := float(p.end.y)
	# the surround round the pitch is drawn with the pitchside (see _build_pitchside)
	var pm := PlaneMesh.new()
	pm.size = Vector2(x1 - x0 - 0.9, z1 - z0 - 0.9)   # the outer margin shows the surround
	var pi := MeshInstance3D.new()
	pi.mesh = pm
	pi.position = Vector3((x0 + x1) / 2.0, 0.03, (z0 + z1) / 2.0)
	pi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _pitch_mat == null:
		_pitch_mat = ShaderMaterial.new()
		_pitch_mat.shader = load("res://view/pitch.gdshader")
		_pitch_mat.set_shader_parameter("grass_n", load(TEX_DIR + "grass_ground/nor.jpg"))
		_pitch_mat.set_shader_parameter("grass_d", load(TEX_DIR + "grass_ground/diff.jpg"))
		var nt := NoiseTexture2D.new()
		nt.seamless = true
		var fn := FastNoiseLite.new()
		fn.frequency = 0.03
		nt.noise = fn
		_pitch_mat.set_shader_parameter("noise", nt)
	_pitch_mat.set_shader_parameter("origin", Vector2(x0, z0))
	_pitch_mat.set_shader_parameter("season_wear", clampf(season_t * 1.2, 0.0, 1.0))
	_pitch_mat.set_shader_parameter("size", Vector2(x1 - x0, z1 - z0))
	pi.material_override = _pitch_mat
	_pitch_node.add_child(pi)
	_pitch_fuzz(Rect2(x0 + 0.45, z0 + 0.45, x1 - x0 - 0.9, z1 - z0 - 0.9))
	var line := mat(_line_col, 0.7)
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
	if _centre_crest and _club:
		# the crest painted flat on the grass inside the centre circle
		var lay := Node3D.new()
		lay.position = Vector3(cx, 0.036, cz)
		lay.rotation = Vector3(-PI / 2.0, PI / 2.0, 0)
		_pitch_node.add_child(lay)
		var cn := _crest(lay, Vector3.ZERO, 3.2, 0.0, false, "flat", "none")
		for mi in cn.find_children("*", "GeometryInstance3D", true, false):
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for end in [0, 1]:
		var gx := lx0 if end == 0 else lx1
		var dir := 1.0 if end == 0 else -1.0
		_rect_lines(min(gx, gx + dir * 4.7), cz - 5.8, max(gx, gx + dir * 4.7), cz + 5.8, y0, y1, t, line)
		_rect_lines(min(gx, gx + dir * 1.6), cz - 2.6, max(gx, gx + dir * 1.6), cz + 2.6, y0, y1, t, line)


## Grass types: two greens (lighter / darker mowing) each.
const GRASS := {
	"classic": [Color(0.2, 0.31, 0.12), Color(0.26, 0.39, 0.15)],
	"lush": [Color(0.16, 0.32, 0.1), Color(0.22, 0.41, 0.14)],
	"emerald": [Color(0.1, 0.29, 0.13), Color(0.14, 0.37, 0.17)],
	"summer": [Color(0.3, 0.34, 0.15), Color(0.38, 0.41, 0.19)],
	"hybrid": [Color(0.12, 0.23, 0.08), Color(0.17, 0.3, 0.11)],
}

var _goals: Node3D
var _side_node: Node3D
static var _net_mat: ShaderMaterial


## Close up, the pitch has real depth: a carpet of very short tufts that
## fades out as you zoom away (from a distance the shader does the work).
func _pitch_fuzz(r: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	var per := 4   # tufts per side of each tile
	var x := r.position.x
	while x < r.end.x:
		var z := r.position.y
		while z < r.end.y:
			for i in per * per:
				var px := x + (i % per + rng.randf()) / per
				var pz := z + (i / per + rng.randf()) / per
				if px >= r.end.x or pz >= r.end.y:
					continue
				var sc := rng.randf_range(0.025, 0.04)
				xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc * 3.0, sc, sc * 3.0)), Vector3(px, 0.028, pz)))
				cols.append(Color(0.55, 0.62, 0.5).lerp(Color(0.62, 0.66, 0.48), rng.randf()))
			z += 1.0
		x += 1.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = ProcTrees.tuft_mesh()
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 28.0
	mi.visibility_range_end_margin = 8.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_pitch_node.add_child(mi)


## Pitch looks that change cheaply: grass type, mowing pattern, goals and nets.
func apply_pitch_look(layout: Layout) -> void:
	if _pitch_mat:
		var g: Array = GRASS.get(layout.pitch_grass, GRASS["classic"])
		_pitch_mat.set_shader_parameter("green_a", g[0])
		_pitch_mat.set_shader_parameter("green_b", g[1])
		_pitch_mat.set_shader_parameter("pattern", maxi(0, Layout.PITCH_PATTERNS.find(layout.pitch_pattern)))
	_build_goals(layout)
	_build_pitchside(layout)


func _build_goals(layout: Layout) -> void:
	if _goals == null or not is_instance_valid(_goals) or _goals.is_queued_for_deletion():
		_goals = Node3D.new()
		_pitch_node.add_child(_goals)
	for c in _goals.get_children():
		c.free()
	if _net_mat == null:
		_net_mat = ShaderMaterial.new()
		_net_mat.shader = load("res://view/net.gdshader")
	_net_mat.set_shader_parameter("net_color", Color.html(layout.net_color))
	_net_mat.set_shader_parameter("pattern", maxi(0, Layout.NET_PATTERNS.find(layout.net_pattern) - 1))
	_nets_on = layout.net_pattern != "none"
	var p := layout.pitch
	var cz := p.get_center().y
	var post := mat(Color.html(layout.goal_color) if Color.html_is_valid(layout.goal_color) else Color(0.97, 0.97, 0.97), 0.35)
	_corner_flags(layout)
	var frame := mat(Color(0.75, 0.76, 0.78), 0.4, 0.6)
	var gh := 0.7
	var hw := 1.05
	for end in [0, 1]:
		var gx: float = float(p.position.x) + 0.6 if end == 0 else float(p.end.x) - 0.6
		var dir := -1.0 if end == 0 else 1.0     # outward, behind the goal line
		var g := Node3D.new()
		g.position = Vector3(gx, 0, cz)
		g.rotation.y = 0.0 if dir > 0 else PI
		_goals.add_child(g)
		# posts and crossbar (local +x points behind the goal)
		for zz in [-hw, hw]:
			lbox(g, Vector3(0, gh / 2.0, zz), Vector3(0.07, gh, 0.07), post)
		lbox(g, Vector3(0, gh, 0), Vector3(0.07, 0.07, hw * 2.0 + 0.07), post)
		match layout.goal_style:
			"box":
				# deep box net with rear posts and a flat top
				var d := 0.95
				for zz in [-hw, hw]:
					lbox(g, Vector3(d, gh / 2.0, zz), Vector3(0.04, gh, 0.04), frame)
					lbox(g, Vector3(d / 2.0, gh, zz), Vector3(d, 0.04, 0.04), frame)
				lbox(g, Vector3(d, gh, 0), Vector3(0.04, 0.04, hw * 2.0), frame)
				_net(g, [Vector3(d, 0, -hw), Vector3(d, 0, hw), Vector3(d, gh, hw), Vector3(d, gh, -hw)])
				_net(g, [Vector3(0, gh, -hw), Vector3(d, gh, -hw), Vector3(d, gh, hw), Vector3(0, gh, hw)])
				for zz in [-hw, hw]:
					_net(g, [Vector3(0, 0, zz), Vector3(d, 0, zz), Vector3(d, gh, zz), Vector3(0, gh, zz)])
			"stanchion":
				# continental: the net falls from the crossbar to the ground far
				# behind, held out by curved stanchions at the sides
				var d := 1.3
				var bars: Array[Transform3D] = []
				for zz in [-hw, hw]:
					var prev := Vector3(0.05, gh, zz)
					for i in range(1, 7):
						var a := PI / 2.0 * i / 6.0
						var q := Vector3(sin(a) * d * 0.55 + 0.05, gh * cos(a) * 0.9 + 0.05, zz)
						bars.append(_rod(prev, q, 0.035))
						prev = q
					bars.append(_rod(prev, Vector3(d, 0.02, zz), 0.035))
				_mm(g, bars, frame)
				_net(g, [Vector3(0, gh, -hw), Vector3(0, gh, hw), Vector3(d, 0, hw), Vector3(d, 0, -hw)])
				for zz in [-hw, hw]:
					_net(g, [Vector3(0, 0, zz), Vector3(d, 0, zz), Vector3(0, gh, zz), Vector3(0, gh, zz)])
			_:
				# classic: shallow net on a back frame
				var d := 0.6
				for zz in [-hw, hw]:
					lbox(g, Vector3(d / 2.0, 0.02, zz), Vector3(d, 0.03, 0.03), frame)
					lbox(g, Vector3(d / 2.0, gh * 0.75, zz), Vector3(d, 0.03, 0.03), frame)
					lbox(g, Vector3(d, gh * 0.375, zz), Vector3(0.03, gh * 0.75, 0.03), frame)
				_net(g, [Vector3(d, 0, -hw), Vector3(d, 0, hw), Vector3(d, gh * 0.75, hw), Vector3(d, gh * 0.75, -hw)])
				_net(g, [Vector3(0, gh, -hw), Vector3(d, gh * 0.75, -hw), Vector3(d, gh * 0.75, hw), Vector3(0, gh, hw)])
				for zz in [-hw, hw]:
					_net(g, [Vector3(0, 0, zz), Vector3(d, 0, zz), Vector3(d, gh * 0.75, zz), Vector3(0, gh, zz)])


var _nets_on := true


## The four corner flags: a pole and a flag in the chosen colours and pattern.
func _corner_flags(layout: Layout) -> void:
	var cf := layout.corner_flags
	if not bool(cf.get("on", false)):
		return
	var p := layout.pitch
	var pole_c := Color.html(cf["pole"]) if String(cf.get("pole", "")) != "" else Color(0.95, 0.85, 0.2)
	var c1 := Color.html(cf["flag"]) if String(cf.get("flag", "")) != "" else _club.primary_color
	var c2 := Color.html(cf["flag2"]) if String(cf.get("flag2", "")) != "" else _club.secondary_color
	var pat: String = cf.get("pattern", "plain")
	var pole_m := mat(pole_c, 0.45)
	var fm := StandardMaterial3D.new()
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.roughness = 0.8
	if pat == "badge":
		fm.albedo_texture = badge_texture()
		fm.albedo_color = Color.WHITE
	else:
		var img := Image.create(16, 12, false, Image.FORMAT_RGB8)
		for y in 12:
			for x in 16:
				var two := false
				match pat:
					"halves": two = x >= 8
					"quarters": two = (x >= 8) != (y >= 6)
					"stripes": two = (y / 3) % 2 == 1
					"diagonal": two = x * 12 > y * 16
				img.set_pixel(x, y, c2 if two else c1)
		fm.albedo_texture = ImageTexture.create_from_image(img)
		fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	for cx in [float(p.position.x) + 0.6, float(p.end.x) - 0.6]:
		for czz in [float(p.position.y) + 0.6, float(p.end.y) - 0.6]:
			var pole := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.014
			cyl.bottom_radius = 0.016
			cyl.height = 0.5
			cyl.radial_segments = 8
			pole.mesh = cyl
			pole.material_override = pole_m
			pole.position = Vector3(cx, 0.25, czz)
			_goals.add_child(pole)
			# the flag hangs from the top with a slight wave
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var segs := 6
			var w := 0.17
			var fh := 0.12
			for i in segs:
				var u0 := float(i) / segs
				var u1 := float(i + 1) / segs
				var a := Vector3(u0 * w, 0, sin(u0 * 5.0) * 0.015 * u0)
				var b := Vector3(u1 * w, 0, sin(u1 * 5.0) * 0.015 * u1)
				for v in [[a, u0, 0.0], [b, u1, 0.0], [b, u1, 1.0], [a, u0, 0.0], [b, u1, 1.0], [a, u0, 1.0]]:
					var q: Vector3 = v[0]
					st.set_uv(Vector2(v[1], v[2]))
					st.set_normal(Vector3(0, 0, 1))
					st.add_vertex(q + Vector3(0, -float(v[2]) * fh, 0))
			var fl := MeshInstance3D.new()
			fl.mesh = st.commit()
			fl.material_override = fm
			fl.position = Vector3(cx, 0.49, czz)
			fl.rotation.y = 0.5 + (0.6 if czz > p.get_center().y else -0.3)
			_goals.add_child(fl)


## One panel of netting through four corners.
func _net(parent: Node3D, q: Array) -> void:
	if not _nets_on:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(q[k])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _net_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## The small things round a pro pitch: angled advertising mats behind the
## goals, photographers crouched by the posts, ball boys' stools, the fourth
## official's table and TV camera platforms at the corners.
func _pitchside_details(layout: Layout, x0: float, x1: float, z0: float, z1: float) -> void:
	if layout.ad_boards == "none":
		return   # a park pitch: none of the trappings
	var cz := (z0 + z1) / 2.0
	var cx := (x0 + x1) / 2.0
	var dark := mat(Color(0.12, 0.12, 0.14), 0.6)
	var steel := mat(Color(0.55, 0.57, 0.6), 0.4, 0.7)
	var bib := mat(Color(0.95, 0.75, 0.1), 0.7)
	for end in [-1.0, 1.0]:
		var gx: float = x0 - 0.5 if end < 0.0 else x1 + 0.5
		# angled carpets either side of the goal, sponsors printed on them
		for side in [-1.0, 1.0]:
			var mat_g := Node3D.new()
			mat_g.position = Vector3(gx, 0.0, cz + side * 2.6)
			mat_g.rotation.y = PI / 2.0 if end < 0.0 else -PI / 2.0
			_side_node.add_child(mat_g)
			var carpet := lbox(mat_g, Vector3(0, 0.08, 0), Vector3(2.4, 0.02, 0.5), mat(_club.primary_color.darkened(0.2), 0.8), 0.0)
			carpet.rotation.x = -0.55
			var lab := Label3D.new()
			lab.text = String(_ad_brands[int(absf(side + end * 2.0)) % _ad_brands.size()])
			lab.font_size = 40
			lab.pixel_size = 0.004
			lab.outline_size = 0
			lab.position = Vector3(0, 0.1, 0.02)
			lab.rotation = Vector3(-0.55, 0, 0)
			mat_g.add_child(lab)
			# a photographer crouched on a stool, long lens pointing up the pitch
			var ph := Vector3(gx - end * 0.15, 0, cz + side * 4.2)
			lbox(_side_node, ph + Vector3(0, 0.1, 0), Vector3(0.16, 0.2, 0.16), dark)
			lbox(_side_node, ph + Vector3(0, 0.32, 0), Vector3(0.2, 0.26, 0.16), bib)
			lbox(_side_node, ph + Vector3(0, 0.5, 0), Vector3(0.11, 0.11, 0.11), mat(Color(0.8, 0.65, 0.5), 0.8))
			var lens := lbox(_side_node, ph + Vector3(-end * 0.14, 0.44, 0), Vector3(0.22, 0.07, 0.07), dark)
			lens.rotation.y = 0.0
		# a TV camera platform at each corner
		for side in [-1.0, 1.0]:
			var tv := Vector3(gx - end * 0.2, 0, (z0 - 0.7) if side < 0.0 else (z1 + 0.7))
			lbox(_side_node, tv + Vector3(0, 0.3, 0), Vector3(0.7, 0.06, 0.7), steel)
			for e in [Vector3(-0.3, 0, -0.3), Vector3(0.3, 0, -0.3), Vector3(-0.3, 0, 0.3), Vector3(0.3, 0, 0.3)]:
				lbox(_side_node, tv + e + Vector3(0, 0.15, 0), Vector3(0.04, 0.3, 0.04), steel)
			lbox(_side_node, tv + Vector3(0, 0.55, 0), Vector3(0.2, 0.18, 0.32), dark)
	# ball boys' stools along the touchlines, the fourth official's table at halfway
	for zz in [z0 - 0.45, z1 + 0.45]:
		for u in [0.2, 0.4, 0.6, 0.8]:
			var bx: float = x0 + (x1 - x0) * u
			lbox(_side_node, Vector3(bx, 0.1, zz), Vector3(0.14, 0.2, 0.14), mat(Color(0.2, 0.4, 0.8), 0.6))
	var fz := (z1 + 0.6) if layout.dugout_side == "S" else (z0 - 0.6)
	lbox(_side_node, Vector3(cx, 0.22, fz), Vector3(0.9, 0.05, 0.4), mat(Color(0.9, 0.9, 0.88), 0.6))
	for e in [-0.38, 0.38]:
		lbox(_side_node, Vector3(cx + e, 0.11, fz), Vector3(0.04, 0.22, 0.34), steel)
	lbox(_side_node, Vector3(cx + 0.2, 0.3, fz), Vector3(0.18, 0.12, 0.04), mat(Color(0.1, 0.9, 0.2), 0.3, 0.0, 1.2))
	# the medical cart parked by the corner flag on the dugout side
	var mc := Vector3(x0 + 1.2, 0, fz + (0.5 if layout.dugout_side == "S" else -0.5))
	lbox(_side_node, mc + Vector3(0, 0.22, 0), Vector3(0.9, 0.22, 0.45), mat(Color(0.95, 0.95, 0.95), 0.5))
	lbox(_side_node, mc + Vector3(0.18, 0.45, 0), Vector3(0.4, 0.04, 0.45), mat(Color(0.95, 0.95, 0.95), 0.5))
	lbox(_side_node, mc + Vector3(-0.2, 0.34, 0.23), Vector3(0.18, 0.06, 0.01), mat(Color(0.85, 0.1, 0.1), 0.5))
	lbox(_side_node, mc + Vector3(-0.2, 0.34, 0.23), Vector3(0.06, 0.18, 0.01), mat(Color(0.85, 0.1, 0.1), 0.5))
	for wx in [-0.32, 0.32]:
		for wz in [-0.24, 0.24]:
			lbox(_side_node, mc + Vector3(wx, 0.07, wz), Vector3(0.14, 0.14, 0.05), dark)


var _led_boards: Array = []   # [material, label, index] of each LED board
var _tier_leds: Array = []    # the same for LED ribbons on upper tier fronts
var _ad_brands: Array = AD_BRANDS
var _led_clock := 0.0
var _led_step := -1


## LED boards scroll through adverts and club messages (all boards in step,
## like a real ground), faster and brighter on a matchday.
var _birds: MultiMeshInstance3D
var _bird_clock := 0.0


## A few gulls wheeling high over the ground (day only).
func _update_birds(delta: float) -> void:
	if _birds == null:
		_birds = MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var pm := PrismMesh.new()
		pm.size = Vector3(0.7, 0.08, 0.25)
		mm.mesh = pm
		mm.instance_count = 9
		_birds.multimesh = mm
		_birds.material_override = mat(Color(0.92, 0.92, 0.9), 0.8)
		_birds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_birds)
	_birds.visible = not _night
	if _night:
		return
	_bird_clock += delta
	var mm2 := _birds.multimesh
	for i in mm2.instance_count:
		var a := _bird_clock * (0.18 + 0.02 * i) + i * 0.7
		var r := 14.0 + 5.0 * sin(i * 1.3)
		var p := Vector3(_pitch_centre.x + cos(a) * r, 22.0 + 3.0 * sin(i + _bird_clock * 0.3), _pitch_centre.y + sin(a) * r)
		var flap := sin(_bird_clock * 6.0 + i) * 0.35
		var b := Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, flap)
		mm2.set_instance_transform(i, Transform3D(b, p))


func _process(delta: float) -> void:
	_update_birds(delta)
	if _led_boards.is_empty() and _tier_leds.is_empty():
		return
	_led_clock += delta * (1.0 if matchday_live else 0.35)
	var step := int(_led_clock / 4.0)
	if step == _led_step:
		return
	_led_step = step
	var club_msgs := ["MATCHDAY", "COME ON YOU " + _club.club_name.split(" ")[0].to_upper(), _club.club_name.to_upper(), "WELCOME TO " + (ground_name if ground_name != "" else _club.stadium_name).to_upper()]
	for b in _led_boards + _tier_leds:
		var ref: WeakRef = b[1]
		var obj: Object = ref.get_ref()
		if obj == null:
			continue   # rebuilt since; the next build registers the new one
		var m: StandardMaterial3D = b[0]
		var lab := obj as Label3D
		var k: int = b[2]
		var phase := (step + k / 6) % 6
		var col: Color
		if phase % 3 == 2:
			col = _club.primary_color
			lab.text = club_msgs[(step / 3 + k) % club_msgs.size()]
			lab.modulate = _club.secondary_color
		else:
			col = Color.from_hsv(fmod(step * 0.17 + 0.05 * (k % 3), 1.0), 0.6, 0.75)
			lab.text = _ad_brands[(step + k) % _ad_brands.size()]
			lab.modulate = Color(1, 1, 1)
		m.albedo_color = col
		m.emission = col
		m.emission_energy_multiplier = 1.4 if matchday_live else 0.8


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
	var grey: Array[Color] = []
	for i in arr.size():
		grey.append(Color(0.5, 0.52, 0.55))
	_ground.add_child(Kenney.batch("city-kit-roads/light-curved", arr, grey))


## LED advertising boards round the pitch and the two dugouts.
func _build_pitchside(layout: Layout) -> void:
	var p := layout.pitch
	if _side_node == null or not is_instance_valid(_side_node) or _side_node.is_queued_for_deletion():
		_side_node = Node3D.new()
		_pitch_node.add_child(_side_node)
	for c in _side_node.get_children():
		c.free()
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
	if layout.ad_boards == "none":
		segs.clear()
	# byelines, either side of the goal
	for gx in ([] if layout.ad_boards == "none" else [x0, x1]):
		for zz in [z0 + 2.3, z1 - 2.3]:
			segs.append([Vector3(gx, 0, zz), 4.0, PI / 2.0 if gx == x0 else -PI / 2.0])
	for sgm in segs:
		var g := Node3D.new()
		g.position = sgm[0]
		g.rotation.y = sgm[2]
		_side_node.add_child(g)
		var L: float = sgm[1]
		lbox(g, Vector3(0, 0.16, 0), Vector3(L, 0.32, 0.06), mat(Color(0.05, 0.05, 0.06), 0.4))
		var col := Color.from_hsv(float(k % 7) / 7.0, 0.55, 0.7)
		var txt_col := Color(1, 1, 1)
		var brands: Array = layout.ad_texts if not layout.ad_texts.is_empty() else AD_BRANDS
		_ad_brands = brands
		var brand: String = brands[k % brands.size()]
		match layout.ad_boards:
			"club":
				col = _club.primary_color if k % 2 == 0 else _club.secondary_color
				txt_col = _club.secondary_color if k % 2 == 0 else _club.primary_color
				brand = _club.club_name.to_upper() if k % 3 == 0 else ("COME ON YOU " + _club.club_name.split(" ")[0].to_upper() if k % 3 == 1 else "WELCOME TO " + (ground_name if ground_name != "" else _club.stadium_name).to_upper())
			"sponsor":
				col = Color(0.08, 0.3, 0.75)
				brand = brands[0]
			"dark":
				col = Color(0.06, 0.06, 0.07)
				txt_col = Color.from_hsv(float(k % 7) / 7.0, 0.6, 1.0)
		var face_m: Material = mat(col, 0.3, 0.0, 0.55 if layout.ad_boards != "dark" else 0.2)
		if layout.ad_boards == "led":
			# its own material: LED boards change colour and message on matchdays
			var lm := StandardMaterial3D.new()
			lm.albedo_color = col
			lm.emission_enabled = true
			lm.emission = col
			lm.emission_energy_multiplier = 0.8
			lm.roughness = 0.25
			face_m = lm
		var face := lbox(g, Vector3(0, 0.17, 0.035), Vector3(L - 0.08, 0.26, 0.01), face_m)
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var lab := Label3D.new()
		lab.text = brand
		lab.font_size = 48
		lab.pixel_size = 0.0042
		lab.outline_size = 0
		lab.modulate = txt_col
		lab.position = Vector3(0, 0.17, 0.045)
		g.add_child(lab)
		if layout.ad_boards == "led":
			_led_boards.append([face_m, weakref(lab), k])
		k += 1
	_pitchside_details(layout, x0, x1, z0, z1)
	# dugouts either side of halfway on the far touchline
	var dug_north := layout.dugout_side == "N"
	for side in ([] if layout.dugout == "none" else [-1, 1]):
		var g := Node3D.new()
		var gap := float(layout.dugout_gap)
		g.position = Vector3((x0 + x1) / 2.0 + side * gap, 0, (z0 + 0.05) if dug_north else (z1 - 0.05))
		g.rotation.y = 0.0 if dug_north else PI
		_side_node.add_child(g)
		var dug_c := Color.html(layout.dugout_color) if layout.dugout_color != "" and Color.html_is_valid(layout.dugout_color) else _club.primary_color
		var seat_m := mat(dug_c, 0.6)
		# the technical area: a dashed white box on the grass in front
		var tam := mat(Color(0.95, 0.95, 0.95), 0.7)
		for dk in 6:
			lbox(g, Vector3(-1.5 + dk * 0.6, 0.03, 0.9), Vector3(0.35, 0.01, 0.05), tam)
		for e in [-1.6, 1.6]:
			for dk in 2:
				lbox(g, Vector3(e, 0.03, 0.2 + dk * 0.45), Vector3(0.05, 0.01, 0.3), tam)
		lbox(g, Vector3(0, 0.02, -0.25), Vector3(2.4, 0.04, 0.55), mat(Color(0.2, 0.2, 0.22), 0.6))
		for i in 6:
			lbox(g, Vector3(-1.0 + i * 0.4, 0.12, -0.38), Vector3(0.3, 0.06, 0.2), seat_m)
			lbox(g, Vector3(-1.0 + i * 0.4, 0.24, -0.47), Vector3(0.3, 0.2, 0.04), seat_m)
		match layout.dugout:
			"brick":
				# old-school sunken brick dugout with a flat roof
				var brick := tex_mat("red_brick_03", Color.WHITE, 1.0)
				lbox(g, Vector3(0, 0.3, -0.55), Vector3(2.5, 0.6, 0.1), brick)
				for e in [-1, 1]:
					lbox(g, Vector3(e * 1.22, 0.3, -0.27), Vector3(0.08, 0.6, 0.6), brick)
				lbox(g, Vector3(0, 0.62, -0.25), Vector3(2.6, 0.06, 0.66), mat(Color(0.2, 0.2, 0.22), 0.7))
			"stadium":
				# modern technical area: a long curved shell, padded seats, club colour
				lbox(g, Vector3(0, 0.3, -0.55), Vector3(2.8, 0.6, 0.05), mat(dug_c.darkened(0.4), 0.4))
				for i in 6:
					var a := PI * i / 5.0
					var seg2 := lbox(g, Vector3(0, 0.35 + sin(a) * 0.25, -0.25 - cos(a) * 0.28), Vector3(2.8, 0.03, 0.15), mat(Color(0.8, 0.88, 0.95), 0.05, 0.2, 0.0, 0.45))
					seg2.rotation.x = -a + PI / 2.0
				lbox(g, Vector3(0, 0.62, -0.5), Vector3(2.8, 0.05, 0.12), mat(dug_c, 0.5))
			_:
				lbox(g, Vector3(0, 0.26, -0.5), Vector3(2.3, 0.2, 0.06), mat(Color(0.1, 0.1, 0.12), 0.5))
				lbox(g, Vector3(0, 0.55, -0.25), Vector3(2.5, 0.03, 0.6), mat(Color(0.75, 0.85, 0.95), 0.05, 0.2, 0.0, 0.45), 0.12)
				for e in [-1, 1]:
					lbox(g, Vector3(e * 1.22, 0.28, -0.25), Vector3(0.03, 0.56, 0.6), mat(Color(0.75, 0.85, 0.95), 0.05, 0.2, 0.0, 0.45))
	# the surround: the strip between the pitch and the stands
	var sm: Material
	match layout.surround:
		"artificial": sm = tex_mat("grass_ground", Color(0.16, 0.42, 0.2), 1.0, true)
		"track": sm = tex_mat("rough_concrete", Color(0.72, 0.26, 0.2), 2.0, true)
		"gravel": sm = tex_mat("rough_concrete", Color(0.62, 0.58, 0.52), 1.0)
		"hardstanding": sm = tex_mat("rough_concrete", Color(0.7, 0.7, 0.68), 1.5)
		"tight": sm = tex_mat("grass_ground", Color(0.25, 0.42, 0.18), 2.0, true)
		_: sm = tex_mat("grass_ground", Color(0.3, 0.45, 0.2), 2.0, true)
	if layout.surround_color != "" and Color.html_is_valid(layout.surround_color):
		var sc := Color.html(layout.surround_color)
		match layout.surround:
			"artificial", "grass", "tight": sm = tex_mat("grass_ground", sc, 2.0, true)
			_: sm = tex_mat("rough_concrete", sc * 1.3, 1.5, true)
	var r := Rect2(p)
	box(_side_node, Vector3(r.position.x, -0.004, r.position.y), Vector3(r.end.x, 0.026, r.end.y), sm, false)
	_build_barrier(layout)
	if layout.post_scoreboard:
		# a lower-league scoreboard on two posts behind one goal
		var sx := x1 + 1.6
		var sb := Node3D.new()
		sb.position = Vector3(sx, 0, cz + 3.5)
		sb.rotation.y = -PI / 2.0
		_side_node.add_child(sb)
		for e in [-0.9, 0.9]:
			lbox(sb, Vector3(e, 1.0, 0), Vector3(0.1, 2.0, 0.1), mat(Color(0.25, 0.26, 0.27), 0.5, 0.6))
		lbox(sb, Vector3(0, 2.3, 0), Vector3(2.4, 0.9, 0.12), mat(Color(0.08, 0.08, 0.09), 0.6))
		lbox(sb, Vector3(0, 2.8, 0), Vector3(2.5, 0.12, 0.18), mat(_club.primary_color, 0.5))
		_lettering(sb, "HOME 0  AWAY 0", Vector3(0, 2.3, 0.07), Color(1.0, 0.85, 0.3), 0.004, 48, 0.0, "inside", "pixel")
	if layout.surround == "track":
		# lane lines round the track, in the margin outside the touchlines
		var lm := mat(Color(0.95, 0.95, 0.95), 0.6)
		for lane in 3:
			_rect_outline(_side_node, Rect2(p).grow(-0.06 - lane * 0.13), 0.027, lm, 0.02)

## What separates the crowd from the pitch: a lower-league rail, a low
## painted wall, a tall South American / Turkish fence, or a dry moat.
func _build_barrier(layout: Layout) -> void:
	if layout.barrier == "none":
		return
	var r := Rect2(layout.pitch).grow(-0.06)
	var edges := [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.position.x, r.end.y), r.end], [r.position, Vector2(r.position.x, r.end.y)], [Vector2(r.end.x, r.position.y), r.end]]
	var posts: Array[Transform3D] = []
	var bars: Array[Transform3D] = []
	var panels: Array[Transform3D] = []
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var horiz := absf(b.x - a.x) > absf(b.y - a.y)
		var len := a.distance_to(b)
		var mid := (a + b) / 2.0
		var sz := func(along: float, h: float, th: float) -> Vector3: return Vector3(along if horiz else th, h, th if horiz else along)
		match layout.barrier:
			"rail":
				var n := int(len / 1.2)
				for i in n + 1:
					var q := a.lerp(b, float(i) / maxf(1.0, n))
					posts.append(Transform3D(Basis().scaled(Vector3(0.05, 0.42, 0.05)), Vector3(q.x, 0.21, q.y)))
				bars.append(Transform3D(Basis().scaled(sz.call(len, 0.05, 0.05)), Vector3(mid.x, 0.42, mid.y)))
			"wall":
				panels.append(Transform3D(Basis().scaled(sz.call(len, 0.45, 0.12)), Vector3(mid.x, 0.225, mid.y)))
				bars.append(Transform3D(Basis().scaled(sz.call(len, 0.05, 0.16)), Vector3(mid.x, 0.47, mid.y)))
			"fence", "moat":
				var fh := 2.6 if layout.barrier == "fence" else 1.8
				var n := int(len / 1.6)
				for i in n + 1:
					var q := a.lerp(b, float(i) / maxf(1.0, n))
					posts.append(Transform3D(Basis().scaled(Vector3(0.06, fh, 0.06)), Vector3(q.x, fh / 2.0, q.y)))
				for hy in [0.3, fh * 0.55, fh]:
					bars.append(Transform3D(Basis().scaled(sz.call(len, 0.04, 0.04)), Vector3(mid.x, hy, mid.y)))
				panels.append(Transform3D(Basis().scaled(sz.call(len, fh - 0.3, 0.02)), Vector3(mid.x, 0.3 + (fh - 0.3) / 2.0, mid.y)))
				if layout.barrier == "fence":
					# angled overhang at the top
					var out := Vector2(0, -1 if a.y == r.position.y and horiz else 1) if horiz else Vector2(-1 if a.x == r.position.x else 1, 0)
					bars.append(Transform3D(Basis().scaled(sz.call(len, 0.04, 0.04)), Vector3(mid.x + out.x * 0.35, fh + 0.3, mid.y + out.y * 0.35)))
	var bcol := Color(0.82, 0.82, 0.8) if layout.barrier == "rail" else Color(0.3, 0.32, 0.33)
	var own := layout.barrier_color != "" and Color.html_is_valid(layout.barrier_color)
	if own:
		bcol = Color.html(layout.barrier_color)
	var steel := mat(bcol, 0.45, 0.6)
	_mm(_side_node, posts, steel)
	_mm(_side_node, bars, mat(bcol if own else _club.primary_color, 0.5, 0.3) if layout.barrier == "wall" else steel)
	match layout.barrier:
		"wall": _mm(_side_node, panels, mat(_club.secondary_color.darkened(0.1), 0.8))
		"fence", "moat":
			var mesh_m := ShaderMaterial.new()
			mesh_m.shader = load("res://view/net.gdshader")
			mesh_m.set_shader_parameter("net_color", Color(0.25, 0.27, 0.28))
			mesh_m.set_shader_parameter("pattern", 0)
			_mm(_side_node, panels, mesh_m, false)
	if layout.barrier == "moat":
		# a dry ditch just inside the fence line
		var dm := tex_mat("rough_concrete", Color(0.45, 0.45, 0.44), 1.0)
		for e in edges:
			var a: Vector2 = e[0]
			var b: Vector2 = e[1]
			var horiz := absf(b.x - a.x) > absf(b.y - a.y)
			var inward := Vector2(0, 1 if a.y == r.position.y else -1) if horiz else Vector2(1 if a.x == r.position.x else -1, 0)
			var c := (a + b) / 2.0 + inward * 0.35
			box(_side_node, Vector3(c.x - (a.distance_to(b) / 2.0 if horiz else 0.3), 0.0, c.y - (0.3 if horiz else a.distance_to(b) / 2.0)),
				Vector3(c.x + (a.distance_to(b) / 2.0 if horiz else 0.3), 0.035, c.y + (0.3 if horiz else a.distance_to(b) / 2.0)), dm, false)


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
	if not layout.pitch_placed or layout.stands.is_empty():
		return   # lights go up with the first stand
	var p := layout.pitch
	var centre := Vector3(p.get_center().x, 0, p.get_center().y)
	var fcol := String(layout.flood.get("color", ""))
	var painted := fcol != "" and Color.html_is_valid(fcol)
	var steel := mat(Color.html(fcol) if painted else Color(0.35, 0.36, 0.38), 0.5, 0.7)
	var hmul := clampf(float(layout.flood.get("height", 1.0)), 0.6, 1.6)
	var nside := int(layout.flood.get("per_side", 0))
	_lamp_style = String(layout.flood.get("lamp", "round"))
	var style := layout.floodlights
	match style:
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
				var nm := nside if nside > 0 else 3
				for k in nm:
					var u := 0.15 + 0.7 * k / maxf(1.0, nm - 1) if nm > 1 else 0.5
					var x: float = p.position.x + p.size.x * u
					var height := (11.0 + reach * 0.6) * hmul
					box(_lights, Vector3(x - 0.12, 0, z - 0.12), Vector3(x + 0.12, height, z + 0.12), steel)
					_lamp_head(Vector3(x, height + 0.5, z), centre, Vector3(1.8, 1.1, 0.2), true)
		"slim", "slim6":
			# a non-league ground: thin steel poles along both touchlines, a small
			# cluster of lamps on top, as tall as the ground needs
			var per_side := nside if nside > 0 else (2 if style == "slim" else 3)
			for side in ["N", "S"]:
				var reach := 2.2
				var tallest := 0.0
				for s in layout.stands:
					if s.side == side:
						reach = maxf(reach, s.footprint_depth() + s.setback + 1.2)
						tallest = maxf(tallest, stand_top(s))
				var z := p.position.y - reach if side == "N" else p.end.y + reach
				for k in per_side:
					var u := 0.22 + 0.56 * k / maxf(1.0, per_side - 1) if per_side > 1 else 0.5
					var x: float = p.position.x + p.size.x * u
					var height := maxf(9.0, tallest + 5.0) * hmul
					var pole := MeshInstance3D.new()
					var cyl := CylinderMesh.new()
					cyl.top_radius = 0.09
					cyl.bottom_radius = 0.16
					cyl.height = height
					cyl.radial_segments = 10
					pole.mesh = cyl
					pole.material_override = steel if painted else mat(Color(0.55, 0.57, 0.58), 0.45, 0.7)
					pole.position = Vector3(x, height / 2.0, z)
					_lights.add_child(pole)
					# a small concrete footing and a cross-arm with the lamps
					box(_lights, Vector3(x - 0.3, 0, z - 0.3), Vector3(x + 0.3, 0.25, z + 0.3), tex_mat("rough_concrete", Color(0.7, 0.7, 0.68), 1.0))
					_lamp_head(Vector3(x, height + 0.35, z), centre, Vector3(1.3, 0.85, 0.16), true)
		_:
			for corner in Stand.CORNERS:
				var reach := 3.5
				for s in layout.stands:
					if corner.contains(s.side) or s.side == corner:
						reach = maxf(reach, s.footprint_depth() + s.setback + 3.0)
				var cf := corner_frame(corner, p)
				var c: Vector2 = cf["centre"] + Vector2(cf["sx"], cf["sz"]) * reach * 0.75
				var height := (17.0 + reach * 0.7) * hmul
				if style == "candles":
					# Italian "candles": a tall tapering concrete shaft, the light bank tilted on top
					height += 2.0
					var shaft := MeshInstance3D.new()
					var cyl := CylinderMesh.new()
					cyl.top_radius = 0.16
					cyl.bottom_radius = 0.42
					cyl.height = height
					cyl.radial_segments = 16
					shaft.mesh = cyl
					shaft.material_override = tex_mat("rough_concrete", Color(0.78, 0.78, 0.76), 2.0)
					shaft.position = Vector3(c.x, height / 2.0, c.y)
					_lights.add_child(shaft)
					_lamp_head(Vector3(c.x, height + 1.6, c.y), centre, Vector3(2.4, 3.2, 0.3), true)
				else:
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
var _lamp_style := "round"


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
	# a grid of individual lamps: round reflectors, square floods or LED strips
	var cols := maxi(2, roundi(size.x / 0.42))
	var rows := maxi(1, roundi(size.y / 0.42))
	var lamp: Mesh
	var face: Mesh
	match _lamp_style:
		"flood":
			var lb := BoxMesh.new()
			lb.size = Vector3(0.36, 0.14, 0.3)
			lamp = lb
			var fb := BoxMesh.new()
			fb.size = Vector3(0.3, 0.02, 0.24)
			face = fb
		"led":
			# long thin LED bars, one per row
			cols = 1
			rows = maxi(2, roundi(size.y / 0.22))
			var lb := BoxMesh.new()
			lb.size = Vector3(size.x * 0.94, 0.08, 0.12)
			lamp = lb
			var fb := BoxMesh.new()
			fb.size = Vector3(size.x * 0.9, 0.02, 0.07)
			face = fb
		_:
			var lc := CylinderMesh.new()
			lc.top_radius = 0.17
			lc.bottom_radius = 0.2
			lc.height = 0.12
			lc.radial_segments = 12
			lc.rings = 1
			lamp = lc
			var fc := CylinderMesh.new()
			fc.top_radius = 0.15
			fc.bottom_radius = 0.15
			fc.height = 0.02
			fc.radial_segments = 12
			fc.rings = 1
			face = fc
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
		# a faint beam down to the pitch, seen at night (stronger in rain and fog)
		var dist := pos.distance_to(aim)
		var beam := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = maxf(size.x, size.y) * 0.4
		cm.bottom_radius = dist * tan(deg_to_rad(18.0))
		cm.height = dist
		cm.radial_segments = 16
		cm.cap_top = false
		cm.cap_bottom = false
		beam.mesh = cm
		beam.material_override = _beam_material()
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# the head looks down -Z towards the aim; the cylinder runs along Y
		beam.rotation.x = -PI / 2.0
		beam.position = Vector3(0, 0, -dist / 2.0)
		head.add_child(beam)


## Metal-halide floodlights take a moment to come up: each bank flickers on
## and warms to full over a couple of seconds, one after another.
func warm_up_floodlights() -> void:
	var i := 0
	for spot in _spots:
		if not is_instance_valid(spot) or not spot.visible:
			continue
		var full: float = spot.light_energy
		spot.light_energy = 0.0
		var tw := create_tween()
		tw.tween_interval(0.15 * i)
		tw.tween_property(spot, "light_energy", full * 0.35, 0.12)
		tw.tween_property(spot, "light_energy", full * 0.1, 0.08)
		tw.tween_property(spot, "light_energy", full, 2.2).set_ease(Tween.EASE_OUT)
		i += 1


var _beam_mat: StandardMaterial3D


## Light beams: unshaded, additive, glowing only at night; set_weather makes
## them stronger in rain and fog.
func _beam_material() -> StandardMaterial3D:
	if _beam_mat == null:
		_beam_mat = StandardMaterial3D.new()
		_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam_mat.albedo_color = Color(0, 0, 0, 1)
		_beam_mat.disable_receive_shadows = true
	var k := _beam_strength if _night else 0.0
	_beam_mat.albedo_color = Color(1.0 * k, 0.95 * k, 0.85 * k, 1.0)   # additive: the colour is the brightness
	return _beam_mat


var _beam_strength := 0.07


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
var season_t := 0.0   # how far through the season (0 August .. 1 May): leaves turn and fall


## A deciduous tree's tint for the time of year: green in late summer, gold
## and rust through autumn, thin and brown in winter, fresh again in spring.
func _seasonal(c: Color, i: int) -> Color:
	var t := season_t
	var autumn := smoothstep(0.12, 0.3, t) * (1.0 - smoothstep(0.45, 0.6, t))
	var winter := smoothstep(0.45, 0.6, t) * (1.0 - smoothstep(0.8, 0.92, t))
	var turn := [Color(1.35, 0.78, 0.35), Color(1.3, 0.55, 0.3), Color(1.25, 1.0, 0.4)][i % 3] as Color
	var out := c.lerp(turn, autumn * 0.85)
	return out.lerp(Color(0.62, 0.5, 0.4), winter * 0.8)


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
	# rock outcrops on the steeper slopes and up the mountains
	var kinds := ["nature-kit/rock_largeA", "nature-kit/rock_largeC", "nature-kit/rock_largeE", "nature-kit/rock_tallB", "nature-kit/rock_largeB", "nature-kit/rock_tallE"]
	var rocks := {}
	var rock_m := tex_mat("rocky_terrain_02", Color(0.82, 0.88, 1.0), 2.0)
	for k in 2800:
		var a := rng.randf() * TAU
		var r := rng.randf_range(60.0, 420.0)
		var p := c + Vector2(cos(a), sin(a)) * r
		var sl := _slope(p.x, p.y)
		var hy := terrain_h(p.x, p.y)
		if sl < 0.28 or hy < 0.5:
			continue
		var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
		var sc := rng.randf_range(1.5, 4.5) * (1.0 + sl) / maxf(0.01, Kenney.size(kind).x)
		if not rocks.has(kind):
			rocks[kind] = [] as Array[Transform3D]
		(rocks[kind] as Array[Transform3D]).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.6, 1.1), sc)), Vector3(p.x, hy - (0.35 + sl * 0.6) * sc * Kenney.size(kind).y, p.y)))
	for kind in rocks:
		var mi := Kenney.batch(kind, rocks[kind])
		mi.material_override = rock_m
		_ground.add_child(mi)
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
	var road_m := tex_mat("asphalt_01", Color(0.5, 0.56, 0.66), 2.0)
	var field_cols := [Color(0.6, 0.54, 0.34), Color(0.4, 0.48, 0.26), Color(0.36, 0.29, 0.22), Color(0.48, 0.54, 0.3)]
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.03
	var road := 2.0
	var road_st := SurfaceTool.new()
	road_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pave_st := SurfaceTool.new()
	pave_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mark_st := SurfaceTool.new()
	mark_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var streets: Array = []
	var lamp_spots: Array[Vector3] = []
	_lot_st = SurfaceTool.new()
	_lot_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_drive_st = SurfaceTool.new()
	_drive_st.begin(Mesh.PRIMITIVE_TRIANGLES)
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
			var keep_out := Rect2(layout.plot).grow(2.6 + road)
			if cell.intersects(keep_out):
				# trim the block back to the ring road rather than dropping it
				var best := Rect2()
				for part in [Rect2(cell.position.x, cell.position.y, keep_out.position.x - cell.position.x - 0.6, cell.size.y),
						Rect2(keep_out.end.x + 0.6, cell.position.y, cell.end.x - keep_out.end.x - 0.6, cell.size.y),
						Rect2(cell.position.x, cell.position.y, cell.size.x, keep_out.position.y - cell.position.y - 0.6),
						Rect2(cell.position.x, keep_out.end.y + 0.6, cell.size.x, cell.end.y - keep_out.end.y - 0.6)]:
					var pr2: Rect2 = part
					if pr2.size.x >= 5.0 and pr2.size.y >= 5.0 and pr2.get_area() > best.get_area():
						best = pr2
				if best.get_area() <= 0.0:
					continue
				cell = best
			var centre := cell.get_center()
			var dist := maxf(maxf(clear.position.x - centre.x, centre.x - clear.end.x), maxf(clear.position.y - centre.y, centre.y - clear.end.y))
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
				# carriageway, raised pavements either side with a kerb line,
				# solid edge lines and a dashed centre line
				_drape_add(road_st, n_road, 0.06)
				_drape_add(road_st, w_road, 0.06)
				# parked cars along the kerb
				for r3 in [n_road, w_road]:
					var rr3: Rect2 = r3
					var ax := rr3.size.x > rr3.size.y
					var ln := rr3.size.x if ax else rr3.size.y
					var t3 := 0.8
					while t3 < ln - 0.8:
						if rng.randf() < 0.22:
							var kind3: String = CAR_KINDS[rng.randi_range(0, CAR_KINDS.size() - 1)]
							var sc3 := Kenney.scale_to(kind3, 1.1)
							var side3 := 0.28 if rng.randf() < 0.5 else road - 0.28
							var pos3 := Vector2(rr3.position.x + t3, rr3.position.y + side3) if ax else Vector2(rr3.position.x + side3, rr3.position.y + t3)
							var yaw3 := (PI / 2.0 if ax else 0.0) + (PI if side3 > 1.0 else 0.0)
							add.call(kind3, Transform3D(Basis(Vector3.UP, yaw3).scaled(Vector3(sc3, sc3, sc3)), Vector3(pos3.x, 0.12, pos3.y)), CAR_TINTS[rng.randi_range(0, CAR_TINTS.size() - 1)])
						t3 += 1.4
					# streetlights on the pavement, alternating sides
					var t4 := 2.0
					var flip := false
					var lsc := 2.3 / maxf(0.01, Kenney.size("city-kit-roads/light-curved").y)
					while t4 < ln - 1.0:
						var off4 := -0.3 if flip else road + 0.3
						var p4 := Vector2(rr3.position.x + t4, rr3.position.y + off4) if ax else Vector2(rr3.position.x + off4, rr3.position.y + t4)
						var yaw4 := (0.0 if not flip else PI) + (0.0 if ax else -PI / 2.0)
						add.call("city-kit-roads/light-curved", Transform3D(Basis(Vector3.UP, yaw4).scaled(Vector3(lsc, lsc, lsc)), Vector3(p4.x, 0.13, p4.y)), Color(0.5, 0.52, 0.55))
						if dist < 90.0:
							var into := Vector2(0, 1 if flip else -1) if ax else Vector2(1 if flip else -1, 0)
							lamp_spots.append(Vector3(p4.x + into.x * 0.5, terrain_h(p4.x, p4.y) + 2.2, p4.y + into.y * 0.5))
						flip = not flip
						t4 += 5.0
				if dist < 110.0:
					streets.append([Vector2(n_road.position.x, n_road.get_center().y), Vector2(n_road.end.x, n_road.get_center().y)])
					streets.append([Vector2(w_road.get_center().x, w_road.position.y), Vector2(w_road.get_center().x, w_road.end.y)])
				var pw := 0.55
				_drape_add(pave_st, Rect2(n_road.position.x - pw, n_road.position.y - pw, n_road.size.x + pw, pw), 0.13)
				_drape_add(pave_st, Rect2(n_road.position.x + road, n_road.end.y, n_road.size.x - road, pw), 0.13)
				_drape_add(pave_st, Rect2(w_road.position.x - pw, w_road.position.y, pw, w_road.size.y), 0.13)
				_drape_add(pave_st, Rect2(w_road.end.x, w_road.position.y + pw, pw, w_road.size.y - pw), 0.13)
				for r2 in [n_road, w_road]:
					var rr: Rect2 = r2
					var along_x := rr.size.x > rr.size.y
					var length := rr.size.x if along_x else rr.size.y
					var t := 0.4
					while t + 0.6 < length - 0.4:
						var dash := Rect2(rr.position.x + t, rr.get_center().y - 0.03, 0.6, 0.06) if along_x else Rect2(rr.get_center().x - 0.03, rr.position.y + t, 0.06, 0.6)
						_drape_add(mark_st, dash, 0.075, 1.0)
						t += 1.3
					for side in [0.18, road - 0.22]:
						var edge := Rect2(rr.position.x + 0.3, rr.position.y + side, length - 0.6, 0.04) if along_x else Rect2(rr.position.x + side, rr.position.y + 0.3, 0.04, length - 0.6)
						_drape_add(mark_st, edge, 0.075, 2.0)
				roads += 1
			_fill_block(cell, block_mode, dist, rng, add, houses, low_shops, mid_blocks, towers, tree_kinds, pines, facades, field_cols, bld)
	# the ring road round the club's land, which the town's streets run into
	var ring := Rect2(layout.plot).grow(2.6)
	var ring_roads := [Rect2(ring.position.x, ring.position.y, ring.size.x, road), Rect2(ring.position.x, ring.end.y - road, ring.size.x, road),
		Rect2(ring.position.x, ring.position.y + road, road, ring.size.y - 2.0 * road), Rect2(ring.end.x - road, ring.position.y + road, road, ring.size.y - 2.0 * road)]
	for rr6 in ring_roads:
		var r6: Rect2 = rr6
		_drape_add(road_st, r6, 0.06)
		var ax6 := r6.size.x > r6.size.y
		_drape_add(pave_st, (Rect2(r6.position.x, r6.position.y - 0.55, r6.size.x, 0.55) if ax6 else Rect2(r6.position.x - 0.55, r6.position.y, 0.55, r6.size.y)), 0.13)
		_drape_add(pave_st, (Rect2(r6.position.x, r6.end.y, r6.size.x, 0.55) if ax6 else Rect2(r6.end.x, r6.position.y, 0.55, r6.size.y)), 0.13)
		var len6 := r6.size.x if ax6 else r6.size.y
		var t6 := 0.4
		while t6 + 0.6 < len6 - 0.4:
			_drape_add(mark_st, (Rect2(r6.position.x + t6, r6.get_center().y - 0.03, 0.6, 0.06) if ax6 else Rect2(r6.get_center().x - 0.03, r6.position.y + t6, 0.06, 0.6)), 0.075, 1.0)
			t6 += 1.3
		streets.append([Vector2(r6.position.x, r6.get_center().y), Vector2(r6.end.x, r6.get_center().y)] if ax6 else [Vector2(r6.get_center().x, r6.position.y), Vector2(r6.get_center().x, r6.end.y)])
		roads += 1
	town.build(_trees)
	# warm pools of light under the streetlamps (shown at night)
	_street_lamps = Node3D.new()
	_street_lamps.visible = _night
	_trees.add_child(_street_lamps)
	var glows: Array[Transform3D] = []
	for lp in lamp_spots:
		glows.append(Transform3D(Basis().scaled(Vector3(0.18, 0.08, 0.18)), lp))
	_mm(_street_lamps, glows, mat(Color(1.0, 0.85, 0.55), 0.3, 0.0, 6.0), false)
	var pool := ShaderMaterial.new()
	pool.shader = load("res://view/light_pool.gdshader")
	var pools: Array[Transform3D] = []
	for lp in lamp_spots:
		pools.append(Transform3D(Basis().scaled(Vector3(3.4, 1.0, 3.4)), Vector3(lp.x, lp.y - 2.06, lp.z)))
	var disc := PlaneMesh.new()
	disc.size = Vector2(1, 1)
	var pmm := MultiMesh.new()
	pmm.transform_format = MultiMesh.TRANSFORM_3D
	pmm.mesh = disc
	pmm.instance_count = pools.size()
	for i in pools.size():
		pmm.set_instance_transform(i, pools[i])
	var pmi := MultiMeshInstance3D.new()
	pmi.multimesh = pmm
	pmi.material_override = pool
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_street_lamps.add_child(pmi)
	# traffic on the nearer streets
	var traffic := Traffic.new()
	traffic.name = "Traffic"
	for st2 in streets:
		traffic.add_street(st2[0], st2[1], terrain_h)
	traffic.populate(mini(700, streets.size() * 5), 99)
	_trees.add_child(traffic)
	for pair2 in [[_lot_st, tex_mat("asphalt_01", Color(0.62, 0.68, 0.78), 3.0)], [_drive_st, tex_mat("square_concrete_pavers", Color(1.0, 1.1, 1.25), 1.0)]]:
		var st5: SurfaceTool = pair2[0]
		st5.generate_normals()
		var m5 := MeshInstance3D.new()
		m5.mesh = st5.commit()
		m5.material_override = pair2[1]
		m5.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_trees.add_child(m5)
	_lot_st = null
	_drive_st = null
	for pair in [[road_st, road_m], [pave_st, tex_mat("square_concrete_pavers", Color(1.0, 1.15, 1.35), 1.2)], [mark_st, mat(Color(0.92, 0.92, 0.88), 0.7)]]:
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
			# a three-arch stone road bridge: deck, parapets, piers and arch rings
			var stone := tex_mat("rough_concrete", Color(0.62, 0.58, 0.52), 1.5, true)
			box(_trees, Vector3(bx - 2.0, 0.55, bz - 12.0), Vector3(bx + 2.0, 0.85, bz + 12.0), stone)
			box(_trees, Vector3(bx - 1.6, 0.85, bz - 12.0), Vector3(bx + 1.6, 0.88, bz + 12.0), tex_mat("asphalt_01", Color(0.5, 0.56, 0.66), 2.0))
			for e in [-1.0, 1.0]:
				box(_trees, Vector3(bx + e * 1.85 - 0.15, 0.85, bz - 12.0), Vector3(bx + e * 1.85 + 0.15, 1.3, bz + 12.0), stone)
				box(_trees, Vector3(bx + e * 1.85 - 0.18, 1.3, bz - 12.0), Vector3(bx + e * 1.85 + 0.18, 1.38, bz + 12.0), tex_mat("rough_concrete", Color(0.75, 0.72, 0.66), 1.5, true))
			for pz in [-4.0, 4.0]:
				box(_trees, Vector3(bx - 2.1, -1.6, bz + pz - 0.8), Vector3(bx + 2.1, 0.6, bz + pz + 0.8), stone)
				for e2 in [-1.0, 1.0]:
					var cut := MeshInstance3D.new()
					var pm2 := PrismMesh.new()
					pm2.size = Vector3(4.3, 0.9, 1.0)
					cut.mesh = pm2
					cut.material_override = stone
					cut.position = Vector3(bx, -0.6, bz + pz + e2 * 1.2)
					cut.rotation.x = PI / 2.0 * e2
					_trees.add_child(cut)
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
		elif rng.randf() < 0.025:
			kind = "pub"
		elif rng.randf() < 0.012:
			kind = "church"
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
			_lot_paving(cell, rng, add, 0.75)
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
				_lot_paving(cell, rng, add, 0.45)
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
						_driveway(p, gz == 0, cell, rng, add)
						if rng.randf() < 0.5:
							tree.call(p + Vector2(rng.randf_range(-1.6, 1.6), 2.6 if gz == 0 else -2.6), tree_kinds, rng.randf_range(3.0, 4.5))


var _lot_st: SurfaceTool
var _drive_st: SurfaceTool


## A paved yard filling a town/city block (behind and between the
## buildings), with cars parked on it: shops and flats sit in hardstanding,
## not lawn.
func _lot_paving(cell: Rect2, rng: RandomNumberGenerator, add: Callable, cars: float) -> void:
	if _lot_st == null:
		return
	_drape_add(_lot_st, cell.grow(-0.15), 0.045, 2.0)
	var n := int(cell.get_area() / 9.0 * cars)
	for i in n:
		var q := cell.position + Vector2(rng.randf_range(0.6, cell.size.x - 0.6), rng.randf_range(0.6, cell.size.y - 0.6))
		var kind: String = CAR_KINDS[rng.randi_range(0, CAR_KINDS.size() - 1)]
		var sc := Kenney.scale_to(kind, 1.1)
		add.call(kind, Transform3D(Basis(Vector3.UP, rng.randi_range(0, 3) * PI / 2.0).scaled(Vector3(sc, sc, sc)), Vector3(q.x, 0.1, q.y)), CAR_TINTS[rng.randi_range(0, CAR_TINTS.size() - 1)])


## A house's driveway from the street to beside the house, often with a car.
func _driveway(p: Vector2, north: bool, cell: Rect2, rng: RandomNumberGenerator, add: Callable) -> void:
	if _drive_st == null:
		return
	var dx := 1.55
	var z0 := cell.position.y if north else p.y + 1.0
	var z1 := p.y - 1.0 if north else cell.end.y
	_drape_add(_drive_st, Rect2(p.x + dx - 0.35, minf(z0, z1), 0.7, absf(z1 - z0)), 0.05, 2.0)
	if rng.randf() < 0.6:
		var kind: String = CAR_KINDS[rng.randi_range(0, CAR_KINDS.size() - 1)]
		var sc := Kenney.scale_to(kind, 1.1)
		var cz := (z0 + z1) / 2.0
		add.call(kind, Transform3D(Basis(Vector3.UP, 0.0 if north else PI).scaled(Vector3(sc, sc, sc)), Vector3(p.x + dx, 0.1, cz)), CAR_TINTS[rng.randi_range(0, CAR_TINTS.size() - 1)])


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


## Roads, paths and landscaping the player painted, plus warnings over
## transport links with no road or a long walk.
func _build_site(layout: Layout, config: SimConfig) -> void:
	var site := layout.site
	var surf := {
		"road": tex_mat("asphalt_01", Color(0.55, 0.6, 0.7), 2.0),
		"path_concrete": tex_mat("square_concrete_pavers", Color(1.05, 1.15, 1.3), 1.5),
		"path_brick": tex_mat("red_brick_03", Color(1.25, 1.05, 0.95), 0.45),
		"path_cobble": tex_mat("square_concrete_pavers", Color(0.78, 0.76, 0.74), 0.35),
		"path_gravel": tex_mat("rough_concrete", Color(0.85, 0.78, 0.66), 1.0),
		"path_setts": tex_mat("square_concrete_pavers", Color(0.62, 0.62, 0.66), 0.25),
		"path_tarmac": tex_mat("asphalt_01", Color(0.75, 0.75, 0.8), 2.0),
		"path_resin": tex_mat("rough_concrete", (_club.primary_color if _club else Color(0.6, 0.2, 0.2)).lerp(Color(0.6, 0.6, 0.6), 0.35) * 1.4, 3.0, true),
		"path_timber": tex_mat("oak_wood_planks", Color(1.0, 0.95, 0.9), 0.8),
	}
	# surfaces, merged into runs along x
	for kind in surf:
		for y in range(layout.plot.position.y, layout.plot.end.y):
			var x := layout.plot.position.x
			while x < layout.plot.end.x:
				if site.get(Vector2i(x, y), "") != kind:
					x += 1
					continue
				var x0 := x
				while x < layout.plot.end.x and site.get(Vector2i(x, y), "") == kind:
					x += 1
				box(_land, Vector3(x0, -0.01, y), Vector3(x, 0.03 if kind == "road" else 0.04, y + 1), surf[kind], false)
	# kerbs where a road or path meets grass
	var kerb: Array[Transform3D] = []
	var dirs := [[Vector2i(1, 0), Vector3(1.0, 0, 0.5), true], [Vector2i(-1, 0), Vector3(0.0, 0, 0.5), true], [Vector2i(0, 1), Vector3(0.5, 0, 1.0), false], [Vector2i(0, -1), Vector3(0.5, 0, 0.0), false]]
	for t in site:
		var g := layout.site_group(t, config)
		if g == "green":
			continue
		for d in dirs:
			var n: Vector2i = t + d[0]
			if layout.site_group(n, config) in ["road", "path"] or not layout.in_plot(n):
				continue
			var o: Vector3 = d[1]
			var along_x: bool = not d[2]
			kerb.append(Transform3D(Basis().scaled(Vector3(1.0 if along_x else 0.08, 0.07, 0.08 if along_x else 1.0)), Vector3(t.x + o.x, 0.04, t.y + o.z)))
	_mm(_land, kerb, tex_mat("rough_concrete", Color(0.8, 0.8, 0.78), 1.0), false)
	# road markings: a dashed centre line along straight runs of access road,
	# and give-way lines where a road meets a path (a crossing)
	var marks: Array[Transform3D] = []
	for t in site:
		if site[t] != "road":
			continue
		var ex: bool = site.get(t + Vector2i(1, 0), "") == "road" or site.get(t + Vector2i(-1, 0), "") == "road"
		var ez: bool = site.get(t + Vector2i(0, 1), "") == "road" or site.get(t + Vector2i(0, -1), "") == "road"
		if ex and not ez:
			marks.append(Transform3D(Basis().scaled(Vector3(0.45, 0.01, 0.05)), Vector3(t.x + 0.5, 0.036, t.y + 0.5)))
		elif ez and not ex:
			marks.append(Transform3D(Basis().scaled(Vector3(0.05, 0.01, 0.45)), Vector3(t.x + 0.5, 0.036, t.y + 0.5)))
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var dv: Vector2i = d
			if layout.site_group(t + dv, config) == "path":
				# zebra stripes across the road where the footpath crosses
				for k in 4:
					var off := (k - 1.5) * 0.22
					if dv.x != 0:
						marks.append(Transform3D(Basis().scaled(Vector3(0.12, 0.01, 0.8)), Vector3(t.x + 0.5 + off, 0.037, t.y + 0.5)))
					else:
						marks.append(Transform3D(Basis().scaled(Vector3(0.8, 0.01, 0.12)), Vector3(t.x + 0.5, 0.037, t.y + 0.5 + off)))
				break
	_mm(_land, marks, mat(Color(0.92, 0.92, 0.88), 0.7), false)
	# green items
	var trees := {}
	var flower_t: Array[Transform3D] = []
	var flower_c: Array[Color] = []
	var hedge: Array[Transform3D] = []
	var wood: Array[Transform3D] = []
	var metal: Array[Transform3D] = []
	var steel_bits: Array[Transform3D] = []
	var bikes: Array[Transform3D] = []
	var bolls: Array[Transform3D] = []
	var bands: Array[Transform3D] = []
	var sign_t: Array[Transform3D] = []
	var banner_t: Array[Transform3D] = []
	var lamp_spots: Array[Vector3] = []
	var lanterns: Array[Transform3D] = []
	var stone: Array[Transform3D] = []
	var soil: Array[Transform3D] = []
	var bins: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	var lamps: Array[Transform3D] = []
	var flag_m := StandardMaterial3D.new()
	flag_m.albedo_texture = badge_texture()
	flag_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var kinds := { "tree_oak": "proc/oak", "tree_birch": "proc/birch", "tree_pine": "proc/spruce", "tree_plane": "proc/lime", "tree_poplar": "proc/poplar", "tree_fir": "proc/fir", "tree_bush": "proc/bush" }
	for t in site:
		var k: String = site[t]
		rng.seed = hash(t) ^ 7919
		var cx: float = t.x + 0.5
		var cz: float = t.y + 0.5
		match k:
			"tree_oak", "tree_birch", "tree_pine", "tree_plane", "tree_poplar", "tree_fir", "tree_bush":
				var kind: String = kinds[k]
				if not trees.has(kind):
					var ta: Array[Transform3D] = []
					var tcl: Array[Color] = []
					trees[kind] = [ta, tcl]
				var h: float = rng.randf_range(3.4, 4.6) * { "tree_pine": 1.25, "tree_poplar": 1.4, "tree_fir": 1.2, "tree_bush": 0.3 }.get(k, 1.0)
				var sc := h / maxf(0.01, Kenney.size(kind).y)
				trees[kind][0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(cx + rng.randf_range(-0.15, 0.15), 0, cz + rng.randf_range(-0.15, 0.15))))
				trees[kind][1].append(_leaf(rng))
				soil.append(Transform3D(Basis().scaled(Vector3(0.7, 0.03, 0.7)), Vector3(cx, 0.015, cz)))
			"hedge":
				hedge.append(Transform3D(Basis().scaled(Vector3(1.0, 0.7, 1.0)), Vector3(cx, 0.35, cz)))
			"hedge_tall":
				hedge.append(Transform3D(Basis().scaled(Vector3(1.0, 1.6, 0.8)), Vector3(cx, 0.8, cz)))
			"hedge_wild":
				# an untrimmed hedgerow: lumpy clumps of different heights
				for i in 4:
					var hh := rng.randf_range(0.6, 1.3)
					var hw := rng.randf_range(0.45, 0.7)
					hedge.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(hw, hh, hw)), Vector3(cx + rng.randf_range(-0.3, 0.3), hh / 2.0, cz + rng.randf_range(-0.3, 0.3))))
			"flowers", "flowers_club":
				stone.append(Transform3D(Basis().scaled(Vector3(0.96, 0.12, 0.96)), Vector3(cx, 0.06, cz)))
				soil.append(Transform3D(Basis().scaled(Vector3(0.86, 0.04, 0.86)), Vector3(cx, 0.13, cz)))
				var palette := [Color(0.9, 0.2, 0.25), Color(1.0, 0.8, 0.2), Color(0.65, 0.35, 0.8), Color(1.0, 0.55, 0.7), Color(1, 1, 1)]
				var pc: Color = palette[rng.randi_range(0, palette.size() - 1)]
				if k == "flowers_club" and _club:
					pc = _club.primary_color if (t.x + t.y) % 2 == 0 else _club.secondary_color
				for i in 26:
					var q := Vector3(cx + rng.randf_range(-0.38, 0.38), 0.14, cz + rng.randf_range(-0.38, 0.38))
					var fs := rng.randf_range(0.14, 0.22)
					flower_t.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(fs, fs * 1.2, fs)), q))
					flower_c.append(pc * rng.randf_range(1.6, 2.4) if i % 3 != 0 else Color(0.7, 1.0, 0.6))
			"bench":
				var rot := 0.0 if (site.get(t + Vector2i(0, 1), "") != "" or site.get(t + Vector2i(0, -1), "") != "") else PI / 2.0
				var bb := Basis(Vector3.UP, rot)
				for sl in 3:
					wood.append(Transform3D(bb.scaled(Vector3(0.8, 0.03, 0.07)), Vector3(cx, 0.22, cz) + bb * Vector3(0, 0, -0.08 + sl * 0.09)))
				wood.append(Transform3D(bb.scaled(Vector3(0.8, 0.14, 0.03)), Vector3(cx, 0.33, cz) + bb * Vector3(0, 0, 0.14)))
				for e in [-0.34, 0.34]:
					metal.append(Transform3D(bb.scaled(Vector3(0.04, 0.22, 0.3)), Vector3(cx, 0.11, cz) + bb * Vector3(e, 0, 0.02)))
			"lamp_heritage":
				# a Victorian lamp post: fluted column, crossbar, lantern
				lamp_spots.append(Vector3(cx, 1.9, cz))
				metal.append(Transform3D(Basis().scaled(Vector3(0.09, 0.3, 0.09)), Vector3(cx, 0.15, cz)))
				metal.append(Transform3D(Basis().scaled(Vector3(0.05, 1.7, 0.05)), Vector3(cx, 1.0, cz)))
				metal.append(Transform3D(Basis().scaled(Vector3(0.36, 0.03, 0.03)), Vector3(cx, 1.7, cz)))
				metal.append(Transform3D(Basis().scaled(Vector3(0.2, 0.05, 0.2)), Vector3(cx, 2.08, cz)))
				lanterns.append(Transform3D(Basis().scaled(Vector3(0.14, 0.22, 0.14)), Vector3(cx, 1.94, cz)))
			"bench_stone":
				stone.append(Transform3D(Basis().scaled(Vector3(0.85, 0.08, 0.32)), Vector3(cx, 0.26, cz)))
				for e in [-0.32, 0.32]:
					stone.append(Transform3D(Basis().scaled(Vector3(0.12, 0.22, 0.28)), Vector3(cx + e, 0.11, cz)))
			"bin":
				bins.append(Transform3D(Basis().scaled(Vector3(0.24, 0.42, 0.24)), Vector3(cx, 0.21, cz)))
			"lamp":
				lamp_spots.append(Vector3(cx, 2.1, cz))
				var lsc := 2.3 / maxf(0.01, Kenney.size("city-kit-roads/light-curved").y)
				lamps.append(Transform3D(Basis(Vector3.UP, rng.randi_range(0, 3) * PI / 2.0).scaled(Vector3(lsc, lsc, lsc)), Vector3(cx, 0, cz)))
			"flagpole", "flagpole_stripes":
				metal.append(Transform3D(Basis().scaled(Vector3(0.05, 4.2, 0.05)), Vector3(cx, 2.1, cz)))
				var qm := QuadMesh.new()
				qm.size = Vector2(1.1, 0.75)
				var fl := MeshInstance3D.new()
				fl.mesh = qm
				if k == "flagpole_stripes":
					var sm := StandardMaterial3D.new()
					sm.albedo_texture = _banner_tex("stripes", _club.primary_color, _club.secondary_color)
					sm.cull_mode = BaseMaterial3D.CULL_DISABLED
					fl.material_override = sm
				else:
					fl.material_override = flag_m
				fl.position = Vector3(cx + 0.58, 3.75, cz)
				fl.rotation.y = rng.randf_range(-0.3, 0.3)
				_land.add_child(fl)
			"bike_rack":
				# a row of steel hoops, now and then a bike locked to one
				for i in 4:
					var hx := cx - 0.36 + i * 0.24
					for e in [-0.08, 0.08]:
						steel_bits.append(Transform3D(Basis().scaled(Vector3(0.03, 0.42, 0.03)), Vector3(hx, 0.21, cz + e)))
					steel_bits.append(Transform3D(Basis().scaled(Vector3(0.03, 0.03, 0.19)), Vector3(hx, 0.42, cz)))
					if rng.randf() < 0.5:
						bikes.append(Transform3D(Basis().scaled(Vector3(0.03, 0.22, 0.5)), Vector3(hx + 0.06, 0.18, cz)))
			"bollards":
				for i in 3:
					var bx := cx - 0.33 + i * 0.33
					bolls.append(Transform3D(Basis().scaled(Vector3(0.11, 0.5, 0.11)), Vector3(bx, 0.25, cz)))
					bands.append(Transform3D(Basis().scaled(Vector3(0.12, 0.05, 0.12)), Vector3(bx, 0.42, cz)))
			"planter":
				stone.append(Transform3D(Basis().scaled(Vector3(0.8, 0.4, 0.8)), Vector3(cx, 0.2, cz)))
				soil.append(Transform3D(Basis().scaled(Vector3(0.7, 0.04, 0.7)), Vector3(cx, 0.41, cz)))
				for i in 5:
					hedge.append(Transform3D(Basis().scaled(Vector3(0.3, 0.32, 0.3) * rng.randf_range(0.8, 1.2)), Vector3(cx + rng.randf_range(-0.22, 0.22), 0.55, cz + rng.randf_range(-0.22, 0.22))))
			"signpost":
				metal.append(Transform3D(Basis().scaled(Vector3(0.05, 1.6, 0.05)), Vector3(cx, 0.8, cz)))
				for i in 2:
					var fb := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
					sign_t.append(Transform3D(fb.scaled(Vector3(0.6, 0.14, 0.03)), Vector3(cx, 1.35 - i * 0.22, cz) + fb * Vector3(0.28, 0, 0)))
			"lamp_banner":
				lamp_spots.append(Vector3(cx, 2.1, cz))
				var lsc2 := 2.3 / maxf(0.01, Kenney.size("city-kit-roads/light-curved").y)
				lamps.append(Transform3D(Basis(Vector3.UP, rng.randi_range(0, 3) * PI / 2.0).scaled(Vector3(lsc2, lsc2, lsc2)), Vector3(cx, 0, cz)))
				for e in [-1.0, 1.0]:
					banner_t.append(Transform3D(Basis().scaled(Vector3(0.02, 0.7, 0.3)), Vector3(cx + e * 0.06, 1.5, cz + e * 0.17)))
			"fence":
				metal.append(Transform3D(Basis().scaled(Vector3(0.05, 0.8, 0.05)), Vector3(cx, 0.4, cz)))
				for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
					var dv: Vector2i = d
					if site.get(t + dv, "") == "fence":
						var half := Vector3(dv.x * 0.25, 0, dv.y * 0.25)
						for hy in [0.12, 0.7]:
							metal.append(Transform3D(Basis().scaled(Vector3(0.5 if dv.x != 0 else 0.03, 0.03, 0.5 if dv.y != 0 else 0.03)), Vector3(cx, hy, cz) + half))
						for bi in 3:
							var off := Vector3(dv.x, 0, dv.y) * (0.1 + bi * 0.15)
							metal.append(Transform3D(Basis().scaled(Vector3(0.02, 0.6, 0.02)), Vector3(cx, 0.4, cz) + off))
	for kind in trees:
		var tr: Array[Transform3D] = trees[kind][0]
		var tc: Array[Color] = trees[kind][1]
		if not kind in ["proc/spruce", "proc/fir"]:
			for ti in tc.size():
				tc[ti] = _seasonal(tc[ti], ti)
		var mi := Kenney.batch(kind, tr, tc)
		mi.set_meta("tree", true)
		_land.add_child(mi)
	_mm(_land, soil, tex_mat("forrest_ground_01", Color(0.6, 0.5, 0.42), 1.0), false)
	_mm(_land, stone, tex_mat("rough_concrete", Color(0.78, 0.76, 0.72), 1.0))
	_mm(_land, wood, mat(Color(0.5, 0.36, 0.24), 0.8))
	_mm(_land, metal, mat(Color(0.12, 0.14, 0.13), 0.45, 0.6))
	var lant_m := StandardMaterial3D.new()
	lant_m.albedo_color = Color(1.0, 0.9, 0.65)
	lant_m.emission_enabled = true
	lant_m.emission = Color(1.0, 0.82, 0.5)
	_glow(lant_m, 0.2, 2.5)
	_mm(_land, lanterns, lant_m)
	_mm(_land, steel_bits, mat(Color(0.62, 0.64, 0.67), 0.35, 0.8))
	# lamps throw warm pools of light on the paving at night (a sensible number of real lights)
	var every := maxi(1, lamp_spots.size() / 24)
	for li in range(0, lamp_spots.size(), every):
		var ol := OmniLight3D.new()
		ol.light_color = Color(1.0, 0.82, 0.55)
		ol.light_energy = 1.6
		ol.omni_range = 3.2
		ol.omni_attenuation = 1.4
		ol.shadow_enabled = false
		ol.position = lamp_spots[li]
		_land.add_child(ol)
		_night_light(ol)
	_mm(_land, bikes, mat(Color(0.15, 0.15, 0.16), 0.5, 0.3))
	_mm(_land, bolls, mat(Color(0.2, 0.22, 0.24), 0.5, 0.4))
	_mm(_land, bands, mat(Color(0.95, 0.85, 0.3), 0.4))
	_mm(_land, sign_t, mat(_club.primary_color if _club else Color(0.2, 0.3, 0.5), 0.5))
	_mm(_land, banner_t, mat(_club.primary_color if _club else Color(0.8, 0.1, 0.1), 0.8))
	if not hedge.is_empty():
		var hm := MultiMesh.new()
		hm.transform_format = MultiMesh.TRANSFORM_3D
		hm.mesh = BoxMesh.new()
		hm.instance_count = hedge.size()
		for i in hedge.size():
			hm.set_instance_transform(i, hedge[i])
		var hmi := MultiMeshInstance3D.new()
		hmi.multimesh = hm
		hmi.material_override = ProcTrees.material()
		_land.add_child(hmi)
	if not bins.is_empty():
		var bm := MultiMesh.new()
		bm.transform_format = MultiMesh.TRANSFORM_3D
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.5
		cyl.bottom_radius = 0.45
		cyl.height = 1.0
		bm.mesh = cyl
		bm.instance_count = bins.size()
		for i in bins.size():
			bm.set_instance_transform(i, bins[i])
		var bmi := MultiMeshInstance3D.new()
		bmi.multimesh = bm
		bmi.material_override = mat(Color(0.14, 0.26, 0.18), 0.5, 0.3)
		_land.add_child(bmi)
	if not lamps.is_empty():
		var grey: Array[Color] = []
		for i in lamps.size():
			grey.append(Color(0.2, 0.22, 0.22))
		_land.add_child(Kenney.batch("city-kit-roads/light-curved", lamps, grey))
	if not flower_t.is_empty():
		var fm := MultiMesh.new()
		fm.transform_format = MultiMesh.TRANSFORM_3D
		fm.use_colors = true
		fm.mesh = ProcTrees.tuft_mesh()
		fm.instance_count = flower_t.size()
		for i in flower_t.size():
			fm.set_instance_transform(i, flower_t[i])
			fm.set_instance_color(i, flower_c[i])
		var fmi := MultiMeshInstance3D.new()
		fmi.multimesh = fm
		fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_land.add_child(fmi)
	# warnings over transport links: no road, or a long walk
	var status := layout.transport_status(config)
	for f in status:
		var fac: Facility = f
		var st: Dictionary = status[f]
		var ft := config.facility_type(fac.type_id)
		var c := Vector3(fac.pos.x + fac.size(ft).x / 2.0, 3.2, fac.pos.y + fac.size(ft).y / 2.0)
		if not bool(st["connected"]):
			_label(_land, "⚠ NO ENTRANCE" if ft.layer == "underground" else "⚠ NO ROAD", c, 64, Color(1.0, 0.4, 0.3), true, 0.012)
		elif float(st["factor"]) < 0.9:
			_label(_land, "LONG WALK", c, 52, Color(1.0, 0.8, 0.3), true, 0.01)


## Placement preview for painting: green tiles that will be laid, red ones taken.
func show_site_ghost(ok: Array, bad: Array, afford: bool) -> void:
	clear_overlay()
	var okm := mat(C_OK if afford else C_NO, 1.0, 0.0, 0.3, 0.45)
	var badm := mat(C_NO, 1.0, 0.0, 0.3, 0.45)
	for pair in [[ok, okm], [bad, badm]]:
		var xf: Array[Transform3D] = []
		for t in pair[0]:
			var p: Vector2i = t
			xf.append(Transform3D(Basis().scaled(Vector3(0.94, 0.08, 0.94)), Vector3(p.x + 0.5, 0.08, p.y + 0.5)))
		_mm(_overlay, xf, pair[1], false)


var _config: SimConfig
var _ring_top := 0.0   # with a roof ring, every roof sits at this stand height
var _ring_reach := 0.0  # with a roof ring, every roof's reach (0 = each its own)


func build_layout(layout: Layout, config: SimConfig, report: MatchdayReport, selected: int, club: ClubState) -> void:
	_pitch_rect = Rect2(layout.pitch)
	if _pitch_mat:
		_pitch_mat.set_shader_parameter("season_wear", clampf(season_t * 1.2, 0.0, 1.0))
	_club = club
	_config = config
	for g in [_solids, _ghosts, _concourse, _bowl, _outside, _under, _markers]:
		for c in g.get_children():
			c.free()
	_roofs.clear()
	_levels.clear()
	_name_labels.clear()
	_glows.clear()
	_night_lights.clear()
	var cd := config.integer("layout/concourse_depth")
	var main_stand := _main_stand(layout, config)
	_ring_top = 0.0
	_ring_reach = layout.ring_reach if layout.roof_ring else 0.0
	if layout.roof_ring:
		for st in layout.stands:
			if st.roof != "open":
				_ring_top = maxf(_ring_top, stand_top(st))
	_corner_rects.clear()
	_corner_tiers.clear()
	_tier_leds.clear()
	for st in layout.stands:
		if st.is_corner():
			_corner_rects.append(tiles_xz(st.tiles(layout.pitch)))
			_corner_tiers.append(st.tiers)
	var ghost_m := mat(Color(0.85, 0.9, 1.0), 1.0, 0.0, 0.0, 0.14)
	for i in layout.stands.size():
		var s := layout.stands[i]
		var root := Node3D.new()
		_solids.add_child(root)
		_hollow_from = s.depth - cd if Layout.internal_concourse(s, config) and s.tiers == 1 else 999
		_paint = s.extra("paint")
		_rs = s.extra("roof_shape")
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
				if ft.kind == "circulation":
					var ci := layout.circulation_stand(f, config, conc_map, stand_tiles)
					var cs: Stand = layout.stands[ci] if ci >= 0 else null
					_build_circulation(f, ft, cs, layout.pitch)
				else:
					_build_facility(f, ft, y)
	_build_landscape(layout, config)
	_problem_markers(layout, config, report)
	if layout.pitch_placed:
		apply_pitch_look(layout)
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
	_beam_strength = { "rain": 0.2, "snow": 0.22, "fog": 0.28 }.get(w, 0.07)
	_beam_material()
	if _weather_node:
		_weather_node.free()
		_weather_node = null
	_trees.visible = layer != "underground"
	for c in _trees.get_children():
		c.visible = true
	if _terrain_mat:
		_terrain_mat.set_shader_parameter("snow", 0.0)
		_terrain_mat.set_shader_parameter("wet", 1.0 if w == "rain" else 0.0)
	# paving, roads and concrete go dark and shiny in the rain
	for key in _mats:
		var wm = _mats[key]
		if wm is StandardMaterial3D and String(key).begins_with("tex|"):
			var sm: StandardMaterial3D = wm
			if not sm.has_meta("dry_rough"):
				sm.set_meta("dry_rough", sm.roughness)
				sm.set_meta("dry_col", sm.albedo_color)
			var dry_r: float = sm.get_meta("dry_rough")
			var dry_c: Color = sm.get_meta("dry_col")
			sm.roughness = dry_r * 0.45 if w == "rain" else dry_r
			sm.albedo_color = dry_c.darkened(0.22) if w == "rain" else dry_c
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


var _street_lamps: Node3D


func set_night(on: bool) -> void:
	_night = on
	for em in _etfe_mats:
		em.emission_energy_multiplier = 0.75 if on else 0.03
	_beam_material()
	if _street_lamps and is_instance_valid(_street_lamps):
		_street_lamps.visible = on
	ProcBuildings.set_night(on)
	for e in _name_labels:
		if is_instance_valid(e[0]):
			_light_name(e[0], e[1], e[2])
	for g in _glows:
		var gm: BaseMaterial3D = g[0]
		gm.emission_energy_multiplier = float(g[2]) if on else float(g[1])
	for l in _night_lights:
		if is_instance_valid(l):
			(l as Light3D).visible = on
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
		# the main stand is the biggest seated one (a terrace only if there's no seating)
		var cap := s.capacity(config.stand_type(s.type_id)) * (3 if has_seats(s) else 1)
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


## How weathered a stand looks (the player's choice, 0 new .. 1 old).
func _age(s: Stand) -> float:
	return clampf(float(s.extra("age")["years"]), 0.0, 1.0)


## A colour as it looks after years out in the weather: darker, dirtier, a
## touch browner.
func _aged(c: Color, s: Stand) -> Color:
	var a := _age(s)
	if a <= 0.0:
		return c
	return c.lerp(Color(0.32, 0.3, 0.26), a * 0.35).darkened(a * 0.18)


func seat_color(s: Stand) -> Color:
	var a := _age(s)
	if a > 0.0:
		# plastic seats fade in the sun
		return _seat_color_raw(s).lerp(Color(0.62, 0.6, 0.58), a * 0.4)
	return _seat_color_raw(s)


func _seat_color_raw(s: Stand) -> Color:
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
	var fin := String(_paint.get("trim_mat" if trim else "wall_mat", ""))
	if fin != "":
		var fc := _pc("trim" if trim else "wall")
		var base := fc if fc.r >= 0.0 else Color(1, 1, 1)
		if _age(s) > 0.0 and fin != "glass" and fin != "etfe":
			base = _aged(base if fc.r >= 0.0 else Color(0.9, 0.9, 0.9), s)
		return finish_mat(fin, base, 2.0) as StandardMaterial3D
	var pw := _pc("trim" if trim else "wall")
	if pw.r >= 0.0:
		match s.facade:
			"brick", "steel", "arcade", "concrete", "painted":
				var tex: String = { "brick": "red_brick_03", "steel": "metal_plate", "arcade": "rough_concrete", "concrete": "rough_concrete", "painted": "rough_concrete" }[s.facade]
				return tex_mat(tex, pw * 1.3, 2.0 if s.facade != "concrete" else 3.0, s.facade in ["concrete", "arcade", "painted"])
			"glass":
				return mat(pw, 0.08, 0.4)
			_:
				return mat(pw, 0.55, 0.3 if s.facade in ["panels", "fins"] else 0.0)
	match s.facade:
		"brick": return tex_mat("red_brick_03", Color.WHITE if not trim else Color(0.8, 0.8, 0.8), 2.0)
		"glass": return mat(Color(0.55, 0.7, 0.8), 0.08, 0.4) if not trim else mat(Color(0.3, 0.32, 0.36), 0.4, 0.6)
		"steel": return tex_mat("metal_plate", Color(0.85, 0.87, 0.9), 2.0)
		"club": return mat(_club.primary_color, 0.6) if not trim else mat(_club.primary_color.darkened(0.3), 0.6)
		"fins": return mat(Color(0.14, 0.15, 0.17), 0.7) if not trim else mat(Color(0.5, 0.38, 0.26), 0.55, 0.35)
		"panels": return mat(_club.primary_color.lerp(Color(0.62, 0.36, 0.24), 0.6), 0.45, 0.55) if not trim else mat(_club.primary_color.lerp(Color(0.3, 0.18, 0.12), 0.7), 0.6)
		"arcade": return tex_mat("rough_concrete", Color(0.8, 0.8, 0.78), 3.0, true) if not trim else mat(Color(0.88, 0.87, 0.84), 0.8)
		"painted": return tex_mat("rough_concrete", _club.primary_color.lightened(0.15), 3.0, true) if not trim else tex_mat("rough_concrete", _club.secondary_color, 3.0, true)
		"heritage": return tex_mat("red_brick_03", Color(1.05, 1.0, 0.98), 1.6) if not trim else tex_mat("rough_concrete", Color(0.92, 0.88, 0.8), 1.0, true)
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


## A grass bank: a smooth earth slope (the crowd stands where each row
## would be), worn concrete steps cut into it, a crush barrier here and there,
## and a post-and-rail fence along the top.
func _build_bank(root: Node3D, s: Stand, pitch: Rect2i) -> void:
	var tp := to_pitch(s.side)
	var foot := tiles_xz(s.lower_tiles(pitch))
	var fr := _frame(root, foot, tp)
	var L := foot.size.x if tp.x == 0.0 else foot.size.y
	var D := foot.size.y if tp.x == 0.0 else foot.size.x
	# in the frame, +z points at the pitch: front edge at z = D/2, back at -D/2
	var h0 := maxf(0.05, s.plinth - _rise(s) * 0.5)
	var h1 := s.plinth + (s.depth - 0.5) * _rise(s)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hl := L / 2.0
	var hd := D / 2.0
	var quads := [
		[Vector3(-hl, h0, hd), Vector3(hl, h0, hd), Vector3(hl, h1, -hd), Vector3(-hl, h1, -hd)],   # the slope
		[Vector3(-hl, 0, hd), Vector3(hl, 0, hd), Vector3(hl, h0, hd), Vector3(-hl, h0, hd)],       # front lip
		[Vector3(hl, 0, -hd), Vector3(-hl, 0, -hd), Vector3(-hl, h1, -hd), Vector3(hl, h1, -hd)],   # back
	]
	for q in quads:
		for k in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(q[k])
	for e in [-1.0, 1.0]:
		# the triangular ends
		var tri := [Vector3(e * hl, 0, hd), Vector3(e * hl, h0, hd), Vector3(e * hl, h1, -hd), Vector3(e * hl, 0, hd), Vector3(e * hl, h1, -hd), Vector3(e * hl, 0, -hd)]
		# both windings, so each end is lit from whichever side you see it
		for v in tri + [tri[0], tri[2], tri[1], tri[3], tri[5], tri[4]]:
			st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = tex_mat("grass_ground", Color(0.62, 0.72, 0.42), 2.0)
	fr.add_child(mi)
	# concrete steps across the slope every other row, a central gangway
	var step := tex_mat("rough_concrete", Color(0.7, 0.69, 0.66), 1.5)
	var slope := atan2(h1 - h0, D)
	for v in range(0, s.depth, 2):
		var z := hd - (v + 0.5)
		var y := row_height(v, s)
		lbox(fr, Vector3(0, y - 0.02, z), Vector3(L - 0.4, 0.06, 0.32), step)
	var gw := lbox(fr, Vector3(0, (h0 + h1) / 2.0 + 0.03, 0), Vector3(0.9, 0.06, sqrt(D * D + (h1 - h0) * (h1 - h0))), step, 0.0)
	gw.rotation.x = slope
	# crush barriers in short runs
	var bar := mat(Color(0.3, 0.32, 0.3), 0.5, 0.6)
	for v in range(2, s.depth, 3):
		var z := hd - (v + 0.5)
		var y := row_height(v, s)
		var x := -hl + 1.5
		while x < hl - 1.5:
			if absf(x) > 1.0:
				lbox(fr, Vector3(x, y + 0.42, z + 0.3), Vector3(1.6, 0.05, 0.05), bar)
				for px in [x - 0.75, x + 0.75]:
					lbox(fr, Vector3(px, y + 0.21, z + 0.3), Vector3(0.05, 0.42, 0.05), bar)
			x += 3.5
	# post-and-rail fence along the top
	var wood := mat(Color(0.42, 0.34, 0.26), 0.9)
	var px := -hl
	while px <= hl:
		lbox(fr, Vector3(px, h1 + 0.3, -hd + 0.1), Vector3(0.08, 0.6, 0.08), wood)
		px += 1.5
	for hy in [0.3, 0.55]:
		lbox(fr, Vector3(0, h1 + hy, -hd + 0.1), Vector3(L, 0.05, 0.04), wood)


func _build_stand(root: Node3D, s: Stand, pitch: Rect2i, selected: bool, label: Dictionary, is_main: bool) -> void:
	if s.type_id == "bank":
		_build_bank(root, s, pitch)
		return
	_wall_spot = []
	var tp := to_pitch(s.side)
	var concrete := tex_mat("rough_concrete", _aged(Color(0.6, 0.6, 0.59), s), 3.0, true)
	var seat := mat(seat_color(s), 0.7) if not has_seats(s) else tex_mat("rough_concrete", Color(0.68, 0.68, 0.67), 3.0, true)
	var rail := mat(_dc(s, "barrier", Color(0.85, 0.75, 0.2) if s.type_id == "terrace" else Color(0.25, 0.26, 0.28)), 0.5 if s.type_id == "terrace" else 0.4, 0.5 if s.type_id == "terrace" else 0.7)
	var top := 0.0
	for v in s.depth:
		var r := tiles_xz(s.row_tiles(pitch, v))
		var hgt := row_height(v, s)
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
	var stacked := s.facade == "stacked"
	if stacked and s.tiers <= 1:
		_stacked_back(fr, s, L, -D / 2.0, top + 1.1)
	else:
		lbox(fr, Vector3(0, (top + 1.1) / 2.0, -D / 2.0 + 0.07), Vector3(L, top + 1.1, 0.14), wall_m)
	if s.tiers <= 1 and not stacked:
		_facade_detail(fr, s, L, -D / 2.0, top + 1.1, is_main)
	_gangways(fr, s, L, D)
	# front parapet along the touchline edge
	var front_m := _part("front", mat(Color(0.18, 0.18, 0.2), 0.5), Color(0.18, 0.18, 0.2), 1.0)
	match String(s.extra("detail").get("front_style", "wall")):
		"glass":
			# a low kerb with glass panels above, so the front row sees through
			lbox(fr, Vector3(0, s.plinth * 0.5, D / 2.0 - 0.04), Vector3(L, s.plinth, 0.08), front_m)
			lbox(fr, Vector3(0, s.plinth + 0.2, D / 2.0 - 0.04), Vector3(L, 0.4, 0.03), mat(Color(0.75, 0.85, 0.9), 0.05, 0.3, 0.0, 0.3))
			lbox(fr, Vector3(0, s.plinth + 0.41, D / 2.0 - 0.04), Vector3(L, 0.03, 0.05), _steel())
		"rail":
			# a kerb with a steel rail on posts
			lbox(fr, Vector3(0, s.plinth * 0.5, D / 2.0 - 0.04), Vector3(L, s.plinth, 0.08), front_m)
			lbox(fr, Vector3(0, s.plinth + 0.36, D / 2.0 - 0.04), Vector3(L, 0.035, 0.035), _steel())
			lbox(fr, Vector3(0, s.plinth + 0.18, D / 2.0 - 0.04), Vector3(L, 0.02, 0.02), _steel())
			var posts: Array[Transform3D] = []
			var px := -L / 2.0 + 0.1
			while px <= L / 2.0:
				posts.append(Transform3D(Basis().scaled(Vector3(0.03, 0.38, 0.03)), Vector3(px, s.plinth + 0.19, D / 2.0 - 0.04)))
				px += 1.2
			_mm(fr, posts, _steel())
		_:
			lbox(fr, Vector3(0, s.plinth * 0.5 + 0.12, D / 2.0 - 0.04), Vector3(L, s.plinth + 0.24, 0.08), front_m)
	if is_main:
		_tunnel_and_gantry(fr, s, L, D, top)
	var open_end := {}
	for e in [-1, 1]:
		# no tall end wall where a corner stand carries the seats on round
		var probe: Vector3 = fr.transform * Vector3(e * (L / 2.0 + 0.5), 0, 0)
		for ci in _corner_rects.size():
			if (_corner_rects[ci] as Rect2).grow(0.6).has_point(Vector2(probe.x, probe.z)):
				open_end[e] = maxi(int(open_end.get(e, 0)), _corner_tiers[ci])
		if open_end.has(e):
			lbox(fr, Vector3(e * (L / 2.0 - 0.03), s.plinth + 0.5, 0), Vector3(0.05, 0.05, D), mat(Color(0.75, 0.77, 0.8), 0.3, 0.8))
		elif stacked:
			pass   # the open-tier bands wrap round the end below
		else:
			lbox(fr, Vector3(e * (L / 2.0 - 0.06), (top + 0.5) / 2.0, 0), Vector3(0.12, top + 0.5, D), dark)
			if s.facade == "concrete" and top > 2.0:
				# the exposed end: the same fins and glazed band as the back
				var ex: float = e * (L / 2.0 + 0.04)
				lbox(fr, Vector3(ex, 0.6, 0), Vector3(0.1, 1.2, D), tex_mat("concrete_tile_facade", Color(1.5, 1.5, 1.5), 2.0))
				lbox(fr, Vector3(ex, 1.85, 0), Vector3(0.06, 1.1, D - 0.2), mat(Color(0.2, 0.27, 0.33), 0.06, 0.55))
				lbox(fr, Vector3(ex, 2.52, 0), Vector3(0.14, 0.24, D), mat(_club.primary_color, 0.5))
				var efins: Array[Transform3D] = []
				var zz := -D / 2.0 + 0.3
				while zz < D / 2.0 - 0.2:
					var fh := top + 0.3 - 2.64
					if fh > 0.4:
						efins.append(Transform3D(Basis().scaled(Vector3(0.28, fh, 0.2)), Vector3(ex + e * 0.08, 2.64 + fh / 2.0, zz)))
					zz += 0.75
				_mm(fr, efins, facade_mat(s))
	# upper tiers: stepped slabs further back and higher, with a club-coloured
	# fascia along the front, end walls and a full-height back wall
	for k in range(1, s.tiers):
		var base := tier_base(s, k)
		var tf := tier_front(s, k)
		for i in s.depth:
			var zf := D / 2.0 - tf - i
			var y := base + row_height(i, s)
			lbox(fr, Vector3(0, y - 0.3, zf - 0.5), Vector3(L, 0.6, 1.0), concrete)
			lbox(fr, Vector3(0, y + 0.035, zf - 0.35), Vector3(L - 0.06, 0.07, 0.68), seat)
			if s.type_id == "safe_standing" or (s.type_id == "terrace" and i % 2 == 1):
				lbox(fr, Vector3(0, y + 0.15, zf - 0.6), Vector3(L - 0.06, 0.3, 0.05), rail)
		var front_z := D / 2.0 - tf
		_tier_front(fr, s, L, base, front_z, k)
		var t_top := base + row_height(s.depth - 1, s)
		for e in [-1, 1]:
			if int(open_end.get(e, 0)) > k or stacked:
				continue   # the corner carries this tier round (or the bands wrap it)
			lbox(fr, Vector3(e * (L / 2.0 - 0.06), (base - 0.6 + t_top + 0.5) / 2.0, front_z - s.depth / 2.0),
				Vector3(0.12, t_top + 0.5 - base + 0.6, float(s.depth)), dark)
		top = t_top
	var extra := float(tier_front(s, s.tiers - 1))
	if s.tiers > 1:
		var bz := -D / 2.0 - extra + 0.07
		if stacked:
			_stacked_back(fr, s, L, bz - 0.07, top + 1.1)
		else:
			lbox(fr, Vector3(0, (top + 1.1) / 2.0, bz), Vector3(L, top + 1.1, 0.14), wall_m)
			_facade_detail(fr, s, L, bz - 0.07, top + 1.1, is_main)
		for e in [-1, 1]:
			if int(open_end.get(e, 0)) >= s.tiers or stacked:
				continue
			lbox(fr, Vector3(e * (L / 2.0 - 0.06), (top + 1.1) / 2.0, -D / 2.0 - extra / 2.0), Vector3(0.12, top + 1.1, extra), dark)
	if stacked:
		# wrap the open-tier bands round each end that doesn't run into a corner
		for e in [-1, 1]:
			if int(open_end.get(e, 0)) >= s.tiers:
				continue
			var en := Node3D.new()
			fr.add_child(en)
			en.position = Vector3(e * L / 2.0, 0, -extra / 2.0)
			en.rotation.y = -e * PI / 2.0
			_stacked_back(en, s, D + extra, 0.0, top + 1.1)
	_split_skin(fr, s, L, -D / 2.0 - extra, top + 1.1)
	_windows(fr, s, L, -D / 2.0 - extra, top + 1.1)
	_uplights(fr, s, L, D, extra, top)
	if bool(s.extra("detail")["boxes"]):
		_box_fronts(s, fr, L, D)
	_wall_signs(s, fr, L, D, top, open_end)
	# roof (covers every tier: a frame shifted back by the upper tiers' setback)
	var roof := Node3D.new()
	fr.add_child(roof)
	roof.position.z = -extra / 2.0
	D += extra
	_roofs.append(roof)
	roof.visible = show_roofs
	var rtop := maxf(top, _ring_top)   # a roof ring puts every roof at one height
	var name_y := 0.0
	var name_z := 0.0
	match s.roof:
		"gable", "shed":
			name_y = _roof_gable(roof, L, D, rtop)
			name_z = D / 2.0 + 0.82
			if s.roof == "shed":
				# the classic covered terrace: the roof rests on a row of
				# slim columns along the front, with knee braces
				var col_m: Material = _steel() if _pc("steel").r >= 0.0 or String(_paint.get("steel_mat", "")) != "" else mat(Color(0.2, 0.32, 0.25) if _club == null else _club.primary_color.darkened(0.45), 0.5, 0.5)
				var ch := rtop + ROOF_CLEARANCE
				var x := -L / 2.0 + 0.3
				var step := maxf(2.5, L / maxf(1.0, roundf(L / 3.5)))
				while x <= L / 2.0 - 0.2:
					lbox(roof, Vector3(x, ch / 2.0, D / 2.0 - 0.25), Vector3(0.12, ch, 0.12), col_m)
					for e in [-1, 1]:
						var br := lbox(roof, Vector3(x + e * 0.25, ch - 0.3, D / 2.0 - 0.25), Vector3(0.06, 0.7, 0.06), col_m)
						br.rotation.z = e * -0.7
					x += step
		"cantilever", "mast":
			name_y = _roof_cantilever(roof, L, D, rtop, s.length)
			name_z = D / 2.0 + 0.72
		"barrel":
			name_y = _roof_barrel(roof, L, D, rtop, s.length)
			name_z = D / 2.0 + 0.72
		"truss":
			name_y = _roof_truss(roof, L, D, rtop)
			name_z = D / 2.0 + 0.85
		"translucent":
			var tint := _pc("roof")
			var clear := mat(tint if tint.r >= 0.0 else Color(0.85, 0.92, 0.98), 0.15, 0.1, 0.0, 0.42)
			name_y = _roof_cantilever(roof, L, D, rtop, s.length, clear)
			name_z = D / 2.0 + 0.72
		"solar":
			var cells := _pc("roof")
			name_y = _roof_cantilever(roof, L, D, rtop, s.length, mat(cells if cells.r >= 0.0 else Color(0.1, 0.14, 0.26), 0.45, 0.15))
			name_z = D / 2.0 + 0.72
			_solar_grid(roof, L, D, rtop)
		"membrane":
			name_y = _roof_membrane(roof, L, D, rtop)
			name_z = D / 2.0 + 0.72
		"sawtooth":
			name_y = _roof_sawtooth(roof, L, D, rtop)
			name_z = D / 2.0 + 0.72
	if s.roof == "mast":
		_roof_masts(roof, L, D, rtop, s.length)
	if s.roof != "open" and String(_rs.get("top_truss", "none")) != "none":
		_top_trusses(roof, L, D, rtop)
	if s.roof != "open" and String(_rs.get("pylons", "none")) != "none":
		_roof_pylons(roof, L, D, rtop)
	if s.roof != "open" and String(_rs.get("ends", "open")) in ["closed", "glazed"]:
		_roof_ends(roof, s, L, D, rtop, open_end)
	if s.roof in ["cantilever", "mast", "translucent", "solar", "barrel", "truss"] and String(_rs.get("back", "open")) != "open":
		# close the gap between the back wall and the roof: cladding or glazing
		var by := rtop + ROOF_CLEARANCE - _roof_tilt() * 0.4
		var gap := by - (top + 1.1)
		if String(_rs["back"]) == "tyre":
			# a skin that bulges out from the ground and curves back in over the
			# top to meet the roof, in the wall's finish (Allianz Arena)
			_tyre_skin(roof, s, L, -D / 2.0, by)
		elif gap > 0.1:
			var bm: Material = facade_mat(s, true) if String(_rs["back"]) == "closed" else mat(Color(0.6, 0.72, 0.8), 0.05, 0.3, 0.0, 0.45)
			lbox(roof, Vector3(0, top + 1.1 + gap / 2.0, -D / 2.0 + 0.08), Vector3(L, gap, 0.1), bm)
	_stand_extras(s, is_main, fr, roof, L, D, name_y, name_z)
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


## The main stand's players' tunnel (a mouth in the front wall and a
## telescopic cover out onto the pitch) and the TV camera gantry above.
func _tunnel_and_gantry(fr: Node3D, s: Stand, L: float, D: float, top: float) -> void:
	var dark := mat(Color(0.08, 0.08, 0.09), 0.7)
	lbox(fr, Vector3(0, 0.35, D / 2.0 - 0.02), Vector3(1.0, 0.7, 0.06), dark)
	# concertina cover in segments, club colour with a white trim
	for i in 2:
		var w := 0.9 - i * 0.04
		var h := 0.55 - i * 0.03
		var seg := lbox(fr, Vector3(0, h / 2.0, D / 2.0 + 0.14 + i * 0.24), Vector3(w, h, 0.22), mat(_club.primary_color, 0.45))
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		lbox(fr, Vector3(0, h + 0.01, D / 2.0 + 0.14 + i * 0.24), Vector3(w + 0.02, 0.03, 0.22), mat(Color(0.95, 0.95, 0.95), 0.5))
	if s.roof == "open":
		return
	# TV camera gantry hung under the front of the roof at halfway
	var gy := top + ROOF_CLEARANCE - 0.75
	var gz := D / 2.0 - 0.1
	lbox(fr, Vector3(0, gy, gz), Vector3(2.2, 0.08, 0.7), mat(Color(0.3, 0.32, 0.34), 0.5, 0.6))
	lbox(fr, Vector3(0, gy + 0.3, gz + 0.33), Vector3(2.2, 0.04, 0.04), mat(Color(0.75, 0.77, 0.8), 0.4, 0.7))
	for cx in [-0.6, 0.5]:
		lbox(fr, Vector3(cx, gy + 0.22, gz), Vector3(0.05, 0.36, 0.05), mat(Color(0.15, 0.15, 0.16), 0.4))
		var cam := lbox(fr, Vector3(cx, gy + 0.46, gz + 0.05), Vector3(0.18, 0.16, 0.36), mat(Color(0.12, 0.12, 0.13), 0.35, 0.3), 0.0)
		cam.rotation.x = 0.15


## A stand of private boxes (palcos): every few rows a glazed box frontage
## facing the pitch, with dividers, a balcony rail and a lit interior.
func _box_fronts(s: Stand, fr: Node3D, L: float, D: float) -> void:
	var every := clampi(int(s.extra("detail")["box_every"]), 1, 6)
	var glass := StandardMaterial3D.new()
	var bg := String(s.extra("detail").get("box_glass", ""))
	var gc := Color.html(bg) if bg != "" and Color.html_is_valid(bg) else Color(0.2, 0.28, 0.34)
	glass.albedo_color = Color(gc.r, gc.g, gc.b, 0.45)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.3
	var frame := _steel()
	var warm := StandardMaterial3D.new()
	warm.albedo_color = Color(0.9, 0.75, 0.5)
	warm.emission_enabled = true
	warm.emission = Color(1.0, 0.8, 0.5)
	_glow(warm, 0.25, 2.2)
	for k in s.tiers:
		var base := tier_base(s, k)
		var tf := tier_front(s, k)
		var v := 0
		while v < s.depth:
			var zf := D / 2.0 - tf - v
			var y := base + row_height(v, s)
			var h := minf(row_height(v + every, s) - row_height(v, s), 2.2)
			lbox(fr, Vector3(0, y + h / 2.0, zf - 0.55), Vector3(L - 0.1, h - 0.1, 0.05), glass)
			lbox(fr, Vector3(0, y + h * 0.4, zf - 0.75), Vector3(L - 0.3, h * 0.6, 0.02), warm)
			var x := -L / 2.0
			while x <= L / 2.0 + 0.01:
				lbox(fr, Vector3(clampf(x, -L / 2.0 + 0.04, L / 2.0 - 0.04), y + h / 2.0, zf - 0.5), Vector3(0.06, h, 0.6), frame)
				x += 2.0
			# balcony: a ledge and a glass rail in front of each row of boxes
			lbox(fr, Vector3(0, y + 0.04, zf - 0.25), Vector3(L, 0.08, 0.5), tex_mat("rough_concrete", Color(0.8, 0.8, 0.78), 2.0, true))
			lbox(fr, Vector3(0, y + 0.35, zf - 0.02), Vector3(L, 0.5, 0.03), mat(Color(0.75, 0.85, 0.92), 0.05, 0.2, 0.0, 0.4))
			v += every


## Signs the player placed on the stand's walls: text, crests, hanging
## banners, player portraits and murals, each on a chosen surface at a chosen
## spot (u along, v up), with its own size, depth and lighting.
func _wall_signs(s: Stand, fr: Node3D, L: float, D: float, top: float, open_end: Dictionary) -> void:
	var list := s.signs()
	if list.is_empty():
		return
	var back_z: float = float(_wall_spot[1]) if not _wall_spot.is_empty() and _wall_spot[0] == fr else -D / 2.0 - 0.08
	var back_h: float = float(_wall_spot[2]) if not _wall_spot.is_empty() and _wall_spot[0] == fr else top + 1.1
	for o in list:
		var surface: String = o["surface"]
		var u: float = o["u"]
		var v: float = o["v"]
		var pos := Vector3.ZERO
		var yaw := 0.0
		var span := L
		var h := back_h
		match surface:
			"back":
				pos = Vector3(lerpf(L / 2.0 - 0.5, -L / 2.0 + 0.5, u), 0, back_z - 0.08)
				yaw = PI
			"end_left", "end_right", "inner_left", "inner_right":
				var left := surface.ends_with("left")
				var inner := surface.begins_with("inner")
				if open_end.has(-1 if left else 1):
					continue   # no wall there: a corner stand carries on round
				var ex := (-1.0 if left else 1.0) * (L / 2.0 + (-0.16 if inner else 0.16))
				pos = Vector3(ex, 0, lerpf(back_z + 0.5, D / 2.0 - 0.5, u if left != inner else 1.0 - u))
				yaw = (-PI / 2.0 if left else PI / 2.0) * (-1.0 if inner else 1.0)
				span = D
				h = top + 0.5
			"front":
				pos = Vector3(lerpf(-L / 2.0 + 0.5, L / 2.0 - 0.5, u), 0, D / 2.0 + 0.06)
				h = s.plinth + 0.24
			"tier":
				if s.tiers < 2:
					continue
				var k := s.tiers - 1
				pos = Vector3(lerpf(-L / 2.0 + 0.5, L / 2.0 - 0.5, u), 0, D / 2.0 - tier_front(s, k) + 0.12)
				h = tier_base(s, k) + 0.15
		var scale: float = o["scale"]
		var y_lo := 0.4
		var y_hi := maxf(y_lo, h - 0.4)
		if surface == "front":
			pos.y = s.plinth * 0.5 + 0.05
		elif surface == "tier":
			pos.y = h - 0.45
		else:
			pos.y = lerpf(y_lo, y_hi, v)
		var node := Node3D.new()
		node.position = pos
		node.rotation.y = yaw
		fr.add_child(node)
		_wall_sign(node, o, scale, span, h)


## Wall signs on a corner stand: on its outer wall (u runs round from one
## side to the other) or on its front wall facing the pitch corner.
func _corner_signs(root: Node3D, s: Stand, pitch: Rect2i, top: float, R: float) -> void:
	var list := s.signs()
	if list.is_empty():
		return
	var cf := corner_frame(s.side, pitch)
	var c: Vector2 = cf["centre"]
	var sx: float = cf["sx"]
	var sz: float = cf["sz"]
	var h := top + 1.1
	for o in list:
		var surface: String = o["surface"]
		if not surface in ["back", "front"]:
			continue
		var phi := PI / 2.0 * clampf(float(o["u"]), 0.05, 0.95)
		var u: Vector2
		if s.shape == "rounded":
			u = _se(phi)
		else:
			var d := Vector2(cos(phi), sin(phi))
			u = d / maxf(absf(d.x), absf(d.y))
		var dir := Vector2(sx * u.x, sz * u.y)
		var out := Vector2(sx * cos(phi), sz * sin(phi)).normalized()
		var node := Node3D.new()
		var r := R + 0.25 if surface == "back" else 0.35
		var p := c + dir * r
		var y := lerpf(0.4, maxf(0.4, h - 0.4), float(o["v"])) if surface == "back" else s.plinth * 0.5 + 0.05
		node.position = Vector3(p.x, y, p.y)
		var facing := out if surface == "back" else -out
		node.rotation.y = atan2(facing.x, facing.y)
		root.add_child(node)
		_wall_sign(node, o, float(o["scale"]), maxf(3.0, R * 0.9) if surface == "back" else 2.5, h if surface == "back" else s.plinth + 0.24)


func _wall_sign(node: Node3D, o: Dictionary, scale: float, span: float, wall_h: float) -> void:
	var c1 := _club.primary_color
	var c2 := _club.secondary_color
	var col := Color.html(o["color"]) if String(o["color"]) != "" else c2
	match String(o["kind"]):
		"text":
			var so: Dictionary = o.duplicate()
			if String(so["text"]) == "":
				so["text"] = _club.club_name
			Signs.build(node, so, col, Color.html(o["panel"]) if String(o["panel"]) != "" else c1, span * 0.95, _glow, _night_light)
		"crest":
			var depth: float = o["depth"]
			_crest(node, Vector3(0, 0, 0.02), 1.4 * scale, 0.0, false, "solid" if depth > 0.02 else "flat", String(o["light"]))
		"banner", "player":
			var n: int = o["count"]
			var bw := 0.9 * scale
			var bh := 2.4 * scale
			var gap := bw * 0.35
			var total := n * bw + (n - 1) * gap
			for k in n:
				var x := -total / 2.0 + bw / 2.0 + k * (bw + gap)
				var tex: Texture2D
				if String(o["kind"]) == "player":
					tex = _player_tex(int(o["seed"]) * 31 + k, c1, c2)
				else:
					tex = _banner_tex(String(o["pattern"]), c1, c2)
				var m := StandardMaterial3D.new()
				m.albedo_texture = tex
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.roughness = 0.85
				var q := QuadMesh.new()
				q.size = Vector2(bw, bh)
				var mi := MeshInstance3D.new()
				mi.mesh = q
				mi.material_override = m
				mi.position = Vector3(x, 0, 0.04)
				node.add_child(mi)
				# a pole across the top, a weight bar along the bottom
				lbox(node, Vector3(x, bh / 2.0 + 0.04, 0.05), Vector3(bw + 0.12, 0.05, 0.05), mat(Color(0.75, 0.76, 0.78), 0.3, 0.7))
				lbox(node, Vector3(x, -bh / 2.0 - 0.02, 0.05), Vector3(bw, 0.04, 0.04), mat(Color(0.3, 0.3, 0.32), 0.5, 0.5))
				if String(o["kind"]) == "banner" and String(o["pattern"]) == "crest":
					_crest(node, Vector3(x, bh * 0.12, 0.06), bw * 0.75, 0.0, false, "flat", "none")
			if String(o["text"]) != "":
				var so := { "text": o["text"], "mount": "painted", "font": o["font"], "scale": scale * 0.45 }
				var tn := Signs.build(node, so, col, c1, total, _glow, _night_light)
				tn.position = Vector3(0, -bh / 2.0 - 0.35 * scale, 0.05)
			if String(o["light"]) == "flood":
				var sp := SpotLight3D.new()
				sp.light_energy = 6.0
				sp.spot_range = bh * 2.5
				sp.spot_angle = clampf(rad_to_deg(atan2(total / 2.0 + 0.5, 1.5)), 20.0, 80.0)
				sp.position = Vector3(0, -bh / 2.0 - 0.6, 1.5)
				node.add_child(sp)
				sp.look_at(node.to_global(Vector3.ZERO), Vector3.UP)
				_night_light(sp)
		"mural":
			var full := bool(o.get("fill", false))
			var mw := span * 0.98 if full else minf(span * 0.9, 6.0 * scale)
			var mh := wall_h * 0.92 if full else minf(wall_h * 0.8, 2.6 * scale)
			var m := StandardMaterial3D.new()
			var mp := String(o["pattern"])
			if mp in ["fans", "waves", "sunburst"]:
				m.albedo_texture = _mural_tex(mp, int(o["seed"]), c1, c2, mw / maxf(0.5, mh))
			else:
				m.albedo_texture = _banner_tex(mp if mp != "crest" else "plain", c1, c2)
			m.roughness = 0.9
			var q := QuadMesh.new()
			q.size = Vector2(mw, mh)
			var mi := MeshInstance3D.new()
			mi.mesh = q
			mi.material_override = m
			mi.position.z = 0.01
			node.add_child(mi)
			if String(o["pattern"]) == "crest":
				_crest(node, Vector3(0, 0, 0.02), mh * 0.75, 0.0, false, "flat", "none")
			if String(o["text"]) != "":
				var tn := Signs.build(node, { "text": o["text"], "mount": "painted", "font": o["font"], "scale": scale * 0.6 }, col, c1, mw * 0.9, _glow, _night_light)
				tn.position = Vector3(0, -mh * 0.32, 0.02)


var _tex_cache := {}


## A painted mural for a whole wall: a crowd of fans with flags and scarves
## held up, rolling waves, or a sunburst, in the club's colours and a few
## brighter folk-art tones (Bombonera style). `aspect` = width / height.
func _mural_tex(kind: String, seed: int, c1: Color, c2: Color, aspect: float) -> Texture2D:
	var H := 128
	var W := clampi(int(H * aspect), 64, 1024)
	var key := "m|%s|%d|%s|%s|%d" % [kind, seed, c1.to_html(), c2.to_html(), W]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + 17
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var folk := [Color(0.95, 0.75, 0.15), Color(0.85, 0.2, 0.2), Color(0.2, 0.45, 0.8), Color(0.95, 0.95, 0.9), Color(0.25, 0.6, 0.3)]
	match kind:
		"fans":
			# sky in the club colour, then rows of fans as head-and-shoulder shapes
			for y in H:
				for x in W:
					img.set_pixel(x, y, c1.lightened(0.25).lerp(c1, float(y) / H))
			for row in 4:
				var base_y := 52 + row * 22
				var x := -8 + rng.randi_range(0, 8)
				while x < W + 10:
					var shirt: Color = c1 if rng.randf() < 0.45 else (c2 if rng.randf() < 0.6 else folk[rng.randi_range(0, folk.size() - 1)])
					var skin := Color(0.9, 0.72, 0.58).darkened(rng.randf_range(0.0, 0.55))
					var hy := base_y - rng.randi_range(0, 4)
					var arms := rng.randf() < 0.35
					for yy in range(hy - 8, H):
						for xx in range(x - 12, x + 13):
							if xx < 0 or xx >= W or yy < 0:
								continue
							var dx := xx - x
							if Vector2(dx, yy - hy).length() < 6.5:
								img.set_pixel(xx, yy, skin)
							elif yy > hy + 6 and absf(dx) < 9.0 + (yy - hy - 6) * 0.6:
								img.set_pixel(xx, yy, shirt.darkened(0.15 * row))
							elif arms and yy < hy + 2 and yy > hy - 18 and absf(absf(dx) - 9.0 - (hy - yy) * 0.15) < 1.6:
								img.set_pixel(xx, yy, skin)
					# now and then a flag or scarf held up over the heads
					if rng.randf() < 0.18:
						var fc: Color = c2 if rng.randf() < 0.5 else folk[rng.randi_range(0, folk.size() - 1)]
						for yy in range(maxi(0, hy - 30), maxi(0, hy - 14)):
							for xx in range(x, mini(W, x + 22)):
								img.set_pixel(xx, yy, fc if (yy / 4) % 2 == 0 else c1)
					x += rng.randi_range(14, 20)
		"waves":
			for y in H:
				for x in W:
					var v := sin(x * 0.06 + sin(y * 0.05) * 2.0) * 10.0 + y
					var band := int(v / 18.0) % 3
					img.set_pixel(x, y, [c1, c2, c1.lightened(0.3)][absi(band)])
		_:
			# a sunburst from the bottom centre
			for y in H:
				for x in W:
					var a := atan2(float(H - y), float(x - W / 2.0))
					var ray := int(a / PI * 24.0) % 2 == 0
					var r := Vector2(x - W / 2.0, H - y).length()
					var col := c2 if ray else c1
					if r < H * 0.28:
						col = folk[0]
					img.set_pixel(x, y, col)
	img.generate_mipmaps()
	_tex_cache[key] = ImageTexture.create_from_image(img)
	return _tex_cache[key]


## A banner or mural in club colours: stripes, halves, hoops, a crest, or plain.
func _banner_tex(pattern: String, c1: Color, c2: Color) -> Texture2D:
	var key := "b|%s|%s|%s" % [pattern, c1.to_html(), c2.to_html()]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create(64, 160, false, Image.FORMAT_RGB8)
	for y in 160:
		for x in 64:
			var two := false
			match pattern:
				"stripes": two = (x / 11) % 2 == 1
				"halves": two = x >= 32
				"hoops": two = (y / 20) % 2 == 1
			img.set_pixel(x, y, c2 if two else c1)
	img.generate_mipmaps()
	_tex_cache[key] = ImageTexture.create_from_image(img)
	return _tex_cache[key]


## A player portrait for a banner: shoulders and head in the club's kit, a
## squad number, a backdrop in club colours. Each seed is a different player.
func _player_tex(seed: int, c1: Color, c2: Color) -> Texture2D:
	var key := "p|%d|%s|%s" % [seed, c1.to_html(), c2.to_html()]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var W := 96
	var H := 256
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var skins := [Color(0.95, 0.8, 0.68), Color(0.85, 0.65, 0.5), Color(0.62, 0.44, 0.32), Color(0.42, 0.29, 0.21), Color(0.3, 0.2, 0.15)]
	var hairs := [Color(0.08, 0.06, 0.05), Color(0.3, 0.2, 0.1), Color(0.75, 0.6, 0.35), Color(0.12, 0.1, 0.1)]
	var skin: Color = skins[rng.randi_range(0, skins.size() - 1)]
	var hair: Color = hairs[rng.randi_range(0, hairs.size() - 1)]
	var bg_top := c1.darkened(0.35)
	var bg_bot := c1.lightened(0.1)
	var arms_up := rng.randf() < 0.4
	for y in H:
		for x in W:
			var t := float(y) / H
			var col := bg_top.lerp(bg_bot, t)
			# diagonal accent stripe
			if absf((x - y * 0.4) - 30.0) < 6.0:
				col = col.lerp(c2, 0.35)
			var dx := x - W / 2.0
			# head
			var hy := 78.0
			if Vector2(dx, (y - hy) * 0.85).length() < 17.0:
				col = skin * (0.92 + 0.08 * (1.0 - absf(dx) / 17.0))
				if y < hy - 6 and Vector2(dx, (y - hy) * 0.85).length() > 9.0 or y < hy - 10:
					col = hair
			# neck
			elif absf(dx) < 7.0 and y >= hy + 13 and y < hy + 24:
				col = skin * 0.85
			# shoulders and shirt
			elif y >= hy + 22:
				var half_w := 22.0 + minf(18.0, (y - hy - 22) * 1.2)
				if absf(dx) < half_w:
					col = c1.lightened(0.05) if absf(dx) > 6.0 or y > hy + 34 else c2
					if absf(absf(dx) - half_w) < 3.0:
						col = c2
			# raised arms
			if arms_up and y > 20 and y < hy + 30:
				for side in [-1.0, 1.0]:
					var ax: float = W / 2.0 + side * (30.0 + (hy + 30 - y) * 0.15)
					if absf(x - ax) < 6.0:
						col = c1 if y > hy - 10 else skin
			img.set_pixel(x, y, col)
	# squad number on the chest
	var num := rng.randi_range(2, 29)
	_draw_digits(img, str(num), W / 2, 150, c2)
	img.generate_mipmaps()
	_tex_cache[key] = ImageTexture.create_from_image(img)
	return _tex_cache[key]


func _draw_digits(img: Image, digits: String, cx: int, cy: int, col: Color) -> void:
	var w := digits.length() * 14 - 2
	var x0 := cx - w / 2
	for i in digits.length():
		var rows: Array = GLYPHS.get(digits[i], [])
		for r in rows.size():
			var row: String = rows[r]
			for c in row.length():
				if row[c] == "1":
					for yy in 3:
						for xx in 2:
							img.set_pixel(clampi(x0 + i * 14 + c * 2 + xx, 0, img.get_width() - 1), clampi(cy + r * 3 + yy, 0, img.get_height() - 1), col)


const SIDE_NAMES := { "N": "NORTH", "S": "SOUTH", "E": "EAST", "W": "WEST" }


## The stand's name on its back wall, the way grounds label their stands.
func stand_title(s: Stand, is_main: bool) -> String:
	if s.sponsor != "" and _config and _config.sponsors.has(s.sponsor):
		return "%s %s" % [String(_config.sponsors[s.sponsor]["name"]).to_upper(), "CORNER" if s.is_corner() else "STAND"]
	if is_main:
		return "MAIN STAND"
	if s.is_corner():
		return "%s CORNER" % s.side
	match s.type_id:
		"family": return "FAMILY STAND"
		"terrace", "safe_standing": return "%s TERRACE" % SIDE_NAMES.get(s.side, "")
		"bank": return "%s BANK" % SIDE_NAMES.get(s.side, "")
	return "%s STAND" % SIDE_NAMES.get(s.side, "")


## The outside of a stand: a dark plinth, the facade's own surface (precast
## panels, brick, steel ribs or glazing), a club-coloured band, the stand's name,
## turnstile entrances with shutters, canopies and signs, and downpipes.
var _corner_rects: Array = []   # footprints of the corner stands (side stands open their ends onto them)
var _corner_tiers: Array[int] = []   # and how many tiers each has (higher tiers still get end walls)
var _wall_spot := []   # [frame, z, height] of the stand's outermost wall, for the name sign
var _name_labels: Array = []   # [Label3D, colour, lit] so night can light (or dim) them
var _glows: Array = []         # [material, day energy, night energy]: lit signs and the like
var _night_lights: Array = []  # lights that only come on at night


func _glow(m: BaseMaterial3D, day: float, night: float) -> void:
	m.emission_energy_multiplier = night if _night else day
	_glows.append([m, day, night])


func _night_light(l: Light3D) -> void:
	l.visible = _night
	_night_lights.append(l)


## The front of an upper tier, as seen from the pitch: a painted fascia (with
## optional lettering), an LED ribbon that runs adverts and club messages, or a
## glass balustrade.
func _tier_front(fr: Node3D, s: Stand, L: float, base: float, front_z: float, k: int) -> void:
	var tfo := s.extra("tier_front")
	var style := String(tfo["style"])
	var col := Color.html(String(tfo["color"])) if String(tfo["color"]) != "" and Color.html_is_valid(String(tfo["color"])) else _club.primary_color
	var text := String(tfo["text"])
	match style:
		"glass":
			lbox(fr, Vector3(0, base - 0.45, front_z + 0.03), Vector3(L, 0.25, 0.1), mat(col.darkened(0.3), 0.5))
			lbox(fr, Vector3(0, base + 0.05, front_z + 0.03), Vector3(L, 0.75, 0.04), mat(Color(0.75, 0.85, 0.9), 0.05, 0.3, 0.0, 0.35))
			lbox(fr, Vector3(0, base + 0.44, front_z + 0.03), Vector3(L, 0.05, 0.07), _steel())
		"led":
			lbox(fr, Vector3(0, base - 0.2, front_z + 0.02), Vector3(L, 0.8, 0.1), mat(Color(0.05, 0.05, 0.06), 0.4))
			var lm := StandardMaterial3D.new()
			lm.albedo_color = col
			lm.emission_enabled = true
			lm.emission = col
			lm.emission_energy_multiplier = 0.8
			var strip := lbox(fr, Vector3(0, base - 0.2, front_z + 0.075), Vector3(L - 0.1, 0.6, 0.01), lm)
			strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var lab := Label3D.new()
			lab.text = text.to_upper() if text != "" else _club.club_name.to_upper()
			lab.font_size = 64
			lab.pixel_size = 0.0075
			lab.outline_size = 0
			lab.position = Vector3(0, base - 0.2, front_z + 0.085)
			fr.add_child(lab)
			if text == "":
				_tier_leds.append([lm, weakref(lab), k * 7])   # runs with the pitch-side boards
		_:
			lbox(fr, Vector3(0, base - 0.2, front_z + 0.03), Vector3(L, 0.75, 0.08), mat(col, 0.5))
			if text != "":
				var sg := Signs.build(fr, { "text": text, "mount": "painted", "font": "future", "scale": 0.9 }, _club.secondary_color if col.is_equal_approx(_club.primary_color) else Color.WHITE, col, L * 0.9, _glow, _night_light)
				sg.position = Vector3(0, base - 0.2, front_z + 0.075)


## A second finish over the lower part of the wall (a glass skin under
## cladding, a brick base under render...), up to the height the player picks.
func _split_material(s: Stand) -> Material:
	var sp := s.extra("split")
	var c := Color.html(String(sp["color"])) if String(sp["color"]) != "" and Color.html_is_valid(String(sp["color"])) else Color(1, 1, 1)
	if String(sp["mat"]) == "glass" and String(sp["color"]) == "":
		c = Color(0.45, 0.65, 0.68)
	return finish_mat(String(sp["mat"]), c, 2.0)


func _split_skin(fr: Node3D, s: Stand, L: float, z: float, h: float) -> void:
	var frac := float(s.extra("split")["height"])
	if frac <= 0.01:
		return
	var sh := h * frac
	lbox(fr, Vector3(0, sh / 2.0, z - 0.12), Vector3(L + 0.02, sh, 0.06), _split_material(s))
	if String(s.extra("split")["mat"]) == "glass":
		var mull: Array[Transform3D] = []
		var x := -L / 2.0
		while x <= L / 2.0:
			mull.append(Transform3D(Basis().scaled(Vector3(0.04, sh, 0.08)), Vector3(x, sh / 2.0, z - 0.14)))
			x += 0.9
		mull.append(Transform3D(Basis().scaled(Vector3(L, 0.08, 0.1)), Vector3(0, sh, z - 0.14)))
		_mm(fr, mull, _steel())


## Windows over any facade: a long strip, a grid of floors, or tall slots;
## frames in the player's colour, warm and lit at night.
func _windows(fr: Node3D, s: Stand, L: float, z: float, h: float) -> void:
	var wo := s.extra("windows")
	var style := String(wo["style"])
	if style == "default" or h < 2.5:
		return
	var fcol := Color.html(String(wo["frame"])) if String(wo["frame"]) != "" and Color.html_is_valid(String(wo["frame"])) else Color(0.22, 0.23, 0.25)
	var frame_m := mat(fcol, 0.4, 0.6)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.16, 0.22, 0.27)
	glass.roughness = 0.08
	glass.metallic = 0.5
	if bool(wo["lit"]):
		glass.emission_enabled = true
		glass.emission = Color(1.0, 0.84, 0.58)
		_glow(glass, 0.0, 1.1)
	var zf := z - 0.1
	var panes: Array[Transform3D] = []
	var frames: Array[Transform3D] = []
	match style:
		"strip":
			var y := clampf(h * 0.55, 2.0, h - 1.0)
			panes.append(Transform3D(Basis().scaled(Vector3(L - 0.6, 0.9, 0.04)), Vector3(0, y, zf)))
			frames.append(Transform3D(Basis().scaled(Vector3(L - 0.5, 0.08, 0.08)), Vector3(0, y + 0.49, zf)))
			frames.append(Transform3D(Basis().scaled(Vector3(L - 0.5, 0.08, 0.08)), Vector3(0, y - 0.49, zf)))
			var x := -L / 2.0 + 0.3
			while x <= L / 2.0 - 0.3:
				frames.append(Transform3D(Basis().scaled(Vector3(0.05, 0.9, 0.07)), Vector3(x, y, zf)))
				x += 1.2
		"grid":
			var y := 1.8
			while y < h - 0.8:
				var x := -L / 2.0 + 0.9
				while x <= L / 2.0 - 0.9:
					panes.append(Transform3D(Basis().scaled(Vector3(0.8, 0.7, 0.04)), Vector3(x, y, zf)))
					frames.append(Transform3D(Basis().scaled(Vector3(0.95, 0.08, 0.07)), Vector3(x, y - 0.38, zf)))
					x += 1.5
				y += 2.0
		"tall":
			var x := -L / 2.0 + 1.0
			while x <= L / 2.0 - 1.0:
				panes.append(Transform3D(Basis().scaled(Vector3(0.45, h - 2.4, 0.04)), Vector3(x, (h - 2.4) / 2.0 + 1.4, zf)))
				frames.append(Transform3D(Basis().scaled(Vector3(0.6, 0.1, 0.08)), Vector3(x, h - 0.95, zf)))
				x += 2.0
	_mm(fr, panes, glass)
	_mm(fr, frames, frame_m)


## Little warning signs floating over pieces with a problem, SimCity style:
## transport with no road to the street, kiosks whose queues were too long.
func _problem_markers(layout: Layout, config: SimConfig, report: MatchdayReport) -> void:
	var notes := []   # [Vector3, text]
	var status := layout.transport_status(config)
	for f in layout.facilities:
		var ft := config.facility_type(f.type_id)
		if status.has(f) and not bool((status[f] as Dictionary).get("connected", true)):
			var sz := f.size(ft)
			notes.append([Vector3(f.pos.x + sz.x / 2.0, 2.6, f.pos.y + sz.y / 2.0), "NO ROAD"])
	if report != null and report.home:
		var by_label := {}
		for q in report.facilities:
			by_label[String(q.get("label", ""))] = q
		for f in layout.facilities:
			if by_label.has(f.label()):
				var q: Dictionary = by_label[f.label()]
				if int(q.get("lost", 0)) > 50:
					var sz2 := f.size(config.facility_type(f.type_id))
					notes.append([Vector3(f.pos.x + sz2.x / 2.0, level_height(layout, f.level) + 2.2, f.pos.y + sz2.y / 2.0), "QUEUES TOO LONG"])
	var seen := {}
	for n in notes:
		var key := "%d,%d|%s" % [roundi((n[0] as Vector3).x), roundi((n[0] as Vector3).z), n[1]]
		if seen.has(key):
			continue
		seen[key] = true
		var l := Label3D.new()
		l.text = "⚠ " + String(n[1])
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.fixed_size = true
		l.pixel_size = 0.0007
		l.font_size = 36
		l.outline_size = 10
		l.modulate = Color(1.0, 0.75, 0.2)
		l.no_depth_test = true
		l.position = n[0]
		_outside.add_child(l)






## Facade uplighting: a row of ground lamps along the back wall washing it in
## the player's colour at night (a few real lights, glowing lamp heads for the rest).
func _uplights(fr: Node3D, s: Stand, L: float, D: float, extra: float, top: float) -> void:
	var up := s.extra("uplight")
	if not bool(up["on"]):
		return
	var col := Color.html(String(up["color"])) if String(up["color"]) != "" and Color.html_is_valid(String(up["color"])) else _club.primary_color.lightened(0.2)
	var spacing := clampf(float(up["spacing"]), 2.0, 12.0)
	var z := -D / 2.0 - extra - 0.45
	var lamp_m := StandardMaterial3D.new()
	lamp_m.albedo_color = Color(0.2, 0.2, 0.22)
	lamp_m.emission_enabled = true
	lamp_m.emission = col
	_glow(lamp_m, 0.0, 4.0)
	var heads: Array[Transform3D] = []
	var n := maxi(1, int(L / spacing))
	var real_every := maxi(1, n / 6)   # keep the light count sane on long stands
	for k in n:
		var x := -L / 2.0 + (k + 0.5) * L / n
		heads.append(Transform3D(Basis().scaled(Vector3(0.3, 0.12, 0.2)), Vector3(x, 0.06, z)))
		if k % real_every == 0:
			var sp := SpotLight3D.new()
			sp.light_color = col
			sp.light_energy = 5.0
			sp.spot_range = top + 3.0
			sp.spot_angle = clampf(rad_to_deg(atan2(spacing * real_every * 0.6, 1.2)), 25.0, 75.0)
			sp.position = Vector3(x, 0.2, z - 0.6)
			sp.shadow_enabled = false
			fr.add_child(sp)
			sp.look_at(fr.to_global(Vector3(x, top * 0.7, z + 0.4)), Vector3.FORWARD)
			_night_light(sp)
	_mm(fr, heads, lamp_m)


## The "open tiers" back (San Siro, Italian bowls): no curtain wall; the
## tiers' undersides show as a deep shadowed recess crossed by the raking
## beams, with a heavy concrete ring band at each level.
func _stacked_back(fr: Node3D, s: Stand, L: float, z: float, h: float) -> void:
	var conc := _part("wall", tex_mat("rough_concrete", Color(0.86, 0.83, 0.76), 2.0, true), Color(0.86, 0.83, 0.76))
	var shade := mat(Color(0.2, 0.2, 0.2), 0.95)
	# the recess, a little behind the face
	lbox(fr, Vector3(0, h / 2.0, z + 0.9), Vector3(L, h, 0.1), shade)
	# ring bands: at the deck of every tier, at the top, and one between
	var levels: Array[float] = [1.2]
	for k in range(1, s.tiers):
		levels.append(tier_base(s, k) - 0.2)
	for k in s.tiers:
		levels.append(tier_base(s, k) + row_height(s.depth / 2, s))
	levels.append(h - 0.35)
	var lm := _part("band", conc, Color(0.86, 0.83, 0.76))
	for y in levels:
		if y < h:
			lbox(fr, Vector3(0, y, z + 0.2), Vector3(L, 0.55, 0.5), lm)
			lbox(fr, Vector3(0, y - 0.32, z + 0.35), Vector3(L, 0.08, 0.6), shade)
	# raking beams: close-set ribs sloping back under each tier
	var ribs: Array[Transform3D] = []
	var x := -L / 2.0 + 0.3
	var lean := Basis(Vector3.RIGHT, -0.28)
	while x < L / 2.0:
		ribs.append(Transform3D(lean.scaled(Vector3(0.14, h - 0.6, 0.35)), Vector3(x, h / 2.0, z + 0.55)))
		x += 0.75
	_mm(fr, ribs, conc)
	# a plinth of entrances along the bottom
	lbox(fr, Vector3(0, 0.45, z + 0.12), Vector3(L, 0.9, 0.24), conc)


func _facade_detail(fr: Node3D, s: Stand, L: float, z: float, h: float, is_main := false) -> void:
	if String(_paint.get("wall_mat", "")) == "etfe":
		return   # the cushions are the whole facade: no plinth, fins or bands over them
	var out := z - 0.08
	var pil := facade_mat(s, true)
	var joint := mat(Color(0.32, 0.32, 0.31), 0.9)
	var plinth_m := tex_mat("concrete_tile_facade", Color(1.5, 1.5, 1.5), 2.0)
	var glazing := mat(Color(0.16, 0.2, 0.24), 0.12, 0.5)
	var frame_m := mat(Color(0.24, 0.25, 0.27), 0.4, 0.7)
	var club_c := _club.primary_color
	var band_c := _pc("band")
	if band_c.r >= 0.0:
		club_c = band_c
	# plinth: a heavier base course along the bottom
	lbox(fr, Vector3(0, 0.6, out - 0.02), Vector3(L + 0.04, 1.2, 0.14), plinth_m)
	lbox(fr, Vector3(0, 1.22, out - 0.05), Vector3(L + 0.06, 0.06, 0.2), joint)
	match s.facade:
		"heritage":
			# an Archibald Leitch style frontage: red brick, a run of arched windows
			# with pale stone surrounds, pilasters, a cornice and a central pediment
			var stone := tex_mat("rough_concrete", Color(0.92, 0.88, 0.8), 1.0, true)
			var glass := mat(Color(0.16, 0.2, 0.24), 0.12, 0.5)
			var bays := maxi(3, int(L / 1.6))
			var bw := L / bays
			var wy := clampf(h * 0.55, 1.8, h - 0.9)
			for k in bays:
				var x := -L / 2.0 + (k + 0.5) * bw
				# pilaster between the bays
				lbox(fr, Vector3(x - bw / 2.0, (h + 1.2) / 2.0, out - 0.04), Vector3(0.16, h - 1.2, 0.12), stone)
				# the arched window: a tall pane with a half-round head
				var ww := bw * 0.5
				var wh := minf(1.4, h - 2.2)
				lbox(fr, Vector3(x, wy, out - 0.03), Vector3(ww, wh, 0.04), glass)
				lbox(fr, Vector3(x, wy - wh / 2.0 - 0.06, out - 0.06), Vector3(ww + 0.2, 0.08, 0.14), stone)
				var arch := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = ww / 2.0 + 0.06
				cyl.bottom_radius = ww / 2.0 + 0.06
				cyl.height = 0.08
				cyl.radial_segments = 14
				arch.mesh = cyl
				arch.material_override = stone
				arch.rotation.x = PI / 2.0
				arch.position = Vector3(x, wy + wh / 2.0, out - 0.07)
				fr.add_child(arch)
				var pane := MeshInstance3D.new()
				var pc := CylinderMesh.new()
				pc.top_radius = ww / 2.0
				pc.bottom_radius = ww / 2.0
				pc.height = 0.09
				pc.radial_segments = 14
				pane.mesh = pc
				pane.material_override = glass
				pane.rotation.x = PI / 2.0
				pane.position = Vector3(x, wy + wh / 2.0, out - 0.075)
				fr.add_child(pane)
			# cornice and a pediment over the middle
			lbox(fr, Vector3(0, h - 0.2, out - 0.08), Vector3(L + 0.1, 0.18, 0.24), stone)
			var pw := minf(L * 0.35, 8.0)
			for e in [-1.0, 1.0]:
				var rake := lbox(fr, Vector3(e * pw / 4.0, h + pw * 0.08, out - 0.08), Vector3(pw / 2.0 + 0.1, 0.16, 0.24), stone, 0.0)
				rake.rotation.z = e * -0.32
			lbox(fr, Vector3(0, h + 0.05, out - 0.05), Vector3(pw * 0.8, pw * 0.12, 0.08), tex_mat("red_brick_03", Color.WHITE, 1.0))
		"glass":
			for k in range(0, int(L) + 1, 2):
				var x := -L / 2.0 + float(k)
				lbox(fr, Vector3(x, (h + 1.2) / 2.0, out), Vector3(0.06, h - 1.2, 0.06), frame_m)
			for y in range(2, int(h)):
				lbox(fr, Vector3(0, float(y), out), Vector3(L, 0.04, 0.05), frame_m)
		"steel":
			for k in range(0, int(L * 4)):
				lbox(fr, Vector3(-L / 2.0 + 0.125 + k * 0.25, (h + 1.2) / 2.0, out + 0.02), Vector3(0.04, h - 1.2, 0.04), mat(Color(0.6, 0.62, 0.66), 0.35, 0.8))
		"fins":
			# close-set bronze louvres, each turned a little, over a dark wall
			var xf: Array[Transform3D] = []
			var k := 0.25
			while k < L:
				xf.append(Transform3D(Basis(Vector3.UP, 0.4).scaled(Vector3(0.07, h - 1.3, 0.55)), Vector3(-L / 2.0 + k, (h + 1.3) / 2.0, out - 0.3)))
				k += 0.5
			_mm(fr, xf, pil)
		"panels":
			# metal cladding panels: joints across and up, a little sheen
			var y := 1.9
			while y < h - 0.3:
				lbox(fr, Vector3(0, y, out - 0.01), Vector3(L, 0.04, 0.04), pil)
				y += 0.8
			var k := 0.0
			while k <= L + 0.01:
				lbox(fr, Vector3(-L / 2.0 + k, (h + 1.2) / 2.0, out - 0.01), Vector3(0.04, h - 1.2, 0.04), pil)
				k += 2.0
		"arcade":
			# a colonnade in front of the wall, a cornice, windows above
			var cy := minf(h * 0.6, 4.2)
			var k := 0.0
			while k <= L + 0.01:
				lbox(fr, Vector3(-L / 2.0 + k, cy / 2.0, out - 0.45), Vector3(0.32, cy, 0.32), pil)
				k += 1.8
			lbox(fr, Vector3(0, cy + 0.12, out - 0.4), Vector3(L + 0.2, 0.25, 0.75), pil)
			_window_band(fr, L, h, out, mat(Color(0.16, 0.2, 0.24), 0.12, 0.5), mat(Color(0.24, 0.25, 0.27), 0.4, 0.7), 1.8)
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
			# modern precast: a glazed concourse band over the plinth, then deep
			# vertical fins over a dark recessed skin (strong shadow rhythm), a
			# club-coloured spandrel between, and stair towers at the ends
			var gl_top := minf(2.6, h - 0.6)
			if gl_top > 1.5:
				lbox(fr, Vector3(0, (1.25 + gl_top) / 2.0, out + 0.02), Vector3(L, gl_top - 1.25, 0.04), mat(Color(0.2, 0.27, 0.33), 0.06, 0.55))
				var mul: Array[Transform3D] = []
				var k := 0.0
				while k <= L + 0.01:
					mul.append(Transform3D(Basis().scaled(Vector3(0.05, gl_top - 1.25, 0.08)), Vector3(-L / 2.0 + k, (1.25 + gl_top) / 2.0, out)))
					k += 0.75
				mul.append(Transform3D(Basis().scaled(Vector3(L, 0.05, 0.08)), Vector3(0, 1.25 + (gl_top - 1.25) * 0.62, out)))
				_mm(fr, mul, frame_m)
				lbox(fr, Vector3(0, gl_top + 0.12, out - 0.04), Vector3(L + 0.04, 0.24, 0.16), mat(club_c, 0.5))
			if h - gl_top > 1.0:
				var y0 := gl_top + 0.24
				lbox(fr, Vector3(0, (y0 + h) / 2.0, out + 0.03), Vector3(L, h - y0, 0.04), mat(Color(0.27, 0.28, 0.3), 0.7))
				var fins: Array[Transform3D] = []
				var k := 0.0
				while k <= L + 0.01:
					fins.append(Transform3D(Basis().scaled(Vector3(0.22, h - y0 - 0.1, 0.3)), Vector3(-L / 2.0 + k, (y0 + h - 0.1) / 2.0, out - 0.12)))
					k += 0.75
				_mm(fr, fins, facade_mat(s))
			if h > 4.0:
				for e in ([-1.0, 1.0] if L < 30.0 else [-1.0, 0.0, 1.0]):
					_stair_tower(fr, e * (L / 2.0 - 1.0), out, h, club_c)
	# club-coloured band and coping
	if h > 2.2:
		lbox(fr, Vector3(0, h - 0.42, out - 0.03), Vector3(L + 0.02, 0.24, 0.06), _part("band", mat(club_c, 0.55), club_c, 1.0))
	lbox(fr, Vector3(0, h - 0.06, out - 0.03), Vector3(L + 0.12, 0.14, 0.24), mat(club_c.darkened(0.25), 0.5))
	_wall_spot = [fr, out, h]
	if s.facade == "painted":
		# broad bands of the second club colour painted across the concrete
		var bm := tex_mat("rough_concrete", _club.secondary_color, 3.0, true)
		var y := 1.6
		while y < h - 0.8:
			lbox(fr, Vector3(0, y, out - 0.02), Vector3(L + 0.02, 0.55, 0.05), bm)
			y += 1.4
	# turnstile entrances: a gatehouse stands out from the wall with an open
	# archway into the stand: gates swung back, turnstile booths and queue rails
	var places := s.capacity(_config.stand_type(s.type_id)) if _config else 0
	var n_ent := clampi(s.gate_count(7, 1400, places), 1, maxi(1, int(L / 2.6)))
	var ent := s.extra("entrances")
	var ent_style := String(ent["style"])
	if String(ent["color"]) != "" and Color.html_is_valid(String(ent["color"])):
		club_c = Color.html(String(ent["color"]))
	_gate_word = String(ent["text"]).to_upper() if String(ent["text"]) != "" else "TURNSTILES"
	for e in n_ent:
		var cx := -L / 2.0 + (e + 0.5) * L / n_ent
		if ent_style == "doors" or (ent_style == "auto" and h < 3.4):
			# a small stand: plain turnstile doors set into the wall
			lbox(fr, Vector3(cx, 0.55, out - 0.02), Vector3(0.9, 1.1, 0.05), mat(Color(0.12, 0.13, 0.14), 0.6))
			lbox(fr, Vector3(cx, 1.18, out - 0.04), Vector3(1.0, 0.16, 0.05), mat(club_c, 0.5))
			lbox(fr, Vector3(cx, 0.5, out - 0.06), Vector3(0.04, 1.0, 0.04), frame_m)
		else:
			_gatehouse(fr, cx, out, e, plinth_m, frame_m, club_c)
	# downpipes between the entrances
	for e in n_ent + 1:
		var cx := -L / 2.0 + e * L / n_ent
		cx = clampf(cx, -L / 2.0 + 0.2, L / 2.0 - 0.2)
		lbox(fr, Vector3(cx, h / 2.0, out - 0.12), Vector3(0.06, h, 0.06), mat(Color(0.2, 0.21, 0.22), 0.5, 0.4))


## The modern facade wrapped round a rounded corner: plinth, glazed band,
## club stripe, and fins on radial lines over a dark skin.
## The open-tier look (see _stacked_back) carried round a rounded corner.
func _curved_stacked(root: Node3D, s: Stand, cf: Dictionary, R: float, h: float) -> void:
	var conc := _part("wall", tex_mat("rough_concrete", Color(0.86, 0.83, 0.76), 2.0, true), Color(0.86, 0.83, 0.76))
	var lm := _part("band", conc, Color(0.86, 0.83, 0.76))
	var shade := mat(Color(0.2, 0.2, 0.2), 0.95)
	sector(root, cf, R - 1.0, R - 0.9, 0.0, h, shade, 24)
	var levels: Array[float] = [1.2]
	for k in range(1, s.tiers):
		levels.append(tier_base(s, k) - 0.2)
	for k in s.tiers:
		levels.append(tier_base(s, k) + row_height(s.depth / 2, s))
	levels.append(h - 0.35)
	for y in levels:
		if y < h:
			sector(root, cf, R - 0.45, R + 0.05, y - 0.27, y + 0.28, lm, 24)
			sector(root, cf, R - 0.6, R - 0.05, y - 0.36, y - 0.28, shade, 24)
	sector(root, cf, R - 0.24, R, 0.0, 0.9, conc, 24)
	# raking ribs round the curve
	var c: Vector2 = cf["centre"]
	var n := int(PI / 2.0 * R / 0.75)
	var ribs: Array[Transform3D] = []
	for i in range(1, n):
		var phi := PI / 2.0 * i / n
		var se := _se(phi)
		var dir := Vector2(float(cf["sx"]) * se.x, float(cf["sz"]) * se.y)
		var p := c + dir * (R - 0.45)
		var yaw := atan2(dir.x, dir.y)
		ribs.append(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.28).scaled(Vector3(0.14, h - 0.6, 0.35)), Vector3(p.x, h / 2.0, p.y)))
	_mm(root, ribs, conc)


func _curved_facade(root: Node3D, cf: Dictionary, R: float, h: float) -> void:
	sector(root, cf, R, R + 0.12, 0.0, 1.2, tex_mat("concrete_tile_facade", Color(1.5, 1.5, 1.5), 2.0), 24)
	sector(root, cf, R + 0.02, R + 0.06, 1.25, 2.6, mat(Color(0.2, 0.27, 0.33), 0.06, 0.55), 24)
	sector(root, cf, R, R + 0.16, 2.6, 2.84, mat(_club.primary_color, 0.5), 24)
	if h > 3.2:
		sector(root, cf, R - 0.02, R + 0.03, 2.84, h, mat(Color(0.27, 0.28, 0.3), 0.7), 24)
	var c: Vector2 = cf["centre"]
	var sx: float = cf["sx"]
	var sz: float = cf["sz"]
	var arc := PI / 2.0 * R
	var n := int(arc / 0.75)
	var fins: Array[Transform3D] = []
	var muls: Array[Transform3D] = []
	for i in range(1, n):
		var phi := PI / 2.0 * i / n
		var se := _se(phi)
		var dir := Vector2(sx * se.x, sz * se.y)
		var yaw := atan2(dir.x, dir.y)
		var p := c + dir * (R + 0.15)
		if h > 3.2:
			fins.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(0.22, h - 2.94, 0.3)), Vector3(p.x, (2.84 + h) / 2.0, p.y)))
		var q := c + dir * (R + 0.07)
		muls.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(0.05, 1.35, 0.06)), Vector3(q.x, 1.92, q.y)))
	_mm(root, fins, tex_mat("rough_concrete", Color(0.74, 0.74, 0.72), 3.0, true))
	_mm(root, muls, mat(Color(0.24, 0.25, 0.27), 0.4, 0.7))


## A stair tower standing out from a stand's back wall: a solid shaft with a
## full-height glazed slot showing the zig-zag flights, and a capping band.
func _stair_tower(fr: Node3D, cx: float, out: float, h: float, club_c: Color) -> void:
	var w := 1.6
	var d := 1.5
	var z := out - d / 2.0 - 0.02
	var shaft := tex_mat("rough_concrete", Color(0.66, 0.66, 0.65), 2.0, true)
	lbox(fr, Vector3(cx, (h + 0.5) / 2.0, z), Vector3(w, h + 0.5, d), shaft)
	lbox(fr, Vector3(cx, (h + 0.5) / 2.0 + 0.3, out - d - 0.02), Vector3(0.7, h - 0.6, 0.04), mat(Color(0.18, 0.24, 0.3), 0.06, 0.5))
	# flights behind the glass
	var n := int(h / 0.7)
	for i in n:
		var f := lbox(fr, Vector3(cx, 0.6 + i * 0.7, out - d + 0.12), Vector3(0.62, 0.06, 0.16), mat(Color(0.75, 0.75, 0.72), 0.8), 0.0)
		f.rotation.z = 0.5 * (1.0 if i % 2 == 0 else -1.0)
	lbox(fr, Vector3(cx, h + 0.5, z), Vector3(w + 0.1, 0.16, d + 0.1), mat(club_c.darkened(0.2), 0.5))
	lbox(fr, Vector3(cx, 1.0, out - d - 0.03), Vector3(0.6, 2.0, 0.04), mat(Color(0.1, 0.1, 0.11), 0.6))


## One turnstile entrance on a stand's back wall (local -Z is outside).
var _gate_word := "TURNSTILES"


func _gatehouse(fr: Node3D, cx: float, out: float, idx: int, plinth_m: Material, frame_m: Material, club_c: Color) -> void:
	var w := 2.2          # opening width
	var h := 2.1          # opening height
	var d := 1.4          # how far the gatehouse stands out from the wall
	var z0 := out - 0.02
	var zf := out - d
	var pier := tex_mat("rough_concrete", Color(0.62, 0.62, 0.61), 2.0, true)
	# the passage: dark walls and a lit far end, so the archway reads as an opening
	lbox(fr, Vector3(cx, h / 2.0, z0 + 0.01), Vector3(w, h, 0.02), mat(Color(0.03, 0.03, 0.035), 0.9))
	var glow := lbox(fr, Vector3(cx, h * 0.45, z0 - 0.0), Vector3(w * 0.45, h * 0.7, 0.01), mat(Color(0.9, 0.75, 0.5), 0.8, 0.0, 0.35))
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# piers, a deep lintel with the sign, a canopy roof and a paved floor
	for side in [-1, 1]:
		lbox(fr, Vector3(cx + side * (w / 2.0 + 0.2), (h + 0.6) / 2.0, (z0 + zf) / 2.0), Vector3(0.4, h + 0.6, d), pier)
	lbox(fr, Vector3(cx, h + 0.3, (z0 + zf) / 2.0), Vector3(w + 0.8, 0.6, d), pier)
	lbox(fr, Vector3(cx, h + 0.65, (z0 + zf) / 2.0 - 0.15), Vector3(w + 1.2, 0.1, d + 0.5), mat(club_c.darkened(0.35), 0.5))
	lbox(fr, Vector3(cx, h + 0.3, zf - 0.01), Vector3(w + 0.3, 0.42, 0.02), mat(club_c, 0.4, 0.0, 0.5))
	_lettering(fr, "%s %s" % [_gate_word, char(65 + idx)], Vector3(cx, h + 0.3, zf - 0.03), Color(1, 1, 1), 0.006, 40, PI, "inside")
	lbox(fr, Vector3(cx, 0.02, (z0 + zf) / 2.0 - 0.4), Vector3(w + 1.2, 0.04, d + 0.8), plinth_m)
	var lamp := lbox(fr, Vector3(cx, h - 0.02, (z0 + zf) / 2.0), Vector3(0.8, 0.04, 0.2), mat(Color(1.0, 0.95, 0.85), 0.3, 0.0, 2.0))
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# turnstile booths across the passage: steel cabinets with three-arm rotors
	var steel := mat(Color(0.7, 0.72, 0.75), 0.3, 0.8)
	var nb := 3
	for k in nb + 1:
		var bx := cx - w / 2.0 + 0.12 + k * (w - 0.24) / nb
		lbox(fr, Vector3(bx, 0.5, z0 - 0.55), Vector3(0.18, 1.0, 0.5), steel)
		if k < nb:
			var ax := bx + 0.15
			for arm in 3:
				var bar := lbox(fr, Vector3(ax, 0.85, z0 - 0.55), Vector3(0.3, 0.03, 0.03), steel)
				bar.rotation = Vector3(arm * TAU / 3.0, 0, 0.35)
	# the gates themselves: two barred leaves swung back against the piers
	var bars := mat(Color(0.12, 0.12, 0.13), 0.5, 0.7)
	for side in [-1, 1]:
		var leaf := Node3D.new()
		leaf.position = Vector3(cx + side * w / 2.0, 0, zf + 0.05)
		leaf.rotation.y = side * -1.25
		fr.add_child(leaf)
		var lw := w / 2.0
		lbox(leaf, Vector3(-side * lw / 2.0, h - 0.1, 0), Vector3(lw, 0.06, 0.04), bars)
		lbox(leaf, Vector3(-side * lw / 2.0, 0.1, 0), Vector3(lw, 0.06, 0.04), bars)
		for b in 7:
			lbox(leaf, Vector3(-side * (0.05 + b * lw / 7.0), h / 2.0, 0), Vector3(0.03, h - 0.1, 0.03), bars)
	# queue rails out front
	var rail := mat(Color(0.8, 0.8, 0.82), 0.3, 0.8)
	for side in [-1, 0, 1]:
		var rx: float = cx + side * (w / 3.0)
		lbox(fr, Vector3(rx, 0.5, zf - 0.8), Vector3(0.04, 0.04, 1.4), rail)
		lbox(fr, Vector3(rx, 0.25, zf - 1.45), Vector3(0.04, 0.5, 0.04), rail)


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
## Vomitories (tunnels up into the seating) on the lower tier: their centres
## along the stand, half way between aisles; none on shallow stands.
static func vom_centres(s: Stand, L: float) -> Array[float]:
	var out: Array[float] = []
	if s.is_corner() or s.depth < 8:
		return out
	var want := int(s.extra("detail").get("voms", -1))
	if want == 0:
		return out
	var n := aisle_count(s, L)
	var gaps: Array[float] = []
	if n >= 2:
		for g in n - 1:
			gaps.append((g + 1.0) * L / n)
	else:
		gaps = [L * 0.25, L * 0.75]
	if want < 0:
		return gaps
	var step := maxf(1.0, float(gaps.size()) / want)
	var i := 0.0
	while int(i) < gaps.size() and out.size() < want:
		out.append(gaps[int(i)])
		i += step
	return out


## The rows a vomitory cuts through: [first, last] on the lower tier.
static func vom_rows(s: Stand) -> Vector2i:
	var v0 := s.depth / 2 - 1
	return Vector2i(v0, v0 + 1)


static func aisle_count(s: Stand, L: float) -> int:
	var a := int(s.extra("detail")["aisles"])
	return a if a >= 0 else maxi(1, int(L / 7.0))


func _dc(s: Stand, key: String, default: Color) -> Color:
	var v := String(s.extra("detail")[key])
	return Color.html(v) if v != "" and Color.html_is_valid(v) else default


func _gangways(fr: Node3D, s: Stand, L: float, D: float) -> void:
	_vomitories(fr, s, L, D)
	var n := aisle_count(s, L)
	var step_m := mat(_dc(s, "steps", Color(0.86, 0.86, 0.84)), 0.8)
	var rail := mat(_dc(s, "rail", Color(0.42, 0.44, 0.47)), 0.35, 0.8)
	var nosing := mat(_dc(s, "nosing", Color(0.95, 0.78, 0.12)), 0.6)
	for g in n:
		var x := -L / 2.0 + (g + 0.5) * L / n
		for v in s.depth:
			var zf := D / 2.0 - v
			var y := row_height(v, s)
			# two steps per row, a lighter colour so the aisle reads
			lbox(fr, Vector3(x, y - _rise(s) * 0.5 + 0.01, zf - 0.25), Vector3(0.42, 0.04, 0.5), step_m)
			lbox(fr, Vector3(x, y + 0.01, zf - 0.75), Vector3(0.42, 0.04, 0.5), step_m)
			# yellow safety nosing on each step edge
			lbox(fr, Vector3(x, y - _rise(s) * 0.5 + 0.035, zf - 0.02), Vector3(0.42, 0.02, 0.05), nosing)
			lbox(fr, Vector3(x, y + 0.035, zf - 0.52), Vector3(0.42, 0.02, 0.05), nosing)
		for e in [-1, 1]:
			var h0 := row_height(0, s) + 0.35
			var h1 := row_height(s.depth - 1, s) + 0.35
			var len := sqrt(float(s.depth * s.depth) + (h1 - h0) * (h1 - h0))
			lbox(fr, Vector3(x + e * 0.24, (h0 + h1) / 2.0, D / 2.0 - s.depth / 2.0), Vector3(0.018, 0.018, len), rail, atan2(h1 - h0, float(s.depth)))


## Vomitory mouths: a dark tunnel opening cut into the rake, low side walls,
## and a rail across the top so nobody falls in.
func _vomitories(fr: Node3D, s: Stand, L: float, D: float) -> void:
	var vcs := vom_centres(s, L)
	if vcs.is_empty():
		return
	var vr := vom_rows(s)
	var dark := mat(Color(0.05, 0.05, 0.06), 0.95)
	var wall := mat(_dc(s, "steps", Color(0.7, 0.7, 0.68)), 0.85)
	var rail := mat(_dc(s, "rail", Color(0.42, 0.44, 0.47)), 0.35, 0.8)
	var y_lo := row_height(maxi(0, vr.x - 1), s) + 0.02
	var y_hi := row_height(vr.y, s)
	var z_front := D / 2.0 - vr.x
	var z_back := D / 2.0 - vr.y - 1.0
	for vc in vcs:
		var x := -L / 2.0 + vc
		# the tunnel: a dark block filling the cut, its face at the front row of the cut
		lbox(fr, Vector3(x, (y_lo + y_hi) / 2.0 + 0.05, (z_front + z_back) / 2.0), Vector3(1.2, y_hi - y_lo + 0.1, z_front - z_back), dark)
		# a lintel over the mouth and side walls up to the seat level
		for e in [-1.0, 1.0]:
			lbox(fr, Vector3(x + e * 0.66, (y_lo + y_hi) / 2.0 + 0.12, (z_front + z_back) / 2.0), Vector3(0.12, y_hi - y_lo + 0.25, z_front - z_back), wall)
		lbox(fr, Vector3(x, y_hi + 0.12, z_back + 0.06), Vector3(1.44, 0.22, 0.12), wall)
		# a handrail round the top of the opening
		lbox(fr, Vector3(x, y_hi + 0.55, z_back + 0.06), Vector3(1.44, 0.03, 0.03), rail)
		for e in [-1.0, 1.0]:
			lbox(fr, Vector3(x + e * 0.66, y_hi + 0.55, (z_front + z_back) / 2.0), Vector3(0.03, 0.03, z_front - z_back), rail)


## Modern roof on columns at the back, pitched gently backwards so rain runs
## away from the pitch, with a club-coloured fascia. Returns fascia height.
func _roof_cantilever(roof: Node3D, L: float, D: float, top: float, length: int, skin: Material = null) -> float:
	var front_y := top + ROOF_CLEARANCE + _roof_tilt() * 0.6
	var back_y := top + ROOF_CLEARANCE - _roof_tilt() * 0.4
	var z0 := -D / 2.0
	var z1 := _roof_front(D)
	var run := z1 - z0
	var tilt := -atan2(front_y - back_y, run)
	var sheet_m: Material = skin if skin else _sheet(Color(0.6, 0.62, 0.65))
	var slen := sqrt(run * run + 0.36)
	if String(_rs.get("ends", "open")) == "cranked" and L > 8.0:
		# the roof folds down over each end of the stand, like a hipped lid,
		# and the cladding drops to meet the end walls
		var c := minf(4.0, L * 0.18)
		var drop := minf(2.4, (front_y + back_y) / 2.0 * 0.25)
		lbox(roof, Vector3(0, (front_y + back_y) / 2.0 + 0.07, (z0 + z1) / 2.0), Vector3(L - 2.0 * c, 0.14, slen), sheet_m, tilt)
		var ang := atan2(drop, c)
		for e in [-1.0, 1.0]:
			var piece := lbox(roof, Vector3(e * (L / 2.0 - c / 2.0), (front_y + back_y) / 2.0 + 0.07 - drop / 2.0, (z0 + z1) / 2.0), Vector3(sqrt(c * c + drop * drop), 0.14, slen), sheet_m)
			piece.basis = Basis(Vector3.FORWARD, e * ang) * Basis(Vector3.RIGHT, tilt)
			# cladding filling under the fold down to the stand's end wall
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var xe: float = e * (L / 2.0 - 0.02)
			var ym := (front_y + back_y) / 2.0 - drop
			var pts: Array[Vector3] = [Vector3(xe, top, z0), Vector3(xe, back_y - drop, z0), Vector3(xe, front_y - drop, z1), Vector3(xe, top * 0.5, z1)]
			for tri in [[0, 1, 2], [0, 2, 3], [0, 2, 1], [0, 3, 2]]:
				for k in tri:
					st.set_normal(Vector3(e, 0, 0))
					st.set_uv(Vector2(pts[k].z, pts[k].y) * 0.5)
					st.add_vertex(pts[k])
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = sheet_m
			roof.add_child(mi)
	elif _roof_cfg("clear_strip", 0.0) > 0.01:
		# a translucent strip along the leading edge lets light onto the front rows
		var f := clampf(_roof_cfg("clear_strip", 0.0), 0.0, 0.6)
		var tm := (1.0 - f) / 2.0
		lbox(roof, Vector3(0, back_y + (front_y - back_y) * tm + 0.07, z0 + run * tm), Vector3(L, 0.14, slen * (1.0 - f)), sheet_m, tilt)
		var tc := 1.0 - f / 2.0
		var clear := mat(Color(0.85, 0.92, 0.98), 0.1, 0.1, 0.0, 0.38)
		lbox(roof, Vector3(0, back_y + (front_y - back_y) * tc + 0.07, z0 + run * tc), Vector3(L, 0.06, slen * f), clear, tilt)
		# glazing bars across the strip
		var bars: Array[Transform3D] = []
		var bx := -L / 2.0
		while bx <= L / 2.0:
			bars.append(Transform3D(Basis(Vector3.RIGHT, tilt).scaled(Vector3(0.05, 0.08, slen * f)), Vector3(bx, back_y + (front_y - back_y) * tc + 0.1, z0 + run * tc)))
			bx += 1.2
		_mm(roof, bars, _steel())
	else:
		lbox(roof, Vector3(0, (front_y + back_y) / 2.0 + 0.07, (z0 + z1) / 2.0), Vector3(L, 0.14, slen), sheet_m, tilt)
	var fh := _roof_cfg("fascia_h", 0.55)
	if fh > 0.01:
		var edge := String(_rs.get("edge", "straight"))
		if edge == "straight":
			lbox(roof, Vector3(0, front_y - fh * 0.15, z1 - 0.06), Vector3(L, fh, 0.12), _fascia())
		else:
			# a shaped edge: the fascia rises and falls along the stand
			var segs := maxi(8, int(L * 2.0))
			var fx: Array[Transform3D] = []
			for k in segs:
				var u := (k + 0.5) / segs
				var x := (u - 0.5) * L
				var bump := 0.0
				match edge:
					"wave": bump = 0.5 + 0.5 * sin(u * TAU * maxf(1.0, roundf(L / 14.0)))
					"arch": bump = sin(u * PI)
					"sawtooth": bump = fposmod(u * maxf(2.0, roundf(L / 6.0)), 1.0)
				var hh := fh * (1.0 + 1.6 * bump)
				fx.append(Transform3D(Basis().scaled(Vector3(L / segs + 0.01, hh, 0.12)), Vector3(x, front_y - fh * 0.15 + (hh - fh) / 2.0, z1 - 0.06)))
			_mm(roof, fx, _fascia())
	# gutter along the back
	lbox(roof, Vector3(0, back_y, z0 - 0.05), Vector3(L, 0.12, 0.16), mat(Color(0.3, 0.32, 0.35), 0.5, 0.6))
	# steel rafters under the sheeting, every 2.5 tiles, and a purlin along the front
	var steel := _steel()
	var nr := maxi(2, int(L / 2.5) + 1)
	for k in nr:
		var x := (float(k) / float(nr - 1) - 0.5) * (L - 0.3)
		lbox(roof, Vector3(x, (front_y + back_y) / 2.0 - 0.12, (z0 + z1) / 2.0), Vector3(0.09, 0.22, sqrt(run * run + 0.36)), steel, tilt)
	lbox(roof, Vector3(0, front_y - 0.4, z1 - 0.3), Vector3(L, 0.08, 0.08), steel)
	_roof_underside(roof, L, z0, z1, back_y, front_y, tilt, skin == null)
	_columns(roof, L, z0 + 0.07, back_y, length)
	if _roof_reach() > 0.95:
		# a long cantilever: deep tapered girders under the roof, tied back by
		# stays from tall back masts (no columns in anyone's view)
		var ng := maxi(2, ceili(length / 5.0) + 1)
		for k in ng:
			var x := (float(k) / float(ng - 1) - 0.5) * (L - 0.4)
			var gd := 0.15 + 0.35 * (_roof_reach() - 0.9)
			lbox(roof, Vector3(x, (front_y + back_y) / 2.0 - 0.1 - gd / 2.0, (z0 + z1) / 2.0), Vector3(0.14, gd, sqrt(run * run + 0.36)), _steel(), tilt)
			var mast_top := back_y + 1.6
			lbox(roof, Vector3(x, back_y + 0.8, z0 + 0.07), Vector3(0.14, 1.6, 0.14), _steel())
			var stay_len := Vector2(z1 - 0.4 - z0, front_y - mast_top).length()
			var stay := lbox(roof, Vector3(x, (mast_top + front_y) / 2.0, (z0 + z1 - 0.4) / 2.0), Vector3(0.03, 0.03, stay_len), _steel(), -atan2(front_y - mast_top, z1 - 0.4 - z0))
			stay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return front_y - 0.08


## Under a roof: a pale lining with purlins across it, a row of lamps and
## PA horns along the front, and CCTV cameras at the ends.
func _roof_underside(roof: Node3D, L: float, z0: float, z1: float, back_y: float, front_y: float, tilt: float, lined: bool) -> void:
	var run := z1 - z0
	var mid_y := (front_y + back_y) / 2.0
	if lined:
		lbox(roof, Vector3(0, mid_y - 0.26, (z0 + z1) / 2.0), Vector3(L - 0.1, 0.02, sqrt(run * run + 0.36) - 0.1), mat(Color(0.72, 0.73, 0.74), 0.7), tilt)
	var steel := _steel(0.1)
	var xf: Array[Transform3D] = []
	var k := 0.6
	while k < run - 0.3:
		var zz := z0 + k
		var yy := back_y + (front_y - back_y) * (k / run) - 0.3
		xf.append(Transform3D(Basis().scaled(Vector3(L - 0.2, 0.06, 0.05)), Vector3(0, yy, zz)))
		k += 1.1
	_mm(roof, xf, steel, false)
	# lamps and PA horns along the front edge
	var lamps: Array[Transform3D] = []
	var horns: Array[Transform3D] = []
	var x := -L / 2.0 + 1.0
	var i := 0
	while x < L / 2.0 - 0.6:
		if i % 3 == 1:
			horns.append(Transform3D(Basis(Vector3.RIGHT, 0.5).scaled(Vector3(0.16, 0.16, 0.28)), Vector3(x, front_y - 0.7, z1 - 0.5)))
		else:
			lamps.append(Transform3D(Basis().scaled(Vector3(0.22, 0.08, 0.16)), Vector3(x, front_y - 0.55, z1 - 0.45)))
		x += 1.6
		i += 1
	_mm(roof, lamps, mat(Color(1.0, 0.95, 0.85), 0.3, 0.0, 0.4), false)
	_mm(roof, horns, mat(Color(0.82, 0.83, 0.84), 0.4, 0.3), false)
	# CCTV at each end: a bracket and a small camera aimed at the stand
	for e in [-1.0, 1.0]:
		var cx: float = e * (L / 2.0 - 0.35)
		lbox(roof, Vector3(cx, front_y - 0.55, z1 - 0.4), Vector3(0.04, 0.3, 0.04), steel)
		var cam := lbox(roof, Vector3(cx, front_y - 0.72, z1 - 0.38), Vector3(0.12, 0.12, 0.26), mat(Color(0.92, 0.92, 0.9), 0.4), 0.0)
		cam.rotation.x = -0.6


## Steel lattice on top of the roof, in the stand's steel finish: girders
## running front to back, one deep girder along the whole front, or a space
## frame over the whole roof.
func _top_trusses(roof: Node3D, L: float, D: float, top: float) -> void:
	var style := String(_rs.get("top_truss", "none"))
	var th := 1.1 * clampf(float(_rs.get("truss_h", 1.0)), 0.3, 3.0)
	var front_y := top + ROOF_CLEARANCE + _roof_tilt() * 0.6 + 0.12
	var back_y := top + ROOF_CLEARANCE - _roof_tilt() * 0.4 + 0.12
	var z0 := -D / 2.0
	var z1 := _roof_front(D)
	var yat := func(z: float) -> float: return lerpf(back_y, front_y, (z - z0) / maxf(0.01, z1 - z0))
	var rods: Array[Transform3D] = []
	var rod := func(a: Vector3, b: Vector3, t: float) -> void: rods.append(_rod(a, b, t))
	match style:
		"cross":
			var n := maxi(2, int(L / 5.0) + 1)
			for k in n:
				var x := (float(k) / float(n - 1) - 0.5) * (L - 0.6)
				var panels := maxi(3, int((z1 - z0) / 1.2))
				for j in panels:
					var za := lerpf(z0, z1, float(j) / panels)
					var zb := lerpf(z0, z1, float(j + 1) / panels)
					var ha := th * (0.4 + 0.6 * sin(PI * float(j) / panels))
					var hb := th * (0.4 + 0.6 * sin(PI * float(j + 1) / panels))
					rod.call(Vector3(x, yat.call(za), za), Vector3(x, yat.call(zb), zb), 0.07)
					rod.call(Vector3(x, yat.call(za) + ha, za), Vector3(x, yat.call(zb) + hb, zb), 0.07)
					rod.call(Vector3(x, yat.call(za), za), Vector3(x, yat.call(za) + ha, za), 0.05)
					rod.call(Vector3(x, yat.call(za), za), Vector3(x, yat.call(zb) + hb, zb), 0.04)
		"long":
			# one deep girder along the length, set back from the front edge
			var zg := lerpf(z0, z1, 0.62)
			var y0: float = yat.call(zg)
			var panels := maxi(4, int(L / 1.6))
			for j in panels:
				var xa := -L / 2.0 + L * float(j) / panels
				var xb := -L / 2.0 + L * float(j + 1) / panels
				for dz in [-0.45, 0.45]:
					rod.call(Vector3(xa, y0 + th * 1.6, zg + dz), Vector3(xb, y0 + th * 1.6, zg + dz), 0.08)
					rod.call(Vector3(xa, y0, zg + dz), Vector3(xb, y0, zg + dz), 0.08)
					rod.call(Vector3(xa, y0, zg + dz), Vector3(xa, y0 + th * 1.6, zg + dz), 0.05)
					rod.call(Vector3(xa, y0 + (th * 1.6 if j % 2 == 0 else 0.0), zg + dz), Vector3(xb, y0 + (0.0 if j % 2 == 0 else th * 1.6), zg + dz), 0.05)
				rod.call(Vector3(xa, y0 + th * 1.6, zg - 0.45), Vector3(xa, y0 + th * 1.6, zg + 0.45), 0.04)
		"space_frame":
			var step := 1.4
			var nz := maxi(2, int((z1 - z0) / step))
			var nx := maxi(2, int(L / step))
			var lift := th * 0.6
			for jx in nx + 1:
				var x := -L / 2.0 + L * float(jx) / nx
				for jz in nz:
					var za := lerpf(z0, z1, float(jz) / nz)
					var zb := lerpf(z0, z1, float(jz + 1) / nz)
					rod.call(Vector3(x, yat.call(za) + lift, za), Vector3(x, yat.call(zb) + lift, zb), 0.04)
			for jz in nz + 1:
				var z := lerpf(z0, z1, float(jz) / nz)
				rod.call(Vector3(-L / 2.0, yat.call(z) + lift, z), Vector3(L / 2.0, yat.call(z) + lift, z), 0.04)
				for jx in nx:
					var xa := -L / 2.0 + L * float(jx) / nx
					var xb := -L / 2.0 + L * float(jx + 1) / nx
					var xm := (xa + xb) / 2.0
					rod.call(Vector3(xm, yat.call(z), z), Vector3(xa, yat.call(z) + lift, z), 0.03)
					rod.call(Vector3(xm, yat.call(z), z), Vector3(xb, yat.call(z) + lift, z), 0.03)
	var sm := _steel()
	if String(_paint.get("steel", "")) == "" and String(_paint.get("steel_mat", "")) == "":
		sm = mat(Color(0.86, 0.87, 0.88), 0.35, 0.7)   # roof steel is usually painted white or light grey
	_mm(roof, rods, sm)


## Structure outside the stand that carries the roof: pylons, lattice or
## concrete towers or A-frames standing behind the stand, with tie rods to the
## roof's front edge. Count, height and colour (the stand's steel paint) are
## the player's.
func _roof_pylons(roof: Node3D, L: float, D: float, top: float) -> void:
	var style := String(_rs.get("pylons", "none"))
	var n := clampi(int(_rs.get("pylon_count", 2)), 1, 8)
	var hm := clampf(float(_rs.get("pylon_h", 1.0)), 0.5, 3.0)
	var base_z := -D / 2.0 - 1.2
	var roof_y := top + ROOF_CLEARANCE
	var h := roof_y + 4.0 * hm
	var front_z := _roof_front(D) - 0.3
	# pylons have their own paint; unpainted they match the steelwork
	var sm := _steel()
	var pc := _pc("pylon")
	var pf := String(_paint.get("pylon_mat", ""))
	if pc.r >= 0.0 or pf != "":
		var col := pc if pc.r >= 0.0 else Color(0.55, 0.57, 0.6)
		sm = finish_mat(pf, col, 1.0) if pf != "" else mat(col, 0.35, 0.8)
	for k in n:
		var x := (float(k) + 0.5) / n * L - L / 2.0 if n > 1 else 0.0
		match style:
			"lattice_tower":
				var w := 0.9
				for dx in [-w / 2.0, w / 2.0]:
					for dz in [-w / 2.0, w / 2.0]:
						lbox(roof, Vector3(x + dx, h / 2.0, base_z + dz), Vector3(0.1, h, 0.1), sm)
				var y := 0.8
				while y < h:
					for dz in [-w / 2.0, w / 2.0]:
						var br := lbox(roof, Vector3(x, y, base_z + dz), Vector3(w * 1.25, 0.05, 0.05), sm, 0.0)
						br.rotation.z = 0.6 if int(y) % 2 == 0 else -0.6
					y += 1.4
			"concrete_tower":
				lbox(roof, Vector3(x, h / 2.0, base_z), Vector3(1.4, h, 1.4), tex_mat("rough_concrete", Color(0.76, 0.76, 0.74), 2.0, true))
				lbox(roof, Vector3(x, h + 0.2, base_z), Vector3(1.6, 0.4, 1.6), sm)
			"box_girder":
				# a round concrete tower behind the stand carrying a huge box
				# girder that cantilevers up over the roof and back out behind
				var tower := MeshInstance3D.new()
				var tcm := CylinderMesh.new()
				tcm.top_radius = 1.0
				tcm.bottom_radius = 1.0
				tcm.height = h
				tcm.radial_segments = 24
				tower.mesh = tcm
				tower.material_override = tex_mat("rough_concrete", Color(0.84, 0.82, 0.78), 2.0, true)
				tower.position = Vector3(x, h / 2.0, base_z - 0.6)
				roof.add_child(tower)
				var gtop := Vector3(x, h + 0.6, base_z - 0.6)
				var tip := Vector3(x, h + 2.2, front_z * 0.6)
				var tail := Vector3(x, h + 1.4, base_z - 6.0)
				_beam(roof, gtop, tip, 1.1, sm)
				_beam(roof, gtop, tail, 1.0, sm)
				# open lattice panels in the girder's sides (dark windows)
				var win := mat(Color(0.12, 0.08, 0.07), 0.8)
				for t in [0.3, 0.55, 0.8]:
					for side_x in [-0.56, 0.56]:
						var wp: Vector3 = gtop.lerp(tip, t) + Vector3(side_x, 0, 0)
						var wb := _beam(roof, wp - (tip - gtop).normalized() * 0.6, wp + (tip - gtop).normalized() * 0.6, 0.6, win)
						wb.scale = Vector3(0.05, 1.0, 1.0)
			"a_frame":
				# two splayed legs meeting at the top, a cross brace, and a heavy
				# boom out over the roof (Dortmund-style)
				var apex := Vector3(x, h, base_z)
				var spread := 1.6 + h * 0.14
				for e in [-1.0, 1.0]:
					_beam(roof, Vector3(x + e * spread, 0.0, base_z - 0.8), apex, 0.55, sm)
				_beam(roof, Vector3(x - spread * 0.55, h * 0.45, base_z - 0.45), Vector3(x + spread * 0.55, h * 0.45, base_z - 0.45), 0.3, sm)
				_beam(roof, apex, Vector3(x, roof_y + 1.2, front_z * 0.15), 0.4, sm)
			_:
				# a single tall tapered steel pylon
				var c := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.14
				cm.bottom_radius = 0.32
				cm.height = h
				cm.radial_segments = 10
				c.mesh = cm
				c.material_override = sm
				c.position = Vector3(x, h / 2.0, base_z)
				roof.add_child(c)
		# tie rods from the top down to the roof front and back to the ground
		var top_p := Vector3(x, h, base_z)
		for tgt in [Vector3(x, roof_y + 0.3, front_z), Vector3(x, roof_y + 0.3, front_z * 0.4), Vector3(x, 0.0, base_z - 4.0)]:
			var d: Vector3 = tgt - top_p
			var rod := MeshInstance3D.new()
			var bm := BoxMesh.new()
			var rt := 0.09 if style == "a_frame" else 0.05
			bm.size = Vector3(rt, rt, d.length())
			rod.mesh = bm
			rod.material_override = sm
			roof.add_child(rod)
			rod.position = top_p + d / 2.0
			rod.look_at(roof.to_global(tgt), Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT)


## Screens closing the open sides of a roof: from the back of the stand up to
## the roof and forward over the seats, solid (in the stand's trim) or glazed.
## Not on an end that runs on into a corner stand.
func _roof_ends(roof: Node3D, s: Stand, L: float, D: float, top: float, open_end: Dictionary) -> void:
	var front_y := top + ROOF_CLEARANCE + _roof_tilt() * 0.6
	var back_y := top + ROOF_CLEARANCE - _roof_tilt() * 0.4
	var z0 := -D / 2.0
	var z1 := minf(_roof_front(D), D / 2.0)
	var run := _roof_front(D) - z0
	var y1 := back_y + (front_y - back_y) * (z1 - z0) / maxf(0.01, run)
	var glazed := String(_rs.get("ends", "open")) == "glazed"
	var m: Material
	if glazed:
		m = mat(Color(0.7, 0.8, 0.86), 0.05, 0.3, 0.0, 0.35)
	else:
		m = facade_mat(s, true)
	var low_front := s.plinth + 0.9
	for e in [-1, 1]:
		if open_end.has(e):
			continue
		var x: float = e * (L / 2.0 - 0.02)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pts: Array[Vector3] = [Vector3(x, 0.0, z0), Vector3(x, back_y, z0), Vector3(x, y1, z1), Vector3(x, low_front, z1)]
		var n := Vector3(e, 0, 0)
		for tri in [[0, 1, 2], [0, 2, 3], [0, 2, 1], [0, 3, 2]]:
			for k in tri:
				st.set_normal(n)
				st.set_uv(Vector2(pts[k].z, pts[k].y) * 0.5)
				st.add_vertex(pts[k])
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = m
		roof.add_child(mi)
		# a steel edge frame, and mullions on the glazed kind
		var sm := _steel()
		_beam(roof, pts[1], pts[2], 0.08, sm)
		_beam(roof, pts[2], pts[3], 0.08, sm)
		_beam(roof, pts[3], pts[0], 0.06, sm)
		if glazed:
			var zz := z0 + 1.2
			while zz < z1 - 0.3:
				var t := (zz - z0) / (z1 - z0)
				_beam(roof, Vector3(x, lerpf(0.0, low_front, t), zz), Vector3(x, lerpf(back_y, y1, t), zz), 0.04, sm)
				zz += 1.2


## The "tyre" profile: outward offset of the skin at height fraction t
## (0 at the ground, 1 where it meets the roof): bulges out, curves back in.
static func tyre_offset(t: float, bulge: float) -> float:
	return bulge * sin(PI * clampf(t, 0.0, 1.0) * 0.85) - bulge * 0.9 * pow(clampf(t, 0.0, 1.0), 3.0)


func _tyre_skin(parent: Node3D, s: Stand, L: float, z0: float, h: float) -> void:
	var m := facade_mat(s)
	var bands := 8
	var bulge := 1.2
	for k in bands:
		var t0 := float(k) / bands
		var t1 := float(k + 1) / bands
		var y0 := h * t0
		var y1 := h * t1
		var o0 := tyre_offset(t0, bulge)
		var o1 := tyre_offset(t1, bulge)
		var a := Vector3(0, y0, z0 - o0)
		var b := Vector3(0, y1, z0 - o1)
		var mid := (a + b) / 2.0
		var seg := lbox(parent, mid, Vector3(L + 0.02, a.distance_to(b) + 0.02, 0.12), m)
		seg.rotation.x = atan2(-(b.z - a.z), b.y - a.y)
	# over the top: from the last band inward to the roof's back edge
	var top_o := tyre_offset(1.0, bulge)
	var cap := lbox(parent, Vector3(0, h + 0.15, z0 - top_o / 2.0 + 0.3), Vector3(L + 0.02, 0.1, absf(top_o) + 0.8), m)
	cap.rotation.x = 0.15


## A straight square beam between two points (local to `parent`).
func _beam(parent: Node3D, a: Vector3, b: Vector3, thick: float, m: Material) -> MeshInstance3D:
	var d := b - a
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, thick, d.length())
	mi.mesh = bm
	mi.material_override = m
	parent.add_child(mi)
	mi.position = a + d / 2.0
	var up := Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT
	mi.basis = Basis.looking_at(d.normalized(), up)
	return mi


## Solar panels: a grid of thin silver frames over the dark cells.
func _solar_grid(roof: Node3D, L: float, D: float, top: float) -> void:
	var front_y := top + ROOF_CLEARANCE + _roof_tilt() * 0.6
	var back_y := top + ROOF_CLEARANCE - _roof_tilt() * 0.4
	var z0 := -D / 2.0
	var z1 := _roof_front(D)
	var run := z1 - z0
	var tilt := -atan2(front_y - back_y, run)
	var frame_m := mat(Color(0.75, 0.77, 0.8), 0.3, 0.8)
	var xf: Array[Transform3D] = []
	var basis := Basis(Vector3.RIGHT, tilt)
	var x := -L / 2.0
	while x <= L / 2.0:
		xf.append(Transform3D(basis.scaled(Vector3(0.03, 0.02, sqrt(run * run + 0.36))), Vector3(x, (front_y + back_y) / 2.0 + 0.15, (z0 + z1) / 2.0)))
		x += 1.0
	var k := 0.0
	while k <= run:
		var zz := z0 + k
		var yy := back_y + (front_y - back_y) * (k / run)
		xf.append(Transform3D(Basis().scaled(Vector3(L, 0.02, 0.03)), Vector3(0, yy + 0.15, zz)))
		k += 0.6
	var mi := MultiMesh.new()
	mi.transform_format = MultiMesh.TRANSFORM_3D
	mi.mesh = BoxMesh.new()
	mi.instance_count = xf.size()
	for i in xf.size():
		mi.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mi
	mmi.material_override = frame_m
	roof.add_child(mmi)


## A tensile membrane roof: white fabric bays pulled up to a peak on each
## mast, like a row of tents, over a steel frame.
func _roof_membrane(roof: Node3D, L: float, D: float, top: float) -> float:
	var base_y := top + ROOF_CLEARANCE
	var z0 := -D / 2.0
	var z1 := _roof_front(D)
	var bays := maxi(1, roundi(L / 4.5))
	var bw := L / bays
	var fab_c := _pc("roof")
	var fabric := mat(fab_c if fab_c.r >= 0.0 else Color(0.95, 0.95, 0.93), 0.6, 0.0, 0.0, 0.92)
	fabric.cull_mode = BaseMaterial3D.CULL_DISABLED
	var steel := _steel()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in bays:
		var xa := -L / 2.0 + b * bw
		var xb := xa + bw
		var peak := Vector3((xa + xb) / 2.0, base_y + 1.6, (z0 + z1) / 2.0 - 0.3)
		var corners := [Vector3(xa, base_y, z0), Vector3(xb, base_y, z0), Vector3(xb, base_y + 0.3, z1), Vector3(xa, base_y + 0.3, z1)]
		for i in 4:
			var a: Vector3 = corners[i]
			var c: Vector3 = corners[(i + 1) % 4]
			# a sagging edge: two triangles via a midpoint pulled toward the peak
			var mid := (a + c) / 2.0
			mid = mid.lerp(peak, 0.12) - Vector3(0, 0.25, 0)
			for tri in [[a, mid, peak], [mid, c, peak]]:
				for v in tri:
					st.add_vertex(v)
		# the mast through the peak and its stays
		lbox(roof, Vector3(peak.x, (base_y - 0.2 + peak.y + 0.8) / 2.0, peak.z), Vector3(0.09, peak.y + 0.8 - base_y + 0.2, 0.09), steel)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = fabric
	roof.add_child(mi)
	# steel frame: a beam along the front and back, columns at the back
	lbox(roof, Vector3(0, base_y + 0.3, z1), Vector3(L, 0.14, 0.14), steel)
	lbox(roof, Vector3(0, base_y, z0), Vector3(L, 0.14, 0.14), steel)
	for b in bays + 1:
		var x := -L / 2.0 + b * bw
		lbox(roof, Vector3(clampf(x, -L / 2.0 + 0.1, L / 2.0 - 0.1), base_y / 2.0, z0 + 0.07), Vector3(0.16, base_y, 0.16), steel)
		var rib := lbox(roof, Vector3(clampf(x, -L / 2.0 + 0.1, L / 2.0 - 0.1), base_y + 0.15, (z0 + z1) / 2.0), Vector3(0.08, 0.1, z1 - z0), steel)
		rib.rotation.x = -atan2(0.3, z1 - z0)
	return base_y + 0.2


## A sawtooth roof: a run of ridges across the stand, each with a glazed
## face toward the pitch and a sloping metal back.
func _roof_sawtooth(roof: Node3D, L: float, D: float, top: float) -> float:
	var base_y := top + ROOF_CLEARANCE
	var z0 := -D / 2.0
	var z1 := _roof_front(D)
	var teeth := maxi(2, roundi((z1 - z0) / 2.0))
	var tw := (z1 - z0) / teeth
	var rise := 0.7
	var metal := _sheet(Color(0.6, 0.62, 0.65))
	var glass := mat(Color(0.55, 0.7, 0.8), 0.1, 0.3, 0.0, 0.6)
	for t in teeth:
		var za := z0 + t * tw
		var zb := za + tw
		var slope := sqrt(tw * tw + rise * rise)
		lbox(roof, Vector3(0, base_y + rise / 2.0, (za + zb) / 2.0), Vector3(L, 0.08, slope), metal, -atan2(rise, tw))
		lbox(roof, Vector3(0, base_y + rise / 2.0, zb - 0.02), Vector3(L, rise, 0.04), glass)
	lbox(roof, Vector3(0, base_y + rise + 0.05, z1), Vector3(L, 0.35, 0.1), _fascia())
	var steel := _steel()
	var n := maxi(2, int(L / 5.0) + 1)
	for k in n:
		var x := (float(k) / float(n - 1) - 0.5) * (L - 0.4)
		lbox(roof, Vector3(x, base_y / 2.0, z0 + 0.07), Vector3(0.2, base_y, 0.2), steel)
		lbox(roof, Vector3(x, base_y - 0.1, (z0 + z1) / 2.0), Vector3(0.1, 0.2, z1 - z0), steel)
	return base_y + rise


## Curved barrel-vault roof (arched front to back) on back columns.
func _roof_barrel(roof: Node3D, L: float, D: float, top: float, length: int) -> float:
	var base_y := top + ROOF_CLEARANCE
	var z0 := -D / 2.0
	var z1 := _roof_front(D)
	var half := (z1 - z0) / 2.0
	var rise := clampf(half * 0.45, 0.8, 2.2)
	var radius := (half * half + rise * rise) / (2.0 * rise)
	var centre_y := base_y + rise - radius
	var centre_z := (z0 + z1) / 2.0
	var theta := asin(clampf(half / radius, -1.0, 1.0))
	var segs := 10
	var skin := _sheet(Color(0.66, 0.68, 0.7))
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
			lbox(roof, Vector3(x, mid.y + 0.06, mid.x), Vector3(0.12, 0.12, d.length() + 0.04), _fascia(), -atan2(d.y, d.x))
		lbox(roof, Vector3(x, base_y / 2.0, z0 + 0.1), Vector3(0.2, base_y, 0.2), _steel())
	# tie bars across each rib and a leading-edge beam
	var steel := mat(Color(0.5, 0.52, 0.56), 0.35, 0.8)
	for k in ribs:
		var x := (float(k) / float(ribs - 1) - 0.5) * (L - 0.1)
		lbox(roof, Vector3(x, base_y - 0.05, centre_z), Vector3(0.06, 0.06, z1 - z0), steel)
	lbox(roof, Vector3(0, base_y - 0.12, z1 - 0.05), Vector3(L, 0.22, 0.14), _fascia())
	return base_y - 0.1


## "Goalpost" roof: no pillars in the way, the front hangs from a big steel
## truss spanning the whole stand on two tall end towers.
func _roof_truss(roof: Node3D, L: float, D: float, top: float) -> float:
	var front_y := top + ROOF_CLEARANCE + 0.2
	var back_y := top + ROOF_CLEARANCE - 0.3
	var z0 := -D / 2.0
	var z1 := _roof_front(D)
	var run := z1 - z0
	lbox(roof, Vector3(0, (front_y + back_y) / 2.0, (z0 + z1) / 2.0), Vector3(L, 0.14, sqrt(run * run + 0.25)), _sheet(Color(0.6, 0.62, 0.65)), -atan2(front_y - back_y, run))
	var steel := _steel_or(_club.primary_color.darkened(0.15))
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
	lbox(roof, Vector3(0, back_y / 2.0, z0 + 0.07), Vector3(L - 0.4, 0.06, 0.06), _steel())
	return lo - 0.25


## Classic pitched roof: two slopes meeting at a ridge, pillars along the front,
## and a gable over the middle. Returns the height for the name board.
func _roof_gable(roof: Node3D, L: float, D: float, top: float) -> float:
	var eave := top + ROOF_CLEARANCE - 0.2
	var ridge := eave + RIDGE_RISE
	var front := _roof_front(D) + 0.1
	var back := -D / 2.0
	var ridge_z := (front + back) / 2.0
	var tin := _sheet(Color(0.42, 0.5, 0.44))
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
	lbox(roof, Vector3(0, eave - 0.1, front), Vector3(L, 0.3, 0.1), _fascia())
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
var _corner_p := 2.0   # superellipse power of the rounded corner being built (2 = circle)


## Unit point on the corner's outline at angle phi (a circle, or squarer).
func _se(phi: float) -> Vector2:
	var cs := cos(phi)
	var sn := sin(phi)
	if is_equal_approx(_corner_p, 2.0):
		return Vector2(cs, sn)
	var n := pow(pow(absf(cs), _corner_p) + pow(absf(sn), _corner_p), 1.0 / _corner_p)
	return Vector2(cs, sn) / maxf(n, 0.0001)


func sector(parent: Node3D, cf: Dictionary, r0: float, r1: float, y0: float, y1: float, m: Material, segs := 14) -> void:
	if not is_equal_approx(_corner_p, 2.0):
		segs = maxi(segs, 24)   # squarer outlines need more pieces round the tight bend
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c: Vector2 = cf["centre"]
	var sx: float = cf["sx"]
	var sz: float = cf["sz"]
	var pt := func(r: float, phi: float, y: float) -> Vector3:
		var u := _se(phi)
		return Vector3(c.x + sx * u.x * r, y, c.y + sz * u.y * r)
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


func _double_sided(m: Material) -> Material:
	if not (m is StandardMaterial3D):
		return m   # shader materials here are already cull_disabled
	var key := "ds|%d" % m.get_instance_id()
	if not _mats.has(key):
		var d: StandardMaterial3D = m.duplicate()
		d.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = d
		if m in _etfe_mats:
			_etfe_mats.append(d)
	return _mats[key]


## A gangway up the diagonal of a corner stand: lighter steps on each row, with handrails.
func _corner_gangway(root: Node3D, s: Stand, pitch: Rect2i) -> void:
	var cf := corner_frame(s.side, pitch)
	var c: Vector2 = cf["centre"]
	var d := Vector2(float(cf["sx"]), float(cf["sz"])).normalized()
	var step_m := mat(Color(0.86, 0.86, 0.84), 0.8)
	var rail := mat(Color(0.42, 0.44, 0.47), 0.35, 0.8)
	var g := Node3D.new()
	g.position = Vector3(c.x, 0, c.y)
	g.rotation.y = atan2(d.x, d.y)
	root.add_child(g)
	# in this frame +Z runs out from the pitch corner along the diagonal
	var scale_r := 1.0 if s.shape == "rounded" else sqrt(2.0)
	for v in s.depth:
		var r0 := v * scale_r
		var y := row_height(v, s)
		lbox(g, Vector3(0, y + 0.01, r0 + scale_r * 0.5), Vector3(0.44, 0.04, scale_r * 0.9), step_m)
	var h0 := row_height(0, s) + 0.35
	var h1 := row_height(s.depth - 1, s) + 0.35
	var run := s.depth * scale_r
	for e in [-1, 1]:
		lbox(g, Vector3(e * 0.25, (h0 + h1) / 2.0, run / 2.0), Vector3(0.03, 0.03, sqrt(run * run + (h1 - h0) * (h1 - h0))), rail, -atan2(h1 - h0, run))


func _build_rounded_corner(root: Node3D, s: Stand, pitch: Rect2i, selected: bool, label: Dictionary) -> void:
	_corner_p = s.corner_power()
	_build_rounded_corner_body(root, s, pitch, selected, label)
	_corner_p = 2.0


func _build_rounded_corner_body(root: Node3D, s: Stand, pitch: Rect2i, selected: bool, label: Dictionary) -> void:
	var cf := corner_frame(s.side, pitch)
	var concrete := tex_mat("rough_concrete", _aged(Color(0.6, 0.6, 0.59), s), 3.0, true)
	var seat := mat(seat_color(s), 0.7) if not has_seats(s) else tex_mat("rough_concrete", Color(0.68, 0.68, 0.67), 3.0, true)
	var top := 0.0
	for v in s.depth:
		var hgt := row_height(v, s)
		top = hgt
		sector(root, cf, float(v), float(v + 1), hgt - 0.5 if v >= _hollow_from else 0.0, hgt, concrete)
		sector(root, cf, v + 0.04, v + 0.7, hgt, hgt + 0.07, seat)
	for k in range(1, s.tiers):
		var base := tier_base(s, k)
		var tf := float(tier_front(s, k))
		for v in s.depth:
			var y := base + row_height(v, s)
			sector(root, cf, tf + v, tf + v + 1, y - 0.6, y, concrete)
			sector(root, cf, tf + v + 0.04, tf + v + 0.7, y, y + 0.07, seat)
		sector(root, cf, tf - 0.06, tf + 0.04, base - 0.55, base + 0.2, _fascia())
		top = base + row_height(s.depth - 1, s)
	var R := float(s.depth + tier_front(s, s.tiers - 1))
	if s.facade != "stacked":
		sector(root, cf, R - 0.14, R, 0.0, top + 1.1, facade_mat(s))
	sector(root, cf, R - 0.04, R + 0.12, top + 1.0, top + 1.16, _fascia(0.15))
	var cc: Vector2 = cf["centre"]
	var split := float(s.extra("split")["height"])
	if split > 0.01:
		sector(root, cf, R + 0.02, R + 0.1, 0.0, (top + 1.1) * split, _split_material(s), 24)
	var painted := _pc("wall").r >= 0.0 or String(_paint.get("wall_mat", "")) != ""
	if s.facade == "stacked":
		_curved_stacked(root, s, cf, R, top + 1.1)
	elif s.facade == "concrete" and not painted:
		_curved_facade(root, cf, R, top + 1.1)
	elif String(_paint.get("wall_mat", "")) == "etfe":
		pass
	else:
		for k in range(1, 6):
			var phi := PI / 2.0 * k / 6.0
			var se := _se(phi)
			var p := cc + Vector2(float(cf["sx"]) * se.x, float(cf["sz"]) * se.y) * (R + 0.05)
			box(root, Vector3(p.x - 0.14, 0, p.y - 0.14), Vector3(p.x + 0.14, top + 1.1, p.y + 0.14), facade_mat(s, true))
	_corner_gangway(root, s, pitch)
	if s.roof != "open":
		var roof := Node3D.new()
		root.add_child(roof)
		_roofs.append(roof)
		roof.visible = show_roofs
		var ry := maxf(top, _ring_top) + ROOF_CLEARANCE
		# the roof reaches in from the back as far as the side stands' roofs do
		var r_in := maxf(0.0, R - (R + 0.7) * _roof_reach())
		var fh := _roof_cfg("fascia_h", 0.55)
		sector(roof, cf, r_in, R, ry, ry + 0.14, _sheet(Color(0.6, 0.62, 0.65)), 18)
		sector(roof, cf, R - 0.12, R, ry - 0.35, ry + 0.2, _fascia(), 18)
		if r_in > 0.05 and fh > 0.01:
			sector(roof, cf, r_in, r_in + 0.12, ry - fh * 0.6, ry + fh * 0.4, _fascia(), 18)
		if String(_rs.get("back", "open")) == "tyre":
			var bands := 8
			for k in bands:
				var t0 := float(k) / bands
				var t1 := float(k + 1) / bands
				var o := (tyre_offset(t0, 1.2) + tyre_offset(t1, 1.2)) / 2.0
				sector(roof, cf, R + o - 0.06, R + o + 0.06, ry * t0, ry * t1 + 0.02, facade_mat(s), 24)
		if String(_rs.get("top_truss", "none")) != "none":
			# the side stands' top steelwork carried round the corner: radial
			# trusses fanning out, tied by a ring along the middle
			var sm := _steel()
			if String(_paint.get("steel", "")) == "" and String(_paint.get("steel_mat", "")) == "":
				sm = mat(Color(0.86, 0.87, 0.88), 0.35, 0.7)
			var th := 0.9 * clampf(float(_rs.get("truss_h", 1.0)), 0.3, 3.0)
			var n := maxi(3, int(PI / 2.0 * R / 2.5))
			var c0: Vector2 = cf["centre"]
			var dirs: Array[Vector2] = []
			for k in n + 1:
				var phi := PI / 2.0 * k / n
				var se := _se(phi)
				dirs.append(Vector2(float(cf["sx"]) * se.x, float(cf["sz"]) * se.y))
			for d in dirs:
				var a := c0 + d * (r_in + 0.3)
				var b := c0 + d * (R - 0.3)
				_beam(roof, Vector3(a.x, ry + 0.2, a.y), Vector3(b.x, ry + 0.2 + th, b.y), 0.08, sm)
				_beam(roof, Vector3(a.x, ry + 0.2, a.y), Vector3(b.x, ry + 0.2, b.y), 0.06, sm)
				var m := c0 + d * ((r_in + R) / 2.0)
				_beam(roof, Vector3(m.x, ry + 0.2, m.y), Vector3(m.x, ry + 0.2 + th * 0.5, m.y), 0.05, sm)
			for k in n:
				var rm := (r_in + R) / 2.0
				var p0 := c0 + dirs[k] * rm
				var p1 := c0 + dirs[k + 1] * rm
				_beam(roof, Vector3(p0.x, ry + 0.2 + th * 0.5, p0.y), Vector3(p1.x, ry + 0.2 + th * 0.5, p1.y), 0.06, sm)
		var c: Vector2 = cf["centre"]
		for phi in [PI / 8, PI / 4, 3 * PI / 8]:
			var se := _se(phi)
			var p := c + Vector2(float(cf["sx"]) * se.x, float(cf["sz"]) * se.y) * (R - 0.25)
			box(roof, Vector3(p.x - 0.1, 0, p.y - 0.1), Vector3(p.x + 0.1, ry, p.y + 0.1), _steel())
	_corner_extras(root, s, pitch, top, R)
	_corner_signs(root, s, pitch, top, R)
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
	var concrete := tex_mat("rough_concrete", _aged(Color(0.6, 0.6, 0.59), s), 3.0, true)
	var seat := mat(seat_color(s), 0.7) if not has_seats(s) else tex_mat("rough_concrete", Color(0.68, 0.68, 0.67), 3.0, true)
	var top := 0.0
	for v in s.depth:
		var hgt := row_height(v, s)
		top = hgt
		for t in s.row_tiles(pitch, v):
			box(root, Vector3(t.x, hgt - 0.5 if v >= _hollow_from else 0.0, t.y), Vector3(t.x + 1, hgt, t.y + 1), concrete)
			box(root, Vector3(t.x + 0.06, hgt, t.y + 0.06), Vector3(t.x + 0.94, hgt + 0.07, t.y + 0.94), seat)
	for k in range(1, s.tiers):
		var base := tier_base(s, k)
		var tf := tier_front(s, k)
		for v in s.depth:
			var y := base + row_height(v, s)
			for ab in s._corner_cells(tf + v, 1):
				var t := Stand.corner_to_grid(s.side, pitch, ab.x, ab.y)
				box(root, Vector3(t.x, y - 0.6, t.y), Vector3(t.x + 1, y, t.y + 1), concrete)
				box(root, Vector3(t.x + 0.06, y, t.y + 0.06), Vector3(t.x + 0.94, y + 0.07, t.y + 0.94), seat)
		top = base + row_height(s.depth - 1, s)
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
		box(root, Vector3(w.position.x + out.x - 0.05, top + 1.0, w.position.y + out.y - 0.05), Vector3(w.end.x + out.x + 0.05, top + 1.16, w.end.y + out.y + 0.05), _fascia(0.15))
	_corner_gangway(root, s, pitch)
	if s.roof != "open":
		var roof := Node3D.new()
		root.add_child(roof)
		_roofs.append(roof)
		roof.visible = show_roofs
		var ry := maxf(top, _ring_top) + ROOF_CLEARANCE
		var rr := _grow_toward_pitch(_grow_toward_pitch(foot, Vector2(tp.x, 0), 0.7), Vector2(0, tp.y), 0.7)
		box(roof, Vector3(rr.position.x, ry, rr.position.y), Vector3(rr.end.x, ry + 0.14, rr.end.y), _sheet(Color(0.6, 0.62, 0.65)))
		for axis in [Vector2(tp.x, 0), Vector2(0, tp.y)]:
			var f := _strip_toward_pitch(rr, axis, 0.12)
			box(roof, Vector3(f.position.x, ry - 0.35, f.position.y), Vector3(f.end.x, ry + 0.2, f.end.y), _fascia())
		var c := Vector2(foot.position.x if tp.x > 0 else foot.end.x, foot.position.y if tp.y > 0 else foot.end.y)
		c -= tp * 0.15
		box(roof, Vector3(c.x - 0.12, 0, c.y - 0.12), Vector3(c.x + 0.12, ry, c.y + 0.12), _steel())
	_corner_extras(root, s, pitch, top, float(R))
	_corner_signs(root, s, pitch, top, float(R))
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


var _roof_tile_mats := {}
## A simple pitched roof over a rectangle (ridge along x), from height y up by h.
func _hip_roof(g: Node3D, r: Rect2, y: float, h: float, m: Material) -> void:
	var half := r.size.y / 2.0 + 0.15
	var slope := sqrt(half * half + h * h)
	var ang := atan2(h, half)
	for side in [-1, 1]:
		var slab := lbox(g, Vector3(r.get_center().x, y + h / 2.0, r.get_center().y + side * half / 2.0), Vector3(r.size.x + 0.3, 0.06, slope), m, 0.0)
		slab.rotation.x = ang * side
	# gable ends
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in [r.position.x, r.end.x]:
		for q in [Vector3(x, y, r.position.y), Vector3(x, y + h, r.get_center().y), Vector3(x, y, r.end.y)]:
			st.add_vertex(q)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _double_sided(tex_mat("red_brick_03", Color.WHITE, 1.0))
	g.add_child(mi)


func _roof_tiles_mat(col: Color) -> Material:
	var k := col.to_html()
	if not _roof_tile_mats.has(k):
		var m := ShaderMaterial.new()
		m.shader = load("res://view/roof_tiles.gdshader")
		m.set_shader_parameter("tint", col)
		_roof_tile_mats[k] = m
	return _roof_tile_mats[k]


var _roof_metal := {}
## Standing-seam metal roofing in a colour (see roof_metal.gdshader).
## The stand being built's roof shape (its "roof_shape" extra): reach over
## the seats (0.5..1.4 of the stand depth), tilt (-1 back .. 1 up to the pitch),
## fascia height, column style.
var _rs: Dictionary = {}


func _roof_cfg(key: String, default: float) -> float:
	return float(_rs.get(key, default)) if _rs.has(key) and float(_rs[key]) >= 0.0 else default


func _roof_reach() -> float:
	if _ring_reach > 0.0:
		return _ring_reach
	return _roof_cfg("reach", 1.0)


func _roof_tilt() -> float:
	return float(_rs.get("tilt", 1.0)) if _rs.has("tilt") and float(_rs["tilt"]) > -9.0 else 1.0


func _roof_front(D: float) -> float:
	return -D / 2.0 + (D + 0.7) * _roof_reach()


## A row of roof columns along a stand, in the stand's column style.
func _columns(roof: Node3D, L: float, z: float, h: float, length: int, front := false) -> void:
	var style := String(_rs.get("columns", "round"))
	if style == "none" and not front:
		# a true cantilever: a heavy back beam instead of columns
		lbox(roof, Vector3(0, h - 0.25, z - 0.1), Vector3(L, 0.5, 0.4), _steel(0.15))
		return
	var n := maxi(2, ceili(length / (5.0 if not front else 7.0)) + 1)
	for k in n:
		var x := (float(k) / float(n - 1) - 0.5) * (L - 0.4)
		match style:
			"ibeam":
				lbox(roof, Vector3(x, h / 2.0, z), Vector3(0.22, h, 0.06), _steel())
				for e in [-1.0, 1.0]:
					lbox(roof, Vector3(x, h / 2.0, z + e * 0.1), Vector3(0.22, h, 0.03), _steel())
			"lattice":
				for dx in [-0.12, 0.12]:
					lbox(roof, Vector3(x + dx, h / 2.0, z), Vector3(0.05, h, 0.05), _steel())
				var y := 0.0
				while y < h - 0.3:
					var br := lbox(roof, Vector3(x, y + 0.25, z), Vector3(0.03, 0.55, 0.03), _steel(), 0.0)
					br.rotation.z = 0.45 if int(y / 0.5) % 2 == 0 else -0.45
					y += 0.5
			_:
				var c := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.09
				cm.bottom_radius = 0.11
				cm.height = h
				cm.radial_segments = 10
				c.mesh = cm
				c.material_override = _steel()
				c.position = Vector3(x, h / 2.0, z)
				roof.add_child(c)


## The stand being built's own paint (its "paint" extra): roof sheet, roof
## fascia, steelwork, walls, trim and front wall, each "" for the default.
var _paint: Dictionary = {}


func _pc(key: String) -> Color:
	var v := String(_paint.get(key, ""))
	return Color.html(v) if v != "" and Color.html_is_valid(v) else Color(-1, -1, -1)


func _sheet(default: Color) -> Material:
	var c := _pc("roof")
	var f := String(_paint.get("roof_mat", ""))
	if f != "":
		return finish_mat(f, c if c.r >= 0.0 else default, 2.0)
	return roof_metal(c if c.r >= 0.0 else default)


func _fascia(dark := 0.0) -> Material:
	var c := _pc("fascia")
	var col := (c if c.r >= 0.0 else _club.primary_color).darkened(dark)
	var f := String(_paint.get("fascia_mat", ""))
	return finish_mat(f, col, 1.5) if f != "" else mat(col, 0.5)


func _steel(dark := 0.0) -> Material:
	var c := _pc("steel")
	var col := (c if c.r >= 0.0 else Color(0.55, 0.57, 0.6)).darkened(dark)
	var f := String(_paint.get("steel_mat", ""))
	return finish_mat(f, col, 1.0) if f != "" else mat(col, 0.35, 0.8)


## A part's own finish, if the player chose one ("" = keep `default`).
func _part(part: String, default: Material, fallback_col: Color, tiles := 2.0) -> Material:
	var f := String(_paint.get(part + "_mat", ""))
	var c := _pc(part)
	if f == "":
		if c.r < 0.0:
			return default
		return mat(c, 0.6)
	return finish_mat(f, c if c.r >= 0.0 else fallback_col, tiles)


const FINISH_TEX := {
	"concrete": ["rough_concrete", 3.0, 0.85, 0.0], "precast": ["concrete_panels", 3.0, 0.8, 0.0],
	"render": ["plastered_wall", 2.5, 0.9, 0.0], "plaster": ["painted_plaster_wall", 2.5, 0.85, 0.0],
	"brick": ["red_brick_03", 1.6, 0.9, 0.0], "sandstone": ["large_sandstone_blocks", 2.0, 0.9, 0.0],
	"granite": ["granite_wall", 2.0, 0.8, 0.0], "wood": ["oak_wood_planks", 1.6, 0.7, 0.0],
	"cladding": ["exterior_wall_cladding", 2.0, 0.6, 0.0], "metal_sheet": ["box_profile_metal_sheet", 2.4, 0.8, 0.2],
	"corrugated": ["corrugated_iron", 1.5, 0.5, 0.5], "steel_plate": ["metal_plate", 2.0, 0.4, 0.7],
	"tiles": ["rectangular_facade_tiles", 1.5, 0.5, 0.0], "rusty": ["rusty_metal_sheet", 1.8, 0.7, 0.4],
}
static var _grey_tex := {}


## A finish (texture) in a colour. With `col` white-ish the texture keeps its
## own colours; any other colour recolours it from the texture's light and
## shade, so blue brick still reads as brick.
func finish_mat(finish: String, col: Color, tiles := 2.0) -> Material:
	var key := "fin|%s|%s|%s" % [finish, col.to_html(), tiles]
	if _mats.has(key):
		return _mats[key]
	var m: StandardMaterial3D
	match finish:
		"glass":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(col.r, col.g, col.b, 0.55)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
			m.metallic = 0.4
		"etfe":
			# inflated ETFE cushions: a diamond lattice of pale pillows that glow
			# from inside at night in the chosen colour (Allianz Arena)
			m = StandardMaterial3D.new()
			m.albedo_texture = _etfe_texture()
			m.albedo_color = Color(1, 1, 1).lerp(col, 0.25)
			m.roughness = 0.25
			m.metallic = 0.0
			m.emission_enabled = true
			m.emission_texture = _etfe_texture()
			m.emission = col if not col.is_equal_approx(Color(1, 1, 1)) else Color(0.95, 0.95, 1.0)
			m.emission_energy_multiplier = 0.75 if _night else 0.03
			_etfe_mats.append(m)   # cached across rebuilds, so set_night switches these itself
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3.ONE / 4.0
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		"paint", "":
			m = StandardMaterial3D.new()
			m.albedo_color = col
			m.roughness = 0.6
			m.detail_enabled = true
			m.detail_albedo = grime_texture()
			m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3.ONE / 3.0
		_:
			var t: Array = FINISH_TEX.get(finish, FINISH_TEX["concrete"])
			var tex_name: String = t[0]
			m = StandardMaterial3D.new()
			var natural := col.is_equal_approx(Color(1, 1, 1)) or col.is_equal_approx(Color(-1, -1, -1))
			if natural:
				m.albedo_texture = load(TEX_DIR + tex_name + "/diff.jpg")
			else:
				m.albedo_texture = _grey(tex_name)
				# lift to the texture mean, but never past 1 (pale colours would blow out)
				m.albedo_color = Color(minf(col.r * 1.7, 0.92), minf(col.g * 1.7, 0.92), minf(col.b * 1.7, 0.92))
			m.normal_enabled = true
			m.normal_texture = load(TEX_DIR + tex_name + "/nor.jpg")
			if finish in ["metal_sheet", "corrugated"]:
				m.normal_scale = 0.3   # fine ribs turn to noise from the air at full strength
			m.roughness_texture = load(TEX_DIR + tex_name + "/rough.jpg")
			m.roughness = float(t[2])
			m.metallic = float(t[3])
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3.ONE / (float(t[1]) * tiles / 2.0)
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


var _etfe_tex: Texture2D
var _etfe_mats: Array[StandardMaterial3D] = []


## A tile of diamond cushions: bright centres falling off to dark seams.
func _etfe_texture() -> Texture2D:
	if _etfe_tex:
		return _etfe_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			# two diamonds per tile in a staggered lattice
			var u := float(x) / n
			var v := float(y) / n
			var a := absf(fposmod(u + v, 1.0) - 0.5) * 2.0
			var b := absf(fposmod(u - v, 1.0) - 0.5) * 2.0
			var d := minf(minf(a, 1.0 - a), minf(b, 1.0 - b))   # 0 at a seam, up to 0.5 at a cushion centre
			# bright in the middle of each pillow, falling off steeply to dark seams
			var lum := clampf(pow(d * 2.0, 0.6), 0.0, 1.0) * 0.95
			if d < 0.03:
				lum = 0.06
			img.set_pixel(x, y, Color(lum, lum, lum * 1.02))
	img.generate_mipmaps()
	_etfe_tex = ImageTexture.create_from_image(img)
	return _etfe_tex


## The texture's light and shade only (for recolouring).
static func _grey(tex_name: String) -> Texture2D:
	if _grey_tex.has(tex_name):
		return _grey_tex[tex_name]
	var img: Image = (load(TEX_DIR + tex_name + "/diff.jpg") as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	var w := img.get_width()
	var h := img.get_height()
	var sum := 0.0
	for y in range(0, h, 8):
		for x in range(0, w, 8):
			sum += img.get_pixel(x, y).get_luminance()
	var avg := maxf(0.05, sum / float((w / 8) * (h / 8)))
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var l := clampf(img.get_pixel(x, y).get_luminance() / avg * 0.5, 0.0, 1.0)
			out.set_pixel(x, y, Color(l, l, l))
	out.generate_mipmaps()
	_grey_tex[tex_name] = ImageTexture.create_from_image(out)
	return _grey_tex[tex_name]


func _steel_or(default: Color) -> Material:
	var c := _pc("steel")
	return mat(c if c.r >= 0.0 else default, 0.4, 0.6)


func roof_metal(col: Color) -> Material:
	var k := col.to_html()
	if not _roof_metal.has(k):
		var m := ShaderMaterial.new()
		m.shader = load("res://view/roof_metal.gdshader")
		m.set_shader_parameter("base", col)
		var nt := NoiseTexture2D.new()
		nt.seamless = true
		var fn := FastNoiseLite.new()
		fn.frequency = 0.05
		nt.noise = fn
		m.set_shader_parameter("noise", nt)
		_roof_metal[k] = m
	return _roof_metal[k]


func _frame_mat(kind: String) -> Material:
	match kind:
		"silver": return mat(Color(0.72, 0.74, 0.77), 0.35, 0.7)
		"club": return _fascia()
	return mat(Color(0.08, 0.08, 0.1), 0.4, 0.3)


## The club crest: a shield in the club colour with a trim chevron and the
## initials, `h` tall, facing local +Z (rotated by yaw). Lit crests glow at night.
## The club's badge (or uploaded logo), rendered once into a texture by a
## small off-screen viewport and redrawn whenever the badge changes.
var _badge_vp: SubViewport
var _badge_ctl: Control
var _badge_sig := ""


func badge_texture() -> Texture2D:
	if _badge_vp == null:
		_badge_vp = SubViewport.new()
		_badge_vp.size = Vector2i(256, 256)
		_badge_vp.transparent_bg = true
		_badge_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_badge_ctl = preload("res://view/ui/badge.gd").new(_club)
		_badge_ctl.size = Vector2(256, 256)
		_badge_vp.add_child(_badge_ctl)
		add_child(_badge_vp)
	var c: ClubState = _club if _club else ClubState.new()
	var sig := "%s|%s|%s|%s|%s|%d" % [c.badge, c.primary_color, c.secondary_color, c.third_color, c.club_name, c.founded]
	if sig != _badge_sig:
		_badge_sig = sig
		_badge_ctl.set("club", c)
		_badge_ctl.call("refresh")
		_badge_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	return _badge_vp.get_texture()


func _crest(parent: Node3D, pos: Vector3, h: float, yaw: float, lit: bool, mount := "flat", light := "") -> Node3D:
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = yaw
	parent.add_child(g)
	if light == "":
		light = "inside" if lit else "none"
	var tex := badge_texture()
	var q := QuadMesh.new()
	q.size = Vector2(h * 1.15, h * 1.15)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.45
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	var depth := 0.0
	if mount == "solid":
		# an extruded badge: the outline as a solid block in the trim colour,
		# the painted face on the front
		depth = h * 0.14
		var shape: String = _club.badge.get("shape", "shield") if _club else "shield"
		var outl := preload("res://view/ui/badge.gd").outline(shape)
		var pts := PackedVector2Array()
		for v in outl:
			pts.append(Vector2((v.x - 0.5) * h * 1.15, (0.5 - v.y) * h * 1.15))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := pts.size()
		for i in n:
			var p0 := pts[i]
			var p1 := pts[(i + 1) % n]
			for v in [Vector3(p0.x, p0.y, 0), Vector3(p1.x, p1.y, 0), Vector3(p1.x, p1.y, -depth), Vector3(p0.x, p0.y, 0), Vector3(p1.x, p1.y, -depth), Vector3(p0.x, p0.y, -depth)]:
				st.add_vertex(v)
		# the back face
		var idx := Geometry2D.triangulate_polygon(pts)
		for k in range(0, idx.size(), 3):
			for j in [0, 2, 1]:
				var pp := pts[idx[k + j]]
				st.add_vertex(Vector3(pp.x, pp.y, -depth))
		st.generate_normals()
		var side := MeshInstance3D.new()
		side.mesh = st.commit()
		var sm := StandardMaterial3D.new()
		sm.albedo_color = _club.third_color.lightened(0.15) if _club else Color(0.2, 0.2, 0.2)
		sm.metallic = 0.5
		sm.roughness = 0.35
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		side.material_override = sm
		g.add_child(side)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position.z = 0.01
	g.add_child(mi)
	match light:
		"inside":
			m.emission_enabled = true
			m.emission_texture = tex
			_glow(m, 0.0, 1.4)
		"halo":
			var hm := StandardMaterial3D.new()
			hm.albedo_texture = tex
			hm.albedo_color = Color(0, 0, 0)
			hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			hm.emission_enabled = true
			hm.emission = Color(1.0, 0.95, 0.85)
			hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_glow(hm, 0.0, 3.0)
			var halo := MeshInstance3D.new()
			halo.mesh = q
			halo.material_override = hm
			halo.scale = Vector3(1.1, 1.1, 1.0)
			halo.position.z = -depth - 0.04
			g.add_child(halo)
			var ol := OmniLight3D.new()
			ol.light_energy = 0.8
			ol.omni_range = h * 1.2
			ol.position = Vector3(0, 0, 0.6)
			g.add_child(ol)
			_night_light(ol)
		"flood", "neon":
			var lamp := lbox(g, Vector3(0, -h * 0.62, 0.45), Vector3(0.3, 0.12, 0.18), mat(Color(0.2, 0.21, 0.22), 0.4, 0.6), 0.6)
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lbox(g, Vector3(0, -h * 0.62, 0.2), Vector3(0.04, 0.04, 0.45), mat(Color(0.2, 0.21, 0.22), 0.4, 0.6))
			var sp := SpotLight3D.new()
			sp.light_energy = 14.0
			sp.spot_range = h * 3.0
			sp.spot_angle = 45.0
			sp.position = Vector3(0, -h * 0.62, 0.9)
			g.add_child(sp)
			sp.look_at(g.to_global(Vector3(0, 0, 0)), Vector3.UP)
			_night_light(sp)
	return g


func _style(f: Facility, ft: FacilityType) -> String:
	return f.style if f.style != "" else ft.styles[0]


## Lettering with depth on a building: 3D letters sized like the old flat
## labels (font size x pixel size), facing +Z unless rotated; `light` as in Signs.
func _lettering(parent: Node3D, text: String, pos: Vector3, color: Color, px: float, size: int, rot_y := 0.0, light := "none", font := "future") -> Node3D:
	var cap := px * size * 0.7
	var o := { "text": text, "mount": "letters", "font": font, "depth": maxf(0.01, cap * 0.2), "scale": cap / 0.55, "light": light }
	var n := Signs.build(parent, o, color, color, 0.0, _glow, _night_light)
	n.position = pos
	n.rotation.y = rot_y
	return n


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

## Ways up: they rise from the ground to the stand's top deck (or the top of
## a single-tier stand), visible from outside when the concourse is behind it.
func _build_circulation(f: Facility, ft: FacilityType, s: Stand, pitch: Rect2i) -> void:
	var g := Node3D.new()
	g.position = Vector3(f.pos.x, 0.0, f.pos.y)
	_outside.add_child(g)
	var h := 3.0
	if s:
		h = maxf(2.0, (deck_y(s, s.tiers - 1) if s.tiers > 1 else stand_top(s)) + 0.4)
	var w := float(ft.size.x)
	var d := float(ft.size.y)
	var conc := tex_mat("rough_concrete", Color(0.72, 0.72, 0.7), 2.0, true)
	var steel := mat(Color(0.5, 0.52, 0.55), 0.35, 0.8)
	var club := _club.primary_color
	var glass := mat(Color(0.65, 0.78, 0.85), 0.05, 0.3, 0.0, 0.45)
	match ft.id:
		"stairs":
			if _style(f, ft) == "switchback":
				# a concrete tower with flights zig-zagging up behind a mesh screen
				box(g, Vector3(0.05, 0, 0.05), Vector3(0.95, h, 0.95), conc)
				var flights := maxi(2, int(h / 0.9))
				for k in flights:
					var y0 := k * h / flights
					var fl := lbox(g, Vector3(0.5, y0 + h / flights / 2.0, 0.5 + (0.22 if k % 2 == 0 else -0.22)), Vector3(0.8, 0.06, sqrt(0.64 + pow(h / flights, 2))), mat(Color(0.82, 0.82, 0.8), 0.8), 0.0)
					fl.rotation.x = atan2(h / flights, 0.8) * (1.0 if k % 2 == 0 else -1.0)
				box(g, Vector3(0.0, 0.0, -0.02), Vector3(1.0, h, 0.02), mat(club.darkened(0.2), 0.6))
			else:
				# a straight open flight with a handrail, up the side of the stand
				var run := sqrt(1.0 + h * h)
				var fl := lbox(g, Vector3(0.5, h / 2.0, 0.5), Vector3(0.8, 0.12, run), conc, 0.0)
				fl.rotation.x = -atan2(h, 1.0)
				var steps := int(h / 0.18)
				for k in steps:
					var t := (k + 0.5) / steps
					lbox(g, Vector3(0.5, t * h + 0.05, 0.5 - 0.5 + t), Vector3(0.78, 0.05, 0.12), mat(Color(0.86, 0.86, 0.84), 0.8))
				for e in [-0.4, 0.4]:
					var rl := lbox(g, Vector3(0.5 + e, h / 2.0 + 0.45, 0.5), Vector3(0.03, 0.03, run), steel, 0.0)
					rl.rotation.x = -atan2(h, 1.0)
		"spiral_ramp":
			if s:
				h = maxf(h, stand_top(s) + 0.6)   # ramp towers climb to the top of the stand
			# a San Siro style tower: a ramp winding round a hollow drum, read from
			# outside as stacked bands of concrete parapet with dark gaps between
			# big drums: they overhang their footprint (the player picks how big)
			var r: float = minf(w, d) / 2.0 * { "M": 1.45, "L": 2.0, "XL": 2.6 }.get(f.opt(ft, "size"), 1.45)
			var c := Vector3(w / 2.0, 0, d / 2.0)
			var ramp_m := tex_mat("rough_concrete", Color(0.84, 0.82, 0.78) if _style(f, ft) == "concrete" else Color(0.58, 0.6, 0.63), 2.0, true)
			var gap_m := mat(Color(0.16, 0.16, 0.17), 0.9)
			var cyl := func(y: float, hh: float, rr: float, m: Material, ring := false) -> void:
				var mi := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = rr
				cm.bottom_radius = rr
				cm.height = hh
				cm.radial_segments = 28
				cm.cap_top = not ring
				cm.cap_bottom = not ring
				mi.mesh = cm
				mi.material_override = m
				mi.position = c + Vector3(0, y + hh / 2.0, 0)
				g.add_child(mi)
			# the dark core you see through the gaps
			cyl.call(0.0, h, r * 0.86, gap_m)
			var pitch_h := 0.55   # one band per half turn of the ramp
			var y := 0.35
			while y < h - 0.1:
				cyl.call(y, 0.3, r, ramp_m, true)
				# a slight lean on alternate bands reads as the ramp's slope
				y += pitch_h
			# a lid and a door at the bottom
			cyl.call(h, 0.18, r * 1.02, ramp_m)
			lbox(g, c + Vector3(0, 0.18, r * 0.9), Vector3(0.45, 0.36, 0.2), gap_m)
		"escalator":
			# a pair of escalators in a glazed enclosure
			var run := sqrt(1.0 + h * h * 0.36)
			for e in [-0.2, 0.2]:
				var band := lbox(g, Vector3(0.5 + e, h / 2.0, 0.5), Vector3(0.28, 0.18, run * 1.4), mat(Color(0.25, 0.26, 0.28), 0.4, 0.6), 0.0)
				band.rotation.x = -atan2(h, 1.4)
				var side := lbox(g, Vector3(0.5 + e, h / 2.0 + 0.2, 0.5), Vector3(0.3, 0.3, run * 1.4), glass, 0.0)
				side.rotation.x = -atan2(h, 1.4)
			box(g, Vector3(0.0, h, 0.0), Vector3(1.0, h + 0.08, 1.0), steel)
		"lift":
			# a glass lift shaft with the car partway up
			for cx in [0.12, 0.88]:
				for cz in [0.12, 0.88]:
					box(g, Vector3(cx - 0.04, 0, cz - 0.04), Vector3(cx + 0.04, h + 0.4, cz + 0.04), steel)
			box(g, Vector3(0.12, 0, 0.12), Vector3(0.88, h + 0.4, 0.88), glass, false)
			var car_y := h * 0.4
			box(g, Vector3(0.2, car_y, 0.2), Vector3(0.8, car_y + 0.7, 0.8), mat(club, 0.4, 0.2))
			box(g, Vector3(0.05, h + 0.4, 0.05), Vector3(0.95, h + 0.55, 0.95), mat(Color(0.25, 0.26, 0.28), 0.5, 0.4))


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
					_stall(g, Color(0.93, 0.9, 0.84), home, Color(0.97, 0.97, 0.95), "FOOD")
		"bar":
			if st == "modern":
				box(g, Vector3(0.05, 0.0, 0.1), Vector3(0.95, 0.75, 0.9), mat(Color(0.5, 0.8, 0.9), 0.1, 0.3, 0.0, 0.55))
				box(g, Vector3(0.1, 0.0, 0.15), Vector3(0.9, 0.4, 0.4), mat(Color(0.15, 0.15, 0.18), 0.3))
				box(g, Vector3(0.1, 0.62, 0.08), Vector3(0.9, 0.72, 0.12), mat(Color(0.2, 0.9, 1.0), 0.2, 0.0, 2.0))
			else:
				_stall(g, Color(0.32, 0.2, 0.12), Color(0.12, 0.28, 0.16), Color(0.85, 0.75, 0.45), "BAR")
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
				_lettering(g, "CLUB STORE", Vector3(w / 2.0, 0.82, 0.02), _club.secondary_color, 0.006, 40, 0.0, "inside")
			else:
				for x in range(int(w)):
					box(g, Vector3(x + 0.1, 0.0, 0.3), Vector3(x + 0.9, 0.35, 0.7), mat(Color(0.4, 0.3, 0.2)))
					box(g, Vector3(x + 0.2, 0.35, 0.4), Vector3(x + 0.45, 0.42, 0.6), mat(home))
					box(g, Vector3(x + 0.55, 0.35, 0.4), Vector3(x + 0.8, 0.42, 0.6), mat(_club.secondary_color))
				box(g, Vector3(0.0, 0.8, 0.1), Vector3(w, 0.86, d - 0.1), mat(home, 0.6))
				for x in [0.1, w - 0.15]:
					box(g, Vector3(x, 0.0, 0.15), Vector3(x + 0.05, 0.8, 0.2), mat(Color(0.3, 0.3, 0.3)))
		"restroom":
			# a tiled toilet block: two doorways with signs, a vent strip, a lit sign
			var tile_c := Color(0.92, 0.93, 0.95) if st == "modern" else Color(0.72, 0.78, 0.86)
			box(g, Vector3(0.06, 0.0, 0.08), Vector3(0.94, 0.82, 0.92), tex_mat("rough_concrete", tile_c, 0.5, true))
			box(g, Vector3(0.02, 0.82, 0.04), Vector3(0.98, 0.88, 0.96), mat(Color(0.25, 0.27, 0.3), 0.5))
			for dx in [0.28, 0.72]:
				box(g, Vector3(dx - 0.13, 0.0, 0.05), Vector3(dx + 0.13, 0.55, 0.09), mat(Color(0.12, 0.13, 0.15), 0.6))
				box(g, Vector3(dx - 0.05, 0.6, 0.06), Vector3(dx + 0.05, 0.7, 0.075), mat(Color(0.2, 0.45, 0.9) if dx < 0.5 else Color(0.9, 0.3, 0.5), 0.4, 0.0, 0.8))
			box(g, Vector3(0.1, 0.74, 0.06), Vector3(0.9, 0.78, 0.075), mat(Color(0.3, 0.32, 0.34), 0.5))
			_lettering(g, "WC", Vector3(0.5, 0.65, 0.04), Color.WHITE, 0.004, 32, PI)
		"first_aid":
			box(g, Vector3(0.08, 0.0, 0.08), Vector3(0.92, 0.78, 0.92), tex_mat("rough_concrete", Color(0.97, 0.97, 0.96), 0.5, true))
			box(g, Vector3(0.04, 0.78, 0.04), Vector3(0.96, 0.84, 0.96), mat(Color(0.2, 0.55, 0.3), 0.5))
			box(g, Vector3(0.32, 0.0, 0.05), Vector3(0.68, 0.58, 0.09), mat(Color(0.75, 0.85, 0.9), 0.1, 0.2))
			box(g, Vector3(0.44, 0.6, 0.05), Vector3(0.56, 0.76, 0.07), mat(Color(1, 1, 1), 0.4, 0.0, 0.6))
			box(g, Vector3(0.42, 0.65, 0.04), Vector3(0.58, 0.71, 0.065), mat(Color(0.1, 0.7, 0.3), 0.4, 0.0, 0.8))
			box(g, Vector3(0.47, 0.62, 0.04), Vector3(0.53, 0.74, 0.065), mat(Color(0.1, 0.7, 0.3), 0.4, 0.0, 0.8))
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


## A bronze figure about 0.95 tall standing at `base`, facing +Z:
## "celebration" arms raised, "founder" in a long coat, else a player with a ball.
## A memorial: a garden of remembrance, a wall of plaques or an eternal flame,
## with the player's dedication cut into the stone and wreaths laid in front.
func _memorial(g: Node3D, f: Facility, ft: FacilityType, w: float, d: float) -> void:
	var st := _style(f, ft)
	var text := f.opt(ft, "text")
	if text == "":
		text = "IN MEMORY"
	var granite := tex_mat("granite_wall", Color(0.5, 0.5, 0.52), 1.0)
	var paving := tex_mat("rough_concrete", Color(0.7, 0.68, 0.64), 2.0, true)
	var gold := mat(Color(0.78, 0.62, 0.3), 0.3, 0.9)
	var engrave := func(pos: Vector3, cap: float) -> void:
		var n := Signs.build(g, { "text": text, "mount": "letters", "font": "classic", "depth": 0.01, "scale": cap / 0.55 }, Color(0.92, 0.82, 0.5), Color(0.92, 0.82, 0.5), w - 0.3, _glow, _night_light)
		n.position = pos
	box(g, Vector3(0.05, 0.0, 0.05), Vector3(w - 0.05, 0.05, d - 0.05), paving)
	var red := mat(Color(0.75, 0.08, 0.1), 0.7)
	var leaf := mat(Color(0.16, 0.32, 0.16), 0.8)
	var wreath := func(c: Vector3, r: float) -> void:
		var tm := TorusMesh.new()
		tm.inner_radius = r * 0.7
		tm.outer_radius = r
		var mi := MeshInstance3D.new()
		mi.mesh = tm
		mi.material_override = leaf
		mi.position = c
		mi.rotation.x = PI / 2.0 - 0.35
		g.add_child(mi)
		for k in 6:
			var a := TAU * k / 6.0
			lbox(g, c + Vector3(cos(a) * r * 0.85, sin(a) * r * 0.8, 0.04), Vector3(0.05, 0.05, 0.05), red)
	match st:
		"wall":
			# a long curved granite wall of name plaques
			box(g, Vector3(0.15, 0.05, 0.25), Vector3(w - 0.15, 1.05, 0.5), granite)
			box(g, Vector3(0.1, 1.05, 0.2), Vector3(w - 0.1, 1.12, 0.55), mat(Color(0.32, 0.32, 0.34), 0.4))
			for ix in 6:
				for iy in 3:
					var px := 0.35 + ix * (w - 0.7) / 5.0
					box(g, Vector3(px - 0.11, 0.25 + iy * 0.25, 0.5), Vector3(px + 0.11, 0.42 + iy * 0.25, 0.515), gold)
			engrave.call(Vector3(w / 2.0, 0.88, 0.52), 0.182)
			for k in 3:
				wreath.call(Vector3(0.6 + k * (w - 1.2) / 2.0, 0.22, 0.75), 0.14)
		"flame":
			# a bronze bowl on a stone column with a flame that never goes out
			box(g, Vector3(w / 2.0 - 0.3, 0.05, d / 2.0 - 0.3), Vector3(w / 2.0 + 0.3, 0.2, d / 2.0 + 0.3), granite)
			var col := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.16
			cm.bottom_radius = 0.2
			cm.height = 0.9
			col.mesh = cm
			col.material_override = granite
			col.position = Vector3(w / 2.0, 0.65, d / 2.0)
			g.add_child(col)
			var bowl := MeshInstance3D.new()
			var bm := CylinderMesh.new()
			bm.top_radius = 0.3
			bm.bottom_radius = 0.12
			bm.height = 0.16
			bowl.mesh = bm
			bowl.material_override = mat(Color(0.5, 0.36, 0.2), 0.35, 0.8)
			bowl.position = Vector3(w / 2.0, 1.18, d / 2.0)
			g.add_child(bowl)
			var fm := StandardMaterial3D.new()
			fm.albedo_color = Color(1.0, 0.6, 0.15)
			fm.emission_enabled = true
			fm.emission = Color(1.0, 0.5, 0.1)
			fm.emission_energy_multiplier = 2.5
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var flame := MeshInstance3D.new()
			var pm := SphereMesh.new()
			pm.radius = 0.14
			pm.height = 0.42
			flame.mesh = pm
			flame.material_override = fm
			flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			flame.position = Vector3(w / 2.0, 1.42, d / 2.0)
			g.add_child(flame)
			var lt := OmniLight3D.new()
			lt.light_color = Color(1.0, 0.6, 0.25)
			lt.omni_range = 2.5
			lt.light_energy = 0.6
			lt.position = Vector3(w / 2.0, 1.6, d / 2.0)
			g.add_child(lt)
			_night_light(lt)
			# the dedication on a low stone in front
			box(g, Vector3(0.1, 0.05, d - 0.4), Vector3(w - 0.1, 0.38, d - 0.2), granite)
			engrave.call(Vector3(w / 2.0, 0.2, d - 0.19), 0.154)
			wreath.call(Vector3(w / 2.0 - 0.55, 0.2, d / 2.0 + 0.4), 0.13)
		_:
			# a garden of remembrance: clipped hedges round a lawn, a stone
			# tablet and benches
			var lawn := mat(Color(0.25, 0.42, 0.18), 0.9)
			box(g, Vector3(0.2, 0.05, 0.2), Vector3(w - 0.2, 0.08, d - 0.2), lawn)
			var hedge := mat(Color(0.12, 0.26, 0.12), 0.95)
			box(g, Vector3(0.05, 0.05, 0.05), Vector3(w - 0.05, 0.4, 0.2), hedge)
			box(g, Vector3(0.05, 0.05, 0.05), Vector3(0.2, 0.4, d - 0.6), hedge)
			box(g, Vector3(w - 0.2, 0.05, 0.05), Vector3(w - 0.05, 0.4, d - 0.6), hedge)
			box(g, Vector3(w / 2.0 - 0.5, 0.05, 0.6), Vector3(w / 2.0 + 0.5, 0.9, 0.78), granite)
			engrave.call(Vector3(w / 2.0, 0.55, 0.79), 0.154)
			_crest(g, Vector3(w / 2.0, 0.85, 0.79), 0.28, 0.0, false, "flat", "none")
			for k in 2:
				wreath.call(Vector3(w / 2.0 - 0.3 + k * 0.6, 0.2, 0.95), 0.12)
			for e in [0.45, w - 0.45]:
				box(g, Vector3(e - 0.25, 0.15, d - 0.5), Vector3(e + 0.25, 0.2, d - 0.35), mat(Color(0.45, 0.32, 0.2), 0.8))
			for e in [0.4, w - 0.4]:
				var flower := mat(Color(0.85, 0.2, 0.25) if e < 1.0 else Color(0.95, 0.85, 0.3), 0.8)
				box(g, Vector3(e - 0.15, 0.08, 1.2), Vector3(e + 0.15, 0.2, 1.5), flower)


## The ground's name in big letters: free-standing 3D letters on a plinth, an
## arch over a path, or a tall totem. Lit the player's way.
func _ground_sign(g: Node3D, f: Facility, ft: FacilityType, w: float, d: float) -> void:
	var st := _style(f, ft)
	var text := f.opt(ft, "text")
	if text == "":
		text = ground_name if ground_name != "" else _club.stadium_name
	var light := f.opt(ft, "light")
	var c1 := _club.primary_color
	var c2 := _club.secondary_color
	var zc := d / 2.0
	var stone := tex_mat("rough_concrete", Color(0.55, 0.55, 0.56), 1.0, true)
	match st:
		"arch":
			var steel := mat(c1.darkened(0.25), 0.4, 0.6)
			for e in [0.15, w - 0.15]:
				lbox(g, Vector3(e, 1.3, zc), Vector3(0.24, 2.6, 0.24), steel)
			lbox(g, Vector3(w / 2.0, 2.75, zc), Vector3(w + 0.1, 0.5, 0.2), steel)
			var sg := Signs.build(g, { "text": text, "mount": "letters", "font": "future", "depth": 0.08, "scale": 0.62, "light": light }, c2, c1, w - 0.3, _glow, _night_light)
			sg.position = Vector3(w / 2.0, 2.75, zc + 0.12)
			var back := Signs.build(g, { "text": text, "mount": "letters", "font": "future", "depth": 0.08, "scale": 0.62, "light": light }, c2, c1, w - 0.3, _glow, _night_light)
			back.position = Vector3(w / 2.0, 2.75, zc - 0.12)
			back.rotation.y = PI
		"totem":
			# a slim tower with the name running up it and the crest on top
			var tw := 0.9
			lbox(g, Vector3(w / 2.0, 0.1, zc), Vector3(tw + 0.4, 0.2, 0.8), stone)
			lbox(g, Vector3(w / 2.0, 2.0, zc), Vector3(tw, 3.8, 0.5), mat(c1.darkened(0.1), 0.5))
			_crest(g, Vector3(w / 2.0, 3.35, zc + 0.26), 0.7, 0.0, false, "solid", "none")
			var sg := Signs.build(g, { "text": text, "mount": "letters", "font": "narrow", "depth": 0.05, "scale": 0.5, "light": light }, c2, c1, 3.0, _glow, _night_light)
			sg.position = Vector3(w / 2.0 + 0.0, 1.55, zc + 0.27)
			sg.rotation.z = PI / 2.0
		_:
			# free-standing 3D letters on a low plinth (lit from below)
			lbox(g, Vector3(w / 2.0, 0.12, zc), Vector3(w, 0.24, 0.55), stone)
			var sg := Signs.build(g, { "text": text, "mount": "letters", "font": "blocks", "depth": 0.3, "scale": 1.25, "light": light }, c1, c2, w - 0.1, _glow, _night_light)
			sg.position = Vector3(w / 2.0, 0.24 + 0.4, zc)


var _pitch_rect := Rect2()


## A scoreboard on its own tower, for an open corner of the ground: it turns
## to face the middle of the pitch.
func _score_tower(g: Node3D, f: Facility, ft: FacilityType, w: float, d: float) -> void:
	var st := _style(f, ft)
	var c := Vector3(w / 2.0, 0, d / 2.0)
	var h := 7.0
	var leg_m: Material = tex_mat("rough_concrete", Color(0.75, 0.75, 0.73), 2.0, true) if st == "concrete" else mat(Color(0.3, 0.32, 0.35), 0.4, 0.7)
	if st == "concrete":
		lbox(g, c + Vector3(0, h / 2.0, 0), Vector3(1.0, h, 1.0), leg_m)
	else:
		for e in [Vector3(-0.7, 0, -0.5), Vector3(0.7, 0, -0.5), Vector3(-0.7, 0, 0.5), Vector3(0.7, 0, 0.5)]:
			lbox(g, c + e + Vector3(0, h / 2.0, 0), Vector3(0.12, h, 0.12), leg_m)
		for y in [2.0, 4.0, 6.0]:
			lbox(g, c + Vector3(0, y, 0), Vector3(1.5, 0.08, 1.1), leg_m)
	# the screen, turned to face the centre spot
	var head := Node3D.new()
	head.position = c + Vector3(0, h + 1.3, 0)
	g.add_child(head)
	var world := g.to_global(c) if g.is_inside_tree() else Vector3(f.pos.x + c.x, 0, f.pos.y + c.z)
	var to := Vector2(_pitch_rect.get_center().x - world.x, _pitch_rect.get_center().y - world.z)
	head.rotation.y = atan2(to.x, to.y)
	lbox(head, Vector3.ZERO, Vector3(4.2, 2.6, 0.4), mat(Color(0.1, 0.1, 0.12), 0.5))
	var scr := StandardMaterial3D.new()
	scr.albedo_color = Color(0.04, 0.06, 0.1)
	scr.emission_enabled = true
	scr.emission = _club.primary_color.lerp(Color(0.1, 0.2, 0.4), 0.5)
	_glow(scr, 0.8, 1.6)
	lbox(head, Vector3(0, 0, 0.21), Vector3(3.9, 2.3, 0.02), scr)
	var lab := _label(head, "%s  0 - 0" % (_club.short_name if _club.short_name != "" else _club.club_name.substr(0, 3)).to_upper(), Vector3(0, 0, 0.23), 64, Color(1.0, 0.85, 0.3), false, 0.008)
	lab.outline_size = 0
	_crest(head, Vector3(0, 1.75, 0.0), 0.9, 0.0, false, "solid", "none")


## A training pitch: smaller, its own grass (or a darker artificial surface),
## white lines, small goals, cones and a mesh fence round it.
func _training_pitch(g: Node3D, f: Facility, ft: FacilityType, w: float, d: float) -> void:
	var art := _style(f, ft) == "artificial"
	box(g, Vector3(0.05, 0.0, 0.05), Vector3(w - 0.05, 0.03, d - 0.05), tex_mat("grass_ground", Color(0.22, 0.45, 0.2) if art else Color(0.35, 0.55, 0.25), 1.5, true))
	# mown stripes on grass
	if not art:
		var x := 0.6
		var k := 0
		while x < w - 0.6:
			if k % 2 == 0:
				box(g, Vector3(x, 0.031, 0.6), Vector3(minf(x + 1.0, w - 0.6), 0.033, d - 0.6), mat(Color(0.3, 0.5, 0.22), 0.9), false)
			x += 1.0
			k += 1
	var line := mat(Color(0.95, 0.95, 0.95), 0.7)
	for zz in [0.6, d - 0.6]:
		box(g, Vector3(0.6, 0.034, zz - 0.03), Vector3(w - 0.6, 0.04, zz + 0.03), line, false)
	for xx in [0.6, w - 0.6]:
		box(g, Vector3(xx - 0.03, 0.034, 0.6), Vector3(xx + 0.03, 0.04, d - 0.6), line, false)
	box(g, Vector3(w / 2.0 - 0.03, 0.034, 0.6), Vector3(w / 2.0 + 0.03, 0.04, d - 0.6), line, false)
	var post := mat(Color(0.95, 0.95, 0.95), 0.4)
	for gx in [0.6, w - 0.6]:
		for e in [-0.6, 0.6]:
			lbox(g, Vector3(gx, 0.3, d / 2.0 + e), Vector3(0.05, 0.6, 0.05), post)
		lbox(g, Vector3(gx, 0.6, d / 2.0), Vector3(0.05, 0.05, 1.25), post)
	var cone := mat(Color(1.0, 0.5, 0.1), 0.6)
	for i in 6:
		lbox(g, Vector3(2.0 + i * 0.5, 0.06, d * 0.3), Vector3(0.08, 0.12, 0.08), cone)
	if f.opt(ft, "fence") == "mesh":
		var fm := mat(Color(0.15, 0.35, 0.2), 0.6, 0.3, 0.0, 0.55)
		for pr in [[Vector3(w / 2.0, 0.9, 0.05), Vector3(w - 0.1, 1.8, 0.03)], [Vector3(w / 2.0, 0.9, d - 0.05), Vector3(w - 0.1, 1.8, 0.03)], [Vector3(0.05, 0.9, d / 2.0), Vector3(0.03, 1.8, d - 0.1)], [Vector3(w - 0.05, 0.9, d / 2.0), Vector3(0.03, 1.8, d - 0.1)]]:
			lbox(g, pr[0], pr[1], fm)


## A fan park outside the ground: a stage with a big screen at the back, bar
## tents in club colours, picnic tables and festoon lights strung overhead.
func _fan_park(g: Node3D, f: Facility, ft: FacilityType, w: float, d: float) -> void:
	var st := _style(f, ft)
	var c1 := _club.primary_color
	var c2 := _club.secondary_color
	box(g, Vector3(0.05, 0.0, 0.05), Vector3(w - 0.05, 0.03, d - 0.05), tex_mat("square_concrete_pavers", Color(1, 1, 1), 1.0) if st == "festival" else tex_mat("grass_ground", Color(0.35, 0.5, 0.22), 1.0, true))
	var steel := mat(Color(0.2, 0.2, 0.22), 0.4, 0.6)
	# the stage and screen along the back
	box(g, Vector3(1.4, 0.0, 0.1), Vector3(w - 1.4, 0.45, 1.0), mat(Color(0.12, 0.12, 0.13), 0.6))
	for x in [1.5, w - 1.5]:
		lbox(g, Vector3(x, 1.4, 0.2), Vector3(0.12, 2.8, 0.12), steel)
	lbox(g, Vector3(w / 2.0, 2.8, 0.2), Vector3(w - 2.8, 0.12, 0.14), steel)
	var scr := StandardMaterial3D.new()
	scr.albedo_color = Color(0.05, 0.08, 0.12)
	scr.emission_enabled = true
	scr.emission = c1.lerp(Color(0.2, 0.6, 0.3), 0.5)
	_glow(scr, 0.8, 1.8)
	lbox(g, Vector3(w / 2.0, 1.65, 0.24), Vector3(w - 3.4, 1.6, 0.06), scr)
	# bar tents with peaked roofs either side
	for e in [0.0, 1.0]:
		var tx := 0.7 if e == 0.0 else w - 0.7
		box(g, Vector3(tx - 0.6, 0.0, 0.3), Vector3(tx + 0.6, 0.9, 1.5), mat(Color(0.95, 0.95, 0.92), 0.8))
		var roof := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(1.3, 0.5, 1.3)
		roof.mesh = pm
		roof.material_override = mat(c1 if e == 0.0 else c2, 0.7)
		roof.position = Vector3(tx, 1.15, 0.9)
		g.add_child(roof)
		lbox(g, Vector3(tx, 0.45, 1.52), Vector3(1.1, 0.06, 0.12), mat(Color(0.45, 0.32, 0.2), 0.7))
	# picnic tables in rows
	var wood := mat(Color(0.5, 0.36, 0.24), 0.8)
	var tables: Array[Transform3D] = []
	var z := 2.0
	while z < d - 0.4:
		var x := 1.0
		while x < w - 0.8:
			tables.append(Transform3D(Basis().scaled(Vector3(0.9, 0.05, 0.35)), Vector3(x, 0.38, z)))
			for bz in [-0.32, 0.32]:
				tables.append(Transform3D(Basis().scaled(Vector3(0.9, 0.04, 0.14)), Vector3(x, 0.22, z + bz)))
			x += 1.3
		z += 1.0
	_mm(g, tables, wood)
	# festoon lights on poles round the edge
	var bulb := StandardMaterial3D.new()
	bulb.albedo_color = Color(1.0, 0.9, 0.6)
	bulb.emission_enabled = true
	bulb.emission = Color(1.0, 0.8, 0.45)
	_glow(bulb, 0.3, 3.0)
	var bulbs: Array[Transform3D] = []
	for corner in [Vector2(0.15, 1.6), Vector2(w - 0.15, 1.6), Vector2(w - 0.15, d - 0.15), Vector2(0.15, d - 0.15)]:
		lbox(g, Vector3(corner.x, 1.1, corner.y), Vector3(0.06, 2.2, 0.06), steel)
	for k in 24:
		var t := k / 23.0
		var p := Vector3(lerpf(0.15, w - 0.15, t), 2.1 - sin(t * PI * 3.0) * 0.0 - 0.25 * sin(fposmod(t * 3.0, 1.0) * PI), lerpf(1.6, d - 0.15, t))
		bulbs.append(Transform3D(Basis().scaled(Vector3(0.07, 0.07, 0.07)), p))
	_mm(g, bulbs, bulb)


## Water outside the ground: a round stone fountain, a still pond with reeds,
## or a paved square with jets springing out of the ground.
func _fountain(g: Node3D, f: Facility, ft: FacilityType, w: float, d: float) -> void:
	var st := _style(f, ft)
	var stone := tex_mat("large_sandstone_blocks", Color(1, 1, 1), 1.0)
	var c := Vector3(w / 2.0, 0, d / 2.0)
	var water := _water_material()
	var cyl := func(pos: Vector3, r: float, hh: float, m: Material) -> void:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = hh
		cm.radial_segments = 28
		mi.mesh = cm
		mi.material_override = m
		mi.position = pos
		g.add_child(mi)
	var spray := StandardMaterial3D.new()
	spray.albedo_color = Color(0.9, 0.95, 1.0, 0.45)
	spray.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spray.roughness = 0.1
	spray.emission_enabled = true
	spray.emission = Color(0.6, 0.75, 0.9)
	_glow(spray, 0.15, 1.2)
	match st:
		"pond":
			cyl.call(c + Vector3(0, 0.02, 0), minf(w, d) * 0.48, 0.04, tex_mat("rough_concrete", Color(0.55, 0.52, 0.48), 1.0, true))
			cyl.call(c + Vector3(0, 0.045, 0), minf(w, d) * 0.44, 0.02, water)
			var rng := RandomNumberGenerator.new()
			rng.seed = f.pos.x * 31 + f.pos.y
			for i in 14:
				var a := rng.randf() * TAU
				var rr := minf(w, d) * 0.42
				lbox(g, c + Vector3(cos(a) * rr, 0.2, sin(a) * rr), Vector3(0.04, 0.4, 0.04), mat(Color(0.35, 0.45, 0.2), 0.9))
		"jets":
			box(g, Vector3(0.05, 0.0, 0.05), Vector3(w - 0.05, 0.04, d - 0.05), tex_mat("square_concrete_pavers", Color(1.0, 1.0, 1.0), 1.0))
			for ix in 3:
				for iz in 3:
					var p := Vector3(0.4 + ix * (w - 0.8) / 2.0, 0, 0.4 + iz * (d - 0.8) / 2.0)
					var jh := 0.6 + 0.4 * float((ix + iz) % 2)
					lbox(g, p + Vector3(0, jh / 2.0, 0), Vector3(0.05, jh, 0.05), spray)
					cyl.call(p + Vector3(0, 0.045, 0), 0.12, 0.01, water)
		_:
			# a round basin with a two-tier centrepiece
			var r := minf(w, d) * 0.47
			cyl.call(c + Vector3(0, 0.15, 0), r, 0.3, stone)
			cyl.call(c + Vector3(0, 0.31, 0), r - 0.1, 0.02, water)
			cyl.call(c + Vector3(0, 0.6, 0), 0.12, 0.6, stone)
			cyl.call(c + Vector3(0, 0.92, 0), 0.4, 0.08, stone)
			cyl.call(c + Vector3(0, 1.2, 0), 0.07, 0.5, stone)
			lbox(g, c + Vector3(0, 1.6, 0), Vector3(0.06, 0.5, 0.06), spray)
			var sp := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.38
			sm.height = 0.3
			sp.mesh = sm
			sp.material_override = spray
			sp.position = c + Vector3(0, 1.0, 0)
			g.add_child(sp)


## A glazed atrium: a multi-storey glass entrance block (for a corner of the
## ground or beside a stand), with floor slabs showing through, a club band and
## lettering over the doors.
func _atrium(g: Node3D, f: Facility, ft: FacilityType, w: float, d: float) -> void:
	var st := _style(f, ft)
	var hh: float = { "low": 4.0, "mid": 7.0, "tall": 11.0 }.get(f.opt(ft, "height"), 7.0)
	var text := f.opt(ft, "text")
	if text == "":
		text = _club.club_name
	var glass := StandardMaterial3D.new()   # its own: it glows at night
	glass.albedo_color = Color(0.32, 0.45, 0.52, 0.72)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.6
	var frame := mat(Color(0.7, 0.72, 0.74), 0.35, 0.7)
	var slab := mat(Color(0.82, 0.82, 0.8), 0.8)
	var inset := 0.15
	# floors behind the glass
	var fy := 0.0
	while fy < hh - 0.5:
		box(g, Vector3(inset + 0.1, fy, inset + 0.1), Vector3(w - inset - 0.1, fy + 0.18, d - inset - 0.1), slab)
		fy += 1.4
	box(g, Vector3(inset, 0, inset), Vector3(w - inset, hh, d - inset), glass)
	box(g, Vector3(0.0, hh, 0.0), Vector3(w, hh + 0.35, d), _fascia())
	if st == "brick_glass":
		var brick := tex_mat("red_brick_03", Color(1, 1, 1), 1.0)
		for corner in [Vector2(0, 0), Vector2(w - 0.7, 0), Vector2(0, d - 0.7), Vector2(w - 0.7, d - 0.7)]:
			box(g, Vector3(corner.x, 0, corner.y), Vector3(corner.x + 0.7, hh, corner.y + 0.7), brick)
	# mullions on all four faces
	var step := 0.45 if st == "glass_fins" else 0.9
	var fin_d := 0.25 if st == "glass_fins" else 0.05
	var xf: Array[Transform3D] = []
	var x := inset
	while x <= w - inset + 0.01:
		for zz in [inset - fin_d / 2.0, d - inset + fin_d / 2.0]:
			xf.append(Transform3D(Basis().scaled(Vector3(0.05, hh, fin_d)), Vector3(x, hh / 2.0, zz)))
		x += step
	var z := inset
	while z <= d - inset + 0.01:
		for xx in [inset - fin_d / 2.0, w - inset + fin_d / 2.0]:
			xf.append(Transform3D(Basis().scaled(Vector3(fin_d, hh, 0.05)), Vector3(xx, hh / 2.0, z)))
		z += step
	var y := 1.4
	while y < hh:
		for zz in [inset, d - inset]:
			xf.append(Transform3D(Basis().scaled(Vector3(w - 2.0 * inset, 0.06, 0.08)), Vector3(w / 2.0, y, zz)))
		for xx in [inset, w - inset]:
			xf.append(Transform3D(Basis().scaled(Vector3(0.08, 0.06, d - 2.0 * inset)), Vector3(xx, y, d / 2.0)))
		y += 1.4
	_mm(g, xf, frame)
	# a canopy and lettering over the doors on the +z face
	box(g, Vector3(0.3, 1.3, d - 0.1), Vector3(w - 0.3, 1.42, d + 0.6), frame)
	var sg := Signs.build(g, { "text": text, "mount": "letters", "font": "future", "depth": 0.06, "scale": 0.5, "light": "inside" }, Color(0.97, 0.97, 0.97), _club.primary_color, w - 0.4, _glow, _night_light)
	sg.position = Vector3(w / 2.0, hh + 0.17, d + 0.03)
	# the glass glows warm at night
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.85, 0.6)
	_glow(glass, 0.0, 0.5)


## Named gates: two piers carrying an arch with the name the player chose,
## in wrought iron (Shankly-style), a stone triumphal arch or a modern steel portal.
func _club_gates(g: Node3D, f: Facility, ft: FacilityType, w: float, d: float) -> void:
	var st := _style(f, ft)
	var text := f.opt(ft, "text")
	if text == "":
		text = _club.club_name
	var zc := d / 2.0
	var c1 := _club.primary_color
	var c2 := _club.secondary_color
	match st:
		"stone_arch":
			var stone := tex_mat("large_sandstone_blocks", Color(1, 1, 1), 1.0)
			for e in [0.0, w - 0.55]:
				box(g, Vector3(e, 0.0, zc - 0.3), Vector3(e + 0.55, 1.6, zc + 0.3), stone)
				box(g, Vector3(e - 0.05, 1.6, zc - 0.35), Vector3(e + 0.6, 1.7, zc + 0.35), stone)
			box(g, Vector3(0.0, 1.7, zc - 0.3), Vector3(w, 2.2, zc + 0.3), stone)
			box(g, Vector3(-0.05, 2.2, zc - 0.35), Vector3(w + 0.05, 2.28, zc + 0.35), stone)
			_lettering(g, text, Vector3(w / 2.0, 1.95, zc + 0.31), Color(0.2, 0.18, 0.15), 0.004, 40, 0.0, "flood", "classic")
			_crest(g, Vector3(w / 2.0, 2.5, zc), 0.45, 0.0, false, "solid", "none")
			# iron gates in the opening
			var iron := mat(Color(0.08, 0.08, 0.09), 0.5, 0.6)
			var bars: Array[Transform3D] = []
			var x := 0.65
			while x < w - 0.6:
				bars.append(Transform3D(Basis().scaled(Vector3(0.035, 1.5, 0.035)), Vector3(x, 0.75, zc)))
				x += 0.14
			_mm(g, bars, iron)
		"modern":
			var steel := mat(c1.darkened(0.15), 0.35, 0.6)
			for e in [0.15, w - 0.15]:
				lbox(g, Vector3(e, 1.1, zc), Vector3(0.3, 2.2, 0.3), steel)
			lbox(g, Vector3(w / 2.0, 2.3, zc), Vector3(w + 0.2, 0.4, 0.34), steel)
			var lt := Signs.build(g, { "text": text, "mount": "letters", "font": "future", "depth": 0.05, "scale": 0.5, "light": "inside" }, c2, c1, w - 0.2, _glow, _night_light)
			lt.position = Vector3(w / 2.0, 2.3, zc + 0.19)
			lbox(g, Vector3(w / 2.0, 0.02, zc), Vector3(w, 0.04, 0.6), mat(Color(0.3, 0.3, 0.32), 0.6))
		_:
			# wrought iron: brick piers with lamps, double gates and an arch of
			# scrollwork carrying the name in gilded letters
			var brick := tex_mat("red_brick_03", Color(1, 1, 1), 1.0)
			var iron := mat(Color(0.06, 0.06, 0.07), 0.45, 0.6)
			var gilt := mat(Color(0.85, 0.68, 0.28), 0.3, 0.9)
			for e in [0.0, w - 0.4]:
				box(g, Vector3(e, 0.0, zc - 0.2), Vector3(e + 0.4, 1.5, zc + 0.2), brick)
				box(g, Vector3(e - 0.04, 1.5, zc - 0.24), Vector3(e + 0.44, 1.58, zc + 0.24), tex_mat("rough_concrete", Color(0.82, 0.8, 0.75), 1.0, true))
				var lamp := lbox(g, Vector3(e + 0.2, 1.72, zc), Vector3(0.14, 0.22, 0.14), mat(Color(1.0, 0.9, 0.65), 0.2, 0.0, 1.2))
				lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var bars: Array[Transform3D] = []
			var x := 0.5
			while x < w - 0.45:
				var arch_h := 1.4 + 0.25 * sin(PI * (x - 0.4) / (w - 0.8))
				bars.append(Transform3D(Basis().scaled(Vector3(0.03, arch_h, 0.03)), Vector3(x, arch_h / 2.0, zc)))
				x += 0.12
			_mm(g, bars, iron)
			for yy in [0.2, 0.9]:
				lbox(g, Vector3(w / 2.0, yy, zc), Vector3(w - 0.8, 0.04, 0.04), iron)
			# the arch over the top with the name
			var segs := 14
			for k in segs:
				var t0 := float(k) / segs
				var t1 := float(k + 1) / segs
				var p0 := Vector3(lerpf(0.2, w - 0.2, t0), 2.1 + 0.45 * sin(PI * t0), zc)
				var p1 := Vector3(lerpf(0.2, w - 0.2, t1), 2.1 + 0.45 * sin(PI * t1), zc)
				_beam(g, p0, p1, 0.05, iron)
			for e in [0.2, w - 0.2]:
				lbox(g, Vector3(e, 1.85, zc), Vector3(0.05, 0.55, 0.05), iron)
			lbox(g, Vector3(w / 2.0, 2.1, zc), Vector3(w - 0.4, 0.04, 0.04), iron)
			var lt := Signs.build(g, { "text": text, "mount": "letters", "font": "classic", "depth": 0.03, "scale": 0.62 }, Color(0.85, 0.68, 0.28), c1, w - 0.5, _glow, _night_light)
			lt.position = Vector3(w / 2.0, 2.3, zc + 0.02)
			# a gilded crest on each gate
			for e in [w / 2.0 - 0.55, w / 2.0 + 0.55]:
				lbox(g, Vector3(e, 0.75, zc + 0.03), Vector3(0.24, 0.24, 0.02), gilt)


func _sculpture(g: Node3D, base: Vector3, style: String, bronze: Material) -> void:
	var limb := func(a: Vector3, b: Vector3, r: float) -> void:
		var c := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = r
		cm.height = (b - a).length() + 2.0 * r
		cm.radial_segments = 12
		cm.rings = 4
		c.mesh = cm
		c.material_override = bronze
		var up := (b - a).normalized()
		var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
		c.transform = Transform3D(Basis(side, up, side.cross(up)), base + (a + b) / 2.0)
		g.add_child(c)
	var coat := style == "founder"
	# legs
	limb.call(Vector3(-0.06, 0.02, 0), Vector3(-0.05, 0.42, 0), 0.045)
	limb.call(Vector3(0.06, 0.02, 0.0 if coat else 0.06), Vector3(0.05, 0.42, 0), 0.045)
	# body (a coat flares to the knees)
	limb.call(Vector3(0, 0.4, 0), Vector3(0, 0.68, 0), 0.1 if not coat else 0.12)
	if coat:
		limb.call(Vector3(0, 0.22, 0), Vector3(0, 0.45, 0), 0.115)
	# arms
	match style:
		"celebration":
			limb.call(Vector3(-0.1, 0.66, 0), Vector3(-0.22, 0.95, 0.02), 0.035)
			limb.call(Vector3(0.1, 0.66, 0), Vector3(0.22, 0.95, 0.02), 0.035)
		"founder":
			limb.call(Vector3(-0.12, 0.66, 0), Vector3(-0.15, 0.42, 0.02), 0.035)
			limb.call(Vector3(0.12, 0.66, 0), Vector3(0.08, 0.5, 0.1), 0.035)
		_:
			limb.call(Vector3(-0.11, 0.66, 0), Vector3(-0.2, 0.46, -0.04), 0.035)
			limb.call(Vector3(0.11, 0.66, 0), Vector3(0.2, 0.48, 0.05), 0.035)
			var ball := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.06
			sm.height = 0.12
			ball.mesh = sm
			ball.material_override = bronze
			ball.position = base + Vector3(0.08, 0.06, 0.12)
			g.add_child(ball)
	# neck and head
	limb.call(Vector3(0, 0.7, 0), Vector3(0, 0.74, 0), 0.035)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.07
	hm.height = 0.16
	head.mesh = hm
	head.material_override = bronze
	head.position = base + Vector3(0, 0.82, 0)
	g.add_child(head)


## A double-decker in club livery, 2.4 long, its side at `p` (local x along it).
func _bus(g: Node3D, p: Vector3) -> void:
	var body := mat(_club.primary_color, 0.45, 0.1)
	var dark_g := mat(Color(0.08, 0.1, 0.12), 0.1, 0.4)
	box(g, p + Vector3(0, 0.12, 0), p + Vector3(2.4, 1.05, 0.55), body)
	box(g, p + Vector3(-0.01, 0.45, -0.01), p + Vector3(2.41, 0.68, 0.56), dark_g)
	box(g, p + Vector3(-0.01, 0.8, -0.01), p + Vector3(2.41, 0.98, 0.56), dark_g)
	box(g, p + Vector3(0, 1.05, 0), p + Vector3(2.4, 1.1, 0.55), mat(Color(0.92, 0.92, 0.9), 0.5))
	box(g, p + Vector3(-0.01, 0.3, -0.01), p + Vector3(2.41, 0.36, 0.56), mat(_club.secondary_color, 0.5))
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.12
	wheel.bottom_radius = 0.12
	wheel.height = 0.08
	for wx in [0.4, 2.0]:
		for wz in [-0.01, 0.56]:
			var wm := MeshInstance3D.new()
			wm.mesh = wheel
			wm.material_override = mat(Color(0.08, 0.08, 0.08), 0.8)
			wm.rotation.x = PI / 2.0
			wm.position = p + Vector3(wx, 0.12, wz)
			g.add_child(wm)


const CAR_KINDS := ["car-kit/sedan", "car-kit/suv", "car-kit/hatchback-sports", "car-kit/van", "car-kit/taxi", "car-kit/sedan-sports", "car-kit/suv-luxury", "car-kit/sedan", "car-kit/hatchback-sports"]
const CAR_TINTS := [Color(1, 1, 1), Color(0.55, 0.6, 0.7), Color(0.25, 0.25, 0.28), Color(0.85, 0.85, 0.85), Color(0.6, 0.15, 0.12), Color(0.2, 0.3, 0.55), Color(0.4, 0.45, 0.35)]


## Parking laid out like a real car park, filling w x d at height y: rows of
## bays back to back with driving aisles between, white bay lines, aisle
## arrows, and `fill` of the bays taken. A surface car park also gets kerbed
## planting islands with trees, lamp posts, a pay station and an entry barrier.
var _car_surface := "asphalt"


func _car_rows(g: Node3D, w: float, d: float, y: float, rng: RandomNumberGenerator, fill: float, surface: bool, off := Vector3.ZERO) -> void:
	var bay_w := 0.62
	var bay_d := 1.3
	var aisle := 1.4
	if surface:
		var sm: Material = tex_mat("asphalt_01", Color(0.62, 0.7, 0.82), 3.0)
		match _car_surface:
			"gravel": sm = tex_mat("rough_concrete", Color(0.85, 0.78, 0.66), 1.0)
			"grass": sm = tex_mat("grass_ground", Color(0.45, 0.55, 0.3), 1.0, true)
		box(g, Vector3(0.0, y - 0.03, 0.0), Vector3(w, y, d), sm, false)
		box(g, Vector3(-0.05, y - 0.03, -0.05), Vector3(w + 0.05, y + 0.06, 0.0), mat(Color(0.72, 0.72, 0.7), 0.8))
		box(g, Vector3(-0.05, y - 0.03, d), Vector3(w + 0.05, y + 0.06, d + 0.05), mat(Color(0.72, 0.72, 0.7), 0.8))
	var line := mat(Color(0.93, 0.93, 0.9), 0.8)
	var lines: Array[Transform3D] = []
	var by_kind := {}
	var tints := {}
	# rows: a single row against each long edge, back-to-back rows between aisles
	var rows: Array = []     # [z_front_of_bay, facing +1 / -1]
	var z := 0.15
	rows.append([z, 1.0])
	z += bay_d + aisle
	while z + 2.0 * bay_d + aisle <= d - 0.15 + 0.01:
		rows.append([z, -1.0])
		rows.append([z + bay_d, 1.0])
		z += 2.0 * bay_d + aisle
	if z + bay_d <= d - 0.1:
		rows.append([z, -1.0])
	var island := surface and w > 6.0
	for r in rows:
		var z0: float = r[0]
		var face: float = r[1]
		var n := int((w - 0.3) / bay_w)
		for k in n:
			var x0 := 0.15 + k * bay_w
			if island and (k == n / 2 or k == n / 2 - 1):
				continue   # the planting island cuts through the middle
			lines.append(Transform3D(Basis().scaled(Vector3(0.03, 0.01, bay_d)), off + Vector3(x0, y + 0.005, z0 + bay_d / 2.0)))
			if rng.randf() < fill:
				var kind: String = CAR_KINDS[rng.randi_range(0, CAR_KINDS.size() - 1)]
				var sc := Kenney.scale_to(kind, 1.15)
				if not by_kind.has(kind):
					by_kind[kind] = []
					tints[kind] = []
				var yaw := (0.0 if face > 0 else PI) + rng.randf_range(-0.06, 0.06)
				by_kind[kind].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)),
					off + Vector3(x0 + bay_w / 2.0 + rng.randf_range(-0.04, 0.04), y, z0 + bay_d / 2.0)))
				tints[kind].append(CAR_TINTS[rng.randi_range(0, CAR_TINTS.size() - 1)])
		lines.append(Transform3D(Basis().scaled(Vector3(0.03, 0.01, bay_d)), off + Vector3(0.15 + n * bay_w, y + 0.005, z0 + bay_d / 2.0)))
		if island:
			var ix := 0.15 + (n / 2 - 1) * bay_w
			box(g, off + Vector3(ix, y, z0 + 0.05), off + Vector3(ix + 2.0 * bay_w, y + 0.08, z0 + bay_d - 0.05), mat(Color(0.7, 0.7, 0.68), 0.8))
			box(g, off + Vector3(ix + 0.05, y + 0.08, z0 + 0.1), off + Vector3(ix + 2.0 * bay_w - 0.05, y + 0.1, z0 + bay_d - 0.1), _terrain_mat if _terrain_mat else mat(Color(0.3, 0.45, 0.2)))
			var tk := "proc/lime"
			var tsc := 2.6 / maxf(0.01, Kenney.size(tk).y)
			var tr := Kenney.batch(tk, [Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(tsc, tsc, tsc)), off + Vector3(ix + bay_w, y + 0.08, z0 + bay_d / 2.0))] as Array[Transform3D], [_leaf(rng)] as Array[Color])
			tr.set_meta("tree", true)
			g.add_child(tr)
	_mm(g, lines, line, false)
	for kind in by_kind:
		var arr: Array[Transform3D] = []
		arr.assign(by_kind[kind])
		var cols: Array[Color] = []
		cols.assign(tints[kind])
		g.add_child(Kenney.batch(kind, arr, cols))
	if surface:
		# lamp posts along the aisles, a pay station and the barrier at the entrance
		var post := mat(Color(0.3, 0.31, 0.33), 0.4, 0.7)
		for lx in range(2, int(w), 4):
			box(g, Vector3(lx - 0.03, y, bay_d + 0.25), Vector3(lx + 0.03, y + 1.4, bay_d + 0.31), post)
			box(g, Vector3(lx - 0.15, y + 1.38, bay_d + 0.22), Vector3(lx + 0.15, y + 1.43, bay_d + 0.34), mat(Color(1.0, 0.95, 0.85), 0.3, 0.0, 0.8))
		box(g, Vector3(0.2, y, d - 0.05), Vector3(0.45, y + 0.5, d + 0.2), mat(Color(0.15, 0.35, 0.75), 0.4))
		box(g, Vector3(0.7, y, d + 0.05), Vector3(0.78, y + 0.35, d + 0.13), mat(Color(0.9, 0.85, 0.2), 0.5))
		box(g, Vector3(0.78, y + 0.28, d + 0.07), Vector3(2.0, y + 0.32, d + 0.11), mat(Color(0.95, 0.2, 0.15), 0.5))


## A concourse stall facing local -Z: a panelled booth with a serving hatch
## and counter, a lit menu board, a striped awning and a roof sign.
func _stall(g: Node3D, body: Color, stripe_a: Color, stripe_b: Color, sign_text: String) -> void:
	box(g, Vector3(0.08, 0.0, 0.18), Vector3(0.92, 0.78, 0.92), tex_mat("rough_concrete", body, 0.6, true))
	box(g, Vector3(0.05, 0.78, 0.15), Vector3(0.95, 0.84, 0.95), mat(body.darkened(0.35), 0.6))
	# the hatch: dark interior, a lit menu board above, a counter in front
	box(g, Vector3(0.15, 0.32, 0.17), Vector3(0.85, 0.62, 0.19), mat(Color(0.1, 0.09, 0.08), 0.8))
	box(g, Vector3(0.2, 0.5, 0.185), Vector3(0.8, 0.6, 0.19), mat(Color(1.0, 0.88, 0.6), 0.3, 0.0, 1.4))
	box(g, Vector3(0.1, 0.3, 0.06), Vector3(0.9, 0.34, 0.2), mat(Color(0.75, 0.76, 0.78), 0.3, 0.7))
	box(g, Vector3(0.12, 0.0, 0.12), Vector3(0.88, 0.3, 0.18), mat(body.darkened(0.15), 0.7))
	# striped awning, sloping out over the counter
	for k in 6:
		var x0 := 0.05 + k * 0.15
		var a := lbox(g, Vector3(x0 + 0.075, 0.7, 0.1), Vector3(0.15, 0.02, 0.24), mat(stripe_a if k % 2 == 0 else stripe_b, 0.7), 0.45)
		a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	box(g, Vector3(0.05, 0.62, 0.0), Vector3(0.95, 0.66, 0.02), mat(stripe_a, 0.7))
	# roof sign
	box(g, Vector3(0.3, 0.84, 0.5), Vector3(0.7, 1.02, 0.54), mat(stripe_a, 0.5))
	_lettering(g, sign_text, Vector3(0.5, 0.93, 0.49), stripe_b, 0.0035, 32, PI, "inside")


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
		"press_box":
			# a glazed box at the back of the stand, off-centre, desks and monitors behind the glass
			var x := L * 0.22
			var z := -D / 2.0 + 0.9
			var y := top - 0.2
			var bw := minf(5.0, L * 0.25)
			var frame_m := mat(Color(0.9, 0.9, 0.9), 0.5) if st == "glass" else tex_mat("red_brick_03", Color.WHITE, 1.0)
			lbox(fr, Vector3(x, y + 0.6, z), Vector3(bw + 0.2, 1.3, 1.6), frame_m)
			var gl := lbox(fr, Vector3(x, y + 0.65, z + 0.81), Vector3(bw, 0.8, 0.03), mat(Color(0.2, 0.3, 0.36), 0.05, 0.5, 0.0, 0.7))
			gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lbox(fr, Vector3(x, y + 0.3, z + 0.95), Vector3(bw, 0.05, 0.3), mat(Color(0.35, 0.3, 0.25), 0.7))
			for k in int(bw / 0.6):
				lbox(fr, Vector3(x - bw / 2.0 + 0.3 + k * 0.6, y + 0.45, z + 0.95), Vector3(0.18, 0.12, 0.03), mat(Color(0.1, 0.2, 0.35), 0.2, 0.0, 0.8))
			_label(fr, "PRESS", Vector3(x, y + 1.15, z + 0.82), 40, Color.WHITE, false, 0.006).outline_size = 0
		"directors_box":
			# the best seats in the house: padded seats on a raised platform at
			# halfway, a canopy in club colours, a glass front
			var v := clampi(s.depth / 3, 1, s.depth - 2)
			var y := row_height(v, s) + 0.05
			var z := D / 2.0 - v - 1.0
			var bw := minf(4.5, L * 0.2)
			lbox(fr, Vector3(0, y, z), Vector3(bw, 0.12, 2.0), mat(Color(0.25, 0.22, 0.2), 0.6))
			var seat_m := mat(_club.primary_color.darkened(0.25), 0.8)
			for row in 2:
				for k in int(bw / 0.45):
					var sx := -bw / 2.0 + 0.25 + k * 0.45
					lbox(fr, Vector3(sx, y + 0.18 + row * 0.25, z + 0.4 - row * 0.8), Vector3(0.36, 0.12, 0.32), seat_m)
					lbox(fr, Vector3(sx, y + 0.38 + row * 0.25, z + 0.24 - row * 0.8), Vector3(0.36, 0.34, 0.08), seat_m)
			lbox(fr, Vector3(0, y + 0.35, z + 1.0), Vector3(bw, 0.5, 0.03), mat(Color(0.75, 0.85, 0.9), 0.05, 0.3, 0.0, 0.35))
			if st == "canopy":
				for e in [-1.0, 1.0]:
					lbox(fr, Vector3(e * (bw / 2.0 - 0.05), y + 0.9, z - 0.5), Vector3(0.06, 1.8, 0.06), _steel())
				lbox(fr, Vector3(0, y + 1.85, z), Vector3(bw + 0.3, 0.08, 2.4), mat(_club.primary_color, 0.5))
				lbox(fr, Vector3(0, y + 1.75, z + 1.2), Vector3(bw + 0.3, 0.25, 0.04), mat(_club.secondary_color, 0.5))
			else:
				lbox(fr, Vector3(0, y + 1.0, z - 0.95), Vector3(bw, 1.8, 0.1), mat(Color(0.2, 0.3, 0.36), 0.05, 0.5, 0.0, 0.7))
		"access_platform":
			# a raised viewing platform for wheelchair users with companion
			# seats, a rail all round and a ramp up from the front
			var y := row_height(3, s) + 0.05 if s.depth > 4 else s.plinth + 0.4
			var z := D / 2.0 - 2.0
			var x := -L * 0.25
			var pw := minf(5.0, L * 0.22)
			var deck_m := mat(Color(0.5, 0.52, 0.55), 0.6, 0.5) if st == "steel" else tex_mat("rough_concrete", Color(0.75, 0.75, 0.73), 2.0, true)
			lbox(fr, Vector3(x, y, z), Vector3(pw, 0.12, 1.8), deck_m)
			for e in [-1.0, 1.0]:
				lbox(fr, Vector3(x + e * pw / 2.0, y / 2.0, z), Vector3(0.12, y, 1.8), deck_m)
			lbox(fr, Vector3(x, y + 0.45, z + 0.9), Vector3(pw, 0.04, 0.04), _steel())
			lbox(fr, Vector3(x, y + 0.25, z + 0.9), Vector3(pw, 0.4, 0.02), mat(Color(0.75, 0.85, 0.9), 0.05, 0.3, 0.0, 0.3))
			var ramp := lbox(fr, Vector3(x + pw / 2.0 + 1.2, y / 2.0, z + 0.6), Vector3(2.4, 0.08, 0.6), deck_m, 0.0)
			ramp.rotation.z = atan2(y, 2.4)
			# blue access markings
			lbox(fr, Vector3(x, y + 0.065, z), Vector3(0.5, 0.01, 0.5), mat(Color(0.1, 0.35, 0.8), 0.6))
		"video_board":
			var mult: float = { "S": 0.7, "M": 1.0, "L": 1.35 }[f.opt(ft, "size")]
			var sw := minf(L * 0.45, 9.0) * mult if st == "classic" else minf(L * 0.8, 16.0) * minf(mult, 1.15)
			var sh := 2.4 * mult if st == "classic" else 1.2 * mult
			var base := roof_y + (0.8 if st == "classic" else 0.2)
			var z := -D / 2.0 + 0.4 if st == "classic" else D / 2.0 + 0.6
			var fm := _frame_mat(f.opt(ft, "frame"))
			if st == "classic":
				for e in [-1, 1]:
					lbox(fr, Vector3(e * sw * 0.35, base / 2.0, z - 0.1), Vector3(0.25, base, 0.25), steel)
			lbox(fr, Vector3(0, base + sh / 2.0, z), Vector3(sw + 0.3, sh + 0.3, 0.25), fm)
			var screen := lbox(fr, Vector3(0, base + sh / 2.0, z + 0.14), Vector3(sw, sh, 0.04), mat(Color(0.04, 0.06, 0.1), 0.2, 0.0, 1.0))
			screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mid := Vector3(0, base + sh / 2.0, z + 0.17)
			match f.opt(ft, "content"):
				"crest":
					lbox(fr, mid - Vector3(0, 0, 0.005), Vector3(sw * 0.94, sh * 0.9, 0.01), mat(_club.primary_color.darkened(0.5), 0.3, 0.0, 1.2))
					_crest(fr, mid + Vector3(0, 0, 0.01), sh * 0.75, 0.0, true)
				"score":
					var lab := _label(fr, "HOME  2 - 1  AWAY", mid + Vector3(0, 0, 0.01), 64, Color(1.0, 0.85, 0.3), false, minf(0.009, sw / 1100.0))
					lab.outline_size = 0
				"sponsor":
					lbox(fr, mid - Vector3(0, 0, 0.005), Vector3(sw * 0.94, sh * 0.9, 0.01), mat(Color(0.1, 0.35, 0.8), 0.3, 0.0, 1.4))
					var lab := _label(fr, AD_BRANDS[(s.offset + s.depth) % AD_BRANDS.size()], mid + Vector3(0, 0, 0.01), 64, Color.WHITE, false, minf(0.01, sw / 1000.0))
					lab.outline_size = 0
				_:
					var band := lbox(fr, Vector3(0, base + sh * 0.5, z + 0.165), Vector3(sw * 0.94, sh * 0.42, 0.01), mat(_club.primary_color, 0.3, 0.0, 1.6))
					band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					lbox(fr, Vector3(0, base + sh * 0.27, z + 0.168), Vector3(sw * 0.94, sh * 0.05, 0.01), mat(_club.secondary_color, 0.3, 0.0, 1.4))
					var lab := _label(fr, _club.club_name.to_upper(), mid + Vector3(0, 0, 0.01), 64, Color.WHITE, false, minf(0.01, sw / 900.0))
					lab.outline_size = 0
		"ribbon_board":
			var y := row_height(maxi(0, s.depth / 2), s) + 0.25
			var z := D / 2.0 - (s.depth / 2 + 0.5) - 0.02
			lbox(fr, Vector3(0, y, z), Vector3(L - 0.2, 0.28, 0.05), mat(_club.primary_color.lerp(Color(1, 1, 1), 0.15), 0.2, 0.0, 2.0))
			var lab := _label(fr, "%s  •  MATCHDAY  •  %s" % [_club.club_name.to_upper(), _club.club_name.to_upper()], Vector3(0, y, z + 0.04), 36, _club.secondary_color, false, 0.005)
			lab.outline_size = 0
		"scoreboard":
			var y := roof_y + 0.5
			var z := D / 2.0 + 0.5
			var dc: Color = { "amber": Color(1.0, 0.6, 0.1), "white": Color(0.95, 0.95, 0.9), "green": Color(0.4, 1.0, 0.45), "red": Color(1.0, 0.25, 0.2) }[f.opt(ft, "digits")]
			var fm := _frame_mat(f.opt(ft, "frame"))
			if st == "retro":
				lbox(fr, Vector3(0, y + 0.6, z), Vector3(3.4, 1.4, 0.15), fm)
				lbox(fr, Vector3(0, y + 0.6, z + 0.08), Vector3(3.2, 1.2, 0.02), mat(Color(0.1, 0.3, 0.15), 0.8))
				_label(fr, "HOME  1   AWAY  0", Vector3(0, y + 0.6, z + 0.1), 48, dc, false, 0.005)
			else:
				lbox(fr, Vector3(0, y + 0.5, z), Vector3(2.6, 1.0, 0.2), fm)
				lbox(fr, Vector3(0, y + 0.5, z + 0.1), Vector3(2.4, 0.85, 0.02), mat(Color(0.03, 0.03, 0.04), 0.3))
				_label(fr, "1 - 0", Vector3(0, y + 0.5, z + 0.12), 96, dc, false, 0.007)
			for e in [-1, 1]:
				lbox(fr, Vector3(e * 1.0, y / 2.0, z - 0.1), Vector3(0.12, y, 0.12), steel)
		"exec_boxes":
			if s.tiers < 2:
				return
			var tf := float(s.tier_front(1))
			var zf := D / 2.0 - tf + 0.05
			var y0 := row_height(int(tf), s) + 0.35
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
			var body: Material = { "black": dark, "white": mat(Color(0.9, 0.9, 0.88), 0.5), "club": _fascia() }[f.opt(ft, "color")]
			var grille := mat(Color(0.25, 0.25, 0.28), 0.3, 0.5)
			var n := maxi(2, int(L / 6.0) + 1)
			for k in n:
				var x := (float(k) / float(n - 1) - 0.5) * (L - 1.0)
				var zf := D / 2.0 + 0.2
				match st:
					"horns":
						# a cluster of trumpet horns on a bracket
						for h in 3:
							var cone := MeshInstance3D.new()
							var cm := CylinderMesh.new()
							cm.top_radius = 0.05
							cm.bottom_radius = 0.2
							cm.height = 0.5
							cone.mesh = cm
							cone.material_override = body
							cone.rotation = Vector3(PI / 2.0 - 0.35, (h - 1) * 0.5, 0)
							cone.position = Vector3(x + (h - 1) * 0.3, y + 0.05 * absf(h - 1), zf + 0.1)
							fr.add_child(cone)
						lbox(fr, Vector3(x, y + 0.4, zf), Vector3(0.04, 0.5, 0.04), steel)
					"line_array":
						# a hanging column of boxes, curving down toward the crowd
						for h in 5:
							var b := lbox(fr, Vector3(x, y + 0.3 - h * 0.24, zf + h * 0.04), Vector3(0.6, 0.22, 0.35), body)
							b.rotation.x = 0.08 * h
							lbox(fr, Vector3(x, y + 0.3 - h * 0.24, zf + h * 0.04 + 0.18), Vector3(0.5, 0.15, 0.01), grille)
						lbox(fr, Vector3(x, y + 0.75, zf), Vector3(0.03, 0.4, 0.03), steel)
					_:
						lbox(fr, Vector3(x, y, zf), Vector3(0.45, 0.7, 0.4), body)
						lbox(fr, Vector3(x, y, zf + 0.21), Vector3(0.3, 0.3, 0.02), grille)
						lbox(fr, Vector3(x, y + 0.5, zf), Vector3(0.04, 0.4, 0.04), steel)


# --- outside -----------------------------------------------------------------------

func _build_outside_item(f: Facility, ft: FacilityType) -> void:
	var g := Node3D.new()
	g.position = Vector3(f.pos.x, 0.0, f.pos.y)
	if f.rot % 4 == 0:
		_outside.add_child(g)
	else:
		# turned: spin about the middle of the (turned) footprint
		var fs := f.size(ft)
		var pivot := Node3D.new()
		pivot.position = Vector3(f.pos.x + fs.x / 2.0, 0.0, f.pos.y + fs.y / 2.0)
		pivot.rotation.y = -f.rot * PI / 2.0
		_outside.add_child(pivot)
		g.position = Vector3(-ft.size.x / 2.0, 0.0, -ft.size.y / 2.0)
		pivot.add_child(g)
	var w := float(ft.size.x)
	var d := float(ft.size.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = f.pos.x * 1000 + f.pos.y
	match ft.id:
		"entrance":
			var st := _style(f, ft)
			var club := _club.primary_color
			match st:
				"glass_pavilion":
					# a glass box over the stairs with a canopy and the logo light
					box(g, Vector3(0.1, 0, 0.1), Vector3(w - 0.1, 1.2, d - 0.1), mat(Color(0.6, 0.75, 0.82), 0.05, 0.3, 0.0, 0.5), false)
					for cx in [0.1, w / 2.0, w - 0.1]:
						box(g, Vector3(cx - 0.03, 0, 0.08), Vector3(cx + 0.03, 1.2, 0.12), mat(Color(0.25, 0.26, 0.28), 0.4, 0.6))
						box(g, Vector3(cx - 0.03, 0, d - 0.12), Vector3(cx + 0.03, 1.2, d - 0.08), mat(Color(0.25, 0.26, 0.28), 0.4, 0.6))
					box(g, Vector3(-0.15, 1.2, -0.15), Vector3(w + 0.15, 1.3, d + 0.15), mat(Color(0.9, 0.9, 0.88), 0.4))
					box(g, Vector3(0.2, 0.02, 0.2), Vector3(w - 0.2, 0.05, d - 0.2), mat(Color(0.12, 0.12, 0.13), 0.8))
				"lift_tower":
					box(g, Vector3(0.2, 0, 0.1), Vector3(w * 0.5, 2.4, d - 0.1), tex_mat("concrete_tile_facade", Color(1.3, 1.3, 1.3), 1.5))
					box(g, Vector3(w * 0.5, 0, 0.15), Vector3(w - 0.2, 0.9, d - 0.15), mat(Color(0.25, 0.26, 0.28), 0.5, 0.5))
					box(g, Vector3(0.25, 1.6, d - 0.11), Vector3(w * 0.5 - 0.05, 2.2, d - 0.09), mat(club, 0.4, 0.0, 0.6))
					_lettering(g, "LIFT", Vector3(w * 0.25 + 0.1, 1.9, d - 0.08), Color.WHITE, 0.004, 40, 0.0, "inside")
				_:
					# a stair hatch: low walls round the opening, a canopy, a lit sign post
					box(g, Vector3(0.1, 0, 0.1), Vector3(w - 0.1, 0.5, 0.2), tex_mat("rough_concrete", Color(0.75, 0.75, 0.73), 1.0))
					box(g, Vector3(0.1, 0, d - 0.2), Vector3(w - 0.1, 0.5, d - 0.1), tex_mat("rough_concrete", Color(0.75, 0.75, 0.73), 1.0))
					box(g, Vector3(0.1, 0, 0.1), Vector3(0.2, 0.5, d - 0.1), tex_mat("rough_concrete", Color(0.75, 0.75, 0.73), 1.0))
					box(g, Vector3(0.25, 0.01, 0.25), Vector3(w - 0.25, 0.03, d - 0.25), mat(Color(0.08, 0.08, 0.09), 0.9))
					for k in 4:
						box(g, Vector3(w - 0.3 - k * 0.3, 0.0, 0.25), Vector3(w - 0.1 - k * 0.3, 0.03 + k * 0.0, d - 0.25), mat(Color(0.7, 0.7, 0.68), 0.8))
					var cn := lbox(g, Vector3(w / 2.0, 1.05, d / 2.0), Vector3(w + 0.2, 0.06, d + 0.2), mat(club.darkened(0.2), 0.5), 0.0)
					cn.rotation.x = 0.08
					for cx in [0.15, w - 0.15]:
						box(g, Vector3(cx - 0.03, 0.5, d / 2.0 - 0.03), Vector3(cx + 0.03, 1.05, d / 2.0 + 0.03), mat(Color(0.25, 0.26, 0.28), 0.4, 0.6))
			# a sign post telling people what's down there
			box(g, Vector3(-0.15, 0, d / 2.0 - 0.04), Vector3(-0.07, 1.6, d / 2.0 + 0.04), mat(Color(0.3, 0.3, 0.3), 0.5, 0.6))
			lbox(g, Vector3(-0.11, 1.75, d / 2.0), Vector3(0.06, 0.4, 0.4), mat(Color(0.15, 0.35, 0.8), 0.4, 0.0, 0.8))
		"tea_bar":
			var st := _style(f, ft)
			match st:
				"van":
					# a catering van with the hatch up
					box(g, Vector3(0.2, 0.18, 0.2), Vector3(w - 0.2, 1.05, d - 0.15), mat(Color(0.92, 0.9, 0.85), 0.4, 0.2))
					box(g, Vector3(w - 0.55, 0.18, 0.2), Vector3(w - 0.2, 0.85, d - 0.15), mat(Color(0.2, 0.25, 0.3), 0.1, 0.4))
					box(g, Vector3(0.45, 0.55, d - 0.16), Vector3(w - 0.75, 0.9, d - 0.13), mat(Color(0.15, 0.12, 0.1), 0.6))
					var hatch := lbox(g, Vector3(w / 2.0 - 0.15, 1.0, d - 0.05), Vector3(w - 1.2, 0.04, 0.35), _fascia(), 0.0)
					hatch.rotation.x = -0.5
					for wx in [0.6, w - 0.7]:
						var wh := MeshInstance3D.new()
						var cy := CylinderMesh.new()
						cy.top_radius = 0.17
						cy.bottom_radius = 0.17
						cy.height = 0.1
						wh.mesh = cy
						wh.material_override = mat(Color(0.08, 0.08, 0.08), 0.8)
						wh.rotation.x = PI / 2.0
						wh.position = Vector3(wx, 0.17, d - 0.12)
						g.add_child(wh)
				"container":
					box(g, Vector3(0.05, 0.0, 0.1), Vector3(w - 0.05, 1.1, d - 0.1), tex_mat("corrugated_iron", _club.primary_color.lightened(0.2), 0.6))
					box(g, Vector3(0.35, 0.45, d - 0.12), Vector3(w - 0.35, 0.9, d - 0.09), mat(Color(0.12, 0.1, 0.09), 0.6))
					box(g, Vector3(0.3, 0.9, d - 0.1), Vector3(w - 0.3, 0.95, d + 0.25), mat(Color(0.85, 0.85, 0.82), 0.5))
				_:
					# a timber hut with a serving hatch, a pitched felt roof and a menu board
					box(g, Vector3(0.1, 0.0, 0.1), Vector3(w - 0.1, 1.05, d - 0.1), tex_mat("rough_concrete", Color(0.55, 0.4, 0.28), 0.5))
					box(g, Vector3(0.4, 0.45, d - 0.12), Vector3(w - 0.4, 0.88, d - 0.08), mat(Color(0.12, 0.1, 0.09), 0.6))
					box(g, Vector3(0.35, 0.42, d - 0.1), Vector3(w - 0.35, 0.46, d + 0.12), mat(Color(0.75, 0.65, 0.5), 0.7))
					var r1 := lbox(g, Vector3(w / 2.0, 1.2, d / 2.0 - 0.22), Vector3(w + 0.1, 0.05, d / 2.0 + 0.2), mat(Color(0.18, 0.2, 0.2), 0.9), 0.0)
					r1.rotation.x = 0.5
					var r2 := lbox(g, Vector3(w / 2.0, 1.2, d / 2.0 + 0.22), Vector3(w + 0.1, 0.05, d / 2.0 + 0.2), mat(Color(0.18, 0.2, 0.2), 0.9), 0.0)
					r2.rotation.x = -0.5
					_lettering(g, "TEA  PIES  BOVRIL", Vector3(w / 2.0, 1.0, d - 0.07), Color(1, 0.95, 0.8), 0.004, 40, 0.0, "none", "classic")
		"turnstile_hut":
			var brick := _style(f, ft) == "brick"
			var wall_m: Material = tex_mat("red_brick_03", Color.WHITE, 1.0) if brick else tex_mat("rough_concrete", Color(0.45, 0.5, 0.42), 0.5)
			box(g, Vector3(0.1, 0.0, 0.2), Vector3(w - 0.1, 1.0, d - 0.2), wall_m)
			box(g, Vector3(0.0, 1.0, 0.1), Vector3(w, 1.08, d - 0.1), mat(Color(0.2, 0.2, 0.22), 0.8))
			# two turnstile windows and the iron gates
			for k in 2:
				var x0 := 0.3 + k * (w / 2.0)
				box(g, Vector3(x0, 0.0, d - 0.22), Vector3(x0 + 0.55, 0.85, d - 0.18), mat(Color(0.15, 0.15, 0.16), 0.5))
				box(g, Vector3(x0 + 0.05, 0.55, d - 0.18), Vector3(x0 + 0.5, 0.75, d - 0.16), mat(Color(0.5, 0.6, 0.65), 0.1, 0.3))
			_lettering(g, "TURNSTILES  PAY HERE", Vector3(w / 2.0, 0.93, d - 0.17), Color.WHITE, 0.0035, 36)
			box(g, Vector3(0.2, 0.88, d - 0.18), Vector3(w - 0.2, 0.98, d - 0.17), _fascia())
		"clubhouse":
			var st := _style(f, ft)
			match st:
				"portakabin":
					for k in 2:
						var z0 := 0.3 + k * 1.3
						box(g, Vector3(0.2, 0.15, z0), Vector3(w - 0.2, 1.1, z0 + 1.2), tex_mat("corrugated_iron", Color(0.75, 0.78, 0.72), 0.5))
						for wx in range(1, int(w) - 0, 1):
							box(g, Vector3(wx - 0.3, 0.55, z0 + 1.2), Vector3(wx + 0.1, 0.9, z0 + 1.22), mat(Color(0.25, 0.32, 0.38), 0.1, 0.4))
					box(g, Vector3(0.0, 0.0, 0.0), Vector3(w, 0.15, d), mat(Color(0.3, 0.3, 0.3), 0.9))
				"modern":
					box(g, Vector3(0.1, 0.0, 0.3), Vector3(w - 0.1, 1.3, d - 0.2), tex_mat("concrete_tile_facade", Color(1.4, 1.4, 1.4), 1.5))
					box(g, Vector3(0.15, 0.1, d - 0.22), Vector3(w - 0.15, 1.15, d - 0.18), mat(Color(0.22, 0.3, 0.36), 0.05, 0.5))
					box(g, Vector3(-0.2, 1.3, 0.1), Vector3(w + 0.2, 1.42, d + 0.4), mat(Color(0.25, 0.25, 0.27), 0.5, 0.4))
					box(g, Vector3(0.2, 1.42, d - 0.05), Vector3(w - 0.2, 1.62, d), _fascia())
				_:
					# brick clubhouse: hipped roof, bay windows, a veranda with benches
					box(g, Vector3(0.1, 0.0, 0.2), Vector3(w - 0.1, 1.2, d - 0.7), tex_mat("red_brick_03", Color.WHITE, 1.0))
					for wx in range(1, int(w)):
						box(g, Vector3(wx - 0.25, 0.4, d - 0.72), Vector3(wx + 0.25, 0.95, d - 0.68), mat(Color(0.85, 0.85, 0.82), 0.5))
						box(g, Vector3(wx - 0.2, 0.45, d - 0.69), Vector3(wx + 0.2, 0.9, d - 0.67), mat(Color(0.22, 0.28, 0.34), 0.1, 0.4))
					_hip_roof(g, Rect2(0.0, 0.1, w, d - 0.7), 1.2, 0.8, _roof_tiles_mat(Color(0.35, 0.3, 0.3)))
					box(g, Vector3(0.0, 0.0, d - 0.7), Vector3(w, 0.06, d), tex_mat("rough_concrete", Color(0.7, 0.68, 0.65), 1.0))
					for vx in [0.1, w / 2.0, w - 0.1]:
						box(g, Vector3(vx - 0.04, 0.0, d - 0.08), Vector3(vx + 0.04, 0.95, d), mat(Color(0.92, 0.92, 0.9), 0.5))
					box(g, Vector3(0.0, 0.95, d - 0.7), Vector3(w, 1.0, d + 0.05), mat(_club.primary_color, 0.6))
			_lettering(g, _club.club_name.to_upper(), Vector3(w / 2.0, 1.55 if st == "modern" else 1.05, d - (0.0 if st == "modern" else 0.69)), Color.WHITE if st == "modern" else Color(1, 0.95, 0.85), 0.004, 40, 0.0, "halo" if st == "modern" else "none", "future" if st == "modern" else "classic")
		"car_park":
			_car_surface = f.opt(ft, "surface")
			_car_rows(g, w, d, 0.03, rng, 0.9, true)
			_car_surface = "asphalt"
			if f.opt(ft, "trees") == "yes":
				# trees along the edges in little islands
				var tt: Array[Transform3D] = []
				var tcols: Array[Color] = []
				var x := 1.0
				while x < w - 0.5:
					for zz in [0.35, d - 0.35]:
						var sc := 3.2 / maxf(0.01, Kenney.size("proc/lime").y)
						tt.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(x, 0.03, zz)))
						tcols.append(_leaf(rng))
					x += 3.0
				var tm := Kenney.batch("proc/lime", tt, tcols)
				g.add_child(tm)
			if f.opt(ft, "lights") == "yes":
				var lx := 2.0
				while lx < w - 1.0:
					lbox(g, Vector3(lx, 1.4, d / 2.0), Vector3(0.08, 2.8, 0.08), mat(Color(0.5, 0.52, 0.55), 0.4, 0.7))
					var head := lbox(g, Vector3(lx, 2.85, d / 2.0), Vector3(0.5, 0.08, 0.2), mat(Color(1.0, 0.92, 0.7), 0.3, 0.0, 1.5))
					head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					var ol := OmniLight3D.new()
					ol.light_color = Color(1.0, 0.9, 0.7)
					ol.light_energy = 1.2
					ol.omni_range = 5.0
					ol.position = Vector3(lx, 2.6, d / 2.0)
					g.add_child(ol)
					_night_light(ol)
					lx += 5.0
		"multi_storey":
			# decks on columns, edge parapets, a ramp, a stair-and-lift core and cars
			# on every level including the open roof
			var deck_h := 0.75
			var levels := int(f.opt(ft, "levels"))
			var clad := f.opt(ft, "cladding")
			var conc := tex_mat("rough_concrete", Color(0.72, 0.72, 0.7), 2.0, true)
			for lv in levels + 1:
				var y := lv * deck_h
				if lv > 0:
					box(g, Vector3(0.0, y - 0.1, 0.0), Vector3(w, y, d), conc)
					# parapet: a solid band with a gap, club stripe on top floor
					box(g, Vector3(-0.02, y, -0.02), Vector3(w + 0.02, y + 0.28, 0.06), conc)
					box(g, Vector3(-0.02, y, d - 0.06), Vector3(w + 0.02, y + 0.28, d + 0.02), conc)
					box(g, Vector3(-0.02, y, 0.0), Vector3(0.06, y + 0.28, d), conc)
					box(g, Vector3(w - 0.06, y, 0.0), Vector3(w + 0.02, y + 0.28, d), conc)
				_car_rows(g, w - 1.6, d, y + 0.0 if lv == 0 else y, rng, 0.85 if lv < levels else 0.55, false, Vector3(0.0, 0.0, 0.0))
				if lv < levels:
					for cx in range(1, int(w - 1.6), 3):
						for cz in [0.15, d / 2.0, d - 0.15]:
							box(g, Vector3(cx - 0.07, y, cz - 0.07), Vector3(cx + 0.07, y + deck_h - 0.1, cz + 0.07), conc)
			box(g, Vector3(0.0, levels * deck_h + 0.28, -0.03), Vector3(w, levels * deck_h + 0.34, 0.07), _fascia())
			if clad != "open":
				# a screen over the front: perforated mesh, or panels in the club colour
				var cm := mat(Color(0.55, 0.57, 0.6), 0.5, 0.6, 0.0, 0.7) if clad == "mesh" else mat(_club.primary_color, 0.6, 0.1, 0.0, 0.85)
				box(g, Vector3(0.0, deck_h * 0.4, -0.08), Vector3(w - 1.6, levels * deck_h + 0.25, -0.05), cm)
				box(g, Vector3(-0.08, deck_h * 0.4, 0.0), Vector3(-0.05, levels * deck_h + 0.25, d), cm)
			# stair and lift core in the corner with a big P
			box(g, Vector3(w - 1.5, 0.0, d - 1.6), Vector3(w, levels * deck_h + 0.7, d), tex_mat("concrete_tile_facade", Color(1.4, 1.4, 1.4), 1.5))
			box(g, Vector3(w - 1.3, 0.3, d + 0.0), Vector3(w - 0.2, levels * deck_h + 0.2, d + 0.02), mat(Color(0.2, 0.3, 0.38), 0.1, 0.4))
			box(g, Vector3(w - 1.25, levels * deck_h + 0.15, d - 1.62), Vector3(w - 0.25, levels * deck_h + 0.65, d - 1.58), mat(Color(0.1, 0.3, 0.75), 0.4, 0.0, 0.6))
			_lettering(g, "P", Vector3(w - 0.75, levels * deck_h + 0.4, d - 1.63), Color.WHITE, 0.005, 96, PI, "inside")
			# ramp strip along one side
			for lv in levels:
				var ramp := lbox(g, Vector3(w - 0.8, lv * deck_h + deck_h / 2.0, d / 2.0 - 0.8), Vector3(1.4, 0.08, d - 2.0), conc, -atan2(deck_h, d - 2.0) * (1.0 if lv % 2 == 0 else -1.0))
				ramp.position.x = w - 0.8
		"statue":
			# a bronze of a club legend on a stepped granite plinth with a plaque
			var st := _style(f, ft)
			var granite := tex_mat("rough_concrete", Color(0.42, 0.42, 0.44), 1.0, true)
			box(g, Vector3(0.05, 0.0, 0.05), Vector3(0.95, 0.12, 0.95), granite)
			box(g, Vector3(0.18, 0.12, 0.18), Vector3(0.82, 0.75, 0.82), granite)
			box(g, Vector3(0.12, 0.75, 0.12), Vector3(0.88, 0.82, 0.88), granite)
			box(g, Vector3(0.32, 0.35, 0.82), Vector3(0.68, 0.55, 0.835), mat(Color(0.6, 0.45, 0.2), 0.3, 0.9))
			var body_m: Material
			match f.opt(ft, "material"):
				"stone": body_m = tex_mat("rough_concrete", Color(0.86, 0.84, 0.8), 1.0, true)
				"painted": body_m = mat(_club.primary_color, 0.5)
				"gold": body_m = mat(Color(0.9, 0.72, 0.3), 0.25, 0.95)
				_: body_m = mat(Color(0.62, 0.44, 0.24), 0.36, 0.6)
			_sculpture(g, Vector3(0.5, 0.82, 0.5), st, body_m)
			# floodlit at night from a lamp set in the paving
			var sl := SpotLight3D.new()
			sl.light_color = Color(1.0, 0.9, 0.75)
			sl.light_energy = 3.0
			sl.spot_range = 4.0
			sl.spot_angle = 30.0
			sl.position = Vector3(0.5, 0.1, 1.6)
			g.add_child(sl)
			sl.look_at(g.to_global(Vector3(0.5, 1.3, 0.5)), Vector3.UP)
			_night_light(sl)
			var words := f.opt(ft, "text")
			if words != "":
				var pl := Signs.build(g, { "text": words, "mount": "letters", "font": "classic", "depth": 0.01, "scale": 0.13 }, Color(0.85, 0.7, 0.35), Color(0.85, 0.7, 0.35), 0.6, _glow, _night_light)
				pl.position = Vector3(0.5, 0.62, 0.84)
		"memorial":
			_memorial(g, f, ft, w, d)
		"club_gates":
			_club_gates(g, f, ft, w, d)
		"ground_sign":
			_ground_sign(g, f, ft, w, d)
		"atrium":
			_atrium(g, f, ft, w, d)
		"fountain":
			_fountain(g, f, ft, w, d)
		"fan_park":
			_fan_park(g, f, ft, w, d)
		"training_pitch":
			_training_pitch(g, f, ft, w, d)
		"score_tower":
			_score_tower(g, f, ft, w, d)
		"ticket_office":
			# a little brick booking hall: hipped roof, a row of lit sales windows
			# under a canopy, the club's colours on the fascia
			var brick := tex_mat("red_brick_03", Color(1, 1, 1), 1.0)
			box(g, Vector3(0.1, 0.0, 0.15), Vector3(w - 0.1, 1.1, d - 0.15), brick)
			box(g, Vector3(0.05, 0.0, 0.1), Vector3(w - 0.05, 0.18, d - 0.1), tex_mat("rough_concrete", Color(0.6, 0.6, 0.6), 2.0, true))
			var rf := MeshInstance3D.new()
			var pmr := PrismMesh.new()
			pmr.size = Vector3(w + 0.1, 0.55, d - 0.05)
			rf.mesh = pmr
			rf.material_override = _roof_tiles_mat(Color(0.32, 0.3, 0.32))
			rf.position = Vector3(w / 2.0, 1.1 + 0.275, d / 2.0)
			g.add_child(rf)
			box(g, Vector3(0.05, 0.95, d - 0.17), Vector3(w - 0.05, 1.12, d - 0.1), _fascia())
			for k in 4:
				var cx := 0.3 + k * (w - 0.6) / 3.0
				box(g, Vector3(cx - 0.17, 0.35, d - 0.16), Vector3(cx + 0.17, 0.75, d - 0.13), mat(Color(1.0, 0.88, 0.62), 0.2, 0.0, 0.9))
				box(g, Vector3(cx - 0.2, 0.32, d - 0.14), Vector3(cx + 0.2, 0.36, d - 0.05), mat(Color(0.9, 0.9, 0.88), 0.5))
			box(g, Vector3(0.0, 0.82, d - 0.1), Vector3(w, 0.86, d + 0.35), mat(_club.primary_color.darkened(0.3), 0.5))
			_lettering(g, "TICKETS", Vector3(w / 2.0, 1.03, d - 0.08), _club.secondary_color, 0.004, 40, 0.0, "inside")
		"museum":
			var stone := tex_mat("rough_concrete", Color(0.88, 0.85, 0.78), 2.0, true)
			if _style(f, ft) == "modern":
				# glass box on a stone plinth with a deep cantilevered roof
				box(g, Vector3(0.15, 0.0, 0.15), Vector3(w - 0.15, 0.25, d - 0.15), stone)
				var pb := ProcBuildings.new()
				pb._wall(Basis(), Vector2(w / 2.0, d / 2.0), 0.25, Vector3(w - 0.6, 1.5, d - 0.6), Color(0.62, 0.66, 0.7), "office", 7.0, 0.75, false)
				pb.build(g)
				box(g, Vector3(0.0, 1.75, 0.0), Vector3(w, 1.9, d), mat(Color(0.92, 0.92, 0.9), 0.6))
				box(g, Vector3(0.0, 1.75, d - 0.06), Vector3(w, 1.9, d), _fascia())
			else:
				# classical: steps, a colonnade, an entablature and a pediment
				for k in 3:
					box(g, Vector3(0.05 + k * 0.1, k * 0.1, 0.05 + k * 0.1), Vector3(w - 0.05 - k * 0.1, (k + 1) * 0.1, d - 0.05 - k * 0.1), stone)
				box(g, Vector3(0.45, 0.3, 0.9), Vector3(w - 0.45, 1.7, d - 0.4), stone)
				for k in 4:
					var wx := 0.9 + k * (w - 1.8) / 3.0
					box(g, Vector3(wx - 0.2, 0.7, d - 0.42), Vector3(wx + 0.2, 1.4, d - 0.39), mat(Color(0.14, 0.17, 0.2), 0.15, 0.4))
				var col_mesh := CylinderMesh.new()
				col_mesh.top_radius = 0.09
				col_mesh.bottom_radius = 0.1
				col_mesh.height = 1.4
				col_mesh.radial_segments = 12
				for k in 6:
					var cx := 0.45 + k * (w - 0.9) / 5.0
					var c := MeshInstance3D.new()
					c.mesh = col_mesh
					c.material_override = stone
					c.position = Vector3(cx, 0.3 + 0.7, 0.55)
					g.add_child(c)
				box(g, Vector3(0.25, 1.7, 0.3), Vector3(w - 0.25, 1.95, d - 0.3), stone)
				var ped := MeshInstance3D.new()
				var pm := PrismMesh.new()
				pm.size = Vector3(w - 0.5, 0.55, 0.12)
				ped.mesh = pm
				ped.material_override = stone
				ped.position = Vector3(w / 2.0, 1.95 + 0.275, 0.36)
				g.add_child(ped)
				var rf := MeshInstance3D.new()
				var pr := PrismMesh.new()
				pr.size = Vector3(w - 0.5, 0.55, d - 0.6)
				rf.mesh = pr
				rf.rotation.y = 0.0
				rf.material_override = _roof_tiles_mat(Color(0.35, 0.37, 0.4))
				rf.position = Vector3(w / 2.0, 1.95 + 0.275, d / 2.0)
				g.add_child(rf)
			_lettering(g, "CLUB MUSEUM", Vector3(w / 2.0, 1.83, 0.28 if _style(f, ft) != "modern" else d + 0.01), Color(0.25, 0.22, 0.2) if _style(f, ft) != "modern" else _club.secondary_color, 0.004, 40, PI if _style(f, ft) != "modern" else 0.0, "flood" if _style(f, ft) != "modern" else "halo", "classic" if _style(f, ft) != "modern" else "future")
		"hotel":
			# a slab tower on a glazed podium: curtain-wall glass, a club-coloured
			# crown, a porte-cochère and the name on top
			var pb := ProcBuildings.new()
			var floors: int = { "low": 4, "mid": 8, "tower": 16 }.get(f.opt(ft, "height"), 8)
			var clad: String = f.opt(ft, "cladding")
			var tower_col: Color = { "stone": Color(0.74, 0.72, 0.68), "glass": Color(0.45, 0.55, 0.62), "brick": Color(0.58, 0.32, 0.24) }.get(clad, Color(0.74, 0.72, 0.68))
			pb._wall(Basis(), Vector2(w / 2.0, d / 2.0), 0.0, Vector3(w - 0.2, 0.9, d - 0.2), Color(0.55, 0.58, 0.6), "office", 3.0, 0.9, false)
			pb._wall(Basis(), Vector2(w / 2.0, d / 2.0 - 0.2), 0.9, Vector3(w - 0.9, floors * 0.62, d - 1.2), tower_col, "office" if clad == "glass" else "flats", 5.0, 0.62, false)
			pb.build(g)
			var top := 0.9 + floors * 0.62
			box(g, Vector3(0.4, top, 0.35), Vector3(w - 0.4, top + 0.25, d - 0.85), _fascia())
			box(g, Vector3(0.9, 0.85, d - 0.1), Vector3(w - 0.9, 0.95, d + 0.6), mat(Color(0.2, 0.2, 0.22), 0.4, 0.5))
			for e in [1.0, w - 1.0]:
				box(g, Vector3(e - 0.04, 0.0, d + 0.5), Vector3(e + 0.04, 0.85, d + 0.58), mat(Color(0.8, 0.8, 0.82), 0.3, 0.7))
			_lettering(g, "HOTEL", Vector3(w / 2.0, top + 0.6, d - 0.3), _club.secondary_color, 0.008, 64, 0.0, "inside")
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
			_lettering(g, "STATION", Vector3(w / 2.0, 2.1, d * 0.25), Color.WHITE, 0.007, 48, 0.0, "inside")
		"bus_stop":
			# a matchday shuttle lay-by: paving, two shelters, the stop sign, and
			# buses in club livery queued at the kerb
			box(g, Vector3(0.0, 0.0, 0.0), Vector3(w, 0.05, 0.75), tex_mat("square_concrete_pavers", Color(1.0, 1.15, 1.35), 1.5), false)
			box(g, Vector3(0.0, 0.0, 0.7), Vector3(w, 0.08, 0.78), mat(Color(0.75, 0.75, 0.73), 0.8), false)
			box(g, Vector3(0.0, -0.01, 0.78), Vector3(w, 0.02, d), tex_mat("asphalt_01", Color(0.62, 0.7, 0.82), 3.0), false)
			box(g, Vector3(0.2, 0.021, d - 0.25), Vector3(w - 0.2, 0.025, d - 0.2), mat(Color(0.95, 0.85, 0.2), 0.6), false)
			var glass := mat(Color(0.75, 0.85, 0.92), 0.05, 0.2, 0.0, 0.35)
			var frame_s := mat(Color(0.25, 0.26, 0.28), 0.4, 0.7)
			for sx in [0.4, w - 1.4]:
				box(g, Vector3(sx, 0.05, 0.1), Vector3(sx + 0.9, 0.7, 0.13), glass)
				for e in [sx, sx + 0.9]:
					box(g, Vector3(e - 0.02, 0.05, 0.1), Vector3(e + 0.02, 0.73, 0.45), frame_s)
				box(g, Vector3(sx - 0.05, 0.73, 0.05), Vector3(sx + 0.95, 0.77, 0.5), frame_s)
				box(g, Vector3(sx + 0.1, 0.2, 0.15), Vector3(sx + 0.8, 0.24, 0.27), mat(Color(0.5, 0.35, 0.2), 0.7))
			box(g, Vector3(w / 2.0, 0.05, 0.55), Vector3(w / 2.0 + 0.04, 1.0, 0.59), frame_s)
			box(g, Vector3(w / 2.0 - 0.1, 0.88, 0.54), Vector3(w / 2.0 + 0.14, 1.06, 0.6), mat(Color(0.85, 0.12, 0.12), 0.5))
			_lettering(g, "SHUTTLE", Vector3(w / 2.0 + 0.02, 0.97, 0.61), Color.WHITE, 0.0025, 24)
			for k in 2:
				_bus(g, Vector3(0.3 + k * 2.8, 0.0, 0.85))
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
func _stand_slots(layout: Layout, s: Stand, per_tile: int, lines := 2) -> Array:
	var out := []
	var cols := ceili(per_tile / float(lines))
	var tp := to_pitch(s.side).normalized()
	var along := Vector2(-tp.y, tp.x)
	# aisle centres (distance along the stand) to keep clear for the gangways
	var aisles := []
	var along_abs := along.abs()
	var lower := tiles_xz(s.lower_tiles(layout.pitch))
	var origin := lower.position
	var voms: Array[float] = []
	var vr := vom_rows(s)
	if not s.is_corner():
		var L := lower.size.x if tp.x == 0.0 else lower.size.y
		var n := aisle_count(s, L)
		for g in n:
			aisles.append((g + 0.5) * L / n)
		voms = vom_centres(s, L)
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
			var y_row := tier_base(s, tier) + row_height(v, s)
			for tile in row_tiles:
				var centre := Vector2(tile) + Vector2(0.5, 0.5)
				for k in per_tile:
					var a := (float(k % cols) + 0.5) / cols - 0.5
					var li: int = k / cols
					var depth_off := (0.22 - li * 0.32) if lines == 2 else (0.3 - li * 0.6 / (lines - 1))
					var pos := centre + along * a * 0.9 + tp * depth_off
					if s.is_corner():
						# keep the diagonal gangway clear
						var cf := corner_frame(s.side, layout.pitch)
						var rel: Vector2 = pos - cf["centre"]
						if absf(rel.x * float(cf["sx"]) - rel.y * float(cf["sz"])) < 0.36:
							continue
					if tier == 0 and v >= vr.x and v <= vr.y and not voms.is_empty():
						var uv := (pos - origin).dot(along_abs)
						var in_vom := false
						for vc in voms:
							if absf(uv - vc) < 0.75:
								in_vom = true
						if in_vom:
							continue
					if not aisles.is_empty():
						var u := (pos - origin).dot(along_abs)
						var in_aisle := false
						for ax in aisles:
							if absf(u - ax) < 0.24:
								in_aisle = true
						if in_aisle:
							continue
					out.append([pos, y_row, tier, v, tp, along, li, lines])
	return out


var _seat_node: MultiMeshInstance3D
const SEATS_ACROSS := 5   # seats drawn per tile along the row
const SEAT_LINES := 3     # seat lines drawn per tile of depth


## Fold-down seats (pan + backrest) in every seated stand, in the stand's seat colour.
func build_seats(layout: Layout, config: SimConfig) -> void:
	if _seat_node == null:
		_seat_node = MultiMeshInstance3D.new()
		_solids.get_parent().add_child(_seat_node)
	for c in _seat_node.get_children():
		c.free()
	var by_kind := {}
	for s in layout.stands:
		if not has_seats(s):
			continue
		var d := s.extra("detail")
		var kind := "%s|%s" % [d["seat_style"], d["back"]]
		if not by_kind.has(kind):
			var ex: Array[Transform3D] = []
			var ec: Array[Color] = []
			by_kind[kind] = [ex, ec]
		var slots := _stand_slots(layout, s, SEATS_ACROSS * SEAT_LINES, SEAT_LINES)
		var pat := _seat_pattern(layout, s, slots)
		for i in slots.size():
			var slot: Array = slots[i]
			var p: Vector2 = slot[0]
			var tp: Vector2 = slot[4]
			by_kind[kind][0].append(Transform3D(Basis(Vector3.UP, atan2(tp.x, tp.y)).scaled(Vector3(0.62, 0.9, 0.8)), Vector3(p.x, slot[1], p.y)))
			by_kind[kind][1].append(pat[i])
	_seat_node.multimesh = null
	for kind in by_kind:
		var xf: Array[Transform3D] = by_kind[kind][0]
		var cols: Array[Color] = by_kind[kind][1]
		var parts := String(kind).split("|")
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _seat_mesh(parts[0], parts[1])
		mm.instance_count = xf.size()
		for i in xf.size():
			mm.set_instance_transform(i, xf[i])
			mm.set_instance_color(i, cols[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.75 if parts[0] == "padded" else 0.5
		mi.material_override = m
		_seat_node.add_child(mi)


var _seat_meshes := {}


## A seat facing local +Z (toward the pitch). Styles: tip-up (pan, back,
## stem), bucket (one moulded shell), padded (thick cushions with armrests),
## bench (a plank without backs). Backs low, standard or high.
func _seat_mesh(style := "tipup", back := "standard") -> Mesh:
	var key := style + back
	if _seat_meshes.has(key):
		return _seat_meshes[key]
	var bh: float = { "low": 0.14, "standard": 0.22, "high": 0.34 }.get(back, 0.22)
	var parts := []
	match style:
		"bucket":
			parts = [[Vector3(0, 0.12, 0.0), Vector3(0.21, 0.04, 0.19)], [Vector3(0, 0.12 + bh / 2.0, -0.09), Vector3(0.21, bh, 0.035)],
				[Vector3(-0.1, 0.17, -0.02), Vector3(0.02, 0.1, 0.16)], [Vector3(0.1, 0.17, -0.02), Vector3(0.02, 0.1, 0.16)], [Vector3(0, 0.05, -0.03), Vector3(0.06, 0.1, 0.06)]]
		"padded":
			parts = [[Vector3(0, 0.13, 0.0), Vector3(0.22, 0.07, 0.2)], [Vector3(0, 0.15 + bh / 2.0, -0.09), Vector3(0.22, bh + 0.04, 0.07)],
				[Vector3(-0.12, 0.2, -0.01), Vector3(0.03, 0.04, 0.2)], [Vector3(0.12, 0.2, -0.01), Vector3(0.03, 0.04, 0.2)], [Vector3(0, 0.06, -0.03), Vector3(0.18, 0.1, 0.05)]]
		"bench":
			parts = [[Vector3(0, 0.12, 0.0), Vector3(0.3, 0.03, 0.16)], [Vector3(0, 0.06, -0.02), Vector3(0.03, 0.12, 0.1)]]
		_:
			parts = [[Vector3(0, 0.13, 0.0), Vector3(0.2, 0.03, 0.17)], [Vector3(0, 0.14 + bh / 2.0, -0.09), Vector3(0.2, bh, 0.03)], [Vector3(0, 0.06, -0.02), Vector3(0.04, 0.12, 0.04)]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var bm := BoxMesh.new()
		bm.size = part[1]
		st.append_from(bm, 0, Transform3D(Basis(), part[0]))
	_seat_meshes[key] = st.commit()
	return _seat_meshes[key]


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


var _pitch_centre := Vector2.ZERO


func build_crowd(layout: Layout, config: SimConfig, report: MatchdayReport) -> void:
	build_seats(layout, config)
	_pitch_centre = Vector2(layout.pitch.get_center())
	if _crowd_standing == null:
		_crowd_standing = MultiMeshInstance3D.new()
		_crowd.get_parent().add_child(_crowd_standing)
		_crowd_mat_standing = ShaderMaterial.new()
		_crowd_mat_standing.shader = _crowd_mat.shader
	var sets := { true: [[], [], []], false: [[], [], []] }   # seated? -> [transforms, colours, customs]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	# away fans: a block at one end of an end stand, in their club's colours,
	# with a strip of empty seats between them and the home fans
	var away_i := -1
	var away_col := Color.WHITE
	var away_frac := 0.0
	if report != null and report.home:
		away_i = _away_stand(layout, config)
		away_col = _away_colour(report.opponent)
		away_frac = clampf(0.12 + 0.002 * float(report.attendance) / 1000.0, 0.12, 0.3)
	if report != null:
		for i in layout.stands.size():
			var s := layout.stands[i]
			var t := config.stand_type(s.type_id)
			if i >= report.stands.size() or report.stands[i]["capacity"] != s.capacity(t):
				continue
			var lower_r := tiles_xz(s.lower_tiles(layout.pitch))
			var s_len := lower_r.size.x if s.side in ["N", "S"] else lower_r.size.y
			var fill: float = report.stands[i]["fill"]
			var tifo := matchday_live and i == tifo_stand(layout, config, report)
			if tifo:
				fill = maxf(fill, 0.98)
			var seated := has_seats(s)
			var bucket: Array = sets[seated]
			var origin := tiles_xz(s.lower_tiles(layout.pitch)).position
			for slot in _stand_slots(layout, s, maxi(1, roundi(t.capacity_per_tile / FIGURES_PER_PLACES))):
				# a part-full stand fills the middle and the front first: the ends
				# and the back rows are where the empty seats show
				var local_fill := fill
				if fill < 0.98 and not s.is_corner():
					var uu := ((slot[0] as Vector2) - origin).dot((slot[5] as Vector2).abs()) / maxf(1.0, s_len)
					var centre := 1.0 - 2.0 * absf(uu - 0.5)
					var front := 1.0 - float(slot[3]) / maxf(1.0, s.depth - 1.0)
					local_fill = clampf(fill + (1.0 - fill) * ((centre - 0.5) * 0.9 + (front - 0.5) * 0.5), 0.0, 1.0)
				if rng.randf() >= local_fill:
					continue
				var p: Vector2 = slot[0] + Vector2(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03))
				var tp: Vector2 = slot[4]
				var along: Vector2 = slot[5]
				var sc := rng.randf_range(0.88, 1.1)
				var y: float = slot[1] + (0.16 if seated else 0.0)
				var basis := Basis(Vector3.UP, atan2(tp.x, tp.y) + rng.randf_range(-0.25, 0.25)).scaled(Vector3(sc, sc, sc))
				var kind := 0.5 if rng.randf() < 0.3 else 0.0
				var u_along := (p - origin).dot(along.abs())
				var in_away := i == away_i and u_along > s_len * (1.0 - away_frac)
				if i == away_i and not in_away and u_along > s_len * (1.0 - away_frac) - 1.0:
					continue   # the segregation gap
				if tifo and slot[2] == 0 and not in_away:
					basis = Basis(Vector3.UP, atan2(tp.x, tp.y)).scaled(Vector3(2.2, 1.0, 2.2))
					bucket[1].append(_tifo_color(report.seed, slot[3], s.depth, u_along))
					kind = 1.0
				elif in_away:
					var ar := rng.randf()
					bucket[1].append(away_col if ar < 0.65 else (Color(0.95, 0.95, 0.95) if ar < 0.8 else Color.from_hsv(rng.randf(), 0.2, rng.randf_range(0.2, 0.6))))
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


## The stand the away fans get: an end stand (east or west), the one that isn't
## the home end, else any side stand that isn't premium. -1 if none.
func _away_stand(layout: Layout, config: SimConfig) -> int:
	var best := -1
	var best_cap := -1
	for pass_ends in [true, false]:
		for i in layout.stands.size():
			var s := layout.stands[i]
			if s.is_corner() or s.type_id == "premium" or s.type_id == "family":
				continue
			if pass_ends and not s.side in ["E", "W"]:
				continue
			var cap := s.capacity(config.stand_type(s.type_id))
			# prefer the smaller end: the bigger one is the home end
			if best < 0 or cap < best_cap:
				best = i
				best_cap = cap
		if best >= 0:
			return best
	return best


## A visiting club's colour, made up from its name (so it's always the same),
## never too close to ours.
func _away_colour(opponent: String) -> Color:
	var h := float(absi(hash(opponent)) % 360) / 360.0
	var c := Color.from_hsv(h, 0.75, 0.8)
	if _club and absf(c.h - _club.primary_color.h) < 0.12:
		c = Color.from_hsv(fmod(h + 0.5, 1.0), 0.75, 0.8)
	return c


## Matchday moments on the crowd: scarves held up before kick-off, a surge
## of arms and jumping when the home side scores (0..1 each).
func set_crowd_moment(scarves: float, surge: float, mexican := 0.0) -> void:
	for m in [_crowd_mat, _crowd_mat_standing]:
		if m:
			(m as ShaderMaterial).set_shader_parameter("scarves", scarves)
			(m as ShaderMaterial).set_shader_parameter("surge", surge)
			(m as ShaderMaterial).set_shader_parameter("mexican", mexican)
			(m as ShaderMaterial).set_shader_parameter("ground_centre", _pitch_centre)


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
	_drop_marker(tiles_xz(s.tiles(pitch)), 0.0, row_height(s.depth - 1, s), ok)


## Moving the pitch: the new pitch, every stand outlined where it would end
## up, and the stands that would have to go shown in red where they stand now.
func show_pitch_move(layout: Layout, at: Vector2i, ok: bool, gone: Array) -> void:
	clear_overlay()
	_drop_marker(Rect2(Vector2(at), Vector2(layout.pitch.size)), 0.0, 0.3, ok)
	var moved := Rect2i(at, layout.pitch.size)
	for i in layout.stands.size():
		var s := layout.stands[i]
		var h := stand_top(s) + ROOF_CLEARANCE + 2.5
		if i in gone:
			var r := tiles_xz(s.tiles(layout.pitch))
			box(_overlay, Vector3(r.position.x - 0.15, -0.05, r.position.y - 0.15), Vector3(r.end.x + 0.15, h, r.end.y + 0.15), mat(C_NO, 1.0, 0.0, 0.6, 0.5), false)
			_rect_outline(_overlay, r.grow(0.2), 0.08, mat(C_NO, 1.0, 0.0, 0.0, 0.95), 0.3)
		elif ok:
			_rect_outline(_overlay, tiles_xz(s.tiles(moved)), 0.08, mat(C_OK, 1.0, 0.0, 0.0, 0.8), 0.18)


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


# --- geometry helpers -------------------------------------------------------

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
	# no automatic paving any more: the player paints roads and paths
	var busy := {}
	for t in layout.stand_tile_map():
		busy[t] = true
	for t in layout.concourse_tile_map(config):
		busy[t] = true
	var paved := layout.site
	_build_site(layout, config)
	# the rest of the club's land is open grass, with tufts for close views
	var tufts: Array[Transform3D] = []
	var tufts_c: Array[Color] = []
	var trng := RandomNumberGenerator.new()
	trng.seed = 31
	for x in range(plot.position.x, plot.end.x):
		for y in range(plot.position.y, plot.end.y):
			var t := Vector2i(x, y)
			if paved.has(t) or busy.has(t) or (layout.pitch_placed and layout.pitch.has_point(t)):
				continue
			# an even, low lawn: a jittered grid of short tufts in the ground's own
			# colours, so close up it reads as grass rather than scattered clumps
			for k in 9:
				var sc := trng.randf_range(0.05, 0.08)
				var gx := x + (k % 3 + trng.randf()) / 3.0
				var gz := y + (k / 3 + trng.randf()) / 3.0
				tufts.append(Transform3D(Basis(Vector3.UP, trng.randf() * TAU).scaled(Vector3(sc * 2.6, sc, sc * 2.6)), Vector3(gx, -0.005, gz)))
				tufts_c.append(Color(0.78, 0.84, 0.7).lerp(Color(0.9, 0.9, 0.7), trng.randf() * 0.4))
	if not tufts.is_empty():
		var tmm := MultiMesh.new()
		tmm.transform_format = MultiMesh.TRANSFORM_3D
		tmm.use_colors = true
		tmm.mesh = ProcTrees.tuft_mesh()
		tmm.instance_count = tufts.size()
		for i in tufts.size():
			tmm.set_instance_transform(i, tufts[i])
			tmm.set_instance_color(i, tufts_c[i])
		var tmi := MultiMeshInstance3D.new()
		tmi.multimesh = tmm
		tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tmi.visibility_range_end = 45.0
		tmi.visibility_range_end_margin = 10.0
		tmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		_land.add_child(tmi)
	# a low post-and-rail fence round the boundary
	var r := Rect2(plot)
	var posts: Array[Transform3D] = []
	var rails: Array[Transform3D] = []
	for edge in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.position.x, r.end.y), r.end], [r.position, Vector2(r.position.x, r.end.y)], [Vector2(r.end.x, r.position.y), r.end]]:
		var e0: Vector2 = edge[0]
		var e1: Vector2 = edge[1]
		var n := int(e0.distance_to(e1) / 1.5)
		for i in n + 1:
			var q := e0.lerp(e1, float(i) / maxf(1.0, n))
			posts.append(Transform3D(Basis().scaled(Vector3(0.06, 0.5, 0.06)), Vector3(q.x, 0.25, q.y)))
		var mid := (e0 + e1) / 2.0
		var horiz := absf(e1.x - e0.x) > absf(e1.y - e0.y)
		for hgt in [0.22, 0.42]:
			rails.append(Transform3D(Basis().scaled(Vector3(e0.distance_to(e1) if horiz else 0.04, 0.04, 0.04 if horiz else e0.distance_to(e1))), Vector3(mid.x, hgt, mid.y)))
	var wood := mat(Color(0.42, 0.34, 0.26), 0.9)
	_mm(_land, posts, wood)
	_mm(_land, rails, wood)
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



## Cable-stayed roof: tall masts behind the stand hold the front edge up with ties.
func _roof_masts(roof: Node3D, L: float, D: float, top: float, length: int) -> void:
	var front_y := top + ROOF_CLEARANCE + 0.25
	var back_y := top + ROOF_CLEARANCE - 0.35
	var z0 := -D / 2.0
	var z1 := D / 2.0 + 0.7
	var masts: Array[Transform3D] = []
	var ties: Array[Transform3D] = []
	# the player's pylon count and height steer the masts too (else by length)
	var n := maxi(2, ceili(length / 8.0) + 1)
	if _rs.has("pylon_count") and String(_rs.get("pylons", "none")) == "none" and int(_rs["pylon_count"]) != 2:
		n = clampi(int(_rs["pylon_count"]), 2, 8)
	var mh := 4.5 * clampf(float(_rs.get("pylon_h", 1.0)), 0.5, 3.0)
	for k in n:
		var x := (float(k) / float(n - 1) - 0.5) * (L - 0.6)
		var foot := Vector3(x, 0.0, z0 - 0.6)
		var head := Vector3(x, back_y + mh, z0 - 1.0)
		masts.append(_rod(foot, head, 0.28))
		ties.append(_rod(head, Vector3(x, front_y, z1 - 0.1), 0.05))
		ties.append(_rod(head, Vector3(x, front_y, (z0 + z1) / 2.0), 0.05))
		ties.append(_rod(head, Vector3(x, 0.0, z0 - 3.0), 0.05))
	_mm(roof, masts, mat(_club.primary_color, 0.45, 0.3))
	_mm(roof, ties, mat(Color(0.2, 0.2, 0.22), 0.4, 0.6), false)


## The stand's switchable add-ons (Stand.EXTRAS): its name, flags, LED strip,
## a clock and fan banners.
func _stand_extras(s: Stand, is_main: bool, fr: Node3D, roof: Node3D, L: float, D: float, roof_y: float, roof_z: float) -> void:
	var has_roof := s.roof != "open"
	var nm := s.extra("name")
	if bool(nm["on"]):
		var o: Dictionary = nm.duplicate()
		var text: String = nm["text"]
		if text == "":
			text = (ground_name if ground_name != "" else _club.stadium_name) if is_main else stand_title(s, false)
		o["text"] = text
		var own: Dictionary = s.extras.get("name", {})
		if not own.has("scale"):
			o["scale"] = { "S": 0.6, "M": 1.0, "L": 1.5 }.get(nm["size"], 1.0)
		if String(nm["light"]) == "":
			o["light"] = "inside" if bool(nm["lit"]) else "none"
		var where: String = nm["where"]
		if where == "tier" and s.tiers < 2:
			where = "roof"
		if (where == "roof" or where == "roof_top") and not has_roof:
			where = "wall"
		var sign: Node3D
		match where:
			"roof":
				o["scale"] = float(o["scale"]) * 0.8
				sign = Signs.build(roof, o, _club.secondary_color, _club.primary_color, L * 0.92, _glow, _night_light)
				# stand proud of the fascia (a light box is deep, so it comes out further)
				var proud := 0.36 if String(o["mount"]) == "box" else (0.12 if String(o["mount"]) == "panel" else 0.08)
				sign.position = Vector3(0, roof_y, roof_z + proud)
			"roof_top":
				sign = Signs.build(roof, o, _club.secondary_color, _club.primary_color, L * 0.92, _glow, _night_light)
				sign.position = Vector3(0, roof_y + 0.75 + 0.45 * float(o["scale"]), roof_z - 0.4)
			"tier":
				var k := s.tiers - 1
				sign = Signs.build(fr, o, _club.secondary_color, _club.primary_color, L * 0.9, _glow, _night_light)
				sign.position = Vector3(0, tier_base(s, k) - 0.15, D / 2.0 - tier_front(s, k) + 0.1)
			_:
				if not _wall_spot.is_empty():
					var wf: Node3D = _wall_spot[0]
					sign = Signs.build(wf, o, _club.secondary_color, _club.primary_color, L * 0.9, _glow, _night_light)
					sign.position = Vector3(0, float(_wall_spot[2]) - 0.9 - 0.4 * float(o["scale"]), float(_wall_spot[1]) - 0.1)
					sign.rotation.y = PI
	if has_roof and bool(s.extra("lights")["on"]):
		var strip := lbox(roof, Vector3(0, roof_y - 0.33, roof_z + 0.03), Vector3(L - 0.2, 0.06, 0.03), mat(Color(1.0, 0.97, 0.9), 0.3, 0.0, 3.0))
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if has_roof and bool(s.extra("flags")["on"]):
		var poles: Array[Transform3D] = []
		var n := maxi(2, int(L / 4.0))
		for k in n:
			var x := (float(k) + 0.5) / n * L - L / 2.0
			poles.append(Transform3D(Basis().scaled(Vector3(0.05, 1.8, 0.05)), Vector3(x, roof_y + 1.15, roof_z - 0.25)))
			var flag := lbox(roof, Vector3(x + 0.38, roof_y + 1.75, roof_z - 0.25), Vector3(0.7, 0.45, 0.02),
				mat(_club.primary_color if k % 2 == 0 else _club.secondary_color, 0.8))
			flag.rotation.y = 0.15 * (1.0 if k % 2 == 0 else -1.0)
		_mm(roof, poles, mat(Color(0.85, 0.86, 0.88), 0.35, 0.6))
	if has_roof and bool(s.extra("clock")["on"]):
		var face := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.55
		cm.bottom_radius = 0.55
		cm.height = 0.08
		face.mesh = cm
		face.material_override = mat(Color(0.96, 0.95, 0.9), 0.5, 0.0, 0.4)
		face.rotation.x = PI / 2.0
		var cx := L / 2.0 - 2.0
		face.position = Vector3(cx, roof_y + 1.0, roof_z)
		roof.add_child(face)
		lbox(roof, Vector3(cx, roof_y + 1.0, roof_z - 0.12), Vector3(1.3, 1.3, 0.16), mat(_club.primary_color.darkened(0.3), 0.5))
		var hand := lbox(roof, Vector3(cx + 0.12, roof_y + 1.12, roof_z + 0.06), Vector3(0.05, 0.38, 0.02), mat(Color(0.05, 0.05, 0.05), 0.5))
		hand.rotation.z = -0.8
		lbox(roof, Vector3(cx, roof_y + 1.22, roof_z + 0.07), Vector3(0.05, 0.46, 0.02), mat(Color(0.05, 0.05, 0.05), 0.5))
		lbox(roof, Vector3(cx, roof_y + 0.4, roof_z - 0.12), Vector3(0.12, 0.6, 0.12), mat(Color(0.25, 0.26, 0.28), 0.5, 0.6))
	var lg := s.extra("logo")
	if has_roof and bool(lg["on"]):
		var h: float = { "S": 1.3, "M": 2.0, "L": 2.9 }[lg["size"]]
		if float(lg["scale"]) > 0.0:
			h = 2.0 * float(lg["scale"])
		var x: float = { "centre": 0.0, "left": -L * 0.32, "right": L * 0.32 }[lg["where"]]
		_crest(roof, Vector3(x, roof_y + 0.35 + h / 2.0, roof_z - 0.3), h, 0.0, bool(lg["lit"]), String(lg["mount"]), String(lg["light"]))
		lbox(roof, Vector3(x, roof_y + 0.2, roof_z - 0.35), Vector3(0.1, 0.5, 0.1), mat(Color(0.3, 0.31, 0.33), 0.4, 0.6))
	if bool(s.extra("banners")["on"]) and not s.is_corner():
		var slogans := ["ONE CLUB", "TOGETHER", "SINCE 1887", "OUR TOWN", "NEVER ALONE", "HOME", "LOYAL"]
		var n := maxi(1, int(L / 5.0))
		for k in n:
			var x := (float(k) + 0.5) / n * L - L / 2.0
			var c := _club.primary_color if k % 2 == 0 else _club.secondary_color
			lbox(fr, Vector3(x, s.plinth + 0.32, D / 2.0 + 0.06), Vector3(3.2, 0.5, 0.02), mat(c, 0.9))
			var lab := Label3D.new()
			lab.text = slogans[(k + s.offset) % slogans.size()]
			lab.font_size = 40
			lab.pixel_size = 0.006
			lab.outline_size = 0
			lab.modulate = _club.secondary_color if k % 2 == 0 else _club.primary_color
			lab.position = Vector3(x, s.plinth + 0.32, D / 2.0 + 0.08)
			fr.add_child(lab)


## Corner stands get the same extras on a frame set across the corner's
## diagonal, facing the pitch corner. The name always sits on the roof.
func _corner_extras(root: Node3D, s: Stand, pitch: Rect2i, top: float, R: float) -> void:
	var cf := corner_frame(s.side, pitch)
	var u := Vector2(cf["sx"], cf["sz"]).normalized()
	var c: Vector2 = cf["centre"]
	var fr := Node3D.new()
	var o := c + u * R * 0.62
	fr.position = Vector3(o.x, 0, o.y)
	fr.rotation.y = atan2(-u.x, -u.y)
	root.add_child(fr)
	var roof := Node3D.new()
	fr.add_child(roof)
	if s.roof != "open":
		_roofs.append(roof)
		roof.visible = show_roofs
	_wall_spot = []
	var L := R * 0.95
	_stand_extras(s, false, fr, roof, L, 1.0, top + ROOF_CLEARANCE + 0.6, 0.0)


func _light_name(t: Label3D, col: Color, lit: bool) -> void:
	if not _night:
		t.modulate = col
		t.outline_modulate = _club.primary_color.darkened(0.45)
	elif lit:
		# lit letters: bright face and a glowing halo that blooms at night
		t.modulate = Color(col.r * 6.0 + 1.0, col.g * 6.0 + 1.0, col.b * 6.0 + 1.0)
		t.outline_modulate = Color(col.r * 3.0, col.g * 3.0, col.b * 3.0, 0.9)
	else:
		t.modulate = col.darkened(0.8)
		t.outline_modulate = Color(0, 0, 0)



# --- seat patterns -------------------------------------------------------------

## 5x7 letters for spelling words in seats.
const GLYPHS := {
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"], "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"], "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"], "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"G": ["01111", "10000", "10000", "10011", "10001", "10001", "01111"], "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"], "J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
	"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"], "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"], "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"], "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"], "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"], "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"], "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
	"W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"], "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"], "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
	"0": ["01110", "10011", "10101", "10101", "10101", "11001", "01110"], "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"], "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"], "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
	"6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"], "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"], "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
	" ": ["000", "000", "000", "000", "000", "000", "000"], "-": ["000", "000", "000", "111", "000", "000", "000"],
	".": ["0", "0", "0", "0", "0", "0", "1"], "'": ["1", "1", "0", "0", "0", "0", "0"], "&": ["01100", "10010", "10100", "01000", "10101", "10010", "01101"],
}

## A colour for every seat slot. Patterns are laid out on a grid of seat
## columns (along the stand) and rows (all tiers stacked, top row first), so
## text reads from the pitch.
func _seat_pattern(layout: Layout, s: Stand, slots: Array) -> Array[Color]:
	var cfg := s.extra("seats")
	var a := seat_color(s)
	var b: Color = Color.html(cfg["color2"]) if String(cfg["color2"]) != "" else (_club.secondary_color if a.is_equal_approx(_club.primary_color) else _club.primary_color)
	var pat: String = cfg["pattern"]
	var out: Array[Color] = []
	if slots.is_empty():
		return out
	# grid coordinates: column from the position along the stand, row from tier/row
	var cols := []
	var rows := []
	var max_row := 0
	var min_u := INF
	var max_u := -INF
	# pattern rows: one per line of seats, all tiers stacked
	var lines := []
	var per_row := 1
	for sl in slots:
		per_row = int(sl[7]) if sl.size() > 7 else 1
		lines.append(int(sl[3]) * per_row + (int(sl[6]) if sl.size() > 6 else 0))
		var row: int = int(sl[2]) * s.depth + int(sl[3])
		rows.append(row)
		max_row = maxi(max_row, row)
		var along: Vector2 = sl[5]
		var u: float
		if s.is_corner():
			var cf := corner_frame(s.side, layout.pitch)
			var rel: Vector2 = (sl[0] as Vector2) - cf["centre"]
			u = atan2(rel.y * float(cf["sz"]), rel.x * float(cf["sx"])) * (row + 2.0)
		else:
			u = (sl[0] as Vector2).dot(along)   # left to right as seen from the pitch
		cols.append(u)
		min_u = minf(min_u, u)
		max_u = maxf(max_u, u)
	# pattern columns: fixed-width cells along the stand (seat lines are staggered,
	# so cells are measured in metres rather than counted seats)
	var cell_w := 0.3
	var ncols := int((max_u - min_u) / cell_w) + 1
	var nrows := max_row + 1
	var bitmap := {}
	if pat == "text" or pat == "crest":
		# words and crests go on the lower tier only, so a tier's fascia never cuts them
		bitmap = _seat_bitmap(pat, cfg["text"], ncols, s.depth * per_row)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(s.side) + s.offset
	for i in slots.size():
		var cx := int((float(cols[i]) - min_u) / cell_w)
		var ry := max_row - int(rows[i])     # 0 = back row
		var use_b := false
		match pat:
			"stripes": use_b = int(rows[i]) % 2 == 1
			"blocks": use_b = (cx / 12) % 2 == 1
			"checks": use_b = ((cx / 6) + (int(rows[i]) / 2)) % 2 == 1
			"mosaic":
				var r := rng.randf()
				out.append(a.lerp(b, 0.15) if r < 0.3 else (a.darkened(0.12) if r < 0.6 else a))
				continue
			"text", "crest":
				use_b = int(slots[i][2]) == 0 and bitmap.has(Vector2i(cx, s.depth * per_row - 1 - int(lines[i])))
		out.append(b if use_b else a)
	return out


## Seat cells (column, row from the back) that take the second colour:
## the word centred on the stand, or a shield shape for the crest.
func _seat_bitmap(pat: String, text: String, ncols: int, nrows: int) -> Dictionary:
	var cells := {}
	if pat == "crest":
		var h := mini(nrows - 2, 16)
		if h < 4:
			return cells
		var w := int(h * 2.4)
		var x0 := ncols / 2 - w / 2
		var y0 := (nrows - h) / 2
		for y in h:
			var f := float(y) / h
			var half := w / 2.0 if f < 0.55 else w / 2.0 * (1.0 - (f - 0.55) / 0.45)
			for x in w:
				var dx := absf(x - w / 2.0 + 0.5)
				if dx <= half:
					# a filled shield with a band across it in the base colour
					var band := absi(y - h / 3) <= maxi(1, h / 10) and dx < half - 1.0
					if not band:
						cells[Vector2i(x0 + x, y0 + y)] = true
		return cells
	if text == "":
		text = _club.club_name
	text = text.to_upper()
	# letters 7 rows high; shrink to fit by dropping to initials if it is too long
	var width := 0
	for ch in text:
		width += (GLYPHS.get(ch, GLYPHS[" "]) as Array)[0].length() + 1
	if width > ncols:
		var initials := ""
		for word in text.split(" ", false):
			initials += word[0]
		text = initials
		width = 0
		for ch in text:
			width += (GLYPHS.get(ch, GLYPHS[" "]) as Array)[0].length() + 1
	# 7 rows tall (each glyph row stretched over several seat lines on deep
	# stands), or squashed to 5 on shallow ones
	var gys: Array = [0, 1, 2, 3, 4, 5, 6] if nrows >= 7 else [0, 2, 3, 4, 6]
	var stretch := clampi(nrows / 9, 1, 3)
	var tall: Array = []
	for gy in gys:
		for k in stretch:
			tall.append(gy)
	gys = tall
	if nrows < 5:
		return cells
	var x := ncols / 2 - width / 2
	var y0 := (nrows - gys.size()) / 2
	for ch in text:
		var g: Array = GLYPHS.get(ch, GLYPHS[" "])
		for row in gys.size():
			var gy: int = gys[row]
			var line: String = g[gy]
			for gx in line.length():
				if line[gx] == "1":
					cells[Vector2i(x + gx, y0 + row)] = true
		x += (g[0] as String).length() + 1
	return cells
