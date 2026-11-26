extends GutTest

var config: SimConfig


func before_all() -> void:
	config = SimConfig.load_default()


func _run(l: Layout, seed := 1, club: ClubState = null) -> MatchdayReport:
	var c := club if club else ClubState.create(config)
	var fx := Fixture.make("Rovers")
	fx.opponent_rating = League.rating_for_wage(c.wage(config))   # an even match
	return MatchdaySim.run(config, l, c, fx, seed)


func _one_stand(type_id: String, depth: int, setback := 0) -> Layout:
	var l := Layout.create(config, "t")
	l.stands.append(Stand.make("N", type_id, 0, 30, depth, setback))
	return l


func test_attendance_capped_and_overflow_lost() -> void:
	var club := ClubState.create(config)
	club.fanbase = 20000.0
	var r := _run(_one_stand("premium", 1), 1, club)  # 360 premium seats, far more demand
	assert_eq(r.attendance, r.capacity)
	assert_gt(r.demand["premium"], r.capacity)


func test_empty_seats_kill_atmosphere() -> void:
	var full := _run(_one_stand("terrace", 1))
	var half_empty := _run(_one_stand("terrace", 8))
	assert_lt(half_empty.stands[0]["fill"], 1.0)
	assert_gt(full.stands[0]["fill"] * full.stands[0]["noise"], half_empty.stands[0]["fill"] * half_empty.stands[0]["noise"])


func test_setback_lowers_atmosphere() -> void:
	assert_gt(_run(_one_stand("terrace", 3, 0)).atmosphere, _run(_one_stand("terrace", 3, 3)).atmosphere)


func test_no_stands_no_atmosphere() -> void:
	assert_eq(_run(Layout.create(config, "empty")).atmosphere, 0.0)


func test_higher_price_lowers_demand() -> void:
	var l := _one_stand("seated", 4)
	var cheap := ClubState.create(config)
	var dear := ClubState.create(config)
	dear.ticket_prices["seated"] = cheap.price("seated") * 2.0
	assert_lt(_run(l, 1, dear).demand["seated"], _run(l, 1, cheap).demand["seated"])


func test_atmosphere_raises_win_probability() -> void:
	var quiet := _run(_one_stand("premium", 1))
	var loud := _run(_one_stand("terrace", 3))
	assert_gt(loud.probabilities["win"], quiet.probabilities["win"])
	assert_almost_eq(loud.probabilities["win"] + loud.probabilities["draw"] + loud.probabilities["loss"], 1.0, 0.001)


func test_no_facilities_means_everyone_unserved() -> void:
	var r := _run(_one_stand("seated", 4))
	assert_eq(r.halftime["food"]["unreachable"], r.halftime["food"]["wanting"])
	assert_eq(r.revenue["food"], 0.0)
	assert_lt(r.mood_change["service"], 0.0)


func test_more_kiosks_fewer_lost_sales() -> void:
	var one := _one_stand("seated", 4)
	one.facilities.append(Facility.make("kiosk", Vector2i(30, 6)))
	var three := _one_stand("seated", 4)
	for x in [20, 30, 40]:
		three.facilities.append(Facility.make("kiosk", Vector2i(x, 6)))
	var big_crowd := ClubState.create(config)
	big_crowd.fanbase = 30000.0
	assert_lt(_run(three, 1, big_crowd).halftime["food"]["lost"], _run(one, 1, big_crowd).halftime["food"]["lost"])


func test_halftime_conserves_fans() -> void:
	var l := Layout.load_json("res://data/layouts/seated_bowl.json", config)
	var r := _run(l)
	for kind in r.halftime:
		var h: Dictionary = r.halftime[kind]
		assert_eq(h["served"] + h["lost"], h["wanting"], kind)


func test_revenue_adds_up() -> void:
	var r := _run(Layout.load_json("res://data/layouts/terrace_wall.json", config))
	assert_almost_eq(r.revenue["total"], r.revenue["tickets"] + r.revenue["food"] + r.revenue["premium"], 0.001)
	assert_almost_eq(r.net, r.revenue["total"] - r.costs["total"], 0.001)


func test_form_feeds_demand() -> void:
	var l := _one_stand("seated", 4)
	var winning := ClubState.create(config)
	winning.recent_results.assign(["W", "W", "W", "W", "W"])
	var losing := ClubState.create(config)
	losing.recent_results.assign(["L", "L", "L", "L", "L"])
	assert_gt(_run(l, 1, winning).demand["seated"], _run(l, 1, losing).demand["seated"])


func test_scoreline_matches_result() -> void:
	var l := Layout.load_json("res://data/layouts/seated_bowl.json", config)
	for seed in range(1, 40):
		var r := _run(l, seed)
		match r.result:
			"W": assert_gt(r.home_goals, r.away_goals)
			"L": assert_lt(r.home_goals, r.away_goals)
			_: assert_eq(r.home_goals, r.away_goals)
