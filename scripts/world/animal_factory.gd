class_name AnimalFactory
extends RefCounted
## Builds low-poly animals from primitives. Every model faces +Z.


static func create(kind: String, world: Node) -> Animal:
	var a := Animal.new()
	a.kind = kind
	a.world = world
	a.name = kind.capitalize()
	match kind:
		"butterfly": _butterfly(a)
		"bird": _bird(a)
		"rabbit": _rabbit(a)
		"deer": _deer(a)
		"wolf": _wolf(a)
		"tiger": _tiger(a)
		"elephant": _elephant(a)
		_: _rabbit(a)
	return a


# ---------------------------------------------------------------- helpers

static func _part(parent: Node3D, prim: PrimitiveMesh, color: Color, t: Transform3D, jitter: float = 0.0) -> MeshInstance3D:
	var mi := LowPoly.instance(LowPoly.mesh(prim, color, t, jitter))
	parent.add_child(mi)
	return mi


## A leg pivoting at the hip; the mesh hangs down from the pivot.
static func _leg(a: Animal, pos: Vector3, length: float, thickness: float, color: Color) -> void:
	var pivot := Node3D.new()
	pivot.position = pos
	a.add_child(pivot)
	_part(pivot, LowPoly.box(Vector3(thickness, length, thickness)), color, LowPoly.xf(Vector3(0, -length * 0.5, 0)))
	a.legs.append(pivot)


static func _quad_legs(a: Animal, half_w: float, front_z: float, back_z: float, hip_y: float, length: float, thick: float, color: Color) -> void:
	# order: front-left, front-right, back-left, back-right (diagonal pairs swing together)
	_leg(a, Vector3(-half_w, hip_y, front_z), length, thick, color)
	_leg(a, Vector3(half_w, hip_y, front_z), length, thick, color)
	_leg(a, Vector3(-half_w, hip_y, back_z), length, thick, color)
	_leg(a, Vector3(half_w, hip_y, back_z), length, thick, color)


static func _wing(a: Animal, side: float, size: Vector3, color: Color, y: float) -> void:
	var pivot := Node3D.new()
	pivot.position = Vector3(0, y, 0)
	a.add_child(pivot)
	_part(pivot, LowPoly.box(size), color, LowPoly.xf(Vector3(side * size.x * 0.5, 0, 0)))
	a.wings.append(pivot)


# ---------------------------------------------------------------- species

static func _butterfly(a: Animal) -> void:
	a.flyer = true
	a.speed = 1.4
	a.flap_speed = 18.0
	a.height_range = Vector2(0.8, 2.2)
	var colors := [Color(1.0, 0.6, 0.1), Color(0.3, 0.6, 1.0), Color(1.0, 0.95, 0.3), Color(0.9, 0.4, 0.9), Color(1, 1, 1)]
	var c: Color = colors[randi() % colors.size()]
	_part(a, LowPoly.box(Vector3(0.04, 0.04, 0.22)), Color(0.15, 0.1, 0.1), Transform3D.IDENTITY)
	_wing(a, -1.0, Vector3(0.2, 0.01, 0.22), c, 0.0)
	_wing(a, 1.0, Vector3(0.2, 0.01, 0.22), c, 0.0)


static func _bird(a: Animal) -> void:
	a.flyer = true
	a.speed = 3.5
	a.flap_speed = 9.0
	a.height_range = Vector2(4.0, 7.0)
	var colors := [Color(0.3, 0.5, 0.9), Color(0.9, 0.35, 0.25), Color(0.95, 0.8, 0.2)]
	var c: Color = colors[randi() % colors.size()]
	_part(a, LowPoly.sphere(0.18, 0.5, 6, 3), c, LowPoly.xf(Vector3.ZERO, Vector3(90, 0, 0)))
	_part(a, LowPoly.sphere(0.13, 0.26, 6, 3), c.lightened(0.1), LowPoly.xf(Vector3(0, 0.08, 0.25)))
	_part(a, LowPoly.cone(0.05, 0.14, 4), Color(1.0, 0.65, 0.1), LowPoly.xf(Vector3(0, 0.07, 0.42), Vector3(90, 0, 0)))
	_part(a, LowPoly.box(Vector3(0.2, 0.03, 0.18)), c.darkened(0.2), LowPoly.xf(Vector3(0, 0.02, -0.3)))
	_wing(a, -1.0, Vector3(0.5, 0.03, 0.22), c.darkened(0.1), 0.05)
	_wing(a, 1.0, Vector3(0.5, 0.03, 0.22), c.darkened(0.1), 0.05)


static func _rabbit(a: Animal) -> void:
	a.hopper = true
	a.speed = 1.6
	var c := Color(0.78, 0.68, 0.58) if randf() < 0.6 else Color(0.95, 0.95, 0.95)
	_part(a, LowPoly.sphere(0.2, 0.36, 6, 4), c, LowPoly.xf(Vector3(0, 0.2, 0)), 0.03)
	_part(a, LowPoly.sphere(0.13, 0.24, 6, 3), c, LowPoly.xf(Vector3(0, 0.36, 0.17)))
	_part(a, LowPoly.box(Vector3(0.05, 0.22, 0.03)), c, LowPoly.xf(Vector3(-0.05, 0.55, 0.14), Vector3(-10, 0, -10)))
	_part(a, LowPoly.box(Vector3(0.05, 0.22, 0.03)), c, LowPoly.xf(Vector3(0.05, 0.55, 0.14), Vector3(-10, 0, 10)))
	_part(a, LowPoly.sphere(0.06, 0.12, 5, 3), Color(1, 1, 1), LowPoly.xf(Vector3(0, 0.25, -0.2)))
	_part(a, LowPoly.box(Vector3(0.03, 0.03, 0.03)), Color(0.1, 0.1, 0.1), LowPoly.xf(Vector3(-0.07, 0.4, 0.27)))
	_part(a, LowPoly.box(Vector3(0.03, 0.03, 0.03)), Color(0.1, 0.1, 0.1), LowPoly.xf(Vector3(0.07, 0.4, 0.27)))


static func _deer(a: Animal) -> void:
	a.speed = 1.3
	var c := Color(0.66, 0.42, 0.24)
	_quad_legs(a, 0.13, 0.32, -0.32, 0.65, 0.65, 0.07, c.darkened(0.15))
	_part(a, LowPoly.box(Vector3(0.36, 0.34, 0.9)), c, LowPoly.xf(Vector3(0, 0.8, 0)))
	_part(a, LowPoly.box(Vector3(0.16, 0.45, 0.16)), c, LowPoly.xf(Vector3(0, 1.1, 0.42), Vector3(25, 0, 0)))
	_part(a, LowPoly.box(Vector3(0.2, 0.2, 0.32)), c, LowPoly.xf(Vector3(0, 1.33, 0.56)))
	_part(a, LowPoly.box(Vector3(0.1, 0.1, 0.08)), Color(0.15, 0.1, 0.08), LowPoly.xf(Vector3(0, 1.3, 0.74)))
	_part(a, LowPoly.box(Vector3(0.14, 0.14, 0.05)), Color(1, 1, 1), LowPoly.xf(Vector3(0, 0.9, -0.47)))
	var antler := Color(0.85, 0.78, 0.6)
	for s in [-1.0, 1.0]:
		_part(a, LowPoly.cylinder(0.02, 0.025, 0.35, 4), antler, LowPoly.xf(Vector3(s * 0.08, 1.58, 0.5), Vector3(-10, 0, s * -25)))
		_part(a, LowPoly.cylinder(0.015, 0.02, 0.18, 4), antler, LowPoly.xf(Vector3(s * 0.15, 1.65, 0.58), Vector3(40, 0, s * -10)))
	for s in [-1.0, 1.0]:
		_part(a, LowPoly.box(Vector3(0.12, 0.06, 0.04)), c, LowPoly.xf(Vector3(s * 0.15, 1.42, 0.48)))


static func _wolf(a: Animal) -> void:
	a.speed = 2.0
	var c := Color(0.55, 0.56, 0.6)
	_quad_legs(a, 0.11, 0.28, -0.28, 0.45, 0.45, 0.08, c.darkened(0.1))
	_part(a, LowPoly.box(Vector3(0.3, 0.3, 0.8)), c, LowPoly.xf(Vector3(0, 0.6, 0)))
	_part(a, LowPoly.box(Vector3(0.26, 0.26, 0.26)), c, LowPoly.xf(Vector3(0, 0.78, 0.48)))
	_part(a, LowPoly.box(Vector3(0.14, 0.12, 0.2)), c.lightened(0.25), LowPoly.xf(Vector3(0, 0.72, 0.68)))
	_part(a, LowPoly.box(Vector3(0.05, 0.05, 0.04)), Color(0.1, 0.1, 0.1), LowPoly.xf(Vector3(0, 0.76, 0.79)))
	for s in [-1.0, 1.0]:
		_part(a, LowPoly.prism(Vector3(0.09, 0.14, 0.05)), c.darkened(0.1), LowPoly.xf(Vector3(s * 0.08, 0.98, 0.44)))
	a.tail = Node3D.new()
	a.tail.position = Vector3(0, 0.65, -0.4)
	a.add_child(a.tail)
	_part(a.tail, LowPoly.box(Vector3(0.09, 0.09, 0.4)), c.lightened(0.1), LowPoly.xf(Vector3(0, -0.1, -0.17), Vector3(30, 0, 0)))


static func _tiger(a: Animal) -> void:
	a.speed = 1.7
	var c := Color(0.95, 0.55, 0.15)
	var stripe := Color(0.12, 0.1, 0.1)
	_quad_legs(a, 0.15, 0.36, -0.36, 0.5, 0.5, 0.11, c)
	_part(a, LowPoly.box(Vector3(0.42, 0.38, 1.05)), c, LowPoly.xf(Vector3(0, 0.68, 0)))
	for z in [-0.35, -0.15, 0.05, 0.25]:
		_part(a, LowPoly.box(Vector3(0.44, 0.06, 0.07)), stripe, LowPoly.xf(Vector3(0, 0.8, z), Vector3(0, 0, 0)))
	_part(a, LowPoly.box(Vector3(0.36, 0.32, 0.32)), c, LowPoly.xf(Vector3(0, 0.85, 0.62)))
	_part(a, LowPoly.box(Vector3(0.22, 0.14, 0.12)), Color(1, 0.95, 0.9), LowPoly.xf(Vector3(0, 0.76, 0.8)))
	_part(a, LowPoly.box(Vector3(0.06, 0.05, 0.04)), stripe, LowPoly.xf(Vector3(0, 0.82, 0.87)))
	for s in [-1.0, 1.0]:
		_part(a, LowPoly.box(Vector3(0.09, 0.09, 0.05)), c, LowPoly.xf(Vector3(s * 0.13, 1.05, 0.58)))
		_part(a, LowPoly.box(Vector3(0.05, 0.05, 0.03)), stripe, LowPoly.xf(Vector3(s * 0.09, 0.92, 0.79)))
	a.tail = Node3D.new()
	a.tail.position = Vector3(0, 0.78, -0.52)
	a.add_child(a.tail)
	_part(a.tail, LowPoly.box(Vector3(0.07, 0.07, 0.6)), c, LowPoly.xf(Vector3(0, -0.15, -0.25), Vector3(35, 0, 0)))


static func _elephant(a: Animal) -> void:
	a.speed = 0.9
	var c := Color(0.58, 0.58, 0.62)
	_quad_legs(a, 0.3, 0.5, -0.5, 0.95, 0.95, 0.26, c.darkened(0.05))
	_part(a, LowPoly.sphere(0.75, 1.3, 8, 5), c, LowPoly.xf(Vector3(0, 1.45, 0), Vector3(90, 0, 0), Vector3(0.85, 1.25, 1.0)), 0.05)
	_part(a, LowPoly.sphere(0.45, 0.85, 7, 4), c, LowPoly.xf(Vector3(0, 1.75, 0.95)))
	for s in [-1.0, 1.0]:
		_part(a, LowPoly.box(Vector3(0.5, 0.6, 0.06)), c.darkened(0.08), LowPoly.xf(Vector3(s * 0.48, 1.75, 0.8), Vector3(0, s * 30, 0)))
		_part(a, LowPoly.cone(0.06, 0.4, 5), Color(0.97, 0.95, 0.88), LowPoly.xf(Vector3(s * 0.18, 1.4, 1.3), Vector3(70, 0, 0)))
	_part(a, LowPoly.cylinder(0.08, 0.14, 0.9, 6), c, LowPoly.xf(Vector3(0, 1.2, 1.35), Vector3(15, 0, 0)))
	a.tail = Node3D.new()
	a.tail.position = Vector3(0, 1.5, -0.92)
	a.add_child(a.tail)
	_part(a.tail, LowPoly.box(Vector3(0.05, 0.5, 0.05)), c.darkened(0.1), LowPoly.xf(Vector3(0, -0.25, 0)))
