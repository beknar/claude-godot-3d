class_name WalkerController
extends CharacterBody3D
## Third-person controller for a walking figure (fig1/fig1.tscn): WASD to walk relative
## to the camera, Shift to run, Space to jump. The model turns to face where it's
## going. An AnimationTree built in code blends the figure's clips: idle/walk/run by
## ground speed (time-scaled so the feet don't slide), jump/fall by vertical speed in
## the air, and a one-shot landing crouch on touchdown.

signal jumped
signal landed

## Camera rig with a `get_yaw()` method; movement is relative to its heading.
@export var camera_rig: Node3D
## Turned to face the direction of travel; holds the model.
@export var model_pivot: Node3D
## The model's AnimationPlayer (holds the clips the tree blends).
@export var animation_player: AnimationPlayer
@export var hud_label: Label

@export_group("Movement")
@export var walk_speed: float = 1.5
@export var run_speed: float = 5.0
## How quickly she reaches the requested speed on the ground (m/s per second).
@export var acceleration: float = 12.0
@export var air_control: float = 3.0
@export var jump_velocity: float = 4.8
## Multiple of the project's gravity (Project Settings > Physics > 3D > Default Gravity).
## Applied every frame, on the ground too, so she stays pressed to floors, kerbs and slopes.
@export var gravity_scale: float = 1.8
## Extra pull while falling, so jumps come down briskly instead of floating.
@export var fall_gravity_multiplier: float = 1.4
@export var turn_sharpness: float = 10.0
## Grace period after stepping off an edge during which a jump still works.
@export var coyote_time: float = 0.12
## A jump pressed this long before landing still happens on touchdown.
@export var jump_buffer: float = 0.15
## Landing faster than this (m/s, downward) plays the landing crouch.
@export var hard_landing_speed: float = 3.0

@export_group("Animation")
## Metres covered by one walk / run cycle (two steps), for foot sync.
@export var walk_stride: float = 1.35
@export var run_stride: float = 3.2

var _yaw := 0.0
var _air_time := 0.0
var _buffered := 0.0
var _fall_speed := 0.0
var _was_on_floor := true
var _tree: AnimationTree
var _ground_blend := 0.0
var _air_amount := 0.0
var _rise_fall := 0.0


func _ready() -> void:
	add_to_group("player")
	floor_snap_length = 0.25
	floor_max_angle = deg_to_rad(50.0)
	if model_pivot:
		_yaw = model_pivot.rotation.y
	_build_animation_tree()


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var heading_yaw: float = camera_rig.call("get_yaw") if camera_rig and camera_rig.has_method("get_yaw") else 0.0
	var wish := Basis(Vector3.UP, heading_yaw) * Vector3(input.x, 0.0, input.y)
	var on_floor := is_on_floor()

	var target := wish * (run_speed if Input.is_action_pressed("move_run") else walk_speed)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(target, (acceleration if on_floor else air_control) * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	_air_time = 0.0 if on_floor else _air_time + delta
	_buffered = jump_buffer if Input.is_action_just_pressed("move_jump") else maxf(_buffered - delta, 0.0)
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale
	if velocity.y < 0.0:
		g *= fall_gravity_multiplier
	velocity.y -= g * delta
	if on_floor and velocity.y < 0.0:
		velocity.y = -g * delta     # one frame's pull: stays grounded without building up speed
	if _buffered > 0.0 and _air_time <= coyote_time:
		velocity.y = jump_velocity
		_buffered = 0.0
		_air_time = coyote_time + 1.0    # no second jump from the grace period
		jumped.emit()
	_fall_speed = maxf(_fall_speed, -velocity.y) if not on_floor else _fall_speed

	move_and_slide()

	if is_on_floor() and not _was_on_floor:
		if _fall_speed > hard_landing_speed and _tree:
			_tree.set("parameters/land/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		_fall_speed = 0.0
		landed.emit()
	_was_on_floor = is_on_floor()

	_orient_model(delta)
	_update_animation(delta)
	_update_hud()


func _orient_model(delta: float) -> void:
	if model_pivot == null:
		return
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() > 0.2:
		_yaw = lerp_angle(_yaw, atan2(-horizontal.x, -horizontal.z), 1.0 - exp(-turn_sharpness * delta))
	model_pivot.rotation.y = _yaw


# ---------------------------------------------------------------- animation

func _build_animation_tree() -> void:
	if animation_player == null:
		return
	var tree_root := AnimationNodeBlendTree.new()
	var ground := AnimationNodeBlendSpace1D.new()
	ground.min_space = 0.0
	ground.max_space = 2.0
	ground.sync = true
	ground.add_blend_point(_clip("idle"), 0.0, -1, &"idle")
	ground.add_blend_point(_clip("walk"), 1.0, -1, &"walk")
	ground.add_blend_point(_clip("run"), 2.0, -1, &"run")
	tree_root.add_node("ground", ground)
	tree_root.add_node("ground_scale", AnimationNodeTimeScale.new())
	tree_root.connect_node("ground_scale", 0, "ground")
	var air := AnimationNodeBlendSpace1D.new()
	air.min_space = 0.0
	air.max_space = 1.0
	air.add_blend_point(_clip("jump"), 0.0, -1, &"jump")
	air.add_blend_point(_clip("fall"), 1.0, -1, &"fall")
	tree_root.add_node("air", air)
	tree_root.add_node("airborne", AnimationNodeBlend2.new())
	tree_root.connect_node("airborne", 0, "ground_scale")
	tree_root.connect_node("airborne", 1, "air")
	var land := AnimationNodeOneShot.new()
	land.fadein_time = 0.05
	land.fadeout_time = 0.12
	tree_root.add_node("land", land)
	tree_root.add_node("land_clip", _clip("land"))
	tree_root.connect_node("land", 0, "airborne")
	tree_root.connect_node("land", 1, "land_clip")
	tree_root.connect_node("output", 0, "land")

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	animation_player.get_parent().add_child(_tree)
	_tree.anim_player = _tree.get_path_to(animation_player)
	_tree.root_node = _tree.get_path_to(animation_player.get_node(animation_player.root_node))
	_tree.tree_root = tree_root
	_tree.active = true


func _clip(clip_name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip_name
	return node


func _update_animation(delta: float) -> void:
	if _tree == null:
		return
	var blend := 1.0 - exp(-8.0 * delta)
	var h := Vector3(velocity.x, 0.0, velocity.z).length()
	var ground_target := h / walk_speed
	if h > walk_speed:
		ground_target = 1.0 + (h - walk_speed) / (run_speed - walk_speed)
	_ground_blend = lerpf(_ground_blend, clampf(ground_target, 0.0, 2.0), blend)
	# Both gait clips are one-second cycles: scale time so a cycle covers one stride.
	var walk_cadence := walk_speed / walk_stride
	var cadence := lerpf(1.0, walk_cadence, _ground_blend)
	if _ground_blend > 1.0:
		cadence = lerpf(walk_cadence, run_speed / run_stride, _ground_blend - 1.0)
	# In the air for more than a moment (not just a bump in the pavement).
	var airborne := _air_time > 0.08
	_air_amount = lerpf(_air_amount, 1.0 if airborne else 0.0, 1.0 - exp(-12.0 * delta))
	_rise_fall = lerpf(_rise_fall, clampf(0.5 - velocity.y / jump_velocity, 0.0, 1.0), 1.0 - exp(-6.0 * delta))

	_tree.set("parameters/ground/blend_position", _ground_blend)
	_tree.set("parameters/ground_scale/scale", cadence)
	_tree.set("parameters/air/blend_position", _rise_fall)
	_tree.set("parameters/airborne/blend_amount", _air_amount)


# ---------------------------------------------------------------- HUD

func _update_hud() -> void:
	if hud_label == null:
		return
	var h := Vector3(velocity.x, 0.0, velocity.z).length()
	var status := "STANDING"
	if _air_time > 0.08:
		status = "JUMPING" if velocity.y > 0.0 else "FALLING"
	elif h > walk_speed * 1.2:
		status = "RUNNING"
	elif h > 0.2:
		status = "WALKING"
	var hint := "WASD move   Shift run   Space jump   Mouse look   Wheel zoom"
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		hint += "\nClick to capture the mouse"
	else:
		hint += "   Esc release mouse"
	hud_label.text = "%s   SPEED %.1f\n%s" % [status, h, hint]
