class_name GoldenBonus
extends Node3D
## Every minute or so a sparkling golden butterfly flutters around the forest
## for a few seconds. Tapping it gives bonus coins and a pollinator fact.

signal collected(amount: float, at: Vector3)

const FIRST_DELAY := 25.0
const DELAY_RANGE := Vector2(50.0, 100.0)
const LIFETIME := 14.0
const HIT_RADIUS_PX := 75.0

const FACTS := [
	"Butterflies and bees carry pollen from flower to flower. That helps plants make fruit and seeds.",
	"Most of the fruits and vegetables we eat need pollinators like bees and butterflies.",
	"Butterflies taste with their feet!",
	"Planting wildflowers gives butterflies and bees food and a safe place to rest.",
	"Monarch butterflies can fly thousands of kilometres every year to escape the winter.",
]

var world: World
var _timer := FIRST_DELAY
var _active := false
var _life := 0.0
var _t := 0.0
var _target := Vector3.ZERO
var _vel := Vector3.ZERO
var _home := Vector3.ZERO
var _wings: Array[Node3D] = []
var _leaving := false
var _rng := RandomNumberGenerator.new()
var _fact_index := 0


func _ready() -> void:
	_rng.randomize()
	_build()
	visible = false


func _build() -> void:
	var gold := Color(1.0, 0.78, 0.15)
	add_child(LowPoly.instance(LowPoly.mesh(LowPoly.box(Vector3(0.06, 0.06, 0.3)), Color(0.35, 0.22, 0.05))))
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		add_child(pivot)
		var b := LowPoly.Builder.new()
		b.add(LowPoly.box(Vector3(0.32, 0.015, 0.3)), gold, LowPoly.xf(Vector3(side * 0.17, 0, 0.04)))
		b.add(LowPoly.box(Vector3(0.22, 0.016, 0.2)), gold.lightened(0.35), LowPoly.xf(Vector3(side * 0.15, 0, -0.16)))
		pivot.add_child(LowPoly.instance(b.commit()))
		_wings.append(pivot)
	var sparkle := CPUParticles3D.new()
	sparkle.amount = 16
	sparkle.lifetime = 0.9
	sparkle.local_coords = false
	sparkle.direction = Vector3.DOWN
	sparkle.spread = 60.0
	sparkle.initial_velocity_min = 0.2
	sparkle.initial_velocity_max = 0.6
	sparkle.gravity = Vector3(0, -0.6, 0)
	var dot := LowPoly.Builder.new()
	dot.unshaded = true
	dot.add(LowPoly.sphere(0.04, 0.08, 4, 2), Color(1.0, 0.95, 0.6))
	sparkle.mesh = dot.commit()
	add_child(sparkle)
	scale = Vector3.ONE * 2.6


func _process(delta: float) -> void:
	_t += delta
	if not _active:
		_timer -= delta
		if _timer <= 0.0:
			_spawn()
		return
	_life -= delta
	if _life <= 0.0 and not _leaving:
		_leaving = true
		_target = position + Vector3(_rng.randf_range(-6, 6), 14.0, _rng.randf_range(-6, 6))
	var to := _target - position
	if to.length() < 0.6:
		if _leaving:
			_despawn()
			return
		_pick_target()
	_vel = _vel.lerp(to.normalized() * (3.0 if _leaving else 1.6), clampf(delta * 2.0, 0.0, 1.0))
	position += _vel * delta
	position.y += sin(_t * 6.0) * 0.01
	if _vel.length_squared() > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(_vel.x, _vel.z), clampf(delta * 5.0, 0.0, 1.0))
	var flap := sin(_t * 16.0)
	_wings[0].rotation.z = -flap * 0.9
	_wings[1].rotation.z = flap * 0.9


func _spawn() -> void:
	# Flutter around the sapling the player is growing, where they are looking.
	_home = world.forest.sapling_position(GameState.selected)
	if _home == Vector3.INF:
		_home = world.forest.center
	_active = true
	_leaving = false
	_life = LIFETIME
	position = _home + Vector3(_rng.randf_range(-5, 5), 6.0, _rng.randf_range(-5, 5))
	visible = true
	_pick_target()


func _pick_target() -> void:
	var p := _home + Vector3(_rng.randf_range(-3.5, 3.5), 0, _rng.randf_range(-3.5, 3.5))
	p.y = world.height_at(p) + _rng.randf_range(1.3, 2.6)
	_target = p


func _despawn() -> void:
	_active = false
	visible = false
	_timer = _rng.randf_range(DELAY_RANGE.x, DELAY_RANGE.y)


## Returns true (and pays out) if a tap at `screen_pos` hit the butterfly.
func try_collect(screen_pos: Vector2, cam: Camera3D) -> bool:
	if not _active or _leaving:
		return false
	if cam.unproject_position(global_position).distance_to(screen_pos) > HIT_RADIUS_PX:
		return false
	var amount := maxf(25.0, maxf(GameState.coins_per_second() * 45.0, GameState.reward(GameState.selected) * 4.0))
	GameState.add_coins(amount)
	collected.emit(amount, global_position)
	_despawn()
	return true


func next_fact() -> String:
	var f: String = FACTS[_fact_index % FACTS.size()]
	_fact_index += 1
	return f
