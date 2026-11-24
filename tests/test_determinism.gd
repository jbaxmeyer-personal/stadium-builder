extends GutTest

const LAYOUTS := ["res://data/layouts/terrace_wall.json", "res://data/layouts/seated_bowl.json"]

var config: SimConfig


func before_all() -> void:
	config = SimConfig.load_default()


func _run(path: String, seed: int) -> Dictionary:
	var layout := Layout.load_json(path, config)
	var club := ClubState.create(config)
	return MatchdaySim.run(config, layout, club, Fixture.make("Rovers"), seed).to_dict()


func test_same_layout_and_seed_gives_identical_report() -> void:
	for path in LAYOUTS:
		for seed in [1, 42, 99999]:
			assert_eq_deep(_run(path, seed), _run(path, seed))


func test_report_text_is_identical_too() -> void:
	var layout := Layout.load_json(LAYOUTS[0], config)
	var a := MatchdaySim.run(config, layout, ClubState.create(config), Fixture.make("Rovers"), 7)
	var b := MatchdaySim.run(config, layout, ClubState.create(config), Fixture.make("Rovers"), 7)
	assert_eq(a.to_text(), b.to_text())


func test_different_seeds_vary_the_outcome() -> void:
	var rolls := {}
	for seed in range(1, 21):
		rolls[_run(LAYOUTS[0], seed)["roll"]] = true
	assert_gt(rolls.size(), 1, "seed should change the RNG draws")


func test_run_does_not_mutate_inputs() -> void:
	var layout := Layout.load_json(LAYOUTS[1], config)
	var club := ClubState.create(config)
	var before_layout := layout.to_dict()
	var before_cash := club.cash
	var before_mood := club.mood
	MatchdaySim.run(config, layout, club, Fixture.make("Rovers"), 3)
	assert_eq_deep(layout.to_dict(), before_layout)
	assert_eq(club.cash, before_cash)
	assert_eq(club.mood, before_mood)


func test_json_round_trip_gives_same_layout_and_report() -> void:
	var original := Layout.load_json(LAYOUTS[0], config)
	var tmp := "user://roundtrip_layout.json"
	assert_eq(original.save_json(tmp), OK)
	var reloaded := Layout.load_json(tmp, config)
	assert_eq_deep(reloaded.to_dict(), original.to_dict())
	var club := ClubState.create(config)
	var fx := Fixture.make("Rovers", true)
	assert_eq_deep(
		MatchdaySim.run(config, reloaded, club, fx, 11).to_dict(),
		MatchdaySim.run(config, original, club, fx, 11).to_dict())
	DirAccess.remove_absolute(tmp)
