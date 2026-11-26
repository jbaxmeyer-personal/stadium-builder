extends VBoxContainer
## The league: the table, every result round by round, your fixtures, and the
## squad budget (what you spend on players each match, which sets how strong
## your team is next to the rest of the division).

const C_TEXT := Color(0.93, 0.94, 0.96)
const C_MUTED := Color(0.62, 0.66, 0.72)
const C_ACCENT := Color(1.0, 0.78, 0.25)
const C_GOOD := Color(0.45, 0.88, 0.5)
const C_BAD := Color(1.0, 0.5, 0.42)
const C_ROW := Color(1, 1, 1, 0.035)
const C_US := Color(1.0, 0.78, 0.25, 0.16)
const C_UP := Color(0.45, 0.88, 0.5, 0.10)
const C_DOWN := Color(1.0, 0.5, 0.42, 0.12)

var m: Node
var tab := "table"
var _body: VBoxContainer
var _tabs := {}


func _init(p_main: Node, p_tab := "table") -> void:
	m = p_main
	tab = p_tab
	add_theme_constant_override("separation", 10)


func _ready() -> void:
	add_child(_squad_box())
	var row := HBoxContainer.new()
	for t in [["table", "Table"], ["results", "Results"], ["fixtures", "Your fixtures"]]:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(120, 30)
		var id: String = t[0]
		b.pressed.connect(func(): _show(id))
		row.add_child(b)
		_tabs[id] = b
	add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 400)
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	scroll.add_child(_body)
	_show(tab)


func _show(id: String) -> void:
	tab = id
	for k in _tabs:
		(_tabs[k] as Button).button_pressed = k == id
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	match id:
		"table": _table()
		"results": _results()
		"fixtures": _fixtures()


# --- squad budget --------------------------------------------------------------------

func _squad_box() -> Control:
	var g: Season = m.game
	var box := VBoxContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(_lbl("SQUAD BUDGET", 11, C_MUTED))
	var wage: float = g.club.wage(m.config)
	var minus := Button.new()
	minus.text = "  −  "
	minus.pressed.connect(func(): _budget(wage / 1.25))
	h.add_child(minus)
	h.add_child(_lbl("%s per match" % Season.money(wage), 16, C_ACCENT))
	var plus := Button.new()
	plus.text = "  +  "
	plus.pressed.connect(func(): _budget(wage * 1.25))
	h.add_child(plus)
	var rank: int = g.league.strength_rank(League.rating_for_wage(maxf(wage, float(m.config.division(g.club.division)["squad_wage"]) * m.config.num("league/talent_floor"))))
	h.add_child(_lbl("   Team strength: %s of %d" % [_ord(rank), g.league.teams.size()], 14, C_GOOD if rank <= 3 else (C_TEXT if rank <= 8 else C_BAD)))
	box.add_child(h)
	var norm: float = float(m.config.division(g.club.division)["squad_wage"])
	box.add_child(_lbl("Players' wages, paid every match (home and away). Spend more for a stronger team; luck still plays a part. A typical %s side spends %s.\nThe club also pays overheads of %s a match, plus stewards for every fan at home." % [
		m.config.division(g.club.division)["name"], Season.money(norm), Season.money(float(m.config.division(g.club.division).get("overheads_per_match", 0.0)))], 11, C_MUTED))
	if g.club.administration:
		box.add_child(_lbl("⚠ IN ADMINISTRATION: %d points deducted, wages capped at %s a match until the club is back in the black." % [
			m.config.integer("economy/administration_points"), Season.money(g.wage_cap())], 12, C_BAD))
	elif g.club.cash < 0.0:
		var limit: float = m.config.num("economy/administration_debt_wages") * norm
		box.add_child(_lbl("⚠ In debt: interest is charged every match. Below -%s at the end of a season the club goes into administration." % Season.money(limit).substr(1), 12, C_BAD))
	return box


func _budget(v: float) -> void:
	var step := 500.0 if v < 20000.0 else 1000.0
	m._report_err(m.game.set_squad_budget(maxf(1000.0, roundf(v / step) * step)))
	m._refresh()
	var w = get_parent().get_parent()
	if w and w.has_method("queue_free"):
		(func(): m.ui.open_league(tab)).call_deferred()


# --- tables --------------------------------------------------------------------------

func _table() -> void:
	var g: Season = m.game
	var t := g.league.table()
	var up: int = g.promoted_places()
	var down: int = g.relegated_places()
	_body.add_child(_row(["#", "CLUB", "P", "W", "D", "L", "GF", "GA", "GD", "PTS", "FORM"], true, Color(0, 0, 0, 0)))
	for i in t.size():
		var r: Dictionary = t[i]
		var form := ""
		for f in (r["form"] as Array).slice(-5):
			form += f
		var bg := C_US if r["team"] == 0 else (C_UP if i < up else (C_DOWN if i >= t.size() - down else (C_ROW if i % 2 == 0 else Color(0, 0, 0, 0))))
		var gd: int = r["gf"] - r["ga"]
		_body.add_child(_row([str(i + 1), r["name"], str(r["p"]), str(r["w"]), str(r["d"]), str(r["l"]), str(r["gf"]), str(r["ga"]),
			("+" if gd > 0 else "") + str(gd), str(r["pts"]), form], false, bg, r["team"] == 0))
	if up > 0:
		_body.add_child(_lbl("Top %d are promoted to the %s." % [up, m.config.division(g.club.division + 1)["name"]], 11, C_GOOD))
	else:
		_body.add_child(_lbl("Top division: win the league!", 11, C_ACCENT))
	if down > 0:
		_body.add_child(_lbl("Bottom %d are relegated to the %s." % [down, m.config.division(g.club.division - 1)["name"]], 11, C_BAD))


func _results() -> void:
	var g: Season = m.game
	var lg: League = g.league
	if lg.played() == 0:
		_body.add_child(_lbl("No games played yet this season.", 13, C_MUTED))
		return
	for ri in range(lg.results.size() - 1, -1, -1):
		var games: Array = lg.results[ri]
		if games.is_empty():
			continue
		_body.add_child(_lbl("MATCHDAY %d" % (ri + 1), 11, C_MUTED))
		for gm in games:
			var ours: bool = gm[0] == 0 or gm[1] == 0
			var line := "%s  %d – %d  %s" % [lg.teams[gm[0]]["name"], gm[2], gm[3], lg.teams[gm[1]]["name"]]
			var l := _lbl(line, 13, C_ACCENT if ours else C_TEXT)
			_body.add_child(l)


func _fixtures() -> void:
	var g: Season = m.game
	for i in g.fixtures.size():
		var fx: Fixture = g.fixtures[i]
		var where := "NEUTRAL" if fx.neutral else ("HOME" if fx.home else "away")
		var txt := "%2d.  %s  vs %s" % [fx.round + 1, where, fx.opponent]
		if not fx.is_league():
			txt = "  ★  %s %s · %s vs %s" % [fx.comp_name, fx.stage, where, fx.opponent]
		var col := C_TEXT
		if i < g.reports.size():
			var r: MatchdayReport = g.reports[i]
			txt += "   %d – %d  %s%s" % [r.home_goals, r.away_goals, r.result, "" if r.penalties == "" else " (pens %s)" % r.penalties]
			col = { "W": C_GOOD, "D": C_TEXT, "L": C_BAD }[r.result]
		elif i == g.reports.size():
			txt += "   ← next"
			col = C_ACCENT
		else:
			col = C_MUTED
		if fx.big:
			txt += "   (big match)"
		_body.add_child(_lbl(txt, 13, col))


func _row(cells: Array, head: bool, bg: Color, bold := false) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	p.add_child(h)
	var widths := [30, 220, 34, 34, 34, 34, 40, 40, 44, 46, 80]
	for i in cells.size():
		var l := _lbl(str(cells[i]), 10 if head else 13, C_MUTED if head else (C_ACCENT if bold else C_TEXT))
		l.custom_minimum_size.x = widths[i]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 1 or i == 10 else HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(l)
	return p


func _lbl(text: String, size := 13, col := C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


static func _ord(n: int) -> String:
	var suf := "th"
	if n % 100 < 11 or n % 100 > 13:
		suf = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suf]
