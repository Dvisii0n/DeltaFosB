extends CanvasLayer
## Full-screen "DeltaFosB" filter (shaders/deltafosb.gdshader). Sits under the HUD (layer 0),
## so it changes the 3D world and the guns but never the HUD or menus.
## On by default; Settings > "DeltaFosB Filter" turns it off (GameSettings.deltafosb_filter).

@onready var rect: ColorRect = $Filter


func _ready() -> void:
	layer = 0
	GameSettings.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	visible = GameSettings.deltafosb_filter
