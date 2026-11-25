class_name GameAudio
extends Node
## In-game sound: short effects and an ambient bed that follows the ecosystem.
## Every sound is synthesized ONCE at startup into an AudioStreamWAV (no audio
## files, and no per-sample work while playing, so it is cheap on phones).
##
##   play("pop", pitch)  tap        play("grow")     tree finished
##   play("coin")        coins in   play("buy")      purchase
##   play("unlock")      new plant  play("fanfare")  milestone
##   play("nope")        can't afford               play("bonus") golden butterfly
## Ambient: wind (loudest on barren land), river (once it flows), birdsong (more
## birds as the ecosystem grows).

const RATE := 22050
const VOICES := 10

var _sfx := {}                       ## name -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _wind: AudioStreamPlayer
var _river: AudioStreamPlayer
var _chirps: Array[AudioStreamWAV] = []
var _bird_timer := 2.0
var _rng := RandomNumberGenerator.new()
var _last_play := {}                 ## name -> time, for throttling
var _task := -1


func _ready() -> void:
	_rng.seed = 11
	for k in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_wind = AudioStreamPlayer.new()
	_river = AudioStreamPlayer.new()
	add_child(_wind)
	add_child(_river)
	# A limiter on the master bus keeps stacked sounds (many trees at once) from clipping.
	if AudioServer.get_bus_effect_count(0) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		AudioServer.add_bus_effect(0, lim)
	_apply_mute()
	# Synthesize on a worker thread so the first frame isn't delayed (~0.25 s on desktop, more on phones).
	_task = WorkerThreadPool.add_task(_render_all)


func _render_all() -> void:
	var sfx := {}
	sfx["pop"] = _render(0.12, _pop)
	sfx["grow"] = _render(0.55, _grow)
	sfx["coin"] = _render(0.35, _coin)
	sfx["buy"] = _render(0.3, _buy)
	sfx["nope"] = _render(0.22, _nope)
	sfx["unlock"] = _render(0.9, _arpeggio.bind([523.25, 659.25, 783.99, 1046.5], 0.09))
	sfx["fanfare"] = _render(1.8, _arpeggio.bind([392.0, 523.25, 659.25, 783.99, 1046.5, 1318.5], 0.12))
	sfx["bonus"] = _render(1.0, _sparkle)
	var chirps: Array[AudioStreamWAV] = []
	for k in 4:
		chirps.append(_render(0.35, _chirp.bind(2400.0 + k * 350.0, 2 + k % 2)))
	var wind := _render_loop(4.0, _wind_sample)
	var river := _render_loop(3.0, _river_sample)
	_finish_render.call_deferred(sfx, chirps, wind, river)


func _finish_render(sfx: Dictionary, chirps: Array[AudioStreamWAV], wind: AudioStreamWAV, river: AudioStreamWAV) -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_sfx = sfx
	_chirps = chirps
	_wind.stream = wind
	_wind.volume_db = -14.0
	_wind.play()
	_river.stream = river
	_river.volume_db = -80.0
	_river.play()


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


# ------------------------------------------------------------------ public

func play(sfx: String, pitch: float = 1.0, volume_db: float = 0.0, min_gap: float = 0.0) -> void:
	if not GameState.sound_on or not _sfx.has(sfx):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if min_gap > 0.0 and now - float(_last_play.get(sfx, -10.0)) < min_gap:
		return
	_last_play[sfx] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _sfx[sfx]
	p.pitch_scale = pitch
	p.volume_db = volume_db - 3.0
	p.play()


func set_sound_on(on: bool) -> void:
	GameState.sound_on = on
	GameState.save_game()
	_apply_mute()


func _apply_mute() -> void:
	AudioServer.set_bus_mute(0, not GameState.sound_on)


func _process(delta: float) -> void:
	# Ambient follows the ecosystem: barren land is windy and silent, a healthy
	# forest has a flowing river and lots of birds.
	var stage := GameState.stage
	var wind_db := lerpf(-12.0, -26.0, clampf(stage / 6.0, 0.0, 1.0))
	_wind.volume_db = lerpf(_wind.volume_db, wind_db, clampf(delta, 0.0, 1.0))
	var river_db := -20.0 if stage >= 2 else -80.0
	_river.volume_db = lerpf(_river.volume_db, river_db, clampf(delta * 0.5, 0.0, 1.0))
	if stage >= 1 and GameState.sound_on and not _chirps.is_empty():
		_bird_timer -= delta
		if _bird_timer <= 0.0:
			# More birds as nature comes back.
			_bird_timer = _rng.randf_range(4.0, 9.0) / (1.0 + stage * 0.5)
			var p := _players[_next]
			_next = (_next + 1) % _players.size()
			p.stream = _chirps[_rng.randi() % _chirps.size()]
			p.pitch_scale = _rng.randf_range(0.85, 1.2)
			p.volume_db = _rng.randf_range(-20.0, -13.0)
			p.play()


# ------------------------------------------------------------------ rendering helpers

func _render(seconds: float, fn: Callable) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v: float = fn.call(t, seconds)
		v = v / (1.0 + absf(v))
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w


## Renders a seamless loop by cross-fading the tail into the head.
func _render_loop(seconds: float, fn: Callable) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var fade := int(0.5 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n + fade)
	for i in n + fade:
		buf[i] = fn.call(float(i) / RATE)
	for i in fade:
		var a := float(i) / fade
		buf[i] = buf[i] * a + buf[n + i] * (1.0 - a)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


static func _env(t: float, attack: float, decay: float) -> float:
	if t < attack:
		return t / attack
	return exp(-(t - attack) * decay)


# ------------------------------------------------------------------ sound recipes (t = seconds)

func _pop(t: float, _len: float) -> float:
	# Soft "bloop": a sine dropping quickly in pitch.
	var f := 520.0 * exp(-t * 18.0) + 180.0
	return sin(TAU * f * t) * _env(t, 0.004, 30.0) * 0.9


func _grow(t: float, _len: float) -> float:
	# Rising shimmer: two detuned sines sweeping up, plus a little sparkle.
	var f := 500.0 + 900.0 * t
	var v := sin(TAU * f * t) + 0.5 * sin(TAU * f * 1.5 * t)
	v += 0.3 * sin(TAU * 2400.0 * t) * (0.5 + 0.5 * sin(t * 70.0))
	return v * _env(t, 0.03, 6.0) * 0.45


func _coin(t: float, _len: float) -> float:
	# Classic two-note coin "ding".
	var f := 988.0 if t < 0.07 else 1319.0
	var tt := t if t < 0.07 else t - 0.07
	return (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * _env(tt, 0.003, 9.0) * 0.5


func _buy(t: float, _len: float) -> float:
	var click := (_rng.randf() * 2.0 - 1.0) * exp(-t * 300.0) * 0.6
	var tone := sin(TAU * 660.0 * t) * _env(t, 0.005, 14.0) + sin(TAU * 990.0 * t) * _env(maxf(t - 0.06, 0.0), 0.005, 12.0) * float(t > 0.06)
	return click + tone * 0.5


func _arpeggio(t: float, _len: float, notes: Array, step: float) -> float:
	var v := 0.0
	for k in notes.size():
		var start: float = k * step
		if t >= start:
			var tt := t - start
			var f: float = notes[k]
			v += (sin(TAU * f * tt) + 0.35 * sin(TAU * f * 2.0 * tt) + 0.15 * sin(TAU * f * 3.0 * tt)) * _env(tt, 0.005, 3.2)
	return v * 0.28


func _nope(t: float, _len: float) -> float:
	var f := 220.0 if t < 0.1 else 175.0
	return sin(TAU * f * t) * _env(fmod(t, 0.1), 0.005, 16.0) * 0.5


func _sparkle(t: float, _len: float) -> float:
	var v := 0.0
	for k in 6:
		var start := k * 0.07
		if t >= start:
			var tt := t - start
			var f := 1200.0 + k * 260.0
			v += sin(TAU * f * tt) * _env(tt, 0.002, 7.0)
	return v * 0.22


func _chirp(t: float, _len: float, base: float, count: int) -> float:
	var v := 0.0
	for k in count:
		var start := k * 0.11
		var tt := t - start
		if tt >= 0.0 and tt < 0.09:
			var f := base + 900.0 * sin(tt * 60.0)
			v += sin(TAU * f * tt) * sin(tt / 0.09 * PI)
	return v * 0.35


var _wind_lp := 0.0
var _wind_lp2 := 0.0
func _wind_sample(t: float) -> float:
	var white := _rng.randf() * 2.0 - 1.0
	var cutoff := 0.015 + 0.02 * (0.5 + 0.5 * sin(t * TAU / 4.0))   # one gust per loop
	_wind_lp += (white - _wind_lp) * cutoff
	_wind_lp2 += (_wind_lp - _wind_lp2) * cutoff
	return _wind_lp2 * 9.0


var _river_lp := 0.0
func _river_sample(t: float) -> float:
	var white := _rng.randf() * 2.0 - 1.0
	_river_lp += (white - _river_lp) * 0.25
	var bubbles := sin(TAU * (600.0 + 300.0 * sin(t * 7.0)) * t) * maxf(sin(t * 23.0), 0.0) * 0.08
	return (white - _river_lp) * 0.25 + _river_lp * 0.6 + bubbles
