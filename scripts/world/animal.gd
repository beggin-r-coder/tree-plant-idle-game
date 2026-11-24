class_name Animal
extends Node3D
## A simple procedural animal. Flyers wander in the air with flapping wings;
## walkers stroll between random points with swinging legs (rabbits hop).
## Models face +Z.

var kind := ""
var flyer := false
var hopper := false
var speed := 1.5
var flap_speed := 10.0
var height_range := Vector2(2.0, 4.0)
var legs: Array[Node3D] = []
var wings: Array[Node3D] = []
var tail: Node3D
var world: Node  ## World node, used for picking free ground points

var _t := 0.0
var _target := Vector3.ZERO
var _vel := Vector3.ZERO
var _idle := 0.0


func _ready() -> void:
	_t = randf() * 10.0
	_pick_target()


## Makes the animal arrive with a "pop" from a start position (e.g. the island edge or sky).
func arrive(from: Vector3, delay: float = 0.0) -> void:
	position = from
	scale = Vector3.ONE * 0.01
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(self, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_idle = 0.0
	_pick_target()


func _pick_target() -> void:
	if world == null:
		return
	var p: Vector3 = world.random_free_point()
	if flyer:
		p.y += randf_range(height_range.x, height_range.y)
	_target = p


func _process(delta: float) -> void:
	_t += delta
	if flyer:
		_process_flyer(delta)
	else:
		_process_walker(delta)


func _process_flyer(delta: float) -> void:
	var to := _target - position
	if to.length() < 0.8:
		_pick_target()
	var desired := to.normalized() * speed
	_vel = _vel.lerp(desired, clampf(delta * 1.5, 0.0, 1.0))
	position += _vel * delta
	position.y += sin(_t * 5.0) * 0.01
	if _vel.length_squared() > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(_vel.x, _vel.z), clampf(delta * 5.0, 0.0, 1.0))
	var flap := sin(_t * flap_speed)
	for i in wings.size():
		var side := -1.0 if i % 2 == 0 else 1.0
		wings[i].rotation.z = side * flap * 0.9


func _process_walker(delta: float) -> void:
	var moving := false
	if _idle > 0.0:
		_idle -= delta
	else:
		var to := _target - position
		to.y = 0.0
		if to.length() < 0.3:
			_idle = randf_range(1.0, 4.0)
			_pick_target()
		else:
			moving = true
			var dir := to.normalized()
			position += dir * speed * delta
			rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), clampf(delta * 6.0, 0.0, 1.0))
	# Leg / hop animation
	var ground: float = world.height_at(position) if world else 0.0
	position.y = ground + (absf(sin(_t * 7.0)) * 0.25 if (hopper and moving) else 0.0)
	var swing := sin(_t * speed * 6.0) * 0.6 if moving else 0.0
	for i in legs.size():
		var phase := 1.0 if (i == 0 or i == 3) else -1.0
		legs[i].rotation.x = swing * phase
	if tail:
		tail.rotation.y = sin(_t * 3.0) * 0.4
