class_name MatchdaySim
extends RefCounted
## One matchday: demand -> attendance -> atmosphere -> result -> halftime -> money -> mood -> fanbase.
## Pure function of (config, layout, club, fixture, seed). Does not mutate inputs.

## Halftime kinds are whatever has a share in tuning halftime/share
## (food, drink, merch, restroom).
static func kinds(config: SimConfig) -> Array:
	return (config.value("halftime/share") as Dictionary).keys()


static func run(config: SimConfig, layout: Layout, club: ClubState, fixture: Fixture, seed: int) -> MatchdayReport:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var r := MatchdayReport.new()
	r.layout_name = layout.name
	r.opponent = fixture.opponent
	r.big_match = fixture.big
	r.seed = seed
	r.sponsor = club.sponsor
	for f in layout.facilities:
		r.layout_facilities.append(f.type_id)

	r.home = fixture.home
	r.round = fixture.round
	r.competition = fixture.competition
	r.comp_name = fixture.comp_name
	r.stage = fixture.stage
	r.knockout = fixture.knockout
	r.division = club.division
	r.evening = fixture.evening
	r.weather = fixture.weather
	# 1. Demand (rng draw #1: demand noise) and 2. attendance: only at home
	var noise_amp := config.num("demand/noise")
	var dnoise := rng.randf_range(-noise_amp, noise_amp)
	r.atmosphere_bonus = compute_atmosphere_bonus(config, layout)
	if fixture.home:
		r.demand_multipliers = demand_multipliers(config, club, fixture, dnoise)
		r.demand = compute_demand(config, club, r.demand_multipliers)
		r.stands = compute_attendance(config, layout, r.demand)
		apply_weather(config, layout, r.stands, fixture.weather)
		r.transport_capacity = layout.transport_capacity(config)
		r.transport_turned_away = apply_transport_cap(r.stands, r.transport_capacity)
		fill_away_end(config, layout, club, fixture, r.stands)
	else:
		# away: your ground stands empty (every stand listed, nobody in it)
		r.demand_multipliers = { "form": 1.0, "mood": 1.0, "opponent": 1.0, "noise": 1.0 }
		var none := {}
		for id in config.stand_type_ids():
			none[id] = 0
		r.demand = none
		r.stands = compute_attendance(config, layout, none)
	r.capacity = 0
	r.attendance = 0
	for s in r.stands:
		r.capacity += s["capacity"]
		r.attendance += s["attendance"]

	# 3. Result from team strengths: squad spend vs theirs, plus form on the
	# day, plus your crowd at home (rng draws #2-#3: form, then goals)
	r.atmosphere = clampf(compute_atmosphere(config, r.stands) + (r.atmosphere_bonus if r.attendance > 0 else 0.0), 0.0, 100.0) if fixture.home else 0.0
	r.home_advantage = r.atmosphere / 100.0 * config.num("result/max_home_advantage") if fixture.home else 0.0
	# a good surface suits the home side; a frozen or bare one levels things out
	if fixture.home:
		r.pitch_quality = pitch_quality(config, layout, fixture.weather)
		r.home_advantage += (r.pitch_quality - config.num("pitch/base")) * config.num("pitch/result_effect")
	var form := config.num("result/form_noise")
	var ours := League.club_rating(config, club) + rng.randfn(0.0, form)
	var theirs := fixture.opponent_rating + rng.randfn(0.0, form)
	var xg_us := League.expected_goals(config, ours, theirs, fixture.home) * (1.0 + r.home_advantage)
	var xg_them := League.expected_goals(config, theirs, ours, not fixture.home)
	r.probabilities = outcome_odds(xg_us, xg_them)
	r.home_goals = League.poisson(rng, xg_us)       # the club's goals (home or away)
	r.away_goals = League.poisson(rng, xg_them)      # the opponent's
	r.result = "W" if r.home_goals > r.away_goals else ("D" if r.home_goals == r.away_goals else "L")
	r.roll = 0.0
	r.events = match_events(r.home_goals, r.away_goals, xg_us, xg_them, club.club_name, fixture.opponent, rng)

	# 3b. Getting in: turnstiles, then stairs to the upper tiers
	r.ingress = simulate_ingress(config, layout, r.stands, club.staff_level("stewards")) if fixture.home else {}

	# 4. Halftime rush
	var ht := simulate_halftime(config, layout, r.stands, club.prices, club.staff_level("catering"))
	r.facilities = ht["facilities"]
	r.halftime = ht["kinds"]

	# 5. Money
	compute_finances(config, layout, club, r)
	if not fixture.is_league():
		# competition TV money and prize money
		var tv_div := float(r.revenue.get("tv", 0.0))
		var tv := fixture.tv if fixture.tv >= 0.0 else tv_div
		var prize := fixture.prize_win if r.result == "W" else (fixture.prize_draw if r.result == "D" else 0.0)
		r.revenue["tv"] = tv
		r.revenue["prize"] = prize
		r.revenue["total"] = float(r.revenue["total"]) - tv_div + tv + prize
		r.net = float(r.revenue["total"]) - float(r.costs["total"])

	# 6. Mood
	r.mood_before = club.mood
	r.mood_change = compute_mood_change(config, r)
	# rounded so saves round-trip exactly
	r.mood_after = snappedf(clampf(club.mood + r.mood_change["total"], config.num("mood/min"), config.num("mood/max")), 0.000001)

	# 7. Fanbase growth
	r.fanbase_before = club.fanbase
	r.fanbase_growth = compute_fanbase_growth(config, r)
	r.fanbase_after = snappedf(club.fanbase * (1.0 + r.fanbase_growth["total"]), 0.000001)
	return r


## If more fans want to come than can get here, every stand loses the same share.
## Returns how many were turned away.
static func apply_transport_cap(stands: Array[Dictionary], cap: float) -> int:
	var total := 0
	for s in stands:
		total += s["attendance"]
	if total <= cap or total == 0:
		return 0
	var keep := cap / total
	var after := 0
	for s in stands:
		s["attendance"] = floori(s["attendance"] * keep)
		s["fill"] = float(s["attendance"]) / float(s["capacity"]) if s["capacity"] > 0 else 0.0
		after += s["attendance"]
	return total - after


## How good the pitch is on the day, 0..1: pitch care between matches helps;
## snow freezes a pitch with no undersoil heating.
static func pitch_quality(config: SimConfig, layout: Layout, weather: String) -> float:
	var q := config.num("pitch/base") + float((config.value("pitch/care") as Dictionary).get(layout.pitch_care, 0.0))
	if weather == "snow" and not layout.heating:
		q -= config.num("pitch/frozen_penalty")
	return clampf(q, 0.0, 1.0)


## Visiting fans come on their own coaches and trains and fill the empty
## places in stands set aside for them; their tickets are the club's money.
static func fill_away_end(config: SimConfig, layout: Layout, club: ClubState, fixture: Fixture, stands: Array[Dictionary]) -> void:
	var dm := float(config.division(club.division).get("demand_multiplier", 1.0))
	var want := roundi(config.num("away/fans_base") * dm * dm * (config.num("away/big_match_multiplier") if fixture.big else 1.0))
	for i in layout.stands.size():
		var st: Dictionary = stands[i]
		st["away"] = 0
		if not layout.stands[i].away or want <= 0:
			continue
		var room := int(st["capacity"]) - int(st["attendance"])
		var n := mini(room, want)
		want -= n
		st["away"] = n
		st["attendance"] = int(st["attendance"]) + n
		st["fill"] = float(st["attendance"]) / float(st["capacity"]) if int(st["capacity"]) > 0 else 0.0


## Flat atmosphere points from screens, sound systems and fan zones, capped.
static func compute_atmosphere_bonus(config: SimConfig, layout: Layout) -> float:
	var bonus := 0.0
	for f in layout.facilities:
		bonus += config.facility_type(f.type_id).atmosphere_bonus
	return minf(bonus, config.num("bowl/atmosphere_bonus_cap"))


static func demand_multipliers(config: SimConfig, club: ClubState, fixture: Fixture, noise: float) -> Dictionary:
	var comp := 1.0
	if fixture.competition == "continental":
		comp = config.num("midweek/continental_demand")
	elif fixture.competition == "cup":
		comp = config.num("midweek/cup_big_opponent") if fixture.big else config.num("midweek/cup_demand_low")
	return {
		"competition": comp,
		"night": fixture.evening,
		"form": config.num("demand/form_base") + config.num("demand/form_per_ppg") * club.form_ppg(config),
		"opponent": config.num("demand/big_match_multiplier") if fixture.big else 1.0,
		"mood": config.num("demand/mood_base") + config.num("demand/mood_scale") * club.mood / 100.0,
		"noise": 1.0 + noise,
		"division": float(config.division(club.division)["demand_multiplier"]),
	}


## Fans wanting a ticket per stand type, before capacity limits.
static func compute_demand(config: SimConfig, club: ClubState, mult: Dictionary) -> Dictionary:
	var base: float = club.fanbase * mult["form"] * mult["opponent"] * mult["mood"] * mult["noise"] * mult.get("division", 1.0) * float(mult.get("competition", 1.0))
	# season ticket holders come whatever the form: a steadier, bigger crowd
	base *= 1.0 + club.season_tickets * config.num("season_tickets/demand_boost")
	var night: bool = mult.get("night", false)
	var out := {}
	for id in config.stand_type_ids():
		var t := config.stand_type(id)
		if t.demand_pool != id:
			continue   # shares another type's fans
		var price_factor := pow(club.price(id) / t.reference_price, t.elasticity)
		# night games: more people free after work, fewer families with young children
		var nf := 1.0
		if night:
			nf = config.num("midweek/night_family") if id == "family" else config.num("midweek/night_demand")
		out[id] = roundi(base * t.demand_share * price_factor * nf)
	return out


## Each type's demand is shared across its stands by capacity and capped.
## Overflow is lost (no spill into other types).
static func compute_attendance(config: SimConfig, layout: Layout, demand: Dictionary) -> Array[Dictionary]:
	var cap_by_type := {}
	for s in layout.stands:
		var pool := config.stand_type(s.type_id).demand_pool
		var cap := s.capacity(config.stand_type(s.type_id))
		cap_by_type[pool] = cap_by_type.get(pool, 0) + cap
	var out: Array[Dictionary] = []
	for s in layout.stands:
		var pool := config.stand_type(s.type_id).demand_pool
		var cap := s.capacity(config.stand_type(s.type_id))
		var share := float(cap) / float(cap_by_type[pool])
		# a stand with a poor view sells fewer of its tickets
		# a stand priced above (or below) its type sells fewer (or more) of its tickets
		var price_mult := 1.0 + s.price_adj
		var price_factor := pow(price_mult, config.stand_type(s.type_id).elasticity)
		var att: int = min(cap, roundi(demand.get(pool, 0) * share * view_quality(config, s) * price_factor))
		out.append({
			"label": s.label(), "type": s.type_id, "capacity": cap, "attendance": att, "price_mult": price_mult,
			"fill": float(att) / float(cap) if cap > 0 else 0.0,
			"proximity": max(0.0, 1.0 - config.num("atmosphere/proximity_per_setback") * s.setback)
				* (1.0 - config.num("atmosphere/upper_tier_proximity") * (s.tiers - 1) / float(s.tiers))
				* clampf(1.0 + (s.rake - 24.0) * 0.01, 0.85, 1.15),
			"noise": config.stand_type(s.type_id).noise,
			"view": view_quality(config, s),
			"steep": steepness(config, s),
		})
	return out


## How good the view is from a stand, 0..1 (1 = as good as it gets): a
## shallow rake puts heads in the way and back rows far away; deep stands
## push the back rows away from the pitch; a low front row sees little.
static func view_quality(config: SimConfig, s: Stand) -> float:
	var q := 1.0
	var good := config.num("view/good_rake")
	if s.rake < good:
		q -= (good - s.rake) * config.num("view/shallow_penalty_per_degree") * (1.0 + s.depth / 10.0)
	var far := maxi(0, s.setback + s.depth - config.integer("view/distance_free_rows"))
	q -= far * config.num("view/distance_penalty_per_row") * (good / maxf(s.rake, 1.0))
	if s.plinth < config.num("view/plinth_good"):
		q -= (config.num("view/plinth_good") - s.plinth) * config.num("view/plinth_penalty")
	# a shed roof stands on pillars along the front: some seats look round them
	if s.roof == "shed":
		q -= config.num("view/pillar_penalty")
	return clampf(q, 0.5, 1.0)


## How steep a stand feels, in degrees over the comfortable limit (0 = fine).
static func steepness(config: SimConfig, s: Stand) -> float:
	return maxf(0.0, s.rake - config.num("view/steep_from"))


## Getting in. Most fans arrive in the last half hour; each stand lets them in
## through its turnstiles, and fans for upper tiers then climb the stand's
## stairs (built-in ones plus any stairways, ramps, escalators and lifts on its
## concourse). Whatever can't get through by kick-off arrives late.
## Returns { stands: [{late, wait, gate_rate, climb_rate}], late, late_share, wait }.
static func simulate_ingress(config: SimConfig, layout: Layout, stands: Array[Dictionary], stewards := 1.0) -> Dictionary:
	var per_tiles := config.integer("ingress/gates_per_tiles")
	# more stewards on the gates search and scan faster
	var per_gate := config.num("ingress/fans_per_gate_per_min") * pow(stewards, config.num("staff/gate_exponent"))
	var window := config.num("ingress/late_window_min")
	var late_share := config.num("ingress/late_share")
	var climb := {}
	var conc := layout.concourse_tile_map(config)
	var stand_tiles := layout.stand_tile_map()
	for f in layout.facilities:
		var ft := config.facility_type(f.type_id)
		if ft.kind == "circulation":
			var si := layout.circulation_stand(f, config, conc, stand_tiles)
			if si >= 0:
				climb[si] = float(climb.get(si, 0.0)) + ft.capacity
	var out := []
	var total_late := 0
	var total := 0
	var wait_sum := 0.0
	for i in layout.stands.size():
		var s := layout.stands[i]
		var att: int = stands[i]["attendance"]
		var gate_rate := s.gate_count(per_tiles, config.integer("ingress/auto_places_per_gate"), s.capacity(config.stand_type(s.type_id))) * per_gate
		var upper := att * (s.tiers - 1) / maxi(1, s.tiers)
		var climb_rate := s.length * config.num("ingress/builtin_stairs_per_tile") + float(climb.get(i, 0.0))
		# the rush: late_share of the crowd in the last `window` minutes
		var rush := att * late_share
		var late_gate := maxf(0.0, rush - gate_rate * window)
		var rush_up := upper * late_share
		var late_up := maxf(0.0, rush_up - climb_rate * window) if s.tiers > 1 else 0.0
		var late := int(minf(float(att), late_gate + late_up))
		# average queue: half the time it takes to clear the rush at the slowest point
		var wait := 0.0
		if att > 0:
			wait = 0.5 * rush / maxf(gate_rate, 1.0)
			if s.tiers > 1:
				wait = maxf(wait, 0.5 * rush_up / maxf(climb_rate, 1.0))
		out.append({ "late": late, "wait": snappedf(wait, 0.01), "gate_rate": gate_rate, "climb_rate": climb_rate })
		total_late += late
		total += att
		wait_sum += wait * att
	return { "stands": out, "late": total_late, "late_share": float(total_late) / maxf(1.0, total), "wait": snappedf(wait_sum / maxf(1.0, total), 0.01) }


## 0..100. Capacity-weighted mean of noise x fill x proximity, scaled by the
## loudest stand type, times a crowd-size factor sqrt(min(1, crowd / reference)).
static func compute_atmosphere(config: SimConfig, stands: Array[Dictionary]) -> float:
	var weighted := 0.0
	var cap := 0
	var crowd := 0
	for s in stands:
		weighted += s["noise"] * s["fill"] * s["proximity"] * s["capacity"]
		cap += s["capacity"]
		crowd += s["attendance"]
	if cap == 0:
		return 0.0
	var intensity := weighted / (config.num("atmosphere/noise_reference") * cap)
	var volume := sqrt(min(1.0, crowd / config.num("atmosphere/volume_reference")))
	return clampf(100.0 * intensity * volume, 0.0, 100.0)


## Rain and snow keep some fans away from stands with no roof.
static func apply_weather(config: SimConfig, layout: Layout, stands: Array[Dictionary], weather: String) -> void:
	var pen := float((config.value("weather/penalty") as Dictionary).get(weather, 0.0))
	if pen <= 0.0:
		return
	for i in stands.size():
		if layout.stands[i].roof == "open":
			var s: Dictionary = stands[i]
			s["attendance"] = floori(s["attendance"] * (1.0 - pen))
			s["fill"] = float(s["attendance"]) / float(s["capacity"]) if s["capacity"] > 0 else 0.0


## Win/draw/loss chances. `shift` makes opponents tougher in higher divisions.
## Win / draw / loss chances for two expected-goal rates (Poisson).
static func outcome_odds(a: float, b: float) -> Dictionary:
	var pa := []
	var pb := []
	for k in 11:
		pa.append(exp(-a) * pow(a, k) / _fact(k))
		pb.append(exp(-b) * pow(b, k) / _fact(k))
	var w := 0.0
	var d := 0.0
	for i in 11:
		for j in 11:
			var p: float = pa[i] * pb[j]
			if i > j:
				w += p
			elif i == j:
				d += p
	# rounded so the numbers survive a save / load unchanged
	return { "win": snappedf(w, 0.0001), "draw": snappedf(d, 0.0001), "loss": snappedf(maxf(0.0, 1.0 - w - d), 0.0001) }


static func _fact(k: int) -> float:
	var f := 1.0
	for i in range(2, k + 1):
		f *= i
	return f


const FIRST := ["Jack", "Tom", "Sam", "Danny", "Luke", "Joe", "Ryan", "Callum", "Liam", "Kieran", "Marcus", "Ollie", "Ben", "Jamie", "Harry", "Adam", "Nathan", "Lewis", "Kai", "Elliot"]
const LAST := ["Walsh", "Hughes", "Carter", "Bennett", "Doyle", "Murphy", "Price", "Fletcher", "Reid", "Barker", "Holt", "Nash", "Quinn", "Shaw", "Kerr", "Lowe", "Dunn", "Rowe", "Tate", "Webb", "Okafor", "Silva", "Mensah", "Novak"]


## A striker's name for a club: the same few names keep scoring for a club.
static func scorer(club: String, rng: RandomNumberGenerator) -> String:
	var h := absi(hash(club))
	var pick := rng.randi_range(0, 5)
	var f: String = FIRST[(h / (7 + pick)) % FIRST.size()]
	var l: String = LAST[(h / (13 + pick * 3)) % LAST.size()]
	return "%s. %s" % [f[0], l]


## Goals with minutes and scorers, plus shots and possession, for the report.
static func match_events(us: int, them: int, xg_us: float, xg_them: float, our_name: String, their_name: String, rng: RandomNumberGenerator) -> Dictionary:
	var goals := []
	for side in [[us, "us", our_name], [them, "them", their_name]]:
		for i in int(side[0]):
			goals.append({ "min": rng.randi_range(2, 90) + (rng.randi_range(1, 4) if rng.randf() < 0.08 else 0), "side": side[1], "name": scorer(side[2], rng) })
	goals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["min"] < b["min"])
	var poss := clampf(50.0 + (xg_us - xg_them) * 9.0 + rng.randf_range(-6.0, 6.0), 28.0, 72.0)
	return {
		"goals": goals,
		"shots": [us + maxi(1, roundi(xg_us * 7.0 + rng.randf_range(-2, 3))), them + maxi(1, roundi(xg_them * 7.0 + rng.randf_range(-2, 3)))],
		"possession": [roundi(poss), 100 - roundi(poss)],
	}


static func result_probabilities(config: SimConfig, home_adv: float, shift := 0.0) -> Dictionary:
	var win: float = maxf(0.05, config.num("result/base_win") + home_adv - shift)
	var loss: float = clampf(config.num("result/base_loss") - home_adv + shift, 0.0, 1.0 - win)
	return { "win": win, "draw": 1.0 - win - loss, "loss": loss }


## A believable scoreline for a result.
static func scoreline(result: String, rng: RandomNumberGenerator) -> Vector2i:
	var low: int = [0, 0, 0, 1, 1, 2][rng.randi_range(0, 5)]
	var margin: int = [1, 1, 1, 2, 2, 3][rng.randi_range(0, 5)]
	match result:
		"W": return Vector2i(low + margin, low)
		"L": return Vector2i(low, low + margin)
	return Vector2i(low, low)


static func pick_result(p: Dictionary, roll: float) -> String:
	if roll < p["win"]:
		return "W"
	if roll < p["win"] + p["draw"]:
		return "D"
	return "L"


## Every stand section sends its share of fans to the nearest facility of each
## kind by walking distance. Each facility then runs QueueModel.
static func simulate_halftime(config: SimConfig, layout: Layout, stands: Array[Dictionary], prices: Dictionary = {}, catering := 1.0) -> Dictionary:
	# more staff behind the counters serve faster
	var serve := pow(catering, config.num("staff/serve_exponent"))
	var window := config.num("halftime/window_minutes")
	var speed := config.num("halftime/walk_tiles_per_minute")
	var section_len := config.integer("layout/section_length")
	var stairs := config.num("halftime/stairs_tiles")
	var stand_tiles := layout.blocked_tiles(config)

	var arrivals := []
	var walk_sum := []
	for f in layout.facilities:
		arrivals.append(0)
		walk_sum.append(0.0)
	var kinds := {}
	var kind_list := kinds(config)
	for kind in kind_list:
		kinds[kind] = { "wanting": 0, "served": 0, "lost": 0, "unreachable": 0, "price": float(prices.get(kind, 1.0)) }
	# dearer stalls sell to fewer fans (and cheaper ones to more)
	var buy := {}
	for kind in kind_list:
		buy[kind] = pow(float(prices.get(kind, 1.0)), config.num("concessions/elasticity"))

	for si in layout.stands.size():
		var att: int = stands[si]["attendance"]
		var sections := layout.stands[si].sections(layout.pitch, section_len, Layout.internal_concourse(layout.stands[si], config),
			config.integer("layout/concourse_depth"))
		var assigned := 0
		for k in sections.size():
			var sec: Dictionary = sections[k]
			# Last section takes the rounding remainder so fans are conserved.
			var fans := att - assigned if k == sections.size() - 1 else roundi(att * sec["weight"])
			assigned += fans
			var dist := layout.walk_distances_cached(sec["source"], stand_tiles)
			# Fans split evenly across tiers; each tier prefers its own concourse
			# level and pays a stairs penalty to use another.
			var tiers: int = layout.stands[si].tiers
			var tier_assigned := 0
			for lvl in tiers:
				var tier_fans := fans - tier_assigned if lvl == tiers - 1 else roundi(float(fans) / tiers)
				tier_assigned += tier_fans
				for kind in kind_list:
					var wanting := roundi(tier_fans * config.num("halftime/share/" + kind) * float(buy[kind]))
					kinds[kind]["wanting"] += wanting
					var best := -1
					var best_d := INF
					for fi in layout.facilities.size():
						var f := layout.facilities[fi]
						if config.facility_type(f.type_id).kind != kind or not dist.has(f.pos):
							continue
						var d: float = dist[f.pos] + absi(f.level - lvl) * stairs
						if d < best_d:
							best_d = d
							best = fi
					if best == -1:
						kinds[kind]["unreachable"] += wanting
						kinds[kind]["lost"] += wanting
						continue
					arrivals[best] += wanting
					walk_sum[best] += wanting * 2.0 * best_d / speed

	var facilities: Array[Dictionary] = []
	for fi in layout.facilities.size():
		var f := layout.facilities[fi]
		var ft := config.facility_type(f.type_id)
		if not kinds.has(ft.kind):
			continue
		var round_trip: float = walk_sum[fi] / arrivals[fi] if arrivals[fi] > 0 else 0.0
		var q := QueueModel.simulate(arrivals[fi], ft.service_rate_per_min * serve, window, round_trip)
		q["label"] = f.label()
		q["kind"] = ft.kind
		q["round_trip_min"] = round_trip
		q["revenue"] = q["served"] * ft.spend_per_customer * float(prices.get(ft.kind, 1.0))
		q["lost_sales"] = q["lost"] * ft.spend_per_customer
		kinds[ft.kind]["served"] += q["served"]
		kinds[ft.kind]["lost"] += q["lost"]
		facilities.append(q)
	return { "facilities": facilities, "kinds": kinds }


const REVENUE_BY_KIND := { "food": "food", "drink": "drinks", "merch": "merch" }


static func compute_finances(config: SimConfig, layout: Layout, club: ClubState, r: MatchdayReport) -> void:
	var rev := { "tickets": 0.0, "food": 0.0, "drinks": 0.0, "merch": 0.0, "premium": 0.0, "sponsors": 0.0,
		"boxes": 0.0, "venue": 0.0, "naming": 0.0, "stand_naming": 0.0, "tv": 0.0 }
	for s in r.stands:
		rev["tickets"] += s["attendance"] * club.price(s["type"]) * float(s.get("price_mult", 1.0)) * (1.0 - club.season_tickets * config.num("season_tickets/discount"))
		rev["premium"] += s["attendance"] * config.stand_type(s["type"]).hospitality_per_head
	var lost := 0.0
	for f in r.facilities:
		if REVENUE_BY_KIND.has(f["kind"]):
			rev[REVENUE_BY_KIND[f["kind"]]] += f["revenue"]
		lost += f["lost_sales"]
	# Fans with no reachable stand of a spending kind are lost sales too,
	# priced at that kind's cheapest spend.
	for kind in r.halftime:
		var unreachable: int = r.halftime[kind]["unreachable"]
		if unreachable == 0:
			continue
		var spend := INF
		for id in config.facility_types:
			var ft := config.facility_type(id)
			if ft.kind == kind and ft.spend_per_customer > 0.0:
				spend = minf(spend, ft.spend_per_customer)
		if spend != INF:
			lost += unreachable * spend
	# Boards earn sponsorship, scaled by how many people see them.
	var scale := clampf(r.attendance / config.num("bowl/sponsor_attendance_reference"),
		config.num("bowl/sponsor_scale_min"), config.num("bowl/sponsor_scale_max"))
	var stand_tiles := layout.stand_tile_map()
	for f in layout.facilities:
		var ft := config.facility_type(f.type_id)
		rev["sponsors"] += ft.sponsor_per_match * scale
		rev["venue"] += ft.income_per_match
		if ft.box_price > 0.0 and stand_tiles.has(f.pos):
			rev["boxes"] += box_count(layout.stands[stand_tiles[f.pos]]) * ft.box_price * box_occupancy(config, club)
	rev["naming"] = naming_fee(config, club.sponsor, r.capacity)
	# stands sold to a sponsor on their own: a share of the fee for their places
	for st in layout.stands:
		if st.sponsor != "":
			rev["stand_naming"] += config.num("economy/stand_naming_share") * naming_fee(config, st.sponsor, st.capacity(config.stand_type(st.type_id)))
	rev["tv"] = float(config.division(club.division)["tv_per_match"])
	var total := 0.0
	for k in rev:
		total += rev[k]
	rev["total"] = total
	r.revenue = rev
	r.lost_food_sales = lost
	var upkeep := layout.upkeep(config)
	var use := layout.utilities(config)
	var bill: float = use["power"] * config.num("utilities/power_price") + use["water"] * config.num("utilities/water_price")
	r.utilities = use
	var wages := club.wage(config)
	# the club's running costs whatever the venue, and interest on any debt
	var overheads := float(config.division(club.division).get("overheads_per_match", 0.0))
	var interest := roundf(maxf(0.0, -club.cash) * config.num("economy/debt_interest_per_match"))
	# a bank loan: interest on what's owed plus a fixed slice of the principal
	var loan_repaid := minf(club.loan, club.loan_payment)
	var loan_cost := roundf(club.loan * config.num("economy/loan_interest_per_match")) + loan_repaid
	if not r.home:
		# away: the home club keeps the gate; you still get TV money and pay the squad
		for k in rev:
			if k != "tv":
				rev[k] = 0.0
		total = float(rev["tv"])
		rev["total"] = total
		r.revenue = rev
		r.lost_food_sales = 0.0
		r.costs = { "stands": 0.0, "facilities": 0.0, "utilities": 0.0, "wages": wages, "overheads": overheads, "interest": interest,
			"loan": loan_cost, "loan_repaid": 0.0, "matchday": 0.0, "total": wages + overheads + interest + loan_cost }
		r.costs["loan_repaid"] = loan_repaid
		r.net = total - float(r.costs["total"])
		return
	var stewards := r.attendance * config.num("economy/stewarding_per_fan") * club.staff_level("stewards")
	# counter staff for every stall that sells something
	var stalls := 0
	for f in layout.facilities:
		if REVENUE_BY_KIND.has(config.facility_type(f.type_id).kind):
			stalls += 1
	var catering := stalls * config.num("staff/catering_per_stall") * club.staff_level("catering")
	stewards += catering
	# groundstaff kit: pitch care and undersoil heating (which runs hard in snow)
	var pitch := float((config.value("pitch/care_cost") as Dictionary).get(layout.pitch_care, 0.0))
	if layout.heating:
		pitch += config.num("pitch/heating_cost") * (config.num("pitch/heating_snow_mult") if r.weather == "snow" else 1.0)
	# big matches need a police operation, paid per fan in the ground
	if r.big_match:
		stewards += r.attendance * config.num("economy/policing_big_per_fan")
	r.costs = { "stands": upkeep["stands"], "facilities": upkeep["facilities"], "utilities": bill, "wages": wages,
		"overheads": overheads, "interest": interest, "loan": loan_cost, "matchday": stewards, "pitch": pitch,
		"total": upkeep["stands"] + upkeep["facilities"] + bill + wages + overheads + interest + loan_cost + stewards + pitch }
	r.costs["loan_repaid"] = loan_repaid
	r.net = r.revenue["total"] - r.costs["total"]


## Executive boxes: two tiles of frontage per box, one row between each pair of tiers.
static func box_count(s: Stand) -> int:
	return (s.length if not s.is_corner() else s.depth) / 2 * (s.tiers - 1)


## Share of boxes sold: corporate demand grows with the club.
static func box_occupancy(config: SimConfig, club: ClubState) -> float:
	return clampf(club.fanbase / 30000.0, 0.2, 1.0)


static func naming_fee(config: SimConfig, id: String, capacity: int) -> float:
	if id == "" or not config.sponsors.has(id):
		return 0.0
	var sp: Dictionary = config.sponsors[id]
	return float(sp["fee_base"]) + float(sp["fee_per_1000_places"]) * capacity / 1000.0


static func compute_mood_change(config: SimConfig, r: MatchdayReport) -> Dictionary:
	var from_result := config.num("mood/win") if r.result == "W" else (
		config.num("mood/draw") if r.result == "D" else config.num("mood/loss"))
	var from_atmos := (r.atmosphere - config.num("mood/atmosphere_pivot")) * config.num("mood/atmosphere_scale")
	var wanting := 0
	var lost := 0
	for kind in config.value("halftime/mood_kinds"):
		if r.halftime.has(kind):
			wanting += r.halftime[kind]["wanting"]
			lost += r.halftime[kind]["lost"]
	var unserved_share := float(lost) / float(wanting) if wanting > 0 else 0.0
	var from_service := -config.num("mood/unserved_penalty") * unserved_share
	# Mood drifts back toward its starting level, so one bad spell doesn't stick forever.
	var from_recovery := (config.num("mood/start") - r.mood_before) * config.num("mood/recovery")
	var from_care := care_bonus(config, r) - naming_penalty(config, r)
	# very steep stands make some fans nervous
	var steep_fans := 0.0
	for st in r.stands:
		steep_fans += float(st.get("steep", 0.0)) * st["attendance"]
	var from_steep := -config.num("view/steep_mood_per_degree") * steep_fans / maxf(1.0, r.attendance)
	# missing kick-off in a queue is the worst start to a matchday
	var from_late := -config.num("ingress/late_mood_scale") * float(r.ingress.get("late_share", 0.0))
	# fans notice dear (or cheap) pies and pints
	var from_prices := 0.0
	if r.home and r.attendance > 0:
		for kind in r.halftime:
			from_prices -= (float(r.halftime[kind].get("price", 1.0)) - 1.0) * config.num("concessions/mood_per_price")
	return { "result": from_result, "atmosphere": from_atmos, "service": from_service,
		"recovery": from_recovery, "care": from_care, "steep": from_steep, "late": from_late, "prices": from_prices, "unserved_share": unserved_share,
		"total": from_result + from_atmos + from_service + from_recovery + from_care + from_steep + from_late + from_prices }


## Fans grumble a little about a sponsor's name on their ground.
static func naming_penalty(config: SimConfig, r: MatchdayReport) -> float:
	var p := 0.0 if r.revenue.get("naming", 0.0) <= 0.0 else float(config.sponsors[r.sponsor]["mood_penalty"])
	if float(r.revenue.get("stand_naming", 0.0)) > 0.0:
		p += config.num("economy/stand_naming_mood")
	return p


## Mood from first aid posts and fan zones: each type's bonus, scaled by how
## much of the crowd its posts cover.
static func care_bonus(config: SimConfig, r: MatchdayReport) -> float:
	if r.attendance <= 0 or r.layout_facilities.is_empty():
		return 0.0
	var counts := {}
	for id in r.layout_facilities:
		counts[id] = counts.get(id, 0) + 1
	var bonus := 0.0
	for id in counts:
		var t := config.facility_type(id)
		if t.mood_bonus > 0.0 and t.coverage > 0.0:
			bonus += t.mood_bonus * minf(1.0, counts[id] * t.coverage / r.attendance)
	return bonus


## Fractional fanbase growth for this match. Generous by design: a club that
## plays and keeps fans reasonably happy grows; success and noise speed it up.
## Growth slows as the fanbase nears the cap.
static func compute_fanbase_growth(config: SimConfig, r: MatchdayReport) -> Dictionary:
	var from_base := config.num("fans/growth_base")
	var from_result := config.num("fans/growth_win") if r.result == "W" else (
		config.num("fans/growth_draw") if r.result == "D" else config.num("fans/growth_loss"))
	var from_mood := (r.mood_after - 50.0) / 50.0 * config.num("fans/growth_mood_scale")
	var from_atmos := r.atmosphere / 100.0 * config.num("fans/growth_atmosphere_scale")
	var headroom: float = max(0.0, 1.0 - r.fanbase_before / config.num("fans/fanbase_cap"))
	var total := (from_base + from_result + from_mood + from_atmos) * headroom
	return { "base": from_base, "result": from_result, "mood": from_mood,
		"atmosphere": from_atmos, "headroom": headroom, "total": total }
