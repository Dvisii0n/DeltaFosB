class_name Blood
extends Object
## Placeholder gore, all built in code (no assets needed). Call from anywhere:
##   Blood.hit(scene_root, position, direction, amount)    - spray from a wound + floor / wall splats
##   Blood.explode(scene_root, position)                     - shotgun kill: big burst, chunks, blood pool
## Splats are Decals (they paint onto floors and walls). Old ones are removed past MAX_SPLATS.

const MAX_SPLATS := 250
const SPLAT_LIFETIME := 40.0

static var _splats: Array[Node3D] = []
static var _splat_texture: GradientTexture2D
static var _drop_material: StandardMaterial3D
static var _chunk_material: StandardMaterial3D


## A hit: droplets fly out along `direction` (the way the bullet was going), splats land below,
## and if there's a wall close behind, it gets painted too. `amount` 1 = normal pistol hit.
static func hit(root: Node, pos: Vector3, direction: Vector3, amount: float = 1.0) -> void:
	if root == null:
		return
	_splash_player(root, pos, 2.5, 0.6 * amount)   # Point-blank hits splash your screen.
	var count := clampi(int(30 * amount), 12, 90)
	_spray(root, pos, direction.normalized(), count, 35.0, Vector2(2.5, 7.5), 0.075, _drop_mat(), 0.9)
	_spray(root, pos, -direction.normalized(), count / 2, 55.0, Vector2(1.5, 4.0), 0.06, _drop_mat(), 0.7)
	var space := root.get_viewport().world_3d.direct_space_state if root.get_viewport() else null
	if space == null:
		return
	# Floor splats under the hit.
	for i in clampi(int(2 * amount), 1, 4):
		var offset := Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6)) + direction * randf_range(0.2, 1.2)
		_splat_ray(root, space, pos + offset, pos + offset + Vector3.DOWN * 4.0, randf_range(0.35, 0.9) * sqrt(amount))
	# Wall behind the target.
	_splat_ray(root, space, pos + direction * 0.6, pos + direction * 3.5, randf_range(0.5, 1.1) * sqrt(amount))


## Shotgun kill: a big burst of blood and chunks plus a pool of splats around the body.
static func explode(root: Node, pos: Vector3) -> void:
	if root == null:
		return
	_splash_player(root, pos, 5.0, 2.5)
	_spray(root, pos, Vector3.UP, 220, 180.0, Vector2(3.0, 12.0), 0.09, _drop_mat(), 1.2)
	_spray(root, pos, Vector3.UP, 30, 120.0, Vector2(3.0, 8.0), 0.18, _chunk_mat(), 1.5)   # chunks
	var space := root.get_viewport().world_3d.direct_space_state if root.get_viewport() else null
	if space == null:
		return
	for i in 12:
		var angle := randf() * TAU
		var dist := sqrt(randf()) * 3.0
		var p := pos + Vector3(cos(angle) * dist, 0.5, sin(angle) * dist)
		_splat_ray(root, space, p, p + Vector3.DOWN * 5.0, randf_range(0.6, 1.6))
	# Paint nearby walls too.
	for i in 6:
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.2, 0.6), randf_range(-1, 1)).normalized()
		_splat_ray(root, space, pos, pos + dir * 4.0, randf_range(0.8, 1.5))


# --- Internals -------------------------------------------------------------------

## If the player is within `radius`, splatter their screen (more the closer they are).
static func _splash_player(root: Node, pos: Vector3, radius: float, strength: float) -> void:
	var player := root.get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not player.has_method("splash_screen"):
		return
	var dist := player.global_position.distance_to(pos)
	if dist < radius:
		player.splash_screen(strength * (1.0 - dist / radius) + 0.3)

static func _spray(root: Node, pos: Vector3, dir: Vector3, count: int, spread: float,
		speed: Vector2, size: float, mat: Material, life: float) -> void:
	var p := CPUParticles3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	box.material = mat
	p.mesh = box
	p.amount = maxi(count, 1)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	p.direction = dir if dir != Vector3.ZERO else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.gravity = Vector3(0, -16, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


## Casts a ray; where it hits level geometry, paints a blood splat facing out of the surface.
static func _splat_ray(root: Node, space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, size: float) -> void:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(query)
	if hit.is_empty() or not hit.collider is StaticBody3D:
		return   # Only paint the level, not enemies or the player.
	_splat(root, hit.position, hit.normal, size)


static func _splat(root: Node, pos: Vector3, normal: Vector3, size: float) -> void:
	var decal := Decal.new()
	decal.texture_albedo = _splat_tex()
	decal.size = Vector3(size, 0.4, size)
	decal.modulate = Color(randf_range(0.6, 0.85), 0.0, 0.0)
	decal.cull_mask = 1
	root.add_child(decal)
	decal.global_position = pos + normal * 0.05
	# A Decal projects along its local -Y: point -Y into the surface.
	var up := normal
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	decal.global_basis = Basis(side, up, side.cross(up)).rotated(up, randf() * TAU)
	_splats.append(decal)
	root.get_tree().create_timer(SPLAT_LIFETIME, false).timeout.connect(_remove_splat.bind(decal))
	while _splats.size() > MAX_SPLATS:
		_remove_splat(_splats[0])


static func _remove_splat(decal: Node3D) -> void:
	_splats.erase(decal)
	if is_instance_valid(decal):
		decal.queue_free()


static func _splat_tex() -> GradientTexture2D:
	if _splat_texture == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.55, Color(1, 1, 1, 0.95))
		_splat_texture = GradientTexture2D.new()
		_splat_texture.gradient = g
		_splat_texture.fill = GradientTexture2D.FILL_RADIAL
		_splat_texture.fill_from = Vector2(0.5, 0.5)
		_splat_texture.fill_to = Vector2(1.0, 0.5)
		_splat_texture.width = 64
		_splat_texture.height = 64
	return _splat_texture


static func _drop_mat() -> StandardMaterial3D:
	if _drop_material == null:
		_drop_material = StandardMaterial3D.new()
		_drop_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # Reads clearly in any light.
		_drop_material.albedo_color = Color(0.75, 0.02, 0.04)
	return _drop_material


static func _chunk_mat() -> StandardMaterial3D:
	if _chunk_material == null:
		_chunk_material = StandardMaterial3D.new()
		_chunk_material.albedo_color = Color(0.7, 0.15, 0.2)
		_chunk_material.roughness = 0.6
	return _chunk_material
