class_name MatchdayReport
extends RefCounted
## Everything one matchday produced. Plain data so it can be compared/printed.

var layout_name: String
var opponent: String
var big_match: bool
var seed: int

var demand_multipliers: Dictionary = {}  # form, opponent, mood, noise
var demand: Dictionary = {}              # stand type -> fans wanting tickets
var layout_facilities: Array[String] = []  # facility type ids present this match
var milestones: Array = []
var sponsor: String = ""               # milestones reached after this match (set by Season)
var transport_capacity: float
var transport_turned_away: int
var atmosphere_bonus: float
var utilities: Dictionary = {}           # power / water units used
var stands: Array[Dictionary] = []       # label, type, capacity, attendance, fill, proximity
var attendance: int
var capacity: int

var atmosphere: float
var home_advantage: float
var probabilities: Dictionary = {}       # win / draw / loss
var roll: float
var result: String
var home_goals: int
var away_goals: int
var evening: bool

var facilities: Array[Dictionary] = []   # per-facility queue results
var halftime: Dictionary = {}            # kind -> {wanting, served, lost, unreachable}

var revenue: Dictionary = {}             # tickets / food / premium / total
var lost_food_sales: float
var costs: Dictionary = {}               # stand_upkeep / facility_upkeep / total
var net: float

var mood_before: float
var mood_change: Dictionary = {}         # result / atmosphere / service / total
var mood_after: float

var fanbase_before: float
var fanbase_growth: Dictionary = {}       # base / result / mood / atmosphere / headroom / total
var fanbase_after: float


func to_dict() -> Dictionary:
	return {
		"layout_name": layout_name, "opponent": opponent, "big_match": big_match, "seed": seed,
		"demand_multipliers": demand_multipliers, "demand": demand, "stands": stands,
		"layout_facilities": layout_facilities, "transport_capacity": transport_capacity,
		"transport_turned_away": transport_turned_away, "atmosphere_bonus": atmosphere_bonus,
		"utilities": utilities, "milestones": milestones, "sponsor": sponsor,
		"attendance": attendance, "capacity": capacity,
		"atmosphere": atmosphere, "home_advantage": home_advantage,
		"probabilities": probabilities, "roll": roll, "result": result,
		"home_goals": home_goals, "away_goals": away_goals, "evening": evening,
		"facilities": facilities, "halftime": halftime,
		"revenue": revenue, "lost_food_sales": lost_food_sales, "costs": costs, "net": net,
		"mood_before": mood_before, "mood_change": mood_change, "mood_after": mood_after,
		"fanbase_before": fanbase_before, "fanbase_growth": fanbase_growth, "fanbase_after": fanbase_after,
	}


static func from_dict(d: Dictionary) -> MatchdayReport:
	var r := MatchdayReport.new()
	for key in d:
		match key:
			"stands":
				r.stands.assign(d[key])
				for st in r.stands:
					st["capacity"] = int(st["capacity"])
					st["attendance"] = int(st["attendance"])
			"facilities":
				r.facilities.assign(d[key])
				for f in r.facilities:
					for k in ["arrivals", "served", "lost"]:
						f[k] = int(f[k])
			"halftime":
				r.halftime = d[key]
				for kind in r.halftime:
					for k in r.halftime[kind]:
						r.halftime[kind][k] = int(r.halftime[kind][k])
			"demand":
				r.demand = d[key]
				for k in r.demand:
					r.demand[k] = int(r.demand[k])
			"seed", "attendance", "capacity", "transport_turned_away", "home_goals", "away_goals": r.set(key, int(d[key]))
			"layout_facilities": r.layout_facilities.assign(d[key])
			_: r.set(key, d[key])
	return r


func to_text() -> String:
	var lines := PackedStringArray()
	lines.append("=== MATCHDAY REPORT: %s ===" % layout_name)
	lines.append("vs %s%s   seed %d" % [opponent, " (BIG MATCH)" if big_match else "", seed])
	lines.append("")
	lines.append("DEMAND  form x%.2f  opponent x%.2f  mood x%.2f  noise x%.3f" % [
		demand_multipliers["form"], demand_multipliers["opponent"],
		demand_multipliers["mood"], demand_multipliers["noise"]])
	for t in demand:
		lines.append("  %-8s %6d fans" % [t, demand[t]])
	lines.append("")
	lines.append("ATTENDANCE  %d / %d (%.0f%%)" % [attendance, capacity, 100.0 * attendance / max(1, capacity)])
	for s in stands:
		lines.append("  %-12s %6d / %6d  fill %3.0f%%  prox %.1f" % [
			s["label"], s["attendance"], s["capacity"], 100.0 * s["fill"], s["proximity"]])
	lines.append("")
	if transport_turned_away > 0:
		lines.append("TRANSPORT  only %d could get here; %d turned away" % [transport_capacity, transport_turned_away])
	lines.append("ATMOSPHERE  %.1f / 100 (incl. +%.1f from screens/sound)   home advantage +%.3f" % [atmosphere, atmosphere_bonus, home_advantage])
	lines.append("SCORE  %d - %d%s" % [home_goals, away_goals, "   (evening kick-off)" if evening else ""])
	lines.append("RESULT  %s   (P win %.2f / draw %.2f / loss %.2f, roll %.3f)" % [
		result, probabilities["win"], probabilities["draw"], probabilities["loss"], roll])
	lines.append("")
	lines.append("HALFTIME")
	for kind in halftime:
		var h: Dictionary = halftime[kind]
		lines.append("  %-8s want %5d  served %5d  lost %5d (%d no facility reachable)" % [
			kind, h["wanting"], h["served"], h["lost"], h["unreachable"]])
	for f in facilities:
		lines.append("    %-18s in %5d  served %5d  lost %5d  walk %4.1fm  wait avg %4.1fm max %5.1fm" % [
			f["label"], f["arrivals"], f["served"], f["lost"], f["round_trip_min"],
			f["wait_avg_min"], f["wait_max_min"]])
	lines.append("")
	lines.append("MONEY")
	lines.append("  tickets   %10.0f" % revenue["tickets"])
	lines.append("  food      %10.0f   (lost sales, all kinds %.0f)" % [revenue["food"], lost_food_sales])
	lines.append("  drinks    %10.0f" % revenue.get("drinks", 0.0))
	lines.append("  merch     %10.0f" % revenue.get("merch", 0.0))
	lines.append("  premium   %10.0f" % revenue["premium"])
	lines.append("  sponsors  %10.0f" % revenue.get("sponsors", 0.0))
	lines.append("  boxes     %10.0f" % revenue.get("boxes", 0.0))
	lines.append("  venue     %10.0f" % revenue.get("venue", 0.0))
	lines.append("  naming    %10.0f" % revenue.get("naming", 0.0))
	lines.append("  revenue   %10.0f" % revenue["total"])
	lines.append("  costs     %10.0f   (stands %.0f, facilities %.0f, utilities %.0f)" % [
		-costs["total"], costs["stands"], costs["facilities"], costs.get("utilities", 0.0)])
	lines.append("  NET       %10.0f" % net)
	lines.append("")
	lines.append("FAN MOOD  %.1f -> %.1f  (result %+.1f, atmosphere %+.1f, service %+.1f, care %+.1f, recovery %+.1f)" % [
		mood_before, mood_after, mood_change["result"], mood_change["atmosphere"], mood_change["service"],
		mood_change.get("care", 0.0), mood_change["recovery"]])
	lines.append("FANBASE  %.0f -> %.0f  (%+.1f%%: base %+.1f, result %+.1f, mood %+.1f, atmosphere %+.1f)" % [
		fanbase_before, fanbase_after, 100.0 * fanbase_growth["total"], 100.0 * fanbase_growth["base"],
		100.0 * fanbase_growth["result"], 100.0 * fanbase_growth["mood"], 100.0 * fanbase_growth["atmosphere"]])
	return "\n".join(lines)
