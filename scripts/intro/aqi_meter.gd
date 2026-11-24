class_name AqiMeter
extends Control
## Air Quality Index meter (US EPA bands): number, category and a colour bar.

const BANDS := [
	[50.0, "Good", Color(0.0, 0.89, 0.0)],
	[100.0, "Moderate", Color(1.0, 0.85, 0.0)],
	[150.0, "Unhealthy for some", Color(1.0, 0.49, 0.0)],
	[200.0, "Unhealthy", Color(1.0, 0.0, 0.0)],
	[300.0, "Very Unhealthy", Color(0.6, 0.2, 0.6)],
	[100000.0, "Hazardous", Color(0.5, 0.0, 0.14)],
]

var value := 20.0:
	set(v):
		value = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(230, 96)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func band(v: float) -> Array:
	for b in BANDS:
		if v <= b[0]:
			return b
	return BANDS[BANDS.size() - 1]


func _draw() -> void:
	var font := get_theme_default_font()
	var b := band(value)
	var col: Color = b[2]
	var w := size.x
	draw_string(font, Vector2(0, 18), "AIR QUALITY (AQI)", HORIZONTAL_ALIGNMENT_RIGHT, w, 14, Color(1, 1, 1, 0.75))
	var num := str(int(value)) + ("+" if value >= 999.0 else "")
	draw_string(font, Vector2(0, 58), num, HORIZONTAL_ALIGNMENT_RIGHT, w, 42, col.lightened(0.15))
	draw_string(font, Vector2(0, 78), String(b[1]).to_upper(), HORIZONTAL_ALIGNMENT_RIGHT, w, 14, col.lightened(0.3))
	# Segmented bar
	var bar_y := 88.0
	var seg_w := w / BANDS.size()
	for i in BANDS.size():
		var c: Color = BANDS[i][2]
		draw_rect(Rect2(i * seg_w + 1, bar_y, seg_w - 2, 6), Color(c.r, c.g, c.b, 0.85))
	var limits := [0.0, 50.0, 100.0, 150.0, 200.0, 300.0, 500.0]
	var x := w
	for i in BANDS.size():
		if value <= limits[i + 1]:
			x = (i + (value - limits[i]) / (limits[i + 1] - limits[i])) * seg_w
			break
	draw_circle(Vector2(clampf(x, 4, w - 4), bar_y + 3), 6.0, Color.WHITE)
