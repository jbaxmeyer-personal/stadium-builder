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


static func make(p_opponent: String, p_big := false) -> Fixture:
	var f := Fixture.new()
	f.opponent = p_opponent
	f.big = p_big
	return f
