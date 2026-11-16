class_name Health
extends Node
## Reusable health component. Add a node named "Health" with this script to anything
## that should take damage (dummies now, enemies later). Weapons look for it by name.

signal damaged(amount: float, current: float)
signal died

@export var max_health := 100.0

var current: float
var is_dead := false


func _ready() -> void:
	current = max_health


func take_damage(amount: float) -> void:
	if is_dead:
		return
	current = maxf(current - amount, 0.0)
	damaged.emit(amount, current)
	if current <= 0.0:
		is_dead = true
		died.emit()


func reset() -> void:
	current = max_health
	is_dead = false
