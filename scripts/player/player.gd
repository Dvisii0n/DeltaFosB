extends CharacterBody3D
## First-person controller: run, jump, slide, wall jump, slam.
## Every number below is exported, so you can tweak it in the Inspector while testing.

enum State { GROUND, AIR, SLIDE, SLAM, DASH }

@export_group("Look")
@export var mouse_sensitivity := 0.002

@export_group("Movement")
@export var move_speed := 12.0         ## Top running speed (m/s).
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


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.fov = base_fov
	dash_charges = max_dash_charges


func _unhandled_input(event: InputEvent) -> void:
	# Mouse look: turn the body left/right, tilt the head up/down.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
	elif event.is_action_pressed("capture_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	# WASD -> a direction in world space, relative to where the player faces.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	_update_timers(delta)

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

	move_and_slide()
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
	var target := wish_dir * move_speed
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

	# Air control: steer freely, but never lose speed gained from slides/slams.
	if wish_dir != Vector3.ZERO:
		var horizontal := _horizontal_velocity()
		var old_speed := horizontal.length()
		horizontal += wish_dir * air_accel * delta
		var speed_cap := maxf(old_speed, move_speed)
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
	weapon_holder.sliding = state == State.SLIDE  # weapons can strike a pose (pistol: gangster grip)
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
