@tool
class_name CityStreet
extends Node3D
## A procedural city street, built from settings and regenerated live in the editor.
## The street runs along X, centred on z = 0: two driving lanes with parking lanes,
## kerbed sidewalks, rows of buildings with lit windows and storefronts, street lights
## and traffic (StreetCar). Generated children are internal, so they aren't saved into
## the scene. `height_at()` gives the walking surface height (for cameras).
##
## Traffic drives on the right: toward +X in the lane at +z, toward -X at -z.

@export var street_length: float = 240.0:
	set(value):
		street_length = maxf(value, 40.0)
		_queue_rebuild()
## Width of one driving lane; the parking lane lies outside it.
@export var lane_width: float = 3.5:
	set(value):
		lane_width = value
		_queue_rebuild()
@export var parking_width: float = 2.5:
	set(value):
		parking_width = value
		_queue_rebuild()
@export var sidewalk_width: float = 4.0:
	set(value):
		sidewalk_width = value
		_queue_rebuild()
@export var kerb_height: float = 0.15:
	set(value):
		kerb_height = value
		_queue_rebuild()
@export var street_seed: int = 7:
	set(value):
		street_seed = value
		_queue_rebuild()
@export_range(8.0, 60.0) var light_spacing: float = 24.0:
	set(value):
		light_spacing = value
		_queue_rebuild()
@export_range(0, 40) var parked_cars: int = 12:
	set(value):
		parked_cars = value
		_queue_rebuild()
@export_range(0, 10) var cars_per_lane: int = 3:
	set(value):
		cars_per_lane = value
		_queue_rebuild()
## x of the zebra crossing (keep it inside the street).
@export var crosswalk_x: float = 0.0:
	set(value):
		crosswalk_x = value
		_queue_rebuild()

const SEGMENT := 20.0
const BUILDING_DEPTH := 14.0
const FACADE_COLORS := [
	Color(0.47, 0.42, 0.37), Color(0.55, 0.35, 0.28), Color(0.62, 0.58, 0.5),
	Color(0.36, 0.38, 0.42), Color(0.5, 0.47, 0.42), Color(0.42, 0.3, 0.26),
	Color(0.58, 0.52, 0.44), Color(0.32, 0.33, 0.36),
]
const CAR_COLORS := [
	Color(0.55, 0.07, 0.07), Color(0.1, 0.18, 0.4), Color(0.85, 0.85, 0.82), Color(0.08, 0.08, 0.09),
	Color(0.45, 0.47, 0.5), Color(0.12, 0.3, 0.2), Color(0.75, 0.55, 0.12), Color(0.25, 0.25, 0.28),
]

var _rng := RandomNumberGenerator.new()
var _rebuild_queued := false
var _root: Node3D          # internal container for everything generated
var _body: StaticBody3D


func _ready() -> void:
	rebuild()


## Height of the walking surface at a world position: the sidewalk or the road.
func height_at(_world_x: float, world_z: float) -> float:
	var z := absf(world_z - global_position.z)
	var on_sidewalk := z >= road_half_width() and z <= road_half_width() + sidewalk_width
	return global_position.y + (kerb_height if on_sidewalk else 0.0)


func road_half_width() -> float:
	return lane_width + parking_width


func rebuild() -> void:
	_rebuild_queued = false
	if _root:
		_root.queue_free()
	_root = Node3D.new()
	_root.name = "Generated"
	add_child(_root, false, Node.INTERNAL_MODE_FRONT)
	_rng.seed = street_seed
	_body = StaticBody3D.new()
	_body.name = "StreetBody"
	_add(_body)
	var road := road_half_width()
	var half := street_length * 0.5
	var extent := half + 30.0

	# Road and sidewalks, in segments so each picks up only its nearby street lights
	# (the Compatibility renderer limits lights per mesh).
	var road_mat := ShaderMaterial.new()
	road_mat.shader = preload("res://game/city/road.gdshader")
	road_mat.set_shader_parameter("lane_width", lane_width)
	road_mat.set_shader_parameter("road_half_width", road)
	road_mat.set_shader_parameter("crosswalk_x", crosswalk_x)
	var walk_mat := ShaderMaterial.new()
	walk_mat.shader = preload("res://game/city/sidewalk.gdshader")
	walk_mat.set_shader_parameter("kerb_z", road)
	var x := -extent
	while x < extent:
		var plane := PlaneMesh.new()
		plane.size = Vector2(SEGMENT, road * 2.0)
		_mesh(plane, Vector3(x + SEGMENT * 0.5, 0, 0), road_mat)
		for side: float in [-1.0, 1.0]:
			var slab := BoxMesh.new()
			slab.size = Vector3(SEGMENT, kerb_height, sidewalk_width)
			_mesh(slab, Vector3(x + SEGMENT * 0.5, kerb_height * 0.5, side * (road + sidewalk_width * 0.5)), walk_mat)
		x += SEGMENT
	_box_shape(Vector3(extent * 2.0, 1.0, (road + sidewalk_width) * 2.0 + 4.0), Vector3(0, -0.5, 0))
	for side: float in [-1.0, 1.0]:
		_box_shape(Vector3(extent * 2.0, kerb_height, sidewalk_width), Vector3(0, kerb_height * 0.5, side * (road + sidewalk_width * 0.5)))
		_kerb_ramp(side, road, extent)
		_buildings(side, road + sidewalk_width, extent)
		_street_lights(side, road, half)
	# Buildings closing off both ends of the street, and walls keeping walkers inside.
	for end: float in [-1.0, 1.0]:
		var width := (road + sidewalk_width) * 2.0
		_building(Vector3(end * (extent + BUILDING_DEPTH * 0.5), 0, 0), Vector3(BUILDING_DEPTH, _rng.randf_range(14, 30), width + 2.0 * BUILDING_DEPTH))
		_box_shape(Vector3(1.0, 10.0, width), Vector3(end * (half + 6.0), 5.0, 0))
	_traffic(half)


func _queue_rebuild() -> void:
	if not is_node_ready() or _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func _add(node: Node) -> void:
	_root.add_child(node)


func _mesh(mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	_add(mi)
	return mi


func _box_shape(size: Vector3, pos: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	_body.add_child(shape)


## A sloped collider along the kerb (kerb_height over 0.3 m), so a CharacterBody3D
## walks up onto the sidewalk instead of being stopped by the step.
func _kerb_ramp(side: float, road: float, extent: float) -> void:
	var z0 := side * (road - 0.3)
	var z1 := side * road
	var shape := CollisionShape3D.new()
	var prism := ConvexPolygonShape3D.new()
	prism.points = PackedVector3Array([
		Vector3(-extent, 0, z0), Vector3(-extent, 0, z1), Vector3(-extent, kerb_height, z1),
		Vector3(extent, 0, z0), Vector3(extent, 0, z1), Vector3(extent, kerb_height, z1),
	])
	shape.shape = prism
	_body.add_child(shape)


func _buildings(side: float, front: float, extent: float) -> void:
	var x := -extent
	while x < extent:
		var w := _rng.randf_range(8.0, 20.0)
		if _rng.randf() < 0.15:
			x += 3.0    # an alley
		var h := _rng.randf_range(9.0, 36.0)
		var depth := BUILDING_DEPTH + _rng.randf_range(-2.0, 2.0)
		var setback := _rng.randf_range(0.0, 0.6)
		_building(Vector3(x + w * 0.5, 0, side * (front + setback + depth * 0.5)), Vector3(w, h, depth))
		x += w


func _building(base: Vector3, size: Vector3) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://game/city/facade.gdshader")
	var wall: Color = FACADE_COLORS[_rng.randi_range(0, FACADE_COLORS.size() - 1)]
	mat.set_shader_parameter("wall_color", wall)
	mat.set_shader_parameter("trim_color", wall.darkened(0.35))
	mat.set_shader_parameter("seed", _rng.randf_range(0.0, 100.0))
	mat.set_shader_parameter("lit_fraction", _rng.randf_range(0.2, 0.5))
	mat.set_shader_parameter("bay_width", _rng.randf_range(2.4, 3.4))
	var box := BoxMesh.new()
	box.size = size
	_mesh(box, base + Vector3(0, size.y * 0.5, 0), mat)
	_box_shape(size, base + Vector3(0, size.y * 0.5, 0))
	# A cornice along the top.
	var cornice := BoxMesh.new()
	cornice.size = Vector3(size.x + 0.4, 0.5, size.z + 0.4)
	var trim := StandardMaterial3D.new()
	trim.albedo_color = wall.darkened(0.4)
	_mesh(cornice, base + Vector3(0, size.y + 0.25, 0), trim)


## Lamp posts along the kerb, staggered between the two sides, each with an arm over
## the road carrying a glowing lamp and a downward spot light.
func _street_lights(side: float, road: float, half: float) -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.12, 0.13, 0.14)
	pole_mat.metallic = 0.6
	pole_mat.roughness = 0.4
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1, 0.9, 0.7)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1, 0.82, 0.55)
	lamp_mat.emission_energy_multiplier = 4.0
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.09
	pole.height = 6.0
	pole.radial_segments = 10
	pole.rings = 0
	var arm := BoxMesh.new()
	arm.size = Vector3(0.08, 0.08, 1.8)
	var head := BoxMesh.new()
	head.size = Vector3(0.35, 0.12, 0.7)
	var x := -half + (light_spacing * 0.5 if side > 0.0 else 0.0) + 4.0
	while x <= half:
		var z := side * (road + 0.45)
		_mesh(pole, Vector3(x, kerb_height + 3.0, z), pole_mat)
		_mesh(arm, Vector3(x, kerb_height + 5.9, z - side * 0.85), pole_mat)
		_mesh(head, Vector3(x, kerb_height + 5.8, z - side * 1.6), lamp_mat)
		var spot := SpotLight3D.new()
		spot.position = Vector3(x, kerb_height + 5.7, z - side * 1.6)
		spot.rotation = Vector3(-PI * 0.5, 0, 0)
		spot.light_color = Color(1, 0.84, 0.6)
		spot.light_energy = 6.0
		spot.spot_range = 14.0
		spot.spot_angle = 62.0
		spot.spot_attenuation = 0.8
		_add(spot)
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.12
		cyl.height = 6.0
		shape.shape = cyl
		shape.position = Vector3(x, 3.0, z)
		_body.add_child(shape)
		x += light_spacing


## Parked cars along both kerbs (facing the traffic on their side) and driving cars
## spread along both lanes.
func _traffic(half: float) -> void:
	var stalls: Array[Vector2] = []    # (x, side)
	for side: float in [-1.0, 1.0]:
		var sx := -half + 3.0
		while sx < half - 3.0:
			if absf(sx - crosswalk_x) > 6.0:
				stalls.append(Vector2(sx, side))
			sx += 6.0
	for i in mini(parked_cars, stalls.size()):
		var k := _rng.randi_range(i, stalls.size() - 1)
		var stall := stalls[k]
		stalls[k] = stalls[i]
		var car := StreetCar.new()
		car.paint = CAR_COLORS[_rng.randi_range(0, CAR_COLORS.size() - 1)]
		car.direction = stall.y
		car.position = Vector3(stall.x + _rng.randf_range(-0.4, 0.4), 0, stall.y * (lane_width + parking_width * 0.5 - 0.05))
		_add(car)
	for side: float in [-1.0, 1.0]:
		for i in cars_per_lane:
			var car := StreetCar.new()
			car.paint = CAR_COLORS[_rng.randi_range(0, CAR_COLORS.size() - 1)]
			car.direction = side
			car.cruise_speed = _rng.randf_range(8.0, 12.0)
			car.wrap_extent = half + 20.0
			var spacing := (street_length + 40.0) / maxf(cars_per_lane, 1)
			car.position = Vector3(-half - 20.0 + spacing * (i + 0.5 * (side + 1.0) * 0.5), 0, side * lane_width * 0.5)
			_add(car)
