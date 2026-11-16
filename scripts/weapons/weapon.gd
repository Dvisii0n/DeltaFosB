class_name Weapon
extends Node3D
## Base class for every weapon. Handles cooldown, ammo cost and recoil.
## Subclasses only need to override _fire() (see MeleeWeapon, HitscanWeapon).
##
## To make a new weapon: duplicate a weapon scene, change the stats in the Inspector,
## and replace its "Visual" child with your model.

enum Slot { MELEE, SHORT, LONG, SPECIAL }
enum CrosshairStyle { CROSS, CIRCLE }

@export var weapon_name := "Weapon"
@export var slot: Slot = Slot.SHORT
@export var damage := 10.0
@export var fire_interval := 0.2       ## Seconds between attacks.
@export var automatic := false         ## true = hold the button to keep firing.
@export var ammo_type := ""            ## "" = needs no ammo. Otherwise "light", "shells" or "heavy".
@export var ammo_per_shot := 1
@export var crosshair: CrosshairStyle = CrosshairStyle.CROSS  ## Look of the crosshair while this weapon is held.
@export var can_dual_wield := true      ## false = never held in both hands.

@export_group("Dual Wield")
## Nodes hidden while dual wielding (e.g. the shotgun's pump arm: nobody has 4 arms).
@export var dual_hide_nodes: Array[NodePath] = []
## Extra move for Visual while dual wielding (camera space, metres). +X pushes the guns apart:
## the left copy is mirrored, so the same offset sends it the other way.
@export var dual_pose_offset := Vector3.ZERO
## true = both hands fire at the same time (minigun). false = they take turns, right then left.
@export var dual_fire_together := false
## While dual wielding, after each shot Visual dips down off screen and comes back
## (pretend-pumping one-handed). 0 = no dip. In metres.
@export var dual_dip_depth := 0.0
@export var dual_dip_tilt := 35.0      ## Degrees the gun tips down while dipping.
@export var dual_dip_delay := 0.12     ## Seconds after the shot before it starts going down (recoil shows first).
@export var dual_dip_down_time := 0.15 ## Seconds to go down.
@export var dual_dip_up_time := 0.22   ## Seconds to come back up (ends just before it can fire again).

@export_group("Feedback")
@export var recoil_kick := 0.08        ## How far Visual jumps back per shot (negative = lunges forward).
@export var recoil_pitch := 0.0        ## Degrees Visual tilts up per shot (muzzle flip).
@export var recoil_recover := 12.0     ## How fast Visual returns to rest.

@export_group("Equip")
@export var equip_drop := 0.7          ## How far (m) Visual drops below its rest spot when switching weapons.
@export var equip_tilt := 35.0         ## Degrees it tips down while lowered.

@export_group("Slide Pose")
## Degrees the gun rolls onto its side while the player slides ("gangster grip").
## Positive = top of the gun tips toward the screen centre. 0 = no pose.
@export var slide_roll_deg := 0.0
@export var slide_pose_offset := Vector3.ZERO  ## Extra move while sliding (camera space, metres).
@export var slide_pose_speed := 8.0            ## How fast it gets into / out of the pose.
@export var slide_pivot: NodePath              ## The gun rolls around this node (e.g. the gun model). Empty = Visual's origin.

var holder: WeaponHolder               # Set by the WeaponHolder that owns this weapon.
var cooldown := 0.0

@onready var visual: Node3D = get_node_or_null("Visual")
var _visual_rest := Vector3.ZERO
var _visual_rest_rotation := Quaternion.IDENTITY
var _animated_models: Array[Node] = []  # Models with arm_view.gd (arm, gun slide...).
var dual_wielded := false               # Set by the WeaponHolder (see set_dual_wielded).
var _dip_left := 0.0                    # Seconds left in the current dual-wield dip.
var _slide_pose := 0.0                  # 0 = normal, 1 = full slide pose.
var equip_amount := 0.0                 # 0 = held up, 1 = lowered off screen. Set by the WeaponHolder.


func _ready() -> void:
	if visual:
		_visual_rest = visual.position
		_visual_rest_rotation = visual.quaternion
	# Every model with arm_view.gd plays its attack animation when we fire.
	for node in find_children("*", "", true, false):
		if node.has_method("play_attack"):
			_animated_models.append(node)


func _physics_process(delta: float) -> void:
	cooldown -= delta
	if _dip_left > 0.0:
		_dip_left -= delta
	var wants_pose := 1.0 if (holder and holder.sliding and slide_roll_deg != 0.0) else 0.0
	_slide_pose = move_toward(_slide_pose, wants_pose, slide_pose_speed * delta)
	if visual:
		if equip_amount > 0.0:
			# Switching weapons: follow the lower/raise motion exactly (no smoothing lag).
			visual.position = _target_position()
			visual.quaternion = _target_rotation(0.0)
		else:
			var t := 1.0 - exp(-recoil_recover * delta)
			visual.position = visual.position.lerp(_target_position(), t)
			visual.quaternion = visual.quaternion.slerp(_target_rotation(0.0), t)


## Where Visual wants to be right now: rest, plus the slide pose and the dual-wield dip.
func _target_position() -> Vector3:
	var p := smoothstep(0.0, 1.0, _slide_pose)
	var pos := _visual_rest + slide_pose_offset * p
	if dual_wielded:
		pos += dual_pose_offset
	# Roll around the pivot instead of Visual's origin: move Visual so the pivot stays put.
	var pivot := get_node_or_null(slide_pivot) as Node3D
	if pivot and p > 0.0:
		var arm := Basis(_visual_rest_rotation) * visual.basis.get_scale().x * visual.to_local(pivot.global_position)
		var roll := Quaternion(Vector3.BACK, deg_to_rad(slide_roll_deg * p))
		pos += arm - roll * arm
	if _dip_left > 0.0:
		pos.y -= dual_dip_depth * _dip_amount()
	pos.y -= equip_drop * _equip_curve()
	return pos


## Same, for rotation. `pitch_deg` tilts the muzzle up (used for recoil).
func _target_rotation(pitch_deg: float) -> Quaternion:
	var p := smoothstep(0.0, 1.0, _slide_pose)
	if _dip_left > 0.0:
		pitch_deg -= dual_dip_tilt * _dip_amount()
	pitch_deg -= equip_tilt * _equip_curve()
	# Pitch first (muzzle flip follows the gun when it's on its side), then roll around
	# the camera's forward axis (+Z points at the player, so + = counter-clockwise on screen).
	var pitch := Quaternion(Vector3.RIGHT, deg_to_rad(pitch_deg))
	var roll := Quaternion(Vector3.BACK, deg_to_rad(slide_roll_deg * p))
	return roll * pitch * _visual_rest_rotation


## Called by the holder every physics frame while this weapon is equipped.
func update_trigger(pressed: bool, just_pressed: bool, _delta: float) -> void:
	var wants_to_fire := just_pressed or (automatic and pressed)
	if wants_to_fire and can_fire():
		_do_fire()


func can_fire() -> bool:
	if cooldown > 0.0001:  # tiny margin so float rounding doesn't cost an extra frame
		return false
	return ammo_type == "" or holder.has_ammo(ammo_type, ammo_per_shot)


func _do_fire() -> void:
	# "+=" keeps leftover time, so fire rate stays exact even when it doesn't
	# divide evenly into frames (e.g. minigun at 20 shots/s).
	cooldown = maxf(cooldown, 0.0) + fire_interval
	if ammo_type != "":
		holder.use_ammo(ammo_type, ammo_per_shot)
	_fire()
	for model in _animated_models:
		model.play_attack()
	if visual:
		visual.position = _target_position() + Vector3(0.0, 0.0, recoil_kick)
		# Flip the muzzle up (around the camera's right axis, so it works however Visual
		# is turned), on top of whatever pose the gun is in.
		visual.quaternion = _target_rotation(recoil_pitch)
	if dual_wielded and dual_dip_depth > 0.0:
		_dip_left = fire_interval


## Override in subclasses: what actually happens when the weapon fires.
func _fire() -> void:
	pass


func on_equipped() -> void:
	pass


func on_unequipped() -> void:
	pass


## Called by the WeaponHolder when dual wielding starts/stops for this weapon.
func set_dual_wielded(on: bool) -> void:
	dual_wielded = on
	if not on:
		_dip_left = 0.0
	for path in dual_hide_nodes:
		var node := get_node_or_null(path) as Node3D
		if node:
			node.visible = not on


## Puts Visual exactly where it should be right now (used when switching, so a freshly
## shown weapon never flashes at its raised position for a frame).
func snap_visual() -> void:
	if visual:
		visual.position = _target_position()
		visual.quaternion = _target_rotation(0.0)


## Eased version of equip_amount (starts and stops gently).
func _equip_curve() -> float:
	return smoothstep(0.0, 1.0, equip_amount)


## 0 = at rest, 1 = fully down. Shape over the dip: wait, go down, stay, come back up.
func _dip_amount() -> float:
	var elapsed := fire_interval - _dip_left
	var down := smoothstep(dual_dip_delay, dual_dip_delay + dual_dip_down_time, elapsed)
	var up_end := fire_interval - 0.08  # be back up a moment before the next shot
	var up := 1.0 - smoothstep(up_end - dual_dip_up_time, up_end, elapsed)
	return minf(down, up)


# --- Helpers for subclasses ------------------------------------------------

## Damages whatever was hit, if it has a "Health" child. Returns true if it did.
func deal_damage(target: Object, amount: float) -> bool:
	if not target is Node:
		return false
	var health := (target as Node).get_node_or_null("Health") as Health
	if health:
		health.take_damage(amount)
		return true
	return false
