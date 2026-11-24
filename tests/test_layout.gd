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
