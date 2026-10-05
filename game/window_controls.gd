extends Node
## Autoload: F11 or Alt+Enter toggles fullscreen. Ignored when the game is running
## embedded in the editor's Game tab, where the editor owns the window.


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_fullscreen"):
		return
	if Engine.is_embedded_in_editor():
		return
	var window := get_window()
	if window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		window.mode = Window.MODE_WINDOWED
	else:
		window.mode = Window.MODE_FULLSCREEN
	get_viewport().set_input_as_handled()
