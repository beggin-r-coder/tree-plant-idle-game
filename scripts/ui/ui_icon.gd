class_name UIIcon
extends Control
## Tiny vector icons drawn in code (no image files, no emoji fonts needed).

var kind := "coin"
var tint := Color.WHITE


static func make(k: String, px: float, color: Color = Color.WHITE) -> UIIcon:
	var i := UIIcon.new()
	i.kind = k
	i.tint = color
	i.custom_minimum_size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return i


func _disc(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r, col)
	draw_arc(c, r, 0, TAU, 32, col, 1.0, true)


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var r := s * 0.5
	match kind:
		"coin":
			_disc(c, r * 0.92, Color(0.98, 0.76, 0.18))
			draw_arc(c, r * 0.64, 0, TAU, 32, Color(0.85, 0.58, 0.08), maxf(1.5, s * 0.07), true)
			_disc(c + Vector2(-r * 0.3, -r * 0.32), r * 0.13, Color(1, 0.95, 0.7))
		"leaf":
			var pts := PackedVector2Array()
			for k in 25:
				var t := float(k) / 24.0 * TAU
				pts.append(c + Vector2(sin(t) * r * 0.5, -cos(t) * r * 0.9).rotated(0.6) * Vector2(1, 1) * (1.0 - 0.25 * absf(sin(t * 0.5))))
			draw_colored_polygon(pts, Color(0.36, 0.72, 0.38))
			draw_line(c + Vector2(-r * 0.45, r * 0.6), c + Vector2(r * 0.45, -r * 0.6), Color(0.85, 1, 0.85, 0.8), maxf(1.0, s * 0.06), true)
		"cloud":
			var col := Color(0.55, 0.75, 0.9)
			_disc(c + Vector2(-r * 0.35, r * 0.12), r * 0.42, col)
			_disc(c + Vector2(r * 0.1, -r * 0.12), r * 0.52, col)
			_disc(c + Vector2(r * 0.5, r * 0.18), r * 0.36, col)
			draw_rect(Rect2(c + Vector2(-r * 0.35, r * 0.1), Vector2(r * 0.85, r * 0.44)), col)
		"bag":
			# shopping basket: wide handle over a tapered body
			var col := tint
			draw_arc(c + Vector2(0, -r * 0.05), r * 0.62, PI * 1.08, PI * 1.92, 20, col, maxf(2.0, s * 0.08), true)
			var body := PackedVector2Array([c + Vector2(-r * 0.85, -r * 0.05), c + Vector2(r * 0.85, -r * 0.05),
					c + Vector2(r * 0.6, r * 0.72), c + Vector2(-r * 0.6, r * 0.72)])
			draw_colored_polygon(body, col)
			var slot := Color(0.3, 0.7, 0.42)
			for k in 3:
				var x := (k - 1) * r * 0.38
				draw_line(c + Vector2(x, r * 0.12), c + Vector2(x * 0.8, r * 0.56), slot, maxf(1.5, s * 0.06), true)
		"close":
			var w := maxf(2.0, s * 0.1)
			draw_line(c + Vector2(-r, -r) * 0.5, c + Vector2(r, r) * 0.5, tint, w, true)
			draw_line(c + Vector2(r, -r) * 0.5, c + Vector2(-r, r) * 0.5, tint, w, true)
		"drop":
			var pts := PackedVector2Array()
			for k in 21:
				var t := PI * float(k) / 20.0
				pts.append(c + Vector2(cos(t) * r * 0.55, sin(t) * r * 0.55 + r * 0.2))
			pts.append(c + Vector2(0, -r * 0.85))
			draw_colored_polygon(pts, Color(0.35, 0.65, 0.95))
		"sprout":
			_disc(c + Vector2(0, r * 0.45), r * 0.5, Color(0.55, 0.38, 0.24))
			draw_line(c + Vector2(0, r * 0.1), c + Vector2(0, -r * 0.35), Color(0.36, 0.72, 0.38), maxf(2.0, s * 0.08), true)
			_disc(c + Vector2(-r * 0.28, -r * 0.45), r * 0.24, Color(0.36, 0.72, 0.38))
			_disc(c + Vector2(r * 0.28, -r * 0.55), r * 0.24, Color(0.45, 0.8, 0.42))
		"drone":
			_disc(c + Vector2(0, r * 0.1), r * 0.36, tint)
			var w := maxf(2.0, s * 0.08)
			draw_line(c + Vector2(-r * 0.85, -r * 0.35), c + Vector2(-r * 0.25, -r * 0.35), Color(0.3, 0.3, 0.35), w, true)
			draw_line(c + Vector2(r * 0.25, -r * 0.35), c + Vector2(r * 0.85, -r * 0.35), Color(0.3, 0.3, 0.35), w, true)
			draw_line(c + Vector2(-r * 0.55, -r * 0.35), c + Vector2(-r * 0.25, 0), Color(0.6, 0.6, 0.65), w, true)
			draw_line(c + Vector2(r * 0.55, -r * 0.35), c + Vector2(r * 0.25, 0), Color(0.6, 0.6, 0.65), w, true)
		"lock":
			draw_arc(c + Vector2(0, -r * 0.1), r * 0.32, PI, TAU, 16, tint, maxf(2.0, s * 0.1), true)
			draw_rect(Rect2(c + Vector2(-r * 0.48, -r * 0.1), Vector2(r * 0.96, r * 0.75)), tint)
