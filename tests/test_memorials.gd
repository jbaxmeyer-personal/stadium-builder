extends GutTest
## Memorials and named gates: outside pieces with the player's own wording.

var config: SimConfig


func before_each() -> void:
	config = SimConfig.load_default()


func _place(s: Season, type_id: String) -> int:
	for y in range(s.layout.plot.position.y, s.layout.plot.end.y):
		for x in range(s.layout.plot.position.x, s.layout.plot.end.x):
			if s.build_facility(Facility.make(type_id, Vector2i(x, y))) == "":
				return s.layout.facilities.size() - 1
	return -1


func test_free_text_wording_saves_and_is_limited() -> void:
	var s := Season.create(config, Layout.create(config, "in"), 1)
	s.club.cash = 1e8
	s.club.peak_fanbase = 1e9
	for type_id in ["memorial", "club_gates"]:
		var i := _place(s, type_id)
		assert_gt(i, -1, type_id + " fits on open ground")
		assert_eq(s.set_facility_option(i, "text", "YOU'LL NEVER FORGET"), "")
		assert_ne(s.set_facility_option(i, "text", "X".repeat(41)), "", "40 letters at most")
		assert_ne(s.set_facility_option(i, "colour", "red"), "", "no such option")
	var back := Layout.from_dict(JSON.parse_string(JSON.stringify(s.layout.to_dict())), config)
	var f: Facility = back.facilities[back.facilities.size() - 1]
	assert_eq(f.opt(config.facility_type(f.type_id), "text"), "YOU'LL NEVER FORGET")


func test_enumerated_options_still_checked() -> void:
	var s := Season.create(config, Layout.create(config, "in"), 1)
	s.club.cash = 1e8
	var i := _place(s, "memorial")
	assert_ne(s.restyle_facility(i, "volcano"), "")
	assert_eq(s.restyle_facility(i, "flame"), "")


func test_copy_stand_look() -> void:
	var s := Season.create(config, Layout.create(config, "in"), 1)
	s.club.cash = 1e9
	s.club.peak_fanbase = 1e9
	var p := s.layout.pitch
	assert_eq(s.build_stand(Stand.make("N", "seated", 0, p.size.x, 4)), "")
	assert_eq(s.build_stand(Stand.make("S", "terrace", 0, p.size.x, 4)), "")
	assert_eq(s.restyle_stand(0, "cantilever", "1f3a5f"), "")
	assert_eq(s.set_stand_extra(0, "paint", { "wall": "8a3b2a", "wall_mat": "brick" }), "")
	assert_eq(s.set_stand_extra(1, "name", { "text": "THE KOP", "on": true }), "")
	assert_eq(s.set_stand_extra(0, "name", { "text": "MAIN", "font": "narrow" }), "")
	var cash := s.club.cash
	assert_eq(s.copy_stand_look(0, 1), "")
	var b := s.layout.stands[1]
	assert_eq(b.roof, "cantilever")
	assert_eq(b.seat_color, "1f3a5f")
	assert_eq(String(b.extra("paint")["wall_mat"]), "brick")
	assert_eq(String(b.extra("name")["text"]), "THE KOP", "keeps its own words")
	assert_eq(String(b.extra("name")["font"]), "narrow", "takes the styling")
	assert_lt(s.club.cash, cash, "a roof still costs money")
	assert_ne(s.copy_stand_look(1, 1), "")


func test_floodlight_options_validate_and_save() -> void:
	var s := Season.create(config, Layout.create(config, "in"), 1)
	assert_eq(s.set_floodlight_opts({ "per_side": 4, "height": 1.3, "color": "f5cf0a" }), "")
	assert_ne(s.set_floodlight_opts({ "per_side": 9 }), "")
	assert_ne(s.set_floodlight_opts({ "height": 3.0 }), "")
	assert_ne(s.set_floodlight_opts({ "colour": "red" }), "")
	var back := Layout.from_dict(JSON.parse_string(JSON.stringify(s.layout.to_dict())), config)
	assert_eq(int(back.flood["per_side"]), 4)
	assert_almost_eq(float(back.flood["height"]), 1.3, 0.001)
	assert_eq(String(back.flood["color"]), "f5cf0a")
	var old := Layout.from_dict({ "plot": [60, 50], "stands": [], "facilities": [] }, config)
	assert_eq(int(old.flood["per_side"]), 0, "old saves get the defaults")


func test_giant_flag_settings() -> void:
	var s := Season.create(config, Layout.create(config, "in"), 1)
	s.club.cash = 1e9
	assert_eq(s.build_stand(Stand.make("N", "terrace", 0, s.layout.pitch.size.x, 6)), "")
	assert_eq(s.set_stand_extra(0, "display", { "giant": "on", "flag": "crest", "spread": 1.0 }), "")
	assert_ne(s.set_stand_extra(0, "display", { "giant": "sometimes" }), "")
	assert_ne(s.set_stand_extra(0, "display", { "flag": "tartan" }), "")
	assert_ne(s.set_stand_extra(0, "display", { "spread": 2.0 }), "")
	var back := Layout.from_dict(JSON.parse_string(JSON.stringify(s.layout.to_dict())), config)
	assert_eq(String(back.stands[0].extra("display")["flag"]), "crest")


func test_corner_stands_take_every_tier_and_deep_rows() -> void:
	var s := Season.create(config, Layout.create(config, "in"), 1)
	s.club.cash = 1e10
	s.club.peak_fanbase = 1e9
	for side in ["N", "S", "E", "W"]:
		for k in 3:
			s.buy_land(side)
	var p := s.layout.pitch
	assert_eq(s.build_stand(Stand.make("N", "seated", 0, Stand.side_length("N", p), 10)), "")
	assert_eq(s.build_stand(Stand.make("W", "seated", 0, Stand.side_length("W", p), 10)), "")
	assert_eq(s.set_tiers(0, 3), "")
	assert_eq(s.set_tiers(1, 3), "")
	assert_eq(s.build_stand(Stand.make_corner("NW", "seated", 10)), "")
	assert_eq(s.set_tiers(2, config.integer("layout/max_tiers")), "", "a corner can be as tall as the sides")
	assert_eq(s.set_overhang(2, 2), "")
	assert_eq(s.resize_stand(2, 0, 12, 12), "", "and as deep")
	assert_gt(s.layout.stands[2].capacity(config.stand_type("seated")), 1000)


func test_corner_roundness() -> void:
	var s := Season.create(config, Layout.create(config, "in"), 1)
	s.club.cash = 1e10
	s.club.peak_fanbase = 1e9
	for side in ["N", "W"]:
		for k in 3:
			s.buy_land(side)
	assert_eq(s.build_stand(Stand.make_corner("NW", "seated", 10)), "")
	var st := s.layout.stands[0]
	var t := config.stand_type("seated")
	var square := st.capacity(t)
	assert_eq(s.set_corner_shape(0, "rounded"), "")
	var circle := st.capacity(t)
	assert_eq(s.set_corner_roundness(0, 0.3), "")
	var tight := st.capacity(t)
	assert_lt(circle, tight, "a squarer corner holds more than a quarter circle")
	assert_lt(tight, square + 1, "but no more than a square one")
	assert_ne(s.set_corner_roundness(0, 0.05), "")
	var back := Layout.from_dict(JSON.parse_string(JSON.stringify(s.layout.to_dict())), config)
	assert_almost_eq(back.stands[0].roundness, 0.3, 0.001)
	assert_eq(back.stands[0].capacity(t), tight)
