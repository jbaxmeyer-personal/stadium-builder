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
var land_spend: float = 0.0
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
	# Opponents and kick-off times come from their own RNG so they don't
	# change the match seeds.
	var names := RandomNumberGenerator.new()
	names.seed = seed * 7919 + season_number
	var pool := config.opponents.duplicate()
	for i in config.integer("season/matches"):
		var number := i + 1
		var opponent := "Match %d" % number
		if not pool.is_empty():
			opponent = pool.pop_at(names.randi_range(0, pool.size() - 1))
		var fx := Fixture.make(opponent, big.has(float(number)) or big.has(number))
		fx.evening = fx.big or number % config.integer("season/evening_every") == 0
		var roll := names.randf()
		var winter: Array = config.value("weather/winter_matches")
		if winter.has(float(number)) and roll < config.num("weather/snow_chance"):
			fx.weather = "snow"
		elif roll > 1.0 - config.num("weather/rain_chance"):
			fx.weather = "rain"
		fixtures.append(fx)
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
	report.milestones = check_milestones()
	reports.append(report)
	return report


## Milestones reached by the fanbase so far that haven't been celebrated yet.
## Pays their reward and returns them (for the matchday banner).
func check_milestones() -> Array:
	var new := []
	for m in config.milestones:
		var fans := float(m["fans"])
		if club.peak_fanbase >= fans and not club.milestones.has(fans):
			club.milestones.append(fans)
			club.cash += float(m["reward"])
			new.append(m)
	return new


## Locked things open up as the fanbase grows (see data/milestones.json).
func is_unlocked(id: String) -> bool:
	return club.peak_fanbase >= config.unlock_fans(id)


func _locked_error(id: String, what: String) -> String:
	return "" if is_unlocked(id) else "%s unlocks at %s fans" % [what, money(config.unlock_fans(id)).substr(1)]


func play_all() -> SeasonReport:
	while not is_over():
		play_next()
	return summary()


## Archives the finished season and sets up the next one.
## True if this season's points are enough to go up a division.
func promotion_earned() -> bool:
	var target := int(config.division(club.division)["promotion_points"])
	return target >= 0 and summary().points >= target


## Points still needed for promotion this season (0 = done, -1 = top division).
func points_to_promotion() -> int:
	var target := int(config.division(club.division)["promotion_points"])
	if target < 0:
		return -1
	return maxi(0, target - summary().points)


func start_next_season() -> void:
	assert(is_over(), "Season still running")
	var sr := summary()
	sr.promoted = promotion_earned()
	history.append(sr)
	if sr.promoted:
		club.division += 1
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
	if config.facility_types.has(facility.type_id):
		var locked := _locked_error(facility.type_id, config.facility_type(facility.type_id).display_name)
		if locked != "":
			return locked
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
			s.offset = 0 if s.is_corner() else offset
			s.length = depth if s.is_corner() else length
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
	var resized := Stand.make(s.side, s.type_id, offset, length, depth, s.setback)
	resized.shape = s.shape
	resized.tiers = s.tiers
	var cost := Layout.stand_cost(resized, config) - Layout.stand_cost(s, config)
	return cost if cost >= 0.0 else cost * config.num("season/demolish_refund_fraction")


## Cosmetic: roof style and seat colour. Free.
func restyle_stand(index: int, roof: String, seat_color: String) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	if not roof in Stand.ROOF_STYLES:
		return "unknown roof style '%s'" % roof
	layout.stands[index].roof = roof
	layout.stands[index].seat_color = seat_color
	return ""


## Add or remove upper tiers. Costs (or refunds) the difference; concourse
## items on a removed level go with it.
func set_tiers(index: int, tiers: int) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	var s := layout.stands[index]
	if tiers > s.tiers:
		var locked := _locked_error("tier%d" % tiers, "A %s tier" % ["", "", "second", "third"][mini(tiers, 3)])
		if locked != "":
			return locked
	var old := s.tiers
	var old_facilities := layout.facilities.duplicate()
	return _modify(func():
			s.tiers = tiers
			_drop_orphan_facilities(),
		func():
			s.tiers = old
			layout.facilities.assign(old_facilities))


func tier_cost(index: int, tiers: int) -> float:
	var s := layout.stands[index]
	var t := Stand.from_dict(s.to_dict())
	t.tiers = tiers
	var cost := Layout.stand_cost(t, config) - Layout.stand_cost(s, config)
	return cost if cost >= 0.0 else cost * config.num("season/demolish_refund_fraction")


## Sign (or end) a naming-rights deal. "" ends it.
func set_sponsor(id: String) -> String:
	if id != "" and not config.sponsors.has(id):
		return "unknown sponsor '%s'" % id
	if id != "":
		var locked := _locked_error("naming_rights", "Naming rights")
		if locked != "":
			return locked
	club.sponsor = id
	return ""


## Naming-rights fee per match for a sponsor at the current capacity.
func sponsor_fee(id: String) -> float:
	return MatchdaySim.naming_fee(config, id, layout.capacity_total(config))


## Cosmetic: stand cladding. Free.
func set_facade(index: int, facade: String) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	if not facade in Stand.FACADES:
		return "unknown facade '%s'" % facade
	layout.stands[index].facade = facade
	return ""


## Cosmetic: mowing pattern. Free.
func set_pitch_pattern(p: String) -> String:
	if not p in Layout.PITCH_PATTERNS:
		return "unknown pitch pattern '%s'" % p
	layout.pitch_pattern = p
	return ""


## Cosmetic: floodlight style. Free.
func set_floodlights(style: String) -> String:
	if not style in Layout.FLOODLIGHT_STYLES:
		return "unknown floodlight style '%s'" % style
	layout.floodlights = style
	return ""


## Price of the next strip of land on a side ("" if none left there). Each
## strip costs more than the last, wherever you bought it.
func land_cost(side: String) -> float:
	var l := layout
	if l.land[side] >= config.integer("land/max_strips_per_side"):
		return -1.0
	var along := l.plot.size.x if side == "N" or side == "S" else l.plot.size.y
	var bought := 0
	for k in l.land:
		bought += l.land[k]
	return along * l.strip_tiles * config.num("land/price_per_tile") * (1.0 + config.num("land/price_growth") * bought)


func buy_land(side: String) -> String:
	if not side in Layout.LAND_SIDES:
		return "unknown side '%s'" % side
	var cost := land_cost(side)
	if cost < 0.0:
		return "no more land for sale on that side"
	if cost > club.cash:
		return "land costs %s, you have %s" % [money(cost), money(club.cash)]
	club.cash -= cost
	land_spend += cost
	layout.land[side] += 1
	layout.update_plot()
	return ""


## Square or rounded corner. Changes capacity, so it costs (or refunds) the difference.
func set_corner_shape(index: int, shape: String) -> String:
	if index < 0 or index >= layout.stands.size() or not layout.stands[index].is_corner():
		return "not a corner stand"
	if not shape in Stand.CORNER_SHAPES:
		return "unknown shape '%s'" % shape
	var s := layout.stands[index]
	var old := s.shape
	return _modify(func():
			s.shape = shape
			_drop_orphan_facilities(),
		func(): s.shape = old)


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


## Facilities that no longer have somewhere to sit (their concourse or stand
## went, or a stand now covers them) are removed.
func _drop_orphan_facilities() -> void:
	var ctx := layout.placement_context(config)
	var kept: Array[Facility] = []
	for f in layout.facilities:
		if layout.facility_error(f, config, ctx) == "":
			kept.append(f)
	layout.facilities = kept


## Cosmetic: change a facility's style. Free.
func restyle_facility(index: int, style: String) -> String:
	if index < 0 or index >= layout.facilities.size():
		return "no facility %d" % index
	if not style in config.facility_type(layout.facilities[index].type_id).styles:
		return "unknown style '%s'" % style
	layout.facilities[index].style = style
	return ""


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


# --- Save / load -------------------------------------------------------------

const SAVE_VERSION := 1


## Everything needed to carry on exactly where the player left off.
func to_save() -> Dictionary:
	var fx := []
	for f in fixtures:
		fx.append({ "opponent": f.opponent, "big": f.big, "evening": f.evening, "weather": f.weather })
	var played := []
	for r in reports:
		played.append(r.to_dict())
	var past := []
	for h in history:
		past.append(h.to_dict())
	return {
		"version": SAVE_VERSION, "seed": seed, "season_number": season_number,
		"rng_state": str(_rng.state), "fixtures": fx, "match_seeds": match_seeds,
		"reports": played, "history": past,
		"build_spend": build_spend, "demolish_refunds": demolish_refunds,
		"start_cash": start_cash, "start_mood": start_mood, "start_fanbase": start_fanbase,
		"layout": layout.to_dict(), "club": club.to_dict(),
	}


static func from_save(p_config: SimConfig, d: Dictionary) -> Season:
	var s := Season.new()
	s.config = p_config
	s.layout = Layout.from_dict(d["layout"], p_config)
	s.club = ClubState.from_dict(d["club"], p_config)
	s.seed = int(d["seed"])
	s.season_number = int(d["season_number"])
	s._rng.seed = s.seed
	s._rng.state = int(d["rng_state"])
	for f in d["fixtures"]:
		var fx := Fixture.make(f["opponent"], bool(f["big"]))
		fx.evening = bool(f.get("evening", false))
		fx.weather = f.get("weather", "clear")
		s.fixtures.append(fx)
	for m in d["match_seeds"]:
		s.match_seeds.append(int(m))
	for r in d["reports"]:
		s.reports.append(MatchdayReport.from_dict(r))
	for h in d.get("history", []):
		s.history.append(SeasonReport.from_dict(h))
	s.build_spend = float(d["build_spend"])
	s.demolish_refunds = float(d["demolish_refunds"])
	s.start_cash = float(d["start_cash"])
	s.start_mood = float(d["start_mood"])
	s.start_fanbase = float(d["start_fanbase"])
	return s


func save_file(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_save(), "  ", true, true))  # full float precision
	return OK


static func load_file(p_config: SimConfig, path: String) -> Season:
	if not FileAccess.file_exists(path):
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or int(data.get("version", 0)) != SAVE_VERSION:
		return null
	return from_save(p_config, data)


func summary() -> SeasonReport:
	return SeasonReport.from_season(self)
