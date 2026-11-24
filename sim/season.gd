class_name Season
extends RefCounted
## A mini-season of home matches on one layout. The layout is built up front
## out of starting cash. Between matches the player may build, demolish and
## change prices; the club state (cash, form, mood) carries match to match.
## Match seeds are derived from the season seed, so same layout + seed = same season.

var config: SimConfig
var layout: Layout
var club: ClubState
var seed: int
var fixtures: Array[Fixture] = []
var match_seeds: Array[int] = []
var reports: Array[MatchdayReport] = []
var build_spend: float = 0.0       # total spent on construction this season
var demolish_refunds: float = 0.0


static func create(p_config: SimConfig, p_layout: Layout, p_seed: int) -> Season:
	var s := Season.new()
	s.config = p_config
	s.layout = p_layout
	s.seed = p_seed
	s.club = ClubState.create(p_config)
	s.build_spend = p_layout.build_cost(p_config)
	s.club.cash -= s.build_spend
	var big: Array = p_config.value("season/big_match_numbers")
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	for i in p_config.integer("season/matches"):
		var number := i + 1
		s.fixtures.append(Fixture.make("Match %d" % number, big.has(float(number)) or big.has(number)))
		s.match_seeds.append(rng.randi())
	return s


func is_over() -> bool:
	return reports.size() >= fixtures.size()


func next_match_number() -> int:
	return reports.size() + 1


func play_next() -> MatchdayReport:
	assert(not is_over(), "Season is over")
	var i := reports.size()
	var report := MatchdaySim.run(config, layout, club, fixtures[i], match_seeds[i])
	club.apply_report(report)
	reports.append(report)
	return report


func play_all() -> SeasonReport:
	while not is_over():
		play_next()
	return summary()


# --- Player commands between matches -------------------------------------
# Each returns an error string ("" on success) and leaves state unchanged on error.

func set_ticket_price(type_id: String, price: float) -> String:
	if not config.stand_types.has(type_id):
		return "unknown stand type '%s'" % type_id
	if price < 0.0:
		return "price must be >= 0"
	club.ticket_prices[type_id] = price
	return ""


func build_stand(stand: Stand) -> String:
	return _build(func(): layout.stands.append(stand),
		func(): layout.stands.erase(stand))


func build_facility(facility: Facility) -> String:
	return _build(func(): layout.facilities.append(facility),
		func(): layout.facilities.erase(facility))


func demolish_stand(index: int) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	var before := layout.build_cost(config)
	layout.stands.remove_at(index)
	# Facilities left off any concourse go with the stand.
	var concourse := layout.concourse_tile_map(config)
	var kept: Array[Facility] = []
	for f in layout.facilities:
		if concourse.has(f.pos):
			kept.append(f)
	layout.facilities = kept
	_refund(before - layout.build_cost(config))
	return ""


func demolish_facility(index: int) -> String:
	if index < 0 or index >= layout.facilities.size():
		return "no facility %d" % index
	var before := layout.build_cost(config)
	layout.facilities.remove_at(index)
	_refund(before - layout.build_cost(config))
	return ""


func _build(add: Callable, undo: Callable) -> String:
	var before := layout.build_cost(config)
	add.call()
	var cost := layout.build_cost(config) - before
	var errors := layout.validate(config)
	if not errors.is_empty():
		undo.call()
		return "; ".join(errors)
	if cost > club.cash:
		undo.call()
		return "costs %.0f, only %.0f cash" % [cost, club.cash]
	club.cash -= cost
	build_spend += cost
	return ""


func _refund(value: float) -> void:
	var refund := value * config.num("season/demolish_refund_fraction")
	club.cash += refund
	demolish_refunds += refund


func summary() -> SeasonReport:
	return SeasonReport.from_season(self)
