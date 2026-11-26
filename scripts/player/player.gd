extends CharacterBody3D
## First-person controller: run, jump, slide, wall jump, slam.
## Every number below is exported, so you can tweak it in the Inspector while testing.

enum State { GROUND, AIR, SLIDE, SLAM, DASH }

@export_group("Look")
@export var mouse_sensitivity := 0.002

@export_group("Movement")
@export var move_speed := 10.0         ## Top running speed (m/s).
@export var ground_accel := 90.0       ## How fast you reach top speed.
@export var ground_friction := 70.0    ## How fast you stop when you let go.
@export var air_accel := 30.0          ## Steering strength while airborne.
@export var gravity := 30.0
@export var jump_velocity := 10.0

@export_group("Jump Assist")
@export var coyote_time := 0.1         ## Grace period to jump after leaving a ledge.
@export var jump_buffer_time := 0.12   ## A jump pressed this early before landing still counts.

@export_group("Slide")
@export var slide_speed := 18.0        ## Minimum slide speed.
@export var stand_height := 1.8
@export var slide_height := 1.0
@export var head_stand_y := 1.6
@export var head_slide_y := 0.8

@export_group("Dash")
@export var dash_speed := 32.0
@export var dash_duration := 0.15      ## Seconds the burst lasts (no gravity during it).
@export var dash_exit_speed := 14.0    ## Speed you keep when the dash ends normally.
@export var max_dash_charges := 3
@export var dash_recharge_time := 0.8  ## Seconds to refill one charge.

@export_group("Wall Jump")
@export var wall_jump_up := 9.0
@export var wall_jump_push := 10.0
@export var max_wall_jumps := 3
@export var max_air_jumps := 0        ## Jumps allowed in mid-air (Double Jump upgrade).

@export_group("Slam")
@export var slam_speed := 40.0
@export var slam_bounce_window := 0.2  ## Jump this soon after a slam landing for a big bounce.
@export var slam_bounce_velocity := 16.0

@export_group("Camera")
@export var base_fov := 90.0
@export var max_fov := 110.0
@export var speed_for_max_fov := 30.0
@export var strafe_tilt_deg := 2.5
@export var slide_tilt_deg := 5.0
@export var camera_smoothing := 10.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var speed_label: Label = $DebugHUD/SpeedLabel
@onready var weapon_label: Label = $DebugHUD/WeaponLabel
@onready var crosshair: Control = $DebugHUD/Crosshair
@onready var weapon_holder: WeaponHolder = $Head/Camera3D/WeaponHolder
@onready var health: Health = $Health
@onready var player_bars: Control = $DebugHUD/PlayerBars
@onready var ability: Ability = $Ability
@onready var bullet_time_tint: ColorRect = $DebugHUD/BulletTimeTint
@onready var upgrades: Upgrades = $Upgrades
@onready var fury: Fury = $Fury
@onready var fury_tint: ColorRect = $DebugHUD/FuryTint
@onready var screen_blood: Control = $DebugHUD/ScreenBlood
@onready var xp_bar: Control = $DebugHUD/XPBar

@export_group("Upgrade Effects")
@export var regen_delay := 3.0         ## Seconds without damage before Regen kicks in.
@export var magnet_pull_speed := 14.0  ## How fast pickups fly to you (Pickup Magnet upgrade).
@export var slam_wave_radius := 4.0    ## Ground Pound upgrade reach.
@export var focus_fade_time := 0.25    ## Seconds for the bullet time vignette to close in / open up.
@export var evasion_full_speed := 20.0 ## Speed (m/s) where the Evasive upgrade's dodge chance is full.

@export_group("Interact")
@export var interact_range := 3.0      ## How far away you can press buttons with E.

var state := State.AIR
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var slam_bounce_timer := 0.0
var wall_jumps_left := 0
var slide_direction := Vector3.ZERO
var slide_current_speed := 0.0
var dash_charges := 0.0                # Float so it can refill smoothly.
var dash_timer := 0.0
var dash_direction := Vector3.ZERO
var air_jumps_left := 0
var _focus_tween: Tween
var speed_boost_time_left := 0.0      # Speed pickup: seconds left.
var _speed_boost_mult := 1.0
var _since_damage := 999.0            # Seconds since we were last hurt (for Regen).


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.fov = base_fov
	dash_charges = max_dash_charges
	health.died.connect(_on_died)
	player_bars.health = health
	player_bars.ability = ability
	player_bars.fury = fury
	fury.started.connect(func(): fury_tint.visible = true)
	fury.stopped.connect(func(): fury_tint.visible = false)
	xp_bar.upgrades = upgrades
	health.damaged.connect(_on_hurt)
	ability.started.connect(func(): _fade_focus(1.0))
	ability.stopped.connect(func(): _fade_focus(0.0))


func _unhandled_input(event: InputEvent) -> void:
	# Mouse look: turn the body left/right, tilt the head up/down.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
	elif event.is_action_pressed("capture_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("interact"):
		# E presses a button if you're looking at one, otherwise it triggers Fury.
		if not _interact():
			fury.activate()   # Does nothing until the Fury bar is full.
	elif event.is_action_pressed("ability"):
		ability.activate()   # Does nothing until the bar is full.


## Press whatever you're looking at (if it has a press() function, like the spawn buttons).
## Returns true if something was pressed.
func _interact() -> bool:
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * interact_range)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider.has_method("press"):
		hit.collider.press()
		return true
	return false


## Called by armor pickups. Returns how much armor was added (0 = already full).
func add_armor(amount: float) -> float:
	return health.add_armor(amount * upgrades.armor_pickup_mult)


## Called by health packs. Returns how much was healed (0 = already full).
func heal(amount: float) -> float:
	return health.heal(amount * upgrades.heal_mult)


## Called by enemies when they die: XP, ability charge and kill-based upgrades.
func on_enemy_killed(enemy: Enemy) -> void:
	upgrades.add_xp(enemy.xp_value)
	ability.add_charge(enemy.ability_charge * upgrades.ability_charge_mult)
	if upgrades.lifesteal > 0.0:
		health.heal(upgrades.lifesteal)
	if upgrades.bt_extend_per_kill > 0.0:
		ability.extend(upgrades.bt_extend_per_kill)


## Called by our weapons whenever they hurt something ("Rage" upgrade).
func on_damage_dealt(amount: float) -> void:
	if upgrades.charge_per_10_damage > 0.0:
		ability.add_charge(amount / 10.0 * upgrades.charge_per_10_damage)


## Speed pickup: move faster for a while (a new pickup resets the timer).
func give_speed_boost(duration: float, mult: float) -> void:
	speed_boost_time_left = maxf(speed_boost_time_left, duration)
	_speed_boost_mult = mult


func speed_boost_mult() -> float:
	return _speed_boost_mult if speed_boost_time_left > 0.0 else 1.0


## Bullet time focus vignette: eases the screen edges in (1) or out (0).
## Real time, so the slow motion doesn't slow the fade itself.
func _fade_focus(target: float) -> void:
	var mat := bullet_time_tint.material as ShaderMaterial
	if _focus_tween:
		_focus_tween.kill()
	_focus_tween = create_tween().set_ignore_time_scale(true)
	_focus_tween.tween_method(func(v: float): mat.set_shader_parameter("strength", v),
		mat.get_shader_parameter("strength"), target, focus_fade_time)


## Getting hurt splatters blood on the screen edges (bigger hit = more).
func _on_hurt(amount: float, _current: float) -> void:
	_since_damage = 0.0
	splash_screen(amount / 12.0)


## Blood on the screen (edges only, the centre stays clear). Also called by Blood when gore
## happens right next to you.
func splash_screen(intensity: float) -> void:
	screen_blood.splash(intensity)


## True while the chainsaw (Chainsaw upgrade) is in your hands. Used by "Rip and Tear".
func is_chainsawing() -> bool:
	return weapon_holder.current != null and weapon_holder.current.weapon_name == "Chainsaw"


## "Evasive" upgrade: chance an enemy bullet misses, bigger the faster you move
## (full chance at evasion_full_speed and above).
func dodges_bullet() -> bool:
	if upgrades.evasion <= 0.0:
		return false
	var speed_factor := clampf(velocity.length() / evasion_full_speed, 0.0, 1.0)
	return randf() < upgrades.evasion * speed_factor


## Called by the dual wield power-up.
func give_dual_wield(duration: float) -> void:
	weapon_holder.give_dual_wield(duration + upgrades.dual_duration_bonus)


## Regen and pickup magnet upgrades.
func _update_upgrade_effects(delta: float) -> void:
	_since_damage += delta
	speed_boost_time_left = maxf(speed_boost_time_left - delta, 0.0)
	if upgrades.regen_per_second > 0.0 and _since_damage >= regen_delay:
		health.heal(upgrades.regen_per_second * delta)
	if upgrades.magnet_range > 0.0:
		var center := global_position + Vector3.UP * 0.5
		for pickup in get_tree().get_nodes_in_group("pickups"):
			var p := pickup as Node3D
			if p.visible and p.global_position.distance_to(center) <= upgrades.magnet_range:
				p.global_position = p.global_position.move_toward(center, magnet_pull_speed * delta)


## Ground Pound upgrade: landing a slam hurts enemies around you.
func _slam_shockwave() -> void:
	if upgrades.slam_damage <= 0.0:
		return
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(global_position) <= slam_wave_radius:
			enemy.health.take_damage(upgrades.slam_damage)


## Placeholder death: restart the level.
func _on_died() -> void:
	get_tree().reload_current_scene.call_deferred()


func _physics_process(delta: float) -> void:
	# Bullet time slows `delta` for everyone. With Sandevistan we turn it back into real time.
	var time_mult := WorldTime.player_time_mult()
	delta *= time_mult

	# WASD -> a direction in world space, relative to where the player faces.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	_update_timers(delta)
	_update_upgrade_effects(delta)

	# Dash works from any state except mid-dash.
	if Input.is_action_just_pressed("dash") and state != State.DASH and dash_charges >= 1.0:
		_start_dash(wish_dir)

	match state:
		State.GROUND:
			_process_ground(delta, wish_dir)
		State.AIR:
			_process_air(delta, wish_dir)
		State.SLIDE:
			_process_slide(delta)
		State.SLAM:
			_process_slam()
		State.DASH:
			_process_dash(delta)

	# move_and_slide() uses the slowed physics step, so speed the move up to match (Sandevistan).
	velocity *= time_mult
	move_and_slide()
	velocity /= time_mult
	_update_camera(delta, input_dir)
	_update_hud()


# --- Timers ---------------------------------------------------------------

func _update_timers(delta: float) -> void:
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer -= delta

	slam_bounce_timer -= delta

	if state != State.DASH:
		dash_charges = minf(dash_charges + delta / dash_recharge_time, max_dash_charges)

	if is_on_floor():
		coyote_timer = coyote_time
		wall_jumps_left = max_wall_jumps
		air_jumps_left = max_air_jumps
	else:
		coyote_timer -= delta


# --- States ---------------------------------------------------------------

func _process_ground(delta: float, wish_dir: Vector3) -> void:
	if not is_on_floor():
		state = State.AIR
		_process_air(delta, wish_dir)
		return

	if Input.is_action_pressed("slide"):
		_start_slide(wish_dir)
		return

	if _try_jump():
		return

	# Snappy acceleration toward the target speed; strong friction when no input.
	var target := wish_dir * move_speed * speed_boost_mult()
	var rate := ground_accel if wish_dir != Vector3.ZERO else ground_friction
	var horizontal := _horizontal_velocity().move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _process_air(delta: float, wish_dir: Vector3) -> void:
	if is_on_floor():
		state = State.GROUND
		_process_ground(delta, wish_dir)
		return

	velocity.y -= gravity * delta

	if Input.is_action_just_pressed("slide"):
		state = State.SLAM
		return

	if jump_buffer_timer > 0.0:
		if _try_jump():
			return
		if is_on_wall() and wall_jumps_left > 0:
			_wall_jump()
			return
		if air_jumps_left > 0:   # Double Jump upgrade.
			velocity.y = jump_velocity
			air_jumps_left -= 1
			jump_buffer_timer = 0.0
			return

	# Air control: steer freely, but never lose speed gained from slides/slams.
	if wish_dir != Vector3.ZERO:
		var horizontal := _horizontal_velocity()
		var old_speed := horizontal.length()
		horizontal += wish_dir * air_accel * delta
		var speed_cap := maxf(old_speed, move_speed * speed_boost_mult())
		horizontal = horizontal.limit_length(speed_cap)
		velocity.x = horizontal.x
		velocity.z = horizontal.z


func _process_slide(delta: float) -> void:
	if not Input.is_action_pressed("slide"):
		_end_slide()
		return

	if _try_jump():  # Jumping out of a slide keeps all the speed.
		_end_slide()
		state = State.AIR
		return

	# Slid off a ledge: become airborne with full momentum.
	if not is_on_floor() and coyote_timer <= 0.0:
		_end_slide()
		return

	velocity.x = slide_direction.x * slide_current_speed
	velocity.z = slide_direction.z * slide_current_speed
	if not is_on_floor():
		velocity.y -= gravity * delta


func _process_slam() -> void:
	velocity = Vector3(0.0, -slam_speed, 0.0)
	if is_on_floor():
		state = State.GROUND
		slam_bounce_timer = slam_bounce_window
		_slam_shockwave()


func _process_dash(delta: float) -> void:
	dash_timer -= delta

	# Dash-jump: jumping mid-dash keeps the full dash speed.
	if _try_jump():
		return

	velocity = dash_direction * dash_speed  # Straight line, no gravity.

	if dash_timer <= 0.0:
		velocity = dash_direction * dash_exit_speed
		state = State.GROUND if is_on_floor() else State.AIR


# --- Actions --------------------------------------------------------------

func _start_dash(wish_dir: Vector3) -> void:
	if state == State.SLIDE:
		_set_body_height(stand_height)
	state = State.DASH
	dash_charges -= 1.0
	dash_timer = dash_duration
	# Dash where you're moving, or straight ahead if standing still.
	dash_direction = wish_dir if wish_dir != Vector3.ZERO else -transform.basis.z


func _try_jump() -> bool:
	if jump_buffer_timer <= 0.0 or coyote_timer <= 0.0:
		return false
	velocity.y = slam_bounce_velocity if slam_bounce_timer > 0.0 else jump_velocity
	jump_buffer_timer = 0.0
	coyote_timer = 0.0
	slam_bounce_timer = 0.0
	state = State.AIR
	return true


func _wall_jump() -> void:
	var normal := get_wall_normal()
	# Keep speed along the wall, then kick away from it and up.
	var horizontal := _horizontal_velocity().slide(normal) + normal * wall_jump_push
	velocity = Vector3(horizontal.x, wall_jump_up, horizontal.z)
	wall_jumps_left -= 1
	jump_buffer_timer = 0.0


func _start_slide(wish_dir: Vector3) -> void:
	state = State.SLIDE
	# Slide where you're moving, or straight ahead if standing still.
	slide_direction = wish_dir if wish_dir != Vector3.ZERO else -transform.basis.z
	slide_current_speed = maxf(_horizontal_velocity().length(), slide_speed)
	_set_body_height(slide_height)


func _end_slide() -> void:
	_set_body_height(stand_height)
	state = State.GROUND if is_on_floor() else State.AIR


func _set_body_height(height: float) -> void:
	var capsule := collision.shape as CapsuleShape3D
	capsule.height = height
	collision.position.y = height / 2.0


# --- Feedback -------------------------------------------------------------

func _update_camera(delta: float, input_dir: Vector2) -> void:
	var weight := 1.0 - exp(-camera_smoothing * delta)

	# Lower the head while sliding.
	var head_target := head_slide_y if state == State.SLIDE else head_stand_y
	weapon_holder.sliding = state == State.SLIDE  # no walking bob while sliding
	head.position.y = lerpf(head.position.y, head_target, weight)

	# Lean into strafes, lean harder while sliding.
	var tilt := -input_dir.x * deg_to_rad(strafe_tilt_deg)
	if state == State.SLIDE:
		# How much the slide goes to the camera's right (+1) or left (-1).
		# Straight forward/back = no lean. Updates as you look around mid-slide.
		var sideways := slide_direction.dot(transform.basis.x)
		tilt = -sideways * deg_to_rad(slide_tilt_deg)
	camera.rotation.z = lerp_angle(camera.rotation.z, tilt, weight)

	# Widen FOV the faster you go above running speed.
	var t := inverse_lerp(move_speed, speed_for_max_fov, _horizontal_velocity().length())
	var fov_target := lerpf(base_fov, max_fov, clampf(t, 0.0, 1.0))
	camera.fov = lerpf(camera.fov, fov_target, weight)


func _update_hud() -> void:
	speed_label.text = "Speed: %.1f m/s | State: %s | Dash: %d" % [
		_horizontal_velocity().length(), State.keys()[state], int(dash_charges)
	]

	var weapon := weapon_holder.current
	crosshair.weapon = weapon  # the crosshair changes shape per weapon
	crosshair.camera = camera
	if weapon == null:
		weapon_label.text = "No weapon"
	elif weapon.ammo_type == "":
		weapon_label.text = "%s | no ammo needed" % weapon.weapon_name
	else:
		weapon_label.text = "%s | %s %d/%d" % [
			weapon.weapon_name, weapon.ammo_type.capitalize(),
			weapon_holder.ammo.get(weapon.ammo_type, 0),
			weapon_holder.max_ammo.get(weapon.ammo_type, 0),
		]

	if speed_boost_time_left > 0.0:
		weapon_label.text += " | SPEED %ds" % ceili(speed_boost_time_left)
	if weapon_holder.dual_wield_time_left > 0.0:
		weapon_label.text += " | DUAL WIELD %ds" % ceili(weapon_holder.dual_wield_time_left)


## Called by the pause menu's FOV slider.
## Moves max_fov too, so the speed boost stays the same size.
func set_base_fov(value: float) -> void:
	var boost := max_fov - base_fov
	base_fov = value
	max_fov = value + boost
	camera.fov = value  # Apply right away so you see it behind the menu.


## Called by ammo pickups.
func add_ammo(type: String, amount: int) -> int:
	return weapon_holder.add_ammo(type, amount)


func _horizontal_velocity() -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)
