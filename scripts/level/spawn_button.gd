extends StaticBody3D
## Test button: look at it and press E (the "interact" action) to spawn an enemy.

@export var enemy_scene: PackedScene
@export var spawn_point: NodePath      ## A Marker3D where the enemy appears.
@export var label_text := "Spawn"
@export var color := Color.WHITE       ## Matches the enemy's placeholder colour.

@onready var visual: MeshInstance3D = $Visual
@onready var label: Label3D = $Label3D

var _press_tween: Tween


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	visual.material_override = mat
	label.text = "[E] %s" % label_text


func press() -> void:
	if enemy_scene == null:
		return
	var marker := get_node_or_null(spawn_point) as Node3D
	var enemy := enemy_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = marker.global_position if marker else global_position + global_basis.z * 2.0
	_push_feedback()


## Little "pushed in" animation.
func _push_feedback() -> void:
	if _press_tween:
		_press_tween.kill()
	visual.position.z = -0.06
	_press_tween = create_tween()
	_press_tween.tween_property(visual, "position:z", 0.0, 0.15)
