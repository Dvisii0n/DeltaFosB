class_name MeleeWeapon
extends Weapon
## Close-range hit. Checks a box in front of the camera and damages everything inside.

@export var reach := 2.5               ## How far in front the hit box goes (m).
@export var hit_width := 1.0           ## Width/height of the hit box (bigger = more forgiving).
@export var max_targets := 4


func _fire() -> void:
	var cam := holder.camera
	var hit_reach := reach * holder.melee_reach_mult   # "reach" upgrades
	var box := BoxShape3D.new()
	box.size = Vector3(hit_width, hit_width, hit_reach)

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = box
	# Box starts at the camera and extends `reach` meters forward.
	params.transform = Transform3D(cam.global_basis, cam.global_position - cam.global_basis.z * hit_reach * 0.5)
	params.exclude = [holder.owner_body.get_rid()]

	var already_hit: Array[Object] = []
	for result in get_world_3d().direct_space_state.intersect_shape(params, max_targets):
		var target: Object = result.collider
		if target in already_hit:
			continue
		already_hit.append(target)
		var hit_pos: Vector3 = result.get("point", Vector3.INF) if result.has("point") else (target as Node3D).global_position + Vector3.UP * 1.1
		deal_damage(target, damage, hit_pos, -cam.global_basis.z)
