class_name Ability
extends Node
## Base for the player's special powers. Put a node named "Ability" on the player with a
## script that extends this one (e.g. BulletTime). To add a new power later, make a new
## script that extends Ability and fill in _on_start() / _on_stop().
##
## The bar fills from kills (add_charge). When it's full, press the "ability" key (Q).
## While active, the bar drains over `duration` seconds, then the power ends.

signal started
signal stopped

@export var power_name := "Ability"
@export var key_hint := "Q"            ## Shown on the HUD bar when ready.
@export var duration := 6.0            ## Seconds the power lasts (real time).

var _time_left := 0.0

var charge := 0.0                      # 0..1 how full the bar is.
var active := false


func is_ready() -> bool:
	return charge >= 1.0 and not active


func add_charge(amount: float) -> void:
	if active:
		return   # No charging while the power is running.
	charge = minf(charge + amount, 1.0)


func activate() -> void:
	if not is_ready():
		return
	active = true
	_time_left = duration
	_on_start()
	started.emit()


## Adds real seconds to a running power (the "kills extend bullet time" upgrade).
func extend(seconds: float) -> void:
	if active:
		_time_left = minf(_time_left + seconds, duration)


func stop() -> void:
	if not active:
		return
	active = false
	charge = 0.0
	_on_stop()
	stopped.emit()


func _process(delta: float) -> void:
	if not active:
		return
	_time_left -= WorldTime.real_delta(delta)   # Real seconds, even while time is slowed.
	charge = maxf(_time_left / duration, 0.0)   # The bar drains while active.
	if _time_left <= 0.0:
		stop()


func _exit_tree() -> void:
	stop()   # Never leave a power running when the level reloads.


## Override in the power's script.
func _on_start() -> void:
	pass


## Override in the power's script.
func _on_stop() -> void:
	pass
