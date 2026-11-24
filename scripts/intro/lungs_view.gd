class_name LungsView
extends Control
## Stylised, child-friendly lungs that breathe. As `health` drops from 1 to 0
## they turn from pink to grey, dark smog spots appear, breathing gets shallow
## and shaky, and grey smog particles are pulled in through the windpipe.

var health := 1.0
var cough := 0.0          ## set to 1 to trigger a short shake
var _t := 0.0
var _phase := 0.0
var _spots: Array[Vector3] = []   ## x, y in lobe space, radius
var _motes: Array[Vector2] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 22:
		_spots.append(Vector3(rng.randf_range(0.25, 0.85), rng.randf_range(-0.6, 0.9), rng.randf_range(0.05, 0.12)))
	for k in 14:
		_motes.append(Vector2(rng.randf_range(-1, 1), rng.randf()))


func _process(delta: float) -> void:
	_t += delta
	# Breathing slows and gets shallower as the air gets worse.
	var rate := lerpf(0.55, 1.0, health)
	_phase += delta * TAU * 0.28 * rate
	cough = maxf(cough - delta * 1.8, 0.0)
	queue_redraw()


func _lobe_points(center: Vector2, scale_px: float, side: float, breath: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 40:
		var a := TAU * k / 40.0
		var x := cos(a)
		var y := sin(a)
		# Flatter inner edge, rounder outer edge, wider at the bottom.
		var w := 0.62 if x * side < 0.0 else 0.9
		w *= 1.0 + 0.22 * maxf(y, 0.0)
		var py := y * 1.25 + (0.2 * (1.0 - absf(x)) if y < -0.6 else 0.0)
		pts.append(center + Vector2(x * w * side * side, py) * scale_px * breath)
	return pts


func _draw() -> void:
	var c := size * 0.5
	var unit := minf(size.x, size.y) * 0.18
	var shake := Vector2(sin(_t * 70.0), cos(_t * 63.0)) * cough * 10.0
	var jitter := Vector2(sin(_t * 23.0), 0) * (1.0 - health) * 1.5
	c += shake + jitter
	var amp := lerpf(0.015, 0.075, health)
	var breath := 1.0 + sin(_phase) * amp + sin(_t * 9.0) * 0.006 * (1.0 - health)
	var pink := Color(0.96, 0.55, 0.6)
	var sick := Color(0.42, 0.36, 0.35)
	var fill := pink.lerp(sick, 1.0 - health)
	var outline := fill.darkened(0.35)
	# Soft glow behind
	draw_circle(c, unit * 2.6, Color(fill.r, fill.g, fill.b, 0.08))
	# Windpipe + bronchi
	var pipe := Color(0.92, 0.8, 0.78).lerp(Color(0.55, 0.5, 0.48), 1.0 - health)
	draw_line(c + Vector2(0, -unit * 2.3), c + Vector2(0, -unit * 0.4), pipe, unit * 0.28, true)
	for k in 5:
		var y := -unit * 2.1 + k * unit * 0.36
		draw_line(c + Vector2(-unit * 0.14, y), c + Vector2(unit * 0.14, y), pipe.darkened(0.15), 2.0, true)
	for side in [-1.0, 1.0]:
		var lc := c + Vector2(side * unit * 1.05, unit * 0.45)
		var pts := _lobe_points(lc, unit, side, breath)
		draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		draw_polyline(pts, outline, 3.0, true)
		# bronchial tree
		var root := c + Vector2(side * unit * 0.12, -unit * 0.35)
		var mid := lc + Vector2(-side * unit * 0.25, -unit * 0.4)
		draw_line(root, mid, pipe.darkened(0.1), unit * 0.12, true)
		for br in 3:
			var end := mid + Vector2(side * unit * (0.25 + br * 0.2), unit * (-0.1 + br * 0.45)) * breath
			draw_line(mid, end, pipe.darkened(0.2), unit * 0.05, true)
		# smog spots
		for sp in _spots:
			var vis := clampf((1.0 - health) * 1.6 - sp.z * 3.0, 0.0, 1.0)
			if vis <= 0.0:
				continue
			var spot_pos := lc + Vector2(sp.x * side * 0.75 - side * 0.05, sp.y * 0.95) * unit * breath
			draw_circle(spot_pos, sp.z * unit * (0.8 + vis * 0.5), Color(0.15, 0.13, 0.12, 0.65 * vis))
	# Smog being breathed in (only while inhaling, once the air is dirty)
	var inhaling := cos(_phase) > 0.0
	if health < 0.85 and inhaling:
		for m in _motes:
			var t := fmod(m.y + _t * 0.5, 1.0)
			var p := c + Vector2(m.x * unit * 0.1, -unit * 3.0 + t * unit * 2.6)
			draw_circle(p, unit * 0.05, Color(0.3, 0.28, 0.26, 0.7 * (1.0 - health)))
