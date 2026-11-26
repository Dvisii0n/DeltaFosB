extends Node3D
## Floating health (red) and armor (blue) bars above an enemy. Always turns to face the camera.
## Each one can be switched off in Settings (GameSettings.show_health_bars / show_armor_bars).
## Reads the "Health" node next to it.

@export var width := 1.0
@export var height := 0.1
@export var gap := 0.04                ## Space between the two bars.
@export var health_color := Color(0.9, 0.15, 0.15)
@export var armor_color := Color(0.2, 0.5, 1.0)
@export var back_color := Color(0.05, 0.05, 0.05)

var _health: Health
var _health_row: Node3D
var _health_fill: MeshInstance3D
var _armor_row: Node3D
var _armor_fill: MeshInstance3D


func _ready() -> void:
	_health = get_parent().get_node("Health") as Health
	_health_row = _make_row(0.0, health_color)
	_health_fill = _health_row.get_child(1)
	_armor_row = _make_row(height + gap, armor_color)
	_armor_fill = _armor_row.get_child(1)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(global_position) > 0.01:
		look_at(cam.global_position, Vector3.UP, true)   # true = our front (+Z) faces the camera.

	_health_row.visible = GameSettings.show_health_bars
	_armor_row.visible = GameSettings.show_armor_bars and _health.max_armor > 0.0
	_set_fill(_health_fill, _health.current / _health.max_health)
	if _health.max_armor > 0.0:
		_set_fill(_armor_fill, _health.armor / _health.max_armor)


## Shrinks the coloured part from the right, keeping it lined up on the left edge.
func _set_fill(fill: MeshInstance3D, fraction: float) -> void:
	fraction = clampf(fraction, 0.0, 1.0)
	fill.visible = fraction > 0.0
	fill.scale.x = maxf(fraction, 0.001)
	fill.position.x = -width * 0.5 * (1.0 - fraction)


func _make_row(y: float, color: Color) -> Node3D:
	var row := Node3D.new()
	row.position.y = y
	add_child(row)
	row.add_child(_make_quad(back_color, 0.0))
	row.add_child(_make_quad(color, 0.005))   # Slightly in front of the background.
	return row


func _make_quad(color: Color, z: float) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.position.z = z
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
