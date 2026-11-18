## One splat asset placed in a 3D scene, drawn by the [SplatScene] that has it under its
## [member SplatScene.instances_root]. Its transform places the asset's own space (ink-studio's:
## metres, Y up), so it is moved, turned, scaled and hidden like any node.
# In Unity, this is the SplatInstance MonoBehaviour with a TextAsset; Godot has no TextAsset, so the
# asset is a path to the .bytes file, read once and shared.
class_name SplatInstance
extends Node3D


# region State
## Bumped whenever an instance appears, goes, hides or changes its asset, so scenes gather again.
static var version: int = 0

static var _clips: Dictionary[String, SplatClip] = {}

## The TCRS file to draw. Files that end in .bytes are not resources: an export preset must list
## [code]*.bytes[/code] under "Filters to export non-resource files".
@export_file("*.bytes") var asset: String = "":
	set(value):
		asset = value
		_clip = null
		version += 1

## Clips only: seconds added to the clock, so avatars don't move in step.
@export var time_offset: float = 0.0

## Clips only: hold the clip's first frame.
@export var frozen: bool = false

## Metres nearer the camera this instance is depth-tested than it is. For a thin thing lying on a
## surface (a rug, a poster), which the surface's own splats would otherwise hatch through.
@export var depth_bias: float = 0.0

var _clip: SplatClip = null
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


# region Queries
## What is drawn, or [code]null[/code] when the asset is missing or cannot be read.
func get_clip() -> SplatClip:
	if _clip == null and not asset.is_empty():
		_clip = load_shared(asset)
	return _clip


## The frame to show at [param seconds] on the scene's clock.
func frame_at(seconds: float) -> int:
	var clip: SplatClip = get_clip()
	if clip == null or frozen:
		return 0
	return clip.frame_at(seconds + time_offset)


## Reads a file once and hands every instance of it the same [SplatClip].
static func load_shared(path: String) -> SplatClip:
	if _clips.has(path):
		return _clips[path]
	var clip: SplatClip = SplatClip.load_file(path)
	if clip == null:
		push_error("[SplatInstance] %s" % SplatClip.last_error)
	_clips[path] = clip
	return clip
# endregion
