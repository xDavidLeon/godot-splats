## A light for splats: the [SplatScene] that has it under its [member SplatScene.instances_root]
## lifts the splats near it and facing it along the ramp each was shaded on ([SplatLight]). Move it,
## hide it or retune it like any node; none of that makes the scene gather again or costs the CPU
## anything. It is not a Godot light: nothing but the splat picture reads it, it casts no shadow and
## nothing blocks it.
##
## A lamp shows at dusk more than by day: daylight already puts floors and walls at the top of their
## ramps, where there is no lighter step to take.
# In Unity, this is the SplatLamp MonoBehaviour, and moving one rebuilt the scene's buffers.
class_name SplatLamp
extends Node3D


# region State
## Bumped whenever a lamp appears, goes or hides, so scenes look for lamps again.
static var version: int = 0

## How far its light reaches, in metres.
@export_range(0.5, 8.0, 0.1, "or_greater") var radius: float = 3.0

## What it adds right next to it, where 1 is a splat's whole ramp from darkest to lightest.
@export_range(0.0, 1.5, 0.05, "or_greater") var strength: float = 0.9
# endregion


# region Lifecycle
func _enter_tree() -> void:
	version += 1


func _exit_tree() -> void:
	version += 1


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		version += 1
# endregion
