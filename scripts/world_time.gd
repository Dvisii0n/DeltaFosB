class_name WorldTime
extends Object
## Slow motion helpers, usable from any script as `WorldTime.something` (no node needed).
##
## Bullet time slows the WHOLE game with Engine.time_scale (0.25 = quarter speed),
## the player included. Every `delta` Godot hands out is already slowed down.
##
## The Sandevistan upgrade makes the player ignore it: player scripts multiply their
## delta by player_time_mult(), so they keep running at real speed while the world crawls.

static var sandevistan := false        ## Set by the Sandevistan upgrade.


## Slows (or restores) the whole game. 1.0 = normal speed.
static func set_world_speed(speed: float) -> void:
	Engine.time_scale = speed


static func world_speed() -> float:
	return Engine.time_scale


## How much faster than the world the player runs: 1 normally, 4 during bullet time with Sandevistan.
static func player_time_mult() -> float:
	if sandevistan and Engine.time_scale > 0.0:
		return 1.0 / Engine.time_scale
	return 1.0


## Turns a slowed-down delta back into real seconds (for timers that should ignore bullet time).
static func real_delta(delta: float) -> float:
	return delta / Engine.time_scale if Engine.time_scale > 0.0 else delta
