extends AudioStreamPlayer
## Procedural crowd sound, no audio files: filtered noise for the crowd's
## murmur and roar, swells for goals, and rhythmic claps for chanting stands.
##   ambient(level)      - background murmur while building (0..1)
##   play_match(r)       - a matchday: roar scaled by atmosphere, one cheer per
##                         home goal spread over the sweep, chants if it's loud
##   stop_match()        - back to the ambient murmur

const RATE := 22050.0

var muted := false
var _playback: AudioStreamGeneratorPlayback
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _base := 0.04          # current crowd level (smoothed toward _target)
var _target := 0.04
var _ambient := 0.04
var _brown := 0.0
var _pink := [0.0, 0.0, 0.0]
var _cheers: Array = []    # [start_time, length, strength]
var _chant := 0.0          # 0..1 clap chant strength
var _clap_env := 0.0
var _next_clap := 0.0
var _clap_step := 0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.25
	stream = gen
	volume_db = -6.0
	play()
	_playback = get_stream_playback()


func ambient(level: float) -> void:
	_ambient = clampf(level, 0.0, 1.0) * 0.12
	_target = _ambient
	_chant = 0.0
	_cheers.clear()


## r: a MatchdayReport.
func play_match(r: MatchdayReport, sweep_seconds := 7.0) -> void:
	var a := r.atmosphere / 100.0
	var size := clampf(r.attendance / 20000.0, 0.15, 1.0)
	_target = 0.12 + 0.55 * a * sqrt(size)
	_chant = a if a > 0.35 else 0.0
	_cheers.clear()
	for g in r.home_goals:
		var at := _t + 0.6 + (g + 0.5) * (sweep_seconds - 1.0) / maxf(1.0, r.home_goals)
		_cheers.append([at, 2.6, 0.6 + 0.6 * a])
	if r.away_goals > 0:
		# a groan for the away goals: a short dip
		_cheers.append([_t + sweep_seconds * 0.5, 1.4, -0.5])


func stop_match() -> void:
	ambient(_ambient / 0.12)


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	for i in frames:
		var s := 0.0 if muted else _sample()
		_playback.push_frame(Vector2(s, s * 0.97))
		_t += 1.0 / RATE


func _sample() -> float:
	_base = lerpf(_base, _target, 0.00004)
	var white := _rng.randf_range(-1.0, 1.0)
	# brown noise: low rumble of a big crowd
	_brown = clampf(_brown + white * 0.02, -1.0, 1.0) * 0.999
	# a cheap pink-ish noise: voices
	_pink[0] = 0.997 * _pink[0] + white * 0.029
	_pink[1] = 0.985 * _pink[1] + white * 0.032
	_pink[2] = 0.950 * _pink[2] + white * 0.048
	var voices: float = _pink[0] + _pink[1] + _pink[2]
	# slow swells so it breathes
	var swell := 0.85 + 0.15 * sin(_t * 0.9) * sin(_t * 0.37)
	var level := _base * swell
	for c in _cheers:
		var dt: float = _t - c[0]
		if dt > 0.0 and dt < c[1]:
			var env := sin(PI * dt / c[1])
			level += c[2] * env * env
	level = maxf(level, 0.0)
	var out := (voices * 0.9 + _brown * 0.6) * level
	# clap-clap-clap chant on the terraces: three claps then a rest
	if _chant > 0.0:
		if _t >= _next_clap:
			_clap_env = 1.0
			_clap_step = (_clap_step + 1) % 4
			_next_clap = _t + (0.28 if _clap_step != 0 else 0.56)
		if _clap_step != 0:
			out += white * _clap_env * _chant * 0.5
		_clap_env *= 0.9985
	return clampf(out, -1.0, 1.0)
