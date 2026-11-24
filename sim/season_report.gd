class_name SeasonReport
extends RefCounted
## End-of-season summary built from a Season's matchday reports.

var layout_name: String
var season_number: int
var seed: int
var matches: int
var wins: int
var draws: int
var losses: int
var points: int
var attendance_total: int
var attendance_avg: float
var fill_avg: float
var atmosphere_avg: float
var revenue: Dictionary = {}   # tickets / food / premium / total
var upkeep: float
var net: float                 # matchday revenue - upkeep (excludes construction)
var lost_food_sales: float
var food_unserved_share: float
var restroom_unserved_share: float
var build_spend: float
var cash_start: float
var cash_end: float
var mood_start: float
var mood_end: float
var fanbase_start: float
var fanbase_end: float
var rows: Array[Dictionary] = []


static func from_season(s: Season) -> SeasonReport:
	var r := SeasonReport.new()
	r.layout_name = s.layout.name
	r.seed = s.seed
	r.season_number = s.season_number
	r.matches = s.reports.size()
	r.revenue = { "tickets": 0.0, "food": 0.0, "premium": 0.0, "total": 0.0 }
	r.build_spend = s.build_spend
	r.cash_start = s.start_cash
	r.cash_end = s.club.cash
	r.mood_start = s.start_mood
	r.fanbase_start = s.start_fanbase
	r.fanbase_end = s.club.fanbase
	r.mood_end = s.club.mood
	var fill_sum := 0.0
	var atmos_sum := 0.0
	var want := { "food": 0, "restroom": 0 }
	var lost := { "food": 0, "restroom": 0 }
	for m in s.reports:
		match m.result:
			"W": r.wins += 1
			"D": r.draws += 1
			_: r.losses += 1
		r.attendance_total += m.attendance
		fill_sum += float(m.attendance) / max(1, m.capacity)
		atmos_sum += m.atmosphere
		for k in r.revenue:
			r.revenue[k] += m.revenue[k]
		r.upkeep += m.costs["total"]
		r.net += m.net
		r.lost_food_sales += m.lost_food_sales
		for kind in want:
			want[kind] += m.halftime[kind]["wanting"]
			lost[kind] += m.halftime[kind]["lost"]
		r.rows.append({
			"match": r.rows.size() + 1, "big": m.big_match, "demand_mult": m.demand_multipliers["form"] * m.demand_multipliers["mood"] * m.demand_multipliers["opponent"],
			"attendance": m.attendance, "capacity": m.capacity, "atmosphere": m.atmosphere,
			"p_win": m.probabilities["win"], "result": m.result, "net": m.net,
			"food_lost": m.halftime["food"]["lost"], "mood": m.mood_after,
		})
	r.points = 3 * r.wins + r.draws
	if r.matches > 0:
		r.attendance_avg = float(r.attendance_total) / r.matches
		r.fill_avg = fill_sum / r.matches
		r.atmosphere_avg = atmos_sum / r.matches
	r.food_unserved_share = float(lost["food"]) / max(1, want["food"])
	r.restroom_unserved_share = float(lost["restroom"]) / max(1, want["restroom"])
	return r


func to_dict() -> Dictionary:
	return {
		"layout_name": layout_name, "season_number": season_number, "seed": seed, "matches": matches,
		"wins": wins, "draws": draws, "losses": losses, "points": points,
		"attendance_total": attendance_total, "attendance_avg": attendance_avg,
		"fill_avg": fill_avg, "atmosphere_avg": atmosphere_avg, "revenue": revenue,
		"upkeep": upkeep, "net": net, "lost_food_sales": lost_food_sales,
		"food_unserved_share": food_unserved_share, "restroom_unserved_share": restroom_unserved_share,
		"build_spend": build_spend, "cash_start": cash_start, "cash_end": cash_end,
		"mood_start": mood_start, "mood_end": mood_end,
		"fanbase_start": fanbase_start, "fanbase_end": fanbase_end, "rows": rows,
	}


func to_text() -> String:
	var lines := PackedStringArray()
	lines.append("=== END OF SEASON %d: %s (seed %d) ===" % [season_number, layout_name, seed])
	lines.append(" #  big  demand  attend/cap        atmos  P(win) res       net  food lost  mood")
	for row in rows:
		lines.append("%2d  %3s  x%.2f  %6d/%-6d  %5.1f  %.3f   %s  %9.0f  %9d  %4.1f" % [
			row["match"], "BIG" if row["big"] else "", row["demand_mult"], row["attendance"], row["capacity"],
			row["atmosphere"], row["p_win"], row["result"], row["net"], row["food_lost"], row["mood"]])
	lines.append("")
	lines.append("RECORD    W%d D%d L%d   %d pts" % [wins, draws, losses, points])
	lines.append("CROWDS    total %d   avg %.0f   avg fill %.0f%%   avg atmosphere %.1f" % [
		attendance_total, attendance_avg, 100.0 * fill_avg, atmosphere_avg])
	lines.append("HALFTIME  food unserved %.0f%%   restroom unserved %.0f%%   lost food sales %.0f" % [
		100.0 * food_unserved_share, 100.0 * restroom_unserved_share, lost_food_sales])
	lines.append("MONEY     tickets %.0f  food %.0f  premium %.0f  upkeep -%.0f  matchday net %.0f" % [
		revenue["tickets"], revenue["food"], revenue["premium"], upkeep, net])
	lines.append("CASH      start %.0f  built -%.0f  end %.0f" % [cash_start, build_spend, cash_end])
	lines.append("MOOD      %.1f -> %.1f" % [mood_start, mood_end])
	lines.append("FANBASE   %.0f -> %.0f" % [fanbase_start, fanbase_end])
	return "\n".join(lines)
