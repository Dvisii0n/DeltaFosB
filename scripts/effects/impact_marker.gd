extends Node3D
## Placeholder bullet hole: shrinks away and deletes itself.

@export var lifetime := 1.0


func _ready() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, lifetime).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
