extends SceneTree
## A "sensible human" bot: starts on an empty plot and builds like a player
## would. It grows whichever stand type sells out (full length first, then
## deeper, buying land when it runs out of room, then upper tiers), fills the
## corners, adds transport and facilities as crowds grow, and backs the squad
## with its income and its savings, spending more after promotion.
## Used to check the core promise: play sensibly and the club grows.
##   godot --headless -s tools/autoplay.gd -- [--seed=S] [--seasons=N] [--strategy=balanced|cheap|allin]
## Strategies: balanced (above), cheap (the minimum squad spend, every penny on
## the ground) and allin (every penny of income and savings on wages).

const HOME_SIDE := { "seated": "S", "terrace": "N", "family": "E", "premium": "W" }
const FANS_PER_KIOSK := 1500
const FANS_PER_RESTROOM := 2500
const RESERVE := 20000.0

var config: SimConfig
var game: Season
var strategy := "balanced"


func _init() -> void:
	var seed := 1
	var seasons := 5
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--seasons="):
			seasons = int(arg.get_slice("=", 1))
		elif arg.begins_with("--strategy="):
			strategy = arg.get_slice("=", 1)
	config = SimConfig.load_default()
	game = Season.create(config, Layout.create(config, "Autoplay"), seed)
	if strategy == "cheap":
		game.set_squad_budget(config.num("league/min_squad_budget"))
	print("strategy: ", strategy)
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
		var keys := PackedStringArray()
		for rk in r.revenue:
			if rk != "total" and float(r.revenue[rk]) > 0.0:
				keys.append("%s %dk" % [rk, roundi(float(r.revenue[rk]) / r.matches / 1000.0)])
		var ckeys := PackedStringArray()
		for ck in r.costs:
			if ck != "total" and float(r.costs[ck]) > 0.0:
				ckeys.append("%s %dk" % [ck, roundi(float(r.costs[ck]) / r.matches / 1000.0)])
		print("        per match: in %dk (%s) | out %dk (%s)" % [roundi(float(r.revenue.get("total", 0.0)) / r.matches / 1000.0), ", ".join(keys),
			roundi(float(r.costs.get("total", 0.0)) / r.matches / 1000.0), ", ".join(ckeys)])
		set_squad(r)
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
	for id in ["subway", "multi_storey", "bus_stop", "car_park"]:
		if config.facility_type(id).build_cost > game.club.cash - RESERVE:
			continue
		var ft := config.facility_type(id)
		var pl := game.layout.plot
		# like a player: outside links go on the street edge, then a path to the stands
		for y in range(pl.position.y, pl.end.y):
			for x in range(pl.position.x, pl.end.x):
				var pos := Vector2i(x, y)
				if ft.layer == "outside" and not (x == pl.position.x or y == pl.position.y or x + ft.size.x == pl.end.x or y + ft.size.y == pl.end.y):
					continue
				if game.build_facility(Facility.make(id, pos)) == "":
					if ft.layer == "outside":
						pave_to_pitch(Rect2i(pos, ft.size))
					if ft.layer == "underground":
						# a way up to the street, next to it
						var done := false
						for dy in range(-2, ft.size.y + 2):
							for dx in range(-2, ft.size.x + 2):
								if not done and game.build_facility(Facility.make("entrance", pos + Vector2i(dx, dy))) == "":
									done = true
					return true
	return false


## A straight paved path from a building toward the pitch, stopping at the stands.
func pave_to_pitch(r: Rect2i) -> void:
	var l := game.layout
	var c := l.pitch.get_center()
	var p := r.get_center()
	var tiles: Array = []
	var solid := l.solid_tiles(config)
	var step := Vector2i(signi(c.x - p.x), 0)
	var q := Vector2i(clampi(c.x, r.position.x, r.end.x - 1), p.y)
	if r.has_point(Vector2i(c.x, p.y)):
		step = Vector2i(0, signi(c.y - p.y))
		q = Vector2i(p.x, p.y)
	while r.has_point(q):
		q += step
	for i in 60:
		if not l.in_plot(q) or (solid.has(q) and not r.has_point(q)):
			break
		tiles.append(q)
		q += step
	if not tiles.is_empty():
		game.paint_site(tiles, "path_gravel" if game.club.cash < RESERVE * 3.0 else "path_concrete")


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
		if expected_demand(type_id) < 0.92 * capacity_of(type_id):
			continue
		if not game.is_unlocked(type_id):
			continue
		var side: String = HOME_SIDE[type_id]
		var side_len := Stand.side_length(side, game.layout.pitch)
		var idx := stand_index(side, type_id)
		if idx == -1:
			for length in [side_len, 18, 12, 6]:
				var off: int = (side_len - mini(length, side_len)) / 2
				if try(func(): return game.build_stand(Stand.make(side, type_id, off, mini(length, side_len), 2))):
					return true
			continue
		var s := game.layout.stands[idx]
		# 0. a roof once it's affordable (rain and snow empty open stands)
		if s.roof == "open" and game.club.cash > RESERVE * 2.0:
			if try(func(): return game.restyle_stand(idx, "cantilever", s.seat_color)):
				return true
		# 1. the full length of the pitch
		if s.length < side_len:
			if try(func(): return game.resize_stand(idx, 0, side_len, s.depth)):
				return true
		# 2. deeper, buying the land behind it when there's no room
		if s.depth < config.integer("layout/max_depth"):
			if try(func(): return game.resize_stand(idx, s.offset, s.length, s.depth + 1)):
				return true
			if game.land_cost(side) >= 0.0 and game.land_cost(side) < game.club.cash - RESERVE:
				if try(func(): return game.buy_land(side)) and try(func(): return game.resize_stand(idx, s.offset, s.length, s.depth + 1)):
					return true
		# 3. another tier on top
		if s.tiers < config.integer("layout/max_tiers") and game.is_unlocked("tier%d" % (s.tiers + 1)):
			if try(func(): return game.set_tiers(idx, s.tiers + 1)):
				return true
			if game.land_cost(side) >= 0.0 and try(func(): return game.buy_land(side)) and try(func(): return game.set_tiers(idx, s.tiers + 1)):
				return true
	# 4. close the corners once the sides are solid
	for corner in Stand.CORNERS:
		var have := false
		for st in game.layout.stands:
			if st.side == corner:
				have = true
		if have:
			continue
		var depth := 99
		for side in [corner[0], corner[1]]:
			var d := 0
			for st in game.layout.stands:
				if st.side == side:
					d = st.depth
			depth = mini(depth, d)
		if depth >= 4 and expected_demand("seated") > 0.85 * capacity_of("seated"):
			var c := Stand.make_corner(corner, "seated", depth)
			c.shape = "rounded"
			if try(func(): return game.build_stand(c)):
				return true
	return false


## Squad budget for next season, like a chairman would set it: about 55% of
## income, topped up from savings, and a push to compete after promotion.
func set_squad(r: SeasonReport) -> void:
	var income := float(r.revenue.get("total", 0.0)) / maxf(1.0, r.matches)
	var matches := 2.0 * (config.integer("league/teams") - 1)
	if strategy == "cheap":
		game.set_squad_budget(config.num("league/min_squad_budget"))
		return
	if strategy == "allin":
		# all income and all savings (bar a small float) go on wages
		var all_in := income + maxf(0.0, game.club.cash - RESERVE * 5.0) / matches
		game.set_squad_budget(maxf(1000.0, roundf(all_in / 500.0) * 500.0))
		return
	var target := income * 0.55
	# spend spare savings over about three seasons (keep a buffer for building)
	var spare := game.club.cash - 2_000_000.0
	if spare > 0.0:
		target += spare / (matches * 3.0)
	# a newly promoted side spends to survive, if it can afford a season of it
	var div := game.club.division + (1 if game.promotion_earned() else (-1 if game.relegated() else 0))
	var norm := float(config.division(div)["squad_wage"])
	if target < norm and game.club.cash > (norm - target) * matches:
		target = norm
	game.set_squad_budget(maxf(1000.0, roundf(target / 500.0) * 500.0))


func grow_facilities() -> bool:
	var crowd := 0.0
	for type_id in HOME_SIDE:
		crowd += min(expected_demand(type_id), capacity_of(type_id))
	var want := { "kiosk": ceili(crowd / FANS_PER_KIOSK), "restroom": ceili(crowd / FANS_PER_RESTROOM),
		"bar": ceili(crowd / 3000.0), "merch": ceili(crowd / 8000.0), "first_aid": ceili(crowd / 15000.0) }
	for f_id in want:
		var have := 0
		for f in game.layout.facilities:
			if f.type_id == f_id:
				have += 1
		if have >= want[f_id] or not game.is_unlocked(f_id):
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
