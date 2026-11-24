extends SceneTree
## Headless matchday runner.
##   godot --headless -s tools/run_matchday.gd -- <layout.json> [more.json ...] [--seed=N] [--big] [--opponent=Name]
## Prints a full report per layout and, with 2+ layouts, a side-by-side summary.


func _init() -> void:
	var paths: Array[String] = []
	var seed := 1
	var big := false
	var opponent := "Opponent"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = int(arg.get_slice("=", 1))
		elif arg == "--big":
			big = true
		elif arg.begins_with("--opponent="):
			opponent = arg.get_slice("=", 1)
		else:
			paths.append(arg if arg.begins_with("res://") or arg.is_absolute_path() else "res://" + arg)
	if paths.is_empty():
		printerr("usage: godot --headless -s tools/run_matchday.gd -- <layout.json> [...] [--seed=N] [--big]")
		quit(1)
		return

	var config := SimConfig.load_default()
	var fixture := Fixture.make(opponent, big)
	var reports: Array[MatchdayReport] = []
	var costs: Array[float] = []
	for path in paths:
		var layout := Layout.load_json(path, config)
		var club := ClubState.create(config)
		var errors := layout.validate(config)
		if not errors.is_empty():
			printerr("%s is invalid:\n  %s" % [path, "\n  ".join(errors)])
			quit(1)
			return
		costs.append(layout.build_cost(config))
		club.cash -= costs[-1]
		var report := MatchdaySim.run(config, layout, club, fixture, seed)
		print("build cost %.0f (starting cash %.0f)\n" % [costs[-1], config.num("economy/starting_cash")])
		print(report.to_text())
		print("")
		reports.append(report)

	if reports.size() > 1:
		print(side_by_side(reports, costs))
	quit(0)


func side_by_side(reports: Array[MatchdayReport], costs: Array[float]) -> String:
	var header := "%-22s" % "metric"
	for r in reports:
		header += "%18s" % r.layout_name.left(17)
	var lines := PackedStringArray([header, "-".repeat(header.length())])
	var metrics := [
		["build cost", func(r, i): return "%.0f" % costs[i]],
		["capacity", func(r, i): return str(r.capacity)],
		["attendance", func(r, i): return str(r.attendance)],
		["fill %", func(r, i): return "%.0f" % (100.0 * r.attendance / max(1, r.capacity))],
		["atmosphere", func(r, i): return "%.1f" % r.atmosphere],
		["P(win)", func(r, i): return "%.3f" % r.probabilities["win"]],
		["result", func(r, i): return r.result],
		["food wanting", func(r, i): return str(r.halftime["food"]["wanting"])],
		["food lost", func(r, i): return str(r.halftime["food"]["lost"])],
		["restroom lost", func(r, i): return str(r.halftime["restroom"]["lost"])],
		["tickets", func(r, i): return "%.0f" % r.revenue["tickets"]],
		["food", func(r, i): return "%.0f" % r.revenue["food"]],
		["premium", func(r, i): return "%.0f" % r.revenue["premium"]],
		["upkeep", func(r, i): return "%.0f" % r.costs["total"]],
		["net", func(r, i): return "%.0f" % r.net],
		["mood change", func(r, i): return "%+.1f" % r.mood_change["total"]],
	]
	for m in metrics:
		var line := "%-22s" % m[0]
		for i in reports.size():
			line += "%18s" % m[1].call(reports[i], i)
		lines.append(line)
	return "\n".join(lines)
