class_name FigureProcedural
extends Node
## Procedural layers on top of a walking figure's animation (a WalkerController with a
## figure from tools/build_figure.gd), added as skeleton modifiers at run time:
## - Feet: two-bone IK plants each foot on the visible ground under it. Clips assume
##   flat ground at her feet, but the kerb's invisible ramp lifts her body up to 15 cm,
##   so one foot hung in the air. The lower foot sets how far her hips drop.
## - Look: neck and head turn toward a target that drifts smoothly: ahead along her path
##   while she moves, and while she stands, passing cars, the camera, or an idle glance.

@export var walker: WalkerController
## The figure's Skeleton3D (bone names as tools/build_figure.gd makes them).
@export var skeleton: Skeleton3D
## A node with `height_at(x, z)` returning the visible ground height (CityStreet). Without
## one, the ground is found by casting rays down at each foot.
@export var ground: Node3D
## Looked at while she stands, when it's in front of her.
@export var camera: Node3D

@export_group("Feet")
@export var foot_ik: bool = true
## Largest step up or down each foot reaches for (m).
@export var max_foot_offset: float = 0.22
## How quickly the hips follow the lower foot (per second).
@export var hip_sharpness: float = 12.0
## Seconds to let go of the ground on take-off and to take hold on landing.
@export var ik_release_time: float = 0.08
@export var ik_catch_time: float = 0.15

@export_group("Look")
@export var look_at: bool = true
## Cars and the camera beyond this distance (m) aren't looked at.
@export var look_range: float = 18.0
## How quickly the gaze target drifts to a new point (per second).
@export var look_sharpness: float = 4.0
## Share of the turn taken by the neck (the head takes the rest).
@export_range(0.0, 1.0) var neck_share: float = 0.35

const SIDES := ["Left", "Right"]

var _ik: TwoBoneIK3D
var _targets: Array[Node3D] = []
var _poles: Array[Node3D] = []
var _bones := {}
var _model: Node3D
var _model_base_y := 0.0
var _drop := 0.0
var _ik_hold := 1.0
var _ik_tween: Tween
var _was_on_floor := true
var _look_target: Node3D
var _gaze := Vector3.ZERO
var _cars: Array[Node3D] = []
var _glance := Vector3.ZERO
var _glance_timer := 2.0


func _ready() -> void:
	if skeleton == null or walker == null:
		push_warning("FigureProcedural needs a walker and a skeleton")
		return
	for bone in ["Hips", "Neck", "Head", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
			"RightUpperLeg", "RightLowerLeg", "RightFoot"]:
		_bones[bone] = skeleton.find_bone(bone)
	# The figure's scene root: lowered with the hips so the lower foot can reach down.
	_model = skeleton.get_parent() as Node3D
	_model_base_y = _model.position.y
	# Modifiers run in child order: these go before the spring bones, so hair and bust
	# follow the corrected pose.
	var first := 0
	for child in skeleton.get_children():
		if child is SpringBoneSimulator3D:
			first = child.get_index()
			break
	if foot_ik:
		_add_foot_ik(first)
	if look_at:
		_add_look_at(first)
	_find_cars(get_tree().current_scene)


func _add_foot_ik(index: int) -> void:
	_ik = TwoBoneIK3D.new()
	_ik.name = "FootIK"
	skeleton.add_child(_ik)
	skeleton.move_child(_ik, index)
	_ik.setting_count = 2
	for i in 2:
		var target := Node3D.new()
		target.name = SIDES[i] + "FootTarget"
		target.top_level = true
		add_child(target)
		_targets.append(target)
		var pole := Node3D.new()
		pole.name = SIDES[i] + "KneePole"
		pole.top_level = true
		add_child(pole)
		_poles.append(pole)
		_ik.set_root_bone_name(i, SIDES[i] + "UpperLeg")
		_ik.set_middle_bone_name(i, SIDES[i] + "LowerLeg")
		_ik.set_end_bone_name(i, SIDES[i] + "Foot")
		_ik.set_target_node(i, _ik.get_path_to(target))
		_ik.set_pole_node(i, _ik.get_path_to(pole))
	_ik.influence = 0.0


func _add_look_at(index: int) -> void:
	_look_target = Node3D.new()
	_look_target.name = "LookTarget"
	_look_target.top_level = true
	add_child(_look_target)
	# The figure faces -Z, and every rest basis is identity, so -Z is each bone's forward.
	for bone_name in ["Neck", "Head"]:
		var look := LookAtModifier3D.new()
		look.name = bone_name + "LookAt"
		skeleton.add_child(look)
		skeleton.move_child(look, index)
		index += 1
		look.bone_name = bone_name
		look.forward_axis = SkeletonModifier3D.BONE_AXIS_MINUS_Z
		look.primary_rotation_axis = Vector3.AXIS_Y
		look.use_secondary_rotation = true
		look.relative = true
		look.target_node = look.get_path_to(_look_target)
		look.use_angle_limitation = true
		look.symmetry_limitation = true
		look.primary_limit_angle = deg_to_rad(140.0)
		look.primary_damp_threshold = 0.6
		look.secondary_limit_angle = deg_to_rad(60.0)
		look.secondary_damp_threshold = 0.6
		look.duration = 0.4
		look.transition_type = Tween.TRANS_SINE
		look.ease_type = Tween.EASE_IN_OUT
		look.influence = neck_share if bone_name == "Neck" else 0.8
	_gaze = _forward_point(4.0)


func _find_cars(node: Node) -> void:
	if node == null:
		return
	if node is StreetCar:
		_cars.append(node)
	for child in node.get_children():
		_find_cars(child)


func _process(delta: float) -> void:
	if skeleton == null or walker == null:
		return
	if _ik:
		_update_feet(delta)
	if _look_target:
		_update_look(delta)


# ---------------------------------------------------------------- feet

func _update_feet(delta: float) -> void:
	# Let go of the ground in the air and take hold again on landing, eased by a tween.
	var on_floor := walker.is_on_floor()
	if on_floor != _was_on_floor:
		_was_on_floor = on_floor
		if _ik_tween:
			_ik_tween.kill()
		_ik_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_ik_tween.tween_property(self, "_ik_hold", 1.0 if on_floor else 0.0,
				ik_catch_time if on_floor else ik_release_time)

	var floor_y := walker.global_position.y
	var skel_xf := skeleton.global_transform
	var lift := Vector3(0.0, _drop, 0.0)
	var offsets: Array[float] = []
	var feet: Array[Vector3] = []
	for side: String in SIDES:
		# The animated pose (spring bones and IK aren't in it); without the hip drop.
		var foot := skel_xf * skeleton.get_bone_global_pose(_bones[side + "Foot"]).origin - lift
		feet.append(foot)
		var offset := clampf(_ground_height(foot.x, foot.z, floor_y) - floor_y, -max_foot_offset, max_foot_offset)
		offsets.append(offset)

	# Uneven ground under her feet: blend the IK in; on flat ground the clip plays as made.
	var uneven := maxf(absf(offsets[0]), absf(offsets[1]))
	var amount := smoothstep(0.008, 0.03, uneven) * _ik_hold
	var drop_goal := minf(0.0, minf(offsets[0], offsets[1])) * amount
	_drop = lerpf(_drop, drop_goal, 1.0 - exp(-hip_sharpness * delta))
	_model.position.y = _model_base_y + _drop
	_ik.influence = amount

	var forward := -_model.global_basis.z.normalized()
	for i in 2:
		var knee := skel_xf * skeleton.get_bone_global_pose(_bones[SIDES[i] + "LowerLeg"]).origin - lift
		var up := Vector3(0.0, offsets[i], 0.0)
		_targets[i].global_position = feet[i] + up
		_poles[i].global_position = knee + up + forward * 0.5


func _ground_height(x: float, z: float, floor_y: float) -> float:
	if ground and ground.has_method("height_at"):
		return ground.call("height_at", x, z)
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, floor_y + 0.6, z), Vector3(x, floor_y - 0.6, z))
	query.exclude = [walker.get_rid()]
	var hit := walker.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if hit else floor_y


# ---------------------------------------------------------------- look

func _update_look(delta: float) -> void:
	var head := skeleton.global_transform * skeleton.get_bone_global_pose(_bones["Head"]).origin
	var velocity := Vector3(walker.velocity.x, 0.0, walker.velocity.z)
	var goal: Vector3
	if not walker.is_on_floor():
		# In the air: down toward where she'll land.
		goal = _forward_point(1.5) + velocity * 0.4 + Vector3.DOWN * 1.2
	elif velocity.length() > 0.3:
		# Ahead along her path, a few steps on and a little down. Her body turns to her
		# velocity more slowly, so the gaze leads into turns.
		goal = head + velocity.normalized() * 5.0 + Vector3.DOWN * 0.9
	else:
		goal = _idle_interest(head, delta)
	_gaze = _gaze.lerp(goal, 1.0 - exp(-look_sharpness * delta))
	_look_target.global_position = _gaze


## Standing: the nearest passing car in front of her, else the camera when it's in front,
## else straight ahead with a glance aside every few seconds.
func _idle_interest(head: Vector3, delta: float) -> Vector3:
	var forward := -_model.global_basis.z.normalized()
	var best: Node3D = null
	var best_d := look_range
	for car in _cars:
		if not is_instance_valid(car) or float(car.get("cruise_speed")) <= 0.0:
			continue
		var to := car.global_position - head
		var d := to.length()
		if d < best_d and forward.dot(to / d) > -0.2:
			best = car
			best_d = d
	if best:
		return best.global_position + Vector3.UP * 0.7
	if camera:
		var to_cam := camera.global_position - head
		if to_cam.length() < look_range and forward.dot(to_cam.normalized()) > 0.35:
			return camera.global_position
	_glance_timer -= delta
	if _glance_timer <= 0.0:
		var looking_aside := _glance != Vector3.ZERO
		_glance = Vector3.ZERO if looking_aside else Vector3(randf_range(-1.6, 1.6), randf_range(-0.6, 0.3), 0.0)
		_glance_timer = randf_range(3.0, 6.0) if looking_aside else randf_range(1.2, 2.2)
	return _forward_point(4.0) + _model.global_basis * _glance


func _forward_point(distance: float) -> Vector3:
	return _head_base() + -_model.global_basis.z.normalized() * distance


func _head_base() -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(_bones["Head"]).origin
