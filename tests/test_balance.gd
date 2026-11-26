extends GutTest
## Money and strength at the extremes: a minimum-budget squad loses most
## games but not all; running costs and debt interest are real; deep debt
## means administration (points off, wages capped).

var config: SimConfig


func before_each() -> void:
	config = SimConfig.load_default()


func _season(seed := 7) -> Season:
	var s := Season.create(config, Layout.create(config, "b"), seed)
	s.club.cash = 5e6
	var p := s.layout.pitch
	assert_eq(s.build_stand(Stand.make("S", "terrace", 0, p.size.x, 4)), "")
	return s


func test_a_minimum_squad_struggles_but_wins_sometimes() -> void:
	var s := _season()
	assert_eq(s.set_squad_budget(config.num("league/min_squad_budget")), "")
	while not s.is_over():
		s.play_next()
	var row: Dictionary = s.league.table().filter(func(x: Dictionary) -> bool: return int(x["team"]) == 0)[0]
	var wins: int = row["w"]
	assert_gt(wins, 0, "a few wins even on no budget")
	assert_lt(wins, 14, "but mostly defeats")
	assert_gte(s.position(), 14, "near the bottom")


func test_running_costs_and_interest() -> void:
	var s := _season()
	var r := s.play_next()
	assert_gt(float(r.costs["overheads"]), 0.0)
	if r.home:
		assert_gt(float(r.costs["matchday"]), 0.0, "stewards and police")
	s.club.cash = -1e6
	var r2 := s.play_next()
	assert_almost_eq(float(r2.costs["interest"]), roundf(1e6 * config.num("economy/debt_interest_per_match")), 1.0)


func test_deep_debt_means_administration() -> void:
	var s := _season()
	while not s.is_over():
		s.play_next()
	s.club.cash = -1e9
	s.start_next_season()
	assert_true(s.club.administration)
	var row: Dictionary = s.league.table().filter(func(x: Dictionary) -> bool: return int(x["team"]) == 0)[0]
	assert_eq(int(row["pts"]), -config.integer("economy/administration_points"), "points deducted")
	assert_ne(s.set_squad_budget(1e7), "", "wages capped")
	assert_eq(s.set_squad_budget(1000.0), "")
	var back := Season.from_save(config, JSON.parse_string(JSON.stringify(s.to_save())))
	assert_true(back.club.administration)
	assert_eq(int(back.league.deductions.get(0, 0)), config.integer("economy/administration_points"))
