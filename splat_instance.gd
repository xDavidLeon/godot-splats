## One splat asset placed in a 3D scene, drawn by the [SplatScene] that has it under its
## [member SplatScene.instances_root]. Its transform places the asset's own space (ink-studio's:
## metres, Y up), so it is moved, turned, scaled and hidden like any node.
##
## [b]A wardrobe.[/b] An asset that holds one ([method SplatClip.has_look]) holds every piece whole.
## [method wear] says which pieces this instance shows and which colours each region takes; until it
## is called every piece is drawn at once, in the file's own colours.
##
## [b]Clips.[/b] An asset may hold several named clips on its one rig ([member SplatClip.takes]).
## [method play] picks one, and [method cross_fade] shows two mixed, bone by bone. The instance keeps
## no clock and no fade of its own: whoever calls decides when a change of clip starts, how long it
## takes and how it eases, and hands in the weight.
##
## [b]Particles.[/b] With a [member motion] the asset is a cloud: steam, flames, dust. Each of its
## splats moves by itself in the shader, on the scene's clock. A cloud's file is an ordinary prop:
## where the particles start and what colour they are. Turn [member casts_shadow] off for one.
##
## [b]A tint.[/b] With [member tinted] it is drawn in one colour, [member tint], shaded by how light
## each of its splats is, on every other art pixel, so what is behind it shows through.
# In Unity, this is the SplatInstance MonoBehaviour with a TextAsset; Godot has no TextAsset, so the
# asset is a path to the .bytes file, read once and shared. Unity's instance made a new clip of the
# shown splats for every look and timed its own fades (0.3 s, eased). Unity's tint was one number,
# 0xRRGGBB with 0 for none, so it had no black.
class_name SplatInstance
extends Node3D


# region State
## How the splats of a particle cloud move ([member motion]).
enum Motion {
	## It is not a cloud: its splats stay where the asset and its bones put them.
	NONE,
	## Steam and flames: each splat climbs [member motion_reach] on a loop of its own length,
	## wobbling up to [member motion_wobble] and shrinking, and is gone at both ends.
	RISE,
	## Dust: each splat wanders [member motion_reach] round where it starts, in view for half of a
	## slower cycle.
	DRIFT,
}

## Bumped whenever an instance appears, goes, hides or changes its asset, so scenes gather again.
static var version: int = 0

static var _clips: Dictionary[String, SplatClip] = {}

## The TCRS file to draw. Files that end in .bytes are not resources: an export preset must list
## [code]*.bytes[/code] under "Filters to export non-resource files".
@export_file("*.bytes") var asset: String = "":
	set(value):
		asset = value
		_clip = null
		_look_palette = PackedInt32Array()
		version += 1

## Clips only: which of the file's clips plays, by name. Empty, or a name the file does not have:
## the file's first.
@export var clip_name: String = ""

## Clips only: seconds added to the clock, so avatars don't move in step.
@export var time_offset: float = 0.0

## Clips only: hold the clip's first frame.
@export var frozen: bool = false

## Metres nearer the camera this instance is depth-tested than it is. For a thin thing lying on a
## surface (a rug, a poster), which the surface's own splats would otherwise hatch through.
@export var depth_bias: float = 0.0

## Whether it darkens the floor under it when the scene draws floor shadows
## ([member SplatScene.floor_shadows]). Turn it off for the floor itself, for walls, and for what
## lies on a surface.
@export var casts_shadow: bool = true

@export_group("Particles")
## How each splat of a particle cloud moves by itself, in the shader. [constant Motion.NONE] for
## anything that is not a cloud. It costs the CPU nothing, may change every frame, and never
## rebuilds the scene. The rule is [method SplatParticles.offset_at].
@export var motion: Motion = Motion.NONE

## How high a rise goes, or how far a drift wanders from where it starts, in metres of the asset's
## own space.
@export_range(0.0, 4.0, 0.001, "or_greater") var motion_reach: float = 0.0

## A rise only: how wide it wobbles on the way up, in metres.
@export_range(0.0, 1.0, 0.001, "or_greater") var motion_wobble: float = 0.0

## How fast the cloud's clock runs against the scene's.
@export var motion_speed: float = 1.0

@export_group("Tint")
## Whether it is drawn in [member tint] instead of its own colours, and only on every other art
## pixel, so what is behind it shows on the pixels between: a thing that is not there yet, or not
## quite. The pixel look leaves a tinted pixel as it is, outside the palette and never inked, and
## every pixel of the picture is still covered or clear. It costs the CPU nothing, may change every
## frame, and never rebuilds the scene.
## [br]Nothing else about the instance changes: it hides what is behind it on the pixels it takes,
## lamps and dusk still move its splats along their ramps (and so the tint's shading), and it darkens
## the floor while [member casts_shadow] is on.
@export var tinted: bool = false

## The colour a tinted instance is drawn in, sRGB. Each splat takes it at 0.55 to 1.25 of its
## strength, by how light the splat's own colour is ([method tint_shade]), so the shape still reads.
@export_color_no_alpha var tint: Color = Color.WHITE

@export_group("")
## The time [member clip_name] is shown at, in seconds of that clip's own. Negative: the scene's
## clock plus [member time_offset].
var clip_time: float = -1.0

## The clip being left while a fade runs, by name. See [method cross_fade].
var fade_from: String = ""
## The time the clip being left is shown at, in seconds of its own.
var fade_from_time: float = 0.0
## How much of [member clip_name] shows, 0 to 1. From 1 on there is no fade.
var fade_weight: float = 1.0

## Bumped whenever the look changes ([method wear]), so a scene that draws this instance gives it,
## and only it, its new pieces and colours.
var look_version: int = 0

var _clip: SplatClip = null
var _wears: bool = false
var _shown: PackedStringArray = PackedStringArray()
var _ramps: Dictionary = {}
var _look_palette: PackedInt32Array = PackedInt32Array()
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


## The frame of the file's first clip to show at [param seconds] on the scene's clock.
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


# region Tint
## The colour a splat whose own colour is [param own] is drawn in on an instance tinted
## [param with_tint]: the rule the shader runs. Both are sRGB.
static func tint_shade(with_tint: Color, own: Color) -> Color:
	var light: float = 0.55 + 0.7 * (0.30 * own.r + 0.55 * own.g + 0.15 * own.b)
	return Color(clampf(with_tint.r * light, 0.0, 1.0), clampf(with_tint.g * light, 0.0, 1.0), clampf(with_tint.b * light, 0.0, 1.0))
# endregion


# region Wardrobe
## Dresses an asset that holds a wardrobe: it shows the pieces named in [param shown] (and the
## splats of no piece), and each region named in [param ramps] takes that ramp of colours
## (0xRRGGBB, dark to light, as many as the file's own; see [member SplatClip.regions]). A piece or
## a region the file does not have is passed over, and a region that is not named keeps the file's
## colours. Returns false, changing nothing, when a ramp's length is not its region's.
## [br]It costs the scene no rebuild: only this instance's pieces, palette and ramps are written
## again. Calling it with what is already worn does nothing. An asset with no wardrobe ignores it.
func wear(shown: PackedStringArray, ramps: Dictionary = {}) -> bool:
	if _wears and shown == _shown and ramps == _ramps:
		return true
	var clip: SplatClip = get_clip()
	var palette: PackedInt32Array = PackedInt32Array()
	if clip != null and clip.has_look():
		palette = clip.dressed_palette(ramps)
		if palette.is_empty():
			push_error("[SplatInstance] %s" % SplatClip.last_error)
			return false
	_wears = true
	_shown = shown.duplicate()
	_ramps = ramps.duplicate(true)
	_look_palette = palette
	look_version += 1
	return true


## Back to the whole wardrobe at once in the file's own colours, as before any [method wear].
func wear_everything() -> void:
	if not _wears:
		return
	_wears = false
	_shown = PackedStringArray()
	_ramps = {}
	_look_palette = PackedInt32Array()
	look_version += 1


## Whether a piece of the wardrobe is drawn.
func shows(piece: String) -> bool:
	return not _wears or _shown.has(piece)


## The pieces given to the last [method wear]; empty before any.
func get_shown() -> PackedStringArray:
	return _shown


## How many of the asset's splats are drawn in the look it wears.
func shown_splat_count() -> int:
	var clip: SplatClip = get_clip()
	if clip == null:
		return 0
	return clip.count_shown(_shown) if _wears else clip.splat_count


## The asset's palette as this instance wears it: the file's, with the regions given to
## [method wear] in their new colours.
func look_palette() -> PackedInt32Array:
	var clip: SplatClip = get_clip()
	if clip == null:
		return PackedInt32Array()
	if not _wears or not clip.has_look():
		return clip.palette
	if _look_palette.is_empty():
		# the look was given before the asset
		_look_palette = clip.dressed_palette(_ramps)
		if _look_palette.is_empty():
			push_error("[SplatInstance] %s" % SplatClip.last_error)
			_look_palette = clip.palette
	return _look_palette
# endregion


# region Clips
## Plays one of the asset's clips, by name, with no fade. [param seconds] is the time to show it
## at, in seconds of the clip's own; leave it out and the clip runs on the scene's clock plus
## [member time_offset]. A name the asset does not have plays its first clip.
func play(clip: String, seconds: float = -1.0) -> void:
	clip_name = clip
	clip_time = seconds
	fade_from = ""
	fade_weight = 1.0


## Shows two of the asset's clips mixed, for one frame of a change of clip: [param from_clip] at
## [param from_seconds] and [param to_clip] at [param to_seconds] (each in seconds of its own
## clip), with [param weight] of the second, 0 to 1. Call it every frame of the fade with the
## weight as far as it has got, then [method play]. A part that either clip hides takes
## [param to_clip]'s pose at once ([method SplatClip.blend_bones]).
func cross_fade(from_clip: String, from_seconds: float, to_clip: String, to_seconds: float, weight: float) -> void:
	clip_name = to_clip
	clip_time = to_seconds
	fade_from = from_clip
	fade_from_time = from_seconds
	fade_weight = clampf(weight, 0.0, 1.0)


## The clip that plays: [member clip_name]'s, or the asset's first. [code]null[/code] with no asset.
func get_take() -> SplatClip.Take:
	var clip: SplatClip = get_clip()
	if clip == null:
		return null
	var take: SplatClip.Take = clip.find(clip_name) if not clip_name.is_empty() else null
	return take if take != null else clip.takes[0]


## The scene's question each frame: this instance's bones at [param seconds] on the scene's clock,
## written into [param into] from [param at]. Returns a stamp of what was written; give it back as
## [param last_stamp] next time, and nothing is written when the bones have not changed (the same
## frame of the same clip, and no fade running). A fade writes every time and returns -1.
func write_bones(seconds: float, into: PackedFloat32Array, at: int, last_stamp: int) -> int:
	var clip: SplatClip = get_clip()
	if clip == null or clip.bone_count == 0:
		return last_stamp
	var count: int = clip.bone_count * SplatClip.BONE_STRIDE
	var take_index: int = maxi(0, clip.index_of(clip_name))
	var take: SplatClip.Take = clip.takes[take_index]
	var frame: int = 0 if frozen else take.frame_at(clip_time if clip_time >= 0.0 else seconds + time_offset)
	var leaving: SplatClip.Take = clip.find(fade_from) if fade_weight < 1.0 and not fade_from.is_empty() else null
	if leaving == null or leaving == take:
		var stamp: int = take_index * 0x1000000 + frame
		if stamp == last_stamp:
			return stamp
		var from: int = frame * count
		for f: int in count:
			into[at + f] = take.bones[from + f]
		return stamp
	var leaving_frame: int = 0 if frozen else leaving.frame_at(fade_from_time)
	SplatClip.blend_bones(leaving.bones, leaving_frame * count, take.bones, frame * count, fade_weight, clip.bone_count, into, at)
	return -1
# endregion
