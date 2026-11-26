extends Control
## The game's HUD, SimCity-style: a slim top bar of stats, a left rail for
## views and camera, a bottom build dock (pick a category, then click or drag
## a tile onto the ground), a floating card for whatever is selected, a big
## play button, and pop-up windows for the club and settings.
## Reads game state from `m` (view/main.gd) and calls its commands.

const Icon := preload("res://view/ui/icons.gd")
const HistoryWindow := preload("res://view/ui/history_window.gd")
const LeagueWindow := preload("res://view/ui/league_window.gd")
const Badge := preload("res://view/ui/badge.gd")
const ClubSetup := preload("res://view/ui/club_setup.gd")
const StadiumRendererRef := preload("res://view/stadium_renderer.gd")

const C_PANEL := Color(0.07, 0.09, 0.12, 0.88)
const C_PANEL_2 := Color(0.12, 0.15, 0.19, 0.95)
const C_LINE := Color(1, 1, 1, 0.08)
const C_TEXT := Color(0.93, 0.94, 0.96)
const C_MUTED := Color(0.62, 0.66, 0.72)
const C_ACCENT := Color(1.0, 0.78, 0.25)
const C_GOOD := Color(0.45, 0.88, 0.5)
const C_BAD := Color(1.0, 0.5, 0.42)

## Build categories per layer: [id, label, icon, [item ids]]
const DOCK := {
	"stadium": [
		["stands", "Stands", "stands_cat", ["pitch", "bank", "terrace", "seated", "premium", "family", "safe_standing"]],
		["bowl", "In the bowl", "bowl_cat", ["video_board", "ribbon_board", "scoreboard", "sound_system", "exec_boxes"]],
		["transport", "Transport", "transport_cat", ["car_park", "multi_storey", "bus_stop", "train_station"]],
		["site", "Roads & paths", "road_cat", ["road", "path_concrete", "path_brick", "path_cobble", "path_gravel"]],
		["green", "Landscaping", "green_cat", ["tree_oak", "tree_birch", "tree_pine", "tree_plane", "hedge", "flowers", "bench", "bin", "lamp", "flagpole", "fence"]],
		["around", "Around", "around_cat", ["clubhouse", "tea_bar", "turnstile_hut", "statue", "ticket_office", "museum", "hotel"]],
		["land", "Land", "land_cat", ["land_N", "land_S", "land_E", "land_W"]],
		["looks", "Looks", "looks_cat", []],
	],
	"concourse": [
		["food", "Food & drink", "food_cat", ["kiosk", "bar"]],
		["services", "Services", "services_cat", ["restroom", "first_aid"]],
		["shops", "Shops & fans", "shops_cat", ["merch", "fan_zone"]],
	],
	"underground": [
		["under", "Underground", "transport_cat", ["garage", "subway"]],
	],
}
const SURROUND_NAMES := { "town": "Town", "riverside": "Riverside", "lakeside": "Lakeside", "mountains": "Mountains",
	"city_edge": "City edge", "suburban": "Suburbs", "city": "City", "fields": "Fields", "forest": "Forest" }
const ROOF_NAMES := { "cantilever": "Modern", "gable": "Classic", "shed": "Shed", "barrel": "Barrel", "truss": "Truss", "mast": "Masts", "open": "None" }
const FACADE_COLORS := { "concrete": Color(0.75, 0.75, 0.73), "brick": Color(0.62, 0.3, 0.22), "glass": Color(0.55, 0.72, 0.85),
	"steel": Color(0.6, 0.63, 0.68), "club": Color(1, 1, 1), "fins": Color(0.5, 0.38, 0.26), "panels": Color(0.66, 0.38, 0.26), "arcade": Color(0.88, 0.87, 0.84) }
const FACADE_NAMES := { "concrete": "Concrete", "brick": "Brick", "glass": "Glass", "steel": "Steel", "club": "Club colour", "fins": "Fins", "panels": "Metal panels", "arcade": "Colonnade" }
const SEAT_PATTERN_NAMES := { "plain": "Plain", "stripes": "Rows", "blocks": "Blocks", "checks": "Checks", "mosaic": "Mosaic", "text": "Word", "crest": "Crest" }
const SEAT_PATTERN_TIPS := { "plain": "One colour", "stripes": "Alternate rows", "blocks": "Blocks along the stand", "checks": "A chequerboard",
	"mosaic": "Mixed shades, like an old stand", "text": "Spell a word in seats", "crest": "A shield outline in seats" }
const GEAR_OPTION_NAMES := { "size": "Size", "frame": "Frame", "content": "Shows", "digits": "Digits", "color": "Colour" }
const NET_COLORS := ["ffffff", "ffd700", "d93030", "2f5fd0", "1f1f1f", "2f9e4f"]
const EXTRA_NAMES := { "flags": ["Flags", "Flagpoles along the roof"], "lights": ["LED strip", "A light strip along the roof edge"],
	"clock": ["Clock", "A clock on the roof"], "banners": ["Banners", "Fan banners along the front"] }

var m: Node            # view/main.gd
var show_details := false
var category := ""

var top_bar: PanelContainer
var crest: Control
var new_game_screen: Control
var club_label: Label
var stat := {}          # name -> Label
var mood_icon: Icon
var mood_bar: ProgressBar
var league_bar: ProgressBar
var rail: VBoxContainer
var layer_btns := {}
var level_box: VBoxContainer
var dock: PanelContainer
var dock_row: HBoxContainer
var tray: PanelContainer
var tray_title: Label
var tray_flow: HFlowContainer
var tiles := {}          # id -> tile Control
var card: PanelContainer
var card_body: VBoxContainer
var card_scroll: ScrollContainer
var _card_root: VBoxContainer
var looks_tab := "world"
var card_tab := "build"            # stand card tab: build / look / signs / gear
var _tab_boxes := {}
var play_panel: PanelContainer
var play_btn: Button
var play_sub: Label
var play_tags: HBoxContainer
var result_card: PanelContainer
var result_body: VBoxContainer
var toast_panel: PanelContainer
var toast_label: Label
var toast_tween: Tween
var hover_label: Label
var windows := {}
var drag_id := ""
var drag_icon: Icon
var md_panel: PanelContainer
var md_title: Label
var md_score: Label
var md_info: Label
var md_noise: ProgressBar
var md_milestone: Label


func _init(main: Node) -> void:
	m = main
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	theme = _make_theme()
	_build_top_bar()
	_build_rail()
	_build_dock()
	_build_card()
	_build_play()
	_build_result_card()
	_build_toast()
	_build_matchday()
	hover_label = Label.new()
	hover_label.add_theme_font_size_override("font_size", 13)
	hover_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hover_label.add_theme_constant_override("outline_size", 6)
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hover_label)
	_build_guide()
	drag_icon = Icon.new()
	drag_icon.size = Vector2(56, 56)
	drag_icon.visible = false
	drag_icon.modulate = Color(1, 1, 1, 0.85)
	add_child(drag_icon)


# --- theme -------------------------------------------------------------------

func _box(bg: Color, radius := 10, border := Color(0, 0, 0, 0), bw := 0, pad := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_content_margin_all(pad)
	sb.anti_aliasing = true
	return sb


func _panel_box() -> StyleBoxFlat:
	var sb := _box(C_PANEL, 14, C_LINE, 1, 10)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	return sb


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	t.set_color("font_color", "Label", C_TEXT)
	t.set_stylebox("panel", "PanelContainer", _panel_box())
	t.set_stylebox("normal", "Button", _box(Color(1, 1, 1, 0.06), 9, Color(1, 1, 1, 0.06), 1, 6))
	t.set_stylebox("hover", "Button", _box(Color(1, 1, 1, 0.14), 9, Color(1, 1, 1, 0.12), 1, 6))
	t.set_stylebox("pressed", "Button", _box(Color(C_ACCENT, 0.3), 9, C_ACCENT, 2, 6))
	t.set_stylebox("hover_pressed", "Button", _box(Color(C_ACCENT, 0.36), 9, C_ACCENT, 2, 6))
	t.set_stylebox("disabled", "Button", _box(Color(1, 1, 1, 0.03), 9, Color(0, 0, 0, 0), 0, 6))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", C_ACCENT)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	t.set_stylebox("normal", "LineEdit", _box(Color(1, 1, 1, 0.07), 8, Color(1, 1, 1, 0.1), 1, 7))
	t.set_stylebox("focus", "LineEdit", _box(Color(1, 1, 1, 0.1), 8, C_ACCENT, 1, 7))
	t.set_stylebox("background", "ProgressBar", _box(Color(1, 1, 1, 0.1), 4, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("fill", "ProgressBar", _box(C_ACCENT, 4, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("panel", "TooltipPanel", _box(Color(0.05, 0.06, 0.08, 0.96), 8, C_LINE, 1, 8))
	t.set_color("font_color", "TooltipLabel", C_TEXT)
	t.set_stylebox("panel", "PopupMenu", _box(C_PANEL_2, 8, C_LINE, 1, 6))
	return t


func _icon_button(id: String, tip: String, sz := 40, cb: Callable = Callable(), toggle := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(sz, sz)
	b.tooltip_text = tip
	b.toggle_mode = toggle
	var ic := Icon.new(id)
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 6
	ic.offset_top = 6
	ic.offset_right = -6
	ic.offset_bottom = -6
	b.add_child(ic)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _label(text: String, size := 14, col := C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


# --- top bar -----------------------------------------------------------------

func _build_top_bar() -> void:
	top_bar = PanelContainer.new()
	var sb := _panel_box()
	sb.set_corner_radius_all(0)
	sb.corner_radius_bottom_left = 16
	sb.corner_radius_bottom_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	top_bar.add_theme_stylebox_override("panel", sb)
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 160
	top_bar.offset_right = -160
	add_child(top_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	top_bar.add_child(row)
	crest = Badge.new(m.game.club)
	crest.custom_minimum_size = Vector2(34, 34)
	row.add_child(crest)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -4)
	club_label = _label("", 15)
	names.add_child(club_label)
	stat["ground"] = _label("", 11, C_MUTED)
	names.add_child(stat["ground"])
	row.add_child(names)
	row.add_child(VSeparator.new())
	_stat(row, "coin", "cash", "Cash")
	_stat(row, "fans", "fans", "Fanbase: everyone who wants to come")
	_stat(row, "capacity", "cap", "Stadium capacity")
	var mood := HBoxContainer.new()
	mood.tooltip_text = "Fan mood"
	mood.mouse_filter = Control.MOUSE_FILTER_PASS
	mood_icon = Icon.new("mood_good")
	mood_icon.custom_minimum_size = Vector2(22, 22)
	mood.add_child(mood_icon)
	mood_bar = ProgressBar.new()
	mood_bar.custom_minimum_size = Vector2(56, 8)
	mood_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mood_bar.show_percentage = false
	mood.add_child(mood_bar)
	row.add_child(mood)
	row.add_child(VSeparator.new())
	var league := HBoxContainer.new()
	league.add_theme_constant_override("separation", 6)
	league.mouse_filter = Control.MOUSE_FILTER_PASS
	var trophy := Icon.new("trophy", C_ACCENT)
	trophy.custom_minimum_size = Vector2(22, 22)
	league.add_child(trophy)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 0)
	stat["league"] = _label("", 12)
	lv.add_child(stat["league"])
	league_bar = ProgressBar.new()
	league_bar.custom_minimum_size = Vector2(120, 6)
	league_bar.show_percentage = false
	lv.add_child(league_bar)
	league.add_child(lv)
	stat["league_box"] = league
	league.mouse_filter = Control.MOUSE_FILTER_STOP
	league.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	league.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			open_league("table"))
	row.add_child(league)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	stat["season"] = _label("", 13, C_MUTED)
	row.add_child(stat["season"])
	row.add_child(_icon_button("trophy", "League table, results and squad budget", 34, func(): open_league("table")))
	row.add_child(_icon_button("history", "History: seasons, money, charts", 34, func(): _toggle_window("history")))
	row.add_child(_icon_button("gear", "Settings and save", 34, func(): _toggle_window("settings")))


func _stat(row: HBoxContainer, icon: String, key: String, tip: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	h.tooltip_text = tip
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	var ic := Icon.new(icon)
	ic.custom_minimum_size = Vector2(22, 22)
	h.add_child(ic)
	stat[key] = _label("", 15)
	h.add_child(stat[key])
	row.add_child(h)


# --- left rail: views and camera -----------------------------------------------

func _build_rail() -> void:
	var p := PanelContainer.new()
	p.position = Vector2(12, 70)
	add_child(p)
	rail = VBoxContainer.new()
	rail.add_theme_constant_override("separation", 6)
	p.add_child(rail)
	var cb := _icon_button("shirt", "Club: name, colours, badge, tickets, sponsor", 48, func(): _toggle_window("club"))
	rail.add_child(cb)
	rail.add_child(HSeparator.new())
	var g := ButtonGroup.new()
	for l in [["stadium", "layer_stadium", "Stadium view"], ["concourse", "layer_concourse", "Concourse view: stands go see-through"],
			["underground", "layer_underground", "Underground view"]]:
		var lid: String = l[0]
		var b := _icon_button(l[1], l[2], 48, func(): m._set_layer(lid), true)
		b.button_group = g
		b.button_pressed = lid == "stadium"
		layer_btns[lid] = b
		rail.add_child(b)
	level_box = VBoxContainer.new()
	level_box.add_theme_constant_override("separation", 4)
	rail.add_child(level_box)
	rail.add_child(HSeparator.new())
	for c in [["zoomIn", "Zoom in (mouse wheel)", func(): m.camera.zoom(0.8)], ["zoomOut", "Zoom out", func(): m.camera.zoom(1.25)],
			["rotate_l", "Rotate left (Q, or right-drag)", func(): m.camera.spin(-0.35)], ["rotate", "Rotate right (E)", func(): m.camera.spin(0.35)],
			["home", "Reset the view", func(): m._reset_camera()]]:
		rail.add_child(_icon_button(c[0], c[1], 48, c[2]))


func set_layer_button(id: String) -> void:
	if layer_btns.has(id):
		layer_btns[id].set_pressed_no_signal(true)


func refresh_levels(n: int, current: int, visible_now: bool) -> void:
	for c in level_box.get_children():
		level_box.remove_child(c)
		c.queue_free()
	if not visible_now or n < 2:
		return
	var g := ButtonGroup.new()
	for lv in n:
		var b := Button.new()
		b.text = "G" if lv == 0 else "L%d" % lv
		b.tooltip_text = "Ground concourse" if lv == 0 else "Level %d concourse" % lv
		b.toggle_mode = true
		b.button_group = g
		b.button_pressed = lv == current
		b.custom_minimum_size = Vector2(48, 32)
		var l := lv
		b.pressed.connect(func(): m._set_level(l))
		level_box.add_child(b)


# --- bottom dock and trays -----------------------------------------------------

func _build_dock() -> void:
	tray = PanelContainer.new()
	tray.visible = false
	tray.resized.connect(func(): _place_dock())
	add_child(tray)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 8)
	tray.add_child(tv)
	tray_title = _label("", 13, C_MUTED)
	tv.add_child(tray_title)
	tray_flow = HFlowContainer.new()
	tray_flow.add_theme_constant_override("h_separation", 8)
	tray_flow.add_theme_constant_override("v_separation", 8)
	tv.add_child(tray_flow)
	dock = PanelContainer.new()
	add_child(dock)
	dock_row = HBoxContainer.new()
	dock_row.add_theme_constant_override("separation", 6)
	dock.add_child(dock_row)
	rebuild_dock()


func rebuild_dock() -> void:
	for c in dock_row.get_children():
		dock_row.remove_child(c)
		c.queue_free()
	category = ""
	tray.visible = false
	var g := ButtonGroup.new()
	g.allow_unpress = true
	for cat in DOCK[m.layer]:
		var b := _dock_button(cat[2], cat[1])
		b.button_group = g
		var cid: String = cat[0]
		b.set_meta("cat", cid)
		b.toggled.connect(func(on: bool): _open_category(cid if on else ""))
		dock_row.add_child(b)
	dock_row.add_child(VSeparator.new())
	var sel := _dock_button("select", "Select")
	sel.pressed.connect(func():
		_close_tray()
		m._set_tool("select"))
	dock_row.add_child(sel)
	var dem := _dock_button("demolish", "Bulldoze")
	dem.pressed.connect(func():
		_close_tray()
		m._set_tool("demolish"))
	dock_row.add_child(dem)
	_place_dock.call_deferred()


func _dock_button(icon: String, label: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(70, 66)
	b.tooltip_text = label
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := Icon.new(icon)
	ic.custom_minimum_size = Vector2(36, 36)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := _label(label, 11, C_MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	b.add_child(v)
	return b


func _place_dock() -> void:
	if dock == null or tray == null:
		return
	var vp := get_viewport_rect().size
	dock.reset_size()
	dock.position = Vector2((vp.x - dock.size.x) / 2.0, vp.y - dock.size.y - 12)
	if tray.visible:
		tray.reset_size()
		var right := vp.x - 12.0
		if card and card.visible:
			right = card.position.x - 10.0   # slide left of the selection card, never under it
		tray.position = Vector2(clampf((vp.x - tray.size.x) / 2.0, 90.0, maxf(90.0, right - tray.size.x)), dock.position.y - tray.size.y - 10)


## The tool was put down (right-click / Esc): back to plain selecting.
func tool_dropped() -> void:
	refresh()
	if tray.visible and category != "looks":
		for k in tiles:
			if is_instance_valid(tiles[k]):
				tiles[k].queue_redraw()


func _close_tray() -> void:
	m.renderer.show_offers = false
	for b in dock_row.get_children():
		if b is Button:
			b.set_pressed_no_signal(false)
	category = ""
	tray.visible = false


func _open_category(cid: String) -> void:
	category = cid
	m.renderer.show_offers = cid == "land"
	tiles.clear()
	for c in tray_flow.get_children():
		tray_flow.remove_child(c)
		c.queue_free()
	if cid == "":
		tray.visible = false
		return
	var cat: Array = []
	for c in DOCK[m.layer]:
		if c[0] == cid:
			cat = c
	tray_title.text = String(cat[1]).to_upper()
	var n: int = maxi(1, (cat[3] as Array).size())
	tray_flow.custom_minimum_size = Vector2(700 if cid == "looks" else mini(n, 8) * 100, 0)
	tray.size = Vector2.ZERO
	if cid == "looks":
		_looks_tray()
	else:
		for id in cat[3]:
			var t := _tile(id)
			tray_flow.add_child(t)
			tiles[id] = t
	tray.visible = true
	result_card.visible = false
	refresh()
	_place_dock.call_deferred()


## A build tile: icon, name and price. Click to pick the tool, or drag it onto the ground.
func _tile(id: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(92, 104)
	p.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.05), 10, Color(1, 1, 1, 0.06), 1, 6))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var ic := Icon.new(id)
	ic.custom_minimum_size = Vector2(80, 64)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var name := _label(_item_name(id), 12)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.clip_text = true
	name.custom_minimum_size = Vector2(80, 0)
	v.add_child(name)
	var price := _label("", 11, C_ACCENT)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(price)
	p.set_meta("icon", ic)
	p.set_meta("price", price)
	p.set_meta("id", id)
	p.gui_input.connect(func(e: InputEvent): _tile_input(p, id, e))
	return p


func _item_name(id: String) -> String:
	if m.config.stand_types.has(id):
		return m.config.stand_type(id).display_name
	if m.config.facility_types.has(id):
		return m.config.facility_type(id).display_name
	if m.config.site_items.has(id):
		return String(m.config.site_items[id]["name"])
	return { "land_N": "Buy north", "land_S": "Buy south", "land_E": "Buy east", "land_W": "Buy west" }.get(id, id.capitalize())


func _tile_input(p: Control, id: String, e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			if not _tile_enabled(id):
				return
			if id.begins_with("land_"):
				m._buy_land(id.substr(5))
				return
			m._set_tool(id)
			drag_id = id
			drag_icon.set_id(id)
		elif drag_id != "":
			var pos := get_global_mouse_position()
			drag_icon.visible = false
			if not _over_ui(pos):
				m._click(m._mouse_tile(pos))
			drag_id = ""
	elif e is InputEventMouseMotion and drag_id != "":
		var pos := get_global_mouse_position()
		drag_icon.visible = not _over_ui(pos)
		drag_icon.position = pos - drag_icon.size / 2.0 + Vector2(0, -34)
		if not _over_ui(pos):
			m._hover_at(pos)


func _tile_enabled(id: String) -> bool:
	if id == "pitch":
		return true
	if m.config.site_items.has(id):
		return true
	if m.config.stand_types.has(id) and not m.game.layout.pitch_placed:
		return false
	if id.begins_with("land_"):
		return m.game.land_cost(id.substr(5)) >= 0.0
	return m.game.is_unlocked(id)


## The "Looks" tray: instant style choices for the whole ground.
func _looks_tray() -> void:
	var groups := [["SKY", Layout.SKIES, func(v: String):
			m.game.set_sky(v)
			m._apply_sky(v), m.game.layout.sky, { "sunny": "Sunny", "cloudy": "Cloudy", "overcast": "Overcast", "golden": "Golden hour" }],
		["SURROUNDINGS", Layout.SURROUNDINGS, func(v: String): m.game.set_surroundings(v), m.game.layout.surroundings, SURROUND_NAMES],
		["FLOODLIGHTS", Layout.FLOODLIGHT_STYLES, func(v: String): m.game.set_floodlights(v), m.game.layout.floodlights,
			{ "slim": "4 slim masts", "slim6": "6 slim masts", "pylons": "Pylons", "roof": "On the roof", "masts": "Side masts" }],
		["PITCH", Layout.PITCH_PATTERNS, func(v: String): m.game.set_pitch_pattern(v), m.game.layout.pitch_pattern,
			{ "stripes": "Stripes", "wide_stripes": "Wide stripes", "checks": "Checks", "diagonal": "Diagonal", "diamonds": "Diamonds", "circles": "Circles", "plain": "Plain" }],
		["GRASS", Layout.GRASS_TYPES, func(v: String): m.game.set_pitch_grass(v), m.game.layout.pitch_grass,
			{ "classic": "Classic", "lush": "Lush", "emerald": "Emerald", "summer": "Summer", "hybrid": "Hybrid dark" }, "grass_"],
		["GOALS", Layout.GOAL_STYLES, func(v: String): m.game.set_goals(v, m.game.layout.net_color, m.game.layout.net_pattern), m.game.layout.goal_style,
			{ "classic": "Classic", "box": "Box", "stanchion": "Stanchion" }, "goal_"],
		["NETS", NET_COLORS + Layout.NET_PATTERNS, func(v: String):
			if v in Layout.NET_PATTERNS:
				m.game.set_goals(m.game.layout.goal_style, m.game.layout.net_color, v)
			else:
				m.game.set_goals(m.game.layout.goal_style, v, m.game.layout.net_pattern), m.game.layout.net_color + "|" + m.game.layout.net_pattern,
			{ "ffffff": "White", "ffd700": "Gold", "d93030": "Red", "2f5fd0": "Blue", "1f1f1f": "Black", "2f9e4f": "Green",
				"none": "No nets", "square": "Square mesh", "hexagon": "Hexagon mesh", "striped": "Striped" }, "net_"],
		["CORNER FLAGS", ["none"] + Layout.FLAG_PATTERNS, func(v: String):
			if v == "none":
				m.game.set_corner_flags({ "on": false })
			else:
				m.game.set_corner_flags({ "on": true, "pattern": v }), "none" if not bool(m.game.layout.corner_flags["on"]) else String(m.game.layout.corner_flags["pattern"]),
			{ "none": "None", "plain": "Plain", "halves": "Halves", "quarters": "Quarters", "stripes": "Stripes", "diagonal": "Diagonal", "badge": "Badge" }, "flag_"],
		["AD BOARDS", Layout.AD_BOARDS, func(v: String): m.game.set_pitchside("ad_boards", v), m.game.layout.ad_boards,
			{ "none": "None", "rainbow": "Mixed ads", "club": "Club colours", "sponsor": "One sponsor", "dark": "Dark" }, "ads_"],
		["DUGOUTS", Layout.DUGOUTS, func(v: String): m.game.set_pitchside("dugout", v), m.game.layout.dugout,
			{ "none": "None", "perspex": "Perspex", "brick": "Brick", "stadium": "Modern" }, "dug_"],
		["BARRIER", Layout.BARRIERS, func(v: String): m.game.set_pitchside("barrier", v), m.game.layout.barrier,
			{ "none": "None", "rail": "Rail", "wall": "Low wall", "fence": "Tall fence", "moat": "Moat & fence" }, "bar_"],
		["SURROUND", Layout.SURROUNDS, func(v: String): m.game.set_pitchside("surround", v), m.game.layout.surround,
			{ "grass": "Grass", "artificial": "Artificial", "track": "Running track", "gravel": "Gravel" }, "sur_"]]
	# two tabs so the tray never outgrows the screen
	var pitch_groups := ["PITCH", "GRASS", "GOALS", "NETS", "CORNER FLAGS", "AD BOARDS", "DUGOUTS", "BARRIER", "SURROUND"]
	var bar := HBoxContainer.new()
	bar.custom_minimum_size = Vector2(680, 0)
	for tdef in [["world", "Sky & surroundings"], ["pitch", "Pitch & pitchside"]]:
		var tid: String = tdef[0]
		var tb := Button.new()
		tb.text = tdef[1]
		tb.toggle_mode = true
		tb.button_pressed = looks_tab == tid
		tb.pressed.connect(func():
			looks_tab = tid
			(func(): _open_category("looks")).call_deferred())
		bar.add_child(tb)
	tray_flow.add_child(bar)
	for gr in groups:
		if (gr[0] in pitch_groups) != (looks_tab == "pitch"):
			continue
		var col := VBoxContainer.new()
		col.add_child(_label(gr[0], 11, C_MUTED))
		var flow := HFlowContainer.new()
		flow.custom_minimum_size = Vector2(minf(gr[1].size(), 9) * 66, 0)
		if gr[0] == "SURROUNDINGS":
			col.custom_minimum_size = Vector2(680, 0)
		for v in gr[1]:
			var val: String = v
			var b := Button.new()
			b.toggle_mode = true
			b.button_pressed = val == gr[3] or val in String(gr[3]).split("|")
			b.custom_minimum_size = Vector2(62, 60)
			b.tooltip_text = gr[4][val]
			var vv := VBoxContainer.new()
			vv.set_anchors_preset(Control.PRESET_FULL_RECT)
			vv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vv.alignment = BoxContainer.ALIGNMENT_CENTER
			var ic := Icon.new((gr[5] if gr.size() > 5 else "") + val)
			ic.custom_minimum_size = Vector2(30, 30)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			vv.add_child(ic)
			var l := _label(gr[4][val], 10, C_MUTED)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vv.add_child(l)
			b.add_child(vv)
			var setter: Callable = gr[2]
			b.pressed.connect(func():
				setter.call(val)
				m._refresh()
				_open_category.call_deferred("looks"))
			flow.add_child(b)
		# full colour pickers next to the swatches
		var lay: Layout = m.game.layout
		if gr[0] == "NETS":
			flow.add_child(_picker("Any net colour", Color.html(lay.net_color), func(c: Color):
				m.game.set_goals(lay.goal_style, c.to_html(false), lay.net_pattern)))
		if gr[0] == "CORNER FLAGS" and bool(lay.corner_flags["on"]):
			var cf := lay.corner_flags
			var club: ClubState = m.game.club
			for k in [["pole", "Pole colour", Color(0.95, 0.85, 0.2)], ["flag", "Flag colour", club.primary_color], ["flag2", "Second flag colour", club.secondary_color]]:
				var key: String = k[0]
				var cur: Color = Color.html(cf[key]) if String(cf[key]) != "" else k[2]
				flow.add_child(_picker(k[1], cur, func(c: Color): m.game.set_corner_flags({ key: c.to_html(false) })))
		col.add_child(flow)
		tray_flow.add_child(col)


# --- selection card ----------------------------------------------------------------

func _build_card() -> void:
	card = PanelContainer.new()
	card.custom_minimum_size = Vector2(300, 0)
	card.visible = false
	add_child(card)
	card_scroll = ScrollContainer.new()
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(card_scroll)
	card_body = VBoxContainer.new()
	card_body.add_theme_constant_override("separation", 8)
	card_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_scroll.add_child(card_body)
	_card_root = card_body


func _card_header(icon: String, title: String, sub: String) -> void:
	var h := HBoxContainer.new()
	var ic := Icon.new(icon)
	ic.custom_minimum_size = Vector2(40, 40)
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_label(title, 16))
	var s := _label(sub, 12, C_MUTED)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.custom_minimum_size = Vector2(200, 0)
	v.add_child(s)
	h.add_child(v)
	h.add_child(_icon_button("cross", "Close (Esc)", 28, func(): m._deselect()))
	card_body.add_child(h)


func _action(label: String, cost: String, cb: Callable, enabled := true, tip := "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(66, 62)
	b.disabled = not enabled
	b.tooltip_text = tip if tip != "" else "%s %s" % [label, cost]
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	var top := _label(label, 13)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(top)
	var bottom := _label(cost, 10, C_ACCENT if enabled else C_MUTED)
	bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(bottom)
	b.add_child(v)
	b.pressed.connect(cb)
	return b


## A colour button that opens the full picker (hue wheel, saturation, value,
## hex). Applies when the picker closes.
func _picker(tip: String, col: Color, cb: Callable, sz := Vector2(62, 60)) -> ColorPickerButton:
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = sz
	cp.edit_alpha = false
	cp.color = col
	cp.tooltip_text = tip + " (any colour)"
	var pk := cp.get_picker()
	pk.picker_shape = ColorPicker.SHAPE_HSV_WHEEL
	pk.presets_visible = false
	cp.popup_closed.connect(func():
		cb.call(cp.color)
		m._refresh()
		if category == "looks" and tray.visible:
			_open_category.call_deferred("looks"))
	return cp


func _swatch(col: Color, tip: String, on: bool, cb: Callable, text := "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(40, 30)
	b.tooltip_text = tip
	b.text = text
	b.add_theme_font_size_override("font_size", 10)
	var sb := _box(col, 7, C_ACCENT if on else Color(1, 1, 1, 0.15), 2 if on else 1, 2)
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color.BLACK if col.get_luminance() > 0.5 else Color.WHITE)
	b.pressed.connect(cb)
	return b


func refresh_card() -> void:
	# never free() here: this often runs from a button inside the card
	card_body = _card_root
	for c in card_body.get_children():
		card_body.remove_child(c)
		c.queue_free()
	var g: Season = m.game
	var sel: int = m.selected
	var fsel: int = m.selected_fac
	if sel >= 0 and sel < g.layout.stands.size():
		_stand_card(sel)
	elif fsel >= 0 and fsel < g.layout.facilities.size():
		_facility_card(fsel)
	else:
		card.visible = false
		return
	card.visible = true
	card.size = Vector2(380, 0)
	_place_card.call_deferred()
	_place_dock.call_deferred()


func _place_card() -> void:
	# fit the card between the top bar and the play panel; scroll the rest
	var room := get_viewport_rect().size.y - 70.0 - 120.0
	var want := _card_root.get_combined_minimum_size()
	card_scroll.custom_minimum_size = Vector2(maxf(want.x, 380.0), minf(want.y, room))
	card.size = Vector2(300, 0)
	card.reset_size()
	card.position = Vector2(get_viewport_rect().size.x - card.size.x - 12, 70)
	_place_dock()


func _stand_card(i: int) -> void:
	var g: Season = m.game
	var s: Stand = g.layout.stands[i]
	var t: StandType = m.config.stand_type(s.type_id)
	var where := "%s corner" % s.side if s.is_corner() else "%s side" % { "N": "North", "S": "South", "E": "East", "W": "West" }[s.side]
	_card_header(s.type_id, "%s stand" % t.display_name, "%s · %s places · %d rows × %d tier%s" % [where, _n(s.capacity(t)), s.depth, s.tiers, "" if s.tiers == 1 else "s"])
	# tabs, so the card stays short: everything else lives on its own tab
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	for tdef in [["build", "Build"], ["look", "Look"], ["signs", "Signs & extras"], ["gear", "Gear"]]:
		var tid: String = tdef[0]
		var tb := Button.new()
		tb.text = tdef[1]
		tb.toggle_mode = true
		tb.button_pressed = card_tab == tid
		tb.add_theme_font_size_override("font_size", 12)
		tb.pressed.connect(func():
			card_tab = tid
			refresh_card.call_deferred())
		bar.add_child(tb)
	_card_root.add_child(bar)
	_tab_boxes = {}
	for tid in ["build", "look", "signs", "gear"]:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		_tab_boxes[tid] = box
	card_body = _tab_boxes["build"]
	var grid := GridContainer.new()
	grid.columns = 4
	var next_len := s.depth + 1 if s.is_corner() else s.length
	grid.add_child(_action("+ Row", _short_money(g.resize_cost(i, s.offset, next_len, s.depth + 1)), func(): m._stand_action("row"), true, "Add a row"))
	grid.add_child(_action("− Row", "", func(): m._stand_action("unrow"), s.depth > 1, "Remove a row (partial refund)"))
	var max_t: int = m.config.integer("layout/max_tiers")
	var tier_open: bool = s.tiers < max_t and g.is_unlocked("tier%d" % (s.tiers + 1))
	var tier_tip := "Add a tier" if tier_open else ("Max tiers" if s.tiers >= max_t else "Unlocks at %s fans" % _n(m.config.unlock_fans("tier%d" % (s.tiers + 1))))
	grid.add_child(_action("+ Tier", _short_money(g.tier_cost(i, s.tiers + 1)) if tier_open else "locked", func(): m._stand_action("tier"), tier_open, tier_tip))
	grid.add_child(_action("− Tier", "", func(): m._stand_action("untier"), s.tiers > 1, "Remove the top tier"))
	if not s.is_corner():
		var side_len := Stand.side_length(s.side, g.layout.pitch)
		var new_off: int = maxi(0, s.offset - m.EXTEND_STEP)
		var new_len: int = mini(side_len - s.offset, s.length + m.EXTEND_STEP)
		grid.add_child(_action("◀ Extend", _short_money(g.resize_cost(i, new_off, s.length + s.offset - new_off, s.depth)), func(): m._stand_action("left"), new_off != s.offset))
		grid.add_child(_action("Extend ▶", _short_money(g.resize_cost(i, s.offset, new_len, s.depth)), func(): m._stand_action("right"), new_len != s.length))
	card_body.add_child(grid)
	card_body = _tab_boxes["look"]
	var roof_cost: float = s.capacity(m.config.stand_type(s.type_id)) * m.config.num("layout/roof_cost_per_place")
	card_body.add_child(_label("ROOF", 11, C_MUTED))
	if s.roof == "open":
		var hint := _label("A roof costs %s and keeps fans coming in rain and snow." % Season.money(roof_cost), 11, C_ACCENT)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(240, 0)
		card_body.add_child(hint)
	var roofs := HFlowContainer.new()
	for r in Stand.ROOF_STYLES:
		var rr: String = r
		var tip: String = ROOF_NAMES[rr] + " roof"
		if s.roof == "open" and rr != "open":
			tip += " · %s" % Season.money(roof_cost)
		roofs.add_child(_swatch(Color(0.25, 0.28, 0.33) if rr != s.roof else Color(C_ACCENT, 0.9), tip, rr == s.roof, func(): m._restyle(rr, ""), ROOF_NAMES[rr]))
	card_body.add_child(roofs)
	card_body.add_child(_label("WALLS & SEATS", 11, C_MUTED))
	var looks := HBoxContainer.new()
	for f in Stand.FACADES:
		var ff: String = f
		var col: Color = m.game.club.primary_color if ff == "club" else FACADE_COLORS[ff]
		looks.add_child(_swatch(col, FACADE_NAMES[ff] + " walls", ff == s.facade, func():
			m._report_err(m.game.set_facade(i, ff))
			m._refresh()))
	var seat := ColorPickerButton.new()
	seat.custom_minimum_size = Vector2(40, 30)
	seat.tooltip_text = "Seat colour"
	seat.edit_alpha = false
	seat.color = m.renderer.seat_color(s)
	seat.popup_closed.connect(func(): m._restyle("", seat.color.to_html(false)))
	looks.add_child(seat)
	card_body.add_child(looks)
	card_body = _tab_boxes["signs"]
	_extras_section(i, s)
	card_body = _tab_boxes["look"]
	if s.is_corner():
		var shp := HBoxContainer.new()
		for sh in Stand.CORNER_SHAPES:
			var shh: String = sh
			shp.add_child(_swatch(Color(0.25, 0.28, 0.33) if shh != s.shape else Color(C_ACCENT, 0.9), shh.capitalize() + " corner", shh == s.shape, func():
				m._report_err(m.game.set_corner_shape(i, shh))
				m._refresh(), shh.capitalize()))
		card_body.add_child(shp)
	# mounted gear
	var gear := VBoxContainer.new()
	var stand_tiles: Dictionary = g.layout.stand_tile_map()
	for fi in g.layout.facilities.size():
		var f: Facility = g.layout.facilities[fi]
		var ft: FacilityType = m.config.facility_type(f.type_id)
		if ft.layer == "bowl" and stand_tiles.get(f.pos, -1) == i:
			var idx := fi
			var row := HFlowContainer.new()
			var b := _icon_button(ft.id, "Remove the %s" % ft.display_name.to_lower(), 34, func():
				m._report_err(m.game.demolish_facility(idx))
				m._refresh())
			row.add_child(b)
			if ft.styles.size() > 1:
				var cur: String = f.style if f.style != "" else ft.styles[0]
				for stv in ft.styles:
					var sv: String = stv
					row.add_child(_swatch(Color(C_ACCENT, 0.9) if sv == cur else Color(0.25, 0.28, 0.33), "Style", sv == cur, func():
						m._report_err(m.game.restyle_facility(idx, sv))
						m._refresh(), sv.capitalize().replace("_", " ")))
			for key in ft.options:
				var kk: String = key
				row.add_child(_label(GEAR_OPTION_NAMES.get(kk, kk.capitalize()), 10, C_MUTED))
				for v in ft.options[kk]:
					var vv: String = v
					var on: bool = f.opt(ft, kk) == vv
					row.add_child(_swatch(Color(C_ACCENT, 0.9) if on else Color(0.25, 0.28, 0.33), "%s: %s" % [kk, vv], on, func():
						m._report_err(m.game.set_facility_option(idx, kk, vv))
						m._refresh(), vv.capitalize()))
			gear.add_child(row)
	card_body = _tab_boxes["gear"]
	if gear.get_child_count() > 0:
		card_body.add_child(_label("MOUNTED GEAR (click an icon to remove it)", 11, C_MUTED))
		card_body.add_child(gear)
	else:
		card_body.add_child(_label("Nothing mounted yet. Add video boards, scoreboards\nand speakers from \"In the bowl\".", 12, C_MUTED))
	card_body = _tab_boxes["build"]
	var bot := HBoxContainer.new()
	bot.alignment = BoxContainer.ALIGNMENT_END
	var dem := _icon_button("trashcan", "Demolish this stand (%d%% refund)" % roundi(100 * m.config.num("season/demolish_refund_fraction")), 36, func(): m._stand_action("demolish"))
	dem.get_child(0).tint = C_BAD
	dem.get_child(0).queue_redraw()
	bot.add_child(dem)
	card_body.add_child(bot)
	card_body = _card_root
	card_body.add_child(_tab_boxes[card_tab])


## The stand's switchable add-ons: its name sign (text, place, size, colour,
## lit at night) and toggles for flags, an LED strip, a clock and banners.
func _extras_section(i: int, s: Stand) -> void:
	var set_extra := func(key: String, settings: Dictionary) -> void:
		m._report_err(m.game.set_stand_extra(i, key, settings))
		m._refresh()
	card_body.add_child(_label("NAME SIGN", 11, C_MUTED))
	var nm := s.extra("name")
	var on: bool = nm["on"]
	var row := HBoxContainer.new()
	row.add_child(_swatch(Color(C_ACCENT, 0.9) if on else Color(0.25, 0.28, 0.33), "Show the name", on, func(): set_extra.call("name", { "on": not on }), "On" if on else "Off"))
	var txt := LineEdit.new()
	txt.custom_minimum_size = Vector2(150, 30)
	txt.text = nm["text"]
	txt.placeholder_text = "(the stand's name)"
	txt.max_length = 32
	txt.tooltip_text = "Leave empty for the stand's own name"
	txt.text_submitted.connect(func(t: String): set_extra.call("name", { "text": t.strip_edges() }))
	txt.focus_exited.connect(func():
		if txt.text.strip_edges() != String(s.extra("name")["text"]):
			set_extra.call("name", { "text": txt.text.strip_edges() }))
	row.add_child(txt)
	card_body.add_child(row)
	if on:
		var opts := HBoxContainer.new()
		for w in (["roof"] if s.is_corner() else Stand.NAME_WHERE):
			var ww: String = w
			opts.add_child(_swatch(Color(C_ACCENT, 0.9) if nm["where"] == ww else Color(0.25, 0.28, 0.33), "On the " + ww, nm["where"] == ww,
				func(): set_extra.call("name", { "where": ww }), "Roof" if ww == "roof" else "Wall"))
		for z in Stand.NAME_SIZES:
			var zz: String = z
			opts.add_child(_swatch(Color(C_ACCENT, 0.9) if nm["size"] == zz else Color(0.25, 0.28, 0.33), "Size " + zz, nm["size"] == zz,
				func(): set_extra.call("name", { "size": zz }), zz))
		var lit: bool = nm["lit"]
		opts.add_child(_swatch(Color(1.0, 0.85, 0.4) if lit else Color(0.25, 0.28, 0.33), "Lit at night", lit, func(): set_extra.call("name", { "lit": not lit }), "Lit"))
		card_body.add_child(opts)
		var cols := HBoxContainer.new()
		var club: ClubState = m.game.club
		for c in [["", club.secondary_color, "Club trim colour"], [club.primary_color.to_html(false), club.primary_color, "Club colour"],
				["ffffff", Color.WHITE, "White"], ["e8c04a", Color(0.91, 0.75, 0.29), "Gold"], ["1c1c1c", Color(0.11, 0.11, 0.11), "Black"]]:
			var hx: String = c[0]
			cols.add_child(_swatch(c[1], c[2], String(nm["color"]) == hx, func(): set_extra.call("name", { "color": hx })))
		var ncur: Color = Color.html(nm["color"]) if String(nm["color"]) != "" else club.secondary_color
		cols.add_child(_picker("Name colour", ncur, func(col: Color): set_extra.call("name", { "color": col.to_html(false) }), Vector2(40, 30)))
		card_body.add_child(cols)
	# the club crest on the roof
	var lg := s.extra("logo")
	var lon: bool = lg["on"]
	card_body.add_child(_label("ROOF CREST", 11, C_MUTED))
	var lrow := HBoxContainer.new()
	lrow.add_child(_swatch(Color(C_ACCENT, 0.9) if lon else Color(0.25, 0.28, 0.33), "Show the club crest on the roof", lon, func(): set_extra.call("logo", { "on": not lon }), "On" if lon else "Off"))
	if lon:
		for w in Stand.LOGO_WHERE:
			var ww: String = w
			lrow.add_child(_swatch(Color(C_ACCENT, 0.9) if lg["where"] == ww else Color(0.25, 0.28, 0.33), "Crest " + ww, lg["where"] == ww,
				func(): set_extra.call("logo", { "where": ww }), { "centre": "Mid", "left": "Left", "right": "Right" }[ww]))
		for z in Stand.NAME_SIZES:
			var zz: String = z
			lrow.add_child(_swatch(Color(C_ACCENT, 0.9) if lg["size"] == zz else Color(0.25, 0.28, 0.33), "Size " + zz, lg["size"] == zz,
				func(): set_extra.call("logo", { "size": zz }), zz))
		var llit: bool = lg["lit"]
		lrow.add_child(_swatch(Color(1.0, 0.85, 0.4) if llit else Color(0.25, 0.28, 0.33), "Lit at night", llit, func(): set_extra.call("logo", { "lit": not llit }), "Lit"))
	card_body.add_child(lrow)
	# seat patterns (shown on the Look tab)
	var signs_box := card_body
	if _tab_boxes.has("look"):
		card_body = _tab_boxes["look"]
	if m.renderer.has_seats(s):
		var sp := s.extra("seats")
		card_body.add_child(_label("SEAT PATTERN", 11, C_MUTED))
		var prow := HFlowContainer.new()
		for pt in Stand.SEAT_PATTERNS:
			var pp: String = pt
			prow.add_child(_swatch(Color(C_ACCENT, 0.9) if sp["pattern"] == pp else Color(0.25, 0.28, 0.33), SEAT_PATTERN_TIPS[pp], sp["pattern"] == pp,
				func(): set_extra.call("seats", { "pattern": pp }), SEAT_PATTERN_NAMES[pp]))
		card_body.add_child(prow)
		if sp["pattern"] != "plain":
			var crow := HBoxContainer.new()
			var club: ClubState = m.game.club
			for c in [["", Color(0.4, 0.4, 0.42), "Auto (club colours)"], ["ffffff", Color.WHITE, "White"], [club.secondary_color.to_html(false), club.secondary_color, "Club trim"],
					[club.primary_color.to_html(false), club.primary_color, "Club colour"], ["e8c04a", Color(0.91, 0.75, 0.29), "Gold"], ["1c1c1c", Color(0.11, 0.11, 0.11), "Black"]]:
				var hx: String = c[0]
				crow.add_child(_swatch(c[1], "Second colour: " + c[2], String(sp["color2"]) == hx, func(): set_extra.call("seats", { "color2": hx }), "A" if hx == "" else ""))
			var scur: Color = Color.html(sp["color2"]) if String(sp["color2"]) != "" else club.secondary_color
			crow.add_child(_picker("Second seat colour", scur, func(col: Color): set_extra.call("seats", { "color2": col.to_html(false) }), Vector2(40, 30)))
			if sp["pattern"] == "text":
				var st := LineEdit.new()
				st.custom_minimum_size = Vector2(110, 30)
				st.text = sp["text"]
				st.placeholder_text = "(club name)"
				st.max_length = 20
				st.text_submitted.connect(func(t: String): set_extra.call("seats", { "text": t.strip_edges() }))
				crow.add_child(st)
			card_body.add_child(crow)
	card_body = signs_box
	card_body.add_child(_label("EXTRAS", 11, C_MUTED))
	var ex := HBoxContainer.new()
	for k in EXTRA_NAMES:
		var kk: String = k
		if s.is_corner() and kk == "banners":
			continue
		var eon: bool = s.extra(kk)["on"]
		ex.add_child(_swatch(Color(C_ACCENT, 0.9) if eon else Color(0.25, 0.28, 0.33), EXTRA_NAMES[kk][1], eon, func(): set_extra.call(kk, { "on": not eon }), EXTRA_NAMES[kk][0]))
	card_body.add_child(ex)


func _facility_card(i: int) -> void:
	var f: Facility = m.game.layout.facilities[i]
	var ft: FacilityType = m.config.facility_type(f.type_id)
	_card_header(ft.id, ft.display_name, m._facility_blurb(ft))
	if ft.styles.size() > 1:
		card_body.add_child(_label("STYLE", 11, C_MUTED))
		var row := HBoxContainer.new()
		var cur: String = f.style if f.style != "" else ft.styles[0]
		for st in ft.styles:
			var sv: String = st
			row.add_child(_swatch(Color(0.25, 0.28, 0.33) if sv != cur else Color(C_ACCENT, 0.9), sv.capitalize(), sv == cur, func():
				m._report_err(m.game.restyle_facility(i, sv))
				m._refresh(), sv.capitalize().left(9)))
		card_body.add_child(row)
	var bot := HBoxContainer.new()
	bot.alignment = BoxContainer.ALIGNMENT_END
	var dem := _icon_button("trashcan", "Demolish", 36, func():
		m._report_err(m.game.demolish_facility(i))
		m._deselect())
	dem.get_child(0).tint = C_BAD
	dem.get_child(0).queue_redraw()
	bot.add_child(dem)
	card_body.add_child(bot)


# --- play button and match result --------------------------------------------------

func _build_play() -> void:
	play_panel = PanelContainer.new()
	add_child(play_panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	play_panel.add_child(h)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	stat["next_label"] = _label("NEXT MATCH", 10, C_MUTED)
	v.add_child(stat["next_label"])
	play_sub = _label("", 15)
	v.add_child(play_sub)
	play_tags = HBoxContainer.new()
	v.add_child(play_tags)
	h.add_child(v)
	play_btn = Button.new()
	play_btn.custom_minimum_size = Vector2(150, 56)
	play_btn.text = "PLAY MATCH ▶"
	play_btn.add_theme_font_size_override("font_size", 16)
	play_btn.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02))
	play_btn.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.02))
	play_btn.add_theme_color_override("font_pressed_color", Color(0.1, 0.08, 0.02))
	play_btn.add_theme_stylebox_override("normal", _box(C_ACCENT, 12, Color(1, 1, 1, 0.5), 2, 6))
	play_btn.add_theme_stylebox_override("hover", _box(C_ACCENT.lightened(0.15), 12, Color.WHITE, 2, 6))
	play_btn.add_theme_stylebox_override("pressed", _box(C_ACCENT.darkened(0.15), 12, Color.WHITE, 2, 6))
	play_btn.pressed.connect(func(): m._on_play())
	h.add_child(play_btn)


func _build_result_card() -> void:
	result_card = PanelContainer.new()
	result_card.custom_minimum_size = Vector2(280, 0)
	result_card.visible = false
	result_card.resized.connect(func(): _place_corner())
	add_child(result_card)
	result_body = VBoxContainer.new()
	result_body.add_theme_constant_override("separation", 4)
	result_card.add_child(result_body)


func _row(icon: String, text: String, col := C_TEXT, size := 13) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var ic := Icon.new(icon)
	ic.custom_minimum_size = Vector2(18, 18)
	h.add_child(ic)
	var l := _label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h


func refresh_result() -> void:
	for c in result_body.get_children():
		result_body.remove_child(c)
		c.queue_free()
	var g: Season = m.game
	var r: MatchdayReport = m.last_report
	var lg: League = g.league
	if g.is_over():
		var sr := g.summary()
		var pos := g.position()
		result_body.add_child(_label("SEASON %d COMPLETE" % sr.season_number, 12, C_MUTED))
		result_body.add_child(_label("Finished %s of %d  ·  %d pts" % [LeagueWindow._ord(pos), lg.teams.size(), sr.points], 18))
		result_body.add_child(_label("W%d  D%d  L%d   goals %d–%d" % [sr.wins, sr.draws, sr.losses, sr.goals_for, sr.goals_against], 13, C_MUTED))
		if g.promotion_earned():
			result_body.add_child(_row("trophy", "Promoted to the %s!" % m.config.division(g.club.division + 1)["name"], C_ACCENT, 14))
		elif g.relegated():
			result_body.add_child(_row("information", "Relegated to the %s. Build back stronger." % m.config.division(g.club.division - 1)["name"], C_BAD, 14))
		elif g.club.division >= m.config.divisions.size() - 1:
			result_body.add_child(_row("trophy", "CHAMPIONS!" if pos == 1 else "Top division: finish 1st to be champions", C_ACCENT if pos == 1 else C_MUTED, 14))
		else:
			result_body.add_child(_row("information", "Top %d go up. Spend more on the squad next season?" % m.game.promoted_places(), C_MUTED, 12))
		var t := lg.table()
		for i in mini(3, t.size()):
			result_body.add_child(_label("%d. %s  %d pts" % [i + 1, t[i]["name"], t[i]["pts"]], 12, C_ACCENT if t[i]["team"] == 0 else C_TEXT))
		result_body.add_child(_row("fans", "Fans %s → %s" % [_n(sr.fanbase_start), _n(sr.fanbase_end)]))
		var prof := sr.profit()
		result_body.add_child(_row("coin", "Season profit %s" % Season.money(prof), C_GOOD if prof >= 0.0 else C_BAD))
		var bt := Button.new()
		bt.text = "Final table"
		bt.pressed.connect(func(): open_league("table"))
		result_body.add_child(bt)
	elif r != null:
		var fx_home: bool = r.home
		var us: String = g.club.club_name
		var head := HBoxContainer.new()
		var res := _label({ "W": "WIN", "D": "DRAW", "L": "LOSS" }[r.result], 13, { "W": C_GOOD, "D": C_TEXT, "L": C_BAD }[r.result])
		head.add_child(res)
		var line := ("  %s %d – %d %s" % [us, r.home_goals, r.away_goals, r.opponent]) if fx_home else ("  %s %d – %d %s" % [r.opponent, r.away_goals, r.home_goals, us])
		var score := _label(line, 15)
		score.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(score)
		head.add_child(_icon_button("cross", "Hide", 24, func(): result_card.visible = false))
		result_body.add_child(head)
		result_body.add_child(_label("Matchday %d · %s" % [r.round + 1, "at home" if fx_home else "away"], 11, C_MUTED))
		# goals: minute and scorer, ours in the club colour
		var ev: Dictionary = r.events
		for gl in ev.get("goals", []):
			var ours: bool = gl["side"] == "us"
			result_body.add_child(_label("%d'  %s  (%s)" % [gl["min"], gl["name"], us if ours else r.opponent], 12, C_GOOD if ours else C_MUTED))
		if ev.has("shots"):
			result_body.add_child(_label("Shots %d–%d   ·   Possession %d%%–%d%%" % [ev["shots"][0], ev["shots"][1], ev["possession"][0], ev["possession"][1]], 11, C_MUTED))
		# the league after this round
		var pos := g.position()
		var prev := _position_before(g)
		var move := ""
		if prev > 0 and prev != pos:
			move = "  (%s%d)" % ["▲" if pos < prev else "▼", absi(prev - pos)]
		result_body.add_child(_row("trophy", "Now %s of %d%s · %d pts" % [LeagueWindow._ord(pos), lg.teams.size(), move, g.summary().points], C_ACCENT, 13))
		if fx_home:
			result_body.add_child(_row("fans", "%s / %s crowd" % [_n(r.attendance), _n(r.capacity)]))
		# money for this match: in, out, profit
		var inc := float(r.revenue["total"])
		var out := float(r.costs["total"])
		result_body.add_child(_row("coin", "In %s  ·  Out %s  ·  %s %s" % [_short_money(inc), _short_money(out), "Profit" if inc >= out else "Loss", _short_money(absf(inc - out))],
			C_GOOD if inc >= out else C_BAD, 12))
		if g.club.administration:
			result_body.add_child(_row("coin", "In administration: points deducted, wages capped", C_BAD, 12))
		elif g.club.cash < 0.0:
			result_body.add_child(_row("coin", "In debt: paying %s interest a match" % _short_money(float(r.costs.get("interest", 0.0))), C_BAD, 12))
		# the one thing worth doing next
		if fx_home and r.transport_turned_away > 0:
			result_body.add_child(_row("transport_cat", "%s couldn't get here" % _n(r.transport_turned_away), C_BAD, 12))
		var btns := HBoxContainer.new()
		for bdef in [["Other results", "results"], ["Table", "table"]]:
			var bt := Button.new()
			bt.text = bdef[0]
			bt.add_theme_font_size_override("font_size", 12)
			var tabid: String = bdef[1]
			bt.pressed.connect(func(): open_league(tabid))
			btns.add_child(bt)
		var more := Button.new()
		more.text = "Match report"
		more.add_theme_font_size_override("font_size", 12)
		more.pressed.connect(func(): _toggle_window("report"))
		btns.add_child(more)
		result_body.add_child(btns)
	else:
		result_card.visible = false
		return
	result_card.visible = not tray.visible and not card.visible
	_place_corner.call_deferred()


## League position before the latest round (0 if none).
func _position_before(g: Season) -> int:
	var lg: League = g.league
	var n := lg.played()
	if n < 2:
		return 0
	var saved: Array = lg.results[n - 1]
	lg.results[n - 1] = []
	var p := lg.position()
	lg.results[n - 1] = saved
	return p


func _place_corner() -> void:
	if play_panel == null or result_card == null:
		return
	var vp := get_viewport_rect().size
	play_panel.reset_size()
	play_panel.position = Vector2(vp.x - play_panel.size.x - 12, vp.y - play_panel.size.y - 12)
	result_card.reset_size()
	result_card.position = Vector2(vp.x - result_card.size.x - 12, play_panel.position.y - result_card.size.y - 10)


# --- toast and hover tip ----------------------------------------------------------

func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.modulate.a = 0.0
	add_child(toast_panel)
	toast_label = _label("", 14)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_panel.add_child(toast_label)


func toast(text: String) -> void:
	if text == "":
		return
	toast_label.text = text
	toast_panel.reset_size()
	var vp := get_viewport_rect().size
	toast_panel.position = Vector2((vp.x - toast_panel.size.x) / 2.0, 66)
	if toast_tween:
		toast_tween.kill()
	toast_panel.modulate.a = 1.0
	toast_tween = create_tween()
	toast_tween.tween_interval(3.0)
	toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.6)


func hover_tip(text: String) -> void:
	hover_label.text = text
	hover_label.visible = text != ""
	hover_label.position = get_global_mouse_position() + Vector2(18, 14)


# --- windows -------------------------------------------------------------------------

var league_tab := "table"


## Open (or reopen) the league window on a tab.
func open_league(p_tab := "table") -> void:
	league_tab = p_tab
	if windows.has("league") and is_instance_valid(windows["league"]):
		_toggle_window("league")
	_toggle_window("league")


func _toggle_window(id: String) -> void:
	if windows.has(id) and is_instance_valid(windows[id]):
		windows[id].queue_free()
		windows.erase(id)
		return
	for k in windows.keys():
		if is_instance_valid(windows[k]):
			windows[k].queue_free()
	windows.clear()
	var w := PanelContainer.new()
	add_child(w)
	windows[id] = w
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	w.add_child(v)
	var head := HBoxContainer.new()
	var title := _label({ "club": "CLUB", "settings": "SETTINGS", "report": "MATCH REPORT", "history": "HISTORY", "league": "LEAGUE & SQUAD" }[id], 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_icon_button("cross", "Close", 28, func(): _toggle_window(id)))
	v.add_child(head)
	match id:
		"club": _club_window(v)
		"settings": _settings_window(v)
		"report": _report_window(v)
		"history": v.add_child(HistoryWindow.new(m.game))
		"league": v.add_child(LeagueWindow.new(m, league_tab))
	w.reset_size()
	var vp := get_viewport_rect().size
	w.position = (vp - w.size) / 2.0


func _club_window(v: VBoxContainer) -> void:
	var g: Season = m.game
	v.add_child(ClubSetup.new(self, false))
	v.add_child(HSeparator.new())
	v.add_child(_label("TICKET PRICES", 11, C_MUTED))
	var pg := GridContainer.new()
	pg.columns = 4
	pg.add_theme_constant_override("h_separation", 8)
	for id in m.config.stand_type_ids():
		var tid: String = id
		if m.config.stand_type(tid).demand_pool != tid:
			continue   # priced with the type it shares fans with
		var ic := Icon.new(tid)
		ic.custom_minimum_size = Vector2(26, 26)
		pg.add_child(ic)
		var l := _label("%s  £%d" % [m.config.stand_type(tid).display_name, roundi(g.club.price(tid))], 13)
		l.custom_minimum_size = Vector2(170, 0)
		pg.add_child(l)
		for d in [-1, 1]:
			var dir: int = d
			var b := _icon_button("minus" if d < 0 else "plus", "Cheaper" if d < 0 else "Dearer", 28, func():
				m._change_price(tid, dir)
				l.text = "%s  £%d" % [m.config.stand_type(tid).display_name, roundi(m.game.club.price(tid))])
			pg.add_child(b)
	v.add_child(pg)
	v.add_child(_label("NAMING RIGHTS", 11, C_MUTED))
	var sp := OptionButton.new()
	var ids := [""]
	sp.add_item("No sponsor")
	for sid in m.config.sponsors:
		var d: Dictionary = m.config.sponsors[sid]
		ids.append(sid)
		sp.add_item("%s %s  (%s/match)" % [d["name"], d["suffix"], Season.money(g.sponsor_fee(sid))])
	sp.select(maxi(0, ids.find(g.club.sponsor)))
	sp.disabled = not g.is_unlocked("naming_rights")
	sp.tooltip_text = "" if not sp.disabled else "Unlocks at %s fans" % _n(m.config.unlock_fans("naming_rights"))
	sp.item_selected.connect(func(k: int):
		m._report_err(m.game.set_sponsor(ids[k]))
		m._refresh())
	v.add_child(sp)


func _settings_window(v: VBoxContainer) -> void:
	for o in [["Roofs", true, func(on: bool): m.renderer.show_roofs = on], ["Crowd sound", not m.crowd_audio.muted, func(on: bool): m.crowd_audio.muted = not on]]:
		var cb := CheckButton.new()
		cb.text = o[0]
		cb.button_pressed = o[1]
		cb.toggled.connect(o[2])
		v.add_child(cb)
	v.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for b in [["save", "Save", func(): m._save_slot()], ["import", "Load", func(): m._load_slot()], ["plus", "New game", func(): m._new_game_clicked()]]:
		var btn := Button.new()
		btn.text = "  " + b[1]
		btn.icon = Icon.kenney(b[0])
		btn.expand_icon = false
		btn.add_theme_constant_override("icon_max_width", 20)
		btn.custom_minimum_size = Vector2(110, 38)
		btn.pressed.connect(b[2])
		row.add_child(btn)
	v.add_child(row)
	v.add_child(_label("The game autosaves after every change.", 11, C_MUTED))
	v.add_child(HSeparator.new())
	var help := _label("Wheel: zoom to cursor · Left-drag: move the map · Right-drag or Q/E: rotate · WASD: move\nStands: pick a type, then drag out from the touchline (along = length, outward = rows)\nRight-click or Esc: put the tool down", 12, C_MUTED)
	v.add_child(help)


func _report_window(v: VBoxContainer) -> void:
	var r: MatchdayReport = m.last_report
	var t := RichTextLabel.new()
	t.custom_minimum_size = Vector2(620, 420)
	t.add_theme_font_size_override("normal_font_size", 12)
	t.add_theme_font_override("normal_font", SystemFont.new())
	t.text = r.to_text() if r != null else "No match yet."
	v.add_child(t)


# --- matchday banner ---------------------------------------------------------------

func _build_matchday() -> void:
	md_panel = PanelContainer.new()
	md_panel.custom_minimum_size = Vector2(560, 0)
	md_panel.visible = false
	add_child(md_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	md_panel.add_child(v)
	md_title = _label("", 13, C_MUTED)
	md_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(md_title)
	md_score = _label("", 30)
	md_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(md_score)
	md_info = _label("", 14, C_TEXT)
	md_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(md_info)
	var nrow := HBoxContainer.new()
	var ni := Icon.new("audioOn")
	ni.custom_minimum_size = Vector2(22, 22)
	nrow.add_child(ni)
	md_noise = ProgressBar.new()
	md_noise.custom_minimum_size = Vector2(460, 14)
	md_noise.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	md_noise.show_percentage = false
	md_noise.max_value = 100
	nrow.add_child(md_noise)
	v.add_child(nrow)
	md_milestone = _label("", 15, C_ACCENT)
	md_milestone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	md_milestone.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	md_milestone.custom_minimum_size = Vector2(520, 0)
	v.add_child(md_milestone)
	var ok := Button.new()
	ok.text = "Back to building"
	ok.custom_minimum_size = Vector2(0, 36)
	ok.pressed.connect(func(): m._matchday_end())
	v.add_child(ok)


func show_matchday(r: MatchdayReport) -> void:
	var c: ClubState = m.game.club
	var bits := PackedStringArray()
	if r.big_match:
		bits.append("BIG MATCH")
	bits.append("Evening" if r.evening else "Afternoon")
	bits.append({ "clear": "Clear", "rain": "Rain", "snow": "Snow" }.get(r.weather, ""))
	bits.append(m.config.division(r.division)["name"])
	md_title.text = "  ·  ".join(bits)
	md_score.text = "%s  %d – %d  %s" % [c.club_name.to_upper(), r.home_goals, r.away_goals, r.opponent.to_upper()]
	md_score.add_theme_color_override("font_color", { "W": C_GOOD, "D": C_TEXT, "L": C_BAD }[r.result])
	md_info.text = "%s crowd  ·  %s takings  ·  fans %+.1f%%" % [_n(r.attendance), Season.money(r.revenue["total"]), 100.0 * r.fanbase_growth["total"]]
	var ms := PackedStringArray()
	for mm in r.milestones:
		var names := PackedStringArray()
		for id in mm["unlocks"]:
			names.append(_item_name(id) if (m.config.facility_types.has(id) or m.config.stand_types.has(id)) else { "tier2": "Second tiers", "tier3": "Third tiers", "naming_rights": "Naming rights" }.get(id, id))
		ms.append("★ %s  (%s fans)  +%s%s" % [mm["name"], _n(mm["fans"]), Season.money(mm["reward"]), "" if names.is_empty() else "\nUnlocked: " + ", ".join(names)])
	md_milestone.text = "\n".join(ms)
	md_milestone.visible = not ms.is_empty()
	md_noise.value = 0
	md_panel.visible = true
	md_panel.reset_size()
	md_panel.position = Vector2((get_viewport_rect().size.x - md_panel.size.x) / 2.0, 70)
	create_tween().tween_property(md_noise, "value", r.atmosphere, 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func hide_matchday() -> void:
	md_panel.visible = false


# --- first-time guide ----------------------------------------------------------------
# Three steps with a bobbing arrow: build a stand, edit it, play a match.
# Shown on a fresh game until finished or skipped, once per install.

const GUIDE_FILE := "user://settings.cfg"
const GUIDE := [
	["Open Stands and place your pitch on the plot", "dock"],
	["Pick a stand type, then drag out from the touchline", "dock"],
	["Use the card to add a row, change the roof or colours", "stand"],
	["Press Play to host your first match", "play"],
	["Fans need to get here: put a car park by the street (Transport)", "transport"],
	["Pave a path from the car park to your stand (Roads & paths)", "site"],
]

var guide_step := -1
var guide_panel: PanelContainer
var guide_label: Label
var guide_count: Label
var guide_arrow: Icon
var _guide_t := 0.0
var _guide_sig := 0
var guide_next: Button


func _build_guide() -> void:
	guide_panel = PanelContainer.new()
	guide_panel.visible = false
	var sb := _box(Color(0.1, 0.12, 0.16, 0.95), 12, C_ACCENT, 2, 12)
	guide_panel.add_theme_stylebox_override("panel", sb)
	add_child(guide_panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	guide_panel.add_child(h)
	guide_count = _label("", 12, C_ACCENT)
	h.add_child(guide_count)
	guide_label = _label("", 15)
	h.add_child(guide_label)
	guide_next = Button.new()
	guide_next.text = "Next"
	guide_next.add_theme_font_size_override("font_size", 12)
	guide_next.pressed.connect(func():
		guide_step += 1
		_guide_update())
	h.add_child(guide_next)
	var skip := Button.new()
	skip.text = "Skip tips"
	skip.add_theme_font_size_override("font_size", 12)
	skip.pressed.connect(func(): _guide_finish())
	h.add_child(skip)
	guide_arrow = Icon.new("arrowDown", C_ACCENT)
	guide_arrow.size = Vector2(44, 44)
	guide_arrow.visible = false
	add_child(guide_arrow)
	var cfg := ConfigFile.new()
	var done := cfg.load(GUIDE_FILE) == OK and bool(cfg.get_value("guide", "done", false))
	if not done and m.game.layout.stands.is_empty() and m.game.season_number == 1 and m.game.reports.is_empty():
		guide_step = 0


func _guide_finish() -> void:
	guide_step = -1
	guide_panel.visible = false
	guide_arrow.visible = false
	var cfg := ConfigFile.new()
	cfg.load(GUIDE_FILE)
	cfg.set_value("guide", "done", true)
	cfg.save(GUIDE_FILE)


func _guide_update() -> void:
	if guide_step < 0:
		return
	if new_game_screen and is_instance_valid(new_game_screen) and not new_game_screen.is_queued_for_deletion():
		guide_panel.visible = false
		guide_arrow.visible = false
		return
	var g: Season = m.game
	if guide_step == 0 and g.layout.pitch_placed:
		guide_step = 1
	if guide_step == 1 and not g.layout.stands.is_empty():
		guide_step = 2
		_guide_sig = hash(g.layout.to_dict())
	if guide_step == 2 and hash(g.layout.to_dict()) != _guide_sig:
		guide_step = 3
	if guide_step >= GUIDE.size():
		_guide_finish()
		return
	if guide_step == 3 and (not g.reports.is_empty() or g.season_number > 1):
		guide_step = 4
	var has_link := false
	for f in g.layout.facilities:
		var ft: FacilityType = m.config.facility_type(f.type_id)
		if ft.layer == "outside" and ft.capacity > 0.0:
			has_link = true
	if guide_step == 4 and has_link:
		guide_step = 5
	if guide_step == 5:
		for t in g.layout.site:
			if g.layout.site_group(t, m.config) == "path":
				_guide_finish()
				toast("Nice! Keep building: bigger crowds, more money, more stadium.")
				return
	if guide_step >= GUIDE.size():
		_guide_finish()
		return
	guide_label.text = GUIDE[guide_step][0]
	guide_count.text = "%d/%d" % [guide_step + 1, GUIDE.size()]
	guide_next.visible = guide_step == 2
	guide_panel.visible = true
	guide_panel.reset_size()
	var vp := get_viewport_rect().size
	guide_panel.position = Vector2((vp.x - guide_panel.size.x) / 2.0, 112)


func _guide_target() -> Vector2:
	match GUIDE[guide_step][1]:
		"dock":
			if tray.visible:
				return Vector2(tray.get_global_rect().get_center().x, tray.global_position.y - 4)
			var b: Control = dock_row.get_child(0)
			return Vector2(b.get_global_rect().get_center().x, b.global_position.y - 4)
		"stand":
			var g: Season = m.game
			if g.layout.stands.is_empty():
				return Vector2(-1, -1)
			var r := StadiumRendererRef.tiles_xz(g.layout.stands[0].tiles(g.layout.pitch))
			var p3 := Vector3(r.get_center().x, 2.0, r.get_center().y)
			if m.camera.is_position_behind(p3):
				return Vector2(-1, -1)
			return m.camera.unproject_position(p3) - Vector2(0, 30)
		"play":
			return Vector2(play_btn.get_global_rect().get_center().x, play_btn.global_position.y - 4)
		"transport", "site":
			if tray.visible:
				return Vector2(tray.get_global_rect().get_center().x, tray.global_position.y - 4)
			for b in dock_row.get_children():
				if b.has_meta("cat") and b.get_meta("cat") == GUIDE[guide_step][1]:
					return Vector2((b as Control).get_global_rect().get_center().x, (b as Control).global_position.y - 4)
	return Vector2(-1, -1)


func _process(delta: float) -> void:
	if guide_step < 0 or not guide_panel.visible:
		return
	_guide_t += delta
	var t := _guide_target()
	guide_arrow.visible = t.x >= 0
	guide_arrow.position = t - Vector2(guide_arrow.size.x / 2.0, guide_arrow.size.y + 6 + absf(sin(_guide_t * 5.0)) * 10.0)


# --- dialogs -------------------------------------------------------------------------

## A small modal: title, text, a cancel button and an action button.
func confirm(title: String, text: String, ok: String, cb: Callable) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var p := PanelContainer.new()
	shade.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	v.add_child(_label(title, 18))
	var t := _label(text, 13, C_MUTED)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD
	t.custom_minimum_size = Vector2(380, 0)
	v.add_child(t)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	var no := Button.new()
	no.text = "Cancel"
	no.custom_minimum_size = Vector2(100, 36)
	no.pressed.connect(func(): shade.queue_free())
	row.add_child(no)
	var yes := Button.new()
	yes.text = ok
	yes.custom_minimum_size = Vector2(150, 36)
	yes.add_theme_stylebox_override("normal", _box(Color(C_BAD, 0.35), 9, C_BAD, 1, 6))
	yes.pressed.connect(func():
		shade.queue_free()
		cb.call())
	row.add_child(yes)
	v.add_child(row)
	p.reset_size()
	p.position = (get_viewport_rect().size - p.size) / 2.0


## The new-game screen: set up the club (names, colours, badge, surroundings,
## sky) with the world updating live behind, then kick off.
func open_new_game() -> void:
	if new_game_screen and is_instance_valid(new_game_screen):
		new_game_screen.queue_free()
	for k in windows.keys():
		if is_instance_valid(windows[k]):
			windows[k].queue_free()
	windows.clear()
	var shade := Control.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	new_game_screen = shade
	var p := PanelContainer.new()
	p.position = Vector2(24, 24)
	shade.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	v.add_child(_label("NEW CLUB", 22, C_ACCENT))
	v.add_child(_label("Who are you? Everything here can be changed later from the Club button.", 13, C_MUTED))
	v.add_child(ClubSetup.new(self, true))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	var go := Button.new()
	go.text = "  KICK OFF  ▶"
	go.custom_minimum_size = Vector2(200, 46)
	go.add_theme_font_size_override("font_size", 18)
	go.add_theme_stylebox_override("normal", _box(Color(C_ACCENT, 0.85), 10, C_ACCENT, 1, 8))
	go.add_theme_stylebox_override("hover", _box(C_ACCENT, 10, Color.WHITE, 1, 8))
	go.add_theme_color_override("font_color", Color(0.08, 0.08, 0.1))
	go.add_theme_color_override("font_hover_color", Color(0.08, 0.08, 0.1))
	go.pressed.connect(func():
		shade.queue_free()
		new_game_screen = null
		m._kick_off())
	row.add_child(go)
	v.add_child(row)
	p.reset_size()
	var vp := get_viewport_rect().size
	p.position.y = maxf(12.0, (vp.y - p.size.y) / 2.0)


# --- refresh -------------------------------------------------------------------------

func refresh() -> void:
	var g: Season = m.game
	var c := g.club
	crest.club = c
	crest.refresh()
	club_label.text = c.club_name
	stat["ground"].text = c.ground_name(m.config)
	stat["cash"].text = Season.money(c.cash)
	stat["cash"].add_theme_color_override("font_color", C_BAD if c.cash < 0 else C_TEXT)
	stat["fans"].text = _n(c.fanbase)
	stat["cap"].text = _n(g.layout.capacity_total(m.config))
	mood_bar.value = c.mood
	mood_icon.set_id("mood_good" if c.mood >= 60 else ("mood_ok" if c.mood >= 35 else "mood_bad"))
	var div: Dictionary = m.config.division(c.division)
	var pts := g.summary().points
	var pos := g.position()
	var nteams := g.league.teams.size()
	stat["league"].text = "%s  ·  %s  ·  %d pts" % [div["name"], LeagueWindow._ord(pos), pts]
	league_bar.max_value = nteams - 1
	league_bar.value = nteams - pos
	stat["league_box"].tooltip_text = "League position: %s of %d.%s%s Click for the table." % [LeagueWindow._ord(pos), nteams,
		(" Top %d go up." % g.promoted_places()) if g.promoted_places() > 0 else "", (" Bottom %d go down." % g.relegated_places()) if g.relegated_places() > 0 else ""]
	var fx := g.next_fixture()
	stat["season"].text = "Season %d" % g.season_number
	for t in play_tags.get_children():
		t.free()
	if g.is_over():
		stat["next_label"].text = "SEASON OVER · finished %s" % LeagueWindow._ord(pos)
		play_sub.text = "Start season %d" % (g.season_number + 1)
		play_btn.text = "NEXT SEASON ▶"
		play_btn.tooltip_text = "Start the next season"
	else:
		stat["next_label"].text = "MATCHDAY %d OF %d · %s" % [g.next_match_number(), g.fixtures.size(), "HOME" if fx.home else "AWAY"]
		play_sub.text = ("vs " if fx.home else "at ") + fx.opponent
		play_btn.text = "PLAY MATCH ▶"
		play_btn.tooltip_text = "Play matchday %d: your game and the rest of the league" % g.next_match_number()
		for tag in [["big", fx.big, "Big match: bigger crowd"], ["night", fx.evening, "Evening kick-off"], ["rain", fx.weather == "rain", "Rain forecast: covered stands help"], ["snow", fx.weather == "snow", "Snow forecast: covered stands help"]]:
			if tag[1]:
				var ic := Icon.new(tag[0])
				ic.custom_minimum_size = Vector2(18, 18)
				ic.tooltip_text = tag[2]
				ic.mouse_filter = Control.MOUSE_FILTER_PASS
				play_tags.add_child(ic)
	# tiles: price, lock, selected
	for id in tiles:
		var t: Control = tiles[id]
		if not is_instance_valid(t):
			continue
		var price: Label = t.get_meta("price")
		var open := _tile_enabled(id)
		t.modulate = Color(1, 1, 1, 1.0 if open else 0.45)
		var sb := _box(Color(C_ACCENT, 0.22) if m.tool == id else Color(1, 1, 1, 0.05), 10, C_ACCENT if m.tool == id else Color(1, 1, 1, 0.06), 2 if m.tool == id else 1, 6)
		t.add_theme_stylebox_override("panel", sb)
		if id == "pitch":
			price.text = "Move" if g.layout.pitch_placed else _short_money(m.config.num("plot/pitch_cost"))
			price.add_theme_color_override("font_color", C_ACCENT)
			t.tooltip_text = "Move the pitch. Stands move with it; any that wouldn't fit show in red and you're asked first."
		elif m.config.site_items.has(id):
			var si: Dictionary = m.config.site_items[id]
			price.text = "%s / tile" % _short_money(float(si["cost"]))
			price.add_theme_color_override("font_color", C_ACCENT)
			var how := "Drag to draw a line (hold Shift for an area)." if si["group"] != "green" else "Click, or drag to plant a row."
			t.tooltip_text = "%s. %s\n%s Bulldoze to remove." % [si["name"], si.get("tip", "Makes the ground look loved"), how]
		elif id.begins_with("land_"):
			var cost: float = g.land_cost(id.substr(5))
			price.text = "sold out" if cost < 0 else _short_money(cost)
			t.tooltip_text = "Buy a strip of land on this side for %s" % Season.money(cost) if cost >= 0 else "No more land for sale here"
		elif not g.is_unlocked(id):
			price.text = "🔒 %s fans" % _n(m.config.unlock_fans(id))
			price.add_theme_color_override("font_color", C_MUTED)
			t.tooltip_text = "%s unlocks at %s fans" % [_item_name(id), _n(m.config.unlock_fans(id))]
		elif m.config.stand_types.has(id):
			var st: StandType = m.config.stand_type(id)
			price.text = "%s / tile" % _short_money(st.capacity_per_tile * st.build_cost_per_place)
			price.add_theme_color_override("font_color", C_ACCENT)
			t.tooltip_text = "%s: %d places per tile, noise %.1f, tickets ~£%d.\nDrag beside the pitch or into a corner. Next to a %s stand, it extends it." % [
				st.display_name, st.capacity_per_tile, st.noise, roundi(st.reference_price), st.display_name.to_lower()]
		elif m.config.facility_types.has(id):
			var ft: FacilityType = m.config.facility_type(id)
			price.text = _short_money(ft.build_cost)
			price.add_theme_color_override("font_color", C_ACCENT)
			t.tooltip_text = m._facility_blurb(ft)
	refresh_levels(m._max_tiers(), m.level, m.layer == "concourse")
	_guide_update()
	refresh_card()
	refresh_result()
	_place_corner.call_deferred()
	_place_dock.call_deferred()


## True if a screen position is over any HUD panel (so clicks there don't build).
func _over_ui(pos: Vector2) -> bool:
	for p in [top_bar, dock, tray, card, play_panel, result_card, md_panel, rail.get_parent()] + windows.values():
		if p and is_instance_valid(p) and p.visible and p.get_global_rect().has_point(pos):
			return true
	return false


static func _n(v: float) -> String:
	return Season.money(v).substr(1)


static func _short_money(v: float) -> String:
	var a := absf(v)
	var s := ""
	if a >= 1e6:
		s = "£%.1fM" % (a / 1e6)
	elif a >= 1e3:
		s = "£%dk" % roundi(a / 1e3)
	else:
		s = "£%d" % roundi(a)
	return ("-" if v < 0 else "") + s
