class_name IsoCamera
extends Node3D
## Orthographic isometric camera made for portrait phones.
## Tap = grow (emits `tapped`), drag = pan, pinch / mouse wheel = zoom.
## Desktop extras: right/middle drag, WASD / arrows, +/- keys.

signal tapped(screen_pos: Vector2)

const MIN_SIZE := 14.0
const MAX_SIZE := 60.0
const DRAG_THRESHOLD := 14.0

var camera: Camera3D
var _target_size := 30.0
var _pressing := false
var _dragged := false
var _press_pos := Vector2.ZERO
var _side_drag := false
var _touches := {}
var _pinch_dist := 0.0


func _ready() -> void:
	rotation_degrees.y = 45.0
	var tilt := Node3D.new()
	tilt.rotation_degrees.x = -35.264  # true isometric angle
	add_child(tilt)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = _target_size
	camera.position = Vector3(0, 0, 70)
	camera.near = 0.1
	camera.far = 200.0
	tilt.add_child(camera)
	camera.make_current()


func focus(world_pos: Vector3) -> void:
	position = Vector3(world_pos.x, 0, world_pos.z)
	_clamp()


func _process(delta: float) -> void:
	camera.size = lerpf(camera.size, _target_size, clampf(delta * 10.0, 0.0, 1.0))
	var move := Vector2(
		Input.get_axis(&"ui_left", &"ui_right") + _key_axis(KEY_A, KEY_D),
		Input.get_axis(&"ui_up", &"ui_down") + _key_axis(KEY_W, KEY_S))
	if move != Vector2.ZERO:
		_pan_screen(move.limit_length(1.0) * camera.size * delta * 0.8)
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
		_zoom(1.0 - delta)
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		_zoom(1.0 + delta)


func _key_axis(neg: Key, pos: Key) -> float:
	return (1.0 if Input.is_key_pressed(pos) else 0.0) - (1.0 if Input.is_key_pressed(neg) else 0.0)


func _zoom(factor: float) -> void:
	_target_size = clampf(_target_size * factor, MIN_SIZE, MAX_SIZE)


func _unhandled_input(event: InputEvent) -> void:
	# Two-finger pinch (real touch events; single touches arrive as emulated mouse).
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		_pinch_dist = 0.0
		if _touches.size() >= 2:
			_dragged = true
		return
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			var pts: Array = _touches.values()
			var d := (pts[0] as Vector2).distance_to(pts[1] as Vector2)
			if _pinch_dist > 0.0 and d > 0.0:
				_zoom(_pinch_dist / d)
			_pinch_dist = d
			_dragged = true
		return
	if event is InputEventMagnifyGesture:
		_zoom(1.0 / (event as InputEventMagnifyGesture).factor)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed: _zoom(0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed: _zoom(1.1)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_side_drag = mb.pressed
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_pressing = true
					_dragged = false
					_press_pos = mb.position
				else:
					if _pressing and not _dragged:
						tapped.emit(mb.position)
					_pressing = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pressing and not _dragged and mm.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_dragged = true
		if (_pressing and _dragged and _touches.size() < 2) or _side_drag:
			var px_to_world := camera.size / float(get_viewport().get_visible_rect().size.y)
			_pan_screen(-mm.relative * px_to_world)


## Moves the camera along the ground following screen directions.
func _pan_screen(screen: Vector2) -> void:
	# Screen-vertical motion covers more ground because the camera is tilted.
	var uv := Terrain.to_uv(position) + Vector2(screen.x, screen.y * 1.73)
	position = Terrain.to_world(uv.x, uv.y)
	_clamp()


func _clamp() -> void:
	var uv := Terrain.to_uv(position)
	uv.x = clampf(uv.x, -Terrain.HALF_U * 0.7, Terrain.HALF_U * 0.7)
	uv.y = clampf(uv.y, -Terrain.HALF_V * 0.9, Terrain.HALF_V * 0.75)
	position = Terrain.to_world(uv.x, uv.y)
