extends CanvasLayer
## Placeholder pause menu. Press Esc to open or close it.
## While it's open the whole game is paused. This node keeps running anyway
## because its Process Mode is set to "Always" (see the Inspector).

@export var min_fov := 60.0   ## Lowest value on the FOV slider.
@export var max_fov := 120.0  ## Highest value on the FOV slider.

@onready var main_page: Control = $Center/Main
@onready var settings_page: Control = $Center/Settings
@onready var resume_button: Button = $Center/Main/ResumeButton
@onready var settings_button: Button = $Center/Main/SettingsButton
@onready var quit_button: Button = $Center/Main/QuitButton
@onready var back_button: Button = $Center/Settings/BackButton
@onready var fov_slider: HSlider = $Center/Settings/FovRow/FovSlider
@onready var fov_value: Label = $Center/Settings/FovRow/FovValue
@onready var dual_wield_check: CheckBox = $Center/Settings/DualWieldCheck
@onready var health_bars_check: CheckBox = $Center/Settings/HealthBarsCheck
@onready var armor_bars_check: CheckBox = $Center/Settings/ArmorBarsCheck
@onready var fullscreen_check: CheckBox = $Center/Settings/FullscreenCheck
@onready var filter_check: CheckBox = $Center/Settings/FilterCheck


func _ready() -> void:
	hide()
	resume_button.pressed.connect(close)
	settings_button.pressed.connect(_show_settings)
	quit_button.pressed.connect(_quit)
	back_button.pressed.connect(_show_main)
	fov_slider.min_value = min_fov
	fov_slider.max_value = max_fov
	fov_slider.value_changed.connect(_on_fov_changed)
	dual_wield_check.toggled.connect(_on_dual_wield_toggled)
	health_bars_check.toggled.connect(func(on: bool): GameSettings.show_health_bars = on)
	armor_bars_check.toggled.connect(func(on: bool): GameSettings.show_armor_bars = on)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	filter_check.toggled.connect(func(on: bool): GameSettings.deltafosb_filter = on)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if get_tree().paused and not visible:
		return   # Something else paused the game (the level-up screen).
	if not visible:
		open()
	elif settings_page.visible:
		_show_main()  # Esc in Settings goes back one page.
	else:
		close()
	get_viewport().set_input_as_handled()


func open() -> void:
	# Start the slider at the player's current FOV.
	var player = _player()
	if player:
		fov_slider.set_value_no_signal(player.base_fov)
	fov_value.text = str(int(fov_slider.value))
	var holder := _weapon_holder()
	if holder:
		dual_wield_check.set_pressed_no_signal(holder.dual_wield)
	health_bars_check.set_pressed_no_signal(GameSettings.show_health_bars)
	armor_bars_check.set_pressed_no_signal(GameSettings.show_armor_bars)
	filter_check.set_pressed_no_signal(GameSettings.deltafosb_filter)
	fullscreen_check.set_pressed_no_signal(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)

	show()
	_show_main()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_main() -> void:
	settings_page.hide()
	main_page.show()
	resume_button.grab_focus()


func _show_settings() -> void:
	main_page.hide()
	settings_page.show()
	fov_slider.grab_focus()


func _on_fov_changed(value: float) -> void:
	fov_value.text = str(int(value))
	var player = _player()
	if player:
		player.set_base_fov(value)


func _on_dual_wield_toggled(on: bool) -> void:
	var holder := _weapon_holder()
	if holder:
		holder.dual_wield = on


## Borderless "windowed fullscreen" (covers the screen, alt-tab friendly). Off = the normal window
## at the project's default size.
func _on_fullscreen_toggled(on: bool) -> void:
	if on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _quit() -> void:
	get_tree().quit()


func _player() -> Node:
	return get_tree().get_first_node_in_group("player")


func _weapon_holder() -> WeaponHolder:
	var player = _player()
	return player.find_child("WeaponHolder", true, false) as WeaponHolder if player else null
