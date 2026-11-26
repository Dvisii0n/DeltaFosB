extends Pickup
## Armor plate. Adds armor to the player (up to their max). Stays if armor is already full.

@export var armor_amount := 35.0


func _collect(body: Node3D) -> bool:
	if not body.has_method("add_armor"):
		return false
	return body.add_armor(armor_amount) > 0.0
