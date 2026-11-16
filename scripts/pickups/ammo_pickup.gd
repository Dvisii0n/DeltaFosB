extends Area3D
## Ammo dropped by defeated enemies. Touch it to collect. Disappears if ignored too long,
## so the player is pushed to keep fighting.

@export var ammo := {"light": 8, "shells": 2, "heavy": 40}
@export var lifetime := 20.0
@export var spin_speed := 2.0
@export var bob_height := 0.15

@onready var visual: Node3D = get_node_or_null("Visual")

var _age := 0.0
var _visual_base_y := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if visual:
		_visual_base_y = visual.position.y


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	if visual:
		visual.rotate_y(spin_speed * delta)
		visual.position.y = _visual_base_y + sin(_age * 3.0) * bob_height


func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("add_ammo"):
		return
	for type in ammo:
		body.add_ammo(type, ammo[type])
	queue_free()
