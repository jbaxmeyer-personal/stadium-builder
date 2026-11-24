extends Node2D
## Grey-box playable view. Reads sim state, sends player commands to Season.
## No game rules live here.

const TILE := 15
const MAP_ORIGIN := Vector2(10, 44)
const PANEL_X := 925.0
const NEW_STAND_LENGTH := 6
const EXTEND_STEP := 2
const PRICE_STEP := { "terrace": 1.0, "seated": 2.0, "premium": 5.0 }

const C_BG := Color(0.13, 0.14, 0.13)
const C_GROUND := Color(0.21, 0.23, 0.21)
const C_PITCH := Color(0.24, 0.44, 0.24)
const C_LINES := Color(1, 1, 1, 0.55)
const C_CONCOURSE := Color(0.33, 0.33, 0.31)
const C_STAND := { "terrace": Color(0.42, 0.42, 0.46), "seated": Color(0.56, 0.56, 0.60), "premium": Color(0.70, 0.66, 0.52) }
const C_FACILITY := { "food": Color(0.86, 0.58, 0.28), "restroom": Color(0.40, 0.60, 0.86) }
const C_SELECT := Color(1.0, 0.85, 0.2)
const C_GOOD := Color(0.55, 0.9, 0.55)
const C_BAD := Color(1.0, 0.5, 0.45)

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
var font: Font


func _ready() -> void:
	config = SimConfig.load_default()
	game = Season.create(config, Layout.create(config, "My Stadium"), int(Time.get_unix_time_from_system()))
	font = ThemeDB.fallback_font
	RenderingServer.set_default_clear_color(C_BG)
	_build_ui()
	_refresh()
	_say("Pick Terrace, Seated or Premium, then click beside the pitch to build your first stand.")


# --- UI construction -----------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	hud = Label.new()
	hud.position = Vector2(10, 10)
	hud.add_theme_font_size_override("font_size", 16)
	hud.size = Vector2(PANEL_X - 20, 24)
	hud.clip_text = true
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)

	message = Label.new()
	message.position = Vector2(10, MAP_ORIGIN.y + 40 * TILE + 8)
	message.size = Vector2(900, 50)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(message)

	var panel := VBoxContainer.new()
	panel.position = Vector2(PANEL_X, 10)
	panel.size = Vector2(345, 700)
	panel.add_theme_constant_override("separation", 6)
	layer.add_child(panel)

	panel.add_child(_heading("BUILD"))
	var grid := GridContainer.new()
	grid.columns = 4
	var group := ButtonGroup.new()
	for t in [["select", "Select"], ["terrace", "Terrace"], ["seated", "Seated"], ["premium", "Premium"],
			["kiosk", "Kiosk"], ["restroom", "Restroom"], ["demolish", "Demolish"]]:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = t[0] == tool
		b.custom_minimum_size = Vector2(82, 30)
		var id: String = t[0]
		b.pressed.connect(func(): _set_tool(id))
		grid.add_child(b)
	panel.add_child(grid)
	tool_hint = Label.new()
	tool_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tool_hint.custom_minimum_size = Vector2(340, 40)
	tool_hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	panel.add_child(tool_hint)

	panel.add_child(HSeparator.new())
	sel_label = Label.new()
	panel.add_child(sel_label)
	var sel_grid := GridContainer.new()
	sel_grid.columns = 2
	for a in ["row", "unrow", "left", "right", "demolish"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(168, 28)
		var action: String = a
		b.pressed.connect(func(): _stand_action(action))
		sel_grid.add_child(b)
		sel_buttons[a] = b
	panel.add_child(sel_grid)

	panel.add_child(HSeparator.new())
	panel.add_child(_heading("TICKET PRICES"))
	for id in config.stand_type_ids():
		var row := HBoxContainer.new()
		var l := Label.new()
		l.custom_minimum_size = Vector2(200, 0)
		row.add_child(l)
		price_labels[id] = l
		for d in [-1, 1]:
			var b := Button.new()
			b.text = "-" if d < 0 else "+"
			b.custom_minimum_size = Vector2(36, 26)
			var type_id: String = id
			var dir: int = d
			b.pressed.connect(func(): _change_price(type_id, dir))
			row.add_child(b)
		panel.add_child(row)

	panel.add_child(HSeparator.new())
	play_button = Button.new()
	play_button.custom_minimum_size = Vector2(340, 44)
	play_button.add_theme_font_size_override("font_size", 18)
	play_button.pressed.connect(_on_play)
	panel.add_child(play_button)

	var details := CheckButton.new()
	details.text = "Show full sim numbers"
	details.toggled.connect(func(on: bool):
		show_details = on
		_refresh())
	panel.add_child(details)

	report_box = RichTextLabel.new()
	report_box.bbcode_enabled = true
	report_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report_box.custom_minimum_size = Vector2(340, 160)
	report_box.scroll_following = false
	panel.add_child(report_box)


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	return l


# --- Commands -------------------------------------------------------------

func _set_tool(id: String) -> void:
	tool = id
	_refresh()


func _change_price(type_id: String, dir: int) -> void:
	var p: float = game.club.price(type_id) + dir * PRICE_STEP[type_id]
	_report_err(game.set_ticket_price(type_id, max(0.0, p)))
	_refresh()


func _stand_action(action: String) -> void:
	if selected < 0 or selected >= game.layout.stands.size():
		return
	var s := game.layout.stands[selected]
	var side_len := Stand.side_length(s.side, game.layout.pitch)
	var err := ""
	match action:
		"row":
			err = game.resize_stand(selected, s.offset, s.length, s.depth + 1)
		"unrow":
			err = "a stand needs at least one row" if s.depth <= 1 else game.resize_stand(selected, s.offset, s.length, s.depth - 1)
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
		return null
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
	return Stand.make(side, tool, lo, hi - lo + 1, 1)


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


func _tile_rect(t: Vector2i) -> Rect2:
	return Rect2(MAP_ORIGIN + Vector2(t) * TILE, Vector2(TILE, TILE))


func _tiles_rect(tiles: Array[Vector2i]) -> Rect2:
	var r := _tile_rect(tiles[0])
	for t in tiles:
		r = r.merge(_tile_rect(t))
	return r


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var t := _mouse_tile(event.position)
		if t != hover:
			hover = t
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var t := _mouse_tile(event.position)
		if not game.layout.in_plot(t):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_click(t)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			selected = -1
			_refresh()


func _mouse_tile(pos: Vector2) -> Vector2i:
	var local := (pos - MAP_ORIGIN) / TILE
	return Vector2i(floori(local.x), floori(local.y))


# --- Refresh / text --------------------------------------------------------

func _refresh() -> void:
	var c := game.club
	var fx := game.next_fixture()
	var match_text := "Season over" if fx == null else "Match %d/%d" % [game.next_match_number(), game.fixtures.size()]
	hud.text = "Season %d   %s   Cash %s   Fans %s   Mood %d   Form %s   Capacity %s" % [
		game.season_number, match_text, Season.money(c.cash), _n(c.fanbase), roundi(c.mood),
		"-" if c.recent_results.is_empty() else "".join(c.recent_results.slice(-5)),
		_n(game.layout.capacity_total(config))]

	tool_hint.text = _tool_hint()
	_refresh_selection()
	for id in price_labels:
		price_labels[id].text = "%s  £%d" % [config.stand_type(id).display_name, roundi(c.price(id))]
	if game.is_over():
		play_button.text = "Start season %d" % (game.season_number + 1)
	else:
		play_button.text = "Play match %d%s" % [game.next_match_number(), "  (BIG MATCH!)" if fx.big else ""]
	report_box.text = _report_text()
	queue_redraw()


func _tool_hint() -> String:
	if config.stand_types.has(tool):
		var t := config.stand_type(tool)
		return "%s: %s per tile (%d places). Click beside the pitch. Noise %.1f, ticket ~£%d." % [
			t.display_name, Season.money(t.capacity_per_tile * t.build_cost_per_place), t.capacity_per_tile,
			t.noise, roundi(t.reference_price)]
	if config.facility_types.has(tool):
		var f := config.facility_type(tool)
		return "%s: %s. Click a concourse tile (dark strip behind a stand). Serves %d fans/min at halftime." % [
			f.display_name, Season.money(f.build_cost), roundi(f.service_rate_per_min)]
	if tool == "demolish":
		return "Click a stand or facility to knock it down (%d%% refund)." % roundi(100 * config.num("season/demolish_refund_fraction"))
	return "Click a stand to select it. Right-click to deselect."


func _refresh_selection() -> void:
	var has := selected >= 0 and selected < game.layout.stands.size()
	for b in sel_buttons.values():
		b.visible = has
	if not has:
		selected = -1
		sel_label.text = "No stand selected"
		return
	var s := game.layout.stands[selected]
	var t := config.stand_type(s.type_id)
	var side_len := Stand.side_length(s.side, game.layout.pitch)
	sel_label.text = "%s stand (%s side): %d x %d tiles, %s places" % [
		t.display_name, s.side, s.length, s.depth, _n(s.capacity(t))]
	sel_buttons["row"].text = "Add row (%s)" % Season.money(game.resize_cost(selected, s.offset, s.length, s.depth + 1))
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


# --- Drawing ---------------------------------------------------------------

func _draw() -> void:
	var l := game.layout
	draw_rect(Rect2(MAP_ORIGIN, Vector2(l.width, l.height) * TILE), C_GROUND)

	var concourse := l.concourse_tile_map(config)
	for t in concourse:
		draw_rect(_tile_rect(t), C_CONCOURSE)

	# Pitch
	var pr := Rect2(MAP_ORIGIN + Vector2(l.pitch.position) * TILE, Vector2(l.pitch.size) * TILE)
	draw_rect(pr, C_PITCH)
	var inner := pr.grow(-TILE * 0.5)
	draw_rect(inner, C_LINES, false, 1.5)
	draw_line(Vector2(inner.get_center().x, inner.position.y), Vector2(inner.get_center().x, inner.end.y), C_LINES, 1.5)
	draw_arc(inner.get_center(), TILE * 2.5, 0, TAU, 32, C_LINES, 1.5)
	for x in [inner.position.x, inner.end.x - TILE * 2.5]:
		draw_rect(Rect2(x, inner.get_center().y - TILE * 3, TILE * 2.5, TILE * 6), C_LINES, false, 1.5)

	# Stands, with last match fill if there is one
	for i in l.stands.size():
		var s := l.stands[i]
		var rect := _tiles_rect(s.tiles(l.pitch))
		draw_rect(rect, C_STAND[s.type_id])
		draw_rect(rect, Color(0, 0, 0, 0.35), false, 1.0)
		var text := "%s %s" % [config.stand_type(s.type_id).display_name, _n(s.capacity(config.stand_type(s.type_id)))]
		if last_report != null and i < last_report.stands.size() and last_report.stands[i]["capacity"] == s.capacity(config.stand_type(s.type_id)):
			var st: Dictionary = last_report.stands[i]
			text = "%s/%s" % [_n(st["attendance"]), _n(st["capacity"])]
			# fill bar along the pitch-facing edge
			var fill: float = st["fill"]
			draw_rect(Rect2(rect.position, Vector2(rect.size.x * fill, 3)), C_GOOD if fill >= 0.95 else Color(0.9, 0.9, 0.9))
		_draw_text_in(rect, text)
		if i == selected:
			draw_rect(rect.grow(1), C_SELECT, false, 2.0)

	# Facilities
	for f in l.facilities:
		var ft := config.facility_type(f.type_id)
		var r := _tile_rect(f.pos).grow(-1)
		draw_rect(r, C_FACILITY[ft.kind])
		draw_string(font, r.position + Vector2(3, r.size.y - 3), "K" if ft.kind == "food" else "R",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)

	# Hover / placement preview
	if l.in_plot(hover):
		if config.stand_types.has(tool) and _stand_at(hover, l.stand_tile_map(), concourse) < 0:
			var ghost := _placement(hover)
			if ghost != null:
				var gr := _tiles_rect(ghost.tiles(l.pitch))
				var t := config.stand_type(tool)
				draw_rect(gr, Color(C_STAND[tool], 0.5))
				draw_rect(gr, C_SELECT, false, 1.0)
				_draw_text_in(gr, Season.money(ghost.capacity(t) * t.build_cost_per_place))
		elif config.facility_types.has(tool):
			draw_rect(_tile_rect(hover), C_GOOD if concourse.has(hover) else C_BAD, false, 2.0)
		else:
			draw_rect(_tile_rect(hover), Color(1, 1, 1, 0.4), false, 1.0)


func _draw_text_in(rect: Rect2, text: String) -> void:
	var size := 11
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if w > rect.size.x - 2 or rect.size.y < 11:
		return
	draw_string(font, rect.get_center() + Vector2(-w / 2.0, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.8))
