extends RefCounted
## Signs with real mass: extruded 3D letters (TextMesh) in a choice of fonts,
## mounted one of five ways, lit one of five ways. Used for stand names and any
## other lettering in the world. A sign is built around its own origin, facing
## +Z (readable from +Z), and registers what glows at night with the renderer.
##
## Options (all optional):
##   text, line2      the words (line2 is a smaller second line underneath)
##   mount            painted | letters | panel | box | frame
##   font             classic | future | narrow | blocks | rocket | high | pixel
##   depth            letter depth in metres (3D letters)
##   color, panel     html colours of the letters and the panel ("" = default)
##   light            none | flood | halo | inside | neon
##   light_color      html colour of the light ("" = warm white / letter colour)
##   scale            letter height multiplier
##   align            left | centre | right (within max_width)

const MOUNTS := ["painted", "letters", "panel", "box", "frame"]
const FONTS := ["classic", "future", "narrow", "blocks", "rocket", "high", "pixel"]
const LIGHTS := ["none", "flood", "halo", "inside", "neon"]
const ALIGNS := ["left", "centre", "right"]
const FONT_NAMES := { "classic": "Classic", "future": "Future", "narrow": "Narrow", "blocks": "Blocks", "rocket": "Rocket", "high": "Tall", "pixel": "Pixel" }
const MOUNT_NAMES := { "painted": "Painted", "letters": "3D letters", "panel": "On a panel", "box": "Light box", "frame": "On a frame" }
const LIGHT_NAMES := { "none": "Unlit", "flood": "Floodlit", "halo": "Backlit", "inside": "Lit letters", "neon": "Neon" }

static var _fonts := {}


static func font(id: String) -> Font:
	if id == "classic" or id == "":
		return ThemeDB.fallback_font
	if not _fonts.has(id):
		var path := "res://assets/kenney/fonts/%s.ttf" % id
		_fonts[id] = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	return _fonts[id]


static func _col(html: String, fallback: Color) -> Color:
	return Color.html(html) if html != "" and Color.html_is_valid(html) else fallback


## Builds the sign under `parent` and returns its root. `glow` is called as
## glow.call(material, day_energy, night_energy) and `night_light` as
## night_light.call(light) so the renderer can switch them with the time of day.
static func build(parent: Node3D, o: Dictionary, base_col: Color, trim_col: Color, max_width: float, glow: Callable, night_light: Callable) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	var text := String(o.get("text", "")).to_upper()
	if text.strip_edges() == "":
		return root
	var mount: String = o.get("mount", "letters")
	var light: String = o.get("light", "none")
	var letter_c := _col(String(o.get("color", "")), base_col)
	var panel_c := _col(String(o.get("panel", "")), trim_col)
	var light_c := _col(String(o.get("light_color", "")), Color(1.0, 0.95, 0.85) if light == "flood" else letter_c)
	var scale: float = clampf(float(o.get("scale", 1.0)), 0.2, 3.0)
	var depth: float = 0.004 if mount == "painted" else clampf(float(o.get("depth", 0.08)), 0.01, 0.4)
	if light == "neon":
		depth = minf(depth, 0.03)
	# the letters: a real extruded mesh, sized to a target cap height
	var cap := 0.55 * scale
	var tm := TextMesh.new()
	tm.font = font(String(o.get("font", "classic")))
	tm.font_size = 64
	tm.text = text
	tm.depth = depth
	tm.curve_step = 1.5
	tm.pixel_size = cap / 46.0
	var w := tm.get_aabb().size.x
	if max_width > 0.0 and w > max_width * 0.96:
		tm.pixel_size *= max_width * 0.96 / w
		w = tm.get_aabb().size.x
		cap = tm.pixel_size * 46.0
	var h := tm.get_aabb().size.y
	var x := 0.0
	match String(o.get("align", "centre")):
		"left": x = -max_width / 2.0 + w / 2.0 + 0.2 if max_width > 0.0 else 0.0
		"right": x = max_width / 2.0 - w / 2.0 - 0.2 if max_width > 0.0 else 0.0
	var line2 := String(o.get("line2", "")).to_upper()
	var tm2: TextMesh = null
	var h2 := 0.0
	if line2.strip_edges() != "":
		tm2 = TextMesh.new()
		tm2.font = tm.font
		tm2.font_size = 64
		tm2.text = line2
		tm2.depth = depth
		tm2.pixel_size = tm.pixel_size * 0.5
		if max_width > 0.0 and tm2.get_aabb().size.x > max_width * 0.96:
			tm2.pixel_size *= max_width * 0.96 / tm2.get_aabb().size.x
		h2 = tm2.get_aabb().size.y + 0.08
	var total_h := h + h2
	var pad := 0.18 * scale
	# the letter material: its own, so it can glow at night
	var lm := StandardMaterial3D.new()
	lm.albedo_color = letter_c
	lm.roughness = 0.35 if mount != "painted" else 0.8
	lm.metallic = 0.3 if mount in ["letters", "frame"] else 0.0
	var front := 0.0   # z of the face the letters stand on
	# the mounting
	match mount:
		"panel", "box":
			var thick := 0.06 if mount == "panel" else 0.32
			var pw := w + pad * 2.0
			var ph := total_h + pad * 2.0
			var pm := StandardMaterial3D.new()
			pm.albedo_color = panel_c
			pm.roughness = 0.5
			_box(root, Vector3(x, 0, -thick / 2.0), Vector3(pw, ph, thick), pm)
			if mount == "box":
				# a frame round the light box
				var fm := StandardMaterial3D.new()
				fm.albedo_color = panel_c.darkened(0.45)
				fm.metallic = 0.5
				fm.roughness = 0.4
				for e in [-1.0, 1.0]:
					_box(root, Vector3(x + e * (pw / 2.0 + 0.03), 0, -thick / 2.0), Vector3(0.06, ph + 0.12, thick + 0.04), fm)
					_box(root, Vector3(x, e * (ph / 2.0 + 0.03), -thick / 2.0), Vector3(pw + 0.12, 0.06, thick + 0.04), fm)
				if light == "inside" and panel_c.get_luminance() >= 0.4:
					# a pale face glows; the letters stand out dark against it
					pm.emission_enabled = true
					pm.emission = panel_c
					glow.call(pm, 0.0, 1.8)
					lm.albedo_color = letter_c.darkened(0.2)
					lm.set_meta("dark_face", true)
			front = 0.0
		"frame":
			# letters stand on a steel lattice above whatever they're mounted on
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.35, 0.36, 0.38)
			sm.metallic = 0.7
			sm.roughness = 0.4
			var fy := -total_h / 2.0 - 0.05
			_box(root, Vector3(x, fy, -0.1), Vector3(w + 0.2, 0.06, 0.06), sm)
			_box(root, Vector3(x, fy - 0.5, -0.1), Vector3(w + 0.2, 0.05, 0.05), sm)
			var px := x - w / 2.0
			while px <= x + w / 2.0 + 0.01:
				_box(root, Vector3(px, fy - 0.45, -0.1), Vector3(0.05, 0.9, 0.05), sm)
				px += 0.8
		"letters":
			# small stand-offs behind the letters
			front = 0.05
	# place the letters (and the second line)
	var y1 := total_h / 2.0 - h / 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = lm
	mi.position = Vector3(x, y1, front + depth / 2.0)
	root.add_child(mi)
	if tm2:
		var mi2 := MeshInstance3D.new()
		mi2.mesh = tm2
		mi2.material_override = lm
		mi2.position = Vector3(x, y1 - h / 2.0 - h2 / 2.0, front + depth / 2.0)
		root.add_child(mi2)
	# lighting
	match light:
		"inside":
			if not lm.has_meta("dark_face"):
				lm.emission_enabled = true
				lm.emission = letter_c
				glow.call(lm, 0.0, 2.2)
		"neon":
			lm.emission_enabled = true
			lm.emission = light_c
			lm.albedo_color = light_c
			glow.call(lm, 0.6, 4.0)
			var omni := OmniLight3D.new()
			omni.light_color = light_c
			omni.light_energy = 1.2
			omni.omni_range = maxf(2.0, w * 0.6)
			omni.position = Vector3(x, 0, 0.6)
			root.add_child(omni)
			night_light.call(omni)
		"halo":
			# a glowing copy just behind the letters lights the wall round them
			var hm := StandardMaterial3D.new()
			hm.albedo_color = Color(0, 0, 0)
			hm.emission_enabled = true
			hm.emission = light_c
			hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			glow.call(hm, 0.0, 3.0)
			var halo := MeshInstance3D.new()
			halo.mesh = tm
			halo.material_override = hm
			halo.scale = Vector3(1.04, 1.12, 0.4)
			halo.position = Vector3(x, y1, front - 0.03)
			halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(halo)
			var back := OmniLight3D.new()
			back.light_color = light_c
			back.light_energy = 0.8
			back.omni_range = maxf(1.5, w * 0.5)
			back.position = Vector3(x, y1, 0.3)
			root.add_child(back)
			night_light.call(back)
		"flood":
			# lamps on arms below the sign throw light up across the letters
			var hm := StandardMaterial3D.new()
			hm.albedo_color = Color(0.2, 0.21, 0.22)
			hm.metallic = 0.6
			var face_m := StandardMaterial3D.new()
			face_m.albedo_color = Color(0.9, 0.9, 0.85)
			face_m.emission_enabled = true
			face_m.emission = light_c
			glow.call(face_m, 0.0, 3.0)
			var n := maxi(1, roundi(w / 2.5))
			var by := -total_h / 2.0 - pad - 0.15
			for k in n:
				var lx := x - w / 2.0 + (k + 0.5) * w / n
				_box(root, Vector3(lx, by, 0.25), Vector3(0.04, 0.04, 0.5), hm)
				var head := _box(root, Vector3(lx, by + 0.04, 0.5), Vector3(0.22, 0.12, 0.14), hm)
				head.rotation.x = 0.6
				var lens := _box(root, Vector3(lx, by + 0.09, 0.47), Vector3(0.18, 0.02, 0.1), face_m)
				lens.rotation.x = 0.6
			var spot := SpotLight3D.new()
			spot.light_color = light_c
			spot.light_energy = 6.0
			spot.spot_range = total_h + 3.0
			spot.spot_angle = clampf(rad_to_deg(atan2(w / 2.0 + 0.5, 1.2)), 20.0, 80.0)
			spot.position = Vector3(x, by, 1.2)
			root.add_child(spot)
			spot.look_at(root.to_global(Vector3(x, y1, 0)), Vector3.UP)
			night_light.call(spot)
	return root


static func _box(parent: Node3D, pos: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi
