class_name Sfx
extends Node
## Little interface sounds, made in code (no sound files): a soft thud when
## something is built, a crunch for demolition, a chime for money, a buzz for
## "can't do that". Each is a short PCM clip generated once.

const RATE := 22050
var _clips := {}
var _players: Array[AudioStreamPlayer] = []
var muted := false


func _ready() -> void:
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_players.append(p)
	_clips["build"] = _make(func(t: float) -> float:
		return sin(TAU * (120.0 - 60.0 * t * 4.0) * t) * exp(-t * 18.0) * 0.9 + sin(TAU * 900.0 * t) * exp(-t * 60.0) * 0.25, 0.25)
	_clips["demolish"] = _make(func(t: float) -> float:
		return randf_range(-1.0, 1.0) * exp(-t * 7.0) * 0.6 + sin(TAU * 70.0 * t) * exp(-t * 9.0) * 0.5, 0.45)
	_clips["cash"] = _make(func(t: float) -> float:
		var f := 1320.0 if t < 0.09 else 1760.0
		return sin(TAU * f * t) * exp(-fmod(t, 0.09) * 14.0) * 0.45, 0.3)
	_clips["error"] = _make(func(t: float) -> float:
		return signf(sin(TAU * 150.0 * t)) * 0.25 * (1.0 - t / 0.18), 0.18)
	_clips["click"] = _make(func(t: float) -> float:
		return sin(TAU * 2200.0 * t) * exp(-t * 120.0) * 0.4, 0.05)


func _make(f: Callable, seconds: float) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := clampf(float(f.call(float(i) / RATE)), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w


func play(kind: String) -> void:
	if muted or not _clips.has(kind):
		return
	for p in _players:
		if not p.playing:
			p.stream = _clips[kind]
			p.play()
			return
	_players[0].stream = _clips[kind]
	_players[0].play()
