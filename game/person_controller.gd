class_name PersonController
extends CharacterBody3D
## Third-person controller for the winged cyborg (person/person.tscn): walk, run and
## jump on the ground, then take off and fly. Movement is relative to the camera's
## heading. The model turns to face where she is going and, in flight, pitches into
## her direction of travel and banks through turns. An AnimationTree built in code
## blends the model's clips: idle/walk/run by ground speed (time-scaled so the feet
## don't slide), fall while airborne, and hover/fly/glide by flight speed.

signal took_off
signal landed

enum State { GROUND, AIRBORNE, FLYING }

## Camera rig with a `get_yaw()` method; movement is relative to its heading.
@export var camera_rig: Node3D
## Turned and tilted to face her motion. Sits at body height so she pitches about her middle.
@export var model_pivot: Node3D
## The model's AnimationPlayer (holds the clips the tree blends).
@export var animation_player: AnimationPlayer
## Optional RollingHillsTerrain, for the altitude readout and the flight ceiling.
@export var terrain: Node3D
@export var hud_label: Label

@export_group("Ground")
@export var walk_speed: float = 1.8
@export var run_speed: float = 6.0
## How quickly she reaches the requested ground speed (m/s per second).
@export var ground_acceleration: float = 14.0
@export var air_control: float = 4.0
@export var jump_velocity: float = 6.0
@export var gravity: float = 16.0
## Metres covered by one cycle (two steps) of the walk and run clips.
@export var walk_stride: float = 1.6
@export var run_stride: float = 3.6

@export_group("Flight")
@export var fly_speed: float = 9.0
## Top speed while holding Shift in flight.
@export var fly_fast_speed: float = 20.0
@export var climb_speed: float = 5.0
@export var flight_acceleration: float = 6.0
## Highest she can fly above the terrain.
@export var ceiling: float = 250.0
## Distance from the terrain's centre beyond which she is turned back, so the map
## edge never comes into view.
@export var boundary_radius: float = 600.0
## Forward pitch of her body at top flight speed.
@export var max_flight_pitch_deg: float = 72.0
@export var max_bank_deg: float = 30.0

@export_group("Turning")
@export var turn_sharpness: float = 10.0
@export var tilt_sharpness: float = 4.0

@export_group("Wings")
## Seconds to fold the wings against her back once she's off the wing (landed or dropping).
@export var fold_time: float = 0.9
## Seconds to spread them again on take-off.
@export var unfold_time: float = 0.35

var state: State = State.GROUND
var _yaw := 0.0
var _pitch := 0.0
var _bank := 0.0
var _yaw_rate := 0.0
var _coyote := 0.0
var _tree: AnimationTree
var _ground_blend := 0.0
var _air_blend := 0.0
var _fall_amount := 0.0
var _fly_amount := 0.0
var _wing_fold := 1.0      # 0 spread .. 1 folded; position in the fold_wings clip
var _wing_layer := 0.0     # weight of the fold clip over the wings
var _fold_length := 1.0


func _ready() -> void:
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50.0)
	if terrain and terrain.has_method("height_at"):
		global_position.y = terrain.call("height_at", global_position.x, global_position.z) + 0.05
	if model_pivot:
		_yaw = model_pivot.rotation.y
	_build_animation_tree()


func is_flying() -> bool:
	return state == State.FLYING


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var heading_yaw: float = camera_rig.call("get_yaw") if camera_rig and camera_rig.has_method("get_yaw") else 0.0
	var wish := Basis(Vector3.UP, heading_yaw) * Vector3(input.x, 0.0, input.y)
	match state:
		State.GROUND:
			_move_ground(delta, wish)
		State.AIRBORNE:
			_move_airborne(delta, wish)
		State.FLYING:
			_move_flying(delta, wish)
	_keep_inside_boundary()
	move_and_slide()
	_update_state(delta)
	_orient_model(delta)
	_update_animation(delta)
	_update_hud()


func _move_ground(delta: float, wish: Vector3) -> void:
	var target := wish * (run_speed if Input.is_action_pressed("move_run") else walk_speed)
	_steer_horizontal(target, ground_acceleration * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("move_jump"):
		velocity.y = jump_velocity
		state = State.AIRBORNE
	elif Input.is_action_just_pressed("move_fly"):
		_take_off()


func _move_airborne(delta: float, wish: Vector3) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target := wish * maxf(horizontal.length(), walk_speed)
	_steer_horizontal(target, air_control * delta)
	velocity.y -= gravity * delta
	# A second press of Space (or F) mid-air spreads the wings.
	if Input.is_action_just_pressed("move_jump") or Input.is_action_just_pressed("move_fly"):
		_take_off()


func _move_flying(delta: float, wish: Vector3) -> void:
	var target := wish * (fly_fast_speed if Input.is_action_pressed("move_run") else fly_speed)
	if Input.is_action_pressed("move_jump"):
		target.y += climb_speed
	if Input.is_action_pressed("move_descend"):
		target.y -= climb_speed
	velocity = velocity.move_toward(target, flight_acceleration * delta)
	if _altitude() > ceiling:
		velocity.y = minf(velocity.y, 0.0)
	if Input.is_action_just_pressed("move_fly"):
		state = State.AIRBORNE   # fold the wings and drop


func _steer_horizontal(target: Vector3, step: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, step)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


## Past the boundary: cancel outward motion and ease her back in.
func _keep_inside_boundary() -> void:
	var center := terrain.global_position if terrain else Vector3.ZERO
	var offset := Vector3(global_position.x - center.x, 0.0, global_position.z - center.z)
	var dist := offset.length()
	if dist <= boundary_radius:
		return
	var outward := offset / dist
	var out_speed := velocity.dot(outward)
	if out_speed > 0.0:
		velocity -= outward * out_speed
	velocity -= outward * minf(dist - boundary_radius, 5.0)


func _take_off() -> void:
	state = State.FLYING
	velocity.y = maxf(velocity.y, 3.0)
	took_off.emit()


func _update_state(delta: float) -> void:
	match state:
		State.GROUND:
			# A short grace period before walking off an edge counts as a fall.
			_coyote = 0.0 if is_on_floor() else _coyote + delta
			if _coyote > 0.15:
				state = State.AIRBORNE
		State.AIRBORNE, State.FLYING:
			if is_on_floor() and velocity.y <= 0.0:
				state = State.GROUND
				landed.emit()


func _orient_model(delta: float) -> void:
	if model_pivot == null:
		return
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var previous := _yaw
	if horizontal.length() > 0.3:
		var target_yaw := atan2(-horizontal.x, -horizontal.z)
		_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-turn_sharpness * delta))
	_yaw_rate = lerpf(_yaw_rate, angle_difference(previous, _yaw) / maxf(delta, 1e-4), 1.0 - exp(-8.0 * delta))

	var pitch_target := 0.0
	var bank_target := 0.0
	if state == State.FLYING:
		var h := horizontal.length()
		pitch_target = -deg_to_rad(lerpf(6.0, max_flight_pitch_deg, clampf(h / fly_fast_speed, 0.0, 1.0)))
		# Nose up while climbing, down while diving.
		pitch_target += atan2(velocity.y, maxf(h, 2.0)) * 0.6
		bank_target = clampf(-_yaw_rate * 0.3, -deg_to_rad(max_bank_deg), deg_to_rad(max_bank_deg))
	var tilt := 1.0 - exp(-tilt_sharpness * delta)
	_pitch = lerpf(_pitch, pitch_target, tilt)
	_bank = lerpf(_bank, bank_target, tilt)
	model_pivot.basis = Basis.from_euler(Vector3(_pitch, _yaw, _bank))


func _altitude() -> float:
	if terrain and terrain.has_method("height_at"):
		return global_position.y - float(terrain.call("height_at", global_position.x, global_position.z))
	return global_position.y


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
	tree_root.add_node("fall", _clip("fall"))
	tree_root.add_node("airborne", AnimationNodeBlend2.new())
	tree_root.connect_node("airborne", 0, "ground_scale")
	tree_root.connect_node("airborne", 1, "fall")
	var air := AnimationNodeBlendSpace1D.new()
	air.min_space = 0.0
	air.max_space = 2.0
	air.sync = true
	air.add_blend_point(_clip("hover"), 0.0, -1, &"hover")
	air.add_blend_point(_clip("fly"), 1.0, -1, &"fly")
	air.add_blend_point(_clip("glide"), 2.0, -1, &"glide")
	tree_root.add_node("air", air)
	tree_root.add_node("air_scale", AnimationNodeTimeScale.new())
	tree_root.connect_node("air_scale", 0, "air")
	tree_root.add_node("mode", AnimationNodeBlend2.new())
	tree_root.connect_node("mode", 0, "airborne")
	tree_root.connect_node("mode", 1, "air_scale")
	# Wing layer: the fold_wings clip, scrubbed by seeking with time frozen, blended
	# over the wing and feather bones only while the wings fold or spread.
	tree_root.add_node("fold", _clip("fold_wings"))
	tree_root.add_node("fold_seek", AnimationNodeTimeSeek.new())
	tree_root.connect_node("fold_seek", 0, "fold")
	tree_root.add_node("fold_hold", AnimationNodeTimeScale.new())
	tree_root.connect_node("fold_hold", 0, "fold_seek")
	var wings := AnimationNodeBlend2.new()
	wings.filter_enabled = true
	var model_root := animation_player.get_node(animation_player.root_node)
	var skeleton: Skeleton3D = model_root.get_node("Skeleton")
	for i in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(i)
		for part in ["Wing", "Primary", "Secondary", "Tertial", "Covert"]:
			if bone.contains(part):
				wings.set_filter_path(NodePath("Skeleton:" + bone), true)
				break
	tree_root.add_node("wings", wings)
	tree_root.connect_node("wings", 0, "mode")
	tree_root.connect_node("wings", 1, "fold_hold")
	tree_root.connect_node("output", 0, "wings")
	_fold_length = animation_player.get_animation("fold_wings").length

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	animation_player.get_parent().add_child(_tree)
	_tree.anim_player = _tree.get_path_to(animation_player)
	_tree.root_node = _tree.get_path_to(model_root)
	_tree.tree_root = tree_root
	_tree.active = true
	_tree.set("parameters/fold_hold/scale", 0.0)


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

	var air_target := clampf(h / (fly_speed * 0.8), 0.0, 1.0)
	var climbing := Input.is_action_pressed("move_jump")
	if h > fly_speed * 1.1 and not climbing:
		air_target = 1.0 + clampf((h - fly_speed) / (fly_fast_speed - fly_speed), 0.0, 1.0)
	_air_blend = lerpf(_air_blend, air_target, blend * 0.5)

	_fall_amount = lerpf(_fall_amount, 1.0 if state == State.AIRBORNE else 0.0, 1.0 - exp(-10.0 * delta))
	_fly_amount = lerpf(_fly_amount, 1.0 if state == State.FLYING else 0.0, 1.0 - exp(-6.0 * delta))

	_tree.set("parameters/ground/blend_position", _ground_blend)
	_tree.set("parameters/ground_scale/scale", cadence)
	_tree.set("parameters/airborne/blend_amount", _fall_amount)
	_tree.set("parameters/air/blend_position", _air_blend)
	_tree.set("parameters/air_scale/scale", 1.35 if climbing else 1.0)
	_tree.set("parameters/mode/blend_amount", _fly_amount)

	# Wings fold whenever she isn't flying (landed, jumping or dropping) and spread on
	# take-off. The fold clip owns the wings only while they move: at rest the gait and
	# flight clips hold the same folded or spread poses (with their own motion).
	var fold_target := 0.0 if state == State.FLYING else 1.0
	var fold_rate := 1.0 / (fold_time if fold_target > _wing_fold else unfold_time)
	_wing_fold = move_toward(_wing_fold, fold_target, fold_rate * delta)
	var folding := _wing_fold > 0.001 and _wing_fold < 0.999
	_wing_layer = move_toward(_wing_layer, 1.0 if folding else 0.0, delta / 0.15)
	_tree.set("parameters/fold_seek/seek_request", _wing_fold * _fold_length)
	_tree.set("parameters/wings/blend_amount", _wing_layer)


# ---------------------------------------------------------------- HUD

func _update_hud() -> void:
	if hud_label == null:
		return
	var h := Vector3(velocity.x, 0.0, velocity.z).length()
	var status := "STANDING"
	match state:
		State.GROUND:
			if h > walk_speed * 1.2:
				status = "RUNNING"
			elif h > 0.2:
				status = "WALKING"
		State.AIRBORNE:
			status = "FALLING" if velocity.y < 0.0 else "JUMPING"
		State.FLYING:
			if h < 1.5:
				status = "HOVERING"
			elif _air_blend > 1.3:
				status = "GLIDING"
			else:
				status = "FLYING"
	var hint := "WASD move   Shift run / fast flight   Space jump, again to fly, hold to climb\nC descend   F take off / drop   Mouse look   Wheel zoom"
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		hint += "\nClick to capture the mouse"
	else:
		hint += "   Esc release mouse"
	hud_label.text = "%s   SPEED %.1f   ALT %d\n%s" % [status, h, roundi(_altitude()), hint]
