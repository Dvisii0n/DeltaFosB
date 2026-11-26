extends Control
## Blood splattered on the player's "screen". Splats only land around the edges and corners:
## an oval in the middle (center_clear) is always kept clean so you can see what you're aiming at.
## They hold for a moment, then fade while dripping down a little.
## Called through player.splash_screen(intensity): when you get hurt, or when gore happens right next to you.

@export var center_clear := 0.6        ## 0..1: how much of the middle stays clean (0.6 = inner 60% of the screen).
@export var max_splats := 40           ## Never more blobs than this on screen at once.
@export var hold_time := 1.0           ## Seconds a splat stays fully visible...
@export var fade_time := 1.6           ## ...then seconds to fade out.
@export var drip_distance := 40.0      ## Pixels a splat slides down while fading.
@export var color := Color(0.6, 0.0, 0.02, 0.85)

var _texture: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## intensity 1 = a normal splash (a few splats). Bigger = more and larger.
func splash(intensity: float) -> void:
	if intensity <= 0.0:
		return
	var count := clampi(int(1 + intensity * 2.5), 1, 8)
	for i in count:
		if get_child_count() >= max_splats:
			return
		_splat(clampf(intensity, 0.5, 3.0))


func _splat(strength: float) -> void:
	# Somewhere in the ring between the clear centre and the screen edge.
	var angle := randf() * TAU
	var radius := randf_range(center_clear + 0.12, 1.05)
	var centre := size * 0.5
	var pos := centre + Vector2(cos(angle) * radius * centre.x, sin(angle) * radius * centre.y)
	var main_size := randf_range(70.0, 150.0) * sqrt(strength)

	var splat := Control.new()
	splat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	splat.position = pos
	add_child(splat)
	# One big blob and a few droplets around it.
	_blob(splat, Vector2.ZERO, main_size)
	var outward := Vector2(cos(angle), sin(angle))   # Droplets fly away from the centre, never into it.
	for i in randi_range(3, 7):
		var off := outward.rotated(randf_range(-1.3, 1.3)) * main_size * randf_range(0.5, 1.1)
		_blob(splat, off, main_size * randf_range(0.12, 0.35))

	var tween := splat.create_tween()
	tween.tween_interval(hold_time)
	tween.tween_property(splat, "modulate:a", 0.0, fade_time)
	tween.parallel().tween_property(splat, "position:y", pos.y + drip_distance, fade_time)
	tween.tween_callback(splat.queue_free)


func _blob(parent: Control, offset: Vector2, diameter: float) -> void:
	var rect := TextureRect.new()
	rect.texture = _blob_texture()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Slightly squashed and rotated so blobs aren't perfect circles.
	rect.size = Vector2(diameter, diameter * randf_range(0.7, 1.0))
	rect.pivot_offset = rect.size * 0.5
	rect.rotation = randf() * TAU
	rect.position = offset - rect.size * 0.5
	rect.modulate = Color(color.r * randf_range(0.8, 1.1), color.g, color.b, color.a)
	parent.add_child(rect)


func _blob_texture() -> GradientTexture2D:
	if _texture == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.6, Color(1, 1, 1, 0.9))
		_texture = GradientTexture2D.new()
		_texture.gradient = g
		_texture.fill = GradientTexture2D.FILL_RADIAL
		_texture.fill_from = Vector2(0.5, 0.5)
		_texture.fill_to = Vector2(1.0, 0.5)
		_texture.width = 64
		_texture.height = 64
	return _texture
