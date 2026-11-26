extends Control
## Draws the crosshair in the middle of the screen.
## Each weapon picks its look with its "crosshair" setting (Weapon.CrosshairStyle):
## - CROSS:  a small "+"
## - CIRCLE: a ring as wide as the weapon's pellet spread (shotgun), so pellets land inside it.
## The player script sets `weapon` and `camera` every frame.

@export var color := Color.WHITE
@export var thickness := 2.0
@export var cross_size := 7.0          ## Half-length of the "+" arms, in pixels.
@export var min_circle_radius := 8.0   ## The ring never gets smaller than this (pixels).

var weapon: Weapon
var camera: Camera3D


func _process(_delta: float) -> void:
	queue_redraw()  # redraw every frame: the ring follows FOV changes


func _draw() -> void:
	var center := size / 2.0
	if weapon and weapon.crosshair == Weapon.CrosshairStyle.CIRCLE:
		draw_arc(center, _circle_radius(), 0.0, TAU, 40, color, thickness, true)
	else:
		draw_line(center - Vector2(cross_size, 0), center + Vector2(cross_size, 0), color, thickness)
		draw_line(center - Vector2(0, cross_size), center + Vector2(0, cross_size), color, thickness)


## How many pixels the weapon's spread cone covers on screen.
func _circle_radius() -> float:
	var spread: float = weapon.effective_spread()
	if camera == null or spread <= 0.0:
		return min_circle_radius
	var half_height := get_viewport_rect().size.y / 2.0
	var r := tan(deg_to_rad(spread)) / tan(deg_to_rad(camera.fov / 2.0)) * half_height
	return maxf(r, min_circle_radius)
