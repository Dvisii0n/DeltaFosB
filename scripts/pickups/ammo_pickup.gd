extends Pickup
## Ammo box. Gives the ammo listed in `ammo` ("light" = pistol, "shells" = shotgun, "heavy" = minigun).
## Stays on the ground if you're already full of every type it gives.

@export var ammo := {"light": 8, "shells": 2, "heavy": 40}


func _collect(body: Node3D) -> bool:
	if not body.has_method("add_ammo"):
		return false
	var gained := 0
	for type in ammo:
		gained += body.add_ammo(type, ammo[type])
	return gained > 0
