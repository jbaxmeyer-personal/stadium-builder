extends GutTest

var config: SimConfig


func before_all() -> void:
	config = SimConfig.load_default()


func _layout() -> Layout:
	return Layout.create(config, "test")


func test_pitch_is_centred() -> void:
	var l := _layout()
	assert_eq(l.pitch, Rect2i(15, 11, 30, 18))


func test_stand_capacity_and_cost_come_from_data() -> void:
	var l := _layout()
	l.stands.append(Stand.make("N", "seated", 0, 10, 2))
	var t := config.stand_type("seated")
	assert_eq(l.capacity_total(config), 10 * 2 * t.capacity_per_tile)
	assert_eq(l.build_cost(config), 10 * 2 * t.capacity_per_tile * t.build_cost_per_place)


func test_stand_tiles_sit_against_each_side() -> void:
	var l := _layout()
	assert_has(Stand.make("N", "seated", 0, 1, 1).tiles(l.pitch), Vector2i(15, 10))
	assert_has(Stand.make("S", "seated", 0, 1, 1).tiles(l.pitch), Vector2i(15, 29))
	assert_has(Stand.make("W", "seated", 0, 1, 1).tiles(l.pitch), Vector2i(14, 11))
	assert_has(Stand.make("E", "seated", 0, 1, 1).tiles(l.pitch), Vector2i(45, 11))
	assert_has(Stand.make("N", "seated", 0, 1, 1, 2).tiles(l.pitch), Vector2i(15, 8))


func test_valid_layout_has_no_errors() -> void:
	var l := _layout()
	l.stands.append(Stand.make("N", "seated", 0, 30, 4))
	l.facilities.append(Facility.make("kiosk", Vector2i(20, 6)))
	assert_eq(l.validate(config, 1e9).size(), 0)


func test_overlap_is_rejected() -> void:
	var l := _layout()
	l.stands.append(Stand.make("N", "seated", 0, 10, 2))
	l.stands.append(Stand.make("N", "terrace", 5, 10, 2))
	assert_gt(l.validate(config).size(), 0)


func test_too_long_for_side_is_rejected() -> void:
	var l := _layout()
	l.stands.append(Stand.make("E", "seated", 0, 19, 2))
	assert_gt(l.validate(config).size(), 0)


func test_facility_must_be_on_concourse() -> void:
	var l := _layout()
	l.stands.append(Stand.make("N", "seated", 0, 30, 4))
	l.facilities.append(Facility.make("kiosk", Vector2i(2, 2)))
	assert_gt(l.validate(config).size(), 0)


func test_over_budget_is_rejected() -> void:
	var l := _layout()
	l.stands.append(Stand.make("N", "premium", 0, 30, 8))
	assert_gt(l.validate(config, config.num("economy/starting_cash")).size(), 0)


func test_sample_layouts_are_valid() -> void:
	for path in ["res://data/layouts/terrace_wall.json", "res://data/layouts/terrace_wall_spread.json",
			"res://data/layouts/seated_bowl.json", "res://data/layouts/all_terrace.json",
			"res://data/layouts/all_premium.json", "res://data/layouts/small_and_loud.json"]:
		var l := Layout.load_json(path, config)
		assert_eq(l.validate(config).size(), 0, path + ": " + ", ".join(l.validate(config)))


func test_walk_distance_goes_around_stands() -> void:
	var l := _layout()
	l.stands.append(Stand.make("N", "seated", 0, 30, 4))
	var d := l.walk_distances(Vector2i(14, 9), l.stand_tile_map())
	# (14,9) is just west of the stand; (45,9) just east. Must route around the back.
	assert_true(d.has(Vector2i(45, 9)))
	assert_gt(d[Vector2i(45, 9)], 31)


func test_walk_cache_invalidates_when_layout_changes() -> void:
	var l := _layout()
	l.stands.append(Stand.make("N", "seated", 0, 30, 4))
	var src := Vector2i(14, 9)
	var east := Vector2i(45, 9)
	var around: int = l.walk_distances_cached(src, l.stand_tile_map())[east]
	l.stands.clear()
	var direct: int = l.walk_distances_cached(src, l.stand_tile_map())[east]
	assert_lt(direct, around)
	assert_eq(direct, l.walk_distances(src, l.stand_tile_map())[east])


func test_corner_stand_geometry() -> void:
	var l := _layout()
	var c := Stand.make_corner("NW", "seated", 3)
	l.stands.append(c)
	assert_eq(c.tiles(l.pitch).size(), 9)
	assert_eq(c.capacity(config.stand_type("seated")), 9 * config.stand_type("seated").capacity_per_tile)
	assert_has(c.tiles(l.pitch), Vector2i(14, 10), "touches the pitch corner diagonally")
	assert_has(c.tiles(l.pitch), Vector2i(12, 8))
	assert_eq(c.row_tiles(l.pitch, 0).size(), 1)
	assert_eq(c.row_tiles(l.pitch, 2).size(), 5)
	assert_eq(l.validate(config).size(), 0, ", ".join(l.validate(config)))


func test_corner_fits_between_side_stands() -> void:
	var l := _layout()
	l.stands.append(Stand.make("N", "seated", 0, 30, 4))
	l.stands.append(Stand.make("W", "seated", 0, 18, 4))
	for corner in Stand.CORNERS:
		l.stands.append(Stand.make_corner(corner, "terrace", 4))
	assert_eq(l.validate(config).size(), 0, ", ".join(l.validate(config)))
	l.facilities.append(Facility.make("kiosk", Stand.corner_to_grid("NW", l.pitch, 4, 4)))
	assert_eq(l.validate(config).size(), 0, "corner concourse takes facilities")


func test_corner_round_trips_through_json() -> void:
	var l := _layout()
	var c := Stand.make_corner("SE", "premium", 2)
	c.roof = "gable"
	c.seat_color = "#ff8800"
	l.stands.append(c)
	var back := Layout.from_dict(JSON.parse_string(l.to_json()), config)
	assert_eq_deep(back.to_dict(), l.to_dict())


func test_rounded_corner_is_a_quarter_circle() -> void:
	var l := _layout()
	var sq := Stand.make_corner("NW", "seated", 6)
	var rd := Stand.make_corner("NE", "seated", 6)
	rd.shape = "rounded"
	l.stands.append(sq)
	l.stands.append(rd)
	var t := config.stand_type("seated")
	assert_lt(rd.capacity(t), sq.capacity(t), "rounding trims the outer corner")
	assert_gt(rd.capacity(t), sq.capacity(t) * 0.6)
	assert_does_not_have(rd.tiles(l.pitch), Stand.corner_to_grid("NE", l.pitch, 5, 5), "far corner cut off")
	assert_has(rd.tiles(l.pitch), Stand.corner_to_grid("NE", l.pitch, 5, 0), "edges kept")
	assert_eq(l.validate(config).size(), 0, ", ".join(l.validate(config)))
	var src: Vector2i = rd.sections(l.pitch, 5)[0]["source"]
	assert_does_not_have(rd.tiles(l.pitch), src, "fans walk out from behind the stand")


func test_big_stands_have_their_concourse_inside() -> void:
	var l := _layout()
	var small := Stand.make("S", "seated", 0, 30, 4)   # rows y 29..32, concourse behind: 33..34
	var big := Stand.make("N", "seated", 0, 30, 6)     # rows y 5..10, concourse inside: y 5..6
	l.stands.append(small)
	l.stands.append(big)
	var conc := l.concourse_tile_map(config)
	assert_true(conc.has(Vector2i(20, 33)), "small stand: behind")
	assert_true(conc.has(Vector2i(20, 5)) and conc.has(Vector2i(20, 6)), "big stand: under the back rows")
	assert_false(conc.has(Vector2i(20, 4)), "the ground behind a big stand is free")
	l.facilities.append(Facility.make("kiosk", Vector2i(20, 6)))
	l.facilities.append(Facility.make("bus_stop", Vector2i(20, 1)))
	assert_eq(l.validate(config).size(), 0, ", ".join(l.validate(config)))
	var blocked := l.blocked_tiles(config)
	assert_false(blocked.has(Vector2i(20, 6)), "fans can walk the inside concourse")
	assert_true(blocked.has(Vector2i(20, 8)), "but not through the seats")


func test_inside_concourse_is_used_at_halftime() -> void:
	var l := _layout()
	l.stands.append(Stand.make("N", "seated", 0, 30, 6))
	l.facilities.append(Facility.make("kiosk", Vector2i(30, 6)))
	var c := ClubState.create(config)
	c.fanbase = 8000.0
	var r := MatchdaySim.run(config, l, c, Fixture.make("X"), 1)
	assert_gt(r.facilities[0]["served"], 0)
	assert_eq(r.halftime["food"]["unreachable"], 0)


func test_upper_tiers_need_more_ground() -> void:
	var one := Stand.make("S", "seated", 0, 30, 6)
	var two := Stand.make("S", "seated", 0, 30, 6)
	two.tiers = 2
	var three := Stand.make("S", "seated", 0, 30, 6)
	three.tiers = 3
	var p := _layout().pitch
	assert_eq(one.tiles(p).size(), 30 * 6)
	assert_eq(two.tiles(p).size(), 30 * 9, "second tier sets back 3 rows")
	assert_eq(three.tiles(p).size(), 30 * 12)
	assert_eq(three.capacity(config.stand_type("seated")), 3 * one.capacity(config.stand_type("seated")))


func test_kop_sized_single_tier_and_three_tiers_need_land() -> void:
	var l := _layout()
	var kop := Stand.make("S", "terrace", 0, 30, 12)   # rows y 29..40: off a 40-high plot
	l.stands.append(kop)
	assert_gt(l.validate(config).size(), 0, "too big for the starting plot")
	var mid := Stand.make("N", "seated", 0, 30, 4)
	mid.tiers = 3                                      # 4 + 2 + 2 = 8 rows of ground: fits
	var l2 := _layout()
	l2.stands.append(mid)
	assert_eq(l2.validate(config).size(), 0, ", ".join(l2.validate(config)))


func test_multi_tier_concourse_is_under_the_upper_tier() -> void:
	var l := _layout()
	var s := Stand.make("N", "seated", 0, 30, 4)        # lower rows y 7..10
	s.tiers = 2                                        # upper tier over y 5..8
	l.stands.append(s)
	var conc := l.concourse_tile_map(config)
	assert_true(conc.has(Vector2i(20, 6)) and conc.has(Vector2i(20, 5)), "concourse under the upper tier")
	assert_false(conc.has(Vector2i(20, 4)))
	assert_false(l.blocked_tiles(config).has(Vector2i(20, 6)))


func test_cosmetic_variants_save_and_validate() -> void:
	var l := _layout()
	var s := Stand.make("N", "seated", 0, 30, 4)
	s.facade = "brick"
	l.stands.append(s)
	l.pitch_pattern = "checks"
	var back := Layout.from_dict(JSON.parse_string(l.to_json()), config)
	assert_eq(back.stands[0].facade, "brick")
	assert_eq(back.pitch_pattern, "checks")
	s.facade = "marble"
	assert_gt(l.validate(config).size(), 0)


func test_stand_extras_are_cosmetic_and_saved() -> void:
	var config := SimConfig.load_default()
	var s := Season.create(config, Layout.create(config, "x"), 1)
	s.club.cash = 1e8
	assert_eq(s.build_stand(Stand.make("N", "seated", 0, 10, 3)), "")
	var st := s.layout.stands[0]
	assert_false(bool(st.extra("name")["on"]), "new stands start bare: no name")
	assert_eq(st.roof, "open", "and no roof")
	var old := Stand.from_dict({ "side": "N", "type": "seated", "offset": 0, "length": 10, "depth": 3, "roof": "gable" })
	assert_true(bool(old.extra("name")["on"]), "old saves keep their names")
	assert_false(bool(st.extra("flags")["on"]))
	var cash := s.club.cash
	assert_eq(s.set_stand_extra(0, "name", { "text": "THE KOP", "size": "L", "lit": false }), "")
	assert_eq(s.set_stand_extra(0, "flags", { "on": true }), "")
	assert_ne(s.set_stand_extra(0, "name", { "size": "XXL" }), "")
	assert_ne(s.set_stand_extra(0, "rocket", { "on": true }), "")
	assert_ne(s.set_stand_extra(0, "flags", { "on": "yes" }), "")
	assert_eq(s.club.cash, cash, "extras are free")
	assert_eq(st.extra("name")["text"], "THE KOP")
	assert_eq(st.extra("name")["where"], "roof", "untouched settings keep defaults")
	assert_eq(s.set_pitch_grass("emerald"), "")
	assert_eq(s.set_goals("stanchion", "ffd700", "hexagon"), "")
	var back := Layout.from_dict(JSON.parse_string(JSON.stringify(s.layout.to_dict())), config)
	assert_eq(back.stands[0].extra("name")["size"], "L")
	assert_true(bool(back.stands[0].extra("flags")["on"]))
	assert_eq(back.pitch_grass, "emerald")
	assert_eq(back.goal_style, "stanchion")
	assert_eq(back.net_pattern, "hexagon")


func test_gear_options_seat_patterns_and_pitchside() -> void:
	var config := SimConfig.load_default()
	var s := Season.create(config, Layout.create(config, "x"), 1)
	s.club.cash = 1e8
	s.club.peak_fanbase = 1e9
	assert_eq(s.build_stand(Stand.make("N", "seated", 0, 10, 3)), "")
	var tile := s.layout.stands[0].tiles(s.layout.pitch)[0]
	assert_eq(s.build_facility(Facility.make("video_board", tile)), "")
	var fi := s.layout.facilities.size() - 1
	var ft := config.facility_type("video_board")
	assert_eq(s.layout.facilities[fi].opt(ft, "size"), "M", "default is the first value")
	assert_eq(s.set_facility_option(fi, "size", "L"), "")
	assert_ne(s.set_facility_option(fi, "size", "XL"), "")
	assert_ne(s.set_facility_option(fi, "colour", "red"), "")
	assert_eq(s.set_stand_extra(0, "seats", { "pattern": "text", "text": "UTD", "color2": "ffffff" }), "")
	assert_ne(s.set_stand_extra(0, "seats", { "pattern": "polka" }), "")
	assert_eq(s.set_stand_extra(0, "logo", { "on": true, "where": "left" }), "")
	assert_ne(s.set_stand_extra(0, "logo", { "where": "roof" }), "")
	assert_eq(s.set_pitchside("surround", "track"), "")
	assert_ne(s.set_pitchside("surround", "lava"), "")
	assert_ne(s.set_pitchside("pitch", "x"), "")
	var back := Layout.from_dict(JSON.parse_string(JSON.stringify(s.layout.to_dict())), config)
	assert_eq(back.facilities[fi].opt(ft, "size"), "L")
	assert_eq(back.stands[0].extra("seats")["pattern"], "text")
	assert_eq(back.surround, "track")


func test_empty_plot_then_place_the_pitch() -> void:
	var config := SimConfig.load_default()
	var l := Layout.create(config, "empty")
	l.pitch_placed = false
	var s := Season.create(config, l, 1)
	assert_ne(s.build_stand(Stand.make("N", "seated", 0, 10, 2)), "", "no stands before the pitch")
	assert_ne(s.place_pitch(Vector2i(-5, 0)), "", "off the plot")
	var cash := s.club.cash
	assert_eq(s.place_pitch(Vector2i(4, 6)), "")
	assert_lt(s.club.cash, cash, "the pitch costs money")
	assert_eq(s.layout.pitch.position, Vector2i(4, 6))
	assert_eq(s.place_pitch(Vector2i(6, 6)), "", "free to move while nothing is built")
	assert_eq(s.build_stand(Stand.make("N", "seated", 0, 10, 2)), "")
	assert_eq(s.place_pitch(Vector2i(8, 6)), "", "stands move with the pitch")
	assert_eq(s.layout.stands.size(), 1)
	var back := Layout.from_dict(JSON.parse_string(JSON.stringify(s.layout.to_dict())), config)
	assert_eq(back.pitch.position, Vector2i(8, 6))
	assert_true(back.pitch_placed)


func test_moving_the_pitch_removes_stands_that_no_longer_fit() -> void:
	var config := SimConfig.load_default()
	var s := Season.create(config, Layout.create(config, "move"), 1)
	assert_true(s.layout.pitch_placed, "a new game starts with the pitch down")
	s.club.cash = 5000000.0
	assert_eq(s.build_stand(Stand.make("N", "seated", 0, s.layout.pitch.size.x, 3)), "")
	assert_eq(s.build_stand(Stand.make("S", "seated", 0, s.layout.pitch.size.x, 3)), "")
	var m := config.integer("plot/pitch_margin")
	var top := Vector2i(s.layout.pitch.position.x, s.layout.plot.position.y + m)
	var plan := s.pitch_move_plan(top)
	assert_eq(plan["error"], "")
	assert_eq(plan["stands"], [0], "only the north stand falls off the plot")
	var cash := s.club.cash
	assert_eq(s.place_pitch(top), "")
	assert_eq(s.layout.stands.size(), 1)
	assert_eq(s.layout.stands[0].side, "S")
	assert_gt(s.club.cash, cash, "a removed stand refunds like a demolition")
	assert_eq(s.layout.validate(config).size(), 0)


func test_a_roof_is_a_paid_layer() -> void:
	var config := SimConfig.load_default()
	var s := Season.create(config, Layout.create(config, "roof"), 1)
	s.club.cash = 1e7
	assert_eq(s.build_stand(Stand.make("N", "seated", 0, 10, 3)), "")
	var cap := s.layout.stands[0].capacity(config.stand_type("seated"))
	var cash := s.club.cash
	assert_eq(s.restyle_stand(0, "gable", ""), "")
	assert_almost_eq(cash - s.club.cash, cap * config.num("layout/roof_cost_per_place"), 0.01, "a roof costs per place covered")
	cash = s.club.cash
	assert_eq(s.restyle_stand(0, "barrel", ""), "")
	assert_eq(s.club.cash, cash, "changing roof style is free")
	assert_eq(s.restyle_stand(0, "open", ""), "")
	assert_gt(s.club.cash, cash, "taking it off refunds part")
	s.club.cash = 0.0
	assert_ne(s.restyle_stand(0, "gable", ""), "", "can't afford a roof")


func test_bare_pitch_and_corner_flags() -> void:
	var config := SimConfig.load_default()
	var s := Season.create(config, Layout.create(config, "p"), 1)
	var l := s.layout
	assert_eq(l.ad_boards, "none")
	assert_eq(l.dugout, "none")
	assert_eq(l.net_pattern, "none")
	assert_false(bool(l.corner_flags["on"]))
	assert_eq(s.set_corner_flags({ "on": true, "pole": "ffcc00", "flag": "", "pattern": "quarters" }), "")
	assert_ne(s.set_corner_flags({ "pattern": "tartan" }), "")
	assert_ne(s.set_corner_flags({ "pole": "nope" }), "")
	var back := Layout.from_dict(JSON.parse_string(JSON.stringify(l.to_dict())), config)
	assert_eq(back.corner_flags["pattern"], "quarters")
	assert_eq(back.corner_flags["pole"], "ffcc00")
	var old := Layout.from_dict({ "name": "old" }, config)
	assert_true(bool(old.corner_flags["on"]), "old saves keep their corner flags")


func test_stand_shape_rake_plinth_concourse() -> void:
	var config := SimConfig.load_default()
	var s := Season.create(config, Layout.create(config, "shape"), 1)
	s.club.cash = 1e8
	var p := s.layout.pitch
	assert_eq(s.build_stand(Stand.make("S", "seated", 0, p.size.x, 8)), "")
	var st := s.layout.stands[0]
	var base_view := MatchdaySim.view_quality(config, st)
	var cost0 := Layout.stand_cost(st, config)
	assert_eq(s.set_stand_shape(0, 18.0, 0.35, 0), "")
	assert_lt(MatchdaySim.view_quality(config, st), base_view, "shallow stands have a worse view")
	assert_lt(Layout.stand_cost(st, config), cost0, "and are cheaper")
	assert_eq(s.set_stand_shape(0, 38.0, 1.5, 2), "")
	assert_gt(Layout.stand_cost(st, config), cost0, "steep, high stands cost more")
	assert_gt(MatchdaySim.steepness(config, st), 0.0)
	var conc := s.layout.stand_concourse(st, config).size()
	assert_eq(s.set_stand_shape(0, 38.0, 1.5, 0), "")
	assert_lt(s.layout.stand_concourse(st, config).size(), conc, "extra concourse rows")
	assert_ne(s.set_stand_shape(0, 60.0, 1.5, 0), "", "too steep")
	var back := Stand.from_dict(st.to_dict())
	assert_eq(back.rake, 38.0)
	assert_eq(back.plinth, 1.5)


func test_wall_signs_add_edit_remove_and_save() -> void:
	var config := SimConfig.load_default()
	var s := Season.create(config, Layout.create(config, "signs"), 1)
	s.club.cash = 1e8
	assert_eq(s.build_stand(Stand.make("S", "seated", 0, 12, 5)), "")
	assert_eq(s.add_stand_sign(0, { "kind": "text", "text": "COME ON YOU REDS", "surface": "back", "u": 0.3 }), "")
	assert_eq(s.add_stand_sign(0, { "kind": "player", "surface": "back", "count": 4, "seed": 7 }), "")
	assert_ne(s.add_stand_sign(0, { "kind": "rocket" }), "")
	assert_ne(s.add_stand_sign(0, { "surface": "roofx" }), "")
	assert_eq(s.set_stand_sign(0, 0, { "depth": 0.0, "light": "flood", "scale": 2.0 }), "")
	assert_eq(s.layout.stands[0].signs().size(), 2)
	assert_eq(String(s.layout.stands[0].signs()[0]["light"]), "flood")
	var back := Layout.from_dict(JSON.parse_string(JSON.stringify(s.layout.to_dict())), config)
	assert_eq(back.stands[0].signs().size(), 2)
	assert_eq(String(back.stands[0].signs()[1]["kind"]), "player")
	assert_eq(s.remove_stand_sign(0, 0), "")
	assert_eq(s.layout.stands[0].signs().size(), 1)


func test_upper_tiers_can_overhang() -> void:
	var config := SimConfig.load_default()
	var s := Season.create(config, Layout.create(config, "oh"), 1)
	s.club.cash = 1e9
	s.club.peak_fanbase = 1e9
	for k in 3:
		s.buy_land("S")
	assert_eq(s.build_stand(Stand.make("S", "seated", 0, 10, 8)), "")
	assert_eq(s.set_tiers(0, 2), "")
	var foot := s.layout.stands[0].footprint_depth()
	assert_eq(s.set_overhang(0, 3), "")
	assert_lt(s.layout.stands[0].footprint_depth(), foot, "an overhanging tier takes less ground")
	assert_ne(s.set_overhang(0, 9), "")
	assert_eq(Stand.from_dict(s.layout.stands[0].to_dict()).overhang, 3)
