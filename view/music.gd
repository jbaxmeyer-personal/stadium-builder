class_name Music
extends Node
## Quiet background music for building, made in code (no sound files): a slow
## loop of soft pad chords, a plucked arpeggio and a little bass. Built once in
## a thread so the game doesn't wait for it; fades out on matchdays, when the
## crowd takes over.

const RATE := 22050
const BPM := 76.0
# chords as semitones above A2 (110 Hz): Cmaj7, Am7, Fmaj7, G6 (twice, the second time an octave of air on top)
const CHORDS := [[3, 7, 10, 14], [0, 3, 7, 10], [-4, 0, 3, 7], [-2, 2, 5, 9]]

var muted := false:
	set(v):
		muted = v
		_target = -80.0 if (muted or _ducked) else VOLUME_DB
var _player: AudioStreamPlayer
var _thread: Thread
var _ducked := false
var _target := -80.0
const VOLUME_DB := -17.0


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = -80.0
	add_child(_player)
	_target = -80.0 if muted else VOLUME_DB
	if DisplayServer.get_name() == "headless":
		return
	_thread = Thread.new()
	_thread.start(_compose)


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


## Quieter while the matchday plays out (the crowd is the music then).
func duck(on: bool) -> void:
	_ducked = on
	_target = -80.0 if (muted or _ducked) else VOLUME_DB


func _process(delta: float) -> void:
	if _player.stream == null:
		return
	_player.volume_db = move_toward(_player.volume_db, _target, delta * 12.0)


func _compose() -> void:
	var beat := 60.0 / BPM
	var bar := beat * 4.0
	var bars := CHORDS.size() * 2
	var n := int(bars * bar * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for b in bars:
		var chord: Array = CHORDS[b % CHORDS.size()]
		var t0 := b * bar
		# pad: detuned sines with a slow swell, overlapping into the next bar
		for semi in chord:
			var f := 110.0 * pow(2.0, float(semi) / 12.0)
			for det in [0.997, 1.003]:
				_add(buf, t0, bar * 1.25, func(t: float) -> float:
					var env := minf(1.0, t / 1.2) * minf(1.0, (bar * 1.25 - t) / 1.0)
					return sin(TAU * f * det * t) * env * 0.045)
		# bass on the root
		var root := 55.0 * pow(2.0, float(chord[0]) / 12.0)
		_add(buf, t0, bar, func(t: float) -> float:
			return sin(TAU * root * t) * exp(-t * 0.8) * 0.12)
		# plucked arpeggio, eighth notes, a few left out
		for k in 8:
			if rng.randf() < 0.25:
				continue
			var semi: int = int(chord[(k * 3 + b) % chord.size()]) + (12 if b >= CHORDS.size() and k % 2 == 1 else 12 * (k / 4))
			var f := 220.0 * pow(2.0, float(semi) / 12.0)
			_add(buf, t0 + k * beat / 2.0, 1.6, func(t: float) -> float:
				return (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * exp(-t * 3.2) * 0.07)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	_start.call_deferred(w)


## Adds a voice into the loop (wrapping round the end so it loops cleanly).
func _add(buf: PackedFloat32Array, start: float, length: float, f: Callable) -> void:
	var n := buf.size()
	var i0 := int(start * RATE)
	var m := int(length * RATE)
	for i in m:
		var idx := (i0 + i) % n
		buf[idx] += float(f.call(float(i) / RATE))


func _start(w: AudioStreamWAV) -> void:
	_player.stream = w
	_player.play()
