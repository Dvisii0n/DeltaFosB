extends "res://scripts/level/spawn_button.gd"
## Same look as the spawn buttons, but starts / stops the enemy waves instead.

@export var wave_manager: NodePath


func _ready() -> void:
	super()
	_refresh_label()


func press() -> void:
	var manager := get_node_or_null(wave_manager)
	if manager:
		manager.toggle()
	_push_feedback()
	_refresh_label()


func _refresh_label() -> void:
	var manager := get_node_or_null(wave_manager)
	var running: bool = manager != null and manager.running
	label.text = "[E] Stop Waves" if running else "[E] Start Waves"
