extends Node3D
## Playable 3D view. Reads sim state, sends player commands to Season.
## No game rules live here; StadiumRenderer draws, OrbitCamera moves.

const PANEL_X := 925.0
const NEW_STAND_LENGTH := 6
const EXTEND_STEP := 2
const SNAP_GAP := 4
const AUTOSAVE := "user://autosave.json"
const SAVE_SLOT := "user://save1.json"
const StadiumRenderer := preload("res://view/stadium_renderer.gd")
const OrbitCamera := preload("res://view/orbit_camera.gd")

var config: SimConfig
var game: Season
var tool := "terrace"
var selected := -1            # selected stand index
var selected_fac := -1        # selected facility index
var layer := "stadium"        # stadium / concourse / underground
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
	var saved := Season.load_file(config, AUTOSAVE)
	game = saved if saved != null else _new_game()
	_build_world()
	_build_ui()
	_refresh()
	if saved != null:
		_say("Welcome back! Season %d, %s fans." % [game.season_number, _n(game.club.fanbase)])
	else:
		_say("Pick a stand type, then click beside the pitch to build your first stand.")


func _new_game() -> Season:
	return Season.create(config, Layout.create(config, "My Stadium"), int(Time.get_unix_time_from_system()))


func _set_game(g: Season) -> void:
	game = g
	selected = -1
	last_report = game.reports[-1] if not game.reports.is_empty() else null
	name_edit.text = game.club.club_name
	primary_picker.color = game.club.primary_color
	secondary_picker.color = game.club.secondary_color
	_world_sig = 0
	_refresh()


func _autosave() -> void:
	game.save_file(AUTOSAVE)


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
const ROOF_NAMES := { "cantilever": "Modern roof", "gable": "Classic roof", "barrel": "Barrel roof", "truss": "Goalpost truss", "open": "No roof" }

var roof_option: OptionButton
var shape_option: OptionButton
var seat_picker: ColorPickerButton
var seat_reset: Button
var style_row: Control
var name_edit: LineEdit
var primary_picker: ColorPickerButton
var secondary_picker: ColorPickerButton
var title_label: Label
var tabs: TabContainer
var tool_box: VBoxContainer
var tool_group := ButtonGroup.new()
var layer_buttons := {}
var fac_box: VBoxContainer
var fac_label: Label
var fac_style: OptionButton
var gear_row: HFlowContainer

const LAYER_TOOLS := {
	"stadium": [["STANDS  (click beside the pitch or in a corner)", "stands"],
		["IN THE BOWL  (click a stand)", ["video_board", "ribbon_board", "scoreboard", "sound_system"]],
		["OUTSIDE", ["car_park", "bus_stop"]]],
	"concourse": [["FOOD & DRINK", ["kiosk", "bar"]],
		["SERVICES", ["restroom", "first_aid"]],
		["SHOPS & FANS", ["merch", "fan_zone"]]],
	"underground": [["TRANSPORT", ["garage", "subway"]]],
}
const LAYER_NAMES := { "stadium": "Stadium", "concourse": "Concourse", "underground": "Underground" }


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var hud_bg := ColorRect.new()
	hud_bg.color = Color(0, 0, 0, 0.55)
	hud_bg.size = Vector2(PANEL_X - 10, 40)
	hud_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud_bg)
	hud = Label.new()
	hud.position = Vector2(12, 8)
	hud.add_theme_font_size_override("font_size", 16)
	hud.size = Vector2(PANEL_X - 20, 24)
	hud.clip_text = true
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud)

	var lbar := HBoxContainer.new()
	lbar.position = Vector2(12, 48)
	var lgroup := ButtonGroup.new()
	for id in ["stadium", "concourse", "underground"]:
		var b := Button.new()
		b.text = LAYER_NAMES[id]
		b.toggle_mode = true
		b.button_group = lgroup
		b.button_pressed = id == layer
		b.custom_minimum_size = Vector2(120, 32)
		var lid: String = id
		b.pressed.connect(func(): _set_layer(lid))
		lbar.add_child(b)
		layer_buttons[id] = b
	canvas.add_child(lbar)

	message = Label.new()
	message.position = Vector2(12, 640)
	message.size = Vector2(900, 70)
	message.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	message.add_theme_color_override("font_outline_color", Color.BLACK)
	message.add_theme_constant_override("outline_size", 6)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(message)

	var panel_bg := Panel.new()
	panel_bg.position = Vector2(PANEL_X - 10, 0)
	panel_bg.size = Vector2(1280 - PANEL_X + 10, 720)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 0.94)
	panel_bg.add_theme_stylebox_override("panel", sb)
	canvas.add_child(panel_bg)
	var panel := VBoxContainer.new()
	panel.position = Vector2(PANEL_X, 8)
	panel.size = Vector2(345, 704)
	panel.add_theme_constant_override("separation", 5)
	canvas.add_child(panel)

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
	var scroll := ScrollContainer.new()
	scroll.name = "Build"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(330, 0)
	box.add_theme_constant_override("separation", 5)
	scroll.add_child(box)
	tool_box = VBoxContainer.new()
	tool_box.add_theme_constant_override("separation", 4)
	box.add_child(tool_box)
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
	var style_box := VBoxContainer.new()
	style_row = style_box
	var srow := HBoxContainer.new()
	style_box.add_child(srow)
	var srow2 := HBoxContainer.new()
	style_box.add_child(srow2)
	roof_option = OptionButton.new()
	for r in Stand.ROOF_STYLES:
		roof_option.add_item(ROOF_NAMES[r])
	roof_option.item_selected.connect(func(i: int): _restyle(Stand.ROOF_STYLES[i], ""))
	srow.add_child(roof_option)
	shape_option = OptionButton.new()
	shape_option.add_item("Square")
	shape_option.add_item("Rounded")
	shape_option.item_selected.connect(func(i: int):
		_report_err(game.set_corner_shape(selected, Stand.CORNER_SHAPES[i]))
		_refresh())
	srow.add_child(shape_option)
	seat_picker = ColorPickerButton.new()
	seat_picker.text = "Seats"
	seat_picker.custom_minimum_size = Vector2(110, 28)
	seat_picker.edit_alpha = false
	seat_picker.popup_closed.connect(func(): _restyle("", seat_picker.color.to_html(false)))
	srow2.add_child(seat_picker)
	seat_reset = Button.new()
	seat_reset.text = "Reset"
	seat_reset.pressed.connect(func(): _restyle("", "-"))
	srow2.add_child(seat_reset)
	var demo := Button.new()
	demo.text = "Demolish"
	demo.pressed.connect(func(): _stand_action("demolish"))
	sel_buttons["demolish"] = demo
	srow2.add_child(demo)
	box.add_child(style_box)
	gear_row = HFlowContainer.new()
	box.add_child(gear_row)

	fac_box = VBoxContainer.new()
	fac_label = Label.new()
	fac_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fac_label.custom_minimum_size = Vector2(330, 0)
	fac_box.add_child(fac_label)
	var frow := HBoxContainer.new()
	fac_style = OptionButton.new()
	fac_style.custom_minimum_size = Vector2(160, 28)
	fac_style.item_selected.connect(func(i: int):
		var ft := config.facility_type(game.layout.facilities[selected_fac].type_id)
		_report_err(game.restyle_facility(selected_fac, ft.styles[i]))
		_refresh())
	frow.add_child(fac_style)
	var fdemo := Button.new()
	fdemo.text = "Demolish"
	fdemo.pressed.connect(func():
		_report_err(game.demolish_facility(selected_fac))
		selected_fac = -1
		_refresh())
	frow.add_child(fdemo)
	fac_box.add_child(frow)
	box.add_child(fac_box)
	_rebuild_tools()
	return scroll


func _rebuild_tools() -> void:
	for c in tool_box.get_children():
		c.free()
	for section in LAYER_TOOLS[layer]:
		tool_box.add_child(_heading(section[0]))
		var grid := GridContainer.new()
		grid.columns = 3
		var ids: Array = config.stand_type_ids() if typeof(section[1]) == TYPE_STRING else section[1]
		for id in ids:
			var name: String = config.stand_type(id).display_name if config.stand_types.has(id) else config.facility_type(id).display_name
			grid.add_child(_tool_button(id, name, tool_group))
		tool_box.add_child(grid)
	tool_box.add_child(_heading("TOOLS"))
	var g2 := GridContainer.new()
	g2.columns = 3
	g2.add_child(_tool_button("select", "Select", tool_group))
	g2.add_child(_tool_button("demolish", "Demolish", tool_group))
	tool_box.add_child(g2)


func _set_layer(id: String) -> void:
	layer = id
	if layer_buttons.has(id):
		layer_buttons[id].set_pressed_no_signal(true)
	tool = "select"
	selected = -1
	selected_fac = -1
	renderer.set_layer(id)
	_rebuild_tools()
	var tip := { "stadium": "The whole ground: build stands, bowl gear (screens, boards, sound) and outside transport.",
		"concourse": "Concourse level: stands go see-through. Place food, bars, shops, restrooms, first aid and fan zones on the paving.",
		"underground": "Underground: dig parking garages and a subway station. You can build under stands but not the pitch." }
	_say(tip[id])
	_refresh()


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
	box.add_child(HSeparator.new())
	box.add_child(_heading("GAME  (autosaves after every match)"))
	var grow := HBoxContainer.new()
	for g in [["Save", func():
				_report_err("" if game.save_file(SAVE_SLOT) == OK else "couldn't write the save file")
				if message.text == "": _say("Saved.")],
			["Load", func():
				var g2 := Season.load_file(config, SAVE_SLOT)
				if g2 == null:
					_say("No saved game yet.")
				else:
					_set_game(g2)
					_say("Loaded.")],
			["New game", func():
				_set_game(_new_game())
				_autosave()
				_say("New club, empty plot. Build your first stand!")]]:
		var b := Button.new()
		b.text = g[0]
		b.custom_minimum_size = Vector2(108, 28)
		b.pressed.connect(g[1])
		grow.add_child(b)
	box.add_child(grow)
	return box


func _tool_button(id: String, text: String, group: ButtonGroup, width := 106) -> Button:
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
		_autosave()
		_refresh()
		return
	if game.layout.stands.is_empty():
		_say("Build a stand first. Nobody comes to watch an empty field.")
		return
	last_report = game.play_next()
	_autosave()
	_say("")
	_refresh()


func _click(tile: Vector2i) -> void:
	var stand_tiles := game.layout.stand_tile_map()
	var concourse := game.layout.concourse_tile_map(config)
	if config.facility_types.has(tool):
		var err := game.build_facility(Facility.make(tool, tile))
		_report_err(err)
		if err == "":
			selected_fac = game.layout.facilities.size() - 1
			selected = -1
		_refresh()
		return
	match tool:
		"select":
			selected_fac = _facility_at(tile)
			selected = -1 if selected_fac >= 0 or layer != "stadium" else _stand_at(tile, stand_tiles, concourse)
		"demolish":
			var fi := _facility_at(tile)
			if fi >= 0:
				_report_err(game.demolish_facility(fi))
				selected_fac = -1
			elif layer == "stadium":
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
	var c := Stand.make_corner(corner, tool, mini(depth, config.integer("layout/max_depth")))
	c.shape = "rounded"
	return c


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


## The facility under this tile in the current layer (bowl items count when
## clicking anywhere on their stand), or -1.
func _facility_at(tile: Vector2i) -> int:
	var layers: Array = { "stadium": ["bowl", "outside"], "concourse": ["concourse"], "underground": ["underground"] }[layer]
	var stand_tiles := game.layout.stand_tile_map()
	for i in range(game.layout.facilities.size() - 1, -1, -1):
		var f := game.layout.facilities[i]
		var ft := config.facility_type(f.type_id)
		if not ft.layer in layers:
			continue
		if ft.layer == "bowl":
			continue  # managed from the stand's editor
		if tile in f.tiles(ft):
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
	for s in game.layout.stands if layer == "stadium" else []:
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
		var ft := config.facility_type(tool)
		var probe := Facility.make(tool, hover)
		var ctx := game.layout.placement_context(config)
		for f in game.layout.facilities:
			game.layout.facility_error(f, config, ctx)
		var ok := game.layout.facility_error(probe, config, ctx) == "" and ft.build_cost <= game.club.cash
		if ft.layer == "bowl":
			var si := _stand_at(hover, game.layout.stand_tile_map(), {})
			if si >= 0:
				var r := StadiumRenderer.stand_aabb(game.layout.stands[si], game.layout.pitch)
				renderer.show_ghost_tile(Vector2i(int(r.position.x), int(r.position.z)), ok, Vector2i(int(r.size.x), int(r.size.z)))
			else:
				renderer.clear_overlay()
		else:
			renderer.show_ghost_tile(hover, ok, ft.size, ft.layer == "underground")
		_say("%s: %s%s" % [ft.display_name, Season.money(ft.build_cost), "" if ok else "  (can't go here)"])
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
	_autosave()  # cheap; keeps every build and setting safe


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
		return _facility_blurb(config.facility_type(tool))
	if tool == "demolish":
		return "Click a stand or facility to knock it down (%d%% refund)." % roundi(100 * config.num("season/demolish_refund_fraction"))
	return "Click a stand to select it. Esc to deselect."


func _facility_blurb(f: FacilityType) -> String:
	var bits := PackedStringArray()
	bits.append("%s: %s, upkeep %s/match." % [f.display_name, Season.money(f.build_cost), Season.money(f.upkeep_per_match)])
	if f.service_rate_per_min > 0:
		bits.append("Serves %d fans/min at halftime%s." % [roundi(f.service_rate_per_min), "" if f.spend_per_customer <= 0 else ", ~£%d each" % roundi(f.spend_per_customer)])
	if f.capacity > 0:
		bits.append("Brings %s more fans to the ground." % _n(f.capacity))
	if f.atmosphere_bonus > 0:
		bits.append("+%d atmosphere." % roundi(f.atmosphere_bonus))
	if f.sponsor_per_match > 0:
		bits.append("Sponsors ~%s/match." % Season.money(f.sponsor_per_match))
	if f.mood_bonus > 0:
		bits.append("Happier fans (covers %s)." % _n(f.coverage))
	if f.size != Vector2i.ONE:
		bits.append("%dx%d tiles." % [f.size.x, f.size.y])
	bits.append({ "concourse": "Place on the paving behind a stand.", "bowl": "Click a stand to mount it.",
		"outside": "Place on open ground.", "underground": "Dig anywhere except under the pitch." }[f.layer])
	return " ".join(bits)


func _refresh_selection() -> void:
	var has_fac := selected_fac >= 0 and selected_fac < game.layout.facilities.size()
	fac_box.visible = has_fac
	if has_fac:
		var f := game.layout.facilities[selected_fac]
		var ft := config.facility_type(f.type_id)
		fac_label.text = _facility_blurb(ft)
		fac_style.clear()
		for st in ft.styles:
			fac_style.add_item(String(st).capitalize())
		fac_style.select(maxi(0, ft.styles.find(f.style)))
		fac_style.disabled = ft.styles.size() < 2
	else:
		selected_fac = -1
	var has := selected >= 0 and selected < game.layout.stands.size()
	for b in sel_buttons.values():
		b.visible = has
	style_row.visible = has
	for c in gear_row.get_children():
		c.free()
	if has:
		var stand_tiles := game.layout.stand_tile_map()
		for i in game.layout.facilities.size():
			var f := game.layout.facilities[i]
			var ft := config.facility_type(f.type_id)
			if ft.layer == "bowl" and stand_tiles.get(f.pos, -1) == selected:
				var b := Button.new()
				b.text = "✕ " + ft.display_name
				b.tooltip_text = "Remove the %s from this stand" % ft.display_name.to_lower()
				var idx := i
				b.pressed.connect(func():
					_report_err(game.demolish_facility(idx))
					_refresh())
				gear_row.add_child(b)
				if ft.styles.size() > 1:
					var sb := Button.new()
					sb.text = "Style: %s" % String(f.style if f.style != "" else ft.styles[0]).capitalize()
					sb.pressed.connect(func():
						var cur: int = ft.styles.find(f.style if f.style != "" else ft.styles[0])
						_report_err(game.restyle_facility(idx, ft.styles[(cur + 1) % ft.styles.size()]))
						_refresh())
					gear_row.add_child(sb)
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
	shape_option.visible = s.is_corner()
	shape_option.select(Stand.CORNER_SHAPES.find(s.shape))
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
	lines.append("Takings [b]%s[/b]  (costs %s incl. utilities %s)" % [Season.money(r.revenue["total"]), Season.money(r.costs["total"]), Season.money(r.costs.get("utilities", 0.0))])
	var extras := PackedStringArray()
	for k in ["food", "drinks", "merch", "sponsors"]:
		if r.revenue.get(k, 0.0) > 0.0:
			extras.append("%s %s" % [k, Season.money(r.revenue[k])])
	if not extras.is_empty():
		lines.append("[color=#aaaaaa]" + "  ".join(extras) + "[/color]")
	if r.transport_turned_away > 0:
		lines.append("[color=#ff8a65]%s fans couldn't get to the ground! Build car parks, bus stops, a garage or a subway.[/color]" % _n(r.transport_turned_away))
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
