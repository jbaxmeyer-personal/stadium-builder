class_name Fixture
extends RefCounted
## One of the club's league matches, at home or away. "Big" matches multiply demand.

var opponent: String = "Opponent"
var big: bool = false
var evening: bool = false   # kick-off under the floodlights
var weather: String = "clear"  # clear / rain / snow
var home: bool = true
var round: int = 0            # league round (0-based)
var opponent_team: int = 1     # index into League.teams
var opponent_rating: float = 0.0
var competition: String = "league"   # league / cup / continental
var comp_name: String = ""            # "National Cup", "Champions Cup", ...
var stage: String = ""                # "Third round", "Group 3", "Final", ...
var knockout: bool = false            # a draw goes to penalties
var neutral: bool = false             # finals: nobody's ground
var prize_win: float = 0.0
var prize_draw: float = 0.0
var tv: float = -1.0                  # TV money for this match (-1 = the division's)
var seed: int = 0                     # cup / continental matches carry their own seed


func is_league() -> bool:
	return competition == "league"


func to_dict() -> Dictionary:
	return { "opponent": opponent, "big": big, "evening": evening, "weather": weather, "home": home, "round": round,
		"opponent_team": opponent_team, "opponent_rating": opponent_rating, "competition": competition, "comp_name": comp_name,
		"stage": stage, "knockout": knockout, "neutral": neutral, "prize_win": prize_win, "prize_draw": prize_draw, "tv": tv, "seed": str(seed) }


static func from_dict(f: Dictionary) -> Fixture:
	var fx := Fixture.make(f["opponent"], bool(f["big"]))
	fx.evening = bool(f.get("evening", false))
	fx.weather = f.get("weather", "clear")
	fx.home = bool(f.get("home", true))
	fx.round = int(f.get("round", 0))
	fx.opponent_team = int(f.get("opponent_team", 1))
	fx.opponent_rating = float(f.get("opponent_rating", 0.0))
	fx.competition = f.get("competition", "league")
	fx.comp_name = f.get("comp_name", "")
	fx.stage = f.get("stage", "")
	fx.knockout = bool(f.get("knockout", false))
	fx.neutral = bool(f.get("neutral", false))
	fx.prize_win = float(f.get("prize_win", 0.0))
	fx.prize_draw = float(f.get("prize_draw", 0.0))
	fx.tv = float(f.get("tv", -1.0))
	fx.seed = int(String(f.get("seed", "0")))
	return fx


static func make(p_opponent: String, p_big := false) -> Fixture:
	var f := Fixture.new()
	f.opponent = p_opponent
	f.big = p_big
	return f
