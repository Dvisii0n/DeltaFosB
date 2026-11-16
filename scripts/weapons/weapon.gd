class_name Weapon
extends Node3D
## Base class for every weapon. Handles cooldown, ammo cost and recoil.
## Subclasses only need to override _fire() (see MeleeWeapon, HitscanWeapon).
##
## To make a new weapon: duplicate a weapon scene, change the stats in the Inspector,
## and replace its "Visual" child with your model.

enum Slot { MELEE, SHORT, LONG, SPECIAL }

@export var weapon_name := "Weapon"
@export var slot: Slot = Slot.SHORT
@export var damage := 10.0
@export var fire_interval := 0.2       ## Seconds between attacks.
@export var automatic := false         ## true = hold the button to keep firing.
@export var ammo_type := ""            ## "" = needs no ammo. Otherwise "light", "shells" or "heavy".
@export var ammo_per_shot := 1

@export_group("Feedback")
@export var recoil_kick := 0.08        ## How far Visual jumps back per shot (negative = lunges forward).
@export var recoil_pitch := 0.0        ## Degrees Visual tilts up per shot (muzzle flip).
@export var recoil_recover := 12.0     ## How fast Visual returns to rest.

var holder: WeaponHolder               # Set by the WeaponHolder that owns this weapon.
var cooldown := 0.0

@onready var visual: Node3D = get_node_or_null("Visual")
var _visual_rest := Vector3.ZERO
var _visual_rest_rotation := Quaternion.IDENTITY
var _animated_models: Array[Node] = []  # Models with arm_view.gd (arm, gun slide...).


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
	if visual:
		var t := 1.0 - exp(-recoil_recover * delta)
		visual.position = visual.position.lerp(_visual_rest, t)
		visual.quaternion = visual.quaternion.slerp(_visual_rest_rotation, t)


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
		visual.position = _visual_rest + Vector3(0.0, 0.0, recoil_kick)
		# Tilt around the camera's right axis, so the muzzle flips straight up
		# no matter how Visual is turned.
		visual.quaternion = Quaternion(Vector3.RIGHT, deg_to_rad(recoil_pitch)) * _visual_rest_rotation


## Override in subclasses: what actually happens when the weapon fires.
func _fire() -> void:
	pass


func on_equipped() -> void:
	pass


func on_unequipped() -> void:
	pass


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
