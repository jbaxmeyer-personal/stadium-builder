extends GutTest


func test_under_capacity_everyone_served() -> void:
	var q := QueueModel.simulate(100, 15.0, 15.0)  # capacity 225
	assert_eq(q["served"], 100)
	assert_eq(q["lost"], 0)


func test_over_capacity_excess_is_lost() -> void:
	var q := QueueModel.simulate(500, 15.0, 15.0)  # capacity 225
	assert_eq(q["served"], 225)
	assert_eq(q["lost"], 275)


func test_wait_is_queued_fans_over_rate() -> void:
	var q := QueueModel.simulate(300, 15.0, 15.0)
	assert_almost_eq(q["wait_max_min"], 20.0, 0.0001)
	# 225 served in a single rush: mean wait = 225 / (2 * 15)
	assert_almost_eq(q["wait_avg_min"], 7.5, 0.0001)


func test_walking_shrinks_the_window() -> void:
	var q := QueueModel.simulate(500, 10.0, 15.0, 5.0)  # usable 10 min -> capacity 100
	assert_almost_eq(q["usable_window_min"], 10.0, 0.0001)
	assert_eq(q["served"], 100)
	assert_eq(q["lost"], 400)


func test_walk_longer_than_window_serves_nobody() -> void:
	var q := QueueModel.simulate(50, 30.0, 15.0, 20.0)
	assert_eq(q["usable_window_min"], 0.0)
	assert_eq(q["served"], 0)
	assert_eq(q["lost"], 50)


func test_fractional_capacity_rounds_down() -> void:
	var q := QueueModel.simulate(1000, 7.5, 15.0, 0.1)  # 7.5 * 14.9 = 111.75
	assert_eq(q["served"], 111)


func test_zero_arrivals() -> void:
	var q := QueueModel.simulate(0, 15.0, 15.0)
	assert_eq(q["served"], 0)
	assert_eq(q["lost"], 0)
	assert_eq(q["wait_max_min"], 0.0)


func test_fans_are_conserved() -> void:
	for arrivals in [0, 1, 37, 224, 225, 226, 5000]:
		var q := QueueModel.simulate(arrivals, 15.0, 15.0, 2.3)
		assert_eq(q["served"] + q["lost"], arrivals)
