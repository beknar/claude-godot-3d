class_name FighterController
extends CharacterBody3D
## Arcade 6-DOF flight model. The ship always flies forward along its nose (-Z):
##   Mouse      point the nose (pitch and yaw); arrow keys do the same
##   A / D      roll left / right
##   W / S      throttle up / down (also E / Q; the setting persists)
##   Shift      afterburner boost (burns boost fuel, which recharges when released)
##   Space      air brake (sheds speed fast without moving the throttle)
##   Esc        release the mouse; click to capture it again
## Speed chases the throttle setting with finite acceleration and drag, and diving
## trades altitude for speed while climbing bleeds it off. Keeps a minimum
## clearance above the terrain and steers back when it strays past the map edge.

signal boost_started
signal boost_ended
## Boost was requested while the fuel was too low to light the afterburner.
signal boost_denied
signal brake_started
signal brake_ended
## The ship crossed the low-altitude warning threshold (in either direction).
signal ground_warning_changed(active: bool)

@export_group("Speed")
## Speed at zero throttle.
@export var min_speed: float = 30.0
## Speed at full throttle.
@export var max_speed: float = 110.0
## Top speed with the afterburner lit.
@export var boost_speed: float = 175.0
@export_range(0.0, 1.0) var start_throttle: float = 0.45
## Throttle lever travel per second while W/S is held.
@export var throttle_rate: float = 0.45
## m/s² gained while below the throttle's target speed.
@export var engine_acceleration: float = 22.0
## m/s² lost to drag while above the throttle's target speed.
@export var drag_deceleration: float = 12.0
@export var boost_acceleration: float = 60.0
@export var brake_deceleration: float = 55.0
## m/s² gained when diving straight down (and lost when climbing straight up).
@export var dive_acceleration: float = 16.0

@export_group("Boost")
## Seconds of afterburner on a full tank.
@export var boost_capacity: float = 4.0
## Seconds of fuel regained per second while not boosting.
@export var boost_recharge_rate: float = 0.5
## Fraction of the tank needed before the afterburner will relight.
@export_range(0.0, 1.0) var boost_relight_fraction: float = 0.25

@export_group("Steering")
## Degrees of nose rotation per pixel of mouse movement.
@export var mouse_sensitivity: float = 0.1
## When true, pushing the mouse forward points the nose down (flight-sim style).
@export var invert_mouse_y: bool = false
## Nose turn rate from the arrow keys, in degrees per second.
@export var key_turn_rate_deg: float = 60.0
@export var max_pitch_rate_deg: float = 110.0
@export var max_yaw_rate_deg: float = 80.0
## How quickly the turn rate catches up with the mouse (per second). Lower is floatier.
@export var turn_response: float = 10.0
@export var roll_rate_deg: float = 160.0
## How quickly the roll rate catches up with A/D (per second).
@export var roll_response: float = 6.0
## Degrees per second the wings drift back to level while A/D are released (0 = off).
@export var auto_level_deg: float = 25.0

@export_group("World")
## Anything with a height_at(x, z) method, e.g. a RollingHillsTerrain.
@export var terrain: Node3D
@export var min_clearance: float = 8.0
## Height above the terrain below which the low-altitude warning sounds.
@export var warning_altitude: float = 25.0
@export var max_altitude: float = 700.0
## Past this horizontal distance from the world origin the ship is steered home.
@export var boundary_radius: float = 1000.0

@export_group("Visuals")
## The fighter model. Its "ExhaustTrail" meshes are stretched with speed.
@export var model: Node3D
@export var hud_label: Label

var speed: float = 0.0
## Throttle lever position, 0..1.
var throttle: float = 0.0
## Remaining afterburner time in seconds.
var boost_fuel: float = 0.0
var is_boosting: bool = false
var is_braking: bool = false
var ground_warning: bool = false

var _mouse_delta := Vector2.ZERO
## Current nose turn rate in rad/s: x = pitch, y = yaw.
var _turn_rate := Vector2.ZERO
var _roll_rate: float = 0.0
var _boost_needs_release: bool = false
var _exhausts: Array[Node3D] = []
var _exhaust_rest: Dictionary = {}
var _particles: Array[CPUParticles3D] = []
var _particle_scale: Dictionary = {}


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	throttle = start_throttle
	speed = lerpf(min_speed, max_speed, throttle)
	boost_fuel = boost_capacity
	if model:
		for node in model.find_children("ExhaustTrail", "Node3D", true, false):
			_exhausts.append(node)
			_exhaust_rest[node] = node.position
	for node in find_children("ExhaustParticles*", "CPUParticles3D", true, false):
		_particles.append(node)
		_particle_scale[node] = Vector2(node.scale_amount_min, node.scale_amount_max)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_delta += event.screen_relative
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	transform.basis = _steer(transform.basis, delta)
	_steer_inside_boundary(delta)
	_update_speed(delta)

	velocity = -transform.basis.z * speed
	move_and_slide()

	_enforce_altitude_limits(delta)
	_update_exhausts()
	_update_hud()


## Applies mouse/arrow-key nose steering and A/D roll in the ship's own frame.
func _steer(orientation: Basis, delta: float) -> Basis:
	var mouse := _mouse_delta
	_mouse_delta = Vector2.ZERO
	if invert_mouse_y:
		mouse.y = -mouse.y

	# Mouse movement this tick becomes a requested turn rate; arrow keys add a steady one.
	var key_rate := deg_to_rad(key_turn_rate_deg)
	var per_pixel := deg_to_rad(mouse_sensitivity) / delta
	var want := Vector2(
		-mouse.y * per_pixel + Input.get_axis("fly_pitch_down", "fly_pitch_up") * key_rate,
		-mouse.x * per_pixel + Input.get_axis("fly_yaw_right", "fly_yaw_left") * key_rate)
	want.x = clampf(want.x, -deg_to_rad(max_pitch_rate_deg), deg_to_rad(max_pitch_rate_deg))
	want.y = clampf(want.y, -deg_to_rad(max_yaw_rate_deg), deg_to_rad(max_yaw_rate_deg))
	_turn_rate = _turn_rate.lerp(want, 1.0 - exp(-turn_response * delta))

	var roll_input := Input.get_axis("fly_roll_right", "fly_roll_left")
	_roll_rate = lerpf(_roll_rate, roll_input * deg_to_rad(roll_rate_deg), 1.0 - exp(-roll_response * delta))

	orientation = orientation * Basis.from_euler(Vector3(_turn_rate.x * delta, _turn_rate.y * delta, _roll_rate * delta))

	# With A/D released, ease the wings back to level the short way round, even from
	# inverted. Skipped near vertical, where "level" is undefined.
	if is_zero_approx(roll_input) and auto_level_deg > 0.0 and absf(orientation.z.y) < 0.95:
		var bank := atan2(orientation.x.y, orientation.y.y)  # > 0 means the right wing is up
		var step := minf(absf(bank), deg_to_rad(auto_level_deg) * delta)
		orientation = orientation * Basis(Vector3.BACK, -signf(bank) * step)

	return orientation.orthonormalized()


## Rotates the nose toward (positive angle) or away from world up, keeping the roll.
func _tilt_nose_up(angle: float) -> void:
	var forward := -transform.basis.z
	var axis := forward.cross(Vector3.UP)
	if axis.length_squared() < 0.0001:
		return
	transform.basis = (Basis(axis.normalized(), angle) * transform.basis).orthonormalized()


func _update_speed(delta: float) -> void:
	throttle = clampf(throttle + Input.get_axis("fly_throttle_down", "fly_throttle_up") * throttle_rate * delta, 0.0, 1.0)

	var braking := Input.is_action_pressed("fly_brake")
	if braking != is_braking:
		is_braking = braking
		if is_braking:
			brake_started.emit()
		else:
			brake_ended.emit()

	# The afterburner needs a minimum of fuel to light, burns out when empty,
	# and is cut by the air brake. After a burnout the key must be released and
	# pressed again, so holding Shift doesn't stutter-relight as fuel trickles back.
	var boost_held := Input.is_action_pressed("fly_boost")
	if not boost_held:
		_boost_needs_release = false
	var wants_boost := boost_held and not is_braking and not _boost_needs_release
	if wants_boost and not is_boosting:
		if boost_fuel >= boost_capacity * boost_relight_fraction:
			is_boosting = true
			boost_started.emit()
		elif Input.is_action_just_pressed("fly_boost"):
			boost_denied.emit()
	elif is_boosting and (not wants_boost or boost_fuel <= 0.0):
		is_boosting = false
		_boost_needs_release = boost_held
		boost_ended.emit()

	if is_boosting:
		boost_fuel = maxf(boost_fuel - delta, 0.0)
	else:
		boost_fuel = minf(boost_fuel + boost_recharge_rate * delta, boost_capacity)

	var target := lerpf(min_speed, max_speed, throttle)
	var rate := engine_acceleration if speed < target else drag_deceleration
	if is_boosting:
		target = boost_speed
		rate = boost_acceleration
	elif is_braking:
		target = min_speed
		rate = brake_deceleration
	speed = move_toward(speed, target, rate * delta)
	# Diving (nose below the horizon) adds speed, climbing costs it.
	var forward := -transform.basis.z
	speed -= forward.y * dive_acceleration * delta
	speed = clampf(speed, min_speed * 0.6, boost_speed * 1.1)


func _steer_inside_boundary(delta: float) -> void:
	var flat := Vector2(global_position.x, global_position.z)
	if flat.length() <= boundary_radius:
		return
	var forward := -transform.basis.z
	var heading := atan2(-forward.x, -forward.z)
	var home := -flat.normalized()
	var home_heading := atan2(-home.x, -home.y)
	var turn := wrapf(home_heading - heading, -PI, PI)
	var step := clampf(turn, -deg_to_rad(45.0) * delta, deg_to_rad(45.0) * delta)
	transform.basis = (Basis(Vector3.UP, step) * transform.basis).orthonormalized()


func _enforce_altitude_limits(delta: float) -> void:
	var forward := -transform.basis.z
	var clearance := INF
	if terrain and terrain.has_method("height_at"):
		var ground_y: float = terrain.call("height_at", global_position.x, global_position.z)
		if global_position.y < ground_y + min_clearance:
			global_position.y = ground_y + min_clearance
			# Skimming the ground pulls the nose up instead of burying it.
			if forward.y < 0.1:
				_tilt_nose_up(deg_to_rad(90.0) * delta)
		clearance = global_position.y - ground_y
	if global_position.y > max_altitude:
		global_position.y = max_altitude
		if forward.y > 0.0:
			_tilt_nose_up(-deg_to_rad(60.0) * delta)

	var warning := clearance < warning_altitude
	if warning != ground_warning:
		ground_warning = warning
		ground_warning_changed.emit(ground_warning)


func _update_exhausts() -> void:
	# Trails are 6 m cones whose nozzle end must stay attached to the engine.
	var stretch := remap(speed, min_speed, boost_speed, 0.45, 1.8)
	for trail in _exhausts:
		var rest: Vector3 = _exhaust_rest[trail]
		trail.scale = Vector3(1.0, stretch, 1.0)
		trail.position = Vector3(rest.x, rest.y, rest.z - 3.0 + 3.0 * stretch)
	# Particle puffs swell with power, and more so on afterburner.
	var puff := clampf(remap(speed, min_speed, max_speed, 0.7, 1.15), 0.7, 1.15) + (0.5 if is_boosting else 0.0)
	for emitter in _particles:
		var base: Vector2 = _particle_scale[emitter]
		emitter.scale_amount_min = base.x * puff
		emitter.scale_amount_max = base.y * puff


func _update_hud() -> void:
	if hud_label == null:
		return
	var altitude := global_position.y
	if terrain and terrain.has_method("height_at"):
		altitude -= terrain.call("height_at", global_position.x, global_position.z)
	var status := ""
	if is_boosting:
		status = "   AFTERBURNER"
	elif is_braking:
		status = "   AIR BRAKE"
	if ground_warning:
		status += "   PULL UP"
	var hint := "Mouse steer   A/D roll   W/S throttle   Shift boost   Space brake"
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		hint += "\nClick to capture the mouse"
	else:
		hint += "   Esc release mouse"
	hud_label.text = "SPEED %d   ALT %d%s\nTHROTTLE %s %d%%\nBOOST    %s\n%s" % [
		roundi(speed), roundi(altitude), status,
		_bar(throttle), roundi(throttle * 100.0),
		_bar(boost_fuel / boost_capacity), hint]


func _bar(fraction: float, width: int = 16) -> String:
	var filled := roundi(clampf(fraction, 0.0, 1.0) * width)
	return "[" + "|".repeat(filled) + ".".repeat(width - filled) + "]"
