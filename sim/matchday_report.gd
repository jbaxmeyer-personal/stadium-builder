class_name MatchdayReport
extends RefCounted
## Everything one matchday produced. Plain data so it can be compared/printed.

var layout_name: String
var opponent: String
var big_match: bool
var seed: int

var demand_multipliers: Dictionary = {}  # form, opponent, mood, noise
var demand: Dictionary = {}              # stand type -> fans wanting tickets
var stands: Array[Dictionary] = []       # label, type, capacity, attendance, fill, proximity
var attendance: int
var capacity: int

var atmosphere: float
var home_advantage: float
var probabilities: Dictionary = {}       # win / draw / loss
var roll: float
var result: String

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
		"attendance": attendance, "capacity": capacity,
		"atmosphere": atmosphere, "home_advantage": home_advantage,
		"probabilities": probabilities, "roll": roll, "result": result,
		"facilities": facilities, "halftime": halftime,
		"revenue": revenue, "lost_food_sales": lost_food_sales, "costs": costs, "net": net,
		"mood_before": mood_before, "mood_change": mood_change, "mood_after": mood_after,
		"fanbase_before": fanbase_before, "fanbase_growth": fanbase_growth, "fanbase_after": fanbase_after,
	}


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
	lines.append("ATMOSPHERE  %.1f / 100   home advantage +%.3f" % [atmosphere, home_advantage])
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
	lines.append("  food      %10.0f   (lost sales %.0f)" % [revenue["food"], lost_food_sales])
	lines.append("  premium   %10.0f" % revenue["premium"])
	lines.append("  revenue   %10.0f" % revenue["total"])
	lines.append("  upkeep    %10.0f   (stands %.0f, facilities %.0f)" % [
		-costs["total"], costs["stands"], costs["facilities"]])
	lines.append("  NET       %10.0f" % net)
	lines.append("")
	lines.append("FAN MOOD  %.1f -> %.1f  (result %+.1f, atmosphere %+.1f, service %+.1f, recovery %+.1f)" % [
		mood_before, mood_after, mood_change["result"], mood_change["atmosphere"], mood_change["service"],
		mood_change["recovery"]])
	lines.append("FANBASE  %.0f -> %.0f  (%+.1f%%: base %+.1f, result %+.1f, mood %+.1f, atmosphere %+.1f)" % [
		fanbase_before, fanbase_after, 100.0 * fanbase_growth["total"], 100.0 * fanbase_growth["base"],
		100.0 * fanbase_growth["result"], 100.0 * fanbase_growth["mood"], 100.0 * fanbase_growth["atmosphere"]])
	return "\n".join(lines)
