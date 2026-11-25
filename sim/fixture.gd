class_name Fixture
extends RefCounted
## One home match. "Big" matches multiply demand.

var opponent: String = "Opponent"
var big: bool = false
var evening: bool = false   # kick-off under the floodlights
var weather: String = "clear"  # clear / rain / snow


static func make(p_opponent: String, p_big := false) -> Fixture:
	var f := Fixture.new()
	f.opponent = p_opponent
	f.big = p_big
	return f
