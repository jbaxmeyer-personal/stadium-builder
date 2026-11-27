class_name ClubState
extends RefCounted
## State carried between matches: cash, fanbase, fan mood, recent form, ticket prices.

var cash: float
var fanbase: float                       # fans who want to come; grows with success
var mood: float
var recent_results: Array[String] = []  # "W" / "D" / "L", oldest first
var ticket_prices: Dictionary = {}       # stand type id -> price
# Cosmetic identity (the sim ignores these):
var club_name: String = "Riverside Town FC"
var stadium_name: String = "Riverside Park"
var sponsor: String = ""                 # naming-rights sponsor id, "" = none
var division: int = 0                   # index into the league ladder (0 = bottom)
var squad_budget: float = -1.0           # squad spend per match (wages); < 0 = the division's typical spend
var loan: float = 0.0                    # bank loan still owed
var loan_payment: float = 0.0            # fixed repayment of principal each match
var administration := false              # deep in debt: points deducted, wages capped until back in the black
var peak_fanbase: float = 0.0            # highest fanbase reached (milestones never un-happen)
var milestones: Array = []               # fan thresholds reached
var short_name: String = ""              # e.g. "Riverside"; "" = first word of the club name
var founded: int = 1887
var third_color: Color = Color(0.1, 0.1, 0.12)
## The crest (cosmetic): shape, split pattern, initials, symbol, stars, or an
## uploaded PNG (logo = a user:// path). Colours come from the club's three colours.
var badge: Dictionary = { "shape": "shield", "pattern": "plain", "text": "", "symbol": "ball", "stars": 0, "logo": "", "swap": false }
var primary_color: Color = Color(0.75, 0.08, 0.10)
var secondary_color: Color = Color(0.97, 0.97, 0.97)


static func create(config: SimConfig) -> ClubState:
	var c := ClubState.new()
	c.cash = config.num("economy/starting_cash")
	c.mood = config.num("mood/start")
	c.fanbase = config.num("demand/start_fanbase")
	c.peak_fanbase = c.fanbase
	for id in config.stand_type_ids():
		c.ticket_prices[id] = config.stand_type(id).reference_price
	return c


## The name on the ground: the sponsor's if there's a naming-rights deal.
func ground_name(config: SimConfig) -> String:
	if sponsor != "" and config.sponsors.has(sponsor):
		var sp: Dictionary = config.sponsors[sponsor]
		return "%s %s" % [sp["name"], sp["suffix"]]
	return stadium_name


## The squad spend per match actually used (the division norm until you set one).
func wage(config: SimConfig) -> float:
	return squad_budget if squad_budget >= 0.0 else float(config.division(division)["squad_wage"])


## The short name fans chant ("Riverside").
func nickname() -> String:
	return short_name if short_name != "" else club_name.split(" ")[0]


## Initials for the badge ("RTFC").
func initials() -> String:
	if String(badge.get("text", "")) != "":
		return badge["text"]
	var out := ""
	for w in club_name.split(" ", false):
		out += w[0]
	return out.to_upper().substr(0, 4)


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
	loan = maxf(0.0, loan - float(report.costs.get("loan_repaid", 0.0)))
	if loan <= 0.01:
		loan = 0.0
		loan_payment = 0.0
	mood = report.mood_after
	fanbase = report.fanbase_after
	peak_fanbase = maxf(peak_fanbase, fanbase)
	recent_results.append(report.result)


func to_dict() -> Dictionary:
	return {
		"cash": cash, "fanbase": fanbase, "mood": mood, "loan": loan, "loan_payment": loan_payment,
		"recent_results": recent_results, "ticket_prices": ticket_prices,
		"club_name": club_name, "stadium_name": stadium_name, "sponsor": sponsor,
		"peak_fanbase": peak_fanbase, "squad_budget": squad_budget, "administration": administration, "milestones": milestones, "division": division,
		"short_name": short_name, "founded": founded, "third_color": third_color.to_html(false), "badge": badge.duplicate(),
		"primary_color": primary_color.to_html(false),
		"secondary_color": secondary_color.to_html(false),
	}


static func from_dict(d: Dictionary, config: SimConfig) -> ClubState:
	var c := ClubState.create(config)
	c.cash = float(d["cash"])
	c.loan = float(d.get("loan", 0.0))
	c.loan_payment = float(d.get("loan_payment", 0.0))
	c.fanbase = float(d["fanbase"])
	c.mood = float(d["mood"])
	c.recent_results.assign(d["recent_results"])
	for id in d["ticket_prices"]:
		c.ticket_prices[id] = float(d["ticket_prices"][id])
	c.club_name = d.get("club_name", c.club_name)
	c.stadium_name = d.get("stadium_name", c.stadium_name)
	c.sponsor = d.get("sponsor", "")
	c.peak_fanbase = float(d.get("peak_fanbase", c.fanbase))
	c.milestones = d.get("milestones", [])
	c.division = int(d.get("division", 0))
	c.squad_budget = float(d.get("squad_budget", -1.0))
	c.administration = bool(d.get("administration", false))
	c.primary_color = Color.html(d.get("primary_color", c.primary_color.to_html(false)))
	c.secondary_color = Color.html(d.get("secondary_color", c.secondary_color.to_html(false)))
	c.short_name = d.get("short_name", "")
	c.founded = int(d.get("founded", 1887))
	c.third_color = Color.html(d.get("third_color", c.third_color.to_html(false)))
	var b: Variant = d.get("badge", {})
	if b is Dictionary:
		c.badge.merge(b as Dictionary, true)
	return c
