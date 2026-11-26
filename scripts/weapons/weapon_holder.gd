class_name WeaponHolder
extends Node3D
## Holds the player's 4 weapon slots and the shared ammo pool.
## Put weapon scenes as children: each one registers itself in its `slot`.

signal weapon_changed(weapon: Weapon)
signal ammo_changed(ammo_type: String, amount: int, max_amount: int)

@export var starting_ammo := {"light": 24, "shells": 8, "heavy": 100}
@export var max_ammo := {"light": 120, "shells": 32, "heavy": 400}
@export var starting_slot: Weapon.Slot = Weapon.Slot.SHORT
@export var require_mouse_capture := true  ## Only fire while the mouse is captured.

@export_group("Switching")
@export var switch_down_time := 0.18       ## Seconds to lower the old weapon off screen.
@export var switch_up_time := 0.25         ## Seconds to raise the new weapon into place.

@export_group("Weapon Bob (walking)")
@export var bob_enabled := true
@export var bob_amount := Vector2(0.035, 0.025)  ## Side-to-side (x) and up-down (y) bob, in metres.
@export var bob_rate_slow := 0.9           ## Side-to-side sways per second when walking slowly (dips are 2x this).
@export var bob_rate_fast := 1.4           ## ...and at bob_reference_speed or faster. Never goes above this.
@export var bob_reference_speed := 12.0    ## At this speed the bob is full size.
@export var land_lag := 0.004              ## Guns rise when falling / dip when jumping (metres per m/s).
@export var strafe_tilt_deg := 3.0         ## Guns roll a little when strafing.

@export_group("Weapon Sway (mouse look)")
@export var sway_enabled := true
@export var sway_amount := 0.0006          ## How far the guns lag behind per pixel of mouse movement (radians).
@export var sway_max_deg := 4.0            ## Never lag more than this.
@export var sway_position := 0.25          ## Guns also drift sideways with the sway (metres per radian).
@export var motion_smoothing := 10.0       ## How fast bob / sway settle back (higher = snappier).

@export_group("Camera Kick (recoil)")
@export var camera_kick_recover := 10.0    ## How fast the view settles after a shot's kick.
@export var camera_kick_max_deg := 8.0     ## Kicks stack (minigun) but never past this.

@export_group("Dual Wield")
## Hold a mirrored copy of the current weapon in the left hand. Attacks alternate: right, then left.
@export var dual_wield := false: set = set_dual_wield
@export var dual_wield_delay := 0.15       ## Seconds after one hand attacks before the other hand may.

var slots: Array[Weapon] = [null, null, null, null]
var current: Weapon
var ammo := {}
var camera: Camera3D
var owner_body: CollisionObject3D          # The player body, so our shots don't hit ourselves.
var sliding := false                       # Set by the player (no walking bob while sliding).
var gangster_grip := false                 # Set by bullet time: guns roll onto their side (pistol).

var _fire_blocked := false                 # Stops the "recapture mouse" click from shooting.

var offhand: Weapon                        # Left-hand copy of the current weapon (only while dual wielding).
# --- Upgrade modifiers (set by the player's Upgrades node; weapons read them) ---
var fire_rate_mult := 1.0                  # 1.2 = 20% faster.
var damage_mult := 1.0                     # All weapons.
var weapon_damage_mult := {}               # weapon_name -> extra multiplier for that weapon.
var crit_chance := 0.0                     # Chance a hit deals double damage.
var ammo_save_chance := 0.0                # Chance a shot uses no ammo.
var bonus_pellets := {}                    # weapon_name -> extra pellets.
var spread_mult := {}                      # weapon_name -> spread multiplier (0.8 = tighter).
var spin_up_mult := 1.0                    # Minigun spin-up time multiplier.
var melee_reach_mult := 1.0
var fury_damage_mult := 1.0               # Fury ability (x2 while active).
var fury_fire_rate_mult := 1.0            # Fury ability (multiplies on top of upgrades).
var dual_fire_all := false                 # true = every weapon fires both hands at once when dual wielding.

var dual_wield_time_left := 0.0            # Seconds left on the dual wield power-up (0 = none active).
var _left_turn := false                    # true = the left hand attacks next.
var _hand_delay := 0.0                     # Time left before the other hand may attack.

var _bob_phase := 0.0                      # Where we are in the walking bob cycle.
var _sway := Vector2.ZERO                  # Current look-sway (x = yaw, y = pitch), radians.
var _rest_transform := Transform3D.IDENTITY
var _cam_kick := 0.0                       # Current view kick from recoil (radians, camera pitch).
var _smoothed := Transform3D.IDENTITY      # Sway / roll / jump lag, eased.

enum SwitchPhase { NONE, DOWN, UP }
var _switch_phase := SwitchPhase.NONE      # DOWN = lowering the old weapon, UP = raising the new one.
var _switch_target: Weapon                 # The weapon we're switching to.


func _ready() -> void:
	# Run after the weapons each frame, so their cooldowns are already updated.
	process_physics_priority = 1
	camera = get_parent() as Camera3D
	var node := get_parent()
	while node and not node is CollisionObject3D:
		node = node.get_parent()
	owner_body = node

	_rest_transform = transform
	_smoothed = transform
	ammo = starting_ammo.duplicate()
	for child in get_children():
		if child is Weapon:
			_register(child)

	if slots[starting_slot]:
		select_slot(starting_slot)
	else:
		cycle(1)


func _unhandled_input(event: InputEvent) -> void:
	# Mouse look pushes the guns the other way; they catch up in _process (sway).
	if sway_enabled and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var limit := deg_to_rad(sway_max_deg)
		_sway.x = clampf(_sway.x + event.relative.x * sway_amount, -limit, limit)
		_sway.y = clampf(_sway.y + event.relative.y * sway_amount, -limit, limit)
	for i in 4:
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			select_slot(i)
	if event.is_action_pressed("weapon_next"):
		cycle(1)
	elif event.is_action_pressed("weapon_prev"):
		cycle(-1)


# --- Weapon motion: bob while walking, sway while looking ---------------------

## Called by a weapon when it fires: punches the view up a little.
func add_camera_kick(degrees: float) -> void:
	_cam_kick = minf(_cam_kick + deg_to_rad(degrees), deg_to_rad(camera_kick_max_deg))


func _process(delta: float) -> void:
	# Camera kick settles in real time, like the fire rate.
	if camera:
		_cam_kick = lerpf(_cam_kick, 0.0, 1.0 - exp(-camera_kick_recover * WorldTime.real_delta(delta)))
		camera.rotation.x = _cam_kick
	delta *= WorldTime.player_time_mult()   # Slows with bullet time unless you have Sandevistan.
	var body := owner_body as CharacterBody3D
	if body == null:
		return
	var t := 1.0 - exp(-motion_smoothing * delta)

	# Walking bob: a figure-eight, bigger and faster the faster you move on the ground.
	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var speed := flat.length()
	var bob := Vector3.ZERO
	var walking := bob_enabled and body.is_on_floor() and not sliding and speed > 0.5
	if walking:
		# Calm footstep rhythm: speed nudges the pace a little but mostly makes the bob bigger.
		var speed_t := clampf(speed / bob_reference_speed, 0.0, 1.0)
		_bob_phase += lerpf(bob_rate_slow, bob_rate_fast, speed_t) * TAU * delta
		var size := clampf(speed / bob_reference_speed, 0.0, 1.25)
		bob.x = sin(_bob_phase) * bob_amount.x * size
		bob.y = -absf(cos(_bob_phase)) * bob_amount.y * size
	else:
		_bob_phase = 0.0

	# Jump / fall: guns lag behind vertical movement.
	var lag := Vector3.ZERO
	if not body.is_on_floor():
		lag.y = clampf(-body.velocity.y * land_lag, -0.06, 0.06)

	# Strafe roll: how fast we move to our own right/left.
	var sideways := flat.dot(body.global_basis.x) / maxf(bob_reference_speed, 0.01)
	var roll := -clampf(sideways, -1.0, 1.0) * deg_to_rad(strafe_tilt_deg)

	# Sway settles back to centre.
	_sway = _sway.lerp(Vector2.ZERO, t)

	# Sway, roll and jump lag are smoothed; the walking bob is added on top unsmoothed
	# (smoothing would flatten it).
	var target := _rest_transform
	target.basis = target.basis * Basis.from_euler(Vector3(_sway.y, _sway.x, roll))
	target.origin += lag + Vector3(-_sway.x * sway_position, _sway.y * sway_position, 0.0)
	_smoothed = _smoothed.interpolate_with(target, t)
	transform = Transform3D(_smoothed.basis, _smoothed.origin + bob)


func _physics_process(delta: float) -> void:
	# Firing runs on real time, so bullet time never slows your fire rate.
	var fire_delta := WorldTime.real_delta(delta)
	delta *= WorldTime.player_time_mult()   # Sandevistan: switching at full speed.
	_update_dual_wield_timer(delta)
	if current == null:
		return
	var pressed := Input.is_action_pressed("fire")
	var just_pressed := Input.is_action_just_pressed("fire")

	# No shooting while the arms are going down / coming back up.
	if _switch_phase != SwitchPhase.NONE:
		_update_switch(delta)
		pressed = false
		just_pressed = false

	if require_mouse_capture and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_fire_blocked = true
	if _fire_blocked:
		if not pressed:
			_fire_blocked = false
		pressed = false
		just_pressed = false

	if offhand == null:
		current.update_trigger(pressed, just_pressed, fire_delta)
		return

	# Dual wield, both at once (e.g. miniguns): both hands get the trigger every frame.
	if current.dual_fire_together or dual_fire_all:
		current.update_trigger(pressed, just_pressed, fire_delta)
		offhand.update_trigger(pressed, just_pressed, fire_delta)
		return

	# Dual wield, taking turns: only the hand whose turn it is listens to the trigger.
	_hand_delay -= fire_delta
	var hand: Weapon = offhand if _left_turn else current
	var other: Weapon = current if _left_turn else offhand
	other.update_trigger(false, false, fire_delta)
	if _hand_delay > 0.0:
		hand.update_trigger(false, false, fire_delta)
		return
	var cooldown_before := hand.cooldown
	hand.update_trigger(pressed, just_pressed, fire_delta)
	if hand.cooldown > cooldown_before + 0.0001:  # it attacked -> other hand's turn, after a delay
		_left_turn = not _left_turn
		_hand_delay = dual_wield_delay


# --- Slots ----------------------------------------------------------------

## Starts switching to the weapon in `index`: the arms go down off screen, the weapons swap
## while they're hidden, then the new arms come back up (see _update_switch).
func select_slot(index: int) -> void:
	if index < 0 or index >= slots.size() or slots[index] == null:
		return
	var target := slots[index]
	if current == null:
		# Nothing in hand yet (game start): just raise the new weapon.
		_swap_to(target)
		_set_equip(1.0)
		_switch_phase = SwitchPhase.UP
		return
	if target == current:
		if _switch_phase == SwitchPhase.DOWN:  # changed our mind while lowering: bring it back up
			_switch_target = current
			_switch_phase = SwitchPhase.UP
		return
	_switch_target = target
	_switch_phase = SwitchPhase.DOWN  # also works mid-raise: it goes back down from where it is


## Moves the arms down/up each frame, and swaps weapons at the bottom.
func _update_switch(delta: float) -> void:
	if not is_instance_valid(_switch_target):
		_switch_target = current
	if _switch_phase == SwitchPhase.DOWN:
		_set_equip(current.equip_amount + delta / switch_down_time)
		if current.equip_amount >= 1.0:
			if _switch_target != current:
				_swap_to(_switch_target)
				_set_equip(1.0)
			_switch_phase = SwitchPhase.UP
	elif _switch_phase == SwitchPhase.UP:
		_set_equip(current.equip_amount - delta / switch_up_time)
		if current.equip_amount <= 0.0:
			_switch_phase = SwitchPhase.NONE


## How far down the held weapon (and its left-hand copy) is: 0 = up, 1 = off screen.
func _set_equip(amount: float) -> void:
	current.equip_amount = clampf(amount, 0.0, 1.0)
	current.snap_visual()
	if offhand:
		offhand.equip_amount = current.equip_amount
		offhand.snap_visual()


## The actual swap (happens while the arms are off screen).
func _swap_to(weapon: Weapon) -> void:
	if current:
		current.visible = false
		current.equip_amount = 0.0
		current.on_unequipped()
	current = weapon
	current.visible = true
	current.on_equipped()
	_refresh_offhand()
	weapon_changed.emit(current)


# --- Dual wield -------------------------------------------------------------

## Total damage multiplier for a weapon (all-weapon upgrades x that weapon's own upgrades).
func damage_multiplier(weapon_name: String) -> float:
	return damage_mult * weapon_damage_mult.get(weapon_name, 1.0) * fury_damage_mult


## Total fire rate multiplier (upgrades x Fury).
func total_fire_rate_mult() -> float:
	return fire_rate_mult * fury_fire_rate_mult


## Permanently swaps the weapon in a slot for a new one (e.g. the Chainsaw upgrade replaces
## the pencil). If the old weapon was in your hands, the new one is in your hands now.
func replace_weapon(weapon_scene: PackedScene) -> Weapon:
	var weapon := weapon_scene.instantiate() as Weapon
	weapon.holder = self
	weapon.visible = false
	add_child(weapon)
	var old := slots[weapon.slot]
	slots[weapon.slot] = weapon
	if old:
		if old == current:
			_swap_to(weapon)
		if _switch_target == old:
			_switch_target = weapon
		old.queue_free()
	return weapon


## Power-up: dual wield for `duration` seconds (a new pickup resets the timer).
func give_dual_wield(duration: float) -> void:
	dual_wield_time_left = maxf(dual_wield_time_left, duration)
	if not dual_wield:
		set_dual_wield(true)


func _update_dual_wield_timer(delta: float) -> void:
	if dual_wield_time_left <= 0.0:
		return
	dual_wield_time_left -= delta
	if dual_wield_time_left <= 0.0:
		dual_wield_time_left = 0.0
		set_dual_wield(false)


func set_dual_wield(on: bool) -> void:
	dual_wield = on
	if is_inside_tree():
		_refresh_offhand()


## Makes (or removes) the left-hand copy of the current weapon.
func _refresh_offhand() -> void:
	if offhand:
		offhand.queue_free()
		offhand = null
	_left_turn = false
	_hand_delay = 0.0
	if current:
		current.set_dual_wielded(false)
	if not dual_wield or current == null or not current.can_dual_wield or current.scene_file_path == "":
		return
	offhand = load(current.scene_file_path).instantiate() as Weapon
	# Mirror it left-to-right: a right arm + gun becomes a left arm + gun on the other side.
	offhand.transform = Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO) * current.transform
	offhand.holder = self
	add_child(offhand)
	offhand.on_equipped()
	offhand.equip_amount = current.equip_amount  # toggled mid-switch: match the right hand
	current.set_dual_wielded(true)
	offhand.set_dual_wielded(true)


func cycle(step: int) -> void:
	# Mid-switch, cycle from the weapon we're switching to, not the one going away.
	var from: Weapon = _switch_target if (_switch_phase == SwitchPhase.DOWN and is_instance_valid(_switch_target)) else current
	var start := from.slot if from else -1
	for i in range(1, slots.size() + 1):
		var index := posmod(start + step * i, slots.size())
		if slots[index]:
			select_slot(index)
			return


## Adds a new weapon, replacing whatever was in its slot. Use this for future weapon pickups.
func equip(weapon_scene: PackedScene) -> Weapon:
	var weapon := weapon_scene.instantiate() as Weapon
	add_child(weapon)
	_register(weapon)
	select_slot(weapon.slot)
	return weapon


func _register(weapon: Weapon) -> void:
	var old := slots[weapon.slot]
	if old and old != weapon:
		if old == current:
			current = null
		old.queue_free()
	slots[weapon.slot] = weapon
	weapon.holder = self
	weapon.visible = false


# --- Ammo -----------------------------------------------------------------

func has_ammo(type: String, amount: int) -> bool:
	return ammo.get(type, 0) >= amount


## Adds `fraction` of each ammo type's max (0.5 = half a full load), never above max. Used by Fury.
func refill_ammo(fraction: float) -> void:
	for type in max_ammo:
		add_ammo(type, ceili(max_ammo[type] * fraction))


func use_ammo(type: String, amount: int) -> void:
	if randf() < ammo_save_chance:
		return   # "Ammo efficiency" upgrade: this shot was free.
	ammo[type] = ammo.get(type, 0) - amount
	ammo_changed.emit(type, ammo[type], max_ammo.get(type, 0))


## Returns how much was actually added (less if near the cap).
func add_ammo(type: String, amount: int) -> int:
	var before: int = ammo.get(type, 0)
	ammo[type] = mini(before + amount, max_ammo.get(type, before + amount))
	ammo_changed.emit(type, ammo[type], max_ammo.get(type, 0))
	return ammo[type] - before
