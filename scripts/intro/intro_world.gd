class_name IntroWorld
extends Node3D
## The 3D set for the intro cinematic. It is the same island the player later
## restores, shown going from lush to ruined. Every "act" is a method the Intro
## timeline calls: cut_forest(), build_factories(), start_traffic(),
## spread_poison(), animals_leave(), earthquake(), tsunami(), storm(), ...

const FACTORY_UV := [Vector2(-4.5, -11.0), Vector2(3.5, -13.5), Vector2(6.5, -8.0)]
const ROAD_CENTER_UV := Vector2(-2.0, 8.0)
const ROAD_RADII := Vector2(6.5, 4.2)
const CAR_COUNT := 7

var terrain: Terrain
var ocean: MeshInstance3D
var river_mat: ShaderMaterial
var pond_mat: ShaderMaterial
var trees: Array[MeshInstance3D] = []
var stumps: Array[MeshInstance3D] = []
var animals: Array[Animal] = []
var factories: Array[Node3D] = []
var road: MeshInstance3D
var cars: Array[Node3D] = []
var car_speed := 0.0
var rain: CPUParticles3D
var wave: Node3D
var hope_set: Node3D

var _rng := RandomNumberGenerator.new()
var _water_shader: Shader
var _smoke_mat: StandardMaterial3D
var _car_phase: Array[float] = []
var _t := 0.0


func build() -> void:
	_rng.seed = 99
	_water_shader = Shader.new()
	_water_shader.code = World.WATER_SHADER
	terrain = Terrain.new()
	add_child(terrain)
	terrain.build()
	var m := terrain.material
	m.set_shader_parameter("dirt_color", Color(0.5, 0.4, 0.3))
	m.set_shader_parameter("grass_color", Color(0.3, 0.6, 0.28))
	m.set_shader_parameter("global_green", 1.0)
	m.set_shader_parameter("poison_color", Color(0.33, 0.33, 0.14))
	m.set_shader_parameter("poison_center", Terrain.to_world(1.0, -10.0))
	m.set_shader_parameter("poison_radius", 0.0)
	_build_water()
	_build_forest()
	_build_animals()
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.vertex_color_use_as_albedo = true
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.roughness = 1.0
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


# ------------------------------------------------------------------ queries (used by Animal)

func height_at(p: Vector3) -> float:
	return terrain.height_at(p)


func random_free_point() -> Vector3:
	return terrain.random_land_point(_rng, 0.25)


func uv_point(u: float, v: float) -> Vector3:
	var p := Terrain.to_world(u, v)
	p.y = terrain.height_at(p)
	return p


# ------------------------------------------------------------------ building the lush island

func _water_material(color: Color, flow: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _water_shader
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("flow", flow)
	mat.set_shader_parameter("foam", 0.25)
	return mat


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	var omat := StandardMaterial3D.new()
	omat.albedo_color = Color(0.24, 0.55, 0.82)
	omat.roughness = 0.6
	plane.material = omat
	ocean = MeshInstance3D.new()
	ocean.mesh = plane
	ocean.position.y = Terrain.OCEAN_Y
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ocean)
	river_mat = _water_material(Color(0.27, 0.6, 0.88, 0.9), 1.5)
	var river := MeshInstance3D.new()
	river.mesh = terrain.build_river_mesh()
	river.material_override = river_mat
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(river)
	var disc := CylinderMesh.new()
	disc.top_radius = Terrain.POND_R * 1.25
	disc.bottom_radius = Terrain.POND_R * 1.25
	disc.height = 0.02
	disc.radial_segments = 16
	pond_mat = _water_material(Color(0.22, 0.55, 0.75, 0.9), 0.4)
	var pond := MeshInstance3D.new()
	pond.mesh = disc
	pond.material_override = pond_mat
	pond.position = Terrain.to_world(Terrain.POND_UV.x, Terrain.POND_UV.y) + Vector3(0, Terrain.WATER_Y, 0)
	add_child(pond)


func _road_dist(uv: Vector2) -> float:
	var q := (uv - ROAD_CENTER_UV) / ROAD_RADII
	return absf(q.length() - 1.0)


func _build_forest() -> void:
	var ids := ["bush", "oak", "oak", "pine", "pine", "birch", "cherry", "sequoia"]
	var placed: Array[Vector2] = []
	var stump_mesh := LowPoly.Builder.new()
	stump_mesh.add(LowPoly.cylinder(0.2, 0.26, 0.28, 7), Color(0.5, 0.36, 0.24), LowPoly.xf(Vector3(0, 0.1, 0)))
	stump_mesh.add(LowPoly.cylinder(0.18, 0.18, 0.02, 7), Color(0.8, 0.67, 0.46), LowPoly.xf(Vector3(0, 0.25, 0)))
	var sm := stump_mesh.commit()
	for attempt in 2500:
		if placed.size() >= 230:
			break
		var p := terrain.random_land_point(_rng, 0.25)
		var uv := Terrain.to_uv(p)
		if uv.y < -24.0 or _road_dist(uv) < 0.22:
			continue
		var ok := true
		for f in FACTORY_UV:
			if uv.distance_to(f) < 2.4:
				ok = false
		for q in placed:
			if uv.distance_to(q) < 1.25:
				ok = false
				break
		if not ok:
			continue
		placed.append(uv)
		var t := LowPoly.instance(TreeFactory.tree_mesh(ids[_rng.randi() % ids.size()]), p)
		t.rotation.y = _rng.randf() * TAU
		t.scale = Vector3.ONE * _rng.randf_range(0.85, 1.15)
		add_child(t)
		trees.append(t)
		var s := LowPoly.instance(sm, p)
		s.visible = false
		add_child(s)
		stumps.append(s)
	# Cut the trees nearest to the factories / road first.
	var order: Array[int] = []
	for i in trees.size():
		order.append(i)
	var key := func(i: int) -> float:
		var uv := Terrain.to_uv(trees[i].position)
		return minf(uv.distance_to(Vector2(1.5, -11.0)), uv.distance_to(ROAD_CENTER_UV)) + _rng.randf() * 4.0
	var keys := {}
	for i in order:
		keys[i] = key.call(i)
	order.sort_custom(func(a: int, b: int) -> bool: return keys[a] < keys[b])
	var t2: Array[MeshInstance3D] = []
	var s2: Array[MeshInstance3D] = []
	for i in order:
		t2.append(trees[i])
		s2.append(stumps[i])
	trees = t2
	stumps = s2


func _build_animals() -> void:
	var kinds := {"deer": 4, "rabbit": 5, "bird": 7, "butterfly": 6}
	for kind in kinds:
		for k in kinds[kind]:
			var a := AnimalFactory.create(kind, self)
			add_child(a)
			var p := uv_point(_rng.randf_range(-8, 8), _rng.randf_range(-6, 14))
			if a.flyer:
				p.y += _rng.randf_range(a.height_range.x, a.height_range.y)
			a.position = p
			animals.append(a)


# ------------------------------------------------------------------ acts

## Trees fall one after another over `duration` seconds, leaving stumps.
func cut_forest(fraction: float, duration: float) -> void:
	var count := int(trees.size() * fraction)
	var cut := 0
	for i in trees.size():
		if not trees[i].visible or trees[i].has_meta("falling"):
			continue
		if cut >= count:
			break
		_fell(i, duration * float(cut) / maxf(count, 1))
		cut += 1


func _fell(i: int, delay: float) -> void:
	var t := trees[i]
	t.set_meta("falling", true)
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(t, "rotation:x", PI * 0.48, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: stumps[i].visible = true)
	tw.tween_property(t, "scale", Vector3.ONE * 0.01, 0.5).set_delay(0.3)
	tw.tween_callback(func() -> void: t.visible = false)


func fade_green(to: float, duration: float) -> void:
	var m := terrain.material
	var from: float = m.get_shader_parameter("global_green")
	create_tween().tween_method(func(v: float) -> void: m.set_shader_parameter("global_green", v), from, to, duration)


func build_factories(duration: float) -> void:
	for k in FACTORY_UV.size():
		var uv: Vector2 = FACTORY_UV[k]
		var f := _factory()
		var p := uv_point(uv.x, uv.y)
		f.position = p + Vector3(0, -4.0, 0)
		f.rotation.y = deg_to_rad(45.0 + _rng.randf_range(-12, 12))
		add_child(f)
		factories.append(f)
		var tw := create_tween()
		tw.tween_interval(duration * k / FACTORY_UV.size())
		tw.tween_property(f, "position:y", p.y - 0.1, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_callback(_set_smoke.bind(f, true))


func _set_smoke(f: Node3D, on: bool) -> void:
	for c in f.get_children():
		if c is CPUParticles3D:
			(c as CPUParticles3D).emitting = on


func _factory() -> Node3D:
	var root := Node3D.new()
	var b := LowPoly.Builder.new()
	var wall := Color(0.62, 0.6, 0.58)
	b.add(LowPoly.box(Vector3(3.2, 1.6, 2.2)), wall, LowPoly.xf(Vector3(0, 0.8, 0)))
	for k in 3:
		b.add(LowPoly.prism(Vector3(1.0, 0.6, 2.2)), Color(0.42, 0.42, 0.45), LowPoly.xf(Vector3(-1.07 + k * 1.07, 1.9, 0)))
	for k in 4:
		b.add(LowPoly.box(Vector3(0.4, 0.35, 0.05)), Color(0.95, 0.8, 0.35), LowPoly.xf(Vector3(-1.2 + k * 0.8, 0.9, 1.11)))
	b.add(LowPoly.box(Vector3(0.6, 0.9, 0.05)), Color(0.3, 0.28, 0.27), LowPoly.xf(Vector3(1.0, 0.45, 1.12)))
	var chimneys := [Vector3(-0.9, 0, -0.5), Vector3(0.6, 0, -0.6)]
	for c in chimneys:
		b.add(LowPoly.cylinder(0.22, 0.3, 3.8, 8), Color(0.72, 0.3, 0.25), LowPoly.xf(c + Vector3(0, 1.9, 0)))
		b.add(LowPoly.cylinder(0.24, 0.24, 0.25, 8), Color(0.92, 0.92, 0.9), LowPoly.xf(c + Vector3(0, 3.0, 0)))
		b.add(LowPoly.cylinder(0.24, 0.24, 0.25, 8), Color(0.92, 0.92, 0.9), LowPoly.xf(c + Vector3(0, 2.2, 0)))
	root.add_child(LowPoly.instance(b.commit()))
	for c in chimneys:
		var smoke := _smoke(Color(0.22, 0.2, 0.2, 0.85), Color(0.45, 0.42, 0.4, 0.0), 40, 5.0, 1.0)
		smoke.position = c + Vector3(0, 3.9, 0)
		root.add_child(smoke)
	return root


func _smoke(start: Color, end: Color, amount: int, lifetime: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	var sphere := SphereMesh.new()
	sphere.radius = 0.35 * size
	sphere.height = 0.7 * size
	sphere.radial_segments = 7
	sphere.rings = 4
	sphere.material = _smoke_mat
	p.mesh = sphere
	p.direction = Vector3(0.3, 1, 0.2)
	p.spread = 18.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0.35, 0.25, 0.15)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 3.0))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, start)
	g.set_color(1, end)
	p.color_ramp = g
	return p


func start_traffic() -> void:
	road = _build_road()
	add_child(road)
	road.scale = Vector3(1, 0.01, 1)
	create_tween().tween_property(road, "scale", Vector3.ONE, 0.8)
	var colors := [Color(0.85, 0.2, 0.2), Color(0.2, 0.45, 0.85), Color(0.95, 0.8, 0.2), Color(0.95, 0.95, 0.95), Color(0.3, 0.3, 0.32), Color(0.3, 0.7, 0.4), Color(0.9, 0.5, 0.15)]
	for k in CAR_COUNT:
		var car := _car(colors[k % colors.size()])
		add_child(car)
		_set_smoke(car, true)
		cars.append(car)
		_car_phase.append(TAU * k / CAR_COUNT)
		car.scale = Vector3.ONE * 0.01
		create_tween().tween_property(car, "scale", Vector3.ONE, 0.4).set_delay(0.6 + k * 0.15)
	car_speed = 0.35


func _road_point(a: float) -> Vector3:
	var uv := ROAD_CENTER_UV + Vector2(cos(a) * ROAD_RADII.x, sin(a) * ROAD_RADII.y)
	return uv_point(uv.x, uv.y)


func _build_road() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 96
	var asphalt := Color(0.25, 0.25, 0.27)
	for s in steps:
		var a0 := TAU * s / steps
		var a1 := TAU * (s + 1) / steps
		var pts: Array[Vector3] = []
		for a: float in [a0, a1]:
			var uv_c := ROAD_CENTER_UV + Vector2(cos(a) * ROAD_RADII.x, sin(a) * ROAD_RADII.y)
			var n := Vector2(cos(a) / ROAD_RADII.x, sin(a) / ROAD_RADII.y).normalized()
			for side: float in [-0.7, 0.7]:
				var uv: Vector2 = uv_c + n * side
				var p := Terrain.to_world(uv.x, uv.y)
				p.y = terrain.height_at(p) + 0.06
				pts.append(p)
		for tri in [[0, 2, 3], [0, 3, 1]]:
			for i in tri:
				st.set_normal(Vector3.UP)
				st.set_color(asphalt)
				st.add_vertex(pts[i])
		if s % 4 == 0:   # dashed centre line
			var c0: Vector3 = (pts[0] + pts[1]) * 0.5 + Vector3(0, 0.01, 0)
			var c1: Vector3 = (pts[2] + pts[3]) * 0.5 + Vector3(0, 0.01, 0)
			var side: Vector3 = (pts[1] - pts[0]).normalized() * 0.06
			for v in [c0 - side, c1 - side, c1 + side, c0 - side, c1 + side, c0 + side]:
				st.set_normal(Vector3.UP)
				st.set_color(Color(0.95, 0.9, 0.6))
				st.add_vertex(v)
	var mesh := st.commit()
	var mat := LowPoly.material().duplicate() as StandardMaterial3D
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func _car(color: Color) -> Node3D:
	var root := Node3D.new()
	var b := LowPoly.Builder.new()
	b.add(LowPoly.box(Vector3(0.5, 0.22, 0.95)), color, LowPoly.xf(Vector3(0, 0.2, 0)))
	b.add(LowPoly.box(Vector3(0.44, 0.2, 0.5)), color.lightened(0.15), LowPoly.xf(Vector3(0, 0.4, -0.05)))
	b.add(LowPoly.box(Vector3(0.45, 0.14, 0.04)), Color(0.55, 0.75, 0.9), LowPoly.xf(Vector3(0, 0.41, 0.2)))
	for x in [-0.24, 0.24]:
		for z in [-0.3, 0.3]:
			b.add(LowPoly.cylinder(0.1, 0.1, 0.08, 7), Color(0.12, 0.12, 0.12), LowPoly.xf(Vector3(x, 0.1, z), Vector3(0, 0, 90)))
	root.add_child(LowPoly.instance(b.commit()))
	var exhaust := _smoke(Color(0.3, 0.3, 0.3, 0.7), Color(0.5, 0.5, 0.5, 0.0), 14, 1.8, 0.45)
	exhaust.position = Vector3(0.15, 0.15, -0.5)
	exhaust.direction = Vector3(0, 0.6, -1)
	root.add_child(exhaust)
	return root


func spread_poison(radius: float, duration: float) -> void:
	var m := terrain.material
	var from: float = m.get_shader_parameter("poison_radius")
	create_tween().tween_method(func(v: float) -> void: m.set_shader_parameter("poison_radius", v), from, radius, duration)
	var murky := Color(0.3, 0.33, 0.18, 0.95)
	_tween_water(river_mat, murky, duration)
	_tween_water(pond_mat, murky, duration)


func _tween_water(mat: ShaderMaterial, to: Color, duration: float) -> void:
	var from: Color = mat.get_shader_parameter("color")
	var fade := func(t: float) -> void:
		mat.set_shader_parameter("color", from.lerp(to, t))
		mat.set_shader_parameter("foam", lerpf(0.25, 0.05, t))
	create_tween().tween_method(fade, 0.0, 1.0, duration)


func animals_leave(duration: float) -> void:
	for k in animals.size():
		var a := animals[k]
		if not is_instance_valid(a):
			continue
		var to: Vector3
		if a.flyer:
			to = a.position + Vector3(_rng.randf_range(-8, 8), 22.0, _rng.randf_range(-8, 8))
		else:
			to = terrain.shore_point(_rng)
		var delay := duration * float(k) / animals.size()
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(_send_away.bind(a, to))


func _send_away(a: Animal, to: Vector3) -> void:
	if is_instance_valid(a):
		a.leave(to)


func earthquake() -> void:
	car_speed = 0.0
	# Cracks spread across the ground.
	for k in 6:
		var start := Vector2(_rng.randf_range(-7, 7), _rng.randf_range(-14, 12))
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		_crack(start, dir, 9, 0.2 + k * 0.25)
	# Factories shake, tilt and collapse in clouds of dust.
	for k in factories.size():
		var f := factories[k]
		var tw := create_tween()
		tw.tween_interval(0.8 + k * 0.5)
		for j in 6:
			tw.tween_property(f, "rotation:z", 0.06 * (1 if j % 2 == 0 else -1), 0.08)
		tw.tween_callback(_collapse_dust.bind(f))
		tw.tween_property(f, "rotation:z", deg_to_rad(28.0 * (1 if k % 2 == 0 else -1)), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(f, "position:y", f.position.y - 1.4, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Remaining trees fall too.
	cut_forest(1.0, 2.5)


func _collapse_dust(f: Node3D) -> void:
	var dust := _smoke(Color(0.55, 0.48, 0.38, 0.8), Color(0.6, 0.55, 0.45, 0.0), 30, 2.5, 1.6)
	dust.one_shot = true
	dust.explosiveness = 0.8
	dust.direction = Vector3.UP
	dust.spread = 80.0
	dust.initial_velocity_min = 1.5
	dust.initial_velocity_max = 3.0
	dust.position = f.position + Vector3(0, 0.5, 0)
	add_child(dust)
	dust.emitting = true
	_set_smoke(f, false)


func _crack(start: Vector2, dir: Vector2, segments: int, delay: float) -> void:
	var p := start
	var tw := create_tween()
	tw.tween_interval(delay)
	for s in segments:
		dir = dir.rotated(_rng.randf_range(-0.6, 0.6))
		var length := _rng.randf_range(0.7, 1.3)
		var q := p + dir * length
		var a := uv_point(p.x, p.y)
		var b := uv_point(q.x, q.y)
		var seg := MeshInstance3D.new()
		var width := 0.16 * (1.0 - float(s) / segments) + 0.05
		seg.mesh = LowPoly.mesh(LowPoly.box(Vector3(width, 0.04, 1.0)), Color(0.12, 0.08, 0.06), LowPoly.xf(Vector3(0, 0, 0.5)))
		var dir3 := (b - a).normalized()
		# Basis.looking_at points -Z at the target; aim -Z backwards so the box (+Z) runs from a to b.
		seg.transform = Transform3D(Basis.looking_at(-dir3, Vector3.UP), a + Vector3(0, 0.04, 0))
		var full := a.distance_to(b)
		seg.scale = Vector3(1, 1, 0.001)
		add_child(seg)
		tw.tween_property(seg, "scale", Vector3(1, 1, full), 0.12)
		p = q


func tsunami(duration: float) -> void:
	wave = _build_wave()
	add_child(wave)
	wave.rotation_degrees.y = 45.0
	var start := Terrain.to_world(0, -48)
	var end := Terrain.to_world(0, 42)
	wave.position = start + Vector3(0, Terrain.OCEAN_Y, 0)
	wave.scale = Vector3(1, 0.2, 1)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(wave, "position", end + Vector3(0, Terrain.OCEAN_Y, 0), duration)
	tw.tween_property(wave, "scale", Vector3(1, 1.9, 1), duration * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(wave, "scale", Vector3(1, 0.3, 1), duration * 0.3).set_delay(duration * 0.7)
	# After the wave, the sea stays higher and floods the low land.
	var tw2 := create_tween()
	tw2.tween_interval(duration * 0.45)
	tw2.tween_property(ocean, "position:y", 0.45, duration * 0.8).set_trans(Tween.TRANS_SINE)
	tw2.tween_callback(func() -> void: wave.visible = false)


func _build_wave() -> Node3D:
	# Cross-section of a breaking wave (z forward, y up), extruded along x.
	var profile := [Vector2(-7, 0), Vector2(-4.5, 1.2), Vector2(-2.4, 2.8), Vector2(-0.9, 4.1), Vector2(0.3, 4.8),
		Vector2(1.3, 4.7), Vector2(1.9, 4.1), Vector2(1.7, 3.5), Vector2(1.0, 3.5), Vector2(0.6, 2.6), Vector2(1.0, 1.2), Vector2(1.8, 0)]
	var colors := [Color(0.08, 0.26, 0.5), Color(0.1, 0.32, 0.58), Color(0.14, 0.4, 0.68), Color(0.25, 0.55, 0.8), Color(0.55, 0.75, 0.9),
		Color(0.75, 0.88, 0.97), Color(0.95, 0.98, 1.0), Color(0.85, 0.93, 0.98), Color(0.4, 0.62, 0.78), Color(0.22, 0.47, 0.67), Color(0.18, 0.42, 0.62), Color(0.15, 0.38, 0.58)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xs := []
	var x := -34.0
	while x <= 34.0:
		xs.append(x)
		x += 2.0
	for xi in xs.size() - 1:
		var x0: float = xs[xi]
		var x1: float = xs[xi + 1]
		var w0 := sin(x0 * 0.35) * 0.6
		var w1 := sin(x1 * 0.35) * 0.6
		for k in profile.size() - 1:
			var a: Vector2 = profile[k]
			var b: Vector2 = profile[k + 1]
			var p00 := Vector3(x0, a.y, a.x + w0)
			var p10 := Vector3(x1, a.y, a.x + w1)
			var p01 := Vector3(x0, b.y, b.x + w0)
			var p11 := Vector3(x1, b.y, b.x + w1)
			var col: Color = colors[k]
			for tri in [[p00, p10, p11], [p00, p11, p01]]:
				var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				if n.z + n.y * 0.5 < 0.0:
					n = -n
				for v in tri:
					st.set_normal(n)
					st.set_color(col)
					st.add_vertex(v)
	var mesh := st.commit()
	var mat := LowPoly.material().duplicate() as StandardMaterial3D
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)
	var spray := CPUParticles3D.new()
	spray.amount = 120
	spray.lifetime = 1.0
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	spray.emission_box_extents = Vector3(30, 0.2, 0.5)
	spray.position = Vector3(0, 4.7, 1.0)
	spray.direction = Vector3(0, 1, 1)
	spray.spread = 35.0
	spray.initial_velocity_min = 2.0
	spray.initial_velocity_max = 4.0
	spray.gravity = Vector3(0, -6, 0)
	spray.mesh = LowPoly.mesh(LowPoly.sphere(0.12, 0.24, 5, 3), Color(0.95, 0.98, 1.0))
	root.add_child(spray)
	return root


func storm(on: bool) -> void:
	if rain == null:
		rain = CPUParticles3D.new()
		rain.amount = 900
		rain.lifetime = 0.9
		rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		rain.emission_box_extents = Vector3(26, 0.5, 26)
		rain.position = Vector3(0, 16, 0)
		rain.direction = Vector3(0.15, -1, 0.1)
		rain.spread = 3.0
		rain.initial_velocity_min = 18.0
		rain.initial_velocity_max = 22.0
		rain.gravity = Vector3(0, -10, 0)
		var drop := LowPoly.Builder.new()
		drop.unshaded = true
		drop.add(LowPoly.box(Vector3(0.025, 0.7, 0.025)), Color(0.75, 0.82, 0.92, 0.7))
		rain.mesh = drop.commit()
		add_child(rain)
	rain.emitting = on


## A jagged lightning bolt that flashes for a moment.
func lightning_bolt(at_uv: Vector2) -> void:
	var b := LowPoly.Builder.new()
	b.unshaded = true
	b.shade_variance = 0.0
	var ground := uv_point(at_uv.x, at_uv.y)
	var p := ground + Vector3(_rng.randf_range(-2, 2), 18.0, _rng.randf_range(-2, 2))
	while p.y > ground.y + 0.3:
		var q := p + Vector3(_rng.randf_range(-1.0, 1.0), -_rng.randf_range(1.2, 2.2), _rng.randf_range(-1.0, 1.0))
		q.y = maxf(q.y, ground.y)
		var mid := (p + q) * 0.5
		var seg_len := p.distance_to(q)
		var basis := Basis.looking_at((q - p).normalized(), Vector3.FORWARD if absf((q - p).normalized().y) > 0.99 else Vector3.UP)
		b.add(LowPoly.box(Vector3(0.12, 0.12, seg_len)), Color(0.9, 0.95, 1.0), Transform3D(basis, mid))
		p = q
	var bolt := LowPoly.instance(b.commit(), Vector3.ZERO, false)
	add_child(bolt)
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(func() -> void: bolt.visible = false)
	tw.tween_interval(0.06)
	tw.tween_callback(func() -> void: bolt.visible = true)
	tw.tween_interval(0.1)
	tw.tween_callback(bolt.queue_free)


## The final hopeful shot: one small sapling on a patch of soil.
func build_hope_set() -> Node3D:
	hope_set = Node3D.new()
	hope_set.position = Vector3(0, 30, 0)   # away from the ruined island
	var b := LowPoly.Builder.new()
	b.add(LowPoly.cylinder(0.95, 1.15, 0.35, 10), Color(0.3, 0.21, 0.14), LowPoly.xf(Vector3(0, -0.17, 0)), 0.08)
	for k in 7:
		var ang := TAU * k / 7.0
		b.add(LowPoly.sphere(0.09, 0.11, 5, 2), Color(0.5, 0.5, 0.5), LowPoly.xf(Vector3(cos(ang) * 0.88, 0.02, sin(ang) * 0.88)))
	hope_set.add_child(LowPoly.instance(b.commit()))
	var sap := LowPoly.Builder.new()
	sap.add(LowPoly.cylinder(0.025, 0.035, 0.55, 5), Color(0.45, 0.32, 0.2), LowPoly.xf(Vector3(0, 0.27, 0)))
	sap.add(LowPoly.sphere(0.16, 0.06, 6, 2), Color(0.4, 0.78, 0.35), LowPoly.xf(Vector3(-0.14, 0.45, 0), Vector3(0, 0, 25)))
	sap.add(LowPoly.sphere(0.16, 0.06, 6, 2), Color(0.45, 0.82, 0.38), LowPoly.xf(Vector3(0.14, 0.52, 0), Vector3(0, 0, -25)))
	sap.add(LowPoly.sphere(0.12, 0.05, 6, 2), Color(0.5, 0.85, 0.42), LowPoly.xf(Vector3(0, 0.62, 0.05), Vector3(20, 0, 0)))
	var sapling := LowPoly.instance(sap.commit())
	sapling.name = "Sapling"
	hope_set.add_child(sapling)
	var motes := CPUParticles3D.new()
	motes.amount = 24
	motes.lifetime = 3.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 1.2
	motes.direction = Vector3.UP
	motes.spread = 20.0
	motes.initial_velocity_min = 0.2
	motes.initial_velocity_max = 0.5
	motes.gravity = Vector3.ZERO
	var mote := LowPoly.Builder.new()
	mote.unshaded = true
	mote.add(LowPoly.sphere(0.03, 0.06, 4, 2), Color(1.0, 0.95, 0.6, 0.9))
	motes.mesh = mote.commit()
	hope_set.add_child(motes)
	var light := OmniLight3D.new()
	light.position = Vector3(0.5, 2.0, 1.0)
	light.light_color = Color(1.0, 0.9, 0.7)
	light.light_energy = 1.0
	light.omni_range = 6.0
	hope_set.add_child(light)
	hope_set.visible = false
	add_child(hope_set)
	return hope_set


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	_t += delta
	for k in cars.size():
		_car_phase[k] += car_speed * delta
		var a := _car_phase[k]
		var p := _road_point(a)
		var ahead := _road_point(a + 0.05)
		var car := cars[k]
		car.position = p + Vector3(0, 0.05, 0)
		var dir := ahead - p
		if dir.length_squared() > 0.0001:
			car.rotation.y = atan2(dir.x, dir.z)
	if hope_set and hope_set.visible:
		var s := hope_set.get_node("Sapling") as Node3D
		s.rotation.z = sin(_t * 1.5) * 0.06
