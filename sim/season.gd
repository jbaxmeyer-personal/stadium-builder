class_name Season
extends RefCounted
## A running club: seasons of home matches on a layout that the player keeps
## building. Any starting layout is paid for out of starting cash. Between
## matches the player may build, resize, demolish and change prices; cash,
## fanbase, form and mood carry over, including across seasons.
## Match seeds come from one seeded RNG, so same layout + seed + commands = same game.

var config: SimConfig
var layout: Layout
var club: ClubState
var seed: int
var season_number: int = 1
var league: League                         # this season's division: teams, fixtures, results, table
var fixtures: Array[Fixture] = []          # the club's own matches, one per league round
var match_seeds: Array[int] = []
var round_seeds: Array[int] = []           # the rest of each round's games
var reports: Array[MatchdayReport] = []   # this season's matches
var history: Array[SeasonReport] = []     # finished seasons
var build_spend: float = 0.0              # construction spend this season
var demolish_refunds: float = 0.0
var land_spend: float = 0.0
var milestone_rewards: float = 0.0
var event_income: float = 0.0            # concerts and other non-matchday events this season
var events_held: int = 0
var pitch_damage: float = 0.0            # how badly the last event cut up the pitch (gone after the next home game)
var start_cash: float                     # cash / mood / fanbase when this season began
var start_mood: float
var start_fanbase: float
var _rng := RandomNumberGenerator.new()
## This season's continental competition ({} = none), from last season's finish.
var continental: Dictionary = {}
var draws: Array = []                      # draws made this season (for the UI): {comp, stage, opponent, home, neutral}


static func create(p_config: SimConfig, p_layout: Layout, p_seed: int) -> Season:
	var s := Season.new()
	s.config = p_config
	s.layout = p_layout
	s.seed = p_seed
	s.club = ClubState.create(p_config)
	s._mark_start()
	s.build_spend = p_layout.build_cost(p_config)
	s.club.cash -= s.build_spend
	s._rng.seed = p_seed
	s._make_fixtures()
	return s


func _mark_start() -> void:
	start_cash = club.cash
	start_mood = club.mood
	start_fanbase = club.fanbase


func _make_fixtures() -> void:
	fixtures.clear()
	match_seeds.clear()
	round_seeds.clear()
	league = League.create(config, seed * 7919 + season_number * 31 + club.division, club.division, club.club_name)
	# Kick-off times and weather come from their own RNG so they don't change
	# the match seeds.
	var names := RandomNumberGenerator.new()
	names.seed = seed * 7919 + season_number
	var n := league.round_count()
	var winter_from := n / 3
	var winter_to := 2 * n / 3
	for i in n:
		var g := league.our_game(i)
		var fx := Fixture.make(String(league.teams[g["opponent"]]["name"]))
		fx.home = g["home"]
		fx.round = i
		fx.opponent_team = g["opponent"]
		fx.opponent_rating = float(league.teams[g["opponent"]]["rating"])
		fx.evening = (i + 1) % config.integer("season/evening_every") == 0
		var roll := names.randf()
		if i >= winter_from and i < winter_to and roll < config.num("weather/snow_chance"):
			fx.weather = "snow"
		elif roll > 1.0 - config.num("weather/rain_chance"):
			fx.weather = "rain"
		fixtures.append(fx)
		match_seeds.append(_rng.randi())
		round_seeds.append(_rng.randi())
	# the two strongest visitors are the big games of the season
	var ratings := []
	for fx in fixtures:
		if fx.home:
			ratings.append(fx.opponent_rating)
	ratings.sort()
	for fx in fixtures:
		if fx.home and ratings.size() >= 2 and fx.opponent_rating >= ratings[ratings.size() - 2]:
			fx.big = true
			fx.evening = true   # big games go under the lights
	draws.clear()
	_draw_cup(0)
	if not continental.is_empty():
		_schedule_continental_groups()


# --- cups and continental nights ----------------------------------------------

func _comp_rng(key: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed, season_number, key])
	return r


## Puts a midweek match straight after a league round (or next, if that's past).
func _insert_after_league_round(fx: Fixture, after_round: int) -> void:
	var at := fixtures.size()
	for k in fixtures.size():
		if fixtures[k].is_league() and fixtures[k].round == after_round:
			at = k + 1
	# after any other midweek match already sitting there
	while at < fixtures.size() and not fixtures[at].is_league():
		at += 1
	at = maxi(at, reports.size())
	fixtures.insert(at, fx)


## A random club from somewhere in the pyramid (cups mix the divisions).
func _cup_opponent(rng: RandomNumberGenerator, stage_i: int) -> Dictionary:
	var top := config.divisions.size() - 1
	# later rounds draw stronger sides
	var d := clampi(rng.randi_range(0, top) + (1 if stage_i >= 3 and rng.randf() < 0.5 else 0), 0, top)
	var wage := float(config.division(d)["squad_wage"]) * rng.randf_range(0.7, 1.4)
	var name: String = config.opponents[rng.randi_range(0, config.opponents.size() - 1)] if not config.opponents.is_empty() else "Cup Rivals"
	return { "name": name, "rating": League.rating_for_wage(wage), "division": d }


func _draw_cup(stage_i: int) -> void:
	var cup := config.cup
	if cup.is_empty() or stage_i >= (cup["rounds"] as Array).size():
		return
	var rng := _comp_rng("cup%d" % stage_i)
	var o := _cup_opponent(rng, stage_i)
	var fx := Fixture.make(o["name"])
	fx.competition = "cup"
	fx.comp_name = cup["name"]
	fx.stage = cup["rounds"][stage_i]
	fx.round = stage_i
	fx.opponent_team = -1
	fx.opponent_rating = o["rating"]
	fx.knockout = true
	fx.evening = true
	var final := stage_i == (cup["rounds"] as Array).size() - 1
	fx.neutral = final
	fx.home = (not final) and rng.randf() < 0.5
	fx.big = int(o["division"]) > club.division or stage_i >= int(cup.get("big_from_round", 99))
	fx.prize_win = float(cup["prize_win"][stage_i])
	fx.tv = float(cup["tv"][stage_i])
	fx.seed = rng.randi()
	_insert_after_league_round(fx, int(cup["after_league_round"][stage_i]))
	draws.append({ "comp": fx.comp_name, "stage": fx.stage, "opponent": fx.opponent, "home": fx.home, "neutral": fx.neutral, "division": o["division"] })


func _schedule_continental_groups() -> void:
	var sch := config.continental_schedule
	var rng := _comp_rng("cont-groups")
	var names: Array = []
	for k in 3:
		names.append("%s %s" % [["Real", "Sporting", "Olympique", "Dynamo", "Inter", "Athletic", "Racing", "Union", "Red Star", "Ajax"][rng.randi_range(0, 9)],
			["Lisboa", "Milano", "Kyiv", "Porto", "Lyon", "Bilbao", "Praha", "Wien", "Beograd", "Brugge", "Napoli", "Sevilla"][rng.randi_range(0, 11)]])
	var after: Array = sch["group_after"]
	for k in 6:
		var fx := Fixture.make(names[k % 3])
		fx.competition = "continental"
		fx.comp_name = continental["name"]
		fx.stage = "Group game %d" % (k + 1)
		fx.round = k
		fx.opponent_team = -1
		fx.opponent_rating = League.rating_for_wage(float(continental["strength_wage"]) * rng.randf_range(0.6, 1.5))
		fx.home = k < 3 if (k % 2 == 0) else k >= 3
		fx.evening = true
		fx.big = true
		fx.prize_win = float(continental["group_prize_win"])
		fx.prize_draw = float(continental["group_prize_draw"])
		fx.tv = float(continental["tv"])
		fx.seed = rng.randi()
		_insert_after_league_round(fx, int(after[k]))
	draws.append({ "comp": continental["name"], "stage": "Group stage", "opponent": ", ".join(names), "home": true, "neutral": false, "division": 9 })


func _draw_continental_knockout(stage_i: int) -> void:
	var sch := config.continental_schedule
	var rounds: Array = sch["knockout_rounds"]
	if stage_i >= rounds.size():
		return
	var rng := _comp_rng("cont-ko%d" % stage_i)
	var fx := Fixture.make("%s %s" % [["Bayern", "Paris", "Benfica", "Juventus", "Atletico", "Feyenoord", "Celtic", "Galatasaray"][rng.randi_range(0, 7)],
		["FC", "SC", "United", "City", "Club"][rng.randi_range(0, 4)]])
	fx.competition = "continental"
	fx.comp_name = continental["name"]
	fx.stage = rounds[stage_i]
	fx.round = 6 + stage_i
	fx.opponent_team = -1
	fx.opponent_rating = League.rating_for_wage(float(continental["strength_wage"]) * rng.randf_range(0.9, 1.7))
	var final := stage_i == rounds.size() - 1
	fx.neutral = final
	fx.home = (not final) and rng.randf() < 0.5
	fx.knockout = true
	fx.evening = true
	fx.big = true
	fx.prize_win = float(continental["knockout_prize"]) * (1.0 + stage_i)
	fx.tv = float(continental["tv"]) * (1.0 + stage_i * 0.5)
	fx.seed = rng.randi()
	_insert_after_league_round(fx, int(sch["knockout_after"][stage_i]))
	draws.append({ "comp": fx.comp_name, "stage": fx.stage, "opponent": fx.opponent, "home": fx.home, "neutral": fx.neutral, "division": 9 })


## After a cup or continental match: through to the next round, or out.
func _after_competition(fx: Fixture, r: MatchdayReport) -> void:
	var won := r.result == "W" or (r.result == "D" and r.penalties == "won")
	if fx.competition == "cup":
		if won:
			_draw_cup(fx.round + 1)
		return
	if fx.knockout:
		if won:
			_draw_continental_knockout(fx.round - 6 + 1)
		return
	if fx.stage == "Group game 6":
		# through if we took at least 9 points from the six group games
		var pts := 0
		for rep in reports + [r]:
			if rep.competition == "continental" and not rep.knockout:
				pts += 3 if rep.result == "W" else (1 if rep.result == "D" else 0)
		r.group_points = pts
		if pts >= 9:
			_draw_continental_knockout(0)


## The club's league matches only (cup and continental nights left out).
func league_fixtures() -> Array[Fixture]:
	var out: Array[Fixture] = []
	for f in fixtures:
		if f.is_league():
			out.append(f)
	return out


func is_over() -> bool:
	return reports.size() >= fixtures.size()


func next_match_number() -> int:
	return reports.size() + 1


func next_fixture() -> Fixture:
	return null if is_over() else fixtures[reports.size()]


func play_next() -> MatchdayReport:
	assert(not is_over(), "Season is over")
	var i := reports.size()
	var fx := fixtures[i]
	var report := MatchdaySim.run(config, layout, club, fx, match_seeds[fx.round] if fx.is_league() else fx.seed, pitch_damage)
	if fx.home:
		pitch_damage = 0.0   # the groundstaff have had a match to put it right
	if fx.knockout and report.result == "D":
		# level after extra time: penalties, a little in favour of the better side
		var pr := RandomNumberGenerator.new()
		pr.seed = fx.seed + 17
		var ours := League.club_rating(config, club)
		report.penalties = "won" if pr.randf() < clampf(0.5 + (ours - fx.opponent_rating) * 0.1, 0.25, 0.75) else "lost"
	club.apply_report(report)
	if fx.is_league():
		league.play_round(config, fx.round, report.home_goals, report.away_goals, round_seeds[fx.round])
	else:
		_after_competition(fx, report)
	report.milestones = check_milestones()
	reports.append(report)
	return report


## Milestones reached by the fanbase so far that haven't been celebrated yet.
## Pays their reward and returns them (for the matchday banner).
func check_milestones() -> Array:
	var new := []
	for m in config.milestones:
		var fans := float(m["fans"])
		if club.peak_fanbase >= fans and not club.milestones.has(fans):
			club.milestones.append(fans)
			club.cash += float(m["reward"])
			milestone_rewards += float(m["reward"])
			new.append(m)
	return new


## Locked things open up as the fanbase grows (see data/milestones.json).
func is_unlocked(id: String) -> bool:
	return club.peak_fanbase >= config.unlock_fans(id)


func _locked_error(id: String, what: String) -> String:
	return "" if is_unlocked(id) else "%s unlocks at %s fans" % [what, money(config.unlock_fans(id)).substr(1)]


func play_all() -> SeasonReport:
	while not is_over():
		play_next()
	return summary()


## Archives the finished season and sets up the next one.
## True if this season's points are enough to go up a division.
func promotion_earned() -> bool:
	return is_over() and league.position() <= promoted_places()


## True once the season is over if the club finished in the drop zone.
func relegated() -> bool:
	return is_over() and league.position() > league.teams.size() - relegated_places()


## How many go down from this division (0 in the bottom one).
func relegated_places() -> int:
	return int(config.division(club.division).get("relegated", 0))


## How many go up from this division (0 in the top flight).
func promoted_places() -> int:
	return int(config.division(club.division).get("promoted", 0))


## League position now (1 = top).
func position() -> int:
	return league.position()


## What the board wants this season: a league target set by how last season
## went, and (after the first season) a bigger average crowd. Each one met pays
## board/reward_wages times the division's squad wage. Derived from history, so
## nothing extra is saved and it can't change mid-season.
func board_objectives() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var reward := config.num("board/reward_wages") * float(config.division(club.division)["squad_wage"])
	var teams := league.teams.size() if league else 20
	var last: SeasonReport = history[-1] if not history.is_empty() else null
	var target := teams / 2
	var text := "Finish in the top half"
	if last != null and last.promoted and relegated_places() > 0:
		target = teams - relegated_places()
		text = "Stay up: finish above the drop zone"
	elif last != null and (last.relegated or last.position <= teams / 2):
		target = maxi(promoted_places(), config.integer("board/push_places"))
		text = "Push for the top: finish in the top %d" % target
	out.append({ "kind": "position", "target": target, "reward": reward, "text": text })
	if last != null and last.home_avg() > 0.0:
		var crowd := roundi(last.home_avg() * config.num("board/crowd_growth") / 100.0) * 100
		out.append({ "kind": "crowd", "target": crowd, "reward": reward, "text": "Average home crowd of %d or more" % crowd })
	return out


## True if an objective is met by the season as it stands.
func objective_met(o: Dictionary) -> bool:
	match String(o["kind"]):
		"position":
			return league != null and league.position() <= int(o["target"])
		"crowd":
			return summary().home_avg() >= float(o["target"])
	return false


func start_next_season() -> void:
	assert(is_over(), "Season still running")
	var sr := summary()
	sr.promoted = promotion_earned()
	sr.relegated = relegated()
	# the board pays out for every objective met
	for o in board_objectives():
		if objective_met(o):
			sr.board_bonus += float(o["reward"])
			sr.board_met.append(o["text"])
	club.cash += sr.board_bonus
	# a top-division finish high enough earns continental football next season
	continental = {}
	if club.division == config.divisions.size() - 1 and not sr.relegated:
		var pos := position()
		for c in config.continental:
			if pos >= int(c["from"]) and pos <= int(c["to"]):
				continental = (c as Dictionary).duplicate()
	history.append(sr)
	if sr.promoted:
		club.division += 1
	elif sr.relegated:
		club.division -= 1
	season_number += 1
	reports.clear()
	for st in layout.stands:
		st.wear += 1
	build_spend = 0.0
	demolish_refunds = 0.0
	land_spend = 0.0
	milestone_rewards = 0.0
	event_income = 0.0
	events_held = 0
	_mark_start()
	_make_fixtures()
	_check_administration()


## Too deep in debt at the start of a season: administration. Points come off
## and the wage bill is capped until the club is back in the black.
func _check_administration() -> void:
	var norm := float(config.division(club.division)["squad_wage"])
	if club.cash < -config.num("economy/administration_debt_wages") * norm:
		club.administration = true
		league.deductions[0] = config.integer("economy/administration_points")
	elif club.cash >= 0.0:
		club.administration = false
	if club.administration:
		club.squad_budget = minf(club.wage(config), wage_cap())


## Highest squad budget allowed (only limited in administration).
func wage_cap() -> float:
	if not club.administration:
		return INF
	return float(config.division(club.division)["squad_wage"]) * config.num("economy/administration_wage_cap")


# --- Player commands between matches -------------------------------------
# Each returns an error string ("" on success) and leaves state unchanged on error.
# Growing something costs the build-cost difference; shrinking or demolishing
# refunds season/demolish_refund_fraction of it.

## Put the pitch down (or move it, while nothing is built round it). `pos` is
## its top-left tile; it must sit on the plot with a little room all round.
func place_pitch(pos: Vector2i) -> String:
	var plan := pitch_move_plan(pos)
	if plan["error"] != "":
		return plan["error"]
	var cost := 0.0 if layout.pitch_placed else config.num("plot/pitch_cost")
	if cost > club.cash:
		return "the pitch costs %s, you have %s" % [money(cost), money(club.cash)]
	var delta: Vector2i = pos - layout.pitch.position
	var old_pos := layout.pitch.position
	var old_stands := layout.stands.duplicate()
	var old_facs: Array = []
	for f in layout.facilities:
		old_facs.append([f, f.pos])
	var old_list := layout.facilities.duplicate()
	var gone: Array = plan["stands"]
	var err := _modify(
		func():
			layout.pitch.position = pos
			layout.pitch_placed = true
			for f in layout.facilities:
				if config.facility_type(f.type_id).layer in ["bowl", "concourse"]:
					f.pos += delta
			var kept: Array[Stand] = []
			for i in layout.stands.size():
				if not i in gone:
					kept.append(layout.stands[i])
			layout.stands = kept
			_drop_orphan_facilities(),
		func():
			layout.pitch.position = old_pos
			layout.stands.assign(old_stands)
			for e in old_facs:
				(e[0] as Facility).pos = e[1]
			layout.facilities.assign(old_list))
	if err != "":
		return err
	club.cash -= cost
	build_spend += cost
	return ""


## What moving the pitch to pos would do: { error, stands: indices that would
## have to go }. Stands, their gear and concourse items move with the pitch;
## a stand that would leave the plot or run into an outside building goes.
func pitch_move_plan(pos: Vector2i) -> Dictionary:
	var r := Rect2i(pos, layout.pitch.size)
	var m := config.integer("plot/pitch_margin")
	var out := { "error": "", "stands": [] }
	if not layout.plot.grow(-m).encloses(r):
		out["error"] = "the pitch needs %d tiles of room on every side" % m
		return out
	var outside := {}
	for f in layout.facilities:
		var ft := config.facility_type(f.type_id)
		if ft.layer == "outside":
			for t in f.tiles(ft):
				outside[t] = true
				if r.grow(1).has_point(t):
					out["error"] = "something is built there"
					return out
	var moved := Layout.new()
	moved.plot = layout.plot
	moved.land = layout.land
	moved.pitch = r
	var gone: Array = []
	for i in layout.stands.size():
		var s := layout.stands[i]
		var bad := false
		for t in s.tiles(r) + moved.stand_concourse(s, config):
			if not layout.plot.has_point(t) or outside.has(t):
				bad = true
				break
		if bad:
			gone.append(i)
	out["stands"] = gone
	return out


## Squad spend per match (wages). More spend = a stronger team next match on.
func set_squad_budget(amount: float) -> String:
	if amount < config.num("league/min_squad_budget"):
		return "the squad needs at least %s a match" % money(config.num("league/min_squad_budget"))
	if amount > wage_cap():
		return "in administration: wages are capped at %s a match until the debts are cleared" % money(wage_cap())
	club.squad_budget = amount
	return ""


## Share of the gate sold as season tickets (0..max_share): cheaper per head,
## but the holders always come, so crowds are bigger and steadier.
func set_season_tickets(share: float) -> String:
	if share < 0.0 or share > config.num("season_tickets/max_share") + 0.0001:
		return "season tickets: 0 to %d%% of the gate" % roundi(config.num("season_tickets/max_share") * 100.0)
	club.season_tickets = share
	return ""


## Sets a stand aside for visiting fans (or gives it back to the home crowd).
func set_away_end(index: int, on: bool) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no such stand"
	layout.stands[index].away = on
	return ""


## What a concert at the ground would earn now (0 if the ground's too small).
func concert_income() -> float:
	var cap := layout.capacity_total(config)
	if cap < config.integer("events/concert_min_capacity"):
		return 0.0
	return roundf(cap * config.num("events/concert_fill") * config.num("events/concert_per_place"))


## Hosts a concert between matches: money in, but the stage and crowd cut up
## the pitch for the next home game (frost covers protect most of it).
func host_concert() -> String:
	if is_over():
		return "the season is over"
	if events_held >= config.integer("events/max_per_season"):
		return "only %d events a season: the pitch needs time to recover" % config.integer("events/max_per_season")
	var income := concert_income()
	if income <= 0.0:
		return "promoters want at least %d places" % config.integer("events/concert_min_capacity")
	club.cash += income
	event_income += income
	events_held += 1
	var protect := config.num("events/covers_protect") if layout.pitch_care == "covers" else 0.0
	pitch_damage = maxf(pitch_damage, config.num("events/pitch_damage") * (1.0 - protect))
	return ""


## What refurbishing a stand costs: a share of building it new.
func refurbish_cost(index: int) -> float:
	if index < 0 or index >= layout.stands.size():
		return 0.0
	return roundf(layout.stand_cost(layout.stands[index], config) * config.num("wear/refurbish_share"))


## Refurbishes a stand: as new again (upkeep back down, the weathering gone).
func refurbish_stand(index: int) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no such stand"
	var s := layout.stands[index]
	if s.wear <= 0:
		return "this stand is as good as new"
	var cost := refurbish_cost(index)
	if cost > club.cash:
		return "refurbishing costs %s" % money(cost)
	club.cash -= cost
	build_spend += cost
	s.wear = 0
	s.extras.erase("age")
	return ""


## Groundstaff kit: pitch care between matches and undersoil heating.
func set_pitch_care(care: String, heating: bool) -> String:
	if not (config.value("pitch/care") as Dictionary).has(care):
		return "unknown pitch care '%s'" % care
	layout.pitch_care = care
	layout.heating = heating
	return ""


## Matchday staff: how many stewards on the gates and staff behind the
## counters, as a level (1.0 = standard). More costs more and moves faster.
func set_staff_level(kind: String, level: float) -> String:
	if not kind in ["stewards", "catering"]:
		return "staff are stewards or catering"
	var lo := config.num("staff/min_level")
	var hi := config.num("staff/max_level")
	if level < lo - 0.0001 or level > hi + 0.0001:
		return "staff level: %d%% to %d%%" % [roundi(lo * 100.0), roundi(hi * 100.0)]
	club.staff[kind] = level
	return ""


## Kiosk prices: a level for food, drink or merch stalls (1.0 = standard).
## Dearer sells to fewer fans for more each, and the crowd grumbles.
func set_price_level(kind: String, level: float) -> String:
	if not kind in ["food", "drink", "merch"]:
		return "prices are set for food, drink or merch"
	var lo := config.num("concessions/min_price")
	var hi := config.num("concessions/max_price")
	if level < lo - 0.0001 or level > hi + 0.0001:
		return "price level: %d%% to %d%%" % [roundi(lo * 100.0), roundi(hi * 100.0)]
	club.prices[kind] = level
	return ""


func set_ticket_price(type_id: String, price: float) -> String:
	if not config.stand_types.has(type_id):
		return "unknown stand type '%s'" % type_id
	if price < 0.0:
		return "price must be >= 0"
	club.ticket_prices[type_id] = price
	return ""


func build_stand(stand: Stand) -> String:
	if not layout.pitch_placed:
		return "place the pitch first"
	return _modify(func(): layout.stands.append(stand), func(): layout.stands.erase(stand))


## Paint roads, paths or landscaping onto tiles (kind "" clears them). Tiles
## that can't take it (off the plot, under a stand, the pitch or a building)
## are skipped; fails only if none can.
func paint_site(tiles: Array, kind: String) -> String:
	if kind != "" and not config.site_items.has(kind):
		return "unknown item '%s'" % kind
	var solid := layout.solid_tiles(config)
	var todo: Array[Vector2i] = []
	for t in tiles:
		var p: Vector2i = t
		if not layout.in_plot(p) or solid.has(p):
			continue
		if kind == "" and not layout.site.has(p):
			continue
		if kind != "" and layout.site.get(p, "") == kind:
			continue
		todo.append(p)
	if todo.is_empty():
		return "nothing to change there" if kind == "" else "no room there: pick open ground"
	var old := layout.site.duplicate()
	return _modify(func():
			for p in todo:
				if kind == "":
					layout.site.erase(p)
				else:
					layout.site[p] = kind,
		func(): layout.site = old)


func build_facility(facility: Facility) -> String:
	if config.facility_types.has(facility.type_id):
		var locked := _locked_error(facility.type_id, config.facility_type(facility.type_id).display_name)
		if locked != "":
			return locked
	return _modify(func(): layout.facilities.append(facility), func(): layout.facilities.erase(facility))


## Change a stand's footprint (e.g. add a row, extend along the side).
func resize_stand(index: int, offset: int, length: int, depth: int) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	var s := layout.stands[index]
	var old := [s.offset, s.length, s.depth]
	var old_facilities := layout.facilities.duplicate()
	return _modify(
		func():
			s.offset = 0 if s.is_corner() else offset
			s.length = depth if s.is_corner() else length
			s.depth = depth
			_drop_orphan_facilities(),
		func():
			s.offset = old[0]
			s.length = old[1]
			s.depth = old[2]
			layout.facilities.assign(old_facilities))


## Cost of a resize without doing it (negative = refund).
func resize_cost(index: int, offset: int, length: int, depth: int) -> float:
	var s := layout.stands[index]
	var t := config.stand_type(s.type_id)
	var resized := Stand.from_dict(s.to_dict())   # keeps roof, rake, front height...
	resized.offset = 0 if s.is_corner() else offset
	resized.length = depth if s.is_corner() else length
	resized.depth = depth
	var cost := Layout.stand_cost(resized, config) - Layout.stand_cost(s, config)
	return cost if cost >= 0.0 else cost * config.num("season/demolish_refund_fraction")


## Cosmetic: roof style and seat colour. Free.
func restyle_stand(index: int, roof: String, seat_color: String) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	if not roof in Stand.ROOF_STYLES:
		return "unknown roof style '%s'" % roof
	var s := layout.stands[index]
	var old_roof := s.roof
	var old_seat := s.seat_color
	# changing between roof styles is free; putting a roof on costs, taking it off refunds part
	return _modify(func():
			s.roof = roof
			s.seat_color = seat_color,
		func():
			s.roof = old_roof
			s.seat_color = old_seat)


## Copy one stand's look onto another: roof (paid like a restyle), seat colour,
## facade, materials and colours, roof shape, seat detail and the name board's
## styling (not its words). Signs stay where they are.
func copy_stand_look(from_index: int, to_index: int) -> String:
	if from_index < 0 or from_index >= layout.stands.size() or to_index < 0 or to_index >= layout.stands.size():
		return "no such stand"
	if from_index == to_index:
		return "that's the same stand"
	var src := layout.stands[from_index]
	var dst := layout.stands[to_index]
	var e := restyle_stand(to_index, src.roof, src.seat_color)
	if e != "":
		return e
	dst.facade = src.facade
	for key in ["paint", "roof_shape", "detail", "logo"]:
		if src.extras.has(key):
			dst.extras[key] = (src.extras[key] as Dictionary).duplicate(true)
		else:
			dst.extras.erase(key)
	if src.extras.has("name"):
		var nm: Dictionary = (src.extras["name"] as Dictionary).duplicate(true)
		var own: Dictionary = dst.extras.get("name", {})
		for k in ["text", "line2", "on"]:
			if own.has(k):
				nm[k] = own[k]
			else:
				nm.erase(k)
		dst.extras["name"] = nm
	return ""


## Wall signs: add, change or remove a sign on a stand (cosmetic, free).
func _sign_error(settings: Dictionary) -> String:
	for k in settings:
		if not Stand.SIGN_DEFAULTS.has(k):
			return "signs have no setting '%s'" % k
	if settings.has("kind") and not settings["kind"] in Stand.SIGN_KINDS:
		return "unknown sign kind"
	if settings.has("surface") and not settings["surface"] in Stand.SIGN_SURFACES:
		return "unknown wall"
	if settings.has("mount") and not settings["mount"] in Stand.SIGN_MOUNTS:
		return "unknown sign mounting"
	if settings.has("font") and not settings["font"] in Stand.SIGN_FONTS:
		return "unknown font"
	if settings.has("light") and not settings["light"] in Stand.SIGN_LIGHTS:
		return "unknown sign lighting"
	if settings.has("pattern") and not settings["pattern"] in Stand.BANNER_PATTERNS:
		return "unknown banner pattern"
	for k in ["u", "v"]:
		if settings.has(k) and (float(settings[k]) < 0.0 or float(settings[k]) > 1.0):
			return "position out of range"
	if settings.has("scale") and (float(settings["scale"]) < 0.2 or float(settings["scale"]) > 5.0):
		return "size out of range"
	if settings.has("count") and (int(settings["count"]) < 1 or int(settings["count"]) > 12):
		return "count out of range"
	for k in ["color", "panel", "light_color"]:
		if settings.has(k) and settings[k] != "" and not Color.html_is_valid(settings[k]):
			return "bad colour"
	if settings.has("text") and String(settings["text"]).length() > 40:
		return "text too long"
	return ""


func add_stand_sign(index: int, settings: Dictionary) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	var err := _sign_error(settings)
	if err != "":
		return err
	var s := layout.stands[index]
	var list: Array = s.extras.get("signs", []).duplicate(true)
	if list.size() >= 24:
		return "that stand has enough signs"
	list.append(settings.duplicate())
	s.extras["signs"] = list
	return ""


func set_stand_sign(index: int, k: int, settings: Dictionary) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	var s := layout.stands[index]
	var list: Array = s.extras.get("signs", [])
	if k < 0 or k >= list.size():
		return "no sign %d" % k
	var err := _sign_error(settings)
	if err != "":
		return err
	(list[k] as Dictionary).merge(settings, true)
	return ""


func remove_stand_sign(index: int, k: int) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	var list: Array = layout.stands[index].extras.get("signs", [])
	if k < 0 or k >= list.size():
		return "no sign %d" % k
	list.remove_at(k)
	return ""


## How far each upper tier hangs out over the one below (rows). More overhang
## means a smaller footprint and closer upper seats; the lower tier's back rows
## sit in its shadow.
func set_overhang(index: int, rows: int) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	var s := layout.stands[index]
	if rows < 0 or rows > maxi(0, s.depth / 2 - 1):
		return "overhang must be 0..%d rows" % maxi(0, s.depth / 2 - 1)
	var old := s.overhang
	var old_facilities := layout.facilities.duplicate()
	return _modify(
		func():
			s.overhang = rows
			_drop_orphan_facilities(),
		func():
			s.overhang = old
			layout.facilities.assign(old_facilities))


## How far back from the pitch a stand stands (rows of open ground in front).
## Set back, corners sweep round in wide curves; right up close, it's a cauldron.
func set_setback(index: int, rows: int) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	var mx := config.integer("layout/max_setback")
	if rows < 0 or rows > mx:
		return "distance from the pitch: 0..%d rows" % mx
	var s := layout.stands[index]
	var old := s.setback
	var old_facilities := layout.facilities.duplicate()
	return _modify(
		func():
			s.setback = rows
			_drop_orphan_facilities(),
		func():
			s.setback = old
			layout.facilities.assign(old_facilities))


## Turnstile entrances on a stand (each one costs money; more gets fans in faster).
func set_gates(index: int, gates: int) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	if gates < 1 or gates > 30:
		return "gates must be 1..30"
	var s := layout.stands[index]
	var old := s.gates
	return _modify(func(): s.gates = gates, func(): s.gates = old)


## The seating's shape: rake (degrees), front height and extra concourse
## behind. Costs or refunds the difference.
func set_stand_shape(index: int, rake: float, plinth: float, concourse_extra: int) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	var s := layout.stands[index]
	if s.type_id == "bank" and (rake > 30.0):
		return "a grass bank can't be that steep"
	var old := [s.rake, s.plinth, s.concourse_extra]
	var old_facilities := layout.facilities.duplicate()
	return _modify(
		func():
			s.rake = rake
			s.plinth = plinth
			s.concourse_extra = concourse_extra
			_drop_orphan_facilities(),
		func():
			s.rake = old[0]
			s.plinth = old[1]
			s.concourse_extra = old[2]
			layout.facilities.assign(old_facilities))


## Add or remove upper tiers. Costs (or refunds) the difference; concourse
## items on a removed level go with it.
func set_tiers(index: int, tiers: int) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	var s := layout.stands[index]
	if tiers > s.tiers:
		var locked := _locked_error("tier%d" % tiers, "A %s tier" % ["", "", "second", "third"][mini(tiers, 3)])
		if locked != "":
			return locked
	var old := s.tiers
	var old_facilities := layout.facilities.duplicate()
	return _modify(func():
			s.tiers = tiers
			_drop_orphan_facilities(),
		func():
			s.tiers = old
			layout.facilities.assign(old_facilities))


func tier_cost(index: int, tiers: int) -> float:
	var s := layout.stands[index]
	var t := Stand.from_dict(s.to_dict())
	t.tiers = tiers
	var cost := Layout.stand_cost(t, config) - Layout.stand_cost(s, config)
	return cost if cost >= 0.0 else cost * config.num("season/demolish_refund_fraction")


## Sign (or end) a naming-rights deal. "" ends it.
func set_sponsor(id: String) -> String:
	if id != "" and not config.sponsors.has(id):
		return "unknown sponsor '%s'" % id
	if id != "":
		var locked := _locked_error("naming_rights", "Naming rights")
		if locked != "":
			return locked
	club.sponsor = id
	return ""


## Sign (or end) a shirt sponsor: a fee every match, home or away.
func set_kit_sponsor(id: String) -> String:
	if id != "" and not config.sponsors.has(id):
		return "unknown sponsor '%s'" % id
	club.kit_sponsor = id
	return ""


## Sell (or end) the naming rights to one stand. "" ends it. Pays a share of
## the sponsor's fee for that stand's places every home match; fans grumble a little.
func set_stand_sponsor(index: int, id: String) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	if id != "" and not config.sponsors.has(id):
		return "unknown sponsor '%s'" % id
	if id != "":
		var locked := _locked_error("naming_rights", "Naming rights")
		if locked != "":
			return locked
	layout.stands[index].sponsor = id
	return ""


## Price one stand above or below its type's price (adj -0.5..+0.5 = half
## price..50% dearer). Dearer stands sell fewer tickets, cheaper ones more.
func set_stand_price(index: int, adj: float) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	var r := config.num("economy/stand_price_range")
	if adj < -r - 0.0001 or adj > r + 0.0001:
		return "between %d%% and +%d%%" % [roundi(-r * 100.0), roundi(r * 100.0)]
	layout.stands[index].price_adj = adj
	return ""


## The most the bank will lend in all: grows with the fanbase.
func loan_limit() -> float:
	return maxf(config.num("economy/loan_min_limit"), club.fanbase * config.num("economy/loan_per_fan"))


## Borrow from the bank: the cash now, paid back in equal slices over
## loan_matches matches, with (cheap) interest on what's still owed.
func take_loan(amount: float) -> String:
	if amount <= 0.0:
		return "borrow something"
	if club.administration:
		return "no bank will lend to a club in administration"
	if club.loan + amount > loan_limit():
		return "the bank will lend %s at most" % money(loan_limit() - club.loan)
	club.loan += amount
	club.cash += amount
	club.loan_payment = club.loan / config.num("economy/loan_matches")
	return ""


## Pay some of the loan back early.
func repay_loan(amount: float) -> String:
	amount = minf(amount, club.loan)
	if amount <= 0.0:
		return "nothing owed"
	if amount > club.cash:
		return "not enough cash"
	club.cash -= amount
	club.loan -= amount
	club.loan_payment = minf(club.loan_payment, club.loan) if club.loan > 0.01 else 0.0
	if club.loan <= 0.01:
		club.loan = 0.0
	return ""


## Per-match fee for one stand's naming rights.
func stand_sponsor_fee(index: int, id: String) -> float:
	var s := layout.stands[index]
	return config.num("economy/stand_naming_share") * MatchdaySim.naming_fee(config, id, s.capacity(config.stand_type(s.type_id)))


## Naming-rights fee per match for a sponsor at the current capacity.
func sponsor_fee(id: String) -> float:
	return MatchdaySim.naming_fee(config, id, layout.capacity_total(config))


## Cosmetic: stand cladding. Free.
func set_facade(index: int, facade: String) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	if not facade in Stand.FACADES:
		return "unknown facade '%s'" % facade
	layout.stands[index].facade = facade
	return ""


## Cosmetic: daylight preset. Free.
func set_sky(kind: String) -> String:
	if not kind in Layout.SKIES:
		return "unknown sky '%s'" % kind
	layout.sky = kind
	return ""


## Cosmetic: what's around the ground. Free.
func set_surroundings(kind: String) -> String:
	if not kind in Layout.SURROUNDINGS:
		return "unknown surroundings '%s'" % kind
	layout.surroundings = kind
	return ""


## Cosmetic: mowing pattern. Free.
func set_pitch_pattern(p: String) -> String:
	if not p in Layout.PITCH_PATTERNS:
		return "unknown pitch pattern '%s'" % p
	layout.pitch_pattern = p
	return ""


## Cosmetic: floodlight style. Free.
## Cosmetic add-on on one stand: switch it on/off or change a setting.
## `settings` holds only the keys to change (e.g. { "on": true, "size": "L" }).
func set_stand_extra(index: int, key: String, settings: Dictionary) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	if not Stand.EXTRAS.has(key):
		return "unknown extra '%s'" % key
	var defaults: Dictionary = Stand.EXTRAS[key]
	for k in settings:
		if not defaults.has(k):
			return "%s has no setting '%s'" % [key, k]
		if typeof(settings[k]) != typeof(defaults[k]):
			return "%s.%s has the wrong type" % [key, k]
	if settings.has("where") and key == "name" and not settings["where"] in Stand.NAME_WHERE:
		return "unknown name position"
	if settings.has("size") and not settings["size"] in Stand.NAME_SIZES:
		return "unknown name size"
	if settings.has("where") and key == "logo" and not settings["where"] in Stand.LOGO_WHERE:
		return "unknown logo position"
	if key == "uplight" and settings.has("spacing") and (float(settings["spacing"]) < 2.0 or float(settings["spacing"]) > 12.0):
		return "uplight spacing out of range"
	if settings.has("color") and String(settings["color"]) != "" and not Color.html_is_valid(String(settings["color"])):
		return "bad colour"
	if key == "tier_front" and settings.has("style") and not settings["style"] in ["paint", "led", "glass"]:
		return "tier front: paint, led or glass"
	if key == "windows" and settings.has("style") and not settings["style"] in ["default", "strip", "grid", "tall"]:
		return "windows: default, strip, grid or tall"
	if key == "windows" and settings.has("frame") and String(settings["frame"]) != "" and not Color.html_is_valid(String(settings["frame"])):
		return "bad colour"
	if key == "age" and settings.has("years") and (float(settings["years"]) < 0.0 or float(settings["years"]) > 1.0):
		return "age out of range"
	if key == "entrances" and settings.has("style") and not settings["style"] in ["auto", "gatehouse", "doors"]:
		return "entrances: auto, gatehouse or doors"
	if key == "split":
		if settings.has("height") and (float(settings["height"]) < 0.0 or float(settings["height"]) > 0.9):
			return "split height out of range"
		if settings.has("mat") and not settings["mat"] in Stand.FINISHES:
			return "unknown finish"
	if key == "display":
		if settings.has("giant") and not settings["giant"] in ["auto", "on", "off"]:
			return "giant flag: auto, on or off"
		if settings.has("flag") and not settings["flag"] in ["stripes", "halves", "hoops", "crest", "plain"]:
			return "unknown flag pattern"
		if settings.has("spread") and (float(settings["spread"]) < 0.2 or float(settings["spread"]) > 1.0):
			return "flag size out of range"
	if settings.has("pattern") and not settings["pattern"] in Stand.SEAT_PATTERNS:
		return "unknown seat pattern"
	if settings.has("color2") and settings["color2"] != "" and not Color.html_is_valid(settings["color2"]):
		return "bad colour"
	if settings.has("text") and String(settings["text"]).length() > 32:
		return "name too long"
	if settings.has("line2") and String(settings["line2"]).length() > 40:
		return "second line too long"
	if key == "detail":
		if settings.has("seat_style") and not settings["seat_style"] in Stand.SEAT_STYLES:
			return "unknown seat style"
		if settings.has("back") and not settings["back"] in Stand.SEAT_BACKS:
			return "unknown seat back"
		if settings.has("aisles") and (int(settings["aisles"]) < -1 or int(settings["aisles"]) > 8):
			return "aisles out of range"
		if settings.has("voms") and (int(settings["voms"]) < -1 or int(settings["voms"]) > 8):
			return "tunnels out of range"
		if settings.has("front_style") and not settings["front_style"] in ["wall", "glass", "rail"]:
			return "front: wall, glass or rail"
		if settings.has("box_every") and (int(settings["box_every"]) < 1 or int(settings["box_every"]) > 6):
			return "box spacing out of range"
		for ck in ["rail", "nosing", "barrier", "steps", "box_glass"]:
			if settings.has(ck) and settings[ck] != "" and not Color.html_is_valid(settings[ck]):
				return "bad colour"
	if key == "roof_shape":
		if settings.has("columns") and not settings["columns"] in Stand.COLUMN_STYLES:
			return "unknown column style"
		if settings.has("edge") and not settings["edge"] in Stand.ROOF_EDGES:
			return "unknown roof edge"
		if settings.has("ends") and not settings["ends"] in Stand.ROOF_ENDS:
			return "unknown roof ends"
		if settings.has("back") and not settings["back"] in ["open", "closed", "glazed", "tyre"]:
			return "roof back: open, closed or glazed"
		if settings.has("clear_strip") and (float(settings["clear_strip"]) < 0.0 or float(settings["clear_strip"]) > 0.6):
			return "clear strip out of range"
		if settings.has("top_truss") and not settings["top_truss"] in Stand.TOP_TRUSSES:
			return "unknown roof truss"
		if settings.has("truss_h") and (float(settings["truss_h"]) < 0.3 or float(settings["truss_h"]) > 3.0):
			return "truss height out of range"
		if settings.has("pylons") and not settings["pylons"] in Stand.PYLON_STYLES:
			return "unknown pylon style"
		if settings.has("pylon_count") and (int(settings["pylon_count"]) < 1 or int(settings["pylon_count"]) > 8):
			return "pylon count out of range"
		if settings.has("pylon_h") and (float(settings["pylon_h"]) < 0.5 or float(settings["pylon_h"]) > 3.0):
			return "pylon height out of range"
		if settings.has("reach") and (float(settings["reach"]) < 0.4 or float(settings["reach"]) > 1.5):
			return "roof reach out of range"
		if settings.has("tilt") and absf(float(settings["tilt"])) > 1.5:
			return "roof tilt out of range"
		if settings.has("fascia_h") and (float(settings["fascia_h"]) < 0.0 or float(settings["fascia_h"]) > 2.0):
			return "fascia height out of range"
	if key == "paint":
		for ck in settings:
			if String(ck).ends_with("_mat"):
				if settings[ck] != "" and not settings[ck] in Stand.FINISHES:
					return "unknown finish"
			elif settings[ck] != "" and not Color.html_is_valid(settings[ck]):
				return "bad colour"
	if key == "logo":
		if settings.has("mount") and not settings["mount"] in Stand.CREST_MOUNTS:
			return "unknown crest style"
		if settings.has("light") and not settings["light"] in Stand.SIGN_LIGHTS:
			return "unknown crest lighting"
		if settings.has("scale") and (float(settings["scale"]) < 0.0 or float(settings["scale"]) > 3.0):
			return "crest size out of range"
	if key == "name":
		if settings.has("mount") and not settings["mount"] in Stand.SIGN_MOUNTS:
			return "unknown sign mounting"
		if settings.has("font") and not settings["font"] in Stand.SIGN_FONTS:
			return "unknown font"
		if settings.has("light") and not settings["light"] in Stand.SIGN_LIGHTS:
			return "unknown sign lighting"
		if settings.has("align") and not settings["align"] in Stand.SIGN_ALIGNS:
			return "unknown alignment"
		if settings.has("scale") and (float(settings["scale"]) < 0.3 or float(settings["scale"]) > 3.0):
			return "sign size out of range"
		if settings.has("depth") and (float(settings["depth"]) < 0.0 or float(settings["depth"]) > 0.6):
			return "letter depth out of range"
		for ck in ["panel", "light_color"]:
			if settings.has(ck) and settings[ck] != "" and not Color.html_is_valid(settings[ck]):
				return "bad colour"
	var s := layout.stands[index]
	var cur: Dictionary = s.extras.get(key, {})
	cur.merge(settings, true)
	s.extras[key] = cur
	return ""


## Pick a placed piece up and put it down somewhere else (free; it must fit there).
func move_facility(index: int, pos: Vector2i) -> String:
	if index < 0 or index >= layout.facilities.size():
		return "no facility %d" % index
	var f := layout.facilities[index]
	var old := f.pos
	return _modify(func(): f.pos = pos, func(): f.pos = old)


## Turn a placed piece a quarter turn (its footprint turns with it, so it
## must still fit where it is).
func rotate_facility(index: int) -> String:
	if index < 0 or index >= layout.facilities.size():
		return "no facility %d" % index
	var f := layout.facilities[index]
	var old := f.rot
	return _modify(func(): f.rot = (old + 1) % 4, func(): f.rot = old)


## Cosmetic option on a placed facility (e.g. a video board's size or frame colour).
func set_facility_option(index: int, key: String, value: String) -> String:
	if index < 0 or index >= layout.facilities.size():
		return "no facility %d" % index
	var f := layout.facilities[index]
	var t := config.facility_type(f.type_id)
	if not t.options.has(key):
		return "%s has no option '%s'" % [t.display_name, key]
	var allowed: Array = t.options[key]
	if allowed == [""]:
		# a free-text option (a memorial's dedication, the name over a gate)
		if value.length() > 40:
			return "too long (40 letters at most)"
	elif not value in allowed:
		return "unknown %s '%s'" % [key, value]
	f.opts[key] = value
	return ""


## Pitchside looks: "ad_boards", "dugout" or "surround".
func set_pitchside(key: String, value: String) -> String:
	var allowed := { "ad_boards": Layout.AD_BOARDS, "dugout": Layout.DUGOUTS, "surround": Layout.SURROUNDS, "barrier": Layout.BARRIERS }
	if not allowed.has(key):
		return "unknown pitchside setting '%s'" % key
	if not value in allowed[key]:
		return "unknown %s '%s'" % [key, value]
	layout.set(key, value)
	return ""


## Corner flags: on, pole and flag colours (html, "" = club colours), pattern.
func set_corner_flags(settings: Dictionary) -> String:
	for k in settings:
		if not Layout.CORNER_FLAG_DEFAULTS.has(k):
			return "corner flags have no setting '%s'" % k
		if typeof(settings[k]) != typeof(Layout.CORNER_FLAG_DEFAULTS[k]):
			return "corner flags.%s has the wrong type" % k
	if settings.has("pattern") and not settings["pattern"] in Layout.FLAG_PATTERNS:
		return "unknown flag pattern"
	for k in ["pole", "flag", "flag2"]:
		if settings.has(k) and settings[k] != "" and not Color.html_is_valid(settings[k]):
			return "bad colour"
	layout.corner_flags.merge(settings, true)
	return ""


func set_pitch_grass(kind: String) -> String:
	if not kind in Layout.GRASS_TYPES:
		return "unknown grass '%s'" % kind
	layout.pitch_grass = kind
	return ""


## How far a roof ring reaches in over the seats, for every stand at once
## (0 = each stand keeps its own reach; else 0.4..1.5). Sets the size of the
## opening over the pitch.
func set_ring_reach(v: float) -> String:
	if v != 0.0 and (v < 0.4 or v > 1.5):
		return "ring reach must be 0.4..1.5"
	layout.ring_reach = v
	return ""


## The ad boards' words: up to 12 sponsor names of up to 24 letters each.
func set_ad_texts(texts: Array) -> String:
	if texts.size() > 12:
		return "12 adverts at most"
	var clean: Array = []
	for t in texts:
		var w := String(t).strip_edges()
		if w.length() > 24:
			return "'%s' is too long (24 letters at most)" % w
		if w != "":
			clean.append(w.to_upper())
	layout.ad_texts = clean
	return ""


## Pitch marking colour (html): white, or yellow on a snowy day.
func set_line_color(html: String) -> String:
	if not Color.html_is_valid(html):
		return "bad colour"
	layout.line_color = html
	return ""


## Goal frame colour (html), e.g. white, yellow or the club's colour.
func set_goal_color(html: String) -> String:
	if not Color.html_is_valid(html):
		return "bad colour"
	layout.goal_color = html
	return ""


func set_goals(style: String, net_color: String, net_pattern: String) -> String:
	if not style in Layout.GOAL_STYLES:
		return "unknown goal style '%s'" % style
	if not net_pattern in Layout.NET_PATTERNS:
		return "unknown net pattern '%s'" % net_pattern
	if not Color.html_is_valid(net_color):
		return "bad net colour"
	layout.goal_style = style
	layout.net_color = net_color
	layout.net_pattern = net_pattern
	return ""


func set_crowd_culture(kind: String) -> String:
	if not kind in Layout.CROWD_CULTURES:
		return "unknown crowd culture '%s'" % kind
	layout.crowd_culture = kind
	return ""


func set_floodlights(style: String) -> String:
	if not style in Layout.FLOODLIGHT_STYLES:
		return "unknown floodlight style '%s'" % style
	layout.floodlights = style
	return ""


## Floodlight options: per_side (0-6, 0 = the style's own), height (0.6-1.6), color (html or "").
func set_floodlight_opts(settings: Dictionary) -> String:
	for k in settings:
		if not Layout.FLOOD_DEFAULTS.has(k):
			return "floodlights have no setting '%s'" % k
	if settings.has("per_side") and (int(settings["per_side"]) < 0 or int(settings["per_side"]) > 6):
		return "between 1 and 6 masts a side"
	if settings.has("height") and (float(settings["height"]) < 0.6 or float(settings["height"]) > 1.6):
		return "height out of range"
	if settings.has("color") and String(settings["color"]) != "" and not Color.html_is_valid(String(settings["color"])):
		return "bad colour"
	if settings.has("lamp") and not settings["lamp"] in Layout.LAMP_HEADS:
		return "unknown lamp head"
	layout.flood.merge(settings, true)
	layout.flood["per_side"] = int(layout.flood["per_side"])
	layout.flood["height"] = float(layout.flood["height"])
	return ""


## Price of the next strip of land on a side ("" if none left there). Each
## strip costs more than the last, wherever you bought it.
func land_cost(side: String) -> float:
	var l := layout
	if l.land[side] >= config.integer("land/max_strips_per_side"):
		return -1.0
	var along := l.plot.size.x if side == "N" or side == "S" else l.plot.size.y
	var bought := 0
	for k in l.land:
		bought += l.land[k]
	return along * l.strip_tiles * config.num("land/price_per_tile") * (1.0 + config.num("land/price_growth") * bought)


func buy_land(side: String) -> String:
	if not side in Layout.LAND_SIDES:
		return "unknown side '%s'" % side
	var cost := land_cost(side)
	if cost < 0.0:
		return "no more land for sale on that side"
	if cost > club.cash:
		return "land costs %s, you have %s" % [money(cost), money(club.cash)]
	club.cash -= cost
	land_spend += cost
	layout.land[side] += 1
	layout.update_plot()
	return ""


## Square or rounded corner. Changes capacity, so it costs (or refunds) the difference.
func set_corner_shape(index: int, shape: String) -> String:
	if index < 0 or index >= layout.stands.size() or not layout.stands[index].is_corner():
		return "not a corner stand"
	if not shape in Stand.CORNER_SHAPES:
		return "unknown shape '%s'" % shape
	var s := layout.stands[index]
	var old := s.shape
	return _modify(func():
			s.shape = shape
			_drop_orphan_facilities(),
		func(): s.shape = old)


## How round a rounded corner is: 1 = a quarter circle, down to 0.15 = nearly
## square with a tight radius at the tip. Changes capacity, so it costs or refunds.
func set_corner_roundness(index: int, roundness: float) -> String:
	if index < 0 or index >= layout.stands.size() or not layout.stands[index].is_corner():
		return "not a corner stand"
	if roundness < 0.15 or roundness > 1.0:
		return "roundness must be 0.15..1"
	var s := layout.stands[index]
	var old_shape := s.shape
	var old := s.roundness
	return _modify(func():
			s.shape = "rounded"
			s.roundness = roundness
			_drop_orphan_facilities(),
		func():
			s.shape = old_shape
			s.roundness = old)


func demolish_stand(index: int) -> String:
	if index < 0 or index >= layout.stands.size():
		return "no stand %d" % index
	var removed := layout.stands[index]
	var old_facilities := layout.facilities.duplicate()
	return _modify(
		func():
			layout.stands.remove_at(index)
			_drop_orphan_facilities(),
		func():
			layout.stands.insert(index, removed)
			layout.facilities.assign(old_facilities))


func demolish_facility(index: int) -> String:
	if index < 0 or index >= layout.facilities.size():
		return "no facility %d" % index
	var removed := layout.facilities[index]
	return _modify(func(): layout.facilities.remove_at(index),
		func(): layout.facilities.insert(index, removed))


## Facilities that no longer have somewhere to sit (their concourse or stand
## went, or a stand now covers them) are removed.
func _drop_orphan_facilities() -> void:
	var ctx := layout.placement_context(config)
	var kept: Array[Facility] = []
	for f in layout.facilities:
		if layout.facility_error(f, config, ctx) == "":
			kept.append(f)
	layout.facilities = kept


## Cosmetic: change a facility's style. Free.
func restyle_facility(index: int, style: String) -> String:
	if index < 0 or index >= layout.facilities.size():
		return "no facility %d" % index
	if not style in config.facility_type(layout.facilities[index].type_id).styles:
		return "unknown style '%s'" % style
	layout.facilities[index].style = style
	return ""


func _modify(apply: Callable, undo: Callable) -> String:
	var before := layout.build_cost(config)
	var old_site := layout.site.duplicate()
	apply.call()
	layout.prune_site(config)   # building over paths or trees clears them
	var errors := layout.validate(config)
	if not errors.is_empty():
		undo.call()
		layout.site = old_site
		return "; ".join(errors)
	var diff := layout.build_cost(config) - before
	if diff > 0.0 and diff > club.cash:
		undo.call()
		layout.site = old_site
		return "costs %s, you have %s" % [money(diff), money(club.cash)]
	if diff >= 0.0:
		club.cash -= diff
		build_spend += diff
	else:
		var refund := -diff * config.num("season/demolish_refund_fraction")
		club.cash += refund
		demolish_refunds += refund
	return ""


## How money and big numbers are written (a display setting; the sim never reads it).
static var currency := "£"
static var thousands := ","


static func money(v: float) -> String:
	return ("-" if v < 0.0 else "") + currency + number(absf(v))


## A whole number with thousands grouped: 12,345 (or 12.345, 12 345).
static func number(v: float) -> String:
	var neg := v < 0.0
	var s := str(roundi(absf(v)))
	var out := ""
	while s.length() > 3:
		out = thousands + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if neg else "") + s + out


# --- Save / load -------------------------------------------------------------

const SAVE_VERSION := 1


## Everything needed to carry on exactly where the player left off.
## A value rounded to 6 decimals the same way the save file will read it back.
static func _exact(v: float) -> float:
	return ("%.6f" % v).to_float()


func to_save() -> Dictionary:
	# keep the live values exactly as they will read back (JSON drops the last digit)
	club.mood = _exact(club.mood)
	club.fanbase = _exact(club.fanbase)
	start_mood = _exact(start_mood)
	start_fanbase = _exact(start_fanbase)
	var fx := []
	for f in fixtures:
		fx.append(f.to_dict())
	var played := []
	for r in reports:
		played.append(r.to_dict())
	var past := []
	for h in history:
		past.append(h.to_dict())
	return {
		"version": SAVE_VERSION, "seed": seed, "season_number": season_number,
		"rng_state": str(_rng.state), "fixtures": fx, "match_seeds": match_seeds,
		"reports": played, "history": past, "league": league.to_dict(), "round_seeds": round_seeds,
		"build_spend": build_spend, "demolish_refunds": demolish_refunds,
		"land_spend": land_spend, "milestone_rewards": milestone_rewards, "event_income": event_income, "events_held": events_held, "pitch_damage": pitch_damage,
		"start_cash": start_cash, "start_mood": start_mood, "start_fanbase": start_fanbase,
		"layout": layout.to_dict(), "club": club.to_dict(), "continental": continental, "draws": draws,
	}


static func from_save(p_config: SimConfig, d: Dictionary) -> Season:
	var s := Season.new()
	s.config = p_config
	s.layout = Layout.from_dict(d["layout"], p_config)
	s.club = ClubState.from_dict(d["club"], p_config)
	s.seed = int(d["seed"])
	s.season_number = int(d["season_number"])
	s._rng.seed = s.seed
	s._rng.state = int(d["rng_state"])
	if not d.has("league"):
		# an old save (10-match seasons, no league): start this season afresh
		s._make_fixtures()
		s.reports.clear()
		s.build_spend = 0.0
		s.demolish_refunds = 0.0
		s.start_cash = s.club.cash
		s.start_mood = s.club.mood
		s.start_fanbase = s.club.fanbase
		for h in d.get("history", []):
			s.history.append(SeasonReport.from_dict(h))
		return s
	s.league = League.from_dict(d["league"])
	for f in d["fixtures"]:
		s.fixtures.append(Fixture.from_dict(f))
	s.continental = d.get("continental", {})
	s.draws = d.get("draws", [])
	for m in d["match_seeds"]:
		s.match_seeds.append(int(m))
	for m in d.get("round_seeds", []):
		s.round_seeds.append(int(m))
	for r in d["reports"]:
		s.reports.append(MatchdayReport.from_dict(r))
	for h in d.get("history", []):
		s.history.append(SeasonReport.from_dict(h))
	s.build_spend = float(d["build_spend"])
	s.demolish_refunds = float(d["demolish_refunds"])
	s.land_spend = float(d.get("land_spend", 0.0))
	s.milestone_rewards = float(d.get("milestone_rewards", 0.0))
	s.event_income = float(d.get("event_income", 0.0))
	s.events_held = int(d.get("events_held", 0))
	s.pitch_damage = float(d.get("pitch_damage", 0.0))
	s.start_cash = float(d["start_cash"])
	s.start_mood = float(d["start_mood"])
	s.start_fanbase = float(d["start_fanbase"])
	return s


func save_file(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_save(), "  ", true, true))  # full float precision
	return OK


static func load_file(p_config: SimConfig, path: String) -> Season:
	if not FileAccess.file_exists(path):
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or int(data.get("version", 0)) != SAVE_VERSION:
		return null
	return from_save(p_config, data)


func summary() -> SeasonReport:
	return SeasonReport.from_season(self)
