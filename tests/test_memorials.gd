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
