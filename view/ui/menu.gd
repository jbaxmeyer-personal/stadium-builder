extends Control
## The title / pause menu over the world: Continue, New club, Load (save
## slots), Save (pause only), Settings and Quit. Settings (graphics quality,
## volume, fullscreen) are kept in user://settings.cfg.

const SETTINGS_FILE := "user://settings.cfg"
const SAVE_DIR := "user://saves"
const QUALITY := ["Low", "Medium", "High"]

var ui: Control          # GameUI
var pause := false       # opened from inside a game (Esc) rather than at launch
var _panel: PanelContainer
var _body: VBoxContainer


func _init(p_ui: Control, p_pause: bool) -> void:
	ui = p_ui
	pause = p_pause
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_panel = PanelContainer.new()
	add_child(_panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_panel.add_child(_body)
	_main()


func _clear() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()


func _center() -> void:
	_panel.reset_size()
	(func():
		_panel.reset_size()
		_panel.position = (get_viewport_rect().size - _panel.size) / 2.0).call_deferred()


func _button(text: String, cb: Callable, primary := false, sub := "") -> Button:
	var b := Button.new()
	b.text = text if sub == "" else "%s\n%s" % [text, sub]
	b.custom_minimum_size = Vector2(320, 54 if sub != "" else 44)
	b.add_theme_font_size_override("font_size", 17 if primary else 15)
	if primary:
		b.add_theme_stylebox_override("normal", ui._box(Color(ui.C_ACCENT, 0.85), 10, ui.C_ACCENT, 1, 8))
		b.add_theme_stylebox_override("hover", ui._box(ui.C_ACCENT, 10, Color.WHITE, 1, 8))
		b.add_theme_color_override("font_color", Color(0.08, 0.08, 0.1))
		b.add_theme_color_override("font_hover_color", Color(0.08, 0.08, 0.1))
	b.pressed.connect(cb)
	_body.add_child(b)
	return b


func _title(t: String, sub := "") -> void:
	var l: Label = ui._label(t, 30 if not pause else 22, ui.C_ACCENT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(l)
	if sub != "":
		var s: Label = ui._label(sub, 13, ui.C_MUTED)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_body.add_child(s)


func _close() -> void:
	queue_free()


# --- screens ----------------------------------------------------------------------

func _main() -> void:
	_clear()
	var g: Season = ui.m.game
	if pause:
		_title("PAUSED", "%s · Season %d" % [g.club.club_name, g.season_number])
		_button("Back to the game", _close, true)
		_button("Save game", _save_screen)
		_button("Load game", _load_screen)
		_button("New club", func():
			_close()
			ui.m._new_game_clicked())
	else:
		_title("STADIUM BUILDER", "Build the ground. Grow the club.")
		if ui.m.has_autosave:
			_button("Continue", _close, true, "%s · Season %d · %s" % [g.club.club_name, g.season_number, ui.m.config.division(g.club.division)["name"]])
			_button("New club", func():
				_close()
				ui.m._new_game_clicked())
		else:
			_button("New club", func():
				_close()
				ui.open_new_game(), true)
		_button("Load game", _load_screen)
	_button("Settings", _settings_screen)
	_button("Quit", func(): ui.get_tree().quit())
	_center()


func _save_screen() -> void:
	_clear()
	_title("SAVE GAME")
	var g: Season = ui.m.game
	var row := HBoxContainer.new()
	var name := LineEdit.new()
	name.text = "%s S%d" % [g.club.club_name, g.season_number]
	name.custom_minimum_size = Vector2(240, 0)
	row.add_child(name)
	var go := Button.new()
	go.text = "Save"
	go.pressed.connect(func():
		var err: String = ui.m.save_named(name.text)
		ui.m._say(err if err != "" else "Saved as \"%s\"." % name.text.strip_edges())
		_main())
	row.add_child(go)
	_body.add_child(row)
	_slot_list(false)
	_button("Back", _main)
	_center()


func _load_screen() -> void:
	_clear()
	_title("LOAD GAME")
	if not _slot_list(true):
		_body.add_child(ui._label("No saved games yet. Save from the pause menu (Esc).", 13, ui.C_MUTED))
	_button("Back", _main)
	_center()


## Lists the save slots; with `load`, clicking one loads it, otherwise it
## overwrites it with the current game. Returns false if there are none.
func _slot_list(load: bool) -> bool:
	var slots: Array = ui.m.list_saves()
	if slots.is_empty():
		return false
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, mini(slots.size(), 5) * 58)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	for s in slots:
		var slot: Dictionary = s
		var h := HBoxContainer.new()
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 52)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s\n%s" % [slot["name"], slot["info"]]
		var path: String = slot["path"]
		b.pressed.connect(func():
			if load:
				if ui.m.load_named(path):
					_close()
			else:
				ui.m.save_to(path)
				ui.m._say("Saved.")
				_main())
		h.add_child(b)
		var del := Button.new()
		del.text = "✕"
		del.tooltip_text = "Delete this save"
		del.pressed.connect(func():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			if load:
				_load_screen()
			else:
				_save_screen())
		h.add_child(del)
		v.add_child(h)
	_body.add_child(scroll)
	return true


func _settings_screen() -> void:
	_clear()
	_title("SETTINGS")
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	grid.add_child(ui._label("Graphics", 14))
	var q := OptionButton.new()
	for name in QUALITY:
		q.add_item(name)
	q.select(int(cfg.get_value("video", "quality", 2)))
	q.tooltip_text = "Low is fastest: fewer shadows and effects"
	q.item_selected.connect(func(i: int): _store("video", "quality", i))
	grid.add_child(q)
	grid.add_child(ui._label("Fullscreen", 14))
	var fs := CheckButton.new()
	fs.button_pressed = bool(cfg.get_value("video", "fullscreen", false))
	fs.toggled.connect(func(on: bool): _store("video", "fullscreen", on))
	grid.add_child(fs)
	grid.add_child(ui._label("Volume", 14))
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.custom_minimum_size = Vector2(200, 0)
	vol.value = float(cfg.get_value("audio", "volume", 0.8))
	vol.value_changed.connect(func(v: float): _store("audio", "volume", v))
	grid.add_child(vol)
	grid.add_child(ui._label("Crowd sound", 14))
	var cs := CheckButton.new()
	cs.button_pressed = not ui.m.crowd_audio.muted
	cs.toggled.connect(func(on: bool): ui.m.crowd_audio.muted = not on)
	grid.add_child(cs)
	grid.add_child(ui._label("Roofs", 14))
	var rf := CheckButton.new()
	rf.button_pressed = ui.m.renderer.show_roofs
	rf.toggled.connect(func(on: bool): ui.m.renderer.show_roofs = on)
	grid.add_child(rf)
	_body.add_child(grid)
	_body.add_child(ui._label("Wheel: zoom · Left-drag: move · Right-drag or Q/E: rotate · WASD: move\nRight-click or Esc: put the tool down · Esc with nothing in hand: this menu", 12, ui.C_MUTED))
	_button("Back", _main)
	_center()


func _store(section: String, key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	cfg.set_value(section, key, value)
	cfg.save(SETTINGS_FILE)
	ui.m.apply_settings()
