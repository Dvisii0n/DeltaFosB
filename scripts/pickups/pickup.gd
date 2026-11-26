class_name Pickup
extends Area3D
## Base for every pickup (ammo, armor, power-ups). Spins and bobs, and is collected by touching it.
## Subclasses only override _collect(body): return true if it was used (then it disappears).

@export var lifetime := 20.0           ## Seconds before it vanishes if ignored. 0 = stays forever.
@export var respawn_time := 0.0        ## 0 = gone for good once taken. Otherwise comes back after this many seconds.
@export var spin_speed := 2.0
@export var bob_height := 0.15

@onready var visual: Node3D = get_node_or_null("Visual")

var _age := 0.0
var _visual_base_y := 0.0
var _taken := false


func _ready() -> void:
	add_to_group("pickups")   # The Pickup Magnet upgrade looks for this group.
	body_entered.connect(_on_body_entered)
	# "Long Shelf Life" upgrade: dropped pickups stay longer.
	var player := get_tree().get_first_node_in_group("player")
	var ups = player.get_node_or_null("Upgrades") if player else null
	if ups and lifetime > 0.0:
		lifetime += ups.pickup_lifetime_bonus
	if visual:
		_visual_base_y = visual.position.y


func _process(delta: float) -> void:
	_age += delta
	if lifetime > 0.0 and _age >= lifetime and not _taken:
		queue_free()
		return
	if visual:
		visual.rotate_y(spin_speed * delta)
		visual.position.y = _visual_base_y + sin(_age * 3.0) * bob_height


## Override this. Return true if the pickup was used up.
func _collect(_body: Node3D) -> bool:
	return false


func _on_body_entered(body: Node3D) -> void:
	if _taken or not _collect(body):
		return
	if respawn_time <= 0.0:
		queue_free()
		return
	# Hide, then come back later.
	_taken = true
	visible = false
	set_deferred("monitoring", false)
	await get_tree().create_timer(respawn_time, false).timeout
	_taken = false
	visible = true
	monitoring = true
