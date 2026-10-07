@tool
class_name StreetCar
extends AnimatableBody3D
## A simple procedural car built from boxes and cylinders. Parked cars stand still.
## Driving cars follow their lane along X, ease off for the player or the car ahead,
## and reappear at the far end of the street after driving off one end. Its front is
## local +X; a car driving toward -X is turned round.

@export var paint := Color(0.55, 0.08, 0.08)
## Cruising speed in m/s; 0 makes a parked car.
@export var cruise_speed: float = 0.0
## +1 drives toward +X, -1 toward -X.
@export var direction: float = 1.0
## Beyond this |x| a driving car wraps to the other end of the street.
@export var wrap_extent: float = 140.0
@export var acceleration: float = 3.5
@export var braking: float = 9.0
## Gap (between bumpers) at which it starts slowing; it stops by about 2 m.
@export var safe_gap: float = 10.0

const LENGTH := 4.3
const WIDTH := 1.82
const WHEEL_RADIUS := 0.34

var speed := 0.0
var _wheels: Array[Node3D] = []
var _brake_material: StandardMaterial3D
var _wheel_angle := 0.0


func _ready() -> void:
	add_to_group("street_cars")
	_build()
	speed = cruise_speed


func is_driving() -> bool:
	return cruise_speed > 0.0


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_driving():
		return
	var target := cruise_speed * clampf((_gap_ahead() - 2.0) / (safe_gap - 2.0), 0.0, 1.0)
	speed = move_toward(speed, target, (acceleration if target > speed else braking) * delta)
	var pos := global_position
	pos.x += direction * speed * delta
	if direction * pos.x > wrap_extent:
		pos.x = -direction * wrap_extent
	global_position = pos
	_wheel_angle -= speed * delta / WHEEL_RADIUS
	for wheel in _wheels:
		wheel.rotation.z = _wheel_angle
	if _brake_material:
		var braking_now := target < speed - 0.1 or speed < 0.5
		_brake_material.emission_energy_multiplier = 3.0 if braking_now else 0.8


## Distance to whatever is ahead in this lane: the player (anything in the "player"
## group) or another car, bumper to bumper.
func _gap_ahead() -> float:
	var gap := INF
	var lane_z := global_position.z
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as Node3D
		if body and absf(body.global_position.z - lane_z) < 1.8:
			var ahead := (body.global_position.x - global_position.x) * direction - LENGTH * 0.5 - 0.4
			if ahead > -1.0:
				gap = minf(gap, ahead)
	for node in get_tree().get_nodes_in_group("street_cars"):
		var car := node as StreetCar
		if car == self or absf(car.global_position.z - lane_z) > 1.2:
			continue
		var ahead := (car.global_position.x - global_position.x) * direction - LENGTH
		if ahead > -0.5:
			gap = minf(gap, ahead)
	return gap


func _build() -> void:
	rotation.y = 0.0 if direction > 0.0 else PI
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = paint
	body_mat.metallic = 0.5
	body_mat.roughness = 0.3
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.07, 0.1)
	glass.metallic = 0.6
	glass.roughness = 0.1
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.05)
	dark.roughness = 0.8
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.7, 0.7, 0.72)
	chrome.metallic = 1.0
	chrome.roughness = 0.25

	_box(Vector3(LENGTH, 0.62, WIDTH), Vector3(0, 0.62, 0), body_mat)            # lower body
	_box(Vector3(LENGTH * 0.96, 0.12, WIDTH * 0.96), Vector3(0, 0.98, 0), body_mat)  # beltline
	_box(Vector3(2.2, 0.55, WIDTH * 0.86), Vector3(-0.25, 1.3, 0), glass)         # cabin glass
	_box(Vector3(2.0, 0.06, WIDTH * 0.84), Vector3(-0.3, 1.6, 0), body_mat)       # roof
	_box(Vector3(0.14, 0.2, WIDTH * 0.98), Vector3(LENGTH * 0.5, 0.42, 0), dark)  # front bumper
	_box(Vector3(0.14, 0.2, WIDTH * 0.98), Vector3(-LENGTH * 0.5, 0.42, 0), dark)
	_box(Vector3(0.05, 0.12, 0.7), Vector3(LENGTH * 0.5 + 0.02, 0.66, 0), chrome)  # grille

	var head := StandardMaterial3D.new()
	head.albedo_color = Color(1, 0.97, 0.88)
	head.emission_enabled = true
	head.emission = Color(1, 0.95, 0.82)
	head.emission_energy_multiplier = 2.5 if is_driving() else 0.0
	_brake_material = StandardMaterial3D.new()
	_brake_material.albedo_color = Color(0.5, 0.02, 0.02)
	_brake_material.emission_enabled = true
	_brake_material.emission = Color(1, 0.05, 0.03)
	_brake_material.emission_energy_multiplier = 0.8 if is_driving() else 0.0
	for side in [-1.0, 1.0]:
		_box(Vector3(0.06, 0.12, 0.34), Vector3(LENGTH * 0.5 + 0.02, 0.74, side * 0.62), head)
		_box(Vector3(0.06, 0.12, 0.3), Vector3(-LENGTH * 0.5 - 0.02, 0.76, side * 0.66), _brake_material)
	if is_driving():
		var beam := SpotLight3D.new()
		beam.position = Vector3(LENGTH * 0.5 + 0.2, 0.75, 0)
		beam.rotation = Vector3(deg_to_rad(-8.0), deg_to_rad(-90.0), 0)
		beam.light_color = Color(1, 0.93, 0.8)
		beam.light_energy = 2.5
		beam.spot_range = 18.0
		beam.spot_angle = 32.0
		beam.distance_fade_enabled = true
		beam.distance_fade_begin = 60.0
		beam.distance_fade_length = 15.0
		add_child(beam, false, Node.INTERNAL_MODE_FRONT)

	var tyre := CylinderMesh.new()
	tyre.top_radius = WHEEL_RADIUS
	tyre.bottom_radius = WHEEL_RADIUS
	tyre.height = 0.24
	tyre.radial_segments = 16
	tyre.rings = 0
	for x in [LENGTH * 0.32, -LENGTH * 0.32]:
		for side in [-1.0, 1.0]:
			var spin := Node3D.new()
			spin.position = Vector3(x, WHEEL_RADIUS, side * (WIDTH * 0.5 - 0.1))
			add_child(spin, false, Node.INTERNAL_MODE_FRONT)
			var wheel := MeshInstance3D.new()
			wheel.mesh = tyre
			wheel.rotation.x = PI * 0.5
			wheel.material_override = dark
			spin.add_child(wheel)
			var hub := MeshInstance3D.new()
			var hub_mesh := CylinderMesh.new()
			hub_mesh.top_radius = 0.18
			hub_mesh.bottom_radius = 0.18
			hub_mesh.height = 0.25
			hub_mesh.radial_segments = 8
			hub_mesh.rings = 0
			hub.mesh = hub_mesh
			hub.rotation.x = PI * 0.5
			hub.material_override = chrome
			spin.add_child(hub)
			_wheels.append(spin)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(LENGTH, 1.4, WIDTH)
	shape.shape = box
	shape.position = Vector3(0, 0.85, 0)
	add_child(shape, false, Node.INTERNAL_MODE_FRONT)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	add_child(mi, false, Node.INTERNAL_MODE_FRONT)
