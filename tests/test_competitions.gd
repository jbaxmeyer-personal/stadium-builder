extends GutTest
## Cups and continental nights: midweek evening matches with draws, prize
## money and knockouts (penalties when level); the top eight of the First
## Division go into the continental competitions the season after.

var config: SimConfig


func before_each() -> void:
	config = SimConfig.load_default()


func _season(seed := 4) -> Season:
	var s := Season.create(config, Layout.create(config, "cup"), seed)
	s.club.cash = 1e9
	assert_eq(s.build_stand(Stand.make("S", "seated", 0, s.layout.pitch.size.x, 6)), "")
	return s


func test_the_cup_draw_and_a_knockout_run() -> void:
	var s := _season()
	var cups := s.fixtures.filter(func(f: Fixture) -> bool: return f.competition == "cup")
	assert_eq(cups.size(), 1, "only the first round is drawn at the start")
	var fx: Fixture = cups[0]
	assert_true(fx.evening, "midweek, under the lights")
	assert_true(fx.knockout)
	assert_eq(s.draws.size(), 1)
	s.club.squad_budget = 1e7   # strong enough to keep winning
	while not s.is_over():
		s.play_next()
	var played := s.reports.filter(func(r: MatchdayReport) -> bool: return r.competition == "cup")
	assert_gt(played.size(), 1, "a strong side goes through some rounds")
	for r in played:
		if r.result == "D":
			assert_true(r.penalties in ["won", "lost"], "level knockouts go to penalties")
	var sr := s.summary()
	assert_eq(sr.matches, 2 * (config.integer("league/teams") - 1), "league matches counted on their own")
	assert_true(sr.cup_runs.has(config.cup["name"]))


func test_cup_wins_pay_prize_money() -> void:
	var s := _season(7)
	s.club.squad_budget = 1e7
	while not s.is_over():
		var r := s.play_next()
		if r.competition == "cup" and r.result == "W":
			assert_gt(float(r.revenue.get("prize", 0.0)), 0.0)
			return
	pass_test("no cup win this season")


func test_top_eight_play_continental_football() -> void:
	var s := _season(3)
	s.club.division = config.divisions.size() - 1
	s.league = League.create(config, 99, s.club.division, s.club.club_name)
	s.club.squad_budget = 1e8
	s._make_fixtures()
	while not s.is_over():
		s.play_next()
	var pos := s.position()
	s.start_next_season()
	if pos <= 8:
		assert_false(s.continental.is_empty())
		var cont := s.fixtures.filter(func(f: Fixture) -> bool: return f.competition == "continental")
		assert_eq(cont.size(), 6, "six group nights")
	else:
		assert_true(s.continental.is_empty())


func test_competition_save_round_trip() -> void:
	var s := _season()
	for k in 8:
		s.play_next()
	var back := Season.from_save(config, JSON.parse_string(JSON.stringify(s.to_save())))
	assert_eq(back.fixtures.size(), s.fixtures.size())
	assert_eq(back.draws.size(), s.draws.size())
	while not s.is_over():
		var a := s.play_next()
		var b := back.play_next()
		assert_eq(a.home_goals, b.home_goals)
		assert_eq(a.competition, b.competition)


func test_night_matches_draw_fewer_families() -> void:
	var club := ClubState.create(config)
	var day := Fixture.make("X")
	var night := Fixture.make("X")
	night.evening = true
	var d1 := MatchdaySim.compute_demand(config, club, MatchdaySim.demand_multipliers(config, club, day, 0.0))
	var d2 := MatchdaySim.compute_demand(config, club, MatchdaySim.demand_multipliers(config, club, night, 0.0))
	assert_lt(int(d2["family"]), int(d1["family"]))
	assert_gt(int(d2["seated"]), int(d1["seated"]))
