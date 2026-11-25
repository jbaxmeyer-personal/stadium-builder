extends Node3D
## Playable 3D view. Reads sim state, sends player commands to Season.
## No game rules live here; StadiumRenderer draws, OrbitCamera moves.

const PANEL_X := 925.0
const NEW_STAND_LENGTH := 6
const EXTEND_STEP := 2
const SNAP_GAP := 4
const StadiumRenderer := preload("res://view/stadium_renderer.gd")
const OrbitCamera := preload("res://view/orbit_camera.gd")

var config: SimConfig
var game: Season
var tool := "terrace"
var selected := -1            # selected stand index
var hover := Vector2i(-1, -1)
var last_report: MatchdayReport
var show_details := false

var hud: Label
var message: Label
var tool_hint: Label
var sel_label: Label
var sel_buttons: Dictionary = {}   # action -> Button
var price_labels: Dictionary = {}  # type -> Label
var play_button: Button
var report_box: RichTextLabel
var renderer: StadiumRenderer
var camera: Camera3D
var _world_sig := 0


func _ready() -> void:
	config = SimConfig.load_default()
	game = Season.create(config, Layout.create(config, "My Stadium"), int(Time.get_unix_time_from_system()))
	_build_world()
	_build_ui()
	_refresh()
	_say("Pick a stand type, then click beside the pitch to build your first stand.")


# --- World ------------------------------------------------------------------

func _build_world() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.24, 0.45)
	sky_mat.sky_horizon_color = Color(0.85, 0.62, 0.45)
	sky_mat.ground_horizon_color = Color(0.35, 0.33, 0.3)
	sky_mat.ground_bottom_color = Color(0.12, 0.12, 0.12)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.6, 0.55, 0.55)
	env.fog_density = 0.002
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, -140, 0)
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)

	camera = OrbitCamera.new()
	camera.target = Vector3(config.integer("plot/width") / 2.0, 0, config.integer("plot/height") / 2.0)
	camera.bounds = Rect2(0, 0, config.integer("plot/width"), config.integer("plot/height"))
	add_child(camera)

	renderer = StadiumRenderer.new()
	add_child(renderer)
	renderer.build_static(game.layout)


# --- UI construction -----------------------------------------------------

const KITS := [
	["Reds", Color(0.75, 0.08, 0.10), Color(0.97, 0.97, 0.97)],
	["Blues", Color(0.08, 0.25, 0.70), Color(0.97, 0.97, 0.97)],
	["Claret & Blue", Color(0.48, 0.08, 0.20), Color(0.45, 0.70, 0.90)],
	["Black & White", Color(0.08, 0.08, 0.08), Color(0.97, 0.97, 0.97)],
	["Yellow & Black", Color(0.98, 0.80, 0.10), Color(0.08, 0.08, 0.08)],
	["Greens", Color(0.05, 0.50, 0.25), Color(0.97, 0.97, 0.97)],
	["Tangerine", Color(0.96, 0.45, 0.08), Color(0.08, 0.08, 0.08)],
	["Sky Blue", Color(0.42, 0.68, 0.90), Color(0.97, 0.97, 0.97)],
]
const ROOF_NAMES := { "cantilever": "Modern roof", "gable": "Classic roof", "open": "No roof" }

var roof_option: OptionButton
var seat_picker: ColorPickerButton
var seat_reset: Button
var style_row: Control
var name_edit: LineEdit
var primary_picker: ColorPickerButton
var secondary_picker: ColorPickerButton
var title_label: Label
var tabs: TabContainer


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var hud_bg := ColorRect.new()
	hud_bg.color = Color(0, 0, 0, 0.55)
	hud_bg.size = Vector2(PANEL_X - 10, 40)
	hud_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud_bg)
	hud = Label.new()
	hud.position = Vector2(12, 8)
	hud.add_theme_font_size_override("font_size", 16)
	hud.size = Vector2(PANEL_X - 20, 24)
	hud.clip_text = true
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)

	message = Label.new()
	message.position = Vector2(12, 640)
	message.size = Vector2(900, 70)
	message.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	message.add_theme_color_override("font_outline_color", Color.BLACK)
	message.add_theme_constant_override("outline_size", 6)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(message)

	var panel_bg := Panel.new()
	panel_bg.position = Vector2(PANEL_X - 10, 0)
	panel_bg.size = Vector2(1280 - PANEL_X + 10, 720)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 0.94)
	panel_bg.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel_bg)
	var panel := VBoxContainer.new()
	panel.position = Vector2(PANEL_X, 8)
	panel.size = Vector2(345, 704)
	panel.add_theme_constant_override("separation", 5)
	layer.add_child(panel)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title_label)

	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(345, 405)
	panel.add_child(tabs)
	tabs.add_child(_build_tab())
	tabs.add_child(_club_tab())

	play_button = Button.new()
	play_button.custom_minimum_size = Vector2(340, 42)
	play_button.add_theme_font_size_override("font_size", 18)
	play_button.pressed.connect(_on_play)
	panel.add_child(play_button)

	var view_row := HBoxContainer.new()
	var roofs := CheckButton.new()
	roofs.text = "Roofs"
	roofs.button_pressed = true
	roofs.toggled.connect(func(on: bool): renderer.show_roofs = on)
	view_row.add_child(roofs)
	var details := CheckButton.new()
	details.text = "Sim numbers"
	details.toggled.connect(func(on: bool):
		show_details = on
		_refresh())
	view_row.add_child(details)
	panel.add_child(view_row)

	report_box = RichTextLabel.new()
	report_box.bbcode_enabled = true
	report_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report_box.scroll_following = false
	panel.add_child(report_box)


func _build_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Build"
	box.add_theme_constant_override("separation", 5)
	var group := ButtonGroup.new()
	box.add_child(_heading("STANDS  (click beside the pitch or in a corner)"))
	var grid := GridContainer.new()
	grid.columns = 3
	for id in config.stand_type_ids():
		grid.add_child(_tool_button(id, config.stand_type(id).display_name, group))
	box.add_child(grid)
	box.add_child(_heading("FACILITIES & TOOLS"))
	var grid2 := GridContainer.new()
	grid2.columns = 4
	for t in [["kiosk", "Kiosk"], ["restroom", "Restroom"], ["select", "Select"], ["demolish", "Demolish"]]:
		grid2.add_child(_tool_button(t[0], t[1], group, 80))
	box.add_child(grid2)
	tool_hint = Label.new()
	tool_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tool_hint.custom_minimum_size = Vector2(330, 36)
	tool_hint.add_theme_font_size_override("font_size", 13)
	tool_hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	box.add_child(tool_hint)
	box.add_child(HSeparator.new())

	sel_label = Label.new()
	sel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sel_label.custom_minimum_size = Vector2(330, 0)
	box.add_child(sel_label)
	var sel_grid := GridContainer.new()
	sel_grid.columns = 2
	for a in ["row", "unrow", "left", "right"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(164, 28)
		var action: String = a
		b.pressed.connect(func(): _stand_action(action))
		sel_grid.add_child(b)
		sel_buttons[a] = b
	box.add_child(sel_grid)
	var srow := HBoxContainer.new()
	style_row = srow
	roof_option = OptionButton.new()
	for r in Stand.ROOF_STYLES:
		roof_option.add_item(ROOF_NAMES[r])
	roof_option.item_selected.connect(func(i: int): _restyle(Stand.ROOF_STYLES[i], ""))
	srow.add_child(roof_option)
	seat_picker = ColorPickerButton.new()
	seat_picker.text = "Seats"
	seat_picker.custom_minimum_size = Vector2(70, 28)
	seat_picker.edit_alpha = false
	seat_picker.popup_closed.connect(func(): _restyle("", seat_picker.color.to_html(false)))
	srow.add_child(seat_picker)
	seat_reset = Button.new()
	seat_reset.text = "Reset"
	seat_reset.pressed.connect(func(): _restyle("", "-"))
	srow.add_child(seat_reset)
	var demo := Button.new()
	demo.text = "Demolish"
	demo.pressed.connect(func(): _stand_action("demolish"))
	sel_buttons["demolish"] = demo
	srow.add_child(demo)
	box.add_child(srow)
	return box


func _club_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Club"
	box.add_theme_constant_override("separation", 6)
	box.add_child(_heading("CLUB NAME"))
	name_edit = LineEdit.new()
	name_edit.text = game.club.club_name
	name_edit.max_length = 28
	name_edit.text_submitted.connect(func(t: String): _set_club_name(t))
	name_edit.focus_exited.connect(func(): _set_club_name(name_edit.text))
	box.add_child(name_edit)
	box.add_child(_heading("COLOURS"))
	var crow := HBoxContainer.new()
	primary_picker = ColorPickerButton.new()
	primary_picker.text = "Home"
	primary_picker.color = game.club.primary_color
	primary_picker.edit_alpha = false
	primary_picker.custom_minimum_size = Vector2(110, 30)
	primary_picker.popup_closed.connect(func(): _set_colors(primary_picker.color, game.club.secondary_color))
	crow.add_child(primary_picker)
	secondary_picker = ColorPickerButton.new()
	secondary_picker.text = "Trim"
	secondary_picker.color = game.club.secondary_color
	secondary_picker.edit_alpha = false
	secondary_picker.custom_minimum_size = Vector2(110, 30)
	secondary_picker.popup_closed.connect(func(): _set_colors(game.club.primary_color, secondary_picker.color))
	crow.add_child(secondary_picker)
	box.add_child(crow)
	var kits := GridContainer.new()
	kits.columns = 4
	for k in KITS:
		var b := Button.new()
		b.tooltip_text = k[0]
		b.custom_minimum_size = Vector2(78, 26)
		var st := StyleBoxFlat.new()
		st.bg_color = k[1]
		st.border_color = k[2]
		st.set_border_width_all(4)
		st.set_corner_radius_all(4)
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", st)
		b.add_theme_stylebox_override("pressed", st)
		var pc: Color = k[1]
		var sc: Color = k[2]
		b.pressed.connect(func(): _set_colors(pc, sc))
		kits.add_child(b)
	box.add_child(kits)
	box.add_child(HSeparator.new())
	box.add_child(_heading("TICKET PRICES"))
	for id in config.stand_type_ids():
		var row := HBoxContainer.new()
		var l := Label.new()
		l.custom_minimum_size = Vector2(230, 0)
		row.add_child(l)
		price_labels[id] = l
		for d in [-1, 1]:
			var b := Button.new()
			b.text = "-" if d < 0 else "+"
			b.custom_minimum_size = Vector2(34, 24)
			var type_id: String = id
			var dir: int = d
			b.pressed.connect(func(): _change_price(type_id, dir))
			row.add_child(b)
		box.add_child(row)
	return box


func _tool_button(id: String, text: String, group: ButtonGroup, width := 108) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = id == tool
	b.custom_minimum_size = Vector2(width, 30)
	b.pressed.connect(func(): _set_tool(id))
	return b


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	return l


# --- Commands -------------------------------------------------------------

func _set_tool(id: String) -> void:
	tool = id
	_refresh()


func _change_price(type_id: String, dir: int) -> void:
	var step: float = maxf(1.0, roundf(config.stand_type(type_id).reference_price * 0.1))
	var p: float = game.club.price(type_id) + dir * step
	_report_err(game.set_ticket_price(type_id, max(0.0, p)))
	_refresh()


## roof "" = keep; seat "" = keep, "-" = reset to default.
func _restyle(roof: String, seat: String) -> void:
	if selected < 0 or selected >= game.layout.stands.size():
		return
	var s := game.layout.stands[selected]
	var new_seat := s.seat_color if seat == "" else ("" if seat == "-" else "#" + seat)
	_report_err(game.restyle_stand(selected, s.roof if roof == "" else roof, new_seat))
	_refresh()


func _set_colors(primary: Color, secondary: Color) -> void:
	game.club.primary_color = primary
	game.club.secondary_color = secondary
	primary_picker.color = primary
	secondary_picker.color = secondary
	_refresh()


func _set_club_name(text: String) -> void:
	var t := text.strip_edges()
	if t != "" and t != game.club.club_name:
		game.club.club_name = t
		_refresh()


func _stand_action(action: String) -> void:
	if selected < 0 or selected >= game.layout.stands.size():
		return
	var s := game.layout.stands[selected]
	var side_len := Stand.side_length(s.side, game.layout.pitch)
	var err := ""
	match action:
		"row":
			err = game.resize_stand(selected, s.offset, s.depth + 1 if s.is_corner() else s.length, s.depth + 1)
		"unrow":
			err = "a stand needs at least one row" if s.depth <= 1 else game.resize_stand(selected, s.offset, s.depth - 1 if s.is_corner() else s.length, s.depth - 1)
		"left":
			var new_off: int = max(0, s.offset - EXTEND_STEP)
			err = "already at the corner" if new_off == s.offset else game.resize_stand(selected, new_off, s.length + s.offset - new_off, s.depth)
		"right":
			var new_len: int = min(side_len - s.offset, s.length + EXTEND_STEP)
			err = "already at the corner" if new_len == s.length else game.resize_stand(selected, s.offset, new_len, s.depth)
		"demolish":
			err = game.demolish_stand(selected)
			if err == "":
				selected = -1
	_report_err(err)
	_refresh()


func _on_play() -> void:
	if game.is_over():
		game.start_next_season()
		last_report = null
		_say("Season %d kicks off. Keep building!" % game.season_number)
		_refresh()
		return
	if game.layout.stands.is_empty():
		_say("Build a stand first. Nobody comes to watch an empty field.")
		return
	last_report = game.play_next()
	_say("")
	_refresh()


func _click(tile: Vector2i) -> void:
	var stand_tiles := game.layout.stand_tile_map()
	var concourse := game.layout.concourse_tile_map(config)
	match tool:
		"select":
			selected = _stand_at(tile, stand_tiles, concourse)
		"kiosk", "restroom":
			if not concourse.has(tile):
				_say("Facilities go on the concourse (the dark strip behind a stand).")
			else:
				_report_err(game.build_facility(Facility.make(tool, tile)))
		"demolish":
			var fi := _facility_at(tile)
			if fi >= 0:
				_report_err(game.demolish_facility(fi))
			else:
				var si := _stand_at(tile, stand_tiles, {})
				if si >= 0:
					_report_err(game.demolish_stand(si))
					selected = -1
		_:  # a stand type
			var existing := _stand_at(tile, stand_tiles, concourse)
			if existing >= 0:
				selected = existing
			else:
				var s := _placement(tile)
				if s == null:
					_say("Stands go right beside the pitch, on one of its four sides.")
				else:
					var join := _neighbour(s)
					if join >= 0:
						# Building next to a stand of the same type extends it into one bigger stand.
						var n := game.layout.stands[join]
						var lo: int = mini(n.offset, s.offset)
						var hi: int = maxi(n.offset + n.length, s.offset + s.length)
						var err := game.resize_stand(join, lo, hi - lo, n.depth)
						_report_err(err)
						if err == "":
							selected = join
					else:
						var err := game.build_stand(s)
						_report_err(err)
						if err == "":
							selected = game.layout.stands.size() - 1
	_refresh()


func _report_err(err: String) -> void:
	_say("" if err == "" else "Can't do that: " + err)


func _say(text: String) -> void:
	message.text = text


# --- Geometry helpers (view-side; read-only on sim state) -----------------

## Which side/u a tile falls on, or {} for corners and the pitch itself.
func _side_of(tile: Vector2i) -> Dictionary:
	var p := game.layout.pitch
	if tile.x >= p.position.x and tile.x < p.end.x:
		if tile.y < p.position.y:
			return { "side": "N", "u": tile.x - p.position.x }
		if tile.y >= p.end.y:
			return { "side": "S", "u": tile.x - p.position.x }
	if tile.y >= p.position.y and tile.y < p.end.y:
		if tile.x < p.position.x:
			return { "side": "W", "u": tile.y - p.position.y }
		if tile.x >= p.end.x:
			return { "side": "E", "u": tile.y - p.position.y }
	return {}


## The new stand a click would build at this tile (largest free run up to
## NEW_STAND_LENGTH, centred on the click), or null.
func _placement(tile: Vector2i) -> Stand:
	if not game.layout.in_plot(tile):
		return null
	var at := _side_of(tile)
	if at.is_empty():
		return _corner_placement(tile)
	var side: String = at["side"]
	var u: int = at["u"]
	var side_len := Stand.side_length(side, game.layout.pitch)
	var taken := game.layout.stand_tile_map()
	if taken.has(Stand.local_to_grid(side, game.layout.pitch, u, 0)):
		return null
	var lo := u
	var hi := u
	while hi - lo + 1 < NEW_STAND_LENGTH:
		var grew := false
		if hi + 1 < side_len and not taken.has(Stand.local_to_grid(side, game.layout.pitch, hi + 1, 0)):
			hi += 1
			grew = true
		if hi - lo + 1 < NEW_STAND_LENGTH and lo - 1 >= 0 and not taken.has(Stand.local_to_grid(side, game.layout.pitch, lo - 1, 0)):
			lo -= 1
			grew = true
		if not grew:
			break
	# Snap across a small gap to a same-type stand on this side, so clicking
	# a little past the end of a stand extends it instead of starting another.
	for n in game.layout.stands:
		if n.side != side or n.type_id != tool:
			continue
		var gap_lo := n.offset + n.length          # gap between n and us, if n is to our left
		var gap_hi := n.offset - 1                 # ... if n is to our right
		if gap_lo <= lo and lo - gap_lo <= SNAP_GAP and _free_run(side, gap_lo, lo - 1, taken):
			lo = gap_lo
		elif gap_hi >= hi and gap_hi - hi <= SNAP_GAP and _free_run(side, hi + 1, gap_hi, taken):
			hi = gap_hi
	return Stand.make(side, tool, lo, hi - lo + 1, 1)


func _free_run(side: String, from_u: int, to_u: int, taken: Dictionary) -> bool:
	for u in range(from_u, to_u + 1):
		if taken.has(Stand.local_to_grid(side, game.layout.pitch, u, 0)):
			return false
	return true


## A corner stand for a click in a corner gap, as deep as the deepest
## neighbouring side stand (at least 2), or null.
func _corner_placement(tile: Vector2i) -> Stand:
	var p := game.layout.pitch
	if p.has_point(tile):
		return null
	var corner := ("N" if tile.y < p.position.y else "S") + ("W" if tile.x < p.position.x else "E")
	for s in game.layout.stands:
		if s.side == corner:
			return null
	var depth := 2
	for s in game.layout.stands:
		if not s.is_corner() and corner.contains(s.side):
			depth = maxi(depth, s.depth)
	return Stand.make_corner(corner, tool, mini(depth, config.integer("layout/max_depth")))


## Index of an existing stand of the same type, side and setback that touches s end-to-end, or -1.
func _neighbour(s: Stand) -> int:
	if s.is_corner():
		return -1
	for i in game.layout.stands.size():
		var n := game.layout.stands[i]
		if n.side == s.side and n.type_id == s.type_id and n.setback == s.setback \
				and (n.offset + n.length == s.offset or s.offset + s.length == n.offset):
			return i
	return -1


func _stand_at(tile: Vector2i, stand_tiles: Dictionary, concourse: Dictionary) -> int:
	if stand_tiles.has(tile):
		return stand_tiles[tile]
	if concourse.has(tile):
		return concourse[tile]
	return -1


func _facility_at(tile: Vector2i) -> int:
	for i in game.layout.facilities.size():
		if game.layout.facilities[i].pos == tile:
			return i
	return -1


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var t := _mouse_tile(event.position)
		if t != hover:
			hover = t
			_update_hover()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var t := _mouse_tile(event.position)
		if game.layout.in_plot(t):
			_click(t)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		selected = -1
		_refresh()


## Tile under the mouse: stands are hit on their raised steps, everything else on the ground.
func _mouse_tile(pos: Vector2) -> Vector2i:
	var from := camera.project_ray_origin(pos)
	var dir := camera.project_ray_normal(pos)
	var best_t := INF
	var best := Vector2i(-1, -1)
	for s in game.layout.stands:
		var hit: Variant = StadiumRenderer.stand_aabb(s, game.layout.pitch).intersects_ray(from, dir)
		if hit != null:
			var t: float = ((hit as Vector3) - from).length()
			if t < best_t:
				var p: Vector3 = (hit as Vector3) + dir * 0.01
				best_t = t
				best = Vector2i(floori(p.x), floori(p.z))
	if absf(dir.y) > 1e-5:
		var t := -from.y / dir.y
		if t > 0.0 and t < best_t:
			var p := from + dir * t
			best = Vector2i(floori(p.x), floori(p.z))
	return best


func _update_hover() -> void:
	if not game.layout.in_plot(hover):
		renderer.clear_overlay()
		return
	var concourse := game.layout.concourse_tile_map(config)
	if config.stand_types.has(tool) and _stand_at(hover, game.layout.stand_tile_map(), concourse) < 0:
		var ghost := _placement(hover)
		if ghost != null:
			var t := config.stand_type(tool)
			var join := _neighbour(ghost)
			if join >= 0:
				ghost.depth = game.layout.stands[join].depth
			renderer.show_ghost_stand(ghost, game.layout.pitch, ghost.capacity(t) * t.build_cost_per_place <= game.club.cash)
			if join >= 0:
				_say("Extend the %s stand: +%d places for %s" % [t.display_name, ghost.capacity(t), Season.money(ghost.capacity(t) * t.build_cost_per_place)])
			else:
				_say("New %s stand: %d places for %s" % [t.display_name, ghost.capacity(t), Season.money(ghost.capacity(t) * t.build_cost_per_place)])
		else:
			renderer.clear_overlay()
	elif config.facility_types.has(tool):
		renderer.show_ghost_tile(hover, concourse.has(hover) and _facility_at(hover) < 0)
	else:
		renderer.show_hover_tile(hover)


# --- Refresh / text --------------------------------------------------------

func _refresh() -> void:
	var c := game.club
	var fx := game.next_fixture()
	var match_text := "Season over" if fx == null else "Match %d/%d" % [game.next_match_number(), game.fixtures.size()]
	hud.text = "Season %d   %s   Cash %s   Fans %s   Mood %d   Form %s   Capacity %s" % [
		game.season_number, match_text, Season.money(c.cash), _n(c.fanbase), roundi(c.mood),
		"-" if c.recent_results.is_empty() else "".join(c.recent_results.slice(-5)),
		_n(game.layout.capacity_total(config))]

	title_label.text = c.club_name
	title_label.add_theme_color_override("font_color", c.secondary_color if c.secondary_color.get_luminance() > 0.35 else c.primary_color.lightened(0.4))
	tool_hint.text = _tool_hint()
	_refresh_selection()
	for id in price_labels:
		price_labels[id].text = "%s  £%d" % [config.stand_type(id).display_name, roundi(c.price(id))]
	if game.is_over():
		play_button.text = "Start season %d" % (game.season_number + 1)
	else:
		play_button.text = "Play match %d%s" % [game.next_match_number(), "  (BIG MATCH!)" if fx.big else ""]
	report_box.text = _report_text()
	_sync_world()


func _sync_world() -> void:
	var c := game.club
	var sig := hash([game.layout.to_dict(), selected, last_report.seed if last_report else -1, game.reports.size(),
		c.club_name, c.primary_color, c.secondary_color])
	if sig != _world_sig:
		_world_sig = sig
		renderer.build_layout(game.layout, config, last_report, selected, c)
	_update_hover()


func _tool_hint() -> String:
	if config.stand_types.has(tool):
		var t := config.stand_type(tool)
		return "%s: %s per tile (%d places). Noise %.1f, ticket ~£%d. Click next to a stand of the same type to extend it." % [
			t.display_name, Season.money(t.capacity_per_tile * t.build_cost_per_place), t.capacity_per_tile,
			t.noise, roundi(t.reference_price)]
	if config.facility_types.has(tool):
		var f := config.facility_type(tool)
		return "%s: %s. Click the paved concourse behind a stand. Serves %d fans/min at halftime." % [
			f.display_name, Season.money(f.build_cost), roundi(f.service_rate_per_min)]
	if tool == "demolish":
		return "Click a stand or facility to knock it down (%d%% refund)." % roundi(100 * config.num("season/demolish_refund_fraction"))
	return "Click a stand to select it. Esc to deselect."


func _refresh_selection() -> void:
	var has := selected >= 0 and selected < game.layout.stands.size()
	for b in sel_buttons.values():
		b.visible = has
	style_row.visible = has
	if not has:
		selected = -1
		sel_label.text = "Click a stand to edit it: add rows, extend, change the roof or seat colour."
		return
	var s := game.layout.stands[selected]
	var t := config.stand_type(s.type_id)
	var side_len := Stand.side_length(s.side, game.layout.pitch)
	var where := "%s corner" % s.side if s.is_corner() else "%s side" % s.side
	sel_label.text = "%s stand (%s): %d rows, %s places, noise %.1f" % [
		t.display_name, where, s.depth, _n(s.capacity(t)), t.noise]
	sel_buttons["left"].visible = not s.is_corner()
	sel_buttons["right"].visible = not s.is_corner()
	roof_option.select(Stand.ROOF_STYLES.find(s.roof))
	seat_picker.color = renderer.seat_color(s) if renderer._club else Color.GRAY
	var next_len := s.depth + 1 if s.is_corner() else s.length
	sel_buttons["row"].text = "Add row (%s)" % Season.money(game.resize_cost(selected, s.offset, next_len, s.depth + 1))
	sel_buttons["unrow"].text = "Remove row"
	var new_off: int = max(0, s.offset - EXTEND_STEP)
	sel_buttons["left"].text = "Extend ◀ (%s)" % Season.money(game.resize_cost(selected, new_off, s.length + s.offset - new_off, s.depth))
	var new_len: int = min(side_len - s.offset, s.length + EXTEND_STEP)
	sel_buttons["right"].text = "Extend ▶ (%s)" % Season.money(game.resize_cost(selected, s.offset, new_len, s.depth))
	sel_buttons["demolish"].text = "Demolish"


func _report_text() -> String:
	if game.is_over():
		var sr := game.summary()
		return "[b]SEASON %d DONE[/b]\nRecord W%d D%d L%d (%d pts)\nAverage crowd %s\nFans %s → %s\nTakings %s\nCash now %s\n\nPress Start season to carry on." % [
			sr.season_number, sr.wins, sr.draws, sr.losses, sr.points, _n(sr.attendance_avg),
			_n(sr.fanbase_start), _n(sr.fanbase_end), Season.money(sr.net), Season.money(sr.cash_end)]
	var r := last_report
	if r == null:
		return "[color=#aaaaaa]Build some stands, then play a match.[/color]"
	if show_details:
		return "[code]" + r.to_text().replace("[", "[lb]") + "[/code]"
	var res := { "W": "[color=#8fe88f][b]WIN![/b][/color]", "D": "[b]DRAW[/b]", "L": "[color=#ff8a80][b]LOSS[/b][/color]" }
	var lines := PackedStringArray()
	lines.append("%s  %s%s" % [res[r.result], r.opponent, "  (big match)" if r.big_match else ""])
	lines.append("Crowd [b]%s[/b] / %s" % [_n(r.attendance), _n(r.capacity)])
	lines.append("Atmosphere [b]%d[/b] %s" % [roundi(r.atmosphere), "▮".repeat(roundi(r.atmosphere / 10.0))])
	lines.append("Takings [b]%s[/b]  (upkeep %s)" % [Season.money(r.revenue["total"]), Season.money(r.costs["total"])])
	lines.append("Fans %s → [b]%s[/b] (%+.1f%%)" % [_n(r.fanbase_before), _n(r.fanbase_after), 100.0 * r.fanbase_growth["total"]])
	# Nudges: turned-away fans and halftime trouble.
	var cap_by_type := {}
	for s in r.stands:
		cap_by_type[s["type"]] = cap_by_type.get(s["type"], 0) + s["capacity"]
	for id in config.stand_type_ids():
		var turned: int = r.demand[id] - cap_by_type.get(id, 0)
		if turned > 0:
			lines.append("[color=#ffd54f]%s fans turned away: %s. Build more![/color]" % [config.stand_type(id).display_name, _n(turned)])
	var food: Dictionary = r.halftime["food"]
	if food["wanting"] > 0 and food["lost"] > food["wanting"] * 0.1:
		lines.append("[color=#ffb74d]%d%% couldn't get food at halftime.[/color]" % roundi(100.0 * food["lost"] / food["wanting"]))
	var loo: Dictionary = r.halftime["restroom"]
	if loo["wanting"] > 0 and loo["lost"] > loo["wanting"] * 0.1:
		lines.append("[color=#90caf9]%d%% gave up on the restroom queue.[/color]" % roundi(100.0 * loo["lost"] / loo["wanting"]))
	return "\n".join(lines)


static func _n(v: float) -> String:
	return Season.money(v).substr(1)
