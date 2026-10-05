class_name ChaseCamera
extends Camera3D
## Smooth third-person camera that trails behind a target. It follows a smoothed
## copy of the target's orientation, so it rolls and loops with the ship instead of
## flipping when the nose points straight up or down.

@export var target: Node3D
## Camera position relative to the target, in the target's (smoothed) frame
## (+Z is behind, +Y is above).
@export var offset: Vector3 = Vector3(0.0, 6.0, 26.0)
## How far ahead of the target the camera aims.
@export var look_ahead: float = 30.0
@export var follow_sharpness: float = 6.0
## How quickly the camera's frame catches up with the target's rotation (per second).
@export var rotation_sharpness: float = 5.0
## When false, the camera keeps the world horizon level instead of rolling.
@export var follow_roll: bool = true
@export var base_fov: float = 70.0
## Extra field of view added at full boost, for a sense of speed.
@export var boost_fov_bonus: float = 14.0

var _frame := Basis.IDENTITY


func _ready() -> void:
	fov = base_fov
	if target:
		_frame = target.global_basis.orthonormalized()
		global_position = _desired_position()
		_aim()


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var goal := target.global_basis.orthonormalized()
	_frame = _frame.slerp(goal, 1.0 - exp(-rotation_sharpness * delta)).orthonormalized()
	global_position = global_position.lerp(_desired_position(), 1.0 - exp(-follow_sharpness * delta))
	_aim()
	_update_fov(delta)


func _desired_position() -> Vector3:
	var frame := _frame
	if not follow_roll:
		var forward := -_frame.z
		if absf(forward.y) < 0.99:
			frame = Basis.looking_at(forward, Vector3.UP)
	return target.global_position + frame * offset


func _aim() -> void:
	var aim_point := target.global_position - _frame.z * look_ahead
	var up := _frame.y if follow_roll else Vector3.UP
	if not global_position.is_equal_approx(aim_point):
		look_at(aim_point, up)


func _update_fov(delta: float) -> void:
	var speed = target.get("speed")
	var cruise = target.get("max_speed")
	var boost = target.get("boost_speed")
	if speed == null or cruise == null or boost == null or boost <= cruise:
		return
	var boost_amount := clampf((speed - cruise) / (boost - cruise), 0.0, 1.0)
	fov = lerpf(fov, base_fov + boost_fov_bonus * boost_amount, 1.0 - exp(-4.0 * delta))
