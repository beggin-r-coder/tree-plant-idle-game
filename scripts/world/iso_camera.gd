class_name IsoCamera
extends Node3D
## Orthographic isometric camera.
## Mouse wheel / pinch-less +/- keys: zoom.  Right or middle drag / WASD / arrows: pan.

const MIN_SIZE := 12.0
const MAX_SIZE := 48.0
const PAN_LIMIT := Vector2(20.0, 16.0)

var camera: Camera3D
var _target_size := 30.0
var _dragging := false


func _ready() -> void:
	rotation_degrees.y = 45.0
	var tilt := Node3D.new()
	tilt.rotation_degrees.x = -35.264  # true isometric angle
	add_child(tilt)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _target_size
	camera.position = Vector3(0, 0, 60)
	camera.near = 0.1
	camera.far = 200.0
	tilt.add_child(camera)
	camera.make_current()
	position = Vector3(0, 0, 1.5)


func _process(delta: float) -> void:
	camera.size = lerpf(camera.size, _target_size, clampf(delta * 10.0, 0.0, 1.0))
	var move := Vector2(
		Input.get_axis(&"ui_left", &"ui_right") + _key_axis(KEY_A, KEY_D),
		Input.get_axis(&"ui_up", &"ui_down") + _key_axis(KEY_W, KEY_S))
	if move != Vector2.ZERO:
		_pan_screen(move.limit_length(1.0) * camera.size * delta * 0.8)
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
		_target_size = clampf(_target_size - delta * 20.0, MIN_SIZE, MAX_SIZE)
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		_target_size = clampf(_target_size + delta * 20.0, MIN_SIZE, MAX_SIZE)


func _key_axis(neg: Key, pos: Key) -> float:
	return (1.0 if Input.is_key_pressed(pos) else 0.0) - (1.0 if Input.is_key_pressed(neg) else 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_size = clampf(_target_size * 0.9, MIN_SIZE, MAX_SIZE)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_size = clampf(_target_size * 1.1, MIN_SIZE, MAX_SIZE)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var px_to_world := camera.size / float(get_viewport().get_visible_rect().size.y)
		_pan_screen(-mm.relative * px_to_world)


## Moves the camera along the ground following screen directions.
func _pan_screen(screen: Vector2) -> void:
	var right := global_transform.basis.x
	var forward := global_transform.basis.z  # screen-down direction projected on the ground
	right.y = 0.0
	forward.y = 0.0
	# Screen-vertical motion covers more ground because the camera is tilted.
	var p := position + right.normalized() * screen.x + forward.normalized() * screen.y * 1.73
	p.x = clampf(p.x, -PAN_LIMIT.x, PAN_LIMIT.x)
	p.z = clampf(p.z, -PAN_LIMIT.y, PAN_LIMIT.y)
	position = p


## Projects a screen position onto the ground plane (y = 0).
func screen_to_ground(screen_pos: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return null
	var t := -origin.y / dir.y
	return origin + dir * t
