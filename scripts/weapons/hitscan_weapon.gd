class_name HitscanWeapon
extends Weapon
## Instant-hit gun. One script covers pistol, shotgun and minigun:
## - pellets > 1 + spread = shotgun
## - automatic + spin_up_time = minigun

@export var pellets := 1               ## Rays fired per shot.
@export var spread_deg := 0.0          ## Random cone angle for each ray.
@export var max_range := 200.0
@export var impact_scene: PackedScene  ## Spawned where a ray hits (bullet-hole placeholder).

@export_group("Spin Up")
@export var spin_up_time := 0.0        ## 0 = fires instantly. Otherwise seconds of holding before firing.
@export var spin_node: Node3D          ## Optional: spins while revving (e.g. a minigun barrel).
@export var spin_speed := 30.0         ## Radians per second at full spin.

var spin := 0.0                        # 0..1 how revved up the weapon is.


func update_trigger(pressed: bool, just_pressed: bool, delta: float) -> void:
	if spin_up_time > 0.0:
		spin = move_toward(spin, 1.0 if pressed else 0.0, delta / spin_up_time)
		if is_instance_valid(spin_node):
			spin_node.rotate_z(spin * spin_speed * delta)
		if spin < 1.0:
			return
	super(pressed, just_pressed, delta)


func on_unequipped() -> void:
	spin = 0.0


func _fire() -> void:
	var cam := holder.camera
	var origin := cam.global_position
	var space := get_world_3d().direct_space_state

	for i in pellets:
		var direction := _spread_direction(cam.global_basis)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * max_range)
		query.exclude = [holder.owner_body.get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		deal_damage(hit.collider, damage)
		_spawn_impact(hit.position)


## Forward direction, nudged randomly inside a cone of spread_deg.
func _spread_direction(aim: Basis) -> Vector3:
	var forward := -aim.z
	if spread_deg <= 0.0:
		return forward
	var angle := randf() * TAU
	var radius := sqrt(randf()) * tan(deg_to_rad(spread_deg))
	return (forward + aim.x * cos(angle) * radius + aim.y * sin(angle) * radius).normalized()


func _spawn_impact(position_: Vector3) -> void:
	if impact_scene == null:
		return
	var impact := impact_scene.instantiate() as Node3D
	holder.owner_body.get_parent().add_child(impact)
	impact.global_position = position_
