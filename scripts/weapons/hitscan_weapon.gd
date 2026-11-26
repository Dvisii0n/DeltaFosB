class_name HitscanWeapon
extends Weapon
## Instant-hit gun. One script covers pistol, shotgun and minigun:
## - pellets > 1 + spread = shotgun
## - automatic + spin_up_time = minigun

@export var pellets := 1               ## Rays fired per shot.
@export var spread_deg := 0.0          ## Random cone angle for each ray.
@export var max_range := 200.0
@export var impact_scene: PackedScene  ## Spawned where a ray hits (bullet-hole placeholder).

@export_group("Muzzle Flash")
@export var flash_enabled := true
@export var flash_size := 0.35         ## Size of the flash star (metres).
@export var flash_light_energy := 8.0  ## How bright the flash lights up the surroundings.
@export var flash_light_range := 6.0
@export var flash_color := Color(1.0, 0.75, 0.3)
@export var flash_time := 0.05         ## Seconds the flash stays visible (real time), +-40% random.
@export_range(0.0, 1.0) var flash_chance := 1.0  ## Chance each shot flashes. <1 = flickery (minigun).
@export var flash_stretch := 0.45      ## Random squash/stretch per shot (0 = always round).
@export var gun_model: NodePath = ^"Visual/Grip/GunModel"  ## The flash sits at the front tip of this model.

@export_group("Spin Up")
@export var spin_up_time := 0.0        ## 0 = fires instantly. Otherwise seconds of holding before firing.
@export var spin_node: Node3D          ## Optional: spins while revving (e.g. a minigun barrel).
@export var spin_speed := 30.0         ## Radians per second at full spin.

var spin := 0.0                        # 0..1 how revved up the weapon is.
var _flash: Node3D                     # Built on the first shot, at the barrel tip.
var _flash_light: OmniLight3D
var _flash_mesh: MeshInstance3D
var _flash_mat: StandardMaterial3D
var _flash_id := 0


func update_trigger(pressed: bool, just_pressed: bool, delta: float) -> void:
	if spin_up_time > 0.0:
		spin = move_toward(spin, 1.0 if pressed else 0.0, delta / (spin_up_time * holder.spin_up_mult))
		if is_instance_valid(spin_node):
			spin_node.rotate_z(spin * spin_speed * delta)
		if spin < 1.0:
			return
	super(pressed, just_pressed, delta)


func on_unequipped() -> void:
	spin = 0.0


func _fire() -> void:
	_muzzle_flash()
	var cam := holder.camera
	var origin := cam.global_position
	var space := get_world_3d().direct_space_state

	for i in pellets + holder.bonus_pellets.get(weapon_name, 0):
		var direction := _spread_direction(cam.global_basis)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * max_range)
		query.exclude = [holder.owner_body.get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		deal_damage(hit.collider, damage, hit.position, direction)
		_spawn_impact(hit.position)


## spread_deg after "tighter spread" upgrades.
func effective_spread() -> float:
	return spread_deg * (holder.spread_mult.get(weapon_name, 1.0) if holder else 1.0)


## Forward direction, nudged randomly inside a cone of spread_deg.
func _spread_direction(aim: Basis) -> Vector3:
	var forward := -aim.z
	var spread := effective_spread()
	if spread <= 0.0:
		return forward
	var angle := randf() * TAU
	var radius := sqrt(randf()) * tan(deg_to_rad(spread))
	return (forward + aim.x * cos(angle) * radius + aim.y * sin(angle) * radius).normalized()


# --- Muzzle flash (placeholder: glowing star + light burst) ------------------------

func _muzzle_flash() -> void:
	if not flash_enabled:
		return
	if _flash == null and not _build_flash():
		return
	if randf() > flash_chance:
		return   # Skip this one: rapid fire flickers instead of glowing constantly.
	_flash.visible = true
	# A different flame every shot: random shape, angle, size and stretch.
	_flash_mat.albedo_texture = _flash_textures().pick_random()
	_flash_mesh.rotation.z = randf() * TAU
	var s := randf_range(0.7, 1.35)
	var stretch := randf_range(-flash_stretch, flash_stretch)
	_flash_mesh.scale = Vector3(s * (1.0 + stretch), s * (1.0 - stretch * 0.6), 1.0)
	_flash_mesh.position = Vector3(randf_range(-0.02, 0.02), randf_range(-0.02, 0.02), -0.04)   # just past the tip
	_flash_light.light_energy = flash_light_energy * randf_range(0.5, 1.3)
	_flash_id += 1
	var id := _flash_id
	# Real-time timer, so the flash stays snappy even in bullet time.
	await get_tree().create_timer(flash_time * randf_range(0.6, 1.4), true, false, true).timeout
	if is_instance_valid(_flash) and id == _flash_id:
		_flash.visible = false


## Finds the barrel tip (the front-most part of the gun model) and builds the flash there.
func _build_flash() -> bool:
	var model := get_node_or_null(gun_model) as Node3D
	if model == null:
		return false
	var tip := _front_tip(model)
	if tip == Vector3.INF:
		return false
	_flash = Node3D.new()
	_flash.name = "MuzzleFlash"
	model.add_child(_flash)
	_flash.global_position = tip
	_flash.global_basis = global_basis.orthonormalized()   # Face the camera like the gun does.

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(flash_color.r, flash_color.g, flash_color.b, 1.0)
	mat.albedo_texture = _flash_textures()[0]
	_flash_mat = mat
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true         # Draw over the gun: seen from behind, the barrel would hide it.
	mat.render_priority = 10
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * flash_size
	quad.material = mat
	_flash_mesh = MeshInstance3D.new()
	_flash_mesh.mesh = quad
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.add_child(_flash_mesh)

	_flash_light = OmniLight3D.new()
	_flash_light.light_color = flash_color
	_flash_light.omni_range = flash_light_range
	_flash_light.shadow_enabled = false
	_flash.add_child(_flash_light)
	_flash.visible = false
	return true


## Front-most point of the model's meshes (most negative Z, seen from the camera),
## averaged over everything within 3 cm of it = the barrel tip.
func _front_tip(model: Node3D) -> Vector3:
	var to_local := global_transform.affine_inverse()
	var points: Array[Vector3] = []
	var min_z := INF
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := to_local * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p := xf * v
				points.append(p)
				min_z = minf(min_z, p.z)
	if points.is_empty():
		return Vector3.INF
	var sum := Vector3.ZERO
	var n := 0
	for p in points:
		if p.z <= min_z + 0.03:
			sum += p
			n += 1
	return global_transform * (sum / n)


static var _flash_shapes: Array[ImageTexture] = []

## A few spiky flame shapes, drawn once in code (no image files). Each shot picks one.
static func _flash_textures() -> Array[ImageTexture]:
	if _flash_shapes.is_empty():
		for variant in 6:
			_flash_shapes.append(_make_flash_shape(variant))
	return _flash_shapes


## Bright core + 4-7 uneven spikes of random length and width.
static func _make_flash_shape(seed_value: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + seed_value
	var size := 64
	var spikes := rng.randi_range(4, 7)
	var spike_angle: Array[float] = []
	var spike_len: Array[float] = []
	var spike_width: Array[float] = []
	for i in spikes:
		spike_angle.append(TAU * i / spikes + rng.randf_range(-0.35, 0.35))
		spike_len.append(rng.randf_range(0.55, 1.0))
		spike_width.append(rng.randf_range(0.12, 0.3))
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5) / size * 2.0 - Vector2.ONE   # -1..1
			var r := p.length()
			var a := p.angle()
			var core := clampf(1.0 - r / 0.35, 0.0, 1.0)
			var spike := 0.0
			for i in spikes:
				var d := absf(angle_difference(a, spike_angle[i]))
				var along := clampf(1.0 - r / spike_len[i], 0.0, 1.0)
				spike = maxf(spike, clampf(1.0 - d / spike_width[i], 0.0, 1.0) * along)
			var v := clampf(maxf(core, spike * 0.9), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.85 + 0.15 * core, 0.6 + 0.4 * core, v))
	return ImageTexture.create_from_image(img)


func _spawn_impact(position_: Vector3) -> void:
	if impact_scene == null:
		return
	var impact := impact_scene.instantiate() as Node3D
	holder.owner_body.get_parent().add_child(impact)
	impact.global_position = position_
