extends SceneTree
## Headless layout comparison: N seasons of each layout, then a comparison table.
##   godot --headless -s tools/compare_layouts.gd -- <a.json> <b.json> [--seed=S] [--seasons=N] [--show-season]
## Season k uses seed S+k for both layouts (paired comparison: same random draws).
## The last column counts seasons where A was higher / equal / B was higher.
## --show-season also prints the first season's summary for each layout.

const METRICS := [
	# [label, key, format]
	["points", "points", "%.1f"],
	["wins", "wins", "%.1f"],
	["avg attendance", "attendance_avg", "%.0f"],
	["avg fill %", "fill_pct", "%.1f"],
	["avg atmosphere", "atmosphere_avg", "%.1f"],
	["ticket revenue", "tickets", "%.0f"],
	["food revenue", "food", "%.0f"],
	["premium revenue", "premium", "%.0f"],
	["upkeep", "upkeep", "%.0f"],
	["matchday net", "net", "%.0f"],
	["food unserved %", "food_unserved_pct", "%.1f"],
	["restroom unserved %", "restroom_unserved_pct", "%.1f"],
	["end mood", "mood_end", "%.1f"],
	["end cash", "cash_end", "%.0f"],
]


func _init() -> void:
	var paths: Array[String] = []
	var seed := 1
	var seasons := 100
	var show_season := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--seasons="):
			seasons = int(arg.get_slice("=", 1))
		elif arg == "--show-season":
			show_season = true
		else:
			paths.append(arg if arg.begins_with("res://") or arg.is_absolute_path() else "res://" + arg)
	if paths.size() != 2 or seasons < 1:
		printerr("usage: godot --headless -s tools/compare_layouts.gd -- <a.json> <b.json> [--seed=S] [--seasons=N] [--show-season]")
		quit(1)
		return

	var config := SimConfig.load_default()
	var budget := config.num("economy/starting_cash")
	var names: Array[String] = []
	var samples: Array = [[], []]  # per layout: Array of metric dicts
	for li in 2:
		var proto := Layout.load_json(paths[li], config)
		var errors := proto.validate(config, budget)
		if not errors.is_empty():
			printerr("%s is invalid:\n  %s" % [paths[li], "\n  ".join(errors)])
			quit(1)
			return
		names.append(proto.name)
		for k in seasons:
			var layout := Layout.load_json(paths[li], config)
			var report := Season.create(config, layout, seed + k).play_all()
			if show_season and k == 0:
				print(report.to_text())
				print("")
			samples[li].append(flatten(report))

	print("LAYOUT COMPARISON   seeds %d..%d   %d seasons x %d matches" % [
		seed, seed + seasons - 1, seasons, config.integer("season/matches")])
	print("build cost: %s %.0f   %s %.0f   (budget %.0f)" % [
		names[0], Layout.load_json(paths[0], config).build_cost(config),
		names[1], Layout.load_json(paths[1], config).build_cost(config), budget])
	print("")
	var header := "%-22s%22s%22s%14s%16s" % ["metric (mean ± sd)", names[0].left(21), names[1].left(21), "B - A", "A>B/tie/B>A"]
	print(header)
	print("-".repeat(header.length()))
	for m in METRICS:
		var a := values(samples[0], m[1])
		var b := values(samples[1], m[1])
		var diffs: Array[float] = []
		var a_better := 0
		var b_better := 0
		for i in seasons:
			diffs.append(b[i] - a[i])
			if b[i] > a[i] + 1e-6:
				b_better += 1
			elif a[i] > b[i] + 1e-6:
				a_better += 1
		print("%-22s%22s%22s%14s%16s" % [
			m[0], fmt_ms(a, m[2]), fmt_ms(b, m[2]),
			(("%+" + m[2].substr(1)) % mean(diffs)),
			"%d/%d/%d" % [a_better, seasons - a_better - b_better, b_better]])
	quit(0)


static func flatten(r: SeasonReport) -> Dictionary:
	return {
		"points": r.points, "wins": r.wins, "attendance_avg": r.attendance_avg,
		"fill_pct": 100.0 * r.fill_avg, "atmosphere_avg": r.atmosphere_avg,
		"tickets": r.revenue["tickets"], "food": r.revenue["food"], "premium": r.revenue["premium"],
		"upkeep": r.upkeep, "net": r.net,
		"food_unserved_pct": 100.0 * r.food_unserved_share,
		"restroom_unserved_pct": 100.0 * r.restroom_unserved_share,
		"mood_end": r.mood_end, "cash_end": r.cash_end,
	}


static func values(rows: Array, key: String) -> Array[float]:
	var out: Array[float] = []
	for row in rows:
		out.append(float(row[key]))
	return out


static func mean(xs: Array[float]) -> float:
	var s := 0.0
	for x in xs:
		s += x
	return s / xs.size()


static func sd(xs: Array[float]) -> float:
	if xs.size() < 2:
		return 0.0
	var m := mean(xs)
	var s := 0.0
	for x in xs:
		s += (x - m) * (x - m)
	return sqrt(s / (xs.size() - 1))


static func fmt_ms(xs: Array[float], f: String) -> String:
	return (f + " ± " + f) % [mean(xs), sd(xs)]
