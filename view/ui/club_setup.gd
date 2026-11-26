extends HBoxContainer
## Club identity editor: names, founding year, the three club colours (full
## colour pickers plus kit presets), the badge designer (shape, split pattern,
## symbol, initials, stars, or an uploaded logo), and, for a new game, the
## surroundings and sky. Used by the new-game screen and the Club window.
## Every change is applied live through `ui.m` so the world behind updates.

const Badge := preload("res://view/ui/badge.gd")

const SHAPE_NAMES := { "shield": "Shield", "round": "Round", "classic": "Heater", "diamond": "Diamond", "square": "Square", "pennant": "Pennant" }
const PATTERN_NAMES := { "plain": "Plain", "halves": "Halves", "quarters": "Quarters", "stripes": "Stripes", "hoops": "Hoops", "chevron": "Chevron",
	"sash": "Sash", "cross": "Cross", "border": "Border" }
const SYMBOL_NAMES := { "none": "None", "ball": "Ball", "star": "Star", "crown": "Crown", "lion": "Lion", "bird": "Bird", "tower": "Castle",
	"anchor": "Anchor", "oak": "Oak", "rose": "Rose", "bolt": "Bolt", "wheel": "Wheel" }
const SKY_NAMES := { "sunny": "Sunny", "cloudy": "Cloudy", "overcast": "Overcast", "golden": "Golden hour" }

var ui: Control        # GameUI
var full: bool         # new game: also surroundings and sky
var preview: Control
var _body: VBoxContainer
var _file: FileDialog


func _init(p_ui: Control, p_full: bool) -> void:
	ui = p_ui
	full = p_full
	add_theme_constant_override("separation", 18)


func _ready() -> void:
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	preview = Badge.new(_club())
	preview.custom_minimum_size = Vector2(150, 150)
	left.add_child(preview)
	var up := Button.new()
	up.text = "Upload logo…"
	up.tooltip_text = "Use your own PNG or JPG as the club badge"
	up.pressed.connect(_pick_logo)
	left.add_child(up)
	if String(_club().badge.get("logo", "")) != "":
		var rm := Button.new()
		rm.text = "Use designer"
		rm.tooltip_text = "Drop the uploaded logo and design a badge"
		rm.pressed.connect(func(): _set_badge("logo", ""))
		left.add_child(rm)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 470 if full else 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_build()


func _club() -> ClubState:
	return ui.m.game.club


func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_ready()


func _changed() -> void:
	ui.m._refresh()
	preview.refresh()


func _section(t: String) -> void:
	_body.add_child(ui._label(t, 11, ui.C_MUTED))


func _build() -> void:
	var c := _club()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	_field(grid, "Club name", c.club_name, 220, func(t: String):
		if t.strip_edges() != "":
			c.club_name = t.strip_edges())
	_field(grid, "Short name", c.short_name, 120, func(t: String): c.short_name = t.strip_edges(), c.nickname())
	_field(grid, "Ground", c.stadium_name, 220, func(t: String):
		if t.strip_edges() != "":
			c.stadium_name = t.strip_edges())
	grid.add_child(ui._label("Founded", 12, ui.C_MUTED))
	var fy := SpinBox.new()
	fy.min_value = 1850
	fy.max_value = 2026
	fy.value = c.founded
	fy.custom_minimum_size = Vector2(120, 0)
	fy.value_changed.connect(func(v: float):
		c.founded = int(v)
		_changed())
	grid.add_child(fy)
	_body.add_child(grid)

	_section("CLUB COLOURS")
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	for k in [["Home", "primary_color"], ["Away", "secondary_color"], ["Trim", "third_color"]]:
		var prop: String = k[1]
		var box := VBoxContainer.new()
		box.add_child(ui._label(k[0], 11, ui.C_MUTED))
		var cp := ColorPickerButton.new()
		cp.custom_minimum_size = Vector2(70, 30)
		cp.edit_alpha = false
		cp.color = c.get(prop)
		var pk := cp.get_picker()
		pk.picker_shape = ColorPicker.SHAPE_HSV_WHEEL
		pk.presets_visible = false
		pk.color_modes_visible = true
		cp.color_changed.connect(func(col: Color):
			c.set(prop, col)
			preview.refresh())
		cp.popup_closed.connect(func(): ui.m._refresh())
		box.add_child(cp)
		cols.add_child(box)
	cols.add_child(VSeparator.new())
	var kits := HFlowContainer.new()
	kits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for kit in ui.m.KITS:
		var pc: Color = kit[1]
		var sc: Color = kit[2]
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 30)
		b.tooltip_text = kit[0]
		var sb: StyleBoxFlat = ui._box(pc, 15, sc, 4, 0)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
		b.pressed.connect(func():
			c.primary_color = pc
			c.secondary_color = sc
			_changed()
			_rebuild())
		kits.add_child(b)
	cols.add_child(kits)
	_body.add_child(cols)

	_section("BADGE")
	if String(c.badge.get("logo", "")) != "":
		_body.add_child(ui._label("Using your uploaded logo. Pick \"Use designer\" to design one instead.", 12, ui.C_MUTED))
	else:
		_chips("Shape", Badge.SHAPES, SHAPE_NAMES, "shape")
		_chips("Pattern", Badge.PATTERNS, PATTERN_NAMES, "pattern")
		_chips("Symbol", Badge.SYMBOLS, SYMBOL_NAMES, "symbol")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(ui._label("Letters", 12, ui.C_MUTED))
		var le := LineEdit.new()
		le.text = String(c.badge.get("text", ""))
		le.placeholder_text = c.initials()
		le.max_length = 5
		le.custom_minimum_size = Vector2(90, 0)
		le.text_changed.connect(func(t: String):
			c.badge["text"] = t.strip_edges().to_upper()
			preview.refresh())
		le.focus_exited.connect(func(): ui.m._refresh())
		row.add_child(le)
		row.add_child(ui._label("Stars", 12, ui.C_MUTED))
		var stars := SpinBox.new()
		stars.min_value = 0
		stars.max_value = 5
		stars.value = int(c.badge.get("stars", 0))
		stars.tooltip_text = "Stars above the badge, one per title"
		stars.value_changed.connect(func(v: float): _set_badge("stars", int(v), false))
		row.add_child(stars)
		var sw := CheckButton.new()
		sw.text = "Swap colours"
		sw.button_pressed = bool(c.badge.get("swap", false))
		sw.toggled.connect(func(on: bool): _set_badge("swap", on))
		row.add_child(sw)
		_body.add_child(row)

	if full:
		_section("SURROUNDINGS")
		_text_chips(Layout.SURROUNDINGS, ui.SURROUND_NAMES, ui.m.game.layout.surroundings, func(v: String):
			ui.m.game.set_surroundings(v)
			ui.m._refresh())
		_section("SKY")
		_text_chips(Layout.SKIES, SKY_NAMES, ui.m.game.layout.sky, func(v: String):
			ui.m.game.set_sky(v)
			ui.m._apply_sky(v))


func _field(grid: GridContainer, label: String, value: String, w: float, set_fn: Callable, placeholder := "") -> void:
	grid.add_child(ui._label(label, 12, ui.C_MUTED))
	var le := LineEdit.new()
	le.text = value
	le.placeholder_text = placeholder
	le.custom_minimum_size = Vector2(w, 0)
	le.text_changed.connect(func(t: String):
		set_fn.call(t)
		preview.refresh())
	le.focus_exited.connect(func(): ui.m._refresh())
	grid.add_child(le)


func _set_badge(key: String, value: Variant, rebuild := true) -> void:
	_club().badge[key] = value
	_changed()
	if rebuild:
		_rebuild()


## A row of mini badges, one per option, each drawn with that option applied.
func _chips(label: String, options: Array, names: Dictionary, key: String) -> void:
	var c := _club()
	var row := HBoxContainer.new()
	var l: Label = ui._label(label, 12, ui.C_MUTED)
	l.custom_minimum_size = Vector2(60, 0)
	row.add_child(l)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(flow)
	for o in options:
		var opt: String = o
		var b := Button.new()
		b.custom_minimum_size = Vector2(42, 42)
		b.tooltip_text = names.get(opt, opt)
		b.toggle_mode = true
		b.button_pressed = String(c.badge.get(key, "")) == opt
		var mock := ClubState.new()
		mock.club_name = c.club_name
		mock.founded = c.founded
		mock.primary_color = c.primary_color
		mock.secondary_color = c.secondary_color
		mock.third_color = c.third_color
		mock.badge = c.badge.duplicate()
		mock.badge[key] = opt
		mock.badge["stars"] = 0
		mock.badge["logo"] = ""
		var mini := Badge.new(mock)
		mini.set_anchors_preset(Control.PRESET_FULL_RECT)
		mini.offset_left = 5
		mini.offset_top = 5
		mini.offset_right = -5
		mini.offset_bottom = -5
		b.add_child(mini)
		b.pressed.connect(func(): _set_badge(key, opt))
		flow.add_child(b)
	_body.add_child(row)


func _text_chips(options: Array, names: Dictionary, current: String, cb: Callable) -> void:
	var flow := HFlowContainer.new()
	var g := ButtonGroup.new()
	for o in options:
		var opt: String = o
		var b := Button.new()
		b.text = names.get(opt, opt.capitalize())
		b.toggle_mode = true
		b.button_group = g
		b.button_pressed = opt == current
		b.custom_minimum_size = Vector2(0, 32)
		b.pressed.connect(func(): cb.call(opt))
		flow.add_child(b)
	_body.add_child(flow)


func _pick_logo() -> void:
	_file = FileDialog.new()
	_file.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file.access = FileDialog.ACCESS_FILESYSTEM
	_file.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	_file.use_native_dialog = true
	_file.title = "Pick your club badge"
	_file.file_selected.connect(_logo_chosen)
	ui.add_child(_file)
	_file.popup_centered(Vector2i(800, 520))


## Copies the picked image into user:// (squared up, at most 512 px) so the
## save keeps working if the original moves.
func _logo_chosen(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		ui.m._say("Couldn't read that image.")
		return
	img.convert(Image.FORMAT_RGBA8)
	var s := maxi(img.get_width(), img.get_height())
	var sq := Image.create(s, s, false, Image.FORMAT_RGBA8)
	sq.fill(Color(0, 0, 0, 0))
	sq.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((s - img.get_width()) / 2, (s - img.get_height()) / 2))
	if s > 512:
		sq.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	var out := "user://badge_%d.png" % int(Time.get_unix_time_from_system())
	sq.save_png(out)
	_set_badge("logo", out)
