class_name LowPoly
extends RefCounted
## Helpers to build faceted "low-poly" meshes in code from Godot primitives.
## Every face gets a flat normal and a vertex colour, so one shared material
## renders everything. Replace these with imported .glb models later if you like.

static var _material: StandardMaterial3D
static var _unshaded: StandardMaterial3D
static var _sway := {}   ## strength -> ShaderMaterial

const SWAY_SHADER := """
shader_type spatial;
render_mode specular_disabled;
// Wind sway: vertices bend more the higher they are above the mesh origin (the ground),
// with a phase that depends on world position so neighbours don't move in sync.
uniform float strength = 0.02;
void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0);
	float w = sin(TIME * 1.4 + origin.x * 0.35 + origin.z * 0.27) + 0.35 * sin(TIME * 3.3 + origin.x * 0.9 - origin.z * 0.6);
	VERTEX.x += w * strength * h * h;
	VERTEX.z += w * strength * 0.6 * h * h;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.92;
}
"""


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.92
		_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return _material


## Shaded vertex-colour material with wind sway (cached per strength).
static func sway_material(strength: float) -> ShaderMaterial:
	if not _sway.has(strength):
		var sh := Shader.new()
		sh.code = SWAY_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("strength", strength)
		_sway[strength] = m
	return _sway[strength]


static func unshaded_material() -> StandardMaterial3D:
	if _unshaded == null:
		_unshaded = StandardMaterial3D.new()
		_unshaded.vertex_color_use_as_albedo = true
		_unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_unshaded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_unshaded.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _unshaded


# ------------------------------------------------------------------ primitives

static func sphere(radius: float, height: float = -1.0, radial: int = 7, rings: int = 4) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0 if height < 0.0 else height
	m.radial_segments = radial
	m.rings = rings
	return m


static func cylinder(top: float, bottom: float, height: float, radial: int = 6) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = radial
	m.rings = 0
	return m


static func cone(radius: float, height: float, radial: int = 7) -> CylinderMesh:
	return cylinder(0.0, radius, height, radial)


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func prism(size: Vector3) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = size
	return m


static func xf(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(rot_deg * (PI / 180.0)).scaled(scl)
	return Transform3D(b, pos)


## Single-part mesh shortcut.
static func mesh(prim: PrimitiveMesh, color: Color, t: Transform3D = Transform3D.IDENTITY, jitter: float = 0.0) -> ArrayMesh:
	var b := Builder.new()
	b.add(prim, color, t, jitter)
	return b.commit()


static func instance(m: Mesh, pos: Vector3 = Vector3.ZERO, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Merges many primitives (each with its own colour + transform) into one flat-shaded mesh.
class Builder:
	var st := SurfaceTool.new()
	var count := 0
	var shade_variance := 0.06
	var unshaded := false
	var sway := 0.0   ## > 0: use the wind-sway material

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func add(prim: PrimitiveMesh, color: Color, t: Transform3D = Transform3D.IDENTITY, jitter: float = 0.0) -> void:
		var arrays := prim.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = PackedInt32Array()
		if typeof(arrays[Mesh.ARRAY_INDEX]) == TYPE_PACKED_INT32_ARRAY:
			idx = arrays[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			for k in verts.size():
				idx.append(k)
		for tri in range(0, idx.size() - 2, 3):
			var ia := idx[tri]
			var ib := idx[tri + 1]
			var ic := idx[tri + 2]
			var a := t * LowPoly.jittered(verts[ia], jitter)
			var b := t * LowPoly.jittered(verts[ib], jitter)
			var c := t * LowPoly.jittered(verts[ic], jitter)
			var n := (b - a).cross(c - a)
			if n.length_squared() < 1e-12:
				continue
			n = n.normalized()
			var ref := t.basis * (norms[ia] + norms[ib] + norms[ic])
			if ref.dot(n) < 0.0:
				n = -n
			# Slight per-face brightness change gives the classic faceted look.
			var h := absi(hash(Vector3i(roundi(a.x * 97.0 + c.z * 13.0), roundi(b.y * 89.0), roundi(c.x * 71.0 + a.z * 7.0)))) % 1000
			var k := 1.0 + (h / 1000.0 - 0.5) * 2.0 * shade_variance
			var col := Color(color.r * k, color.g * k, color.b * k, color.a)
			st.set_normal(n)
			st.set_color(col)
			st.add_vertex(a)
			st.set_normal(n)
			st.set_color(col)
			st.add_vertex(b)
			st.set_normal(n)
			st.set_color(col)
			st.add_vertex(c)
		count += 1

	func commit() -> ArrayMesh:
		var m := st.commit()
		var mat: Material = LowPoly.material()
		if unshaded:
			mat = LowPoly.unshaded_material()
		elif sway > 0.0:
			mat = LowPoly.sway_material(sway)
		m.surface_set_material(0, mat)
		return m


## Deterministic per-position noise so shared vertices move together (no cracks).
static func jittered(p: Vector3, amount: float) -> Vector3:
	if amount <= 0.0:
		return p
	var key := Vector3i(roundi(p.x * 1000.0), roundi(p.y * 1000.0), roundi(p.z * 1000.0))
	var h := hash(key)
	var x := float(h & 0x3FF) / 1023.0 - 0.5
	var y := float((h >> 10) & 0x3FF) / 1023.0 - 0.5
	var z := float((h >> 20) & 0x3FF) / 1023.0 - 0.5
	return p + Vector3(x, y, z) * amount
