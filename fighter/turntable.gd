extends Node3D
## Turntable for showing off the fighter: one full revolution every `duration`
## seconds while tilting toward and away from the camera, so the top, every side
## and the underside all come into view. Loops seamlessly.
## Render it with Godot's Movie Maker, e.g. (600 frames = 10 s at 60 fps):
##   godot --path . --write-movie out.png --fixed-fps 60 --quit-after 600 res://fighter/turntable.tscn

@export var duration: float = 10.0
## Peak tilt; positive leans the top toward the camera, negative shows the belly.
@export var tilt_degrees: float = 22.0
## Heading at time 0 (145 = nose toward the camera and to the left).
@export var start_yaw_degrees: float = 145.0
## Rotates around the model's vertical axis.
@export var spin: Node3D
## Parent of `spin`; tilts around the camera's horizontal axis.
@export var tilt: Node3D

var _time: float = 0.0


func _ready() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_apply(0.0)


func _process(delta: float) -> void:
	_time += delta
	_apply(_time)


func _apply(time: float) -> void:
	var phase := fmod(time / duration, 1.0)
	spin.rotation.y = deg_to_rad(start_yaw_degrees) + TAU * phase
	tilt.rotation.x = deg_to_rad(tilt_degrees) * sin(TAU * phase)
