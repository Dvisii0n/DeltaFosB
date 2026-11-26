class_name Enemy
extends CharacterBody3D
## Shared enemy brain. All four enemy types use this script; they only differ in the
## numbers set in the Inspector (speed, behavior, attack...).
##
## States:
##   IDLE   - hasn't seen the player yet. Stands still.
##   ALERT  - knows where the player is. Moves around according to `behavior`.
##   ATTACK - stops moving, faces the player and shoots / swings.
##            Hook a shooting animation to the `state_changed` signal later.

enum Behavior { CHASE, KEEP_DISTANCE, HOLD_GROUND }
enum State { IDLE, ALERT, ATTACK }

signal state_changed(new_state: State)

## CHASE = runs at you. KEEP_DISTANCE = stays about `preferred_distance` away.
## HOLD_GROUND = shuffles slowly around where it spawned.
@export var behavior: Behavior = Behavior.CHASE

@export_group("Movement")
@export var move_speed := 4.0          ## Metres per second.
@export var acceleration := 25.0       ## How fast it reaches move_speed.
@export var turn_speed := 8.0          ## How fast it turns to face you.
@export var gravity := 30.0
@export var repath_interval := 0.25    ## Seconds between path updates (lower = smarter, slower).

@export_group("Keep Distance")
@export var preferred_distance := 10.0 ## Distance it tries to keep from you.
@export var distance_tolerance := 2.0  ## How far off that distance is still "fine".
@export var strafe_speed_scale := 0.5  ## Sidestep speed, as a share of move_speed.

@export_group("Hold Ground")
@export var hold_radius := 3.0         ## How far from its spawn point it may wander.
@export var hold_pause_time := 1.5     ## Seconds it waits between little moves.

@export_group("Senses")
@export var sight_range := 40.0
@export var eye_height := 1.5          ## Where it "looks" from, measured from its feet.

@export_group("Attack")
@export var melee := false             ## true = hits you up close instead of shooting.
@export var attack_range := 20.0       ## It only starts an attack when you're this close.
@export var attack_damage := 8.0       ## Per pellet / per swing.
@export var pellets := 1               ## Rays per shot (shotgun > 1).
@export var spread_deg := 2.0          ## Random aim cone. Bigger = misses more.
@export var attack_windup := 0.2       ## Seconds standing still before the first shot (minigun spin-up).
@export var attack_interval := 0.1     ## Seconds between shots inside one attack.
@export var burst_count := 1           ## Shots per attack. 0 = keeps firing until attack_hold_time ends.
@export var attack_hold_time := 0.5    ## Seconds it stays in ATTACK (not moving).
@export var attack_cooldown := 1.0     ## Seconds of moving around before it can attack again.
@export var tracer_color := Color(1.0, 0.85, 0.3)

@export_group("Attack Warning")
## Ranged enemies flash red above their head during attack_windup, so you can dodge.
@export var show_attack_warning := true
@export var warning_height := 2.9      ## Metres above the feet.
@export var warning_color := Color(1.0, 0.1, 0.1)
@export var warning_flash_speed := 18.0
## true = aims at where you were when the warning appeared, so moving after the flash dodges it.
## false = keeps tracking you (the minigun, which sprays a long burst).
@export var lock_aim_on_warning := true
## When not locked: how fast (m/s) the aim follows you during an attack. 0 = perfect tracking.
## Lower = easier to outrun (strafe and the bullets trail behind you).
@export var aim_follow_speed := 0.0

@export_group("Feedback")
@export var hit_punch := 1.15          ## Visual briefly scales up when hit.
@export var show_state_label := true   ## Debug text above its head (only if the enemy has a "StateLabel" Label3D child; removed by default).

@export_group("Drops")
## Ammo boxes it can drop on death. Each one rolls its own chance (same order as below),
## so stronger ammo is set rarer: pistol 60%, shotgun 35%, minigun 20%.
@export var ammo_drops: Array[PackedScene] = [
	preload("res://scenes/pickups/ammo_light.tscn"),
	preload("res://scenes/pickups/ammo_shells.tscn"),
	preload("res://scenes/pickups/ammo_heavy.tscn"),
]
@export var ammo_drop_chances: Array[float] = [0.6, 0.35, 0.2]
## Ammo type of each drop above, so the player's drop chance upgrades know which is which.
@export var ammo_drop_types: Array[String] = ["light", "shells", "heavy"]
## Armor plate drop. Only armored enemies (Health max_armor > 0) ever drop it.
@export var armor_drop_scene: PackedScene = preload("res://scenes/pickups/armor_pickup.tscn")
@export_range(0.0, 1.0) var armor_drop_chance := 0.5
## Health pack drop. Stronger enemies give a bigger heal.
@export var health_drop_scene: PackedScene = preload("res://scenes/pickups/health_pickup.tscn")
@export_range(0.0, 1.0) var health_drop_chance := 0.4
@export var health_drop_amount := 15.0
## Dual wield power-up drop chance. Stronger enemies are set higher (worker 3%, guard 5%, vest 10%, head 25%).
@export var dual_wield_drop_scene: PackedScene = preload("res://scenes/pickups/dual_wield_pickup.tscn")
@export_range(0.0, 1.0) var dual_wield_drop_chance := 0.0
## Speed boost power-up drop.
@export var speed_drop_scene: PackedScene = preload("res://scenes/pickups/speed_pickup.tscn")
@export_range(0.0, 1.0) var speed_drop_chance := 0.05

@export_group("Ability")
@export var ability_charge := 0.1     ## How much of the player's ability bar a kill fills (1 = full bar).
@export var xp_value := 20.0           ## XP the player gets for the kill.

@onready var health: Health = $Health
@onready var visual: Node3D = $Visual
@onready var muzzle: Node3D = $Muzzle
@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var state_label: Label3D = get_node_or_null("StateLabel")

var state := State.IDLE
var player: Node3D

var _home := Vector3.ZERO
var _started := false
var _can_see := false
var _repath_timer := 0.0
var _cooldown_timer := 0.0
var _attack_timer := 0.0
var _next_shot_time := 0.0
var _shots_fired := 0
var _strafe_dir := 1.0
var _strafe_timer := 0.0
var _hold_pause := 0.0
var _hold_move_time := 0.0
var _hit_tween: Tween
var _tracer_material: StandardMaterial3D
var _warning: MeshInstance3D            # Red flash shown before a ranged attack.
var _locked_aim := Vector3.ZERO
var _aim_point := Vector3.ZERO           # Where a tracking (non-locked) attack is aiming right now.


func _ready() -> void:
	add_to_group("enemies")
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_tracer_material = StandardMaterial3D.new()
	_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_material.albedo_color = tracer_color
	if state_label:
		state_label.visible = show_state_label
	if not melee and show_attack_warning:
		_warning = _make_warning()
	_set_state(State.IDLE)


func _physics_process(delta: float) -> void:
	if not _started:
		# Done here instead of _ready so the spawner has already placed us.
		_started = true
		_home = global_position
		agent.target_position = global_position
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node3D

	_can_see = player != null and _check_sight()
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)

	var wish_velocity := Vector3.ZERO
	match state:
		State.IDLE:
			if _can_see:
				_set_state(State.ALERT)
		State.ALERT:
			if _can_see and _cooldown_timer <= 0.0 and _flat_distance_to_player() <= attack_range:
				_start_attack()
			else:
				wish_velocity = _alert_movement(delta)
		State.ATTACK:
			_process_attack(delta)

	_update_warning()

	if state != State.IDLE and player:
		_face(player.global_position, delta)

	# Horizontal movement. ATTACK stops dead so a shooting animation can play.
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if state == State.ATTACK:
		flat = Vector3.ZERO
	else:
		flat = flat.move_toward(wish_velocity, acceleration * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()


# --- Moving (ALERT) -----------------------------------------------------------

func _alert_movement(delta: float) -> Vector3:
	if player == null:
		return Vector3.ZERO
	_repath_timer -= delta
	var repath := _repath_timer <= 0.0
	if repath:
		_repath_timer = repath_interval

	match behavior:
		Behavior.CHASE:
			if repath:
				agent.target_position = player.global_position
			return _follow_path(move_speed)

		Behavior.KEEP_DISTANCE:
			var dist := _flat_distance_to_player()
			var away := global_position - player.global_position
			away.y = 0.0
			away = away.normalized()
			var target := player.global_position
			var speed := move_speed
			if not _can_see or dist > preferred_distance + distance_tolerance:
				target = player.global_position                 # Too far / lost sight: get closer.
			elif dist < preferred_distance - distance_tolerance:
				target = global_position + away * 4.0           # Too close: back off.
			else:
				# Good distance: sidestep, switching direction now and then.
				_strafe_timer -= delta
				if _strafe_timer <= 0.0:
					_strafe_timer = randf_range(1.0, 2.5)
					_strafe_dir = -1.0 if randf() < 0.5 else 1.0
				target = global_position + away.cross(Vector3.UP) * _strafe_dir * 2.0
				speed = move_speed * strafe_speed_scale
			if repath:
				agent.target_position = target
			return _follow_path(speed)

		Behavior.HOLD_GROUND:
			if agent.is_navigation_finished() or _hold_move_time > 4.0:
				_hold_pause -= delta
				if _hold_pause <= 0.0:
					_hold_pause = hold_pause_time
					_hold_move_time = 0.0
					var angle := randf() * TAU
					var offset := Vector3(cos(angle), 0.0, sin(angle)) * randf_range(0.4, 1.0) * hold_radius
					# Snap the spot onto the walkable area so it's always reachable.
					agent.target_position = NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), _home + offset)
				return Vector3.ZERO
			_hold_move_time += delta
			var step := _follow_path(move_speed)
			if step == Vector3.ZERO:
				_hold_move_time = 99.0   # Path goes nowhere: give up and pick another spot.
			return step

	return Vector3.ZERO


## Velocity toward the next corner of the navigation path.
func _follow_path(speed: float) -> Vector3:
	if agent.is_navigation_finished():
		return Vector3.ZERO
	var dir := agent.get_next_path_position() - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return Vector3.ZERO
	return dir.normalized() * speed


func _face(target: Vector3, delta: float) -> void:
	var dir := target - global_position
	if Vector2(dir.x, dir.z).length() < 0.01:
		return
	var yaw := atan2(-dir.x, -dir.z)   # Our front is -Z.
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-turn_speed * delta))


# --- Attacking ----------------------------------------------------------------

func _start_attack() -> void:
	_set_state(State.ATTACK)
	_attack_timer = 0.0
	_shots_fired = 0
	_next_shot_time = attack_windup
	if player:
		_locked_aim = _player_chest()   # Remember where you were when the warning appeared.
		_aim_point = _locked_aim


func _process_attack(delta: float) -> void:
	_attack_timer += delta
	if player and aim_follow_speed > 0.0:
		_aim_point = _aim_point.move_toward(_player_chest(), aim_follow_speed * delta)
	while _attack_timer >= _next_shot_time and _next_shot_time <= attack_hold_time \
			and (burst_count == 0 or _shots_fired < burst_count):
		_do_attack()
		_shots_fired += 1
		_next_shot_time += attack_interval
	if _attack_timer >= attack_hold_time:
		_cooldown_timer = attack_cooldown
		_set_state(State.ALERT)


func _do_attack() -> void:
	if player == null:
		return
	if melee:
		var height_gap := absf(player.global_position.y - global_position.y)
		if _flat_distance_to_player() <= attack_range + 0.3 and height_gap < 2.0:
			_hurt_player(player)
		return

	var origin := muzzle.global_position
	var space := get_world_3d().direct_space_state
	var target := _player_chest()
	if lock_aim_on_warning:
		target = _locked_aim
	elif aim_follow_speed > 0.0:
		target = _aim_point
	var aim := Basis.looking_at(target - origin)
	for i in pellets:
		var end := origin + _spread_direction(aim) * attack_range * 2.0
		var query := PhysicsRayQueryParameters3D.create(origin, end)
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			end = hit.position
			_hurt_player(hit.collider, true)
		_spawn_tracer(origin, end)


## Enemies only hurt the player (no friendly fire, dummies are safe).
func _hurt_player(target: Object, is_bullet := false) -> void:
	if target != player:
		return
	if is_bullet and player.has_method("dodges_bullet") and player.dodges_bullet():
		return   # "Evasive" upgrade: the shot whizzed past.
	var player_health := player.get_node_or_null("Health") as Health
	if player_health:
		player_health.take_damage(attack_damage)


## Forward direction, nudged randomly inside a cone of spread_deg (same as the player's guns).
func _spread_direction(aim: Basis) -> Vector3:
	var forward := -aim.z
	if spread_deg <= 0.0:
		return forward
	var angle := randf() * TAU
	var radius := sqrt(randf()) * tan(deg_to_rad(spread_deg))
	return (forward + aim.x * cos(angle) * radius + aim.y * sin(angle) * radius).normalized()


## Placeholder bullet trail: a thin line that disappears almost instantly.
func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _tracer_material)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()
	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.top_level = true   # Vertices are in world space.
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line)
	line.global_transform = Transform3D.IDENTITY
	get_tree().create_timer(0.05, false).timeout.connect(line.queue_free)


# --- Attack warning -----------------------------------------------------------

## Placeholder warning: a glowing red ball. Swap for a sprite / effect later.
func _make_warning() -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = warning_color
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	sphere.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "AttackWarning"
	mi.mesh = sphere
	mi.position.y = warning_height
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


## Visible (and flashing) from the start of an attack until the first shot.
func _update_warning() -> void:
	if _warning == null:
		return
	var winding_up := state == State.ATTACK and _attack_timer < attack_windup
	_warning.visible = winding_up
	if winding_up:
		var pulse := 0.5 + 0.5 * sin(_attack_timer * warning_flash_speed)
		_warning.scale = Vector3.ONE * lerpf(0.7, 1.3, pulse)


# --- Senses / helpers ---------------------------------------------------------

func _check_sight() -> bool:
	var eye := global_position + Vector3.UP * eye_height
	var target := _player_chest()
	if eye.distance_to(target) > sight_range:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, target)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == player


func _player_chest() -> Vector3:
	return player.global_position + Vector3.UP * 0.7


func _flat_distance_to_player() -> float:
	var d := player.global_position - global_position
	return Vector2(d.x, d.z).length()


func _set_state(new_state: State) -> void:
	state = new_state
	if state_label:
		state_label.text = State.keys()[new_state]
	state_changed.emit(new_state)


func _on_damaged(_amount: float, _current: float) -> void:
	if _hit_tween:
		_hit_tween.kill()
	visual.scale = Vector3.ONE * hit_punch
	_hit_tween = create_tween()
	_hit_tween.tween_property(visual, "scale", Vector3.ONE, 0.12)
	if state == State.IDLE:
		_set_state(State.ALERT)   # Getting shot wakes it up.


func _on_died() -> void:
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node3D
	if player and player.has_method("on_enemy_killed"):
		player.on_enemy_killed(self)   # XP, ability charge, kill upgrades.
	# "Rip and Tear" upgrade: chainsaw kills drop every ammo type.
	var ups = player.get_node_or_null("Upgrades") if player else null
	var rip_and_tear: bool = ups != null and ups.chainsaw_ammo and player.is_chainsawing()
	for i in ammo_drops.size():
		var chance: float = ammo_drop_chances[i] if i < ammo_drop_chances.size() else 0.0
		if rip_and_tear:
			chance = 1.0
		var type: String = ammo_drop_types[i] if i < ammo_drop_types.size() else ""
		if randf() < chance + _drop_bonus(type):
			_drop(ammo_drops[i])
	if health.max_armor > 0.0 and randf() < armor_drop_chance + _drop_bonus("armor"):
		_drop(armor_drop_scene)
	if randf() < health_drop_chance + _drop_bonus("health"):
		var pack := _drop(health_drop_scene)
		if pack:
			pack.set("heal_amount", health_drop_amount)
	if randf() < dual_wield_drop_chance + _drop_bonus("dual"):
		_drop(dual_wield_drop_scene)
	if randf() < speed_drop_chance + _drop_bonus("speed"):
		_drop(speed_drop_scene)
	queue_free()


## Extra drop chance from the player's upgrades (0 if none).
func _drop_bonus(key: String) -> float:
	var ups = player.get_node_or_null("Upgrades") if player else null
	return ups.drop_bonus.get(key, 0.0) if ups else 0.0


## Makes this enemy tougher (used by waves). 1.5 = +50%. Call right after spawning.
func scale_strength(health_mult: float, damage_mult: float, speed_mult: float = 1.0) -> void:
	move_speed *= speed_mult
	acceleration *= speed_mult
	health.max_health *= health_mult
	health.current = health.max_health
	health.max_armor *= health_mult
	health.armor *= health_mult
	attack_damage *= damage_mult


## Wakes the enemy up right away (used by waves so enemies come for you without seeing you first).
func alert() -> void:
	if state == State.IDLE:
		_set_state(State.ALERT)


## Spawns a pickup near where we died, spread out a little so drops don't overlap.
func _drop(scene: PackedScene) -> Node3D:
	if scene == null:
		return null
	var drop := scene.instantiate() as Node3D
	var offset := Vector3(randf_range(-0.6, 0.6), 0.2, randf_range(-0.6, 0.6))
	get_parent().add_child.call_deferred(drop)
	drop.set_deferred("global_position", global_position + offset)
	return drop
