class_name BulletTime
extends Ability
## Bullet time: the whole game slows down, you included.
## With the Sandevistan upgrade you keep full speed while everything else crawls.

@export var world_speed := 0.25        ## 0.25 = everything runs at a quarter speed.


func _on_start() -> void:
	WorldTime.set_world_speed(world_speed)
	_set_grip(true)    # Pistol tips onto its side: gangster grip.


func _on_stop() -> void:
	WorldTime.set_world_speed(1.0)
	_set_grip(false)


func _set_grip(on: bool) -> void:
	var player := get_parent()
	if not is_instance_valid(player):
		return
	var holder := player.find_child("WeaponHolder", true, false) as WeaponHolder
	if holder:
		holder.gangster_grip = on
