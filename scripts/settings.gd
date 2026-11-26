extends Node
## Global game settings, reachable from any script as `GameSettings`
## (registered as an Autoload in Project Settings > Globals).

signal changed

var show_health_bars := true:
	set(value):
		show_health_bars = value
		changed.emit()

var deltafosb_filter := true:      ## The full-screen DeltaFosB look (on by default).
	set(value):
		deltafosb_filter = value
		changed.emit()

var show_armor_bars := true:
	set(value):
		show_armor_bars = value
		changed.emit()
