class_name FighterAudio
extends Node
## Sound for a FighterController: an engine loop whose pitch and volume follow the
## throttle and speed, rushing wind that grows with airspeed, an afterburner roar
## while boosting, one-shots for afterburner ignition / air brake / empty boost tank,
## and a repeating low-altitude warning.

@export var fighter: FighterController
## How quickly loop volumes and pitches glide to their new values (per second).
@export var response: float = 6.0

@export_group("Engine")
## Playback speed of the recorded hum at idle and at full throttle. Keep it near 1:
## a recording smears when slowed down and turns chipmunky when sped up.
@export var engine_pitch_idle: float = 0.85
@export var engine_pitch_full: float = 1.15
## Extra pitch on top of full throttle at top afterburner speed.
@export var engine_pitch_boost_bonus: float = 0.15
@export var engine_volume_idle: float = 0.35
@export var engine_volume_full: float = 0.75

@export_group("Wind")
@export var wind_volume_max: float = 0.8

@export_group("Afterburner")
@export var afterburner_volume: float = 0.9

@onready var _engine: AudioStreamPlayer = $Engine
@onready var _wind: AudioStreamPlayer = $Wind
@onready var _afterburner: AudioStreamPlayer = $Afterburner
@onready var _warning: AudioStreamPlayer = $Warning
@onready var _boost_ignite: AudioStreamPlayer = $BoostIgnite
@onready var _airbrake: AudioStreamPlayer = $Airbrake
@onready var _boost_empty: AudioStreamPlayer = $BoostEmpty

var _afterburner_level: float = 0.0


func _ready() -> void:
	for loop in [_engine, _wind, _afterburner]:
		loop.volume_linear = 0.0
		loop.play()
	if fighter == null:
		return
	fighter.boost_started.connect(_boost_ignite.play)
	fighter.boost_denied.connect(_boost_empty.play)
	fighter.brake_started.connect(_on_brake_started)
	fighter.ground_warning_changed.connect(_on_ground_warning_changed)


func _process(delta: float) -> void:
	if fighter == null:
		return
	var blend := 1.0 - exp(-response * delta)

	var cruise_fraction := clampf(inverse_lerp(fighter.min_speed, fighter.max_speed, fighter.speed), 0.0, 1.0)
	var boost_fraction := clampf(inverse_lerp(fighter.max_speed, fighter.boost_speed, fighter.speed), 0.0, 1.0)
	# The engine note follows the throttle lever (what the pilot asks for) and the
	# actual speed, so pushing the throttle spools the engine up before the ship catches up.
	var drive := clampf(0.6 * fighter.throttle + 0.4 * cruise_fraction, 0.0, 1.0)
	var engine_pitch := lerpf(engine_pitch_idle, engine_pitch_full, drive) + engine_pitch_boost_bonus * boost_fraction
	var engine_volume := lerpf(engine_volume_idle, engine_volume_full, drive)
	if fighter.is_boosting:
		engine_volume = engine_volume_full
	_engine.pitch_scale = lerpf(_engine.pitch_scale, engine_pitch, blend)
	_engine.volume_linear = lerpf(_engine.volume_linear, engine_volume, blend)

	var airspeed := clampf(inverse_lerp(fighter.min_speed * 0.6, fighter.boost_speed, fighter.speed), 0.0, 1.0)
	var wind_volume := wind_volume_max * pow(airspeed, 1.6)
	if fighter.is_braking:
		wind_volume = minf(wind_volume * 1.4, 1.0)  # deployed flaps catch more air
	_wind.volume_linear = lerpf(_wind.volume_linear, wind_volume, blend)
	_wind.pitch_scale = lerpf(_wind.pitch_scale, lerpf(0.8, 1.3, airspeed), blend)

	_afterburner_level = lerpf(_afterburner_level, 1.0 if fighter.is_boosting else 0.0, 1.0 - exp(-8.0 * delta))
	_afterburner.volume_linear = afterburner_volume * _afterburner_level
	_afterburner.pitch_scale = lerpf(0.85, 1.1, boost_fraction)


func _on_brake_started() -> void:
	# Only worth a whoosh if there's speed to shed.
	if fighter.speed > fighter.min_speed + 5.0:
		_airbrake.play()


func _on_ground_warning_changed(active: bool) -> void:
	if active:
		_warning.play()
	else:
		_warning.stop()
