class_name SeasonReport
extends RefCounted
## End-of-season summary built from a Season's matchday reports.

var layout_name: String
var season_number: int
var division: int
var division_name: String
var promotion_points: int      # old saves only
var position: int = 0          # final (or current) league position
var teams: int = 0
var promoted: bool = false
var relegated: bool = false
var seed: int
var matches: int                 # league matches
var cup_matches: int = 0          # cup and continental matches
var cup_runs: Dictionary = {}     # competition -> how far we got
var wins: int
var draws: int
var losses: int
var points: int
var attendance_total: int
var attendance_avg: float
var fill_avg: float
var atmosphere_avg: float
var revenue: Dictionary = {}   # every income line (tickets, food, drinks, merch, premium, ...) + total
var costs: Dictionary = {}     # stands / facilities / utilities / total
var upkeep: float
var net: float                 # matchday revenue - upkeep (excludes construction)
var lost_food_sales: float
var food_unserved_share: float
var restroom_unserved_share: float
var build_spend: float
var land_spend: float
var demolish_refunds: float
var milestone_rewards: float
var event_income: float = 0.0
var board_bonus: float = 0.0     # paid by the board for objectives met (at the season's end)
var board_met: Array = []        # texts of the objectives met
var goals_for: int
var goals_against: int
var capacity_end: int
var best_attendance: int
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
	r.division = s.club.division
	r.division_name = s.config.division(s.club.division)["name"]
	r.promotion_points = -1
	r.position = s.league.position() if s.league else 0
	r.teams = s.league.teams.size() if s.league else 0
	r.matches = 0
	r.revenue = { "tickets": 0.0, "food": 0.0, "premium": 0.0, "total": 0.0 }
	r.costs = { "stands": 0.0, "facilities": 0.0, "utilities": 0.0, "total": 0.0 }
	r.build_spend = s.build_spend
	r.land_spend = s.land_spend
	r.demolish_refunds = s.demolish_refunds
	r.milestone_rewards = s.milestone_rewards
	r.event_income = s.event_income
	r.capacity_end = s.layout.capacity_total(s.config)
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
		if m.competition == "league":
			r.matches += 1
			match m.result:
				"W": r.wins += 1
				"D": r.draws += 1
				_: r.losses += 1
		else:
			r.cup_matches += 1
			var label := "%s: %s" % [m.comp_name, m.stage]
			var out := m.result == "L" or (m.result == "D" and m.penalties == "lost")
			if m.knockout:
				r.cup_runs[m.comp_name] = (m.stage + (" (won)" if m.stage == "Final" and not out else "")) if not out else "out in the " + m.stage.to_lower()
			else:
				r.cup_runs[m.comp_name] = "group stage"
		r.attendance_total += m.attendance
		fill_sum += float(m.attendance) / max(1, m.capacity)
		atmos_sum += m.atmosphere
		for k in m.revenue:
			r.revenue[k] = float(r.revenue.get(k, 0.0)) + float(m.revenue[k])
		for k in m.costs:
			r.costs[k] = float(r.costs.get(k, 0.0)) + float(m.costs[k])
		r.upkeep += m.costs["total"]
		r.goals_for += m.home_goals
		r.goals_against += m.away_goals
		r.best_attendance = maxi(r.best_attendance, m.attendance)
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
			"opponent": m.opponent, "score": "%d-%d" % [m.home_goals, m.away_goals], "revenue": m.revenue["total"],
		})
	r.points = 3 * r.wins + r.draws
	var all := r.matches + r.cup_matches
	if all > 0:
		r.attendance_avg = float(r.attendance_total) / all
		r.fill_avg = fill_sum / all
		r.atmosphere_avg = atmos_sum / all
	r.food_unserved_share = float(lost["food"]) / max(1, want["food"])
	r.restroom_unserved_share = float(lost["restroom"]) / max(1, want["restroom"])
	return r


static func from_dict(d: Dictionary) -> SeasonReport:
	var r := SeasonReport.new()
	for key in d:
		if key == "rows":
			r.rows.assign(d[key])
		elif key in ["division", "promotion_points", "position", "teams", "season_number", "seed", "matches", "cup_matches", "wins", "draws", "losses", "points", "attendance_total",
				"goals_for", "goals_against", "capacity_end", "best_attendance"]:
			r.set(key, int(d[key]))
		else:
			r.set(key, d[key])
	return r


func to_dict() -> Dictionary:
	return {
		"layout_name": layout_name, "season_number": season_number, "seed": seed,
		"division": division, "division_name": division_name, "promotion_points": promotion_points, "position": position, "teams": teams, "promoted": promoted, "relegated": relegated, "matches": matches, "cup_matches": cup_matches, "cup_runs": cup_runs,
		"wins": wins, "draws": draws, "losses": losses, "points": points,
		"attendance_total": attendance_total, "attendance_avg": attendance_avg,
		"fill_avg": fill_avg, "atmosphere_avg": atmosphere_avg, "revenue": revenue,
		"costs": costs, "land_spend": land_spend, "demolish_refunds": demolish_refunds, "milestone_rewards": milestone_rewards, "event_income": event_income,
		"board_bonus": board_bonus, "board_met": board_met,
		"goals_for": goals_for, "goals_against": goals_against, "capacity_end": capacity_end, "best_attendance": best_attendance,
		"upkeep": upkeep, "net": net, "lost_food_sales": lost_food_sales,
		"food_unserved_share": food_unserved_share, "restroom_unserved_share": restroom_unserved_share,
		"build_spend": build_spend, "cash_start": cash_start, "cash_end": cash_end,
		"mood_start": mood_start, "mood_end": mood_end,
		"fanbase_start": fanbase_start, "fanbase_end": fanbase_end, "rows": rows,
	}


## Average crowd over the home games (away games have nobody in your ground).
func home_avg() -> float:
	var n := 0
	var sum := 0
	for row in rows:
		if int(row.get("attendance", 0)) > 0:
			n += 1
			sum += int(row["attendance"])
	return float(sum) / n if n > 0 else 0.0


## Everything that came in or went out over the season (cash_end - cash_start).
func profit() -> float:
	return net + demolish_refunds + milestone_rewards + event_income - build_spend - land_spend


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
