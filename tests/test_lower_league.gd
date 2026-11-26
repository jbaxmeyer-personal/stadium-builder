extends GutTest
## The lower-league kit: grass banks share the terrace's fans, have no roof or
## tiers; tea bars feed fans at halftime from outside; a new ground has slim masts.

var config: SimConfig


func before_each() -> void:
	config = SimConfig.load_default()


func _season() -> Season:
	var s := Season.create(config, Layout.create(config, "ll"), 5)
	s.club.cash = 1e8
	s.club.peak_fanbase = 1e9
	return s


func test_a_bank_shares_the_terrace_crowd() -> void:
	var s := _season()
	var p := s.layout.pitch
	assert_eq(s.build_stand(Stand.make("N", "terrace", 0, p.size.x, 3)), "")
	var club := ClubState.create(config)
	club.fanbase = 60000.0
	var alone := MatchdaySim.run(config, s.layout, club, Fixture.make("X"), 1)
	assert_eq(s.build_stand(Stand.make("S", "bank", 0, p.size.x, 3)), "")
	var both := MatchdaySim.run(config, s.layout, club, Fixture.make("X"), 1)
	var demand: int = alone.demand["terrace"]
	assert_false(both.demand.has("bank"), "no demand of its own")
	assert_lte(both.stands[0]["attendance"] + both.stands[1]["attendance"], demand, "the two share one pool")
	assert_gt(both.stands[1]["attendance"], 0)


func test_banks_stay_simple() -> void:
	var s := _season()
	var p := s.layout.pitch
	assert_ne(s.build_stand(Stand.make_corner("NE", "bank", 3)), "", "not in a corner")
	assert_eq(s.build_stand(Stand.make("N", "bank", 0, p.size.x, 3)), "")
	assert_ne(s.restyle_stand(0, "gable", ""), "", "no roof")
	assert_ne(s.set_tiers(0, 2), "", "no tiers")
	assert_lt(Layout.stand_cost(s.layout.stands[0], config), Layout.stand_cost(Stand.make("N", "terrace", 0, p.size.x, 3), config), "cheaper than a terrace")


func test_tea_bar_serves_from_outside() -> void:
	var s := _season()
	var p := s.layout.pitch
	assert_eq(s.build_stand(Stand.make("S", "terrace", 0, p.size.x, 3)), "")
	assert_eq(s.build_facility(Facility.make("tea_bar", Vector2i(p.get_center().x, p.end.y + 6))), "")
	assert_eq(s.build_facility(Facility.make("clubhouse", Vector2i(s.layout.plot.position.x + 1, s.layout.plot.position.y + 1))), "")
	var r := s.play_next()
	while not r.home:
		r = s.play_next()
	assert_gt(float(r.revenue.get(MatchdaySim.REVENUE_BY_KIND["food"], 0.0)), 0.0, "halftime food sold")


func test_new_ground_defaults() -> void:
	var l := Layout.create(config, "x")
	assert_eq(l.floodlights, "slim")
	assert_eq(l.barrier, "none")
	var s := _season()
	assert_eq(s.set_pitchside("barrier", "fence"), "")
	assert_ne(s.set_pitchside("barrier", "lava"), "")
	var back := Layout.from_dict(JSON.parse_string(JSON.stringify(s.layout.to_dict())), config)
	assert_eq(back.barrier, "fence")
