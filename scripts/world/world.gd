class_name World
extends Node3D
## Open-land world: terrain, the growing forest, ecosystem features and animals.
## Reacts to GameState signals and transforms the land at every milestone.

const MOUNTAINS := [   ## [u, v, radius, height] at the far (top) end of the island
	[-8.0, -27.0, 3.6, 7.0], [-1.5, -29.5, 3.2, 6.0], [5.5, -27.5, 3.4, 7.5],
	[10.5, -23.5, 2.6, 4.6], [-11.5, -21.0, 2.4, 4.0], [1.5, -24.5, 2.0, 3.6],
]

const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(0.27, 0.6, 0.88, 0.88);
uniform float flow = 1.5;
uniform float foam = 0.25;
uniform float reveal = 1.0;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wp.x * 1.3 + TIME * 2.0) * 0.02 + cos(wp.z * 2.1 + TIME * 1.6) * 0.02;
}
void fragment() {
	if (UV.x > reveal) { discard; }
	float s = sin((wp.x - wp.z) * 1.6 - TIME * flow + sin((wp.x + wp.z) * 2.0) * 1.2) * 0.5 + 0.5;
	ALBEDO = color.rgb + vec3(smoothstep(0.93, 1.0, s) * foam);
	ALPHA = color.a;
	ROUGHNESS = 0.15;
}
"""

var terrain: Terrain
var forest: Forest
var features := {}          ## feature name -> Node3D
var animals_root: Node3D
var _rng := RandomNumberGenerator.new()
var _water_shader: Shader


func build() -> void:
	_rng.seed = 42
	_water_shader = Shader.new()
	_water_shader.code = WATER_SHADER
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build()
	_build_ocean()
	forest = Forest.new()
	forest.name = "Forest"
	add_child(forest)
	forest.setup(terrain)
	forest.extent_changed.connect(_on_extent_changed)
	_build_barren_decor()
	for m in MOUNTAINS:
		forest.add_obstacle(Terrain.to_world(m[0], m[1]), m[2])
	animals_root = Node3D.new()
	animals_root.name = "Animals"
	add_child(animals_root)

	terrain.material.set_shader_parameter("forest_center", forest.center)
	_apply_ground_colors(GameState.stage)
	forest.restore()
	for s in range(1, GameState.stage + 1):
		_unlock_stage_content(s, false)

	GameState.clicked.connect(func(i: int) -> void: forest.on_click(i))
	GameState.trees_completed.connect(func(i: int, count: int, earned: float, _m: bool) -> void: forest.on_trees_completed(i, count, earned))
	GameState.plant_unlocked.connect(func(i: int) -> void: forest.on_unlocked(i))
	GameState.machine_changed.connect(func(i: int) -> void: forest.on_machine_changed(i))
	GameState.stage_changed.connect(_on_stage_changed)


func height_at(p: Vector3) -> float:
	return terrain.height_at(p)


## Random spot on open dry land (used by animals).
func random_free_point() -> Vector3:
	return terrain.random_land_point(_rng, 0.2)


# ------------------------------------------------------------------ stages

func _grass_color(stage: int) -> Color:
	return GameData.STAGES[maxi(stage, 1)]["ground"]


func _apply_ground_colors(stage: int) -> void:
	terrain.material.set_shader_parameter("dirt_color", GameData.STAGES[0]["ground"])
	terrain.material.set_shader_parameter("grass_color", _grass_color(stage))
	terrain.material.set_shader_parameter("global_green", _global_green(stage))


func _global_green(stage: int) -> float:
	return clampf(float(stage) / float(GameData.STAGES.size() - 1), 0.0, 1.0) * 0.85


func _on_extent_changed(r: float) -> void:
	var target := r + 3.0 if r > 0.0 else 0.0
	var mat := terrain.material
	var cur_v: Variant = mat.get_shader_parameter("green_radius")
	var current := 0.0 if cur_v == null else float(cur_v)
	if is_zero_approx(current):
		mat.set_shader_parameter("green_radius", target)
	else:
		create_tween().tween_method(func(v: float) -> void: mat.set_shader_parameter("green_radius", v), current, target, 1.2)


func _on_stage_changed(stage: int) -> void:
	var mat := terrain.material
	var from_grass: Color = mat.get_shader_parameter("grass_color")
	var from_green: float = mat.get_shader_parameter("global_green")
	var to_grass := _grass_color(stage)
	var to_green := _global_green(stage)
	var fade := func(t: float) -> void:
		mat.set_shader_parameter("grass_color", from_grass.lerp(to_grass, t))
		mat.set_shader_parameter("global_green", lerpf(from_green, to_green, t))
	create_tween().tween_method(fade, 0.0, 1.0, 2.5)
	_unlock_stage_content(stage, true)


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
			from = Terrain.to_world(_rng.randf_range(-10, 10), _rng.randf_range(10, 20)) + Vector3(0, 9.0, 0)
		else:
			from = terrain.shore_point(_rng)
		a.arrive(from, delay)
	else:
		var p := random_free_point()
		if a.flyer:
			p.y += _rng.randf_range(a.height_range.x, a.height_range.y)
		a.position = p
	return a


# ------------------------------------------------------------------ building

func _water_material(color: Color, flow: float, foam: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _water_shader
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("flow", flow)
	m.set_shader_parameter("foam", foam)
	return m


func _build_ocean() -> void:
	var ocean := PlaneMesh.new()
	ocean.size = Vector2(400, 400)
	var omat := StandardMaterial3D.new()
	omat.albedo_color = Color(0.24, 0.55, 0.82)
	omat.roughness = 0.6
	ocean.material = omat
	var mi := MeshInstance3D.new()
	mi.name = "Ocean"
	mi.mesh = ocean
	mi.position.y = Terrain.OCEAN_Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_barren_decor() -> void:
	# Rocks and old stumps: a reminder of the forest that was cut down.
	var b := LowPoly.Builder.new()
	for k in 30:
		var p := terrain.random_land_point(_rng, 0.25)
		var s := _rng.randf_range(0.2, 0.5)
		b.add(LowPoly.sphere(s, s * 1.2, 6, 3), Color(0.58, 0.57, 0.56), LowPoly.xf(p + Vector3(0, s * 0.2, 0), Vector3(0, _rng.randf() * 360.0, 0)), s * 0.4)
		forest.add_obstacle(p, s + 0.1)
	for k in 18:
		var p := terrain.random_land_point(_rng, 0.25)
		b.add(LowPoly.cylinder(0.22, 0.28, 0.3, 7), Color(0.5, 0.36, 0.24), LowPoly.xf(p + Vector3(0, 0.1, 0)))
		b.add(LowPoly.cylinder(0.2, 0.2, 0.02, 7), Color(0.78, 0.65, 0.45), LowPoly.xf(p + Vector3(0, 0.26, 0)))
		forest.add_obstacle(p, 0.35)
	var mi := LowPoly.instance(b.commit())
	mi.name = "Decor"
	add_child(mi)


## Scatters small plants with MultiMeshes (one per variant), optionally popping them in.
func _scatter(parent: Node3D, count: int, meshes: Array, animate: bool, min_h: float = 0.2) -> void:
	var per := ceili(float(count) / meshes.size())
	for mesh in meshes:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = per
		var xforms: Array[Transform3D] = []
		var delays: Array[float] = []
		for k in per:
			var p := terrain.random_land_point(_rng, min_h)
			var s := _rng.randf_range(0.8, 1.25)
			xforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), p))
			delays.append(_rng.randf() * 2.2)
			mm.set_instance_transform(k, xforms[k] if not animate else Transform3D(Basis().scaled(Vector3.ONE * 0.001), p))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
		if animate:
			var grow := func(t: float) -> void:
				for k in per:
					var local := clampf((t - delays[k]) / 0.4, 0.0, 1.0)
					var e := 1.0 + 2.70158 * pow(local - 1.0, 3.0) + 1.70158 * pow(local - 1.0, 2.0)   # back-out ease
					var x := xforms[k]
					mm.set_instance_transform(k, Transform3D(x.basis.scaled(Vector3.ONE * maxf(e, 0.001)), x.origin))
			create_tween().tween_method(grow, 0.0, 2.7, 2.7)


func _build_grass(node: Node3D, animate: bool) -> void:
	var meshes: Array = []
	for v in 3:
		var b := LowPoly.Builder.new()
		b.sway = 0.45
		var g := Color(0.35, 0.62, 0.25).lightened(v * 0.07)
		b.add(LowPoly.cone(0.08, 0.45, 3), g, LowPoly.xf(Vector3(0, 0.2, 0), Vector3(0, 0, 12)))
		b.add(LowPoly.cone(0.08, 0.35, 3), g, LowPoly.xf(Vector3(0.1, 0.15, 0.05), Vector3(0, 0, -18)))
		b.add(LowPoly.cone(0.07, 0.3, 3), g.darkened(0.1), LowPoly.xf(Vector3(-0.08, 0.13, -0.06), Vector3(15, 0, 0)))
		meshes.append(b.commit())
	_scatter(node, 330, meshes, animate)


func _build_flowers(node: Node3D, animate: bool) -> void:
	var colors := [Color(1, 0.4, 0.5), Color(1, 0.85, 0.2), Color(0.7, 0.5, 1.0), Color(1, 1, 1), Color(1, 0.55, 0.2)]
	var meshes: Array = []
	for c in colors:
		var b := LowPoly.Builder.new()
		b.sway = 0.35
		for f in 3:
			var off := Vector3(cos(f * 2.1) * 0.15, 0, sin(f * 2.1) * 0.15)
			b.add(LowPoly.cylinder(0.015, 0.015, 0.35, 3), Color(0.3, 0.6, 0.25), LowPoly.xf(off + Vector3(0, 0.15, 0)))
			b.add(LowPoly.sphere(0.08, 0.08, 5, 2), c, LowPoly.xf(off + Vector3(0, 0.35, 0)))
			b.add(LowPoly.sphere(0.03, 0.05, 4, 2), Color(1, 0.9, 0.3), LowPoly.xf(off + Vector3(0, 0.39, 0)))
		meshes.append(b.commit())
	_scatter(node, 180, meshes, animate)


func _build_jungle(node: Node3D, animate: bool) -> void:
	var fern := LowPoly.Builder.new()
	fern.sway = 0.3
	for k in 6:
		var ang := k * 60.0
		fern.add(LowPoly.box(Vector3(0.12, 0.03, 0.7)), Color(0.2, 0.55, 0.2), LowPoly.xf(Vector3(sin(deg_to_rad(ang)) * 0.3, 0.2, cos(deg_to_rad(ang)) * 0.3), Vector3(-30, ang, 0)))
	var bamboo := LowPoly.Builder.new()
	bamboo.sway = 0.03
	for k in 4:
		var off := Vector3(cos(k * 1.7) * 0.25, 0, sin(k * 1.7) * 0.25)
		var h := 1.6 + k * 0.35
		bamboo.add(LowPoly.cylinder(0.05, 0.06, h, 5), Color(0.55, 0.72, 0.3), LowPoly.xf(off + Vector3(0, h * 0.5, 0)))
		bamboo.add(LowPoly.box(Vector3(0.35, 0.02, 0.1)), Color(0.35, 0.65, 0.25), LowPoly.xf(off + Vector3(0.15, h, 0), Vector3(0, k * 50.0, -20)))
	var mush := LowPoly.Builder.new()
	mush.add(LowPoly.cylinder(0.04, 0.05, 0.18, 5), Color(0.95, 0.92, 0.85), LowPoly.xf(Vector3(0, 0.09, 0)))
	mush.add(LowPoly.sphere(0.13, 0.12, 6, 2), Color(0.85, 0.2, 0.15), LowPoly.xf(Vector3(0, 0.2, 0)))
	_scatter(node, 120, [fern.commit(), bamboo.commit(), mush.commit()], animate)


func _build_river(node: Node3D, animate: bool) -> void:
	var mat := _water_material(Color(0.27, 0.6, 0.88, 0.88), 1.5, 0.25)
	var water := MeshInstance3D.new()
	water.mesh = terrain.build_river_mesh()
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(water)
	if animate:
		# The dry riverbed fills up from one side, like the river starting to flow again.
		mat.set_shader_parameter("reveal", 0.0)
		create_tween().tween_method(func(v: float) -> void: mat.set_shader_parameter("reveal", v), 0.0, 1.0, 3.5).set_trans(Tween.TRANS_SINE)


func _build_pond(node: Node3D, animate: bool) -> void:
	var c := Terrain.to_world(Terrain.POND_UV.x, Terrain.POND_UV.y)
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = Terrain.POND_R * 1.25
	water_mesh.bottom_radius = Terrain.POND_R * 1.25
	water_mesh.height = 0.02
	water_mesh.radial_segments = 16
	water_mesh.rings = 1
	var water := MeshInstance3D.new()
	water.mesh = water_mesh
	water.material_override = _water_material(Color(0.22, 0.55, 0.75, 0.9), 0.4, 0.15)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = c + Vector3(0, Terrain.WATER_Y, 0)
	node.add_child(water)
	var b := LowPoly.Builder.new()
	for k in 5:
		var ang := _rng.randf() * TAU
		var d := _rng.randf_range(0.3, Terrain.POND_R * 0.6)
		var p := c + Vector3(cos(ang) * d, Terrain.WATER_Y + 0.02, sin(ang) * d)
		b.add(LowPoly.cylinder(0.28, 0.28, 0.02, 7), Color(0.3, 0.65, 0.3), LowPoly.xf(p))
		if k % 2 == 0:
			b.add(LowPoly.sphere(0.08, 0.1, 5, 2), Color(1, 0.7, 0.85), LowPoly.xf(p + Vector3(0, 0.05, 0)))
	var pads := LowPoly.instance(b.commit(), Vector3.ZERO, false)
	node.add_child(pads)
	var reeds := LowPoly.Builder.new()
	for k in 12:
		var ang := _rng.randf() * TAU
		var p := c + Vector3(cos(ang), 0, sin(ang)) * Terrain.POND_R * 1.15
		p.y = terrain.height_at(p)
		reeds.add(LowPoly.cylinder(0.02, 0.03, 0.8, 3), Color(0.4, 0.6, 0.25), LowPoly.xf(p + Vector3(0, 0.4, 0)))
		reeds.add(LowPoly.cylinder(0.05, 0.05, 0.2, 4), Color(0.45, 0.3, 0.18), LowPoly.xf(p + Vector3(0, 0.75, 0)))
	var reed_mi := LowPoly.instance(reeds.commit(), Vector3.ZERO, false)
	node.add_child(reed_mi)
	if animate:
		water.position.y = -0.7
		pads.position.y = -0.6
		create_tween().tween_property(water, "position:y", c.y + Terrain.WATER_Y, 2.5).set_trans(Tween.TRANS_SINE)
		create_tween().tween_property(pads, "position:y", 0.0, 2.5).set_trans(Tween.TRANS_SINE)
		reed_mi.scale = Vector3(1, 0.01, 1)
		create_tween().tween_property(reed_mi, "scale", Vector3.ONE, 1.5).set_delay(1.5)


func _build_mountains(node: Node3D, animate: bool) -> void:
	for m in MOUNTAINS:
		var c := Terrain.to_world(m[0], m[1])
		var r: float = m[2]
		var h: float = m[3]
		var base_y := terrain.height_at(c) - 0.3
		var b := LowPoly.Builder.new()
		b.shade_variance = 0.1
		b.add(LowPoly.cone(r, h, 7), Color(0.5, 0.52, 0.55), LowPoly.xf(Vector3(0, h * 0.5, 0)), 0.35)
		b.add(LowPoly.cone(r * 0.32, h * 0.32, 7), Color(0.96, 0.97, 1.0), LowPoly.xf(Vector3(0, h * 0.84 + 0.02, 0)), 0.05)
		b.add(LowPoly.cone(r * 0.7, h * 0.45, 6), Color(0.35, 0.55, 0.3), LowPoly.xf(Vector3(r * 0.5, h * 0.22, r * 0.3), Vector3(0, 30, 0)), 0.2)
		var mi := LowPoly.instance(b.commit(), Vector3(c.x, base_y, c.z))
		node.add_child(mi)
		if animate:
			mi.position.y = base_y - h - 1.0
			var tw := create_tween()
			tw.tween_interval(_rng.randf() * 1.0)
			tw.tween_property(mi, "position:y", base_y, 2.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _build_rainbow(node: Node3D, animate: bool) -> void:
	var colors := [Color(0.9, 0.2, 0.2), Color(1, 0.55, 0.1), Color(1, 0.9, 0.2), Color(0.3, 0.8, 0.3), Color(0.2, 0.6, 1), Color(0.35, 0.3, 0.85), Color(0.65, 0.35, 0.85)]
	var b := LowPoly.Builder.new()
	b.unshaded = true
	b.shade_variance = 0.0
	var segments := 36
	for ci in colors.size():
		var radius := 11.0 - ci * 0.5
		var c: Color = colors[ci]
		c.a = 0.6
		for s in segments:
			var mid := PI * (s + 0.5) / segments
			var seg_len := radius * PI / segments + 0.05
			b.add(LowPoly.box(Vector3(seg_len, 0.5, 0.05)), c, LowPoly.xf(Vector3(cos(mid) * radius, sin(mid) * radius, 0), Vector3(0, 0, rad_to_deg(mid) + 90.0)))
	var rainbow := LowPoly.instance(b.commit(), Terrain.to_world(0.0, -22.0) + Vector3(0, -1.0, 0), false)
	rainbow.rotation_degrees.y = 45.0
	node.add_child(rainbow)
	if animate:
		rainbow.scale = Vector3.ONE * 0.01
		create_tween().tween_property(rainbow, "scale", Vector3.ONE, 2.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
