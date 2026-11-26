extends Control
## Placeholder XP bar along the bottom-centre of the screen: level number and XP progress.
## The player script sets `upgrades` when the game starts.

@export var bar_size := Vector2(420, 12)
@export var fill_color := Color(0.35, 0.95, 0.45)
@export var back_color := Color(0, 0, 0, 0.55)

var upgrades: Upgrades


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if upgrades == null:
		return
	var pos := Vector2((size.x - bar_size.x) * 0.5, size.y - bar_size.y)
	var fraction := clampf(upgrades.xp / upgrades.xp_needed, 0.0, 1.0)
	draw_rect(Rect2(pos, bar_size), back_color)
	draw_rect(Rect2(pos, Vector2(bar_size.x * fraction, bar_size.y)), fill_color)
	var text := "LV %d     %d / %d XP" % [upgrades.level, int(upgrades.xp), int(upgrades.xp_needed)]
	var font := get_theme_default_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(font, Vector2((size.x - width) * 0.5, pos.y - 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
