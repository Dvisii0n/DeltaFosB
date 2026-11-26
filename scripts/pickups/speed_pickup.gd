extends Pickup
## Power-up: move faster for `duration` seconds. Picking another one up resets the timer.

@export var duration := 10.0
@export var speed_mult := 1.4          ## 1.4 = +40% move speed.


func _collect(body: Node3D) -> bool:
	if not body.has_method("give_speed_boost"):
		return false
	body.give_speed_boost(duration, speed_mult)
	return true
