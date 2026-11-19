## A splat asset as [code]tools/export.js[/code] writes it (a "TCRS" [code].bytes[/code] file, see FORMAT.md):
## a prop (version 2), a boned clip (version 1) or a boned clip with light data (version 3).
##
## The numbers are kept exactly as the file holds them: ink-studio's world, in metres, Y up and
## right-handed. That is Godot's own convention, so nothing is flipped here.
# In Unity, SplatClip.Read flips z (positions, covariances, bones, normals) because Unity is
# left-handed, and the game's picture comes out mirrored against ink-studio's. Godot needs no flip,
# so a Godot picture is the same way round as ink-studio's own render.
class_name SplatClip
extends RefCounted


# region Constants
## A clip: a puppet and its frames.
const FORMAT_VERSION: int = 1
## A prop: no bones, no frames, and a colour set for each of the four ways it can stand.
const PROP_VERSION: int = 2
## A clip that also carries light data.
const LIT_CLIP_VERSION: int = 3
## How many ways a prop can stand: quarter turns about y.
const TURNS: int = 4
## Floats per splat: position (3), density, covariance c00 c01 c02, packed colour, c11 c12 c22,
## kind, bone, second bone, the second bone's weight, one spare.
const STRIDE: int = 16
## Floats per bone and frame: a 3x3 by rows, then the translation.
const BONE_STRIDE: int = 12
## The splat kind that rides on bones; every other splat the format allows is plain (kind 0).
const BONED_KIND: int = 12

const _HEADER_BYTES: int = 56
const _MAX_NAME_BYTES: int = 256
# endregion


# region State
## Why the last [method read] returned [code]null[/code], or empty.
static var last_error: String = ""

## The file's version: [constant FORMAT_VERSION], [constant PROP_VERSION] or [constant LIT_CLIP_VERSION].
var version: int = 0
var splat_count: int = 0
var bone_count: int = 0
var frame_count: int = 0
var fps: float = 0.0
## 0xRRGGBB, sRGB; index 0 is the background.
var palette: PackedInt32Array = PackedInt32Array()
## [constant STRIDE] floats per splat.
var splats: PackedFloat32Array = PackedFloat32Array()
## [constant BONE_STRIDE] floats per bone, [member bone_count] bones per frame.
var bones: PackedFloat32Array = PackedFloat32Array()
## The scene's own camera, as ink-studio frames it: target x y z, distance, pitch, yaw (radians).
var camera: PackedFloat32Array = PackedFloat32Array()
## Art pixels per metre of ink-studio's reference render, roughly.
var detail: float = 0.0
## The skinning test's sample: indices of splats on bones.
var reference_splats: PackedInt32Array = PackedInt32Array()
## The frames the sample was posed at by ink-studio.
var reference_frames: PackedInt32Array = PackedInt32Array()
## Per reference frame: three floats per sample splat, its posed position.
var reference_positions: Array[PackedFloat32Array] = []
## Props only (empty for a clip): each splat's packed colour when the prop is turned k quarter
## turns, baked with the room's sun turned the other way. See [method turn_of].
var colour_sets: Array[PackedFloat32Array] = []
## Light data (empty when the file has none): the ramps splats were shaded on, each a list of
## palette indices from dark to light.
var ramps: Array[PackedInt32Array] = []
## The ramp each splat was shaded on, or -1 for one that keeps its colour.
var ramp_of: PackedInt32Array = PackedInt32Array()
## How bright each splat came out of each bake, 0 to 1: four sets for a prop, one for a clip.
var brightness: Array[PackedFloat32Array] = []
## Three floats per splat: its surface normal.
var normals: PackedFloat32Array = PackedFloat32Array()
## The marks of the optional sections that were read past: "LOOK" (a wardrobe) and "CLPS" (more
## clips) are recognised and skipped.
var skipped_sections: PackedStringArray = PackedStringArray()
## The mark of a section this reader does not know, or empty. Sections carry no length, so reading
## stops there; everything before it is intact.
var unknown_section: String = ""

var _light_texels: PackedFloat32Array = PackedFloat32Array()
# endregion


# region Queries
## True for a prop: it has four colour sets and no bones.
func is_prop() -> bool:
	return not colour_sets.is_empty()


## True when the file carries light data.
func has_light() -> bool:
	return not ramps.is_empty()


## Four floats per splat, as [SplatScene] hands them to its shader: the splat's normal, then the ramp
## it was shaded on, or -1 for one that keeps its colour (every splat of a file with no light data).
## Made once and kept.
func light_texels() -> PackedFloat32Array:
	if _light_texels.size() == splat_count * 4:
		return _light_texels
	_light_texels.resize(splat_count * 4)
	var lit: bool = has_light()
	for i: int in splat_count:
		var o: int = i * 4
		if lit:
			_light_texels[o] = normals[i * 3]
			_light_texels[o + 1] = normals[i * 3 + 1]
			_light_texels[o + 2] = normals[i * 3 + 2]
			_light_texels[o + 3] = ramp_of[i]
		else:
			_light_texels[o] = 0.0
			_light_texels[o + 1] = 0.0
			_light_texels[o + 2] = 0.0
			_light_texels[o + 3] = -1.0
	return _light_texels


## The clip's length in seconds; 0 for a prop.
func duration() -> float:
	return frame_count / fps if frame_count > 0 else 0.0


## The frame to show at [param seconds], looping. Derived from the time, never accumulated.
func frame_at(seconds: float) -> int:
	if frame_count <= 0:
		return 0
	return posmod(floori(seconds * fps), frame_count)


## The colour set for a prop turned [param yaw_radians] about y in Godot (counter-clockwise seen
## from above): the nearest quarter turn.
# The file counts its sets in Unity's yaw, which turns the other way seen from above, so the sign
# flips: Godot's +90 degrees is the file's set 3.
static func turn_of(yaw_radians: float) -> int:
	return posmod(roundi(-yaw_radians / (PI * 0.5)), TURNS)


## True when a splat record's kind field says it rides on bones.
static func is_boned(kind_field: float) -> bool:
	return roundi(kind_field) % 16 == BONED_KIND


## A palette colour (0xRRGGBB) as a splat record carries it: r + g * 256 + b * 65536.
static func pack(rgb: int) -> float:
	return float(((rgb >> 16) & 255) + ((rgb >> 8) & 255) * 256 + (rgb & 255) * 65536)


## A splat record's packed colour as 0xRRGGBB.
static func unpack(packed: float) -> int:
	var value: int = roundi(packed)
	return ((value & 255) << 16) | (((value >> 8) & 255) << 8) | ((value >> 16) & 255)
# endregion


# region Reading
## Reads the file at [param path]. Returns [code]null[/code] and sets [member last_error] on failure.
static func load_file(path: String) -> SplatClip:
	if not FileAccess.file_exists(path):
		last_error = "No splat file at %s." % path
		return null
	return read(FileAccess.get_file_as_bytes(path))


## Reads a TCRS file's bytes. Returns [code]null[/code] and sets [member last_error] on failure.
static func read(bytes: PackedByteArray) -> SplatClip:
	last_error = ""
	var clip: SplatClip = SplatClip.new()
	var error: String = clip._parse(bytes)
	if error.is_empty():
		return clip
	last_error = error
	return null


func _parse(bytes: PackedByteArray) -> String:
	var size: int = bytes.size()
	if size < _HEADER_BYTES:
		return "Splat file ends early (the header)."
	var magic: String = bytes.slice(0, 4).get_string_from_ascii()
	if magic != "TCRS":
		return "Not a splat file (starts with \"%s\")." % magic
	version = bytes.decode_s32(4)
	if version != FORMAT_VERSION and version != PROP_VERSION and version != LIT_CLIP_VERSION:
		return "Splat file version %d; this reader knows 1 (a clip), 2 (a prop) and 3 (a clip with light data)." % version
	var prop: bool = version == PROP_VERSION
	splat_count = bytes.decode_s32(8)
	var palette_count: int = bytes.decode_s32(12)
	bone_count = bytes.decode_s32(16)
	frame_count = bytes.decode_s32(20)
	fps = bytes.decode_float(24)
	if splat_count <= 0 or palette_count <= 0 or bone_count < 0:
		return "Splat file header is out of range."
	if prop and (bone_count != 0 or frame_count != 0):
		return "A prop (version 2) has no bones or frames."
	if not prop and (frame_count <= 0 or fps <= 0.0):
		return "Splat clip header is out of range."
	camera = bytes.slice(28, 52).to_float32_array()
	detail = bytes.decode_float(52)

	var at: int = _HEADER_BYTES
	var count: int = palette_count * 4
	if at + count > size:
		return "Splat file ends early (the palette)."
	palette = bytes.slice(at, at + count).to_int32_array()
	at += count

	count = splat_count * STRIDE * 4
	if at + count > size:
		return "Splat file ends early (the splats)."
	splats = bytes.slice(at, at + count).to_float32_array()
	at += count

	count = frame_count * bone_count * BONE_STRIDE * 4
	if at + count > size:
		return "Splat file ends early (the bones)."
	bones = bytes.slice(at, at + count).to_float32_array()
	at += count

	if at + 8 > size:
		return "Splat file ends early (the references)."
	var references: int = bytes.decode_s32(at)
	var samples: int = bytes.decode_s32(at + 4)
	at += 8
	if references < 0 or samples < 0 or at + samples * 4 + references * (4 + samples * 12) > size:
		return "Splat file ends early (the references)."
	reference_splats = bytes.slice(at, at + samples * 4).to_int32_array()
	at += samples * 4
	reference_frames.resize(references)
	for r: int in references:
		reference_frames[r] = bytes.decode_s32(at)
		at += 4
		reference_positions.append(bytes.slice(at, at + samples * 12).to_float32_array())
		at += samples * 12

	if prop:
		if at + 4 > size:
			return "Splat file ends early (the colour sets)."
		var sets: int = bytes.decode_s32(at)
		at += 4
		if sets != TURNS:
			return "A prop has %d colour sets; this one has %d." % [TURNS, sets]
		if at + sets * splat_count * 4 > size:
			return "Splat file ends early (the colour sets)."
		for k: int in sets:
			colour_sets.append(bytes.slice(at, at + splat_count * 4).to_float32_array())
			at += splat_count * 4

	# A prop written before the light data existed ends here; a lit clip must go on.
	if version == LIT_CLIP_VERSION or (prop and at < size):
		at = _parse_light(bytes, at, palette_count, TURNS if prop else 1)
		if at < 0:
			return "Splat light data ends early or is out of range."

	# Optional sections, each under a four-letter mark, in any order.
	while size - at >= 4:
		var mark: String = bytes.slice(at, at + 4).get_string_from_ascii()
		var next: int = -1
		if mark == "LOOK":
			next = _skip_look(bytes, at + 4)
		elif mark == "CLPS":
			next = _skip_clips(bytes, at + 4, samples)
		else:
			unknown_section = mark
			break
		if next < 0:
			return "The %s section ends early or is out of range." % mark
		skipped_sections.append(mark)
		at = next
	return ""


# Returns the offset after the light data, or -1.
func _parse_light(bytes: PackedByteArray, at: int, palette_count: int, expected_sets: int) -> int:
	var size: int = bytes.size()
	if at + 4 > size:
		return -1
	var ramp_count: int = bytes.decode_s32(at)
	at += 4
	if ramp_count < 0 or ramp_count > 4096:
		return -1
	for r: int in ramp_count:
		if at + 4 > size:
			return -1
		var length: int = bytes.decode_s32(at)
		at += 4
		if length <= 0 or length > 256 or at + length * 4 > size:
			return -1
		var ramp: PackedInt32Array = bytes.slice(at, at + length * 4).to_int32_array()
		for index: int in ramp:
			if index < 0 or index >= palette_count:
				return -1
		ramps.append(ramp)
		at += length * 4
	if at + splat_count * 4 + 4 > size:
		return -1
	ramp_of = bytes.slice(at, at + splat_count * 4).to_int32_array()
	at += splat_count * 4
	var sets: int = bytes.decode_s32(at)
	at += 4
	if sets != expected_sets or at + sets * splat_count * 4 + splat_count * 12 > size:
		return -1
	for k: int in sets:
		brightness.append(bytes.slice(at, at + splat_count * 4).to_float32_array())
		at += splat_count * 4
	normals = bytes.slice(at, at + splat_count * 12).to_float32_array()
	return at + splat_count * 12


# A wardrobe: piece names, a piece per splat, then named colour regions. Returns the offset after it, or -1.
func _skip_look(bytes: PackedByteArray, at: int) -> int:
	var size: int = bytes.size()
	if at + 4 > size:
		return -1
	var pieces: int = bytes.decode_s32(at)
	at += 4
	if pieces <= 0 or pieces > 1024:
		return -1
	for p: int in pieces:
		at = _skip_name(bytes, at)
		if at < 0:
			return -1
	at += splat_count * 4
	if at + 4 > size:
		return -1
	var regions: int = bytes.decode_s32(at)
	at += 4
	if regions < 0 or regions > 256:
		return -1
	for r: int in regions:
		at = _skip_name(bytes, at)
		if at < 0 or at + 4 > size:
			return -1
		var colours: int = bytes.decode_s32(at)
		if colours <= 0 or colours > 256:
			return -1
		at += 4 + colours * 4
		if at > size:
			return -1
	return at


# More named clips on the same rig. Returns the offset after them, or -1.
func _skip_clips(bytes: PackedByteArray, at: int, samples: int) -> int:
	var size: int = bytes.size()
	if at + 4 > size:
		return -1
	var clips: int = bytes.decode_s32(at)
	at += 4
	if clips <= 0 or clips > 256:
		return -1
	for c: int in clips:
		at = _skip_name(bytes, at)
		if at < 0 or at + 12 > size:
			return -1
		var frames: int = bytes.decode_s32(at)
		at += 8 # the frame count and the fps
		if frames < 0:
			return -1
		at += frames * bone_count * BONE_STRIDE * 4
		if at + 4 > size:
			return -1
		var reference: int = bytes.decode_s32(at)
		at += 4
		if reference >= 0:
			at += samples * 12
		if at > size:
			return -1
	return at


func _skip_name(bytes: PackedByteArray, at: int) -> int:
	if at + 4 > bytes.size():
		return -1
	var length: int = bytes.decode_s32(at)
	if length <= 0 or length > _MAX_NAME_BYTES or at + 4 + length > bytes.size():
		return -1
	return at + 4 + length
# endregion
