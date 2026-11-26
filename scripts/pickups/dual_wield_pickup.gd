extends Pickup
## Power-up: dual wield for `duration` seconds. Picking another one up resets the timer.

@export var duration := 20.0


func _collect(body: Node3D) -> bool:
	if not body.has_method("give_dual_wield"):
		return false
	body.give_dual_wield(duration)
	return true
