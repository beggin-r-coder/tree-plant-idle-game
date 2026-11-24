class_name IntroSynth
extends AudioStreamPlayer
## Procedural soundtrack for the intro, generated sample by sample (no audio files).
## The Intro timeline tweens these "mixer" values:
##   pad      : soft chord, `dark` morphs it from a warm major chord to a low, uneasy one
##   hum      : industrial drone (factories / traffic)
##   wind     : filtered noise
##   rumble   : deep earthquake rumble
##   rain     : rain hiss
##   heart    : heartbeat volume, `heart_bpm` its speed
## and calls chirp(), thunder(), chime() for one-shot sounds.

const RATE := 22050.0

var master := 0.0
var pad := 0.0
var dark := 0.0
var hum := 0.0
var wind := 0.0
var rumble := 0.0
var rain := 0.0
var heart := 0.0
var heart_bpm := 60.0
var birds := 0.0          ## chance of random bird chirps (lush opening)

var _pb: AudioStreamGeneratorPlayback
var _ph: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _hum_ph := 0.0
var _lp_wind := 0.0
var _lp_rain := 0.0
var _brown := 0.0
var _beat_t := 0.0
var _chirp_t := -1.0
var _chirps_left := 0
var _chirp_f := 3000.0
var _chirp_ph := 0.0
var _thunder := 0.0
var _chime_t := -1.0
var _chime_ph: Array[float] = [0.0, 0.0, 0.0]
var _time := 0.0
var _rng := RandomNumberGenerator.new()

const HAPPY := [261.63, 329.63, 392.0, 523.25, 130.81]   # C major + octave + bass
const SAD := [233.08, 277.18, 349.23, 415.30, 69.30]     # dark, low Db-ish cluster


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.25
	stream = gen
	play()
	_pb = get_stream_playback() as AudioStreamGeneratorPlayback


func chirp() -> void:
	_chirp_t = 0.0
	_chirps_left = _rng.randi_range(1, 2)
	_chirp_f = _rng.randf_range(2600.0, 3600.0)


func thunder() -> void:
	_thunder = 1.0


func chime() -> void:
	_chime_t = 0.0


func _process(_delta: float) -> void:
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	for i in n:
		var s := _sample()
		_pb.push_frame(Vector2(s, s))


func _sample() -> float:
	var dt := 1.0 / RATE
	_time += dt
	var white := _rng.randf() * 2.0 - 1.0
	_brown = clampf(_brown * 0.995 + white * 0.03, -1.0, 1.0)
	var out := 0.0

	# Pad: 5 voices gliding between the happy and the dark chord.
	if pad > 0.001:
		var p := 0.0
		for v in 5:
			var f := lerpf(HAPPY[v], SAD[v], dark) * 0.5
			_ph[v] = fmod(_ph[v] + f * dt, 1.0)
			var tone := sin(_ph[v] * TAU) + 0.25 * sin(_ph[v] * TAU * 2.0)
			p += tone * (0.6 if v == 4 else 0.25)
		p *= 0.75 + 0.25 * sin(_time * 0.7)
		out += p * pad * 0.22

	# Industrial hum
	if hum > 0.001:
		_hum_ph = fmod(_hum_ph + 55.0 * dt, 1.0)
		var h := sin(_hum_ph * TAU) * 0.6 + sin(_hum_ph * TAU * 2.0) * 0.3 + sin(_hum_ph * TAU * 3.0) * 0.2
		out += (h + white * 0.08) * hum * 0.25

	# Wind (slowly gusting low-passed noise)
	if wind > 0.001:
		var cutoff := 0.02 + 0.03 * (0.5 + 0.5 * sin(_time * 0.6))
		_lp_wind += (white - _lp_wind) * cutoff
		out += _lp_wind * wind * 1.4

	# Earthquake rumble
	if rumble > 0.001:
		out += _brown * rumble * 1.6

	# Rain hiss (high-passed noise)
	if rain > 0.001:
		_lp_rain += (white - _lp_rain) * 0.3
		out += (white - _lp_rain) * rain * 0.35

	# Heartbeat: "lub-dub"
	if heart > 0.001:
		_beat_t += dt
		var period := 60.0 / heart_bpm
		if _beat_t >= period:
			_beat_t -= period
		var b := 0.0
		for offset in [0.0, 0.22]:
			var t: float = _beat_t - offset
			if t >= 0.0 and t < 0.25:
				b += sin(TAU * 55.0 * t) * exp(-t * 22.0) * (1.0 if offset == 0.0 else 0.7)
		out += b * heart * 0.9

	# Bird chirps: little bursts of 2-3 quick chirps.
	# _chirp_t: >= 0 chirping, between -1 and 0 short gap, <= -1 idle.
	if birds > 0.0 and _chirp_t <= -1.0 and _rng.randf() < birds * dt * 1.5:
		chirp()
	if _chirp_t >= 0.0:
		_chirp_t += dt
		var env := sin(clampf(_chirp_t / 0.09, 0.0, 1.0) * PI)
		_chirp_ph = fmod(_chirp_ph + (_chirp_f + 900.0 * sin(_chirp_t * 90.0)) * dt, 1.0)
		out += sin(_chirp_ph * TAU) * env * 0.06
		if _chirp_t > 0.09:
			if _chirps_left > 0:
				_chirps_left -= 1
				_chirp_t = -0.05
			else:
				_chirp_t = -1.0
	elif _chirp_t > -1.0:
		_chirp_t = minf(_chirp_t + dt, 0.0)

	# Thunder: crack + long rumble
	if _thunder > 0.001:
		out += (_brown * 1.8 + white * maxf(_thunder - 0.85, 0.0) * 3.0) * _thunder
		_thunder *= 1.0 - dt * 0.9

	# Hopeful chime (bell partials)
	if _chime_t >= 0.0:
		_chime_t += dt
		var freqs := [523.25, 659.25, 783.99]
		var c := 0.0
		for k in 3:
			var start := k * 0.35
			var t: float = _chime_t - start
			if t > 0.0:
				_chime_ph[k] = fmod(_chime_ph[k] + freqs[k] * dt, 1.0)
				c += (sin(_chime_ph[k] * TAU) + 0.3 * sin(_chime_ph[k] * TAU * 2.76)) * exp(-t * 1.6)
		out += c * 0.12
		if _chime_t > 4.5:
			_chime_t = -1.0

	out *= master * 1.8
	return out / (1.0 + absf(out))   # soft clip
