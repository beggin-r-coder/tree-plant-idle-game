class_name Forest
extends Node3D
## A natural, mixed forest that spreads outward over open land.
##
## Each unlocked plant has one growing sapling at the edge of the forest. Taps
## (for the selected plant) and Planter Drones make saplings grow; a finished
## tree stays where it grew and a new sapling starts at a fresh spot nearby.
## Trees are drawn with one MultiMesh per species, so hundreds stay cheap.

signal extent_changed(radius: float)

const MAX_TREES := 700
const CENTER_UV := Vector2(0.0, 9.0)   ## where the first tree grows (lower-middle of the screen)
const HASH_CELL := 2.0
const MAX_POPS := 6

var terrain: Terrain
var center := Vector3.ZERO
var extent := 0.0                       ## distance of the farthest tree from the centre

var _mm: Array[MultiMesh] = []
var _hash := {}                         ## Vector2i -> Array of [Vector2 uv, radius]
var _recent: Array[Vector2] = []        ## recently placed trees (the forest edge)
var _all: Array[Vector2] = []
var _saplings: Array[MeshInstance3D] = []
var _sapling_spot: Array[Vector3] = []
var _drones: Array[Node3D] = []
var _bounce: Array[float] = []
var _popup_accum: Array[float] = []
var _popup_timer: Array[float] = []
var _marker: Node3D
var _particles: CPUParticles3D
var _pops := 0
var _rng := RandomNumberGenerator.new()
var _t := 0.0


func setup(t: Terrain) -> void:
	terrain = t
	_rng.seed = 2024 + GameState.total_trees
	center = Terrain.to_world(CENTER_UV.x, CENTER_UV.y)
	center.y = terrain.height_at(center)
	var n := GameData.PLANTS.size()
	for i in n:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = TreeFactory.tree_mesh(GameData.PLANTS[i]["id"])
		mm.instance_count = MAX_TREES
		mm.visible_instance_count = 0
		_mm.append(mm)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "Trees_%s" % GameData.PLANTS[i]["id"]
		add_child(mmi)
		var sap := LowPoly.instance(TreeFactory.tree_mesh(GameData.PLANTS[i]["id"]))
		sap.visible = false
		add_child(sap)
		_saplings.append(sap)
		_sapling_spot.append(Vector3.INF)
		_drones.append(null)
		_bounce.append(0.0)
		_popup_accum.append(0.0)
		_popup_timer.append(0.0)
	_build_marker()
	_build_particles()


## Rebuild trees from the save file, then place any trees grown offline.
func restore() -> void:
	var layout := GameState.forest_layout
	var placed: Array[int] = []
	placed.resize(GameData.PLANTS.size())
	placed.fill(0)
	for k in range(0, layout.size() - 2, 3):
		var i := int(layout[k])
		if i < 0 or i >= _mm.size():
			continue
		var p := Vector3(layout[k + 1], 0, layout[k + 2])
		p.y = terrain.height_at(p)
		_add_instance(i, p, false, false)
		placed[i] += 1
	for i in GameData.PLANTS.size():
		var missing := GameState.trees_per_type[i] - placed[i]
		for k in mini(missing, MAX_TREES):
			if total_visible() >= MAX_TREES:
				break
			var spot := find_spot(i)
			if spot == Vector3.INF:
				break
			_add_instance(i, spot, false, true)
	for i in GameData.PLANTS.size():
		if GameState.unlocked[i]:
			_new_sapling(i)
		_update_drone(i, false)
	extent_changed.emit(extent)


func total_visible() -> int:
	var c := 0
	for mm in _mm:
		c += mm.visible_instance_count
	return c


func add_obstacle(p: Vector3, radius: float) -> void:
	_hash_add(Terrain.to_uv(p), radius)


func sapling_position(i: int) -> Vector3:
	return _sapling_spot[i]


# ------------------------------------------------------------------ placement

## Finds a free spot at the forest edge, preferring spots close to the centre so
## the forest grows as one natural, roughly round woodland.
func find_spot(i: int) -> Vector3:
	var r: float = GameData.PLANTS[i]["radius"]
	var best := Vector2.INF
	var best_score := INF
	var tries := 24
	for k in tries:
		var base := CENTER_UV
		if not _all.is_empty():
			if _rng.randf() < 0.75 and not _recent.is_empty():
				base = _recent[_rng.randi() % _recent.size()]
			else:
				base = _all[_rng.randi() % _all.size()]
		var cand := base + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(r + 0.45, r + 1.9)
		if _all.is_empty() and k == 0:
			cand = CENTER_UV
		if not _is_free(cand, r):
			continue
		var score := cand.distance_to(CENTER_UV) + _rng.randf() * 2.0
		if score < best_score:
			best_score = score
			best = cand
	if best == Vector2.INF:
		# Edge is crowded: try random spots on a ring just outside the forest.
		for k in 60:
			var cand := CENTER_UV + Vector2.from_angle(_rng.randf() * TAU) * (extent + _rng.randf_range(0.5, 4.0))
			if _is_free(cand, r):
				best = cand
				break
	if best == Vector2.INF:
		for k in 80:
			var p := terrain.random_land_point(_rng, 0.2)
			var cand := Terrain.to_uv(p)
			if _is_free(cand, r):
				best = cand
				break
	if best == Vector2.INF:
		return Vector3.INF
	var w := Terrain.to_world(best.x, best.y)
	w.y = terrain.height_at(w)
	return w


func _is_free(uv: Vector2, r: float) -> bool:
	if absf(uv.x) > Terrain.HALF_U - 0.5 or uv.y < -Terrain.HALF_V + 6.0 or uv.y > Terrain.HALF_V - 0.5:
		return false
	var w := Terrain.to_world(uv.x, uv.y)
	if not terrain.is_land(w, 0.2):
		return false
	var cell := Vector2i(floori(uv.x / HASH_CELL), floori(uv.y / HASH_CELL))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var key := cell + Vector2i(dx, dy)
			if not _hash.has(key):
				continue
			for e in _hash[key]:
				var other: Vector2 = e[0]
				var orad: float = e[1]
				if uv.distance_to(other) < (r + orad) * 0.92:
					return false
	return true


func _hash_add(uv: Vector2, r: float) -> void:
	var key := Vector2i(floori(uv.x / HASH_CELL), floori(uv.y / HASH_CELL))
	if not _hash.has(key):
		_hash[key] = []
	_hash[key].append([uv, r])


func _add_instance(i: int, p: Vector3, animate: bool, record: bool) -> void:
	var mm := _mm[i]
	var idx := mm.visible_instance_count
	if idx >= MAX_TREES:
		return
	var uv := Terrain.to_uv(p)
	var h := absi(hash(Vector2i(roundi(p.x * 100.0), roundi(p.z * 100.0))))
	var rot := float(h % 6283) / 1000.0
	var s := 0.85 + float((h >> 13) % 300) / 1000.0
	var basis := Basis(Vector3.UP, rot)
	var xf := Transform3D(basis.scaled(Vector3.ONE * s), p)
	mm.visible_instance_count = idx + 1
	if animate and _pops < MAX_POPS:
		_pops += 1
		mm.set_instance_transform(idx, Transform3D(basis.scaled(Vector3.ONE * 0.01), p))
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void: mm.set_instance_transform(idx, Transform3D(basis.scaled(Vector3(v, v, v) * s), p)), 0.3, 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func() -> void: _pops -= 1)
	else:
		mm.set_instance_transform(idx, xf)
	if record:
		GameState.forest_layout.append_array(PackedFloat32Array([float(i), p.x, p.z]))
	var r: float = GameData.PLANTS[i]["radius"]
	if _sapling_spot[i] == Vector3.INF or not p.is_equal_approx(_sapling_spot[i]):
		_hash_add(uv, r)   # sapling spots are already reserved in the hash
	_all.append(uv)
	_recent.append(uv)
	if _recent.size() > 60:
		_recent.pop_front()
	var d := uv.distance_to(CENTER_UV) + r
	if d > extent:
		extent = d
		extent_changed.emit(extent)


func _new_sapling(i: int) -> void:
	var spot := Vector3.INF
	if total_visible() < MAX_TREES:
		spot = find_spot(i)
	if spot == Vector3.INF:
		# Forest is full: keep growing at the old spot (trees still earn coins).
		if _sapling_spot[i] == Vector3.INF:
			spot = center
		else:
			spot = _sapling_spot[i]
	else:
		_hash_add(Terrain.to_uv(spot), GameData.PLANTS[i]["radius"])
	_sapling_spot[i] = spot
	var sap := _saplings[i]
	sap.position = spot
	sap.rotation.y = _rng.randf() * TAU
	sap.visible = true


# ------------------------------------------------------------------ events

func on_click(i: int) -> void:
	_bounce[i] = 1.0


func on_trees_completed(i: int, count: int, earned: float) -> void:
	if i == GameState.selected:
		_particles.global_position = _sapling_spot[i] + Vector3(0, 0.6, 0)
		_particles.restart()
	_popup_accum[i] += earned
	for k in count:
		if total_visible() >= MAX_TREES:
			break
		_add_instance(i, _sapling_spot[i], true, true)
		_new_sapling(i)


func on_unlocked(i: int) -> void:
	_new_sapling(i)
	var sap := _saplings[i]
	sap.scale = Vector3.ONE * 0.01


func on_machine_changed(i: int) -> void:
	_update_drone(i, true)


func _update_drone(i: int, animate: bool) -> void:
	var lvl: int = GameState.machine_level[i]
	if lvl <= 0 or not GameState.unlocked[i]:
		return
	if _drones[i] == null:
		var d := TreeFactory.drone(TreeFactory.plant_color(GameData.PLANTS[i]["id"]))
		var drops := CPUParticles3D.new()
		drops.amount = 10
		drops.lifetime = 0.6
		drops.direction = Vector3.DOWN
		drops.spread = 12.0
		drops.initial_velocity_min = 1.5
		drops.initial_velocity_max = 2.5
		drops.gravity = Vector3(0, -6, 0)
		drops.mesh = LowPoly.mesh(LowPoly.sphere(0.035, 0.07, 4, 2), Color(0.5, 0.75, 1.0))
		drops.position = Vector3(0, -0.2, 0)
		d.add_child(drops)
		add_child(d)
		d.position = _sapling_spot[i] + Vector3(0, 6.0, 0)
		_drones[i] = d
	var drone := _drones[i]
	if animate:
		drone.scale = Vector3.ONE * 0.6
		create_tween().tween_property(drone, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	_t += delta
	for i in _saplings.size():
		var sap := _saplings[i]
		if not sap.visible:
			continue
		var p := clampf(GameState.progress[i] / GameState.growth_needed(i), 0.0, 1.0)
		var s := lerpf(0.22, 1.0, p)
		_bounce[i] = maxf(_bounce[i] - delta * 4.0, 0.0)
		var squash := 1.0 + sin(_bounce[i] * PI) * 0.2
		var target := Vector3(s * squash, s / squash, s * squash)
		sap.scale = sap.scale.lerp(target, clampf(delta * 12.0, 0.0, 1.0))
		# Coin popups (batched so fast drones don't spam).
		_popup_timer[i] -= delta
		if _popup_accum[i] > 0.0 and _popup_timer[i] <= 0.0:
			_coin_popup(_sapling_spot[i], _popup_accum[i])
			_popup_accum[i] = 0.0
			_popup_timer[i] = 0.5
	# Drones hover above their sapling.
	for i in _drones.size():
		var d := _drones[i]
		if d == null:
			continue
		var phase := i * 1.3
		var target := _sapling_spot[i] + Vector3(cos(_t * 0.8 + phase) * 0.5, 2.3 + sin(_t * 2.0 + phase) * 0.12, sin(_t * 0.8 + phase) * 0.5)
		var to := target - d.position
		d.position += to * clampf(delta * 2.5, 0.0, 1.0)
		d.rotation.z = clampf(-to.x * 0.15, -0.4, 0.4)
		d.rotation.x = clampf(to.z * 0.15, -0.4, 0.4)
		for k in 4:
			var rotor := d.get_node("Rotor%d" % k) as Node3D
			rotor.rotation.y += delta * 30.0
	# Marker over the plant you are growing.
	var sel := GameState.selected
	if _saplings[sel].visible:
		var top := _sapling_spot[sel]
		var sap_s := _saplings[sel].scale.y
		_marker.visible = true
		_marker.position = top + Vector3(0, 0.0, 0)
		(_marker.get_child(1) as Node3D).position.y = 1.0 + sap_s * 2.6 + absf(sin(_t * 3.0)) * 0.35
		(_marker.get_child(0) as Node3D).rotation.y += delta * 0.8
	else:
		_marker.visible = false


func _build_marker() -> void:
	_marker = Node3D.new()
	add_child(_marker)
	var ring := LowPoly.Builder.new()
	ring.unshaded = true
	ring.shade_variance = 0.0
	for k in 18:
		var ang := TAU * k / 18.0
		ring.add(LowPoly.box(Vector3(0.28, 0.02, 0.08)), Color(1, 1, 1, 0.85), LowPoly.xf(Vector3(cos(ang) * 1.0, 0.08, sin(ang) * 1.0), Vector3(0, -rad_to_deg(ang) + 90.0, 0)))
	_marker.add_child(LowPoly.instance(ring.commit(), Vector3.ZERO, false))
	var arrow := LowPoly.Builder.new()
	arrow.add(LowPoly.cone(0.22, 0.4, 4), Color(1.0, 0.85, 0.25), LowPoly.xf(Vector3.ZERO, Vector3(180, 0, 0)))
	_marker.add_child(LowPoly.instance(arrow.commit(), Vector3.ZERO, false))


func _build_particles() -> void:
	_particles = CPUParticles3D.new()
	_particles.emitting = false
	_particles.one_shot = true
	_particles.amount = 16
	_particles.lifetime = 0.9
	_particles.explosiveness = 0.95
	_particles.direction = Vector3.UP
	_particles.spread = 70.0
	_particles.initial_velocity_min = 2.0
	_particles.initial_velocity_max = 3.5
	_particles.gravity = Vector3(0, -6, 0)
	_particles.mesh = LowPoly.mesh(LowPoly.box(Vector3(0.12, 0.03, 0.08)), Color(0.55, 0.85, 0.35))
	add_child(_particles)


func _coin_popup(p: Vector3, amount: float) -> void:
	var l := Label3D.new()
	l.text = "+%s" % GameData.format_number(amount)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 56
	l.outline_size = 12
	l.pixel_size = 0.008
	l.modulate = Color(1.0, 0.88, 0.3)
	l.outline_modulate = Color(0.3, 0.2, 0.0, 0.8)
	l.position = p + Vector3(0.0, 2.0, 0.0)
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 1.4, 1.0).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)
