class_name Health
extends Node
## Reusable health component. Add a node named "Health" with this script to anything
## that should take damage (dummies, enemies, the player). Weapons look for it by name.
##
## Armor: while armor is left, it soaks up `armor_absorb` of every hit (0.75 = 75%)
## and only the rest reaches health. When armor runs out, health takes full damage.

signal damaged(amount: float, current: float)
signal armor_changed(current_armor: float)
signal died

@export var max_health := 100.0
@export var max_armor := 0.0                        ## 0 = no armor.
@export_range(0.0, 1.0) var armor_absorb := 0.75   ## Share of each hit the armor takes.
@export var start_with_full_armor := true          ## false = starts at 0 armor (the player picks it up).

var current: float
var armor: float
var is_dead := false
var last_stands := 0                   # "Last Stand" upgrade: survive this many lethal hits with 1 HP.


func _ready() -> void:
	current = max_health
	armor = max_armor if start_with_full_armor else 0.0


func take_damage(amount: float) -> void:
	if is_dead:
		return
	var to_health := amount
	if armor > 0.0:
		var absorbed := minf(amount * armor_absorb, armor)
		armor -= absorbed
		to_health -= absorbed
		armor_changed.emit(armor)
	current = maxf(current - to_health, 0.0)
	if current <= 0.0 and last_stands > 0:
		last_stands -= 1
		current = 1.0
	damaged.emit(amount, current)
	if current <= 0.0:
		is_dead = true
		died.emit()


func reset() -> void:
	current = max_health
	armor = max_armor if start_with_full_armor else 0.0
	is_dead = false
	armor_changed.emit(armor)


## Restores health up to max_health. Returns how much was actually healed.
func heal(amount: float) -> float:
	if is_dead:
		return 0.0
	var before := current
	current = minf(current + amount, max_health)
	return current - before


## Adds armor up to max_armor. Returns how much was actually added.
func add_armor(amount: float) -> float:
	var before := armor
	armor = minf(armor + amount, max_armor)
	armor_changed.emit(armor)
	return armor - before
