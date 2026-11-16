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

@export_group("Dual Wield")
## Hold a mirrored copy of the current weapon in the left hand. Attacks alternate: right, then left.
@export var dual_wield := false: set = set_dual_wield
@export var dual_wield_delay := 0.15       ## Seconds after one hand attacks before the other hand may.

var slots: Array[Weapon] = [null, null, null, null]
var current: Weapon
var ammo := {}
var camera: Camera3D
var owner_body: CollisionObject3D          # The player body, so our shots don't hit ourselves.
var sliding := false                       # Set by the player; weapons use it for their slide pose.

var _fire_blocked := false                 # Stops the "recapture mouse" click from shooting.

var offhand: Weapon                        # Left-hand copy of the current weapon (only while dual wielding).
var _left_turn := false                    # true = the left hand attacks next.
var _hand_delay := 0.0                     # Time left before the other hand may attack.

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

	ammo = starting_ammo.duplicate()
	for child in get_children():
		if child is Weapon:
			_register(child)

	if slots[starting_slot]:
		select_slot(starting_slot)
	else:
		cycle(1)


func _unhandled_input(event: InputEvent) -> void:
	for i in 4:
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			select_slot(i)
	if event.is_action_pressed("weapon_next"):
		cycle(1)
	elif event.is_action_pressed("weapon_prev"):
		cycle(-1)


func _physics_process(delta: float) -> void:
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
		current.update_trigger(pressed, just_pressed, delta)
		return

	# Dual wield, both at once (e.g. miniguns): both hands get the trigger every frame.
	if current.dual_fire_together:
		current.update_trigger(pressed, just_pressed, delta)
		offhand.update_trigger(pressed, just_pressed, delta)
		return

	# Dual wield, taking turns: only the hand whose turn it is listens to the trigger.
	_hand_delay -= delta
	var hand: Weapon = offhand if _left_turn else current
	var other: Weapon = current if _left_turn else offhand
	other.update_trigger(false, false, delta)
	if _hand_delay > 0.0:
		hand.update_trigger(false, false, delta)
		return
	var cooldown_before := hand.cooldown
	hand.update_trigger(pressed, just_pressed, delta)
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


func use_ammo(type: String, amount: int) -> void:
	ammo[type] = ammo.get(type, 0) - amount
	ammo_changed.emit(type, ammo[type], max_ammo.get(type, 0))


## Returns how much was actually added (less if near the cap).
func add_ammo(type: String, amount: int) -> int:
	var before: int = ammo.get(type, 0)
	ammo[type] = mini(before + amount, max_ammo.get(type, before + amount))
	ammo_changed.emit(type, ammo[type], max_ammo.get(type, 0))
	return ammo[type] - before
