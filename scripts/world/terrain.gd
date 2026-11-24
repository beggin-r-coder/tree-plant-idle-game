class_name Terrain
extends Node3D
## One organic low-poly island with gentle hills, a dried-up riverbed and a dry
## pond hollow (they fill with water at milestones). The island is long along the
## screen's vertical axis so it fits a portrait phone screen.
##
## Two coordinate systems are used:
##   world (x, z)  : Godot space
##   screen (u, v) : u = screen right, v = towards the camera (screen down)
## With the isometric camera at 45 degrees, u/v are the world axes rotated by 45.

const HALF_U := 13.0          ## island half width (screen horizontal)
const HALF_V := 28.0          ## island half length (screen vertical)
const CELL := 1.0
const MARGIN := 6.0
const OCEAN_Y := -0.55
const WATER_Y := -0.18        ## river / pond surface
const RIGHT := Vector3(0.70710678, 0.0, -0.70710678)
const TOWARD := Vector3(0.70710678, 0.0, 0.70710678)
const RIVER_V := -4.0
const POND_UV := Vector2(6.5, 15.5)
const POND_R := 2.4

const GROUND_SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform vec3 dirt_color : source_color = vec3(0.55, 0.42, 0.30);
uniform vec3 grass_color : source_color = vec3(0.45, 0.62, 0.32);
uniform vec3 sand_color : source_color = vec3(0.74, 0.64, 0.45);
uniform vec3 rock_color : source_color = vec3(0.52, 0.5, 0.48);
uniform float global_green = 0.0;     // how green the land far from the forest is
uniform vec3 forest_center = vec3(0.0);
uniform float green_radius = 0.0;     // land inside this radius around the forest is fully green
uniform float water_y = -0.18;
// Pollution overlay (used by the intro): land within poison_radius of poison_center turns toxic.
uniform vec3 poison_center = vec3(0.0);
uniform float poison_radius = 0.0;
uniform vec3 poison_color : source_color = vec3(0.3, 0.32, 0.12);
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float ragged = sin(wp.x * 1.3) * sin(wp.z * 1.1) * 1.4 + sin(wp.x * 0.37 + wp.z * 0.51) * 1.2;
	float d = length(wp.xz - forest_center.xz) + ragged;
	float near_forest = (1.0 - smoothstep(green_radius - 1.2, green_radius, d)) * step(0.01, green_radius);
	float g = clamp(max(global_green, near_forest), 0.0, 1.0);
	vec3 land = mix(dirt_color, grass_color, g);
	float dp = length(wp.xz - poison_center.xz) + ragged * 0.8;
	float poison = (1.0 - smoothstep(poison_radius - 2.5, poison_radius, dp)) * step(0.01, poison_radius);
	land = mix(land, poison_color, poison * 0.85);
	float slope = 1.0 - wn.y;
	land = mix(land, rock_color, smoothstep(0.32, 0.5, slope));
	float beach = smoothstep(water_y + 0.08, water_y + 0.22, wp.y);
	vec3 c = mix(sand_color, land, beach);
	c *= mix(0.35, 1.0, smoothstep(-1.2, water_y, wp.y));   // darker under water
	ALBEDO = c * COLOR.r;
	ROUGHNESS = 1.0;
}
"""

var material: ShaderMaterial
var _noise := FastNoiseLite.new()
var _heights := PackedFloat32Array()
var _nu := 0
var _nv := 0
var _u0 := 0.0
var _v0 := 0.0


static func to_world(u: float, v: float) -> Vector3:
	return RIGHT * u + TOWARD * v


static func to_uv(p: Vector3) -> Vector2:
	return Vector2(p.dot(RIGHT), p.dot(TOWARD))


static func river_v_at(u: float) -> float:
	return RIVER_V + sin(u * 0.33) * 2.2 + sin(u * 0.9 + 1.0) * 0.5


func build() -> void:
	_noise.seed = 7
	_noise.frequency = 0.055
	_noise.fractal_octaves = 3
	_u0 = -HALF_U - MARGIN
	_v0 = -HALF_V - MARGIN
	_nu = int((HALF_U + MARGIN) * 2.0 / CELL)
	_nv = int((HALF_V + MARGIN) * 2.0 / CELL)
	_heights.resize((_nu + 1) * (_nv + 1))
	for j in _nv + 1:
		for i in _nu + 1:
			_heights[j * (_nu + 1) + i] = _height_fn(_u0 + i * CELL, _v0 + j * CELL)
	_build_mesh()


func _height_fn(u: float, v: float) -> float:
	var p := to_world(u, v)
	var hills := (_noise.get_noise_2d(p.x, p.z) * 0.5 + 0.5) * 1.3
	var h := 0.25 + hills
	# Island outline: a stretched ellipse with a wobbly coastline.
	var edge := _noise.get_noise_2d(p.x * 0.8 + 300.0, p.z * 0.8) * 0.2
	var m := sqrt(pow(u / HALF_U, 2.0) + pow(v / HALF_V, 2.0)) + edge
	h = lerpf(-1.6, h, 1.0 - smoothstep(0.86, 1.06, m))
	# Dry riverbed winding across the island.
	var d := absf(v - river_v_at(u))
	h = lerpf(-0.5, h, smoothstep(0.9, 2.4, d))
	# Dry pond hollow.
	var dp := Vector2(u, v).distance_to(POND_UV) / POND_R
	h = lerpf(-0.5, h, smoothstep(0.6, 1.3, dp))
	return h


func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in _nv:
		for i in _nu:
			var h00 := _h(i, j)
			var h10 := _h(i + 1, j)
			var h01 := _h(i, j + 1)
			var h11 := _h(i + 1, j + 1)
			if maxf(maxf(h00, h10), maxf(h01, h11)) < OCEAN_Y - 0.9:
				continue
			var p00 := to_world(_u0 + i * CELL, _v0 + j * CELL) + Vector3(0, h00, 0)
			var p10 := to_world(_u0 + (i + 1) * CELL, _v0 + j * CELL) + Vector3(0, h10, 0)
			var p01 := to_world(_u0 + i * CELL, _v0 + (j + 1) * CELL) + Vector3(0, h01, 0)
			var p11 := to_world(_u0 + (i + 1) * CELL, _v0 + (j + 1) * CELL) + Vector3(0, h11, 0)
			# Alternate the diagonal for a less regular faceted look.
			if (i + j) % 2 == 0:
				_tri(st, p00, p10, p11)
				_tri(st, p00, p11, p01)
			else:
				_tri(st, p00, p10, p01)
				_tri(st, p10, p11, p01)
	var mesh := st.commit()
	material = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	material.shader = sh
	material.set_shader_parameter("water_y", WATER_Y)
	# Set every colour from code: defaults of source_color uniforms are not
	# converted to linear space by the Compatibility renderer.
	material.set_shader_parameter("sand_color", Color(0.64, 0.55, 0.40))
	material.set_shader_parameter("rock_color", Color(0.55, 0.53, 0.5))
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	var h := absi(hash(Vector3i(roundi(a.x * 10.0 + c.x * 3.0), roundi(b.z * 10.0), roundi(a.z * 7.0 + b.x)))) % 1000
	var k := 0.93 + (h / 1000.0) * 0.14
	var col := Color(k, k, k)
	for p in [a, b, c]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(p)


func _h(i: int, j: int) -> float:
	return _heights[clampi(j, 0, _nv) * (_nu + 1) + clampi(i, 0, _nu)]


## Terrain height at a world position (bilinear on the grid).
func height_at(p: Vector3) -> float:
	var uv := to_uv(p)
	var fi := (uv.x - _u0) / CELL
	var fj := (uv.y - _v0) / CELL
	var i := int(floor(fi))
	var j := int(floor(fj))
	var tx := fi - i
	var ty := fj - j
	var a := lerpf(_h(i, j), _h(i + 1, j), tx)
	var b := lerpf(_h(i, j + 1), _h(i + 1, j + 1), tx)
	return lerpf(a, b, ty)


## True if p is on dry, fairly flat land (not beach, riverbed or pond).
func is_land(p: Vector3, min_h: float = 0.15) -> bool:
	return height_at(p) > min_h


## Random point on dry land. Returns the point with y = terrain height.
func random_land_point(rng: RandomNumberGenerator, min_h: float = 0.15) -> Vector3:
	var p := Vector3.ZERO
	for attempt in 60:
		p = to_world(rng.randf_range(-HALF_U, HALF_U), rng.randf_range(-HALF_V, HALF_V))
		if is_land(p, min_h):
			p.y = height_at(p)
			return p
	p = to_world(0, 9)
	p.y = height_at(p)
	return p


## A land point near the coast on the camera side (animals walk in from there).
func shore_point(rng: RandomNumberGenerator) -> Vector3:
	for attempt in 40:
		var ang := rng.randf_range(0.15, PI - 0.15)   # lower half of the island on screen
		var p := to_world(cos(ang) * HALF_U * 0.82, sin(ang) * HALF_V * 0.82)
		if is_land(p):
			p.y = height_at(p)
			return p
	return random_land_point(rng)


## Builds the river water as a ribbon along the riverbed (UV.x = distance along it).
func build_river_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u_min := -HALF_U - 4.0
	var u_max := HALF_U + 4.0
	var steps := 70
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for s in steps + 1:
		var t := float(s) / steps
		var u := lerpf(u_min, u_max, t)
		var v := river_v_at(u)
		var l := to_world(u, v - 2.3) + Vector3(0, WATER_Y, 0)
		var r := to_world(u, v + 2.3) + Vector3(0, WATER_Y, 0)
		if s > 0:
			var t0 := float(s - 1) / steps
			for q in [[prev_l, t0, 0.0], [r, t, 1.0], [prev_r, t0, 1.0], [prev_l, t0, 0.0], [l, t, 0.0], [r, t, 1.0]]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(q[1], q[2]))
				st.add_vertex(q[0])
		prev_l = l
		prev_r = r
	return st.commit()
