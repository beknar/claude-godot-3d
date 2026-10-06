class_name OrbitCamera
extends Camera3D
## Third-person orbit camera. The mouse swings it around the target, whose controller
## moves relative to the camera's heading (`get_yaw()`). It pulls back while the
## target flies, zooms with the mouse wheel and stays above the terrain.

@export var target: Node3D
## Height above the target's origin that the camera looks at.
@export var focus_height: float = 1.3
@export var distance: float = 4.5
## Distance while the target `is_flying()`.
@export var flying_distance: float = 6.5
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.5
## Degrees of turn per pixel of mouse movement.
@export var mouse_sensitivity: float = 0.15
@export var invert_mouse_y: bool = false
@export var min_pitch_deg: float = -75.0
@export var max_pitch_deg: float = 45.0
@export var follow_sharpness: float = 12.0
## Optional node with `height_at(x, z)` (RollingHillsTerrain, CityStreet) the camera keeps above.
@export var terrain: Node3D
@export var ground_clearance: float = 0.5
## Pull the camera in front of anything (on `obstacle_mask`) between it and the target.
@export var avoid_obstacles: bool = true
@export_flags_3d_physics var obstacle_mask: int = 1
@export var obstacle_margin: float = 0.3

var _yaw := 0.0
var _pitch := deg_to_rad(-15.0)
var _zoom := 1.0
var _distance := 0.0
var _focus := Vector3.ZERO


func _ready() -> void:
	# Moved every rendered frame from the target's interpolated transform instead.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_distance = distance
	if target:
		_yaw = target.global_rotation.y
		_focus = target.global_position + Vector3.UP * focus_height
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_place()


func get_yaw() -> float:
	return _yaw


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.screen_relative * deg_to_rad(mouse_sensitivity)
		_yaw -= rel.x
		_pitch += rel.y if invert_mouse_y else -rel.y
		_pitch = clampf(_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(min_zoom, _zoom * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(max_zoom, _zoom * 1.1)
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if target == null:
		return
	var flying: bool = target.has_method("is_flying") and target.call("is_flying")
	_distance = lerpf(_distance, flying_distance if flying else distance, 1.0 - exp(-2.0 * delta))
	var goal := target.get_global_transform_interpolated().origin + Vector3.UP * focus_height
	_focus = _focus.lerp(goal, 1.0 - exp(-follow_sharpness * delta))
	_place()


func _place() -> void:
	var orbit := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var pos := _focus + orbit * Vector3(0.0, 0.0, _distance * _zoom)
	if avoid_obstacles and is_inside_tree():
		var query := PhysicsRayQueryParameters3D.create(_focus, pos, obstacle_mask)
		if target is CollisionObject3D:
			query.exclude = [(target as CollisionObject3D).get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			pos = hit.position + (_focus - pos).normalized() * obstacle_margin
	if terrain and terrain.has_method("height_at"):
		pos.y = maxf(pos.y, float(terrain.call("height_at", pos.x, pos.z)) + ground_clearance)
	global_position = pos
	if not pos.is_equal_approx(_focus):
		look_at(_focus, Vector3.UP)
