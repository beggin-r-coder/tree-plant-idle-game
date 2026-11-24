class_name TreeFactory
extends RefCounted
## Builds (and caches) one merged low-poly mesh per plant type.
## Each tree is ~1 draw call, so a big forest stays fast.

static var _cache: Dictionary = {}

const TRUNK := Color(0.45, 0.30, 0.18)
const TRUNK_DARK := Color(0.33, 0.22, 0.14)


static func tree_mesh(plant_id: String) -> ArrayMesh:
	if _cache.has(plant_id):
		return _cache[plant_id]
	var b := LowPoly.Builder.new()
	match plant_id:
		"bush": _bush(b)
		"oak": _oak(b)
		"pine": _pine(b)
		"birch": _birch(b)
		"cherry": _cherry(b)
		"sequoia": _sequoia(b)
		_: _oak(b)
	var m := b.commit()
	_cache[plant_id] = m
	return m


static func _bush(b: LowPoly.Builder) -> void:
	var g := Color(0.30, 0.62, 0.25)
	b.add(LowPoly.cylinder(0.05, 0.07, 0.3), TRUNK, LowPoly.xf(Vector3(0, 0.15, 0)))
	b.add(LowPoly.sphere(0.42, 0.7, 7, 4), g, LowPoly.xf(Vector3(0, 0.45, 0)), 0.08)
	b.add(LowPoly.sphere(0.32, 0.55, 6, 3), g.lightened(0.1), LowPoly.xf(Vector3(0.3, 0.35, 0.1)), 0.06)
	b.add(LowPoly.sphere(0.3, 0.5, 6, 3), g.darkened(0.1), LowPoly.xf(Vector3(-0.28, 0.33, -0.08)), 0.06)
	var berry := Color(0.85, 0.15, 0.25)
	for p in [Vector3(0.25, 0.6, 0.25), Vector3(-0.2, 0.55, 0.3), Vector3(0.05, 0.78, 0.2), Vector3(0.4, 0.4, -0.15), Vector3(-0.35, 0.45, -0.2)]:
		b.add(LowPoly.sphere(0.06, 0.12, 4, 2), berry, LowPoly.xf(p))


static func _oak(b: LowPoly.Builder) -> void:
	var g := Color(0.27, 0.58, 0.22)
	b.add(LowPoly.cylinder(0.11, 0.18, 1.1, 6), TRUNK, LowPoly.xf(Vector3(0, 0.55, 0)))
	b.add(LowPoly.cylinder(0.04, 0.07, 0.6, 5), TRUNK, LowPoly.xf(Vector3(0.2, 1.0, 0), Vector3(0, 0, -40)))
	b.add(LowPoly.sphere(0.8, 1.3, 8, 5), g, LowPoly.xf(Vector3(0, 1.6, 0)), 0.15)
	b.add(LowPoly.sphere(0.55, 0.9, 7, 4), g.lightened(0.08), LowPoly.xf(Vector3(0.55, 1.35, 0.2)), 0.1)
	b.add(LowPoly.sphere(0.5, 0.85, 7, 4), g.darkened(0.08), LowPoly.xf(Vector3(-0.5, 1.4, -0.25)), 0.1)


static func _pine(b: LowPoly.Builder) -> void:
	var g := Color(0.13, 0.45, 0.25)
	b.add(LowPoly.cylinder(0.08, 0.13, 0.7, 6), TRUNK_DARK, LowPoly.xf(Vector3(0, 0.35, 0)))
	b.add(LowPoly.cone(0.75, 1.0, 7), g, LowPoly.xf(Vector3(0, 1.0, 0)), 0.06)
	b.add(LowPoly.cone(0.58, 0.9, 7), g.lightened(0.06), LowPoly.xf(Vector3(0, 1.55, 0), Vector3(0, 20, 0)), 0.05)
	b.add(LowPoly.cone(0.4, 0.85, 7), g.lightened(0.12), LowPoly.xf(Vector3(0, 2.05, 0), Vector3(0, 40, 0)), 0.04)


static func _birch(b: LowPoly.Builder) -> void:
	var bark := Color(0.93, 0.92, 0.88)
	var g := Color(0.55, 0.74, 0.28)
	b.add(LowPoly.cylinder(0.07, 0.1, 1.9, 6), bark, LowPoly.xf(Vector3(0, 0.95, 0)))
	for y in [0.35, 0.8, 1.25]:
		b.add(LowPoly.box(Vector3(0.13, 0.05, 0.13)), Color(0.15, 0.15, 0.15), LowPoly.xf(Vector3(0.03, y, 0.03), Vector3(0, 30, 0)))
	b.add(LowPoly.sphere(0.5, 1.2, 7, 4), g, LowPoly.xf(Vector3(0, 1.95, 0)), 0.1)
	b.add(LowPoly.sphere(0.38, 0.9, 6, 4), g.lightened(0.1), LowPoly.xf(Vector3(0.3, 1.6, 0.15)), 0.08)


static func _cherry(b: LowPoly.Builder) -> void:
	var pink := Color(0.98, 0.62, 0.78)
	b.add(LowPoly.cylinder(0.09, 0.15, 1.0, 6), TRUNK_DARK, LowPoly.xf(Vector3(0, 0.5, 0)))
	b.add(LowPoly.cylinder(0.04, 0.07, 0.7, 5), TRUNK_DARK, LowPoly.xf(Vector3(-0.25, 1.05, 0), Vector3(0, 0, 45)))
	b.add(LowPoly.cylinder(0.04, 0.07, 0.7, 5), TRUNK_DARK, LowPoly.xf(Vector3(0.25, 1.05, 0), Vector3(0, 0, -45)))
	b.add(LowPoly.sphere(0.7, 1.0, 8, 4), pink, LowPoly.xf(Vector3(0, 1.55, 0)), 0.14)
	b.add(LowPoly.sphere(0.5, 0.75, 7, 4), pink.lightened(0.15), LowPoly.xf(Vector3(-0.6, 1.35, 0.1)), 0.1)
	b.add(LowPoly.sphere(0.5, 0.75, 7, 4), pink.darkened(0.05), LowPoly.xf(Vector3(0.6, 1.4, -0.1)), 0.1)


static func _sequoia(b: LowPoly.Builder) -> void:
	var bark := Color(0.60, 0.30, 0.18)
	var g := Color(0.16, 0.42, 0.20)
	b.add(LowPoly.cylinder(0.18, 0.34, 2.2, 7), bark, LowPoly.xf(Vector3(0, 1.1, 0)))
	b.add(LowPoly.cone(0.9, 1.0, 8), g, LowPoly.xf(Vector3(0, 2.1, 0)), 0.1)
	b.add(LowPoly.cone(0.75, 1.0, 8), g.lightened(0.05), LowPoly.xf(Vector3(0, 2.6, 0), Vector3(0, 22, 0)), 0.08)
	b.add(LowPoly.cone(0.55, 0.9, 7), g.lightened(0.1), LowPoly.xf(Vector3(0, 3.1, 0), Vector3(0, 44, 0)), 0.06)
	b.add(LowPoly.cone(0.35, 0.8, 7), g.lightened(0.15), LowPoly.xf(Vector3(0, 3.55, 0)), 0.04)


## The Planter Drone (automation): a little hovering robot that waters its
## plant's sapling. Rotor nodes are children named "Rotor0".."Rotor3".
static func drone(plant_color: Color) -> Node3D:
	var root := Node3D.new()
	var b := LowPoly.Builder.new()
	b.add(LowPoly.cylinder(0.32, 0.26, 0.2, 8), Color(0.96, 0.96, 0.94))
	b.add(LowPoly.sphere(0.2, 0.22, 8, 3), plant_color, LowPoly.xf(Vector3(0, 0.1, 0)))
	b.add(LowPoly.cylinder(0.08, 0.05, 0.12, 6), Color(0.35, 0.6, 0.9), LowPoly.xf(Vector3(0, -0.15, 0)))
	b.add(LowPoly.box(Vector3(0.05, 0.03, 0.05)), Color(0.15, 0.15, 0.2), LowPoly.xf(Vector3(-0.08, 0.04, 0.27)))
	b.add(LowPoly.box(Vector3(0.05, 0.03, 0.05)), Color(0.15, 0.15, 0.2), LowPoly.xf(Vector3(0.08, 0.04, 0.27)))
	for k in 4:
		var ang := PI * 0.25 + k * PI * 0.5
		var dir := Vector3(cos(ang), 0, sin(ang))
		b.add(LowPoly.box(Vector3(0.5, 0.04, 0.06)), Color(0.8, 0.8, 0.82), LowPoly.xf(dir * 0.3, Vector3(0, -rad_to_deg(ang), 0)))
	root.add_child(LowPoly.instance(b.commit()))
	var rotor_mesh := LowPoly.Builder.new()
	rotor_mesh.add(LowPoly.box(Vector3(0.36, 0.015, 0.05)), Color(0.25, 0.25, 0.3))
	rotor_mesh.add(LowPoly.cylinder(0.03, 0.03, 0.05, 5), Color(0.9, 0.35, 0.25))
	var rm := rotor_mesh.commit()
	for k in 4:
		var ang := PI * 0.25 + k * PI * 0.5
		var rotor := LowPoly.instance(rm, Vector3(cos(ang) * 0.52, 0.05, sin(ang) * 0.52), false)
		rotor.name = "Rotor%d" % k
		root.add_child(rotor)
	return root


## Representative leaf colour per plant (used for UI and machine accents).
static func plant_color(plant_id: String) -> Color:
	match plant_id:
		"bush": return Color(0.30, 0.62, 0.25)
		"oak": return Color(0.27, 0.58, 0.22)
		"pine": return Color(0.13, 0.45, 0.25)
		"birch": return Color(0.62, 0.78, 0.30)
		"cherry": return Color(0.98, 0.62, 0.78)
		"sequoia": return Color(0.60, 0.30, 0.18)
	return Color.GREEN
