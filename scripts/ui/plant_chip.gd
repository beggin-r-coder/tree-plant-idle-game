class_name PlantChip
extends Control
## Round plant button for the bottom tray: colour disc with the plant level,
## a ring showing how much the current sapling has grown, and the plant name
## (or the unlock price) underneath.

signal pressed(index: int)

const DISC_R := 30.0

var index := 0
var color := Color.GREEN
var label := ""
var level := 1
var progress := 0.0
var selected := false
var locked := false
var affordable := false
var cost_text := ""
var _pulse := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(92, 104)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func set_state(p: float, sel: bool, lock: bool, can_afford: bool, cost: String) -> void:
	var changed := not is_equal_approx(p, progress) or sel != selected or lock != locked or can_afford != affordable or cost != cost_text
	progress = p
	selected = sel
	locked = lock
	affordable = can_afford
	cost_text = cost
	if changed or (locked and affordable):
		queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and Rect2(Vector2.ZERO, size).has_point(mb.position):
			pressed.emit(index)
			var tw := create_tween()
			pivot_offset = size * 0.5
			tw.tween_property(self, "scale", Vector2.ONE * 0.9, 0.06)
			tw.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var c := Vector2(size.x * 0.5, 40.0)
	var font := get_theme_default_font()
	var ring_col := Color(0.3, 0.7, 0.42)
	if selected:
		draw_circle(c, DISC_R + 7.0, Color(0.3, 0.7, 0.42, 0.18))
	# progress track + fill
	draw_arc(c, DISC_R + 5.0, 0, TAU, 48, Color(0, 0, 0, 0.08), 4.0, true)
	if not locked and progress > 0.001:
		draw_arc(c, DISC_R + 5.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, ring_col, 4.0, true)
	if locked and affordable:
		var a := 0.5 + 0.5 * sin(_pulse * 5.0)
		draw_arc(c, DISC_R + 5.0, 0, TAU, 48, Color(0.98, 0.76, 0.18, 0.5 + a * 0.5), 4.0, true)
	var disc := Color(0.82, 0.84, 0.82) if locked else color
	draw_circle(c, DISC_R, disc)
	draw_arc(c, DISC_R, 0, TAU, 48, disc, 1.0, true)
	if locked:
		var lc := Color(1, 1, 1, 0.95)
		draw_arc(c + Vector2(0, -5), 7.0, PI, TAU, 16, lc, 3.0, true)
		draw_rect(Rect2(c + Vector2(-10, -5), Vector2(20, 15)), lc)
	else:
		var txt := str(level)
		draw_string(font, Vector2(0, c.y + 9), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, Color.WHITE)
	var below := cost_text if locked else label
	var col := Color(0.55, 0.42, 0.1) if locked else (Color(0.13, 0.3, 0.18) if selected else Color(0.35, 0.42, 0.37))
	draw_string(font, Vector2(0, 98), below, HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, col)
