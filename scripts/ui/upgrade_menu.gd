extends CanvasLayer
## Level-up screen: pauses the game and shows 3 upgrade cards. Click one (or press 1 / 2 / 3).
## If you gained several levels at once, the next set of cards appears right after.
## One free reroll per level up (button or R): swaps all 3 cards for new ones.
## Placeholder look: coloured panels, border colour = rarity (grey common, blue rare, purple epic).

@export var upgrades_path: NodePath = ^"../Upgrades"
@export var card_size := Vector2(280, 240)
@export var mouse_park_height := 0.92  ## Where the mouse goes when the screen opens (0 = top, 1 = bottom).

var _upgrades: Upgrades
var _choices: Array[Dictionary] = []
var _title: Label
var _cards: HBoxContainer
var _reroll_button: Button
var _reroll_used := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # Works while the game is paused.
	layer = 20
	_build()
	hide()
	_upgrades = get_node(upgrades_path) as Upgrades
	_upgrades.leveled_up.connect(func(_level): _open_if_needed.call_deferred())


func _open_if_needed() -> void:
	if visible or _upgrades.pending_levels <= 0:
		return
	_choices = _upgrades.roll_choices(3)
	if _choices.is_empty():   # Everything maxed out.
		_upgrades.pending_levels = 0
		return
	_title.text = "LEVEL UP!  Level %d - choose an upgrade" % (_upgrades.level - _upgrades.pending_levels + 1)
	_reroll_used = false
	_show_cards()
	show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_park_mouse.call_deferred()


## Puts the mouse below the cards, so a click (or release) left over from shooting
## can't land on one. The captured mouse sits in the middle = right on the centre card.
func _park_mouse() -> void:
	var view := get_viewport().get_visible_rect().size
	Input.warp_mouse(Vector2(view.x * 0.5, view.y * mouse_park_height))


func _show_cards() -> void:
	for child in _cards.get_children():
		child.queue_free()
	for i in _choices.size():
		_cards.add_child(_make_card(_choices[i], i))
	_reroll_button.disabled = _reroll_used
	_reroll_button.text = "Reroll used" if _reroll_used else "Reroll  [R]  (1 left)"


## Swaps the cards for a new set. Once per level up.
func _reroll() -> void:
	if not visible or _reroll_used:
		return
	var fresh := _upgrades.roll_choices(3)
	if fresh.is_empty():
		return
	_reroll_used = true
	_choices = fresh
	_show_cards()


func _choose(index: int) -> void:
	if not visible or index >= _choices.size():
		return
	_upgrades.pick(_choices[index])
	hide()
	if _upgrades.pending_levels > 0:
		_open_if_needed()      # Another level is waiting.
		return
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	for i in 3:
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			_choose(i)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		_reroll()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()   # Must pick before pausing.


# --- Building the UI in code (placeholder) ----------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	center.add_child(column)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 36)
	column.add_child(_title)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 20)
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_cards)
	_reroll_button = Button.new()
	_reroll_button.custom_minimum_size = Vector2(260, 44)
	_reroll_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_reroll_button.focus_mode = Control.FOCUS_NONE
	_reroll_button.add_theme_font_size_override("font_size", 20)
	_reroll_button.pressed.connect(_reroll)
	column.add_child(_reroll_button)
	var hint := Label.new()
	hint.text = "Click a card or press 1 / 2 / 3"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)


func _make_card(up: Dictionary, index: int) -> Button:
	var color: Color = UpgradeList.RARITY_COLORS[up.rarity]
	var button := Button.new()
	button.custom_minimum_size = card_size
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.12, 0.12, 0.14) if state == "normal" else Color(0.2, 0.2, 0.24)
		box.border_color = color
		box.set_border_width_all(4 if state == "normal" else 6)
		box.set_corner_radius_all(8)
		button.add_theme_stylebox_override(state, box)
	button.pressed.connect(_choose.bind(index))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	button.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	column.add_child(_label("[%d]  %s" % [index + 1, UpgradeList.RARITY_NAMES[up.rarity].to_upper()], 14, color))
	column.add_child(_label(up.title, 24, Color.WHITE))
	var body := _label(_upgrades.describe(up), 16, Color(0.85, 0.85, 0.85))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	return button


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
