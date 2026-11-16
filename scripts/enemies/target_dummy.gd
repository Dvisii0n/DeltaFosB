extends StaticBody3D
## Practice target: takes damage, "dies", drops ammo, then respawns.

@export var respawn_time := 3.0
@export var ammo_drop_scene: PackedScene   ## What it drops on death.
@export var hit_punch := 1.15              ## Visual briefly scales up when hit.

@onready var health: Health = $Health
@onready var visual: Node3D = $Visual
@onready var collision: CollisionShape3D = $CollisionShape3D

var _hit_tween: Tween


func _ready() -> void:
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)


func _on_damaged(_amount: float, _current: float) -> void:
	# Scale "punch" works with any model you swap in, unlike a color flash.
	if _hit_tween:
		_hit_tween.kill()
	visual.scale = Vector3.ONE * hit_punch
	_hit_tween = create_tween()
	_hit_tween.tween_property(visual, "scale", Vector3.ONE, 0.12)


func _on_died() -> void:
	visual.visible = false
	collision.set_deferred("disabled", true)
	if ammo_drop_scene:
		var drop := ammo_drop_scene.instantiate() as Node3D
		get_parent().add_child.call_deferred(drop)
		drop.position = position + Vector3.UP * 0.2

	await get_tree().create_timer(respawn_time, false, true).timeout
	health.reset()
	visual.visible = true
	collision.set_deferred("disabled", false)
