extends GutTest
## Roads, paths and landscaping: transport needs a road to the street, fans
## walk faster on paving, and painted tiles cost money and save.

var config: SimConfig


func before_each() -> void:
	config = SimConfig.load_default()


func _season() -> Season:
	var s := Season.create(config, Layout.create(config, "site"), 3)
	s.club.cash = 1e8
	s.club.peak_fanbase = 1e9
	var p := s.layout.pitch
	assert_eq(s.build_stand(Stand.make("S", "seated", 0, p.size.x, 4)), "")
	return s


func test_a_car_park_needs_a_road_unless_it_is_on_the_street() -> void:
	var s := _season()
	var l := s.layout
	var cap0 := l.transport_capacity(config)
	var ft := config.facility_type("car_park")
	# inside the plot, away from the edge: no road, no cars
	var pos := Vector2i(l.plot.position.x + 3, l.plot.position.y + 3)
	assert_eq(s.build_facility(Facility.make("car_park", pos)), "")
	var f := l.facilities[-1]
	assert_false(bool(l.transport_status(config)[f]["connected"]))
	assert_almost_eq(l.transport_capacity(config), cap0, 0.01, "unconnected adds nothing")
	# a road from the plot edge to the car park
	var road: Array = []
	for y in range(l.plot.position.y, pos.y):
		road.append(Vector2i(pos.x, y))
	assert_eq(s.paint_site(road, "road"), "")
	assert_true(bool(l.transport_status(config)[f]["connected"]))
	assert_gt(l.transport_capacity(config), cap0)
	# a car park on the plot edge sits on the street already
	var edge := Vector2i(l.plot.end.x - ft.size.x, l.plot.position.y)
	assert_eq(s.build_facility(Facility.make("car_park", edge)), "")
	assert_true(bool(l.transport_status(config)[l.facilities[-1]]["connected"]))


func test_paths_shorten_the_walk() -> void:
	var s := _season()
	var l := s.layout
	var pos := Vector2i(l.plot.position.x, l.plot.end.y - config.facility_type("car_park").size.y)
	assert_eq(s.build_facility(Facility.make("car_park", pos)), "")
	var f := l.facilities[-1]
	var before: Dictionary = l.transport_status(config)[f]
	assert_true(bool(before["connected"]))
	# pave everything open between the car park and the south stand
	var tiles: Array = []
	for x in range(l.plot.position.x, l.plot.end.x):
		for y in range(l.pitch.end.y, l.plot.end.y):
			tiles.append(Vector2i(x, y))
	assert_eq(s.paint_site(tiles, "path_concrete"), "")
	var after: Dictionary = l.transport_status(config)[f]
	assert_lt(float(after["walk"]), float(before["walk"]), "paving is quicker than grass")
	assert_gte(float(after["factor"]), float(before["factor"]))


func test_painting_costs_saves_and_clears_under_buildings() -> void:
	var s := _season()
	var l := s.layout
	var cash := s.club.cash
	var t := Vector2i(l.plot.position.x + 1, l.plot.position.y + 1)
	assert_eq(s.paint_site([t, t + Vector2i.RIGHT], "tree_oak"), "")
	assert_almost_eq(cash - s.club.cash, 2.0 * float(config.site_items["tree_oak"]["cost"]), 0.01)
	assert_ne(s.paint_site([l.pitch.get_center()], "flowers"), "", "not on the pitch")
	assert_ne(s.paint_site([t], "rocket"), "")
	var back := Layout.from_dict(JSON.parse_string(JSON.stringify(l.to_dict())), config)
	assert_eq(back.site.get(t, ""), "tree_oak")
	assert_false(back.legacy_access)
	# a building on top clears them
	assert_eq(s.build_facility(Facility.make("statue", t)), "")
	assert_false(l.site.has(t))
	# clearing refunds part
	cash = s.club.cash
	assert_eq(s.paint_site([t + Vector2i.RIGHT], ""), "")
	assert_gt(s.club.cash, cash)


func test_old_saves_keep_their_transport() -> void:
	var l := Layout.from_dict({ "name": "old", "facilities": [{ "type": "car_park", "x": 10, "y": 10 }] }, config)
	assert_true(l.legacy_access)
	assert_true(bool(l.transport_status(config)[l.facilities[0]]["connected"]))
