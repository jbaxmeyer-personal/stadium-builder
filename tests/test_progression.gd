extends GutTest
## Milestones and unlocks, executive boxes, buildings around the ground, naming rights.

var config: SimConfig


func before_all() -> void:
	config = SimConfig.load_default()


func _season() -> Season:
	var l := Layout.create(config, "p")
	l.stands.append(Stand.make("N", "seated", 0, 30, 4))
	var s := Season.create(config, l, 1)
	s.club.cash = 1e8
	return s


func test_basics_are_open_from_the_start() -> void:
	var s := _season()
	for id in ["kiosk", "bar", "restroom", "merch", "car_park", "bus_stop", "first_aid", "fan_zone"]:
		assert_true(s.is_unlocked(id), id)
	for id in ["video_board", "tier2", "subway", "hotel", "exec_boxes"]:
		assert_false(s.is_unlocked(id), id)


func test_locked_items_say_when_they_unlock() -> void:
	var s := _season()
	var err := s.build_facility(Facility.make("video_board", Vector2i(20, 8)))
	assert_string_contains(err, "8,000 fans")
	assert_string_contains(s.set_tiers(0, 2), "12,000 fans")


func test_milestones_unlock_and_pay_out_once() -> void:
	var s := _season()
	var cash := s.club.cash
	s.club.peak_fanbase = 8500.0
	var got := s.check_milestones()
	assert_eq(got.size(), 2, "5,000 and 8,000")
	assert_almost_eq(s.club.cash, cash + 100000.0 + 150000.0, 0.01)
	assert_true(s.is_unlocked("video_board"))
	assert_eq(s.check_milestones().size(), 0, "paid once")
	assert_eq(s.build_facility(Facility.make("video_board", Vector2i(20, 8))), "")


func test_growing_past_a_milestone_during_play_is_reported() -> void:
	var s := _season()
	s.club.fanbase = 4990.0
	s.club.peak_fanbase = 4990.0
	var hit := false
	for i in 5:
		var r := s.play_next()
		if not r.milestones.is_empty():
			hit = true
			assert_eq(r.milestones[0]["name"], "Local favourites")
	assert_true(hit)


func test_executive_boxes_need_two_tiers_and_earn() -> void:
	var s := _season()
	s.club.peak_fanbase = 1e9
	assert_ne(s.build_facility(Facility.make("exec_boxes", Vector2i(20, 8))), "", "single tier: no")
	assert_eq(s.set_tiers(0, 2), "")
	assert_eq(s.build_facility(Facility.make("exec_boxes", Vector2i(20, 8))), "")
	var r := s.play_next()
	assert_gt(r.revenue["boxes"], 0.0)
	assert_eq(MatchdaySim.box_count(s.layout.stands[0]), 15)


func test_venue_income_and_train_station() -> void:
	var s := _season()
	s.club.peak_fanbase = 1e9
	var cap0 := s.layout.transport_capacity(config)
	assert_eq(s.build_facility(Facility.make("hotel", Vector2i(1, 1))), "")
	assert_eq(s.build_facility(Facility.make("train_station", Vector2i(1, 34))), "")
	assert_eq(s.build_facility(Facility.make("statue", Vector2i(10, 2))), "")
	assert_gt(s.layout.transport_capacity(config), cap0)
	var r := s.play_next()
	assert_almost_eq(r.revenue["venue"], 35000.0, 0.01)
	assert_gt(r.mood_change["care"], 0.0, "the statue cheers fans up")


func test_naming_rights_pay_but_cost_a_little_mood() -> void:
	var s := _season()
	assert_ne(s.set_sponsor("voltline"), "", "locked until 8,000 fans")
	s.club.peak_fanbase = 1e9
	assert_eq(s.set_sponsor("voltline"), "")
	assert_eq(s.club.ground_name(config), "Voltline Energy Arena")
	var a := s.play_next()
	assert_gt(a.revenue["naming"], 0.0)
	var plain := _season()
	var b := plain.play_next()
	assert_lt(a.mood_change["care"], b.mood_change["care"])
	assert_eq(s.set_sponsor(""), "")
	assert_eq(s.club.ground_name(config), s.club.stadium_name)


func test_progress_survives_save_and_load() -> void:
	var s := _season()
	s.club.peak_fanbase = 9000.0
	s.check_milestones()
	s.club.stadium_name = "The Fortress"
	s.set_sponsor("brightbank")
	var t := Season.from_save(config, JSON.parse_string(JSON.stringify(s.to_save(), "", true, true)))
	assert_eq(t.club.milestones.size(), 2)
	assert_eq(t.club.sponsor, "brightbank")
	assert_eq(t.club.stadium_name, "The Fortress")
	assert_true(t.is_unlocked("video_board"))


func test_promotion_after_a_good_season() -> void:
	var s := _season()
	s.play_all()
	var pts := s.summary().points
	var target := int(config.division(0)["promotion_points"])
	var expect_up := pts >= target
	assert_eq(s.promotion_earned(), expect_up)
	s.start_next_season()
	assert_eq(s.club.division, 1 if expect_up else 0)
	assert_eq(s.history[0].promoted, expect_up)


func test_forced_promotion_and_higher_division_effects() -> void:
	var s := _season()
	s.club.division = 2
	var r := s.play_next()
	assert_almost_eq(r.revenue["tv"], 60000.0, 0.01)
	assert_almost_eq(r.demand_multipliers["division"], 1.35, 0.0001)
	var low := _season().play_next()
	assert_lt(r.probabilities["win"], low.probabilities["win"] - 0.05, "tougher opponents")


func test_top_division_has_no_promotion() -> void:
	var s := _season()
	s.club.division = config.divisions.size() - 1
	s.play_all()
	assert_false(s.promotion_earned())
	assert_eq(s.points_to_promotion(), -1)


func test_rain_and_snow_empty_open_stands_but_not_roofed_ones() -> void:
	var l := Layout.create(config, "w")
	var covered := Stand.make("N", "seated", 0, 30, 4)
	var open := Stand.make("S", "seated", 0, 30, 4)
	open.roof = "open"
	l.stands.append(covered)
	l.stands.append(open)
	var c := ClubState.create(config)
	c.fanbase = 50000.0
	var results := {}
	for w in ["clear", "rain", "snow"]:
		var fx := Fixture.make("X")
		fx.weather = w
		results[w] = MatchdaySim.run(config, l, c, fx, 3)
	assert_eq(results["rain"].stands[0]["attendance"], results["clear"].stands[0]["attendance"], "roof keeps them coming")
	assert_lt(results["rain"].stands[1]["attendance"], results["clear"].stands[1]["attendance"])
	assert_lt(results["snow"].stands[1]["attendance"], results["rain"].stands[1]["attendance"])


func test_snow_only_in_winter() -> void:
	for seed in range(1, 30):
		var s := Season.create(config, Layout.create(config, "w"), seed)
		for i in s.fixtures.size():
			if s.fixtures[i].weather == "snow":
				assert_has([4, 5, 6, 7], i + 1)
