extends GutTest
## Getting in: turnstiles and stairs limit how fast fans reach their seats;
## upper tiers need climbing capacity; late fans cost mood.

var config: SimConfig


func before_each() -> void:
	config = SimConfig.load_default()


func _stands(att: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{ "attendance": att, "capacity": att }]
	return out


func test_too_few_gates_makes_fans_late() -> void:
	var l := Layout.create(config, "in")
	var s := Stand.make("S", "seated", 0, l.pitch.size.x, 10)
	l.stands.append(s)
	s.gates = 1
	var few := MatchdaySim.simulate_ingress(config, l, _stands(7000))
	s.gates = 8
	var many := MatchdaySim.simulate_ingress(config, l, _stands(7000))
	assert_gt(int(few["late"]), 0, "one gate can't take a big crowd")
	assert_lt(int(many["late"]), int(few["late"]))
	assert_lt(float(many["wait"]), float(few["wait"]))


func test_upper_tiers_need_stairs() -> void:
	var s := Season.create(config, Layout.create(config, "in"), 1)
	s.club.cash = 1e9
	s.club.peak_fanbase = 1e9
	var p := s.layout.pitch
	for k in 3:
		s.buy_land("S")
	assert_eq(s.build_stand(Stand.make("S", "seated", 0, 12, 8)), "")
	assert_eq(s.set_tiers(0, 2), "")
	s.layout.stands[0].gates = 40
	var before := MatchdaySim.simulate_ingress(config, s.layout, _stands(9000))
	var conc := s.layout.stand_concourse(s.layout.stands[0], config)
	var placed := 0
	for t in conc:
		if placed < 3 and s.build_facility(Facility.make("escalator", t)) == "":
			placed += 1
	assert_gt(placed, 0, "escalators fit on the concourse")
	var after := MatchdaySim.simulate_ingress(config, s.layout, _stands(9000))
	assert_gt(float(after["stands"][0]["climb_rate"]), float(before["stands"][0]["climb_rate"]))
	assert_lt(int(after["late"]), int(before["late"]), "escalators get people up faster")


func test_late_fans_cost_mood_and_save() -> void:
	var s := Season.create(config, Layout.create(config, "in"), 2)
	s.club.cash = 1e8
	s.club.fanbase = 40000.0
	assert_eq(s.build_stand(Stand.make("S", "terrace", 0, s.layout.pitch.size.x, 10)), "")
	s.layout.stands[0].gates = 1
	var r := s.play_next()
	while not r.home:
		r = s.play_next()
	assert_gt(int(r.ingress["late"]), 0)
	assert_lt(float(r.mood_change["late"]), 0.0)
	var back := MatchdayReport.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	assert_eq(int(back.ingress["late"]), int(r.ingress["late"]))


func test_ramp_tower_against_the_outside_of_a_stand_counts() -> void:
	var s := Season.create(config, Layout.create(config, "in"), 1)
	s.club.cash = 1e9
	s.club.peak_fanbase = 1e9
	for k in 4:
		s.buy_land("S")
	assert_eq(s.build_stand(Stand.make("S", "seated", 0, 12, 8)), "")
	assert_eq(s.set_tiers(0, 2), "")
	var before := MatchdaySim.simulate_ingress(config, s.layout, _stands(9000))
	var conc := s.layout.concourse_tile_map(config)
	var stand_tiles := s.layout.stand_tile_map()
	var placed := false
	for t in stand_tiles:
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var tile: Vector2i = t + d
			if placed or conc.has(tile) or stand_tiles.has(tile):
				continue
			if s.build_facility(Facility.make("spiral_ramp", tile)) == "":
				placed = true
	assert_true(placed, "a ramp tower fits against the stand")
	var f: Facility = s.layout.facilities[s.layout.facilities.size() - 1]
	assert_eq(s.layout.circulation_stand(f, config), 0)
	var after := MatchdaySim.simulate_ingress(config, s.layout, _stands(9000))
	assert_gt(float(after["stands"][0]["climb_rate"]), float(before["stands"][0]["climb_rate"]))
	# but not out in the open
	assert_ne(s.build_facility(Facility.make("spiral_ramp", s.layout.plot.position)), "")
