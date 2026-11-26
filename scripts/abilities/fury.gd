class_name Fury
extends Ability
## Fury: fills up on its own over time (not from kills). Press E (when not looking at a button)
## to see red: double damage and faster fire rate, multiplied ON TOP of your upgrades.
## Upgrades: longer duration, and the epic "dual wield during Fury".

@export var fill_time := 40.0          ## Seconds for the bar to fill from empty.
@export var damage_mult := 2.0         ## x2 damage while active.
@export var fire_rate_mult := 1.5      ## +50% fire rate while active (stacks with upgrades).
@export_range(0.0, 1.0) var ammo_refill := 0.5  ## Activating Fury adds this share of each ammo type's max (0.5 = half).

var dual_wield_on_fury := false        # Set by the "Dual Wield Fury" upgrade.


func _process(delta: float) -> void:
	if not active:
		charge = minf(charge + delta / fill_time, 1.0)
	super(delta)


func add_charge(_amount: float) -> void:
	pass   # Fury only fills over time.


func _on_start() -> void:
	var holder := _holder()
	if holder:
		holder.fury_damage_mult = damage_mult
		holder.fury_fire_rate_mult = fire_rate_mult
		if ammo_refill > 0.0:
			holder.refill_ammo(ammo_refill)
		if dual_wield_on_fury:
			holder.give_dual_wield(duration)


func _on_stop() -> void:
	var holder := _holder()
	if holder:
		holder.fury_damage_mult = 1.0
		holder.fury_fire_rate_mult = 1.0


func _holder() -> WeaponHolder:
	var player := get_parent()
	if not is_instance_valid(player):
		return null
	return player.find_child("WeaponHolder", true, false) as WeaponHolder
