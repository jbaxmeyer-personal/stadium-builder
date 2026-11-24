class_name Season
extends RefCounted
## A running club: seasons of home matches on a layout that the player keeps
## building. Any starting layout is paid for out of starting cash. Between
## matches the player may build, resize, demolish and change prices; cash,
## fanbase, form and mood carry over, including across seasons.
## Match seeds come from one seeded RNG, so same layout + seed + commands = same game.

var config: SimConfig
var layout: Layout
var club: ClubState
var seed: int
var season_number: int = 1
var fixtures: Array[Fixture] = []
var match_seeds: Array[int] = []
var reports: Array[MatchdayReport] = []   # this season's matches
var history: Array[SeasonReport] = []     # finished seasons
var build_spend: float = 0.0              # construction spend this season
var demolish_refunds: float = 0.0
var start_cash: float                     # cash / mood / fanbase when this season began
var start_mood: float
var start_fanbase: float
var _rng := RandomNumberGenerator.new()


static func create(p_config: SimConfig, p_layout: Layout, p_seed: int) -> Season:
	var s := Season.new()
	s.config = p_config
	s.layout = p_layout
	s.seed = p_seed
	s.club = ClubState.create(p_config)
	s._mark_start()
	s.build_spend = p_layout.build_cost(p_config)
	s.club.cash -= s.build_spend
	s._rng.seed = p_seed
	s._make_fixtures()
	return s


func _mark_start() -> void:
	start_cash = club.cash
	start_mood = club.mood
	start_fanbase = club.fanbase


func _make_fixtures() -> void:
	fixtures.clear()
	match_seeds.clear()
	var big: Array = config.value("season/big_match_numbers")
	for i in config.integer("season/matches"):
		var number := i + 1
		fixtures.append(Fixture.make("Match %d" % number, big.has(float(number)) or big.has(number)))
		match_seeds.append(_rng.randi())


func is_over() -> bool:
	return reports.size() >= fixtures.size()


func next_match_number() -> int:
	return reports.size() + 1


func next_fixture() -> Fixture:
	return null if is_over() else fixtures[reports.size()]


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


## Archives the finished season and sets up the next one.
func start_next_season() -> void:
	assert(is_over(), "Season still running")
	history.append(summary())
	season_number += 1
	reports.clear()
	build_spend = 0.0
	demolish_refunds = 0.0
	_mark_start()
	_make_fixtures()


# --- Player commands between matches -------------------------------------
# Each returns an error string ("" on success) and leaves state unchanged on error.
# Growing something costs the build-cost difference; shrinking or demolishing
# refunds season/demolish_refund_fraction of it.

func set_ticket_price(type_id: String, price: float) -> String:
	if not config.stand_types.has(type_id):
		return "unknown stand type '%s'" % type_id
	if price < 0.0:
		return "price must be >= 0"
	club.ticket_prices[type_id] = price
	return ""


func build_stand(stand: Stand) -> String:
	return _modify(func(): layout.stands.append(stand), func(): layout.stands.erase(stand))


func build_facility(facility: Facility) -> String:
	return _modify(func(): layout.facilities.append(facility), func(): layout.facilities.erase(facility))


## Change a stand's footprint (e.g. add a row, extend along the side).
func resize_stand(index: int, offset: int, length: int, depth: int) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	var s := layout.stands[index]
	var old := [s.offset, s.length, s.depth]
	var old_facilities := layout.facilities.duplicate()
	return _modify(
		func():
			s.offset = offset
			s.length = length
			s.depth = depth
			_drop_orphan_facilities(),
		func():
			s.offset = old[0]
			s.length = old[1]
			s.depth = old[2]
			layout.facilities.assign(old_facilities))


## Cost of a resize without doing it (negative = refund).
func resize_cost(index: int, offset: int, length: int, depth: int) -> float:
	var s := layout.stands[index]
	var t := config.stand_type(s.type_id)
	var cost := (length * depth - s.length * s.depth) * t.capacity_per_tile * t.build_cost_per_place
	return cost if cost >= 0.0 else cost * config.num("season/demolish_refund_fraction")


func demolish_stand(index: int) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	var removed := layout.stands[index]
	var old_facilities := layout.facilities.duplicate()
	return _modify(
		func():
			layout.stands.remove_at(index)
			_drop_orphan_facilities(),
		func():
			layout.stands.insert(index, removed)
			layout.facilities.assign(old_facilities))


func demolish_facility(index: int) -> String:
	if index < 0 or index >= layout.facilities.size():
		return "no facility %d" % index
	var removed := layout.facilities[index]
	return _modify(func(): layout.facilities.remove_at(index),
		func(): layout.facilities.insert(index, removed))


## Facilities left off any concourse go with the stand.
func _drop_orphan_facilities() -> void:
	var concourse := layout.concourse_tile_map(config)
	var kept: Array[Facility] = []
	for f in layout.facilities:
		if concourse.has(f.pos):
			kept.append(f)
	layout.facilities = kept


func _modify(apply: Callable, undo: Callable) -> String:
	var before := layout.build_cost(config)
	apply.call()
	var errors := layout.validate(config)
	if not errors.is_empty():
		undo.call()
		return "; ".join(errors)
	var diff := layout.build_cost(config) - before
	if diff > 0.0 and diff > club.cash:
		undo.call()
		return "costs %s, you have %s" % [money(diff), money(club.cash)]
	if diff >= 0.0:
		club.cash -= diff
		build_spend += diff
	else:
		var refund := -diff * config.num("season/demolish_refund_fraction")
		club.cash += refund
		demolish_refunds += refund
	return ""


static func money(v: float) -> String:
	var neg := v < 0.0
	var s := str(roundi(absf(v)))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-£" if neg else "£") + s + out


func summary() -> SeasonReport:
	return SeasonReport.from_season(self)
