class_name League
extends RefCounted
## One season of one division: the teams, a double round-robin fixture list,
## every result, and the table. Team 0 is always the player's club.
## Other teams have a fixed strength rating for the season (from the
## division's typical squad spend plus a random spread); the player's rating
## comes from their squad budget (see rating_for_wage).

var division: int = 0
var teams: Array[Dictionary] = []          # { name, rating }
var rounds: Array = []                     # round -> [[home, away], ...]
var results: Array = []                    # round -> [[home, away, home_goals, away_goals], ...]


## Strength rating for a squad spend per match: ln(wage / 1000).
## Doubling the spend adds about 0.69.
static func rating_for_wage(wage: float) -> float:
	return log(maxf(wage, 500.0) / 1000.0)


static func create(config: SimConfig, seed: int, p_division: int, club_name: String) -> League:
	var l := League.new()
	l.division = p_division
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := config.integer("league/teams")
	var pool := config.opponents.duplicate()
	var base := rating_for_wage(float(config.division(p_division)["squad_wage"]))
	var spread := config.num("league/rating_spread")
	l.teams.append({ "name": club_name, "rating": 0.0 })
	for i in n - 1:
		var name := "Team %d" % (i + 2)
		if not pool.is_empty():
			name = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		# evenly spread from weakest to strongest, plus a little noise
		var t := (float(i) / maxf(1.0, n - 2) - 0.5) * 2.0
		l.teams.append({ "name": name, "rating": base + t * spread + rng.randfn(0.0, spread * 0.25) })
	l._make_rounds(rng)
	return l


## Circle-method round robin, then the same again with home and away swapped.
func _make_rounds(rng: RandomNumberGenerator) -> void:
	var n := teams.size()
	var idx: Array = range(n)
	# shuffle who meets whom when, but keep team 0 in the fixed slot
	var rest: Array = idx.slice(1)
	for i in range(rest.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = rest[i]
		rest[i] = rest[j]
		rest[j] = tmp
	idx = [0] + rest
	var first: Array = []
	for r in n - 1:
		var games := []
		for k in n / 2:
			var a: int = idx[k]
			var b: int = idx[n - 1 - k]
			# alternate home and away so nobody gets long runs at home
			games.append([a, b] if (r + k) % 2 == 0 else [b, a])
		first.append(games)
		# rotate all but the first slot
		var last = idx.pop_back()
		idx.insert(1, last)
	rounds = first.duplicate(true)
	for games in first:
		var back := []
		for g in games:
			back.append([g[1], g[0]])
		rounds.append(back)


func round_count() -> int:
	return rounds.size()


## The player's game in a round: { home: bool, opponent: int }.
func our_game(round: int) -> Dictionary:
	for g in rounds[round]:
		if g[0] == 0:
			return { "home": true, "opponent": g[1] }
		if g[1] == 0:
			return { "home": false, "opponent": g[0] }
	return {}


## Expected goals for a side with rating `att` against `def`.
static func expected_goals(config: SimConfig, att: float, def: float, home: bool) -> float:
	var base := config.num("result/goals_home") if home else config.num("result/goals_away")
	return base * exp(config.num("result/strength_k") * (att - def))


static func poisson(rng: RandomNumberGenerator, mean: float) -> int:
	var l := exp(-mean)
	var k := 0
	var p := 1.0
	while true:
		p *= rng.randf()
		if p <= l or k > 9:
			break
		k += 1
	return k


## Records a round: the player's score is given, the rest are simulated.
func play_round(config: SimConfig, round: int, our_goals: int, their_goals: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var noise := config.num("result/form_noise")
	var out := []
	for g in rounds[round]:
		var h: int = g[0]
		var a: int = g[1]
		if h == 0:
			out.append([h, a, our_goals, their_goals])
		elif a == 0:
			out.append([h, a, their_goals, our_goals])
		else:
			var rh: float = float(teams[h]["rating"]) + rng.randfn(0.0, noise)
			var ra: float = float(teams[a]["rating"]) + rng.randfn(0.0, noise)
			out.append([h, a, poisson(rng, expected_goals(config, rh, ra, true)), poisson(rng, expected_goals(config, ra, rh, false))])
	while results.size() <= round:
		results.append([])
	results[round] = out


func played() -> int:
	var n := 0
	for r in results:
		if not (r as Array).is_empty():
			n += 1
	return n


## The table, sorted: points, goal difference, goals scored, name.
func table() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for i in teams.size():
		rows.append({ "team": i, "name": teams[i]["name"], "p": 0, "w": 0, "d": 0, "l": 0, "gf": 0, "ga": 0, "pts": 0, "form": [] })
	for r in results:
		for g in r:
			var h: Dictionary = rows[int(g[0])]
			var a: Dictionary = rows[int(g[1])]
			var hg: int = g[2]
			var ag: int = g[3]
			for side in [[h, hg, ag], [a, ag, hg]]:
				var row: Dictionary = side[0]
				var f: int = side[1]
				var c: int = side[2]
				row["p"] += 1
				row["gf"] += f
				row["ga"] += c
				if f > c:
					row["w"] += 1
					row["pts"] += 3
					row["form"].append("W")
				elif f == c:
					row["d"] += 1
					row["pts"] += 1
					row["form"].append("D")
				else:
					row["l"] += 1
					row["form"].append("L")
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["pts"] != y["pts"]:
			return x["pts"] > y["pts"]
		var gx: int = x["gf"] - x["ga"]
		var gy: int = y["gf"] - y["ga"]
		if gx != gy:
			return gx > gy
		if x["gf"] != y["gf"]:
			return x["gf"] > y["gf"]
		return String(x["name"]) < String(y["name"]))
	return rows


## 1-based league position of a team.
func position(team := 0) -> int:
	var t := table()
	for i in t.size():
		if t[i]["team"] == team:
			return i + 1
	return t.size()


## Where the player's squad budget would rank (1 = strongest).
func strength_rank(our_rating: float) -> int:
	var rank := 1
	for i in range(1, teams.size()):
		if float(teams[i]["rating"]) > our_rating:
			rank += 1
	return rank


func to_dict() -> Dictionary:
	return { "division": division, "teams": teams, "rounds": rounds, "results": results }


static func from_dict(d: Dictionary) -> League:
	var l := League.new()
	l.division = int(d.get("division", 0))
	for t in d.get("teams", []):
		l.teams.append({ "name": String(t["name"]), "rating": float(t["rating"]) })
	for r in d.get("rounds", []):
		var games := []
		for g in r:
			games.append([int(g[0]), int(g[1])])
		l.rounds.append(games)
	for r in d.get("results", []):
		var games := []
		for g in r:
			games.append([int(g[0]), int(g[1]), int(g[2]), int(g[3])])
		l.results.append(games)
	return l
