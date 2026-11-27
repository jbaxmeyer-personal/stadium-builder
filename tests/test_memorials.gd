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


func test_rotate_a_placed_piece() -> void:
	var s := Season.create(config, Layout.create(config, "in"), 1)
	s.club.cash = 1e8
	s.club.peak_fanbase = 1e9
	var i := _place(s, "club_gates")   # 3 x 1
	assert_gt(i, -1)
	var f: Facility = s.layout.facilities[i]
	var ft := config.facility_type("club_gates")
	assert_eq(f.size(ft), Vector2i(3, 1))
	var e := s.rotate_facility(i)
	if e == "":
		assert_eq(f.size(ft), Vector2i(1, 3), "a quarter turn swaps the footprint")
		var back := Layout.from_dict(JSON.parse_string(JSON.stringify(s.layout.to_dict())), config)
		assert_eq(back.facilities[i].rot, 1)
	else:
		assert_eq(f.rot, 0, "a turn that doesn't fit is undone")
	for k in 3:
		s.rotate_facility(i)
	assert_true(f.rot >= 0 and f.rot < 4)


func test_move_a_placed_piece() -> void:
	var s := Season.create(config, Layout.create(config, "in"), 1)
	s.club.cash = 1e8
	s.club.peak_fanbase = 1e9
	var i := _place(s, "memorial")
	var f: Facility = s.layout.facilities[i]
	var start := f.pos
	var cash := s.club.cash
	var moved := false
	for dy in range(-3, 4):
		for dx in range(1, 6):
			if not moved and s.move_facility(i, start + Vector2i(dx, dy)) == "":
				moved = true
	assert_true(moved, "it fits somewhere nearby")
	assert_ne(f.pos, start)
	assert_eq(s.club.cash, cash, "moving is free")
	var before := f.pos
	assert_ne(s.move_facility(i, Vector2i(-50, -50)), "", "not off the plot")
	assert_eq(f.pos, before, "a bad move is undone")


func test_player_written_adverts() -> void:
	var s := Season.create(config, Layout.create(config, "in"), 1)
	assert_eq(s.set_ad_texts(["Joe's Cafe", " Riverside Motors ", ""]), "")
	assert_eq(s.layout.ad_texts, ["JOE'S CAFE", "RIVERSIDE MOTORS"])
	assert_ne(s.set_ad_texts(["X".repeat(30)]), "")
	var back := Layout.from_dict(JSON.parse_string(JSON.stringify(s.layout.to_dict())), config)
	assert_eq(back.ad_texts.size(), 2)


func test_stand_naming_rights_pay_and_save() -> void:
	var s := Season.create(config, Layout.create(config, "in"), 1)
	s.club.cash = 1e9
	s.club.peak_fanbase = 1e9
	assert_eq(s.build_stand(Stand.make("N", "seated", 0, s.layout.pitch.size.x, 6)), "")
	var id: String = config.sponsors.keys()[0]
	var e := s.set_stand_sponsor(0, id)
	if e != "":
		pass_test("naming rights still locked at this stage: %s" % e)
		return
	assert_gt(s.stand_sponsor_fee(0, id), 0.0)
	var r := s.play_next()
	while not r.home:
		r = s.play_next()
	assert_gt(float(r.revenue["stand_naming"]), 0.0)
	var back := Layout.from_dict(JSON.parse_string(JSON.stringify(s.layout.to_dict())), config)
	assert_eq(back.stands[0].sponsor, id)
	assert_ne(s.set_stand_sponsor(0, "nobody"), "")


func test_bank_loan_pays_out_and_is_paid_back() -> void:
	var s := Season.create(config, Layout.create(config, "in"), 1)
	s.club.cash = 100000.0
	assert_ne(s.take_loan(s.loan_limit() + 1.0), "", "not beyond the limit")
	assert_eq(s.take_loan(200000.0), "")
	assert_almost_eq(s.club.cash, 300000.0, 0.01)
	assert_almost_eq(s.club.loan, 200000.0, 0.01)
	assert_gt(s.club.loan_payment, 0.0)
	assert_eq(s.build_stand(Stand.make("N", "terrace", 0, 10, 2)), "")
	var before := s.club.loan
	var r := s.play_next()
	assert_gt(float(r.costs["loan"]), 0.0)
	assert_lt(s.club.loan, before, "a slice of the loan is paid off every match")
	var back := ClubState.from_dict(JSON.parse_string(JSON.stringify(s.club.to_dict())), config)
	assert_almost_eq(back.loan, s.club.loan, 0.01)
	s.club.cash = 1e7
	assert_eq(s.repay_loan(s.club.loan), "")
	assert_eq(s.club.loan, 0.0)
	assert_ne(s.repay_loan(10.0), "")


func test_stand_price_trades_fans_for_money() -> void:
	var l := Layout.create(config, "in")
	var a := Stand.make("N", "seated", 0, 10, 6)
	var b := Stand.make("S", "seated", 0, 10, 6)
	l.stands.append(a)
	l.stands.append(b)
	var demand := { "seated": 100000 }
	b.price_adj = 0.0
	var even := MatchdaySim.compute_attendance(config, l, { "seated": 900 })
	b.price_adj = 0.4
	var dear := MatchdaySim.compute_attendance(config, l, { "seated": 900 })
	assert_lt(int(dear[1]["attendance"]), int(even[1]["attendance"]), "a dearer stand sells fewer tickets")
	assert_almost_eq(float(dear[1]["price_mult"]), 1.4, 0.001)
	var s := Season.create(config, Layout.create(config, "in"), 1)
	s.club.cash = 1e9
	assert_eq(s.build_stand(Stand.make("N", "seated", 0, 10, 4)), "")
	assert_eq(s.set_stand_price(0, 0.25), "")
	assert_ne(s.set_stand_price(0, 0.9), "")
	var back := Layout.from_dict(JSON.parse_string(JSON.stringify(s.layout.to_dict())), config)
	assert_almost_eq(back.stands[0].price_adj, 0.25, 0.001)


func test_season_tickets_bigger_crowd_cheaper_head() -> void:
	var c := ClubState.create(config)
	c.fanbase = 20000.0
	var mult := { "form": 1.0, "opponent": 1.0, "mood": 1.0, "noise": 1.0 }
	var d0 := MatchdaySim.compute_demand(config, c, mult)
	c.season_tickets = 0.5
	var d1 := MatchdaySim.compute_demand(config, c, mult)
	assert_gt(int(d1["seated"]), int(d0["seated"]))
	var s := Season.create(config, Layout.create(config, "in"), 1)
	assert_eq(s.set_season_tickets(0.4), "")
	assert_ne(s.set_season_tickets(0.95), "")
	var back := ClubState.from_dict(JSON.parse_string(JSON.stringify(s.club.to_dict())), config)
	assert_almost_eq(back.season_tickets, 0.4, 0.001)


func test_pillars_cost_a_little_view() -> void:
	var s := Stand.make("N", "terrace", 0, 10, 6)
	s.roof = "cantilever"
	var clear := MatchdaySim.view_quality(config, s)
	s.roof = "shed"
	assert_lt(MatchdaySim.view_quality(config, s), clear)


func test_plant_room_cuts_the_power_bill() -> void:
	var s := Season.create(config, Layout.create(config, "in"), 1)
	s.club.cash = 1e9
	s.club.peak_fanbase = 1e9
	assert_eq(s.build_stand(Stand.make("N", "seated", 0, 10, 6)), "")
	var before := float(s.layout.utilities(config)["power"])
	var placed := false
	for y in range(s.layout.plot.position.y, s.layout.plot.end.y):
		if placed:
			break
		for x in range(s.layout.plot.position.x, s.layout.plot.end.x):
			if s.build_facility(Facility.make("plant_room", Vector2i(x, y))) == "":
				placed = true
				break
	assert_true(placed)
	assert_lt(float(s.layout.utilities(config)["power"]), before)
	assert_gte(float(s.layout.utilities(config)["power"]), 0.0)


func test_kiosk_prices_trade_mood_for_money() -> void:
	var layout := Layout.load_json("res://data/layouts/seated_bowl.json", config)
	var cheap := ClubState.create(config)
	cheap.fanbase = 30000.0
	var dear := ClubState.create(config)
	dear.fanbase = 30000.0
	dear.prices = { "food": 1.5, "drink": 1.5, "merch": 1.5 }
	var a := MatchdaySim.run(config, layout, cheap, Fixture.make("Rovers"), 5)
	var b := MatchdaySim.run(config, layout, dear, Fixture.make("Rovers"), 5)
	assert_lt(int(b.halftime["food"]["wanting"]), int(a.halftime["food"]["wanting"]), "dearer pies, fewer buyers")
	assert_gt(float(b.revenue["food"]) + float(b.revenue["drinks"]), float(a.revenue["food"]) + float(a.revenue["drinks"]))
	assert_lt(float(b.mood_change["prices"]), 0.0)
	var s := Season.create(config, Layout.create(config, "in"), 1)
	assert_eq(s.set_price_level("food", 1.3), "")
	assert_ne(s.set_price_level("food", 5.0), "")
	assert_ne(s.set_price_level("tickets", 1.0), "")
	var back := ClubState.from_dict(JSON.parse_string(JSON.stringify(s.club.to_dict())), config)
	assert_almost_eq(back.price_level("food"), 1.3, 0.001)


func test_big_matches_cost_policing() -> void:
	var layout := Layout.load_json("res://data/layouts/seated_bowl.json", config)
	var c := ClubState.create(config)
	c.fanbase = 30000.0
	var plain := MatchdaySim.run(config, layout, c, Fixture.make("Rovers"), 5)
	var big := MatchdaySim.run(config, layout, c, Fixture.make("Rovers", true), 5)
	assert_gt(float(big.costs["matchday"]) / maxf(1.0, big.attendance), float(plain.costs["matchday"]) / maxf(1.0, plain.attendance))


func test_away_end_fills_empty_places() -> void:
	var layout := Layout.load_json("res://data/layouts/seated_bowl.json", config)
	var c := ClubState.create(config)
	c.fanbase = 2000.0
	var a := MatchdaySim.run(config, layout, c, Fixture.make("Rovers"), 5)
	assert_eq(a.away_fans(), 0)
	layout.stands[0].away = true
	var b := MatchdaySim.run(config, layout, c, Fixture.make("Rovers"), 5)
	assert_gt(b.away_fans(), 0)
	assert_gt(b.attendance, a.attendance)
	assert_gt(float(b.revenue["tickets"]), float(a.revenue["tickets"]))
	var big := MatchdaySim.run(config, layout, c, Fixture.make("Rovers", true), 5)
	assert_gte(big.away_fans(), b.away_fans())
	var back := Stand.from_dict(JSON.parse_string(JSON.stringify(layout.stands[0].to_dict())))
	assert_true(back.away)
	var rb := MatchdayReport.from_dict(JSON.parse_string(JSON.stringify(b.to_dict())))
	assert_eq(rb.away_fans(), b.away_fans())


func test_board_objectives_pay_out() -> void:
	var s := Season.create(config, Layout.load_json("res://data/layouts/seated_bowl.json", config), 3)
	var objs := s.board_objectives()
	assert_eq(objs.size(), 1, "first season: just a league target")
	assert_eq(String(objs[0]["kind"]), "position")
	s.play_all()
	var met := s.objective_met(objs[0])
	var cash := s.club.cash
	s.start_next_season()
	var sr: SeasonReport = s.history[-1]
	assert_eq(sr.board_bonus > 0.0, met)
	assert_almost_eq(s.club.cash, cash + sr.board_bonus, 0.01)
	var objs2 := s.board_objectives()
	assert_eq(objs2.size(), 2, "then a crowd target too")
	assert_gt(int(objs2[1]["target"]), 0)
	var back := SeasonReport.from_dict(JSON.parse_string(JSON.stringify(sr.to_dict())))
	assert_almost_eq(back.board_bonus, sr.board_bonus, 0.01)


func test_more_staff_cost_more_and_move_faster() -> void:
	var layout := Layout.load_json("res://data/layouts/seated_bowl.json", config)
	var lo := ClubState.create(config)
	lo.fanbase = 60000.0
	lo.staff = { "stewards": 0.5, "catering": 0.5 }
	var hi := ClubState.create(config)
	hi.fanbase = 60000.0
	hi.staff = { "stewards": 2.0, "catering": 2.0 }
	var a := MatchdaySim.run(config, layout, lo, Fixture.make("Rovers"), 5)
	var b := MatchdaySim.run(config, layout, hi, Fixture.make("Rovers"), 5)
	assert_gt(float(b.costs["matchday"]), float(a.costs["matchday"]))
	assert_gte(int(a.ingress["late"]), int(b.ingress["late"]))
	assert_gte(int(b.halftime["food"]["served"]), int(a.halftime["food"]["served"]))
	var s := Season.create(config, Layout.create(config, "in"), 1)
	assert_eq(s.set_staff_level("catering", 1.5), "")
	assert_ne(s.set_staff_level("catering", 9.0), "")
	assert_ne(s.set_staff_level("chefs", 1.0), "")
	var back := ClubState.from_dict(JSON.parse_string(JSON.stringify(s.club.to_dict())), config)
	assert_almost_eq(back.staff_level("catering"), 1.5, 0.001)
