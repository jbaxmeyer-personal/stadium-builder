extends SceneTree
## A simple "sensible player" bot: starts on an empty plot, grows whichever
## stand type is selling out, adds facilities as crowds grow, never touches
## prices. Used to check the game's core promise: play reasonably and the
## stadium grows.
##   godot --headless -s tools/autoplay.gd -- [--seed=S] [--seasons=N]

const HOME_SIDE := { "terrace": "N", "seated": "S", "premium": "W" }
const FANS_PER_KIOSK := 1500
const FANS_PER_RESTROOM := 2500
const RESERVE := 20000.0

var config: SimConfig
var game: Season


func _init() -> void:
	var seed := 1
	var seasons := 5
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--seasons="):
			seasons = int(arg.get_slice("=", 1))
	config = SimConfig.load_default()
	game = Season.create(config, Layout.create(config, "Autoplay"), seed)
	print("division / promoted per season shown at line end")
	print("season  W-D-L  fans start->end   avg crowd  capacity  atmos  mood  cash end   stands/facilities")
	for k in seasons:
		while not game.is_over():
			invest()
			game.play_next()
		var r := game.summary()
		var pos := game.position()
		print("%6d  %d-%d-%d  %6.0f -> %6.0f  %9.0f  %8d  %5.1f  %4.0f  %9s   %d/%d" % [
			r.season_number, r.wins, r.draws, r.losses, r.fanbase_start, r.fanbase_end,
			r.attendance_avg, game.layout.capacity_total(config), r.atmosphere_avg, r.mood_end,
			Season.money(r.cash_end), game.layout.stands.size(), game.layout.facilities.size()]
			+ "   %s %s, %dpts%s  squad %s/match" % [r.division_name, _ord(pos), r.points, "  PROMOTED" if game.promotion_earned() else ("  RELEGATED" if game.relegated() else ""),
				Season.money(game.club.wage(config))])
		# a sensible chairman: half of last season's income goes on wages, like
		# a real club; never more than the club takes in
		var income := float(r.revenue.get("total", 0.0)) / maxf(1.0, r.matches)
		game.set_squad_budget(maxf(1000.0, income * 0.5))
		game.start_next_season()
	quit(0)


func invest() -> void:
	for _i in 20:  # a few actions per match at most
		if not (grow_transport() or grow_facilities() or grow_stands()):
			return


## Keep transport ahead of the crowd: bus stops and car parks, then a subway.
func grow_transport() -> bool:
	var crowd := 0.0
	for type_id in HOME_SIDE:
		crowd += min(expected_demand(type_id), capacity_of(type_id))
	if crowd < 0.9 * game.layout.transport_capacity(config):
		return false
	for id in ["subway", "bus_stop", "car_park"]:
		if config.facility_type(id).build_cost > game.club.cash - RESERVE:
			continue
		for y in range(game.layout.plot.position.y, game.layout.plot.end.y):
			for x in range(game.layout.plot.position.x, game.layout.plot.end.x):
				if game.build_facility(Facility.make(id, Vector2i(x, y))) == "":
					return true
	return false


func expected_demand(type_id: String) -> float:
	var t := config.stand_type(type_id)
	return game.club.fanbase * t.demand_share


func capacity_of(type_id: String) -> int:
	var c := 0
	for s in game.layout.stands:
		if s.type_id == type_id:
			c += s.capacity(config.stand_type(s.type_id))
	return c


func grow_stands() -> bool:
	for type_id in HOME_SIDE:
		if expected_demand(type_id) < 0.95 * capacity_of(type_id):
			continue
		var idx := stand_index(HOME_SIDE[type_id], type_id)
		if idx == -1:
			var side: String = HOME_SIDE[type_id]
			var side_len := Stand.side_length(side, game.layout.pitch)
			for length in [10, 6, 3]:
				if try(func(): return game.build_stand(Stand.make(side, type_id, (side_len - length) / 2, length, 1))):
					return true
			continue
		var s := game.layout.stands[idx]
		var side_len2 := Stand.side_length(s.side, game.layout.pitch)
		var options := [
			[s.offset, min(side_len2 - s.offset, s.length + 4), s.depth],
			[max(0, s.offset - 4), s.length + (s.offset - max(0, s.offset - 4)), s.depth],
			[s.offset, s.length, s.depth + 1],
		]
		for o in options:
			if o[1] == s.length and o[2] == s.depth:
				continue
			if try(func(): return game.resize_stand(idx, o[0], o[1], o[2])):
				return true
	return false


func grow_facilities() -> bool:
	var crowd := 0.0
	for type_id in HOME_SIDE:
		crowd += min(expected_demand(type_id), capacity_of(type_id))
	var want := { "kiosk": ceili(crowd / FANS_PER_KIOSK), "restroom": ceili(crowd / FANS_PER_RESTROOM) }
	for f_id in want:
		var have := 0
		for f in game.layout.facilities:
			if f.type_id == f_id:
				have += 1
		if have >= want[f_id]:
			continue
		var tile := free_concourse_tile()
		if tile != Vector2i(-1, -1) and try(func(): return game.build_facility(Facility.make(f_id, tile))):
			return true
	return false


## Free first-row concourse tile farthest from existing facilities (spreads them out).
func free_concourse_tile() -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := -1
	for si in game.layout.stands.size():
		var s := game.layout.stands[si]
		for p in game.layout.stand_concourse(s, config):
			var d := 1000
			for f in game.layout.facilities:
				d = min(d, absi(f.pos.x - p.x) + absi(f.pos.y - p.y))
			if d > best_d and d > 0:
				best_d = d
				best = p
	return best


func stand_index(side: String, type_id: String) -> int:
	for i in game.layout.stands.size():
		if game.layout.stands[i].side == side and game.layout.stands[i].type_id == type_id:
			return i
	return -1


## Runs a command (Season commands are atomic: failure changes nothing).
## The bot stops spending once cash falls under its reserve.
func try(cmd: Callable) -> bool:
	if game.club.cash < RESERVE:
		return false
	var err: String = cmd.call()
	return err == ""


static func _ord(n: int) -> String:
	var suf := "th"
	if n % 100 < 11 or n % 100 > 13:
		suf = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suf]
