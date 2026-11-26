extends Control
## Placeholder HUD, bottom-left: Fury bar (orange-red), bullet time bar (yellow), armor (blue), health (red).
## The player script sets `health`, `ability` and `fury` when the game starts.

@export var bar_size := Vector2(260, 20)
@export var gap := 6.0
@export var health_color := Color(0.85, 0.15, 0.15)
@export var armor_color := Color(0.2, 0.5, 1.0)
@export var ability_color := Color(1.0, 0.8, 0.15)
@export var ability_ready_color := Color(1.0, 1.0, 0.5)
@export var fury_color := Color(1.0, 0.3, 0.1)
@export var fury_ready_color := Color(1.0, 0.7, 0.5)
@export var back_color := Color(0, 0, 0, 0.55)

var health: Health
var ability: Ability
var fury: Ability


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if health == null:
		return
	var row := bar_size.y + gap
	if fury:
		_draw_ability_bar(Vector2.ZERO, fury, fury_color, fury_ready_color)
	if ability:
		_draw_ability_bar(Vector2(0, row), ability, ability_color, ability_ready_color)
	var armor_y := row * 2.0
	var health_y := row * 3.0
	_draw_bar(Vector2(0, armor_y), health.armor, health.max_armor, armor_color, "ARMOR")
	_draw_bar(Vector2(0, health_y), health.current, health.max_health, health_color, "HP")


func _draw_bar(pos: Vector2, value: float, max_value: float, color: Color, title: String) -> void:
	var fraction := clampf(value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0
	draw_rect(Rect2(pos, bar_size), back_color)
	draw_rect(Rect2(pos, Vector2(bar_size.x * fraction, bar_size.y)), color)
	var font := get_theme_default_font()
	var text := "%s %d / %d" % [title, ceili(value), int(max_value)]
	draw_string(font, pos + Vector2(6, bar_size.y - 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)


## Power bar. Flashes when full; drains while the power is active.
func _draw_ability_bar(pos: Vector2, power: Ability, base_color: Color, ready_color: Color) -> void:
	var color := base_color
	var text := "%s %d%%" % [power.power_name.to_upper(), int(power.charge * 100.0)]
	if power.active:
		text = "%s ACTIVE" % power.power_name.to_upper()
	elif power.is_ready():
		text = "%s READY [%s]" % [power.power_name.to_upper(), power.key_hint]
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.01)
		color = base_color.lerp(ready_color, pulse)
	draw_rect(Rect2(pos, bar_size), back_color)
	draw_rect(Rect2(pos, Vector2(bar_size.x * power.charge, bar_size.y)), color)
	draw_string(get_theme_default_font(), pos + Vector2(6, bar_size.y - 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK if power.charge > 0.35 else Color.WHITE)
