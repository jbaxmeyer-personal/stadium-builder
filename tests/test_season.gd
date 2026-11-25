extends GutTest

const TW := "res://data/layouts/terrace_wall.json"
const SB := "res://data/layouts/seated_bowl.json"

var config: SimConfig


func before_all() -> void:
	config = SimConfig.load_default()


func _season(path: String, seed: int) -> Season:
	return Season.create(config, Layout.load_json(path, config), seed)


func test_season_plays_configured_number_of_matches() -> void:
	var r := _season(SB, 1).play_all()
	assert_eq(r.matches, config.integer("season/matches"))
	assert_eq(r.wins + r.draws + r.losses, r.matches)
	assert_eq(r.points, 3 * r.wins + r.draws)


func test_big_matches_come_from_config() -> void:
	var s := _season(SB, 1)
	var big: Array = config.value("season/big_match_numbers")
	for i in s.fixtures.size():
		assert_eq(s.fixtures[i].big, big.has(float(i + 1)), "match %d" % (i + 1))


func test_same_layout_and_seed_gives_identical_season() -> void:
	for path in [TW, SB]:
		assert_eq_deep(_season(path, 5).play_all().to_dict(), _season(path, 5).play_all().to_dict())


func test_different_seeds_give_different_seasons() -> void:
	var seen := {}
	for seed in range(1, 11):
		var r := _season(SB, seed).play_all()
		seen["%d-%d-%d" % [r.wins, r.draws, r.losses]] = true
	assert_gt(seen.size(), 1)


func test_cash_and_mood_carry_between_matches() -> void:
	var s := _season(TW, 3)
	var cash := s.club.cash
	assert_eq(cash, config.num("economy/starting_cash") - s.layout.build_cost(config))
	for i in 3:
		var m := s.play_next()
		cash += m.net
		assert_almost_eq(s.club.cash, cash, 0.01)
		assert_eq(s.club.mood, m.mood_after)
	assert_eq(s.reports[1].mood_before, s.reports[0].mood_after)


func test_results_feed_form_and_form_feeds_demand() -> void:
	var s := _season(SB, 3)
	s.club.recent_results.assign(["W", "W", "W", "W", "W"])
	var hot: float = s.play_next().demand_multipliers["form"]
	var s2 := _season(SB, 3)
	s2.club.recent_results.assign(["L", "L", "L", "L", "L"])
	var cold: float = s2.play_next().demand_multipliers["form"]
	assert_gt(hot, cold)
	var s3 := _season(SB, 3)
	var first := s3.play_next()
	assert_eq(s3.club.recent_results, [first.result] as Array[String])


func test_price_change_between_matches() -> void:
	var s := _season(SB, 1)
	var base: int = s.play_next().demand["seated"]
	assert_eq(s.set_ticket_price("seated", 60.0), "")
	assert_lt(s.play_next().demand["seated"], base)
	assert_ne(s.set_ticket_price("nope", 10.0), "")


func test_build_charges_cash_and_rejects_invalid() -> void:
	var s := Season.create(config, Layout.create(config, "empty"), 1)
	var cash := s.club.cash
	var stand := Stand.make("N", "seated", 0, 10, 2)
	assert_eq(s.build_stand(stand), "")
	assert_almost_eq(s.club.cash, cash - s.layout.build_cost(config), 0.01)
	assert_ne(s.build_stand(Stand.make("N", "seated", 5, 10, 2)), "", "overlap")
	assert_eq(s.layout.stands.size(), 1)
	assert_ne(s.build_facility(Facility.make("kiosk", Vector2i(0, 0))), "", "off concourse")
	assert_eq(s.build_facility(Facility.make("kiosk", Vector2i(20, 8))), "")


func test_build_rejected_when_cash_short() -> void:
	var s := _season(TW, 1)  # TW spends almost all the budget
	assert_ne(s.build_stand(Stand.make("E", "premium", 0, 18, 8)), "")
	assert_eq(s.layout.stands.size(), 3)


func test_demolish_removes_stand_and_orphaned_facilities() -> void:
	var s := _season(SB, 1)
	var before := s.layout.facilities.size()
	var cash := s.club.cash
	var cost_before := s.layout.build_cost(config)
	assert_eq(s.demolish_stand(2), "")  # E terrace; kiosk@49,20 and restroom@49,14 sit behind it
	assert_eq(s.layout.stands.size(), 3)
	assert_eq(s.layout.facilities.size(), before - 2)
	var refund := (cost_before - s.layout.build_cost(config)) * config.num("season/demolish_refund_fraction")
	assert_almost_eq(s.club.cash, cash + refund, 0.01)


func test_resize_stand_charges_difference_and_can_undo() -> void:
	var s := Season.create(config, Layout.create(config, "grow"), 1)
	assert_eq(s.build_stand(Stand.make("N", "seated", 0, 10, 1)), "")
	var cash := s.club.cash
	var cost := s.resize_cost(0, 0, 10, 2)
	assert_gt(cost, 0.0)
	assert_eq(s.resize_stand(0, 0, 10, 2), "")
	assert_almost_eq(s.club.cash, cash - cost, 0.01)
	assert_eq(s.layout.stands[0].depth, 2)
	assert_ne(s.resize_stand(0, 25, 10, 2), "", "runs off the pitch side")
	assert_eq(s.layout.stands[0].offset, 0, "failed resize leaves stand unchanged")


func test_seasons_chain_and_keep_club_state() -> void:
	var s := _season(SB, 2)
	s.play_all()
	var fans := s.club.fanbase
	var cash := s.club.cash
	s.start_next_season()
	assert_eq(s.season_number, 2)
	assert_eq(s.history.size(), 1)
	assert_eq(s.reports.size(), 0)
	assert_eq(s.club.fanbase, fans)
	assert_eq(s.club.cash, cash)
	s.play_next()
	assert_eq(s.summary().cash_start, cash)


func test_fanbase_grows_for_a_reasonable_club() -> void:
	var s := _season(SB, 4)
	var start := s.club.fanbase
	s.play_all()
	assert_gt(s.club.fanbase, start * 1.2, "a decent stadium should grow its fanbase over a season")


func test_corner_resize_keeps_it_square() -> void:
	var s := Season.create(config, Layout.create(config, "c"), 1)
	assert_eq(s.build_stand(Stand.make_corner("NE", "seated", 2)), "")
	var t := config.stand_type("seated")
	var cost := s.resize_cost(0, 0, 3, 3)
	assert_almost_eq(cost, (9 - 4) * t.capacity_per_tile * t.build_cost_per_place, 0.01)
	assert_eq(s.resize_stand(0, 0, 3, 3), "")
	assert_eq(s.layout.stands[0].length, 3)
	assert_eq(s.layout.stands[0].tiles(s.layout.pitch).size(), 9)


func test_corner_shape_change_refunds_the_trimmed_seats() -> void:
	var s := Season.create(config, Layout.create(config, "c"), 1)
	assert_eq(s.build_stand(Stand.make_corner("SW", "seated", 6)), "")
	var cash := s.club.cash
	var t := config.stand_type("seated")
	var before := s.layout.stands[0].capacity(t)
	assert_eq(s.set_corner_shape(0, "rounded"), "")
	var after := s.layout.stands[0].capacity(t)
	assert_lt(after, before)
	assert_almost_eq(s.club.cash, cash + (before - after) * t.build_cost_per_place * config.num("season/demolish_refund_fraction"), 0.01)
	assert_ne(s.set_corner_shape(0, "hexagon"), "")


func test_save_and_load_carries_on_identically() -> void:
	var a := _season(SB, 21)
	for i in 4:
		a.play_next()
	a.set_ticket_price("seated", 34.0)
	a.club.club_name = "Saved FC"
	a.club.primary_color = Color(0.1, 0.2, 0.9)
	var path := "user://test_save.json"
	assert_eq(a.save_file(path), OK)
	var b := Season.load_file(config, path)
	assert_not_null(b)
	assert_eq_deep(_norm(b.to_save()), _norm(a.to_save()))
	assert_eq(b.club.club_name, "Saved FC")
	while not a.is_over():
		var ra := a.play_next()
		var rb := b.play_next()
		assert_eq_deep(rb.to_dict(), ra.to_dict())
	var sa := a.summary()
	var sb := b.summary()
	assert_eq(sb.points, sa.points)
	assert_eq(sb.attendance_total, sa.attendance_total)
	assert_almost_eq(sb.net, sa.net, 0.01)
	assert_almost_eq(sb.cash_end, sa.cash_end, 0.01)
	assert_almost_eq(sb.fanbase_end, sa.fanbase_end, 0.001)
	DirAccess.remove_absolute(path)


func test_save_survives_a_season_change() -> void:
	var a := _season(TW, 22)
	a.play_all()
	a.start_next_season()
	a.play_next()
	var b := Season.from_save(config, _norm(a.to_save()))
	assert_eq(b.season_number, 2)
	assert_eq(b.history.size(), 1)
	assert_eq_deep(b.play_next().to_dict(), a.play_next().to_dict())


## Round-trip through JSON (full precision) so ints/floats compare equal.
func _norm(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d, "", true, true))
