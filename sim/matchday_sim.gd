class_name MatchdaySim
extends RefCounted
## One matchday: demand -> attendance -> atmosphere -> result -> halftime -> money -> mood.
## Pure function of (config, layout, club, fixture, seed). Does not mutate inputs.

const KINDS := ["food", "restroom"]


static func run(config: SimConfig, layout: Layout, club: ClubState, fixture: Fixture, seed: int) -> MatchdayReport:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var r := MatchdayReport.new()
	r.layout_name = layout.name
	r.opponent = fixture.opponent
	r.big_match = fixture.big
	r.seed = seed

	# 1. Demand (rng draw #1: demand noise)
	var noise_amp := config.num("demand/noise")
	r.demand_multipliers = demand_multipliers(config, club, fixture, rng.randf_range(-noise_amp, noise_amp))
	r.demand = compute_demand(config, club, r.demand_multipliers)

	# 2. Attendance
	r.stands = compute_attendance(config, layout, r.demand)
	r.capacity = 0
	r.attendance = 0
	for s in r.stands:
		r.capacity += s["capacity"]
		r.attendance += s["attendance"]

	# 3. Atmosphere -> home advantage -> result (rng draw #2: result roll)
	r.atmosphere = compute_atmosphere(config, r.stands)
	r.home_advantage = r.atmosphere / 100.0 * config.num("result/max_home_advantage")
	r.probabilities = result_probabilities(config, r.home_advantage)
	r.roll = rng.randf()
	r.result = pick_result(r.probabilities, r.roll)

	# 4. Halftime rush
	var ht := simulate_halftime(config, layout, r.stands)
	r.facilities = ht["facilities"]
	r.halftime = ht["kinds"]

	# 5. Money
	compute_finances(config, layout, club, r)

	# 6. Mood
	r.mood_before = club.mood
	r.mood_change = compute_mood_change(config, r)
	r.mood_after = clampf(club.mood + r.mood_change["total"], config.num("mood/min"), config.num("mood/max"))
	return r


static func demand_multipliers(config: SimConfig, club: ClubState, fixture: Fixture, noise: float) -> Dictionary:
	return {
		"form": config.num("demand/form_base") + config.num("demand/form_per_ppg") * club.form_ppg(config),
		"opponent": config.num("demand/big_match_multiplier") if fixture.big else 1.0,
		"mood": config.num("demand/mood_base") + config.num("demand/mood_scale") * club.mood / 100.0,
		"noise": 1.0 + noise,
	}


## Fans wanting a ticket per stand type, before capacity limits.
static func compute_demand(config: SimConfig, club: ClubState, mult: Dictionary) -> Dictionary:
	var base: float = config.num("demand/base") * mult["form"] * mult["opponent"] * mult["mood"] * mult["noise"]
	var out := {}
	for id in config.stand_type_ids():
		var t := config.stand_type(id)
		var price_factor := pow(club.price(id) / t.reference_price, t.elasticity)
		out[id] = roundi(base * t.demand_share * price_factor)
	return out


## Each type's demand is shared across its stands by capacity and capped.
## Overflow is lost (no spill into other types).
static func compute_attendance(config: SimConfig, layout: Layout, demand: Dictionary) -> Array[Dictionary]:
	var cap_by_type := {}
	for s in layout.stands:
		var cap := s.capacity(config.stand_type(s.type_id))
		cap_by_type[s.type_id] = cap_by_type.get(s.type_id, 0) + cap
	var out: Array[Dictionary] = []
	for s in layout.stands:
		var cap := s.capacity(config.stand_type(s.type_id))
		var share := float(cap) / float(cap_by_type[s.type_id])
		var att: int = min(cap, roundi(demand.get(s.type_id, 0) * share))
		out.append({
			"label": s.label(), "type": s.type_id, "capacity": cap, "attendance": att,
			"fill": float(att) / float(cap) if cap > 0 else 0.0,
			"proximity": max(0.0, 1.0 - config.num("atmosphere/proximity_per_setback") * s.setback),
			"noise": config.stand_type(s.type_id).noise,
		})
	return out


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


static func result_probabilities(config: SimConfig, home_adv: float) -> Dictionary:
	var win := config.num("result/base_win") + home_adv
	var loss: float = max(0.0, config.num("result/base_loss") - home_adv)
	return { "win": win, "draw": 1.0 - win - loss, "loss": loss }


static func pick_result(p: Dictionary, roll: float) -> String:
	if roll < p["win"]:
		return "W"
	if roll < p["win"] + p["draw"]:
		return "D"
	return "L"


## Every stand section sends its share of fans to the nearest facility of each
## kind by walking distance. Each facility then runs QueueModel.
static func simulate_halftime(config: SimConfig, layout: Layout, stands: Array[Dictionary]) -> Dictionary:
	var window := config.num("halftime/window_minutes")
	var speed := config.num("halftime/walk_tiles_per_minute")
	var section_len := config.integer("layout/section_length")
	var stand_tiles := layout.stand_tile_map()

	var arrivals := []
	var walk_sum := []
	for f in layout.facilities:
		arrivals.append(0)
		walk_sum.append(0.0)
	var kinds := {}
	for kind in KINDS:
		kinds[kind] = { "wanting": 0, "served": 0, "lost": 0, "unreachable": 0 }

	for si in layout.stands.size():
		var att: int = stands[si]["attendance"]
		var sections := layout.stands[si].sections(layout.pitch, section_len)
		var assigned := 0
		for k in sections.size():
			var sec: Dictionary = sections[k]
			# Last section takes the rounding remainder so fans are conserved.
			var fans := att - assigned if k == sections.size() - 1 else roundi(att * sec["weight"])
			assigned += fans
			var dist := layout.walk_distances(sec["source"], stand_tiles)
			for kind in KINDS:
				var wanting := roundi(fans * config.num("halftime/share/" + kind))
				kinds[kind]["wanting"] += wanting
				var best := -1
				for fi in layout.facilities.size():
					var f := layout.facilities[fi]
					if config.facility_type(f.type_id).kind != kind or not dist.has(f.pos):
						continue
					if best == -1 or dist[f.pos] < dist[layout.facilities[best].pos]:
						best = fi
				if best == -1:
					kinds[kind]["unreachable"] += wanting
					kinds[kind]["lost"] += wanting
					continue
				arrivals[best] += wanting
				walk_sum[best] += wanting * 2.0 * dist[layout.facilities[best].pos] / speed

	var facilities: Array[Dictionary] = []
	for fi in layout.facilities.size():
		var f := layout.facilities[fi]
		var ft := config.facility_type(f.type_id)
		var round_trip: float = walk_sum[fi] / arrivals[fi] if arrivals[fi] > 0 else 0.0
		var q := QueueModel.simulate(arrivals[fi], ft.service_rate_per_min, window, round_trip)
		q["label"] = f.label()
		q["kind"] = ft.kind
		q["round_trip_min"] = round_trip
		q["revenue"] = q["served"] * ft.spend_per_customer
		q["lost_sales"] = q["lost"] * ft.spend_per_customer
		kinds[ft.kind]["served"] += q["served"]
		kinds[ft.kind]["lost"] += q["lost"]
		facilities.append(q)
	return { "facilities": facilities, "kinds": kinds }


static func compute_finances(config: SimConfig, layout: Layout, club: ClubState, r: MatchdayReport) -> void:
	var tickets := 0.0
	var premium := 0.0
	for s in r.stands:
		tickets += s["attendance"] * club.price(s["type"])
		premium += s["attendance"] * config.stand_type(s["type"]).hospitality_per_head
	var food := 0.0
	var lost := 0.0
	for f in r.facilities:
		food += f["revenue"]
		lost += f["lost_sales"]
	# Fans with no reachable food facility are lost sales too (priced at the
	# cheapest food spend so the number is visible but conservative).
	var unreachable_food: int = r.halftime["food"]["unreachable"]
	if unreachable_food > 0:
		var spend := INF
		for id in config.facility_types:
			var ft := config.facility_type(id)
			if ft.kind == "food":
				spend = min(spend, ft.spend_per_customer)
		if spend != INF:
			lost += unreachable_food * spend
	r.revenue = { "tickets": tickets, "food": food, "premium": premium, "total": tickets + food + premium }
	r.lost_food_sales = lost
	var upkeep := layout.upkeep(config)
	r.costs = { "stands": upkeep["stands"], "facilities": upkeep["facilities"],
		"total": upkeep["stands"] + upkeep["facilities"] }
	r.net = r.revenue["total"] - r.costs["total"]


static func compute_mood_change(config: SimConfig, r: MatchdayReport) -> Dictionary:
	var from_result := config.num("mood/win") if r.result == "W" else (
		config.num("mood/draw") if r.result == "D" else config.num("mood/loss"))
	var from_atmos := (r.atmosphere - config.num("mood/atmosphere_pivot")) * config.num("mood/atmosphere_scale")
	var wanting := 0
	var lost := 0
	for kind in r.halftime:
		wanting += r.halftime[kind]["wanting"]
		lost += r.halftime[kind]["lost"]
	var unserved_share := float(lost) / float(wanting) if wanting > 0 else 0.0
	var from_service := -config.num("mood/unserved_penalty") * unserved_share
	return { "result": from_result, "atmosphere": from_atmos, "service": from_service,
		"unserved_share": unserved_share, "total": from_result + from_atmos + from_service }
