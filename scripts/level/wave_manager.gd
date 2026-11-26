extends Node
## Endless enemy waves. Call toggle() (the "Start Waves" button does) to start or stop.
##
## Each wave spawns more enemies than the last, and stronger enemy types get more likely:
##   enemy count  = base_count + (wave - 1) * count_per_wave   (capped at max_count)
##   type weight  = start_weight + (wave - 1) * weight_per_wave   (bigger weight = more likely)
## The next wave starts `break_time` seconds after every enemy of the current wave is dead.

signal wave_started(wave: int, count: int)

## Enemy types, weakest first. The weight arrays below follow this order.
@export var enemy_scenes: Array[PackedScene] = [
	preload("res://scenes/enemies/office_worker.tscn"),
	preload("res://scenes/enemies/security_guard.tscn"),
	preload("res://scenes/enemies/vest_guard.tscn"),
	preload("res://scenes/enemies/security_head.tscn"),
]
@export var start_weights: Array[float] = [10.0, 3.0, 0.0, 0.0]     ## Wave 1: only workers and a few guards.
@export var weight_per_wave: Array[float] = [0.0, 1.0, 0.8, 0.4]   ## Added every wave: stronger types catch up.

@export var base_count := 3            ## Enemies in wave 1.
@export var count_per_wave := 2.0      ## Extra enemies each wave.
@export var max_count := 30            ## Never more than this in one wave.
@export var spawn_interval := 0.5      ## Seconds between each enemy appearing.
@export var break_time := 4.0          ## Seconds of rest between waves.
@export var min_spawn_distance := 10.0 ## Don't spawn closer than this to the player.
@export var spawn_points_path: NodePath ## A node whose Marker3D children are the wave spawn spots.

@export_group("Difficulty")
@export var health_per_wave := 0.06    ## +6% enemy health and armor every wave after the first.
@export var damage_per_wave := 0.06    ## +6% enemy damage every wave after the first.
@export var speed_per_wave := 0.04     ## +4% enemy movement speed every wave after the first...
@export var max_speed_bonus := 0.6     ## ...but never more than +60%.

var running := false
var wave := 0

var _alive: Array[Node] = []
var _to_spawn := 0
var _spawn_timer := 0.0
var _break_timer := 0.0
var _label: Label


func _ready() -> void:
	# Simple on-screen text, top-centre.
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_label.position.y = 16
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(_label)
	_update_label()


func toggle() -> void:
	if running:
		stop()
	else:
		start()


func start() -> void:
	running = true
	wave = 0
	_break_timer = 1.0   # Short moment before wave 1.


func stop() -> void:
	running = false
	_to_spawn = 0
	for e in _alive:
		if is_instance_valid(e):
			e.queue_free()
	_alive.clear()
	_update_label()


func _physics_process(delta: float) -> void:
	if not running:
		return
	_alive = _alive.filter(func(e): return is_instance_valid(e))

	if _to_spawn > 0:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = spawn_interval
			_spawn_one()
	elif _alive.is_empty():
		_break_timer -= delta
		if _break_timer <= 0.0:
			_start_next_wave()
	_update_label()


func _start_next_wave() -> void:
	wave += 1
	_to_spawn = mini(base_count + int((wave - 1) * count_per_wave), max_count)
	_spawn_timer = 0.0
	_break_timer = break_time
	wave_started.emit(wave, _to_spawn)


func _spawn_one() -> void:
	_to_spawn -= 1
	var scene := _pick_enemy()
	var point := _pick_spawn_point()
	if scene == null or point == null:
		return
	var enemy := scene.instantiate() as Node3D
	get_tree().current_scene.add_child(enemy)
	var jitter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	enemy.global_position = point.global_position + jitter
	if enemy.has_method("scale_strength"):
		enemy.scale_strength(health_mult(), damage_mult(), speed_mult())   # Later waves = tougher enemies.
	if enemy.has_method("alert"):
		enemy.alert()   # Wave enemies know where you are right away.
	_alive.append(enemy)


func health_mult() -> float:
	return 1.0 + health_per_wave * (wave - 1)


func damage_mult() -> float:
	return 1.0 + damage_per_wave * (wave - 1)


func speed_mult() -> float:
	return 1.0 + minf(speed_per_wave * (wave - 1), max_speed_bonus)


## Weighted random pick: the higher a type's weight this wave, the more likely it is.
func _pick_enemy() -> PackedScene:
	var weights: Array[float] = []
	var total := 0.0
	for i in enemy_scenes.size():
		var w := _weight(i)
		weights.append(w)
		total += w
	if total <= 0.0:
		return null
	var roll := randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			return enemy_scenes[i]
	return enemy_scenes.back()


func _weight(index: int) -> float:
	var start: float = start_weights[index] if index < start_weights.size() else 0.0
	var growth: float = weight_per_wave[index] if index < weight_per_wave.size() else 0.0
	return maxf(start + (wave - 1) * growth, 0.0)


## A random spawn spot that isn't right next to the player.
func _pick_spawn_point() -> Node3D:
	var holder := get_node_or_null(spawn_points_path)
	if holder == null:
		return null
	var points: Array[Node3D] = []
	for c in holder.get_children():
		if c is Node3D:
			points.append(c)
	if points.is_empty():
		return null
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		var far := points.filter(func(p): return p.global_position.distance_to(player.global_position) >= min_spawn_distance)
		if not far.is_empty():
			points.assign(far)
	return points.pick_random()


func _update_label() -> void:
	if _label == null:
		return
	if not running:
		_label.text = ""
	elif wave == 0 or (_to_spawn == 0 and _alive.is_empty()):
		_label.text = "WAVE %d CLEARED - next wave in %d" % [wave, ceili(_break_timer)] if wave > 0 else "GET READY"
	else:
		_label.text = "WAVE %d  |  enemies left: %d" % [wave, _alive.size() + _to_spawn]
		if wave > 1:
			_label.text += "\nenemies: +%d%% health  +%d%% damage  +%d%% speed" % [roundi((health_mult() - 1.0) * 100.0), roundi((damage_mult() - 1.0) * 100.0), roundi((speed_mult() - 1.0) * 100.0)]
