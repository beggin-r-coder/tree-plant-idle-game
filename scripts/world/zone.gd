class_name Zone
extends Node3D
## One plantation plot for a single plant type.
## The "nursery" tree at the front grows from clicks / its machine. When fully
## grown it is transplanted into the zone's forest grid and a new sapling starts.

const GRID := 6
const SPACING := 1.3
const HALF := GRID * SPACING * 0.5 + 0.3   ## half size of the soil patch
const NURSERY_OFFSET := Vector3(0.0, 0.0, HALF + 1.1)
const MAX_FLYING_TREES := 4

var plant_index := 0
var plant_id := ""
var cells: Array[Vector3] = []
var forest: Array[MeshInstance3D] = []

var _patch: MeshInstance3D
var _patch_mat: StandardMaterial3D
var _nursery: MeshInstance3D
var _nursery_root: Node3D
var _lock_sign: Node3D
var _machine: Node3D
var _machine_label: Label3D
var _name_label: Label3D
var _select_ring: MeshInstance3D
var _particles: CPUParticles3D
var _flying := 0
var _popup_accum := 0.0
var _popup_timer := 0.0
var _bounce := 0.0
var _rng := RandomNumberGenerator.new()


func setup(index: int) -> void:
	plant_index = index
	plant_id = GameData.PLANTS[index]["id"]
	_rng.seed = 1234 + index * 77
	_build_cells()
	_build_patch()
	_build_nursery()
	_build_labels()
	rebuild_from_state()


func _build_cells() -> void:
	cells.clear()
	var start := -(GRID - 1) * SPACING * 0.5
	for gz in GRID:
		for gx in GRID:
			var p := Vector3(start + gx * SPACING, 0, start + gz * SPACING)
			p += Vector3(_rng.randf_range(-0.2, 0.2), 0, _rng.randf_range(-0.2, 0.2))
			cells.append(p)
	# Fill in a pleasant order: from the back towards the camera.
	cells.shuffle()
	cells.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z + a.x * 0.3 < b.z + b.x * 0.3)


func _build_patch() -> void:
	_patch_mat = StandardMaterial3D.new()
	_patch_mat.vertex_color_use_as_albedo = true
	_patch_mat.roughness = 1.0
	_patch = MeshInstance3D.new()
	var m := LowPoly.mesh(LowPoly.box(Vector3(HALF * 2.0, 0.12, HALF * 2.0)), Color(1, 1, 1), LowPoly.xf(Vector3(0, 0.02, 0)))
	m.surface_set_material(0, _patch_mat)
	_patch.mesh = m
	_patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_patch)
	# Nursery plot: a round soil bed with little stones.
	var b := LowPoly.Builder.new()
	b.add(LowPoly.cylinder(0.85, 0.95, 0.16, 10), Color(0.36, 0.24, 0.15), LowPoly.xf(NURSERY_OFFSET + Vector3(0, 0.06, 0)))
	for k in 10:
		var ang := TAU * k / 10.0
		b.add(LowPoly.sphere(0.13, 0.18, 5, 2), Color(0.7, 0.7, 0.68), LowPoly.xf(NURSERY_OFFSET + Vector3(cos(ang) * 0.95, 0.1, sin(ang) * 0.95)))
	add_child(LowPoly.instance(b.commit(), Vector3.ZERO, false))
	# Selection ring (shown when this plant is the one you are clicking for).
	var ring := LowPoly.Builder.new()
	ring.unshaded = true
	for k in 16:
		var ang := TAU * k / 16.0
		ring.add(LowPoly.box(Vector3(0.38, 0.03, 0.1)), Color(1.0, 0.95, 0.4, 0.9), LowPoly.xf(Vector3(cos(ang) * 1.2, 0.18, sin(ang) * 1.2), Vector3(0, -rad_to_deg(ang) + 90.0, 0)))
	_select_ring = LowPoly.instance(ring.commit(), NURSERY_OFFSET, false)
	add_child(_select_ring)


func _build_nursery() -> void:
	_nursery_root = Node3D.new()
	_nursery_root.position = NURSERY_OFFSET + Vector3(0, 0.12, 0)
	add_child(_nursery_root)
	_nursery = LowPoly.instance(TreeFactory.tree_mesh(plant_id))
	_nursery_root.add_child(_nursery)
	_particles = CPUParticles3D.new()
	_particles.emitting = false
	_particles.one_shot = true
	_particles.amount = 14
	_particles.lifetime = 0.8
	_particles.explosiveness = 0.9
	_particles.direction = Vector3.UP
	_particles.spread = 60.0
	_particles.initial_velocity_min = 2.0
	_particles.initial_velocity_max = 3.5
	_particles.gravity = Vector3(0, -6, 0)
	_particles.scale_amount_min = 0.6
	_particles.scale_amount_max = 1.0
	_particles.mesh = LowPoly.mesh(LowPoly.box(Vector3(0.12, 0.03, 0.08)), TreeFactory.plant_color(plant_id).lightened(0.2))
	_particles.position = Vector3(0, 0.6, 0)
	_nursery_root.add_child(_particles)


func _build_labels() -> void:
	_name_label = Label3D.new()
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.font_size = 56
	_name_label.outline_size = 14
	_name_label.pixel_size = 0.008
	_name_label.position = NURSERY_OFFSET + Vector3(0, 3.6, 0)
	_name_label.modulate = Color(1, 1, 1)
	_name_label.outline_modulate = Color(0.1, 0.2, 0.1)
	add_child(_name_label)


func rebuild_from_state() -> void:
	for t in forest:
		t.queue_free()
	forest.clear()
	var visible_count := mini(GameState.trees_per_type[plant_index], cells.size())
	for k in visible_count:
		_spawn_forest_tree(k, false)
	_update_locked_visual(false)
	_update_machine(false)
	_update_label()


func is_unlocked() -> bool:
	return GameState.unlocked[plant_index]


func contains_point(p: Vector3) -> bool:
	var local := p - position
	var in_patch := absf(local.x) <= HALF and absf(local.z) <= HALF
	var in_nursery := Vector2(local.x - NURSERY_OFFSET.x, local.z - NURSERY_OFFSET.z).length() <= 1.4
	return in_patch or in_nursery


## World-space rectangle (x, z, size) used to keep decorations out of the zone.
func blocked_rect() -> Rect2:
	return Rect2(position.x - HALF - 0.4, position.z - HALF - 0.4, HALF * 2.0 + 0.8, HALF * 2.0 + 2.8)


# ------------------------------------------------------------------ runtime

func _process(delta: float) -> void:
	var unlocked := is_unlocked()
	_nursery_root.visible = unlocked
	_select_ring.visible = unlocked and GameState.selected == plant_index
	if _select_ring.visible:
		_select_ring.rotation.y += delta * 0.6
	if unlocked:
		var p := clampf(GameState.progress[plant_index] / GameState.growth_needed(plant_index), 0.0, 1.0)
		var s := lerpf(0.12, 1.0, p)
		_bounce = maxf(_bounce - delta * 4.0, 0.0)
		var squash := 1.0 + sin(_bounce * PI) * 0.18
		_nursery.scale = Vector3(s * squash, s / squash, s * squash)
	if _machine and _machine.visible:
		var rotor := _machine.get_node("Rotor") as Node3D
		rotor.rotation.y += delta * (3.0 + GameState.machine_level[plant_index] * 0.5)
	# Batch coin popups when machines finish many trees quickly.
	_popup_timer -= delta
	if _popup_accum > 0.0 and _popup_timer <= 0.0:
		_coin_popup(_popup_accum)
		_popup_accum = 0.0
		_popup_timer = 0.35


func on_click() -> void:
	_bounce = 1.0


func on_trees_completed(count: int, earned: float) -> void:
	_particles.restart()
	_popup_accum += earned
	var placed := forest.size()
	var to_place := mini(count, cells.size() - placed)
	for k in to_place:
		_spawn_forest_tree(placed + k, _flying < MAX_FLYING_TREES)
	_update_label()


func on_unlocked() -> void:
	_update_locked_visual(true)
	_update_label()


func on_machine_changed() -> void:
	_update_machine(true)


func _spawn_forest_tree(k: int, animate: bool) -> void:
	var t := LowPoly.instance(TreeFactory.tree_mesh(plant_id))
	var target := cells[k]
	var r := RandomNumberGenerator.new()
	r.seed = plant_index * 1000 + k
	t.rotation.y = r.randf() * TAU
	var final_scale := Vector3.ONE * r.randf_range(0.85, 1.15)
	add_child(t)
	forest.append(t)
	if not animate:
		t.position = target
		t.scale = final_scale
		return
	# Hop from the nursery to its spot in the forest.
	_flying += 1
	var from := NURSERY_OFFSET + Vector3(0, 0.12, 0)
	t.position = from
	t.scale = final_scale * 0.9
	var tw := create_tween()
	var arc := func(v: float) -> void: t.position = from.lerp(target, v) + Vector3(0, sin(v * PI) * 2.5, 0)
	tw.tween_method(arc, 0.0, 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(t, "scale", final_scale * Vector3(1.2, 0.8, 1.2), 0.08)
	tw.tween_property(t, "scale", final_scale, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _flying -= 1)


func _coin_popup(amount: float) -> void:
	var l := Label3D.new()
	l.text = "+%s" % GameData.format_number(amount)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 64
	l.outline_size = 16
	l.pixel_size = 0.008
	l.modulate = Color(1.0, 0.86, 0.2)
	l.outline_modulate = Color(0.35, 0.2, 0.0)
	l.position = NURSERY_OFFSET + Vector3(0.0, 2.2, 0.0)
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 1.6, 1.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


func _update_locked_visual(animate: bool) -> void:
	var unlocked := is_unlocked()
	var soil := Color(0.42, 0.3, 0.2) if unlocked else Color(0.4, 0.37, 0.34)
	if animate:
		create_tween().tween_property(_patch_mat, "albedo_color", soil, 0.8)
	else:
		_patch_mat.albedo_color = soil
	if unlocked:
		if _lock_sign:
			var old_sign := _lock_sign
			_lock_sign = null
			if animate:
				var tw := create_tween()
				tw.tween_property(old_sign, "scale", Vector3.ONE * 0.01, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
				tw.tween_callback(old_sign.queue_free)
			else:
				old_sign.queue_free()
		if animate:
			_nursery_root.scale = Vector3.ONE * 0.01
			create_tween().tween_property(_nursery_root, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif _lock_sign == null:
		_lock_sign = Node3D.new()
		var b := LowPoly.Builder.new()
		b.add(LowPoly.box(Vector3(0.12, 1.2, 0.12)), Color(0.45, 0.3, 0.18), LowPoly.xf(Vector3(0, 0.6, 0)))
		b.add(LowPoly.box(Vector3(1.3, 0.7, 0.08)), Color(0.7, 0.5, 0.3), LowPoly.xf(Vector3(0, 1.3, 0)))
		# little fence around the patch
		for k in 8:
			var s := -HALF + k * (HALF * 2.0 / 7.0)
			for p in [Vector3(s, 0.25, -HALF), Vector3(s, 0.25, HALF), Vector3(-HALF, 0.25, s), Vector3(HALF, 0.25, s)]:
				b.add(LowPoly.box(Vector3(0.1, 0.5, 0.1)), Color(0.6, 0.45, 0.3), LowPoly.xf(p))
		_lock_sign.add_child(LowPoly.instance(b.commit()))
		_lock_sign.position = Vector3.ZERO
		add_child(_lock_sign)


func _update_machine(animate: bool) -> void:
	var lvl: int = GameState.machine_level[plant_index]
	if lvl <= 0:
		if _machine:
			_machine.visible = false
		return
	var created := false
	if _machine == null:
		_machine = TreeFactory.machine(TreeFactory.plant_color(plant_id))
		_machine.position = NURSERY_OFFSET + Vector3(1.9, 0, 0.2)
		add_child(_machine)
		_machine_label = Label3D.new()
		_machine_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_machine_label.no_depth_test = true
		_machine_label.font_size = 44
		_machine_label.outline_size = 12
		_machine_label.pixel_size = 0.008
		_machine_label.position = Vector3(0, 1.7, 0)
		_machine_label.modulate = Color(1, 0.95, 0.6)
		_machine_label.outline_modulate = Color(0.2, 0.15, 0.0)
		_machine.add_child(_machine_label)
		created = true
	_machine.visible = true
	_machine_label.text = "Auto Lv %d" % lvl
	if animate:
		_machine.scale = Vector3.ONE * (0.01 if created else 0.7)
		create_tween().tween_property(_machine, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_label() -> void:
	var data: Dictionary = GameData.PLANTS[plant_index]
	if is_unlocked():
		_name_label.text = "%s  x%s" % [data["name"], GameData.format_number(GameState.trees_per_type[plant_index])]
	else:
		_name_label.text = "LOCKED: %s\n%s coins" % [data["name"], GameData.format_number(data["unlock_cost"])]
