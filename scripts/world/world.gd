class_name World
extends Node3D
## The island: ground, plantation zones, ecosystem features and animals.
## Reacts to GameState signals and transforms the land at every milestone.

const ISLAND_HALF := Vector2(23.0, 18.0)   ## half size in x / z
## Plot position per plant level: the first plant sits front-centre where new players look.
const ZONE_POSITIONS := [
	Vector3(0, 0, 5.5), Vector3(-10, 0, 5.5), Vector3(10, 0, 5.5),
	Vector3(0, 0, -9.5), Vector3(-10, 0, -9.5), Vector3(10, 0, -9.5),
]
const RIVER_Z := -0.75
const RIVER_HALF_WIDTH := 1.1
const POND_CENTER := Vector3(18.5, 0, 8.0)
const POND_RADIUS := 2.8
const MOUNTAINS := [
	[Vector3(-19.5, 0, -15.0), 3.6, 7.0], [Vector3(-12.0, 0, -16.5), 2.8, 5.0],
	[Vector3(-3.5, 0, -17.0), 2.6, 4.2], [Vector3(-20.5, 0, -6.0), 2.8, 5.2],
	[Vector3(5.0, 0, -17.2), 2.2, 3.6], [Vector3(-21.0, 0, 3.0), 2.0, 3.4],
]

const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(0.25, 0.58, 0.88, 0.85);
uniform float flow = 1.5;
uniform float foam = 0.3;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wp.x * 1.3 + TIME * 2.0) * 0.03 + cos(wp.z * 2.1 + TIME * 1.6) * 0.03;
}
void fragment() {
	float s = sin(wp.x * 2.0 - TIME * flow + sin(wp.z * 3.0) * 1.2) * 0.5 + 0.5;
	float stripe = smoothstep(0.93, 1.0, s);
	ALBEDO = color.rgb + vec3(stripe * foam);
	ALPHA = color.a;
	ROUGHNESS = 0.15;
}
"""

var zones: Array[Zone] = []
var ground_mat: StandardMaterial3D
var features := {}          ## feature name -> Node3D
var animals_root: Node3D
var decor_root: Node3D
var _rng := RandomNumberGenerator.new()


func build() -> void:
	_rng.seed = 42
	_build_ground()
	decor_root = Node3D.new()
	decor_root.name = "Decor"
	add_child(decor_root)
	animals_root = Node3D.new()
	animals_root.name = "Animals"
	add_child(animals_root)
	_build_zones()
	_build_barren_decor()
	apply_state(false)

	GameState.clicked.connect(_on_clicked)
	GameState.trees_completed.connect(_on_trees_completed)
	GameState.plant_unlocked.connect(func(i: int) -> void: zones[i].on_unlocked())
	GameState.machine_changed.connect(func(i: int) -> void: zones[i].on_machine_changed())
	GameState.stage_changed.connect(_on_stage_changed)
	GameState.game_reset.connect(_on_game_reset)


## Builds every feature/animal for stages already reached (used on load / reset).
func apply_state(animate: bool) -> void:
	var st: Dictionary = GameData.STAGES[GameState.stage]
	ground_mat.albedo_color = st["ground"]
	for s in range(1, GameState.stage + 1):
		_unlock_stage_content(s, animate)


func _on_stage_changed(stage: int) -> void:
	var st: Dictionary = GameData.STAGES[stage]
	create_tween().tween_property(ground_mat, "albedo_color", st["ground"], 2.0)
	_unlock_stage_content(stage, true)


func _on_game_reset() -> void:
	for f in features.values():
		(f as Node).queue_free()
	features.clear()
	for a in animals_root.get_children():
		a.queue_free()
	for z in zones:
		z.rebuild_from_state()
	apply_state(false)


func _unlock_stage_content(stage: int, animate: bool) -> void:
	var st: Dictionary = GameData.STAGES[stage]
	var feature: String = st["feature"]
	if feature != "" and not features.has(feature):
		var node := Node3D.new()
		node.name = feature.capitalize()
		add_child(node)
		features[feature] = node
		match feature:
			"grass": _build_grass(node, animate)
			"river": _build_river(node, animate)
			"flowers": _build_flowers(node, animate)
			"pond": _build_pond(node, animate)
			"mountains": _build_mountains(node, animate)
			"jungle": _build_jungle(node, animate)
			"rainbow": _build_rainbow(node, animate)
	var kind: String = st["animal"]
	var count: int = st["count"]
	for k in count:
		spawn_animal(kind, animate, k * 0.35 + (1.5 if animate else 0.0))


func spawn_animal(kind: String, animate: bool, delay: float = 0.0) -> Animal:
	if kind == "":
		return null
	var a := AnimalFactory.create(kind, self)
	animals_root.add_child(a)
	if animate:
		var from: Vector3
		if a.flyer:
			from = Vector3(_rng.randf_range(-15, 15), 10.0, _rng.randf_range(8, 16))
		else:
			from = _edge_point()
		a.arrive(from, delay)
	else:
		var p := random_free_point()
		if a.flyer:
			p.y = _rng.randf_range(a.height_range.x, a.height_range.y)
		a.position = p
	return a


func _edge_point() -> Vector3:
	# Animals walk in from the front edges of the island (towards the camera).
	if _rng.randf() < 0.5:
		return Vector3(_rng.randf_range(-ISLAND_HALF.x + 2, ISLAND_HALF.x - 2), 0, ISLAND_HALF.y - 0.5)
	return Vector3(ISLAND_HALF.x - 0.5, 0, _rng.randf_range(-ISLAND_HALF.y + 2, ISLAND_HALF.y - 2))


# ------------------------------------------------------------------ queries

## Random spot on open ground (not in a zone, river, pond or mountain).
func random_free_point(margin: float = 1.5) -> Vector3:
	var p := Vector3.ZERO
	for attempt in 40:
		p = Vector3(_rng.randf_range(-ISLAND_HALF.x + margin, ISLAND_HALF.x - margin), 0,
				_rng.randf_range(-ISLAND_HALF.y + margin, ISLAND_HALF.y - margin))
		if is_free(p):
			return p
	return p


func is_free(p: Vector3) -> bool:
	for z in zones:
		if z.blocked_rect().has_point(Vector2(p.x, p.z)):
			return false
	if absf(p.z - RIVER_Z) < RIVER_HALF_WIDTH + 0.5:
		return false
	if Vector2(p.x - POND_CENTER.x, p.z - POND_CENTER.z).length() < POND_RADIUS + 0.6:
		return false
	for m in MOUNTAINS:
		var c: Vector3 = m[0]
		var r: float = m[1]
		if Vector2(p.x - c.x, p.z - c.z).length() < r + 0.5:
			return false
	return true


func zone_at(p: Vector3) -> Zone:
	for z in zones:
		if z.contains_point(p):
			return z
	return null


# ------------------------------------------------------------------ events

func _on_clicked(i: int) -> void:
	zones[i].on_click()


func _on_trees_completed(i: int, count: int, earned: float, _by_machine: bool) -> void:
	zones[i].on_trees_completed(count, earned)


# ------------------------------------------------------------------ building

func _build_ground() -> void:
	ground_mat = StandardMaterial3D.new()
	ground_mat.vertex_color_use_as_albedo = true
	ground_mat.roughness = 1.0
	var plane := PlaneMesh.new()
	plane.size = ISLAND_HALF * 2.0
	plane.subdivide_width = 22
	plane.subdivide_depth = 18
	var b := LowPoly.Builder.new()
	b.shade_variance = 0.09
	b.add(plane, Color(1, 1, 1))
	var top := b.commit()
	top.surface_set_material(0, ground_mat)
	var top_mi := LowPoly.instance(top, Vector3.ZERO, false)
	top_mi.name = "Ground"
	add_child(top_mi)
	# Dirt cliff sides of the island.
	var sides := LowPoly.Builder.new()
	sides.add(LowPoly.box(Vector3(ISLAND_HALF.x * 2.0, 3.0, ISLAND_HALF.y * 2.0)), Color(0.48, 0.33, 0.22), LowPoly.xf(Vector3(0, -1.52, 0)))
	sides.add(LowPoly.box(Vector3(ISLAND_HALF.x * 2.0 - 1.0, 1.0, ISLAND_HALF.y * 2.0 - 1.0)), Color(0.4, 0.4, 0.42), LowPoly.xf(Vector3(0, -3.3, 0)))
	add_child(LowPoly.instance(sides.commit(), Vector3.ZERO, false))
	# Ocean around the island.
	var ocean := PlaneMesh.new()
	ocean.size = Vector2(400, 400)
	var omat := StandardMaterial3D.new()
	omat.albedo_color = Color(0.2, 0.46, 0.74)
	omat.roughness = 0.7
	ocean.material = omat
	var ocean_mi := MeshInstance3D.new()
	ocean_mi.mesh = ocean
	ocean_mi.position.y = -1.6
	ocean_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ocean_mi)


static var _shader_cache: Shader
static func _water_shader() -> Shader:
	if _shader_cache == null:
		_shader_cache = Shader.new()
		_shader_cache.code = WATER_SHADER
	return _shader_cache


func _build_zones() -> void:
	for i in mini(GameData.PLANTS.size(), ZONE_POSITIONS.size()):
		var z := Zone.new()
		z.name = "Zone_%s" % GameData.PLANTS[i]["id"]
		z.position = ZONE_POSITIONS[i]
		add_child(z)
		z.setup(i)
		zones.append(z)


func _build_barren_decor() -> void:
	# Rocks and old tree stumps: a reminder of the forest that was cut down.
	var b := LowPoly.Builder.new()
	for k in 26:
		var p := random_free_point()
		var s := _rng.randf_range(0.2, 0.55)
		b.add(LowPoly.sphere(s, s * 1.2, 6, 3), Color(0.55, 0.55, 0.56), LowPoly.xf(p + Vector3(0, s * 0.2, 0), Vector3(0, _rng.randf() * 360.0, 0)), s * 0.4)
	for k in 14:
		var p := random_free_point()
		b.add(LowPoly.cylinder(0.22, 0.28, 0.3, 7), Color(0.5, 0.36, 0.24), LowPoly.xf(p + Vector3(0, 0.15, 0)))
		b.add(LowPoly.cylinder(0.2, 0.2, 0.02, 7), Color(0.78, 0.65, 0.45), LowPoly.xf(p + Vector3(0, 0.31, 0)))
	decor_root.add_child(LowPoly.instance(b.commit()))


## Pops children in one after another for a "the world is changing" feeling.
func _pop_in(nodes: Array, total_time: float = 2.0) -> void:
	var step := total_time / maxf(nodes.size(), 1.0)
	for k in nodes.size():
		var n: Node3D = nodes[k]
		var target := n.scale
		n.scale = Vector3.ONE * 0.01
		var tw := n.create_tween()
		tw.tween_interval(k * step)
		tw.tween_property(n, "scale", target, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _scatter(parent: Node3D, count: int, maker: Callable, animate: bool) -> void:
	var nodes: Array = []
	for k in count:
		var p := random_free_point(1.0)
		var mi := LowPoly.instance(maker.call(k) as Mesh, p, false)
		mi.rotation.y = _rng.randf() * TAU
		var s := _rng.randf_range(0.8, 1.25)
		mi.scale = Vector3(s, s, s)
		parent.add_child(mi)
		nodes.append(mi)
	if animate:
		_pop_in(nodes, 2.5)


func _build_grass(node: Node3D, animate: bool) -> void:
	var meshes: Array[ArrayMesh] = []
	for v in 3:
		var b := LowPoly.Builder.new()
		var g := Color(0.35, 0.65, 0.25).lightened(v * 0.07)
		b.add(LowPoly.cone(0.08, 0.45, 3), g, LowPoly.xf(Vector3(0, 0.22, 0), Vector3(0, 0, 12)))
		b.add(LowPoly.cone(0.08, 0.35, 3), g, LowPoly.xf(Vector3(0.1, 0.17, 0.05), Vector3(0, 0, -18)))
		b.add(LowPoly.cone(0.07, 0.3, 3), g.darkened(0.1), LowPoly.xf(Vector3(-0.08, 0.15, -0.06), Vector3(15, 0, 0)))
		meshes.append(b.commit())
	_scatter(node, 140, func(k: int) -> Mesh: return meshes[k % meshes.size()], animate)


func _build_flowers(node: Node3D, animate: bool) -> void:
	var colors := [Color(1, 0.4, 0.5), Color(1, 0.85, 0.2), Color(0.7, 0.5, 1.0), Color(1, 1, 1), Color(1, 0.55, 0.2)]
	var meshes: Array[ArrayMesh] = []
	for c in colors:
		var b := LowPoly.Builder.new()
		for f in 3:
			var off := Vector3(cos(f * 2.1) * 0.15, 0, sin(f * 2.1) * 0.15)
			b.add(LowPoly.cylinder(0.015, 0.015, 0.35, 3), Color(0.3, 0.6, 0.25), LowPoly.xf(off + Vector3(0, 0.17, 0)))
			b.add(LowPoly.sphere(0.08, 0.08, 5, 2), c, LowPoly.xf(off + Vector3(0, 0.37, 0)))
			b.add(LowPoly.sphere(0.03, 0.05, 4, 2), Color(1, 0.9, 0.3), LowPoly.xf(off + Vector3(0, 0.41, 0)))
		meshes.append(b.commit())
	_scatter(node, 90, func(k: int) -> Mesh: return meshes[k % meshes.size()], animate)


func _build_river(node: Node3D, animate: bool) -> void:
	var length := ISLAND_HALF.x * 2.0
	# The water grows from the left edge of the island, like a river starting to flow.
	var water_root := Node3D.new()
	water_root.position = Vector3(-ISLAND_HALF.x, 0, RIVER_Z)
	node.add_child(water_root)
	var plane := PlaneMesh.new()
	plane.size = Vector2(length + 0.4, RIVER_HALF_WIDTH * 2.0)
	plane.subdivide_width = 40
	plane.subdivide_depth = 3
	var mat := ShaderMaterial.new()
	mat.shader = _water_shader()
	plane.material = mat
	var water := MeshInstance3D.new()
	water.mesh = plane
	water.position = Vector3(length * 0.5, 0.06, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_root.add_child(water)
	# Banks: sand strips + stones, and two little bridges.
	var b := LowPoly.Builder.new()
	for s in [-1.0, 1.0]:
		b.add(LowPoly.box(Vector3(length, 0.05, 0.35)), Color(0.85, 0.78, 0.55), LowPoly.xf(Vector3(0, 0.03, RIVER_Z + s * (RIVER_HALF_WIDTH + 0.12))))
	for k in 40:
		var x := _rng.randf_range(-ISLAND_HALF.x + 0.5, ISLAND_HALF.x - 0.5)
		var s := 1.0 if _rng.randf() < 0.5 else -1.0
		var r := _rng.randf_range(0.12, 0.25)
		b.add(LowPoly.sphere(r, r * 1.2, 5, 3), Color(0.6, 0.6, 0.62), LowPoly.xf(Vector3(x, 0.05, RIVER_Z + s * (RIVER_HALF_WIDTH + 0.15))), r * 0.3)
	var banks := LowPoly.instance(b.commit(), Vector3.ZERO, false)
	node.add_child(banks)
	var bridges: Array = []
	for bx in [-5.0, 5.0]:
		var bb := LowPoly.Builder.new()
		for k in 7:
			bb.add(LowPoly.box(Vector3(0.28, 0.08, 3.2)), Color(0.62, 0.42, 0.25).darkened((k % 2) * 0.08), LowPoly.xf(Vector3((k - 3) * 0.3, 0.25, 0)))
		for s in [-1.0, 1.0]:
			bb.add(LowPoly.box(Vector3(2.2, 0.08, 0.08)), Color(0.5, 0.33, 0.2), LowPoly.xf(Vector3(0, 0.6, s * 1.5)))
			for px in [-1.0, 0.0, 1.0]:
				bb.add(LowPoly.box(Vector3(0.08, 0.45, 0.08)), Color(0.5, 0.33, 0.2), LowPoly.xf(Vector3(px, 0.4, s * 1.5)))
		var bridge := LowPoly.instance(bb.commit(), Vector3(bx, 0, RIVER_Z))
		node.add_child(bridge)
		bridges.append(bridge)
	if animate:
		water_root.scale = Vector3(0.01, 1, 1)
		var tw := create_tween()
		tw.tween_property(water_root, "scale", Vector3.ONE, 3.0).set_trans(Tween.TRANS_SINE)
		banks.scale = Vector3(1, 0.01, 1)
		create_tween().tween_property(banks, "scale", Vector3.ONE, 1.0)
		_pop_in(bridges, 3.0)


func _build_pond(node: Node3D, animate: bool) -> void:
	var b := LowPoly.Builder.new()
	b.add(LowPoly.cylinder(POND_RADIUS + 0.3, POND_RADIUS + 0.4, 0.06, 12), Color(0.85, 0.78, 0.55), LowPoly.xf(POND_CENTER + Vector3(0, 0.02, 0)))
	for k in 16:
		var ang := TAU * k / 16.0 + _rng.randf() * 0.2
		var r := _rng.randf_range(0.18, 0.35)
		b.add(LowPoly.sphere(r, r * 1.3, 6, 3), Color(0.58, 0.58, 0.6), LowPoly.xf(POND_CENTER + Vector3(cos(ang), 0, sin(ang)) * (POND_RADIUS + 0.35) + Vector3(0, 0.08, 0)), r * 0.3)
	for k in 5:
		var ang := _rng.randf() * TAU
		var d := _rng.randf_range(0.5, POND_RADIUS - 0.6)
		b.add(LowPoly.cylinder(0.3, 0.3, 0.02, 7), Color(0.3, 0.65, 0.3), LowPoly.xf(POND_CENTER + Vector3(cos(ang) * d, 0.12, sin(ang) * d)))
		if k % 2 == 0:
			b.add(LowPoly.sphere(0.08, 0.1, 5, 2), Color(1, 0.7, 0.85), LowPoly.xf(POND_CENTER + Vector3(cos(ang) * d, 0.17, sin(ang) * d)))
	# reeds
	for k in 10:
		var ang := _rng.randf() * TAU
		var p := POND_CENTER + Vector3(cos(ang), 0, sin(ang)) * (POND_RADIUS + 0.1)
		b.add(LowPoly.cylinder(0.02, 0.03, 0.8, 3), Color(0.4, 0.6, 0.25), LowPoly.xf(p + Vector3(0, 0.4, 0)))
		b.add(LowPoly.cylinder(0.05, 0.05, 0.2, 4), Color(0.45, 0.3, 0.18), LowPoly.xf(p + Vector3(0, 0.75, 0)))
	var rim := LowPoly.instance(b.commit(), Vector3.ZERO, false)
	node.add_child(rim)
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = POND_RADIUS
	water_mesh.bottom_radius = POND_RADIUS
	water_mesh.height = 0.04
	water_mesh.radial_segments = 14
	water_mesh.rings = 1
	var mat := ShaderMaterial.new()
	mat.shader = _water_shader()
	mat.set_shader_parameter("color", Color(0.22, 0.55, 0.75, 0.9))
	mat.set_shader_parameter("flow", 0.4)
	water_mesh.material = mat
	var water := MeshInstance3D.new()
	water.mesh = water_mesh
	water.position = POND_CENTER + Vector3(0, 0.08, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(water)
	if animate:
		_pop_in([rim, water], 0.8)


func _build_mountains(node: Node3D, animate: bool) -> void:
	for m in MOUNTAINS:
		var c: Vector3 = m[0]
		var r: float = m[1]
		var h: float = m[2]
		var b := LowPoly.Builder.new()
		b.shade_variance = 0.1
		b.add(LowPoly.cone(r, h, 7), Color(0.5, 0.52, 0.55), LowPoly.xf(Vector3(0, h * 0.5, 0)), 0.35)
		b.add(LowPoly.cone(r * 0.32, h * 0.32, 7), Color(0.96, 0.97, 1.0), LowPoly.xf(Vector3(0, h * 0.84 + 0.02, 0)), 0.05)
		b.add(LowPoly.cone(r * 0.7, h * 0.45, 6), Color(0.35, 0.55, 0.3), LowPoly.xf(Vector3(r * 0.5, h * 0.22, r * 0.3), Vector3(0, 30, 0)), 0.2)
		var mi := LowPoly.instance(b.commit(), c)
		node.add_child(mi)
		if animate:
			mi.position.y = -h - 1.0
			var tw := create_tween()
			tw.tween_interval(_rng.randf() * 1.0)
			tw.tween_property(mi, "position:y", 0.0, 2.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _build_jungle(node: Node3D, animate: bool) -> void:
	var fern := LowPoly.Builder.new()
	for k in 6:
		var ang := k * 60.0
		fern.add(LowPoly.box(Vector3(0.12, 0.03, 0.7)), Color(0.2, 0.55, 0.2), LowPoly.xf(Vector3(sin(deg_to_rad(ang)) * 0.3, 0.2, cos(deg_to_rad(ang)) * 0.3), Vector3(-30, ang, 0)))
	var fern_mesh := fern.commit()
	var bamboo := LowPoly.Builder.new()
	for k in 4:
		var off := Vector3(cos(k * 1.7) * 0.25, 0, sin(k * 1.7) * 0.25)
		var h := 1.6 + k * 0.35
		bamboo.add(LowPoly.cylinder(0.05, 0.06, h, 5), Color(0.55, 0.72, 0.3), LowPoly.xf(off + Vector3(0, h * 0.5, 0)))
		bamboo.add(LowPoly.box(Vector3(0.35, 0.02, 0.1)), Color(0.35, 0.65, 0.25), LowPoly.xf(off + Vector3(0.15, h, 0), Vector3(0, k * 50.0, -20)))
	var bamboo_mesh := bamboo.commit()
	var mush := LowPoly.Builder.new()
	mush.add(LowPoly.cylinder(0.04, 0.05, 0.18, 5), Color(0.95, 0.92, 0.85), LowPoly.xf(Vector3(0, 0.09, 0)))
	mush.add(LowPoly.sphere(0.13, 0.12, 6, 2), Color(0.85, 0.2, 0.15), LowPoly.xf(Vector3(0, 0.2, 0)))
	var mush_mesh := mush.commit()
	var pool: Array[ArrayMesh] = [fern_mesh, fern_mesh, bamboo_mesh, mush_mesh]
	_scatter(node, 70, func(k: int) -> Mesh: return pool[k % pool.size()], animate)


func _build_rainbow(node: Node3D, animate: bool) -> void:
	var colors := [Color(0.9, 0.2, 0.2), Color(1, 0.55, 0.1), Color(1, 0.9, 0.2), Color(0.3, 0.8, 0.3), Color(0.2, 0.6, 1), Color(0.35, 0.3, 0.85), Color(0.65, 0.35, 0.85)]
	var b := LowPoly.Builder.new()
	b.unshaded = true
	b.shade_variance = 0.0
	var segments := 36
	for ci in colors.size():
		var radius := 12.0 - ci * 0.5
		var c: Color = colors[ci]
		c.a = 0.6
		for s in segments:
			var a0 := PI * s / segments
			var mid := a0 + PI / segments * 0.5
			var seg_len := radius * PI / segments + 0.05
			b.add(LowPoly.box(Vector3(seg_len, 0.6, 0.05)), c, LowPoly.xf(Vector3(cos(mid) * radius, sin(mid) * radius, 0), Vector3(0, 0, rad_to_deg(mid) + 90.0)))
	var rainbow := LowPoly.instance(b.commit(), Vector3(-11, -1.5, -11), false)
	rainbow.rotation_degrees.y = 45.0
	node.add_child(rainbow)
	if animate:
		rainbow.scale = Vector3.ONE * 0.01
		create_tween().tween_property(rainbow, "scale", Vector3.ONE, 2.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
