extends Node3D
## Put this on an imported model (.glb) with animations: an arm, or a gun with a moving slide.
## It loops the idle animation, and plays the attack animation when the weapon fires
## (then goes back to idle). Leave idle_animation empty if the model has no idle.
## Godot names the animation after the Blender Action, minus the "_loop" ending
## ("idle_loop" in Blender becomes "idle" here, already set to loop).

@export var idle_animation := "idle"
@export var attack_animation := "stab"
@export var blend_time := 0.05        ## Seconds to smoothly blend between animations.

@onready var animation_player: AnimationPlayer = find_child("AnimationPlayer", true, false)


func _process(_delta: float) -> void:
	# Arm / gun animations always play at real speed, matching the real-time fire rate.
	if animation_player and Engine.time_scale > 0.0:
		animation_player.speed_scale = 1.0 / Engine.time_scale


func _ready() -> void:
	if animation_player and animation_player.has_animation(idle_animation):
		animation_player.play(idle_animation)


## Plays the attack from the start (even if it was already playing), then returns to idle.
func play_attack() -> void:
	if not animation_player or not animation_player.has_animation(attack_animation):
		return
	animation_player.clear_queue()
	animation_player.play(attack_animation, blend_time)
	animation_player.seek(0.0, true)  # restart if we attack again mid-stab
	if animation_player.has_animation(idle_animation):
		animation_player.queue(idle_animation)
