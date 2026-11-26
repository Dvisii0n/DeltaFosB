extends Pickup
## Health pack. Heals the player by `heal_amount` (never above max).
## Stays on the ground if you're already at full health.
## Enemies set heal_amount when they drop it (stronger enemy = bigger heal),
## and the pack grows a bit with the amount so you can tell big ones apart.

@export var heal_amount := 20.0
@export var size_per_point := 0.01     ## Extra scale per HP healed (on top of the base size).


func _ready() -> void:
	super()
	if visual:
		visual.scale = Vector3.ONE * (0.8 + heal_amount * size_per_point)


func _collect(body: Node3D) -> bool:
	if not body.has_method("heal"):
		return false
	return body.heal(heal_amount) > 0.0
