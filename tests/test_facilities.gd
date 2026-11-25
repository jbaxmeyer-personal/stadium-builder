extends GutTest
## Placement rules per layer and what each kind of facility does on matchday.

var config: SimConfig


func before_all() -> void:
	config = SimConfig.load_default()


func _base() -> Layout:
	var l := Layout.create(config, "f")
	l.stands.append(Stand.make("N", "seated", 0, 30, 4))   # rows y 7..10, concourse y 5..6
	l.stands.append(Stand.make("S", "terrace", 0, 30, 4))  # rows y 29..32, concourse y 33..34
	return l


func _run(l: Layout, fanbase := 6000.0, seed := 3) -> MatchdayReport:
	var c := ClubState.create(config)
	c.fanbase = fanbase
	return MatchdaySim.run(config, l, c, Fixture.make("Rovers"), seed)


func test_every_type_has_a_known_layer_and_styles() -> void:
	for id in config.facility_types:
		var t := config.facility_type(id)
		assert_has(FacilityType.LAYERS, t.layer, id)
		assert_gt(t.styles.size(), 0, id)


func test_concourse_items_need_concourse_and_respect_footprint() -> void:
	var l := _base()
	l.facilities.append(Facility.make("merch", Vector2i(20, 5)))        # 2x1 on concourse
	l.facilities.append(Facility.make("fan_zone", Vector2i(30, 5)))     # 2x2 fills both concourse rows
	assert_eq(l.validate(config).size(), 0, ", ".join(l.validate(config)))
	l.facilities.append(Facility.make("kiosk", Vector2i(31, 6)))        # overlaps the fan zone
	assert_eq(l.validate(config).size(), 1)
	l.facilities.pop_back()
	l.facilities.append(Facility.make("fan_zone", Vector2i(40, 4)))     # half off the concourse
	assert_eq(l.validate(config).size(), 1)


func test_bowl_items_sit_on_a_stand_one_of_each_per_stand() -> void:
	var l := _base()
	l.facilities.append(Facility.make("video_board", Vector2i(20, 8)))
	l.facilities.append(Facility.make("video_board", Vector2i(20, 30)))  # other stand: fine
	assert_eq(l.validate(config).size(), 0, ", ".join(l.validate(config)))
	l.facilities.append(Facility.make("video_board", Vector2i(25, 9)))   # same stand again
	assert_eq(l.validate(config).size(), 1)
	l.facilities.pop_back()
	l.facilities.append(Facility.make("scoreboard", Vector2i(2, 2)))     # not on a stand
	assert_eq(l.validate(config).size(), 1)


func test_outside_and_underground_placement() -> void:
	var l := _base()
	l.facilities.append(Facility.make("car_park", Vector2i(1, 1)))
	l.facilities.append(Facility.make("garage", Vector2i(20, 6)))        # under a stand: allowed
	assert_eq(l.validate(config).size(), 0, ", ".join(l.validate(config)))
	l.facilities.append(Facility.make("car_park", Vector2i(20, 6)))      # outside but on the stand
	assert_eq(l.validate(config).size(), 1)
	l.facilities.pop_back()
	l.facilities.append(Facility.make("subway", Vector2i(20, 15)))       # under the pitch
	assert_eq(l.validate(config).size(), 1)


func test_transport_caps_the_crowd() -> void:
	var l := _base()
	var free := _run(l, 40000.0)
	assert_almost_eq(float(free.attendance), l.transport_capacity(config), float(l.stands.size()), "limited by transport")
	assert_gt(free.transport_turned_away, 0)
	l.facilities.append(Facility.make("subway", Vector2i(1, 1)))
	var linked := _run(l, 40000.0)
	assert_gt(linked.attendance, free.attendance)


func test_screens_and_sound_lift_atmosphere_and_boards_earn() -> void:
	var l := _base()
	var plain := _run(l)
	l.facilities.append(Facility.make("video_board", Vector2i(20, 8)))
	l.facilities.append(Facility.make("sound_system", Vector2i(20, 30)))
	l.facilities.append(Facility.make("ribbon_board", Vector2i(10, 30)))
	var kitted := _run(l)
	assert_almost_eq(kitted.atmosphere - plain.atmosphere, 8.0, 0.01)
	assert_gt(kitted.revenue["sponsors"], 0.0)
	assert_eq(plain.revenue["sponsors"], 0.0)


func test_bars_and_shops_earn_at_halftime() -> void:
	var l := _base()
	l.facilities.append(Facility.make("bar", Vector2i(20, 5)))
	l.facilities.append(Facility.make("merch", Vector2i(24, 5)))
	var r := _run(l)
	assert_gt(r.revenue["drinks"], 0.0)
	assert_gt(r.revenue["merch"], 0.0)
	assert_almost_eq(r.revenue["total"], r.revenue["tickets"] + r.revenue["food"] + r.revenue["drinks"]
		+ r.revenue["merch"] + r.revenue["premium"] + r.revenue["sponsors"], 0.01)


func test_first_aid_and_fan_zones_raise_mood() -> void:
	var l := _base()
	var before := _run(l)
	l.facilities.append(Facility.make("first_aid", Vector2i(20, 5)))
	l.facilities.append(Facility.make("fan_zone", Vector2i(30, 33)))
	var after := _run(l)
	assert_gt(after.mood_change["care"], 0.0)
	assert_eq(before.mood_change["care"], 0.0)


func test_utility_bill_grows_with_the_stadium() -> void:
	var l := _base()
	var small: float = _run(l).costs["utilities"]
	l.facilities.append(Facility.make("video_board", Vector2i(20, 8)))
	l.facilities.append(Facility.make("restroom", Vector2i(20, 5)))
	assert_gt(_run(l).costs["utilities"], small)


func test_demolishing_a_stand_removes_its_bowl_items() -> void:
	var s := Season.create(config, _base(), 1)
	s.club.cash = 1e7
	assert_eq(s.build_facility(Facility.make("video_board", Vector2i(20, 8))), "")
	assert_eq(s.build_facility(Facility.make("kiosk", Vector2i(20, 33))), "")
	assert_eq(s.demolish_stand(0), "")
	assert_eq(s.layout.facilities.size(), 1, "board on the north stand went with it")
	assert_eq(s.layout.facilities[0].type_id, "kiosk")


func test_facility_styles() -> void:
	var s := Season.create(config, _base(), 1)
	s.club.cash = 1e7
	assert_eq(s.build_facility(Facility.make("kiosk", Vector2i(20, 5))), "")
	assert_eq(s.restyle_facility(0, "food_truck"), "")
	assert_eq(s.layout.facilities[0].style, "food_truck")
	assert_ne(s.restyle_facility(0, "spaceship"), "")
