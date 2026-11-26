extends VBoxContainer
## The club's record books: season-by-season results, a profit-and-loss
## spreadsheet, this season's matches, and charts of how it all grew.
## Reads Season.history (finished seasons) plus the season in progress.

const C_TEXT := Color(0.93, 0.94, 0.96)
const C_MUTED := Color(0.62, 0.66, 0.72)
const C_ACCENT := Color(1.0, 0.78, 0.25)
const C_GOOD := Color(0.45, 0.88, 0.5)
const C_BAD := Color(1.0, 0.5, 0.42)
const C_LINE := Color(1, 1, 1, 0.07)
const C_ROW := Color(1, 1, 1, 0.035)

const INCOME := [["tickets", "Tickets"], ["premium", "Hospitality"], ["boxes", "Executive boxes"], ["food", "Food"],
	["drinks", "Drinks"], ["merch", "Merchandise"], ["sponsors", "Board sponsors"], ["naming", "Naming rights"],
	["tv", "TV money"], ["venue", "Venue income"]]
const COSTS := [["wages", "Player wages"], ["stands", "Stand upkeep"], ["facilities", "Facility upkeep"], ["utilities", "Power and water"]]

var game: Season
var tab := "seasons"
var _body: VBoxContainer
var _tabs := {}


func _init(p_game: Season) -> void:
	game = p_game
	add_theme_constant_override("separation", 10)


func _ready() -> void:
	add_child(_headline())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for t in [["seasons", "Seasons"], ["money", "Money"], ["matches", "This season"], ["charts", "Charts"]]:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(110, 30)
		var id: String = t[0]
		b.pressed.connect(func(): _show(id))
		row.add_child(b)
		_tabs[id] = b
	add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(960, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)
	_show(tab)


## Finished seasons plus the one being played (if a match has been played).
func _rows() -> Array[SeasonReport]:
	var out: Array[SeasonReport] = []
	out.append_array(game.history)
	if not game.reports.is_empty():
		out.append(game.summary())
	return out


func _live(r: SeasonReport) -> bool:
	return r.season_number == game.season_number


func _show(id: String) -> void:
	tab = id
	for k in _tabs:
		(_tabs[k] as Button).button_pressed = k == id
	for c in _body.get_children():
		c.queue_free()
	match id:
		"seasons": _seasons()
		"money": _money()
		"matches": _matches()
		"charts": _charts()


# --- headline numbers ---------------------------------------------------------

func _headline() -> Control:
	var rows := _rows()
	var promos := 0
	var record := 0
	var profit := 0.0
	var best_pts := 0
	for r in rows:
		promos += 1 if r.promoted else 0
		record = maxi(record, r.best_attendance)
		profit += r.profit()
		best_pts = maxi(best_pts, r.points)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 26)
	for kv in [["Seasons", str(game.season_number)], ["Promotions", str(promos)], ["Record crowd", _n(record)],
			["Best season", "%d pts" % best_pts], ["Capacity now", _n(game.layout.capacity_total(game.config))],
			["Fans", _n(game.club.fanbase)], ["Profit, all time", _money_s(profit)]]:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.add_child(_lbl(kv[0].to_upper(), 10, C_MUTED))
		var big := _lbl(kv[1], 18, C_TEXT)
		if kv[0] == "Profit, all time":
			big.add_theme_color_override("font_color", C_GOOD if profit >= 0.0 else C_BAD)
		v.add_child(big)
		h.add_child(v)
	return h


# --- tables -----------------------------------------------------------------------

## A spreadsheet-like grid: header row, then rows of cells. A cell is a String or
## [text, colour]. First column left-aligned, the rest right-aligned.
func _table(head: Array, rows: Array, first_w := 70.0, col_w := 74.0, bold_rows: Array = [], widths := {}, left_cols: Array = [0]) -> Control:
	var grid := GridContainer.new()
	grid.columns = head.size()
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	var all := [head]
	all.append_array(rows)
	for ri in all.size():
		var row: Array = all[ri]
		for ci in row.size():
			var cell: Variant = row[ci]
			var text := ""
			var col := C_TEXT if ri > 0 else C_MUTED
			if cell is Array:
				text = str(cell[0])
				col = cell[1]
			else:
				text = str(cell)
			var p := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0) if ri == 0 else (C_ROW if ri % 2 == 1 else Color(0, 0, 0, 0))
			if ri in bold_rows:
				sb.bg_color = Color(1, 1, 1, 0.08)
			sb.border_color = C_LINE
			sb.border_width_bottom = 1
			sb.content_margin_left = 8
			sb.content_margin_right = 8
			sb.content_margin_top = 4
			sb.content_margin_bottom = 4
			p.add_theme_stylebox_override("panel", sb)
			var l := _lbl(text, 10 if ri == 0 else 12, col)
			l.custom_minimum_size.x = float(widths.get(ci, first_w if ci == 0 else col_w))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if ci in left_cols else HORIZONTAL_ALIGNMENT_RIGHT
			p.add_child(l)
			grid.add_child(p)
	return grid


func _seasons() -> void:
	var rows := _rows()
	if rows.is_empty():
		_body.add_child(_lbl("Play a match and the record books start here.", 13, C_MUTED))
		return
	var out := []
	for r in rows:
		var target := ("%d/%d" % [r.position, r.teams]) if r.position > 0 else ("-" if r.promotion_points < 0 else str(r.promotion_points) + " pts")
		var outcome: Array = ["Promoted", C_GOOD] if r.promoted else (["Playing", C_ACCENT] if _live(r) else ["Stayed", C_MUTED])
		var fans_delta := r.fanbase_end - r.fanbase_start
		out.append([
			"%d%s" % [r.season_number, " *" if _live(r) else ""], [r.division_name, C_TEXT], str(r.matches), str(r.wins), str(r.draws), str(r.losses),
			"%d-%d" % [r.goals_for, r.goals_against], [str(r.points), C_ACCENT], target, outcome,
			_n(r.attendance_avg), _n(r.best_attendance), _n(r.capacity_end), "%d%%" % roundi(100.0 * r.fill_avg),
			"%.1f" % r.atmosphere_avg, _n(r.fanbase_end), [("+" if fans_delta >= 0 else "") + _n(fans_delta), C_GOOD if fans_delta >= 0 else C_BAD],
		])
	_body.add_child(_table(["SEASON", "DIVISION", "P", "W", "D", "L", "GOALS", "PTS", "POS", "OUTCOME", "AVG CROWD", "BEST",
		"CAPACITY", "FILL", "ATMOS", "FANS", "FANS +/-"], out, 48.0, 40.0, [],
		{ 1: 118.0, 6: 50.0, 9: 70.0, 10: 66.0, 11: 52.0, 12: 62.0, 15: 56.0, 16: 62.0 }, [0, 1]))
	_body.add_child(_lbl("* season in progress", 10, C_MUTED))


func _money() -> void:
	var rows := _rows()
	if rows.is_empty():
		_body.add_child(_lbl("No money in or out yet.", 13, C_MUTED))
		return
	rows = rows.slice(maxi(0, rows.size() - 9))   # the last nine seasons fit; older ones roll off
	var head := ["", ]
	for r in rows:
		head.append("SEASON %d%s" % [r.season_number, " *" if _live(r) else ""])
	var done := rows.size() - (1 if _live(rows.back()) else 0)
	var cmp := done >= 2
	if cmp:
		head.append("S%d VS S%d" % [rows[done - 1].season_number, rows[done - 2].season_number])
	var out := []
	var bold := []
	var line := func(label: String, vals: Array, colour := C_TEXT, signed := false, cost := false) -> void:
		var row: Array = [[label, colour]]
		for v in vals:
			var f := float(v)
			row.append([_money_s(f) if f != 0.0 else "-", (C_GOOD if f > 0 else (C_BAD if f < 0 else C_MUTED)) if signed else colour])
		if cmp:
			row.append(_yoy(float(vals[done - 2]), float(vals[done - 1]), cost))
		out.append(row)
	out.append([["INCOME", C_ACCENT]] + _blank(head.size() - 1))
	for it in INCOME:
		var vals := []
		var any := false
		for r in rows:
			var v := float(r.revenue.get(it[0], 0.0))
			any = any or v != 0.0
			vals.append(v)
		if any:
			line.call("  " + it[1], vals)
	var extra := []
	var refunds := []
	var inc_total := []
	for r in rows:
		extra.append(r.milestone_rewards)
		refunds.append(r.demolish_refunds)
		inc_total.append(float(r.revenue.get("total", 0.0)) + r.milestone_rewards + r.demolish_refunds)
	line.call("  Milestone rewards", extra)
	line.call("  Demolition refunds", refunds)
	bold.append(out.size() + 1)
	line.call("Total income", inc_total)
	out.append([["SPENDING", C_ACCENT]] + _blank(head.size() - 1))
	for it in COSTS:
		var vals := []
		for r in rows:
			vals.append(float(r.costs.get(it[0], r.upkeep if it[0] == "stands" and r.costs.is_empty() else 0.0)))
		line.call("  " + it[1], vals, C_TEXT, false, true)
	var build := []
	var land := []
	var spend_total := []
	for r in rows:
		build.append(r.build_spend)
		land.append(r.land_spend)
		spend_total.append(r.upkeep + r.build_spend + r.land_spend)
	line.call("  Construction", build, C_TEXT, false, true)
	line.call("  Land", land, C_TEXT, false, true)
	bold.append(out.size() + 1)
	line.call("Total spending", spend_total, C_TEXT, false, true)
	out.append(_blank(head.size()))
	var op := []
	var prof := []
	var cash := []
	for r in rows:
		op.append(r.net)
		prof.append(r.profit())
		cash.append(r.cash_end)
	line.call("Matchday profit", op, C_TEXT, true)
	bold.append(out.size() + 1)
	line.call("Profit / loss", prof, C_TEXT, true)
	line.call("Cash at end", cash)
	_body.add_child(_table(head, out, 150.0, 92.0, bold))
	_body.add_child(_lbl("Matchday profit = match income minus running costs. Profit / loss also counts building, land, rewards and refunds.", 10, C_MUTED))


func _matches() -> void:
	var r: SeasonReport = null
	if not game.reports.is_empty():
		r = game.summary()
	elif not game.history.is_empty():
		r = game.history.back()
	if r == null:
		_body.add_child(_lbl("No matches played yet this season.", 13, C_MUTED))
		return
	_body.add_child(_lbl("Season %d, %s" % [r.season_number, r.division_name], 13, C_MUTED))
	var out := []
	for row in r.rows:
		var res: String = row["result"]
		var att := int(row["attendance"])
		var cap := int(row["capacity"])
		out.append([str(row["match"]), [str(row.get("opponent", "-")) + ("  (big)" if row["big"] else ""), C_TEXT], str(row.get("score", "")),
			[res, C_GOOD if res == "W" else (C_ACCENT if res == "D" else C_BAD)], _n(att), _n(cap),
			"%d%%" % roundi(100.0 * att / maxf(1.0, cap)), "%.1f" % float(row["atmosphere"]),
			_money_s(float(row.get("revenue", 0.0))), [_money_s(float(row["net"])), C_GOOD if float(row["net"]) >= 0.0 else C_BAD],
			"%.0f" % float(row["mood"])])
	_body.add_child(_table(["#", "OPPONENT", "SCORE", "RES", "CROWD", "CAPACITY", "FILL", "ATMOS", "INCOME", "NET", "MOOD"], out, 30.0, 66.0, [], { 1: 190.0, 3: 40.0 }, [0, 1]))


# --- charts -----------------------------------------------------------------------

func _charts() -> void:
	var rows := _rows()
	if rows.is_empty():
		_body.add_child(_lbl("Charts appear after your first match.", 13, C_MUTED))
		return
	var labels: Array[String] = []
	var inc: Array[float] = []
	var spend: Array[float] = []
	var avg: Array[float] = []
	var cap: Array[float] = []
	var fans: Array[float] = []
	var pts: Array[float] = []
	var tgt: Array[float] = []
	for r in rows:
		labels.append("S%d" % r.season_number)
		inc.append(float(r.revenue.get("total", 0.0)) + r.milestone_rewards + r.demolish_refunds)
		spend.append(r.upkeep + r.build_spend + r.land_spend)
		avg.append(r.attendance_avg)
		cap.append(float(r.capacity_end))
		fans.append(r.fanbase_end)
		pts.append(float(r.points))
		tgt.append(0.0)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	grid.add_child(Chart.make("Income and spending", labels, [[inc, C_GOOD, "income"], [spend, C_BAD, "spending"]], "bars", true))
	grid.add_child(Chart.make("Crowds and capacity", labels, [[cap, C_MUTED, "capacity"], [avg, C_ACCENT, "avg crowd"]], "lines"))
	grid.add_child(Chart.make("Fans", labels, [[fans, Color(0.5, 0.75, 1.0), "fans"]], "lines"))
	grid.add_child(Chart.make("Points per season", labels, [[pts, C_ACCENT, "points"]], "bars"))
	_body.add_child(grid)


class Chart extends Control:
	var title := ""
	var labels: Array[String] = []
	var series: Array = []   # [values: Array[float], colour, name]
	var kind := "bars"
	var money := false

	static func make(p_title: String, p_labels: Array[String], p_series: Array, p_kind: String, p_money := false) -> Chart:
		var c := Chart.new()
		c.title = p_title
		c.labels = p_labels
		c.series = p_series
		c.kind = p_kind
		c.money = p_money
		c.custom_minimum_size = Vector2(462, 196)
		return c

	func _fmt(v: float) -> String:
		var a := absf(v)
		var pre := "£" if money else ""
		if a >= 1e6:
			return pre + "%.1fM" % (v / 1e6)
		if a >= 1e3:
			return pre + "%dk" % roundi(v / 1e3)
		return pre + str(roundi(v))

	func _draw() -> void:
		var font := get_theme_default_font()
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.03))
		draw_string(font, Vector2(10, 18), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.62, 0.66, 0.72))
		var lx := size.x - 10.0
		for si in range(series.size() - 1, -1, -1):
			var s: Array = series[si]
			var w := font.get_string_size(s[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			lx -= w
			draw_string(font, Vector2(lx, 18), s[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, s[1])
			lx -= 14.0
			draw_rect(Rect2(lx, 10, 9, 9), s[1])
			lx -= 10.0
		var area := Rect2(52, 30, size.x - 64, size.y - 56)
		var top := 1.0
		for s in series:
			for v in s[0]:
				top = maxf(top, float(v))
		top *= 1.1
		for k in 5:
			var y := area.end.y - area.size.y * k / 4.0
			draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color(1, 1, 1, 0.06))
			draw_string(font, Vector2(4, y + 4), _fmt(top * k / 4.0), HORIZONTAL_ALIGNMENT_LEFT, 46, 9, Color(0.62, 0.66, 0.72))
		var n := labels.size()
		var step := area.size.x / maxf(1.0, n)
		for i in n:
			var cx := area.position.x + step * (i + 0.5)
			if n <= 12 or i % int(ceil(n / 12.0)) == 0:
				draw_string(font, Vector2(cx - 12, area.end.y + 16), labels[i], HORIZONTAL_ALIGNMENT_CENTER, 24, 9, Color(0.62, 0.66, 0.72))
		if kind == "bars":
			var bw := minf(26.0, step * 0.8 / series.size())
			for si in series.size():
				var s: Array = series[si]
				for i in n:
					var v := float(s[0][i])
					var h := area.size.y * v / top
					var x := area.position.x + step * (i + 0.5) - bw * series.size() / 2.0 + bw * si
					draw_rect(Rect2(x + 1, area.end.y - h, bw - 2, h), s[1])
		else:
			for s in series:
				var pts := PackedVector2Array()
				for i in n:
					pts.append(Vector2(area.position.x + step * (i + 0.5), area.end.y - area.size.y * float(s[0][i]) / top))
				if pts.size() >= 2:
					draw_polyline(pts, s[1], 2.5, true)
				for p in pts:
					draw_circle(p, 3.5, s[1])


# --- helpers ----------------------------------------------------------------------

func _lbl(text: String, size := 13, col := C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _blank(n: int) -> Array:
	var a := []
	for i in n:
		a.append("")
	return a


func _yoy(prev: float, now: float, cost := false) -> Array:
	if absf(prev) < 1.0:
		return ["-", C_MUTED]
	var pct := (now - prev) / absf(prev) * 100.0
	if roundi(pct) == 0:
		return ["0%", C_MUTED]
	var good := (pct >= 0) != cost
	return ["%s%d%%" % ["+" if pct >= 0 else "", roundi(pct)], C_GOOD if good else C_BAD]


static func _n(v: float) -> String:
	return Season.money(v).substr(1)


static func _money_s(v: float) -> String:
	var a := absf(v)
	var s := ""
	if a >= 1e6:
		s = "£%.2fM" % (a / 1e6)
	elif a >= 1e3:
		s = "£%dk" % roundi(a / 1e3)
	else:
		s = "£%d" % roundi(a)
	return ("-" if v < 0 else "") + s
