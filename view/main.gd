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
const CrowdAudio := preload("res://view/crowd_audio.gd")

var config: SimConfig
var game: Season
var tool := "terrace"
var selected := -1            # selected stand index
var selected_fac := -1        # selected facility index
var layer := "stadium"        # stadium / concourse / underground
var level := 0                # concourse level being viewed (0 = ground)
var level_bar: HBoxContainer
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
var crowd_audio: CrowdAudio
var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var md_panel: PanelContainer
var md_title: Label
var md_score: Label
var md_info: Label
var md_noise: ProgressBar
var md_tween: Tween
var md_saved_cam := {}
var _world_sig := 0
var _static_plot := Rect2i()
var land_box: GridContainer


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
	stadium_edit.text = game.club.stadium_name
	primary_picker.color = game.club.primary_color
	secondary_picker.color = game.club.secondary_color
	_world_sig = 0
	_refresh()


func _autosave() -> void:
	game.save_file(AUTOSAVE)


# --- World ------------------------------------------------------------------

func _build_world() -> void:
	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
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

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, -140, 0)
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)

	camera = OrbitCamera.new()
	camera.target = Vector3(config.integer("plot/width") / 2.0, 0, config.integer("plot/height") / 2.0)
	camera.bounds = Rect2(game.layout.plot)
	add_child(camera)

	crowd_audio = CrowdAudio.new()
	add_child(crowd_audio)
	crowd_audio.ambient(0.3)

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
var facade_option: OptionButton
var seat_picker: ColorPickerButton
var seat_reset: Button
var style_row: Control
var name_edit: LineEdit
var primary_picker: ColorPickerButton
var secondary_picker: ColorPickerButton
var title_label: Label
var ground_label: Label
var tool_buttons := {}
var md_milestone: Label
var stadium_edit: LineEdit
var sponsor_option: OptionButton
var sponsor_ids: Array = []
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
		["IN THE BOWL  (click a stand)", ["video_board", "ribbon_board", "scoreboard", "sound_system", "exec_boxes"]],
		["OUTSIDE: TRANSPORT", ["car_park", "bus_stop", "train_station"]],
		["AROUND THE GROUND", ["statue", "ticket_office", "museum", "hotel"]]],
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

	level_bar = HBoxContainer.new()
	level_bar.position = Vector2(400, 48)
	canvas.add_child(level_bar)

	var cam_bar := HBoxContainer.new()
	cam_bar.position = Vector2(12, 86)
	for c in [["+", "Zoom in", func(): camera.zoom(0.8)], ["−", "Zoom out", func(): camera.zoom(1.25)],
			["⟲", "Rotate left", func(): camera.spin(-0.35)], ["⟳", "Rotate right", func(): camera.spin(0.35)],
			["▲", "Look from higher", func(): camera.tilt(-0.15)], ["▼", "Look from lower", func(): camera.tilt(0.15)],
			["⌂", "Reset view", func():
				camera.reset(Vector3(config.integer("plot/width") / 2.0, 0, config.integer("plot/height") / 2.0))
				_follow_level()]]:
		var b := Button.new()
		b.text = c[0]
		b.tooltip_text = c[1] + "  (also: mouse wheel, right-drag, WASD, Q/E)"
		b.custom_minimum_size = Vector2(34, 30)
		b.pressed.connect(c[2])
		cam_bar.add_child(b)
	canvas.add_child(cam_bar)

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
	ground_label = Label.new()
	ground_label.add_theme_font_size_override("font_size", 12)
	ground_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	ground_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(ground_label)

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
	var sound := CheckButton.new()
	sound.text = "Sound"
	sound.button_pressed = true
	sound.toggled.connect(func(on: bool): crowd_audio.muted = not on)
	view_row.add_child(sound)
	var details := CheckButton.new()
	details.text = "Sim numbers"
	details.toggled.connect(func(on: bool):
		show_details = on
		_refresh())
	view_row.add_child(details)
	panel.add_child(view_row)

	_build_matchday_overlay(canvas)

	report_box = RichTextLabel.new()
	report_box.bbcode_enabled = true
	report_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report_box.scroll_following = false
	panel.add_child(report_box)


# --- Matchday moment ------------------------------------------------------

func _build_matchday_overlay(canvas: CanvasLayer) -> void:
	md_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.06, 0.88)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	md_panel.add_theme_stylebox_override("panel", sb)
	md_panel.position = Vector2(PANEL_X / 2.0 - 280, 130)
	md_panel.custom_minimum_size = Vector2(560, 0)
	md_panel.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	md_panel.add_child(v)
	md_title = Label.new()
	md_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	md_title.add_theme_font_size_override("font_size", 16)
	md_title.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	v.add_child(md_title)
	md_score = Label.new()
	md_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	md_score.add_theme_font_size_override("font_size", 30)
	v.add_child(md_score)
	md_info = Label.new()
	md_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	md_info.add_theme_font_size_override("font_size", 15)
	v.add_child(md_info)
	var nrow := HBoxContainer.new()
	var nl := Label.new()
	nl.text = "NOISE"
	nl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	nrow.add_child(nl)
	md_noise = ProgressBar.new()
	md_noise.custom_minimum_size = Vector2(440, 22)
	md_noise.max_value = 100
	md_noise.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.55, 0.15)
	fill.set_corner_radius_all(4)
	md_noise.add_theme_stylebox_override("fill", fill)
	nrow.add_child(md_noise)
	v.add_child(nrow)
	md_milestone = Label.new()
	md_milestone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	md_milestone.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	md_milestone.custom_minimum_size = Vector2(520, 0)
	md_milestone.add_theme_font_size_override("font_size", 17)
	md_milestone.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	v.add_child(md_milestone)
	var ok := Button.new()
	ok.text = "Back to building"
	ok.pressed.connect(_matchday_end)
	v.add_child(ok)
	canvas.add_child(md_panel)


func _matchday_show(r: MatchdayReport) -> void:
	var c := game.club
	md_title.text = "%s%s  ·  %s  ·  %s" % ["BIG MATCH  ·  " if r.big_match else "", "Evening kick-off" if r.evening else "Afternoon kick-off",
		{ "clear": "Clear skies", "rain": "Pouring rain", "snow": "Snow!" }.get(r.weather, ""), config.division(r.division)["name"]]
	if r.weather != "clear":
		var open_stands := 0
		for st in game.layout.stands:
			if st.roof == "open":
				open_stands += 1
		if open_stands > 0:
			md_title.text += "\n%d uncovered stand%s: some fans stayed home" % [open_stands, "" if open_stands == 1 else "s"]
	md_score.text = "%s  %d – %d  %s" % [c.club_name.to_upper(), r.home_goals, r.away_goals, r.opponent.to_upper()]
	md_score.add_theme_color_override("font_color", { "W": Color(0.55, 1.0, 0.55), "D": Color(1, 1, 1), "L": Color(1.0, 0.55, 0.5) }[r.result])
	md_info.text = "%s  ·  crowd %s  ·  takings %s  ·  fans %+.1f%%" % [
		{ "W": "WIN!", "D": "Draw", "L": "Defeat" }[r.result], _n(r.attendance), Season.money(r.revenue["total"]), 100.0 * r.fanbase_growth["total"]]
	md_noise.value = 0
	var ms := PackedStringArray()
	for m in r.milestones:
		var names := PackedStringArray()
		for id in m["unlocks"]:
			if config.facility_types.has(id):
				names.append(config.facility_type(id).display_name)
			else:
				names.append({ "tier2": "Second tiers", "tier3": "Third tiers", "naming_rights": "Naming rights" }.get(id, id))
		ms.append("★ MILESTONE: %s (%s fans)!  +%s%s" % [m["name"], _n(m["fans"]), Season.money(m["reward"]),
			"" if names.is_empty() else "\nUnlocked: " + ", ".join(names)])
	md_milestone.text = "\n".join(ms)
	md_milestone.visible = not ms.is_empty()
	md_panel.visible = true
	renderer.matchday_live = true
	_world_sig = 0
	crowd_audio.play_match(r)
	_set_night(r.evening)
	_set_weather(r.weather)
	if md_saved_cam.is_empty():
		md_saved_cam = { "yaw": camera.yaw, "pitch": camera.pitch, "distance": camera.distance, "target": camera.target }
	if md_tween:
		md_tween.kill()
	md_tween = create_tween().set_parallel(true)
	md_tween.tween_property(md_noise, "value", r.atmosphere, 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	camera.target = Vector3(config.integer("plot/width") / 2.0, 0, config.integer("plot/height") / 2.0)
	camera.pitch = deg_to_rad(-24.0)
	camera.distance = 48.0
	md_tween.tween_method(_sweep, camera.yaw, camera.yaw + deg_to_rad(100.0), 7.0)


func _sweep(yaw: float) -> void:
	camera.yaw = yaw
	camera._apply()


func _matchday_end() -> void:
	if md_tween:
		md_tween.kill()
	md_panel.visible = false
	if renderer.matchday_live:
		renderer.matchday_live = false
		_world_sig = 0
		_sync_world()
	crowd_audio.stop_match()
	_set_night(false)
	_set_weather("clear")
	if not md_saved_cam.is_empty():
		camera.yaw = md_saved_cam["yaw"]
		camera.pitch = md_saved_cam["pitch"]
		camera.distance = md_saved_cam["distance"]
		camera.target = md_saved_cam["target"]
		camera._apply()
		md_saved_cam = {}


func _set_weather(w: String) -> void:
	renderer.set_weather(w, game.layout)
	if w != "clear" and sun.light_energy > 0.5:
		# overcast day
		sky_mat.sky_top_color = Color(0.42, 0.45, 0.5)
		sky_mat.sky_horizon_color = Color(0.62, 0.64, 0.66)
		sun.light_energy = 0.45
		env.fog_density = 0.008
	elif w == "clear":
		env.fog_density = 0.002


func _set_night(on: bool) -> void:
	sky_mat.sky_top_color = Color(0.02, 0.03, 0.08) if on else Color(0.16, 0.24, 0.45)
	sky_mat.sky_horizon_color = Color(0.12, 0.1, 0.18) if on else Color(0.85, 0.62, 0.45)
	sky_mat.ground_horizon_color = Color(0.05, 0.05, 0.06) if on else Color(0.35, 0.33, 0.3)
	sun.light_energy = 0.08 if on else 1.1
	env.ambient_light_energy = 0.25 if on else 0.6
	env.glow_intensity = 1.0 if on else 0.6
	env.fog_light_color = Color(0.02, 0.02, 0.04) if on else Color(0.6, 0.55, 0.55)
	env.background_energy_multiplier = 0.35 if on else 1.0
	renderer.set_night(on)


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
	for a in ["row", "unrow", "left", "right", "tier", "untier"]:
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
	facade_option = OptionButton.new()
	for f in Stand.FACADES:
		facade_option.add_item({ "concrete": "Concrete", "brick": "Brick", "glass": "Glass", "steel": "Steel", "club": "Club colour" }[f] + " walls")
	facade_option.item_selected.connect(func(i: int):
		_report_err(game.set_facade(selected, Stand.FACADES[i]))
		_refresh())
	srow.add_child(facade_option)
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
	tool_buttons.clear()
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
	if layer == "stadium":
		tool_box.add_child(_heading("FLOODLIGHTS"))
		var fl := OptionButton.new()
		for st in Layout.FLOODLIGHT_STYLES:
			fl.add_item({ "pylons": "Corner pylons", "roof": "Roof-mounted", "masts": "Side masts" }[st])
		fl.select(Layout.FLOODLIGHT_STYLES.find(game.layout.floodlights))
		fl.item_selected.connect(func(i: int):
			_report_err(game.set_floodlights(Layout.FLOODLIGHT_STYLES[i]))
			_refresh())
		tool_box.add_child(fl)
		tool_box.add_child(_heading("PITCH"))
		var pp := OptionButton.new()
		for st in Layout.PITCH_PATTERNS:
			pp.add_item({ "stripes": "Stripes", "wide_stripes": "Wide stripes", "checks": "Checkerboard", "plain": "Plain" }[st])
		pp.select(Layout.PITCH_PATTERNS.find(game.layout.pitch_pattern))
		pp.item_selected.connect(func(i: int):
			_report_err(game.set_pitch_pattern(Layout.PITCH_PATTERNS[i]))
			_refresh())
		tool_box.add_child(pp)
		tool_box.add_child(_heading("LAND  (grow the plot for bigger stands and more parking)"))
		land_box = GridContainer.new()
		land_box.columns = 2
		for side in Layout.LAND_SIDES:
			var b := Button.new()
			b.custom_minimum_size = Vector2(160, 28)
			var sd: String = side
			b.pressed.connect(func():
				var err := game.buy_land(sd)
				_report_err(err)
				if err == "":
					_say("Bought land on the %s side. The plot is now %d x %d." % [{"N": "north", "S": "south", "E": "east", "W": "west"}[sd], game.layout.plot.size.x, game.layout.plot.size.y])
				_refresh())
			land_box.add_child(b)
		tool_box.add_child(land_box)
	else:
		land_box = null
	tool_box.add_child(_heading("TOOLS"))
	var g2 := GridContainer.new()
	g2.columns = 3
	g2.add_child(_tool_button("select", "Select", tool_group))
	g2.add_child(_tool_button("demolish", "Demolish", tool_group))
	tool_box.add_child(g2)


func _max_tiers() -> int:
	var m := 1
	for s in game.layout.stands:
		m = maxi(m, s.tiers)
	return m


func _set_level(lv: int) -> void:
	level = lv
	renderer.set_layer(layer, level)
	_follow_level()
	_say("Concourse %s: place facilities on this level. Upper-tier fans use their own level, or walk the stairs." % ("ground level" if lv == 0 else "level %d" % lv))
	_refresh()


## Keep the camera orbiting the floor being worked on.
func _follow_level() -> void:
	var y := -2.5 if layer == "underground" else (StadiumRenderer.level_height(game.layout, level) if layer == "concourse" else 0.0)
	camera.set_height(y)


func _refresh_level_bar() -> void:
	for c in level_bar.get_children():
		c.free()
	var n := _max_tiers()
	if layer != "concourse" or n < 2:
		if level >= n:
			level = 0
		return
	var g := ButtonGroup.new()
	for lv in n:
		var b := Button.new()
		b.text = "Ground" if lv == 0 else "Level %d" % lv
		b.toggle_mode = true
		b.button_group = g
		b.button_pressed = lv == level
		b.custom_minimum_size = Vector2(80, 32)
		var l := lv
		b.pressed.connect(func(): _set_level(l))
		level_bar.add_child(b)


func _refresh_land(prices: Dictionary) -> void:
	if land_box == null or not is_instance_valid(land_box):
		return
	var names := { "N": "North", "S": "South", "E": "East", "W": "West" }
	for i in Layout.LAND_SIDES.size():
		var side: String = Layout.LAND_SIDES[i]
		var b: Button = land_box.get_child(i)
		var cost: float = prices[side]
		b.text = "%s: sold out" % names[side] if cost < 0.0 else "Buy %s (%s)" % [names[side], Season.money(cost)]
		b.disabled = cost < 0.0


func _set_layer(id: String) -> void:
	layer = id
	if layer_buttons.has(id):
		layer_buttons[id].set_pressed_no_signal(true)
	tool = "select"
	selected = -1
	selected_fac = -1
	if id != "concourse":
		level = 0
	renderer.set_layer(id, level)
	_follow_level()
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
	box.add_child(_heading("STADIUM NAME"))
	stadium_edit = LineEdit.new()
	stadium_edit.text = game.club.stadium_name
	stadium_edit.max_length = 32
	stadium_edit.text_submitted.connect(func(t: String): _set_stadium_name(t))
	stadium_edit.focus_exited.connect(func(): _set_stadium_name(stadium_edit.text))
	box.add_child(stadium_edit)
	sponsor_option = OptionButton.new()
	sponsor_option.item_selected.connect(func(i: int):
		_report_err(game.set_sponsor(sponsor_ids[i]))
		_refresh())
	box.add_child(sponsor_option)
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
	b.set_meta("label", text)
	tool_buttons[id] = b
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


func _set_stadium_name(text: String) -> void:
	var t := text.strip_edges()
	if t != "" and t != game.club.stadium_name:
		game.club.stadium_name = t
		_refresh()


func _refresh_sponsors() -> void:
	sponsor_ids = [""]
	sponsor_option.clear()
	sponsor_option.add_item("No naming-rights sponsor")
	for id in config.sponsors:
		var sp: Dictionary = config.sponsors[id]
		sponsor_ids.append(id)
		sponsor_option.add_item("%s %s  (%s/match, fans grumble a bit)" % [sp["name"], sp["suffix"], Season.money(game.sponsor_fee(id))])
	sponsor_option.select(maxi(0, sponsor_ids.find(game.club.sponsor)))
	var open := game.is_unlocked("naming_rights")
	sponsor_option.disabled = not open
	sponsor_option.tooltip_text = "" if open else "Naming rights unlock at %s fans" % _n(config.unlock_fans("naming_rights"))


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
		"tier":
			err = game.set_tiers(selected, s.tiers + 1)
		"untier":
			err = "already a single tier" if s.tiers <= 1 else game.set_tiers(selected, s.tiers - 1)
		"demolish":
			err = game.demolish_stand(selected)
			if err == "":
				selected = -1
	_report_err(err)
	_refresh()


func _on_play() -> void:
	_matchday_end()
	if game.is_over():
		var promoted := game.promotion_earned()
		game.start_next_season()
		last_report = null
		if promoted:
			_say("★ PROMOTED! Welcome to the %s: bigger crowds, TV money and tougher opponents." % config.division(game.club.division)["name"])
		else:
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
	_matchday_show(last_report)
	_refresh()


func _click(tile: Vector2i) -> void:
	if md_panel.visible:
		_matchday_end()
	var stand_tiles := game.layout.stand_tile_map()
	var concourse := game.layout.concourse_tile_map(config)
	if config.facility_types.has(tool):
		var nf := Facility.make(tool, tile)
		if config.facility_type(tool).layer == "concourse":
			nf.level = level
		var err := game.build_facility(nf)
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
		if ft.layer == "concourse" and f.level != level:
			continue
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
	var floor_y := StadiumRenderer.level_height(game.layout, level) if layer == "concourse" else 0.0
	if absf(dir.y) > 1e-5:
		var t := (floor_y - from.y) / dir.y
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
		if ft.layer == "concourse":
			probe.level = level
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
			renderer.show_ghost_tile(hover, ok, ft.size, ft.layer == "underground", StadiumRenderer.level_height(game.layout, level) if ft.layer == "concourse" else 0.0)
		_say("%s: %s%s" % [ft.display_name, Season.money(ft.build_cost), "" if ok else "  (can't go here)"])
	else:
		renderer.show_hover_tile(hover)


# --- Refresh / text --------------------------------------------------------

func _refresh() -> void:
	var c := game.club
	var fx := game.next_fixture()
	var match_text := "Season over" if fx == null else "Match %d/%d" % [game.next_match_number(), game.fixtures.size()]
	var need := game.points_to_promotion()
	var league := "%s  %d pts%s" % [config.division(c.division)["name"], game.summary().points,
		"" if need < 0 else (" ✓ promotion!" if need == 0 else " (need %d)" % need)]
	hud.text = "S%d  %s  ·  %s  ·  Cash %s  Fans %s  Mood %d  Cap %s" % [
		game.season_number, match_text, league, Season.money(c.cash), _n(c.fanbase), roundi(c.mood),
		_n(game.layout.capacity_total(config))]

	title_label.text = c.club_name
	title_label.add_theme_color_override("font_color", c.secondary_color if c.secondary_color.get_luminance() > 0.35 else c.primary_color.lightened(0.4))
	tool_hint.text = _tool_hint()
	_refresh_level_bar()
	for id in tool_buttons:
		var b: Button = tool_buttons[id]
		if not is_instance_valid(b):
			continue
		var open := game.is_unlocked(id)
		b.disabled = not open
		b.text = b.get_meta("label") if open else "%s 🔒%sk" % [b.get_meta("label"), _n(config.unlock_fans(id) / 1000.0)]
		b.tooltip_text = "" if open else "%s unlocks at %s fans" % [b.get_meta("label"), _n(config.unlock_fans(id))]
		b.clip_text = true
		if open:
			b.remove_theme_font_size_override("font_size")
		else:
			b.add_theme_font_size_override("font_size", 11)
	ground_label.text = c.ground_name(config)
	_refresh_sponsors()
	_refresh_selection()
	for id in price_labels:
		price_labels[id].text = "%s  £%d" % [config.stand_type(id).display_name, roundi(c.price(id))]
	if game.is_over():
		play_button.text = "Start season %d" % (game.season_number + 1)
	else:
		play_button.text = "Play match %d: vs %s%s" % [game.next_match_number(), fx.opponent, "  (BIG!)" if fx.big else (" (night)" if fx.evening else "")]
	report_box.text = _report_text()
	_sync_world()
	_autosave()  # cheap; keeps every build and setting safe


func _sync_world() -> void:
	var c := game.club
	if game.layout.plot != _static_plot or renderer.pitch_pattern != game.layout.pitch_pattern:
		_static_plot = game.layout.plot
		renderer.pitch_pattern = game.layout.pitch_pattern
		renderer.build_static(game.layout)
		camera.bounds = Rect2(game.layout.plot)
	var prices := {}
	for side in Layout.LAND_SIDES:
		prices[side] = game.land_cost(side)
	renderer.show_land_offers(game.layout, prices)
	_refresh_land(prices)
	var sig := hash([game.layout.to_dict(), selected, last_report.seed if last_report else -1, game.reports.size(),
		c.club_name, c.primary_color, c.secondary_color, c.ground_name(config)])
	if sig != _world_sig:
		_world_sig = sig
		renderer.ground_name = c.ground_name(config)
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
	if f.income_per_match > 0:
		bits.append("Earns ~%s/match." % Season.money(f.income_per_match))
	if f.box_price > 0:
		bits.append("Corporate boxes along the stand, ~%s each when sold." % Season.money(f.box_price))
	if f.requires_tiers > 1:
		bits.append("Needs a stand with %d tiers." % f.requires_tiers)
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
	sel_label.text = "%s stand (%s): %d rows x %d tier%s, %s places, noise %.1f" % [
		t.display_name, where, s.depth, s.tiers, "" if s.tiers == 1 else "s", _n(s.capacity(t)), t.noise]
	sel_buttons["left"].visible = not s.is_corner()
	sel_buttons["right"].visible = not s.is_corner()
	roof_option.select(Stand.ROOF_STYLES.find(s.roof))
	facade_option.select(Stand.FACADES.find(s.facade))
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
	var max_t := config.integer("layout/max_tiers")
	sel_buttons["tier"].text = "Add tier (%s)" % Season.money(game.tier_cost(selected, s.tiers + 1)) if s.tiers < max_t else "Max tiers"
	sel_buttons["tier"].disabled = s.tiers >= max_t
	if s.tiers < max_t and not game.is_unlocked("tier%d" % (s.tiers + 1)):
		sel_buttons["tier"].text = "🔒 Tier at %s fans" % _n(config.unlock_fans("tier%d" % (s.tiers + 1)))
		sel_buttons["tier"].disabled = true
	sel_buttons["untier"].text = "Remove tier"
	sel_buttons["untier"].disabled = s.tiers <= 1


func _report_text() -> String:
	if game.is_over():
		var sr := game.summary()
		var up := "\n[color=#ffd54f][b]★ PROMOTED to the %s![/b][/color]" % config.division(game.club.division + 1)["name"] if game.promotion_earned() else ""
		if game.points_to_promotion() > 0:
			up = "\n[color=#aaaaaa]%d points short of promotion. Louder stands win more at home![/color]" % game.points_to_promotion()
		return "[b]SEASON %d DONE[/b] · " % sr.season_number + sr.division_name + up + ("\nRecord W%d D%d L%d (%d pts)\nAverage crowd %s\nFans %s → %s\nTakings %s\nCash now %s\n\nPress Start season to carry on.") % [
			sr.wins, sr.draws, sr.losses, sr.points, _n(sr.attendance_avg),
			_n(sr.fanbase_start), _n(sr.fanbase_end), Season.money(sr.net), Season.money(sr.cash_end)]
	var r := last_report
	if r == null:
		return "[color=#aaaaaa]Build some stands, then play a match.[/color]"
	if show_details:
		return "[code]" + r.to_text().replace("[", "[lb]") + "[/code]"
	var res := { "W": "[color=#8fe88f][b]WIN![/b][/color]", "D": "[b]DRAW[/b]", "L": "[color=#ff8a80][b]LOSS[/b][/color]" }
	var lines := PackedStringArray()
	lines.append("%s  %d–%d vs %s%s" % [res[r.result], r.home_goals, r.away_goals, r.opponent, "  (big match)" if r.big_match else ""])
	lines.append("Crowd [b]%s[/b] / %s" % [_n(r.attendance), _n(r.capacity)])
	lines.append("Atmosphere [b]%d[/b] %s" % [roundi(r.atmosphere), "▮".repeat(roundi(r.atmosphere / 10.0))])
	lines.append("Takings [b]%s[/b]  (costs %s incl. utilities %s)" % [Season.money(r.revenue["total"]), Season.money(r.costs["total"]), Season.money(r.costs.get("utilities", 0.0))])
	var extras := PackedStringArray()
	for k in ["food", "drinks", "merch", "sponsors", "boxes", "venue", "naming", "tv"]:
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
