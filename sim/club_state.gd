class_name ClubState
extends RefCounted
## State carried between matches: cash, fan mood, recent form, ticket prices.

var cash: float
var mood: float
var recent_results: Array[String] = []  # "W" / "D" / "L", oldest first
var ticket_prices: Dictionary = {}       # stand type id -> price


static func create(config: SimConfig) -> ClubState:
	var c := ClubState.new()
	c.cash = config.num("economy/starting_cash")
	c.mood = config.num("mood/start")
	for id in config.stand_type_ids():
		c.ticket_prices[id] = config.stand_type(id).reference_price
	return c


func price(type_id: String) -> float:
	return float(ticket_prices[type_id])


## Points per game over the form window; neutral value if no matches yet.
func form_ppg(config: SimConfig) -> float:
	if recent_results.is_empty():
		return config.num("demand/form_neutral_ppg")
	var window := recent_results.slice(-config.integer("demand/form_window"))
	var pts := 0.0
	for r in window:
		pts += 3.0 if r == "W" else (1.0 if r == "D" else 0.0)
	return pts / window.size()


func apply_report(report: MatchdayReport) -> void:
	cash += report.net
	mood = report.mood_after
	recent_results.append(report.result)
