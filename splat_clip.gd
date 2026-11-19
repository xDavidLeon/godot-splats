## A splat asset as [code]tools/export.js[/code] writes it (a "TCRS" [code].bytes[/code] file, see FORMAT.md):
## a prop (version 2), a boned clip (version 1) or a boned clip with light data (version 3). A file
## may also hold a wardrobe ([member pieces], [member regions]) and more clips on its one rig
## ([member takes]).
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

## A bone whose translation is below this y parks its part out of sight (ink-studio puts hidden
## parts at y = -99); a splat posed below it is not drawn.
const HIDDEN_BELOW_Y: float = -30.0
## The name of a file's one clip when the file names none.
const UNNAMED_CLIP: String = "clip"

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
## A wardrobe (empty when the file has none): the names of the pieces the file holds, every one of
## them whole. See [method has_look].
var pieces: PackedStringArray = PackedStringArray()
## The piece each splat belongs to (an index into [member pieces]), or -1 for one that always shows.
var piece_of: PackedInt32Array = PackedInt32Array()
## The colour regions of a wardrobe, by name: each a ramp of [member palette] indices, dark to light.
var regions: Dictionary[String, PackedInt32Array] = {}
## The clips on the file's one rig. Always at least one: the first is the file's own
## ([member bones]), called [constant UNNAMED_CLIP] unless the file names its clips. A prop has one
## with no frames.
var takes: Array[Take] = []
## The marks of the optional sections that were read, in the file's order: "LOOK" (a wardrobe) and
## "CLPS" (more clips).
var sections: PackedStringArray = PackedStringArray()
## The mark of a section this reader does not know, or empty. Sections carry no length, so reading
## stops there; everything before it is intact.
var unknown_section: String = ""

var _light_texels: PackedFloat32Array = PackedFloat32Array()
var _look_splats: PackedFloat32Array = PackedFloat32Array()
var _section_error: String = ""
# endregion


# region Clips
## One named clip: its own frames on the file's one rig.
class Take extends RefCounted:
	var name: String = ""
	var frame_count: int = 0
	var fps: float = 0.0
	## [constant SplatClip.BONE_STRIDE] floats per bone, the file's bone count per frame.
	var bones: PackedFloat32Array = PackedFloat32Array()
	## The skinning test's answer for this clip: the frame the file's sample splats
	## ([member SplatClip.reference_splats]) were posed at, or -1 for none (the first clip's are the
	## file's own).
	var reference_frame: int = -1
	## Three floats per sample splat, its posed position at [member reference_frame].
	var reference_positions: PackedFloat32Array = PackedFloat32Array()

	## The clip's length in seconds; 0 for a prop's.
	func duration() -> float:
		return frame_count / fps if frame_count > 0 else 0.0

	## The frame to show at [param seconds], looping. Derived from the time, never accumulated.
	func frame_at(seconds: float) -> int:
		if frame_count <= 0:
			return 0
		return posmod(floori(seconds * fps), frame_count)


## The clip of that name, or [code]null[/code].
func find(clip_name: String) -> Take:
	for take: Take in takes:
		if take.name == clip_name:
			return take
	return null


## Where the clip of that name is in [member takes], or -1.
func index_of(clip_name: String) -> int:
	for t: int in takes.size():
		if takes[t].name == clip_name:
			return t
	return -1


## Writes one frame's bones, two clips mixed, into [param into] from [param at]: [param bones_in_rig]
## bones of [constant BONE_STRIDE] floats, each entry [param weight] of the way from
## [param from_bones] (read from [param from_at]) to [param to_bones] (read from [param to_at]).
## A part that either clip hides (its bone's y is below [constant HIDDEN_BELOW_Y]) takes
## [param to_bones]'s matrix at once: mixing to or from there would fly it through the picture.
static func blend_bones(from_bones: PackedFloat32Array, from_at: int, to_bones: PackedFloat32Array, to_at: int,
		weight: float, bones_in_rig: int, into: PackedFloat32Array, at: int) -> void:
	for bone: int in bones_in_rig:
		var o: int = bone * BONE_STRIDE
		var hidden: bool = from_bones[from_at + o + 10] < HIDDEN_BELOW_Y or to_bones[to_at + o + 10] < HIDDEN_BELOW_Y
		for k: int in BONE_STRIDE:
			var b: float = to_bones[to_at + o + k]
			if hidden:
				into[at + o + k] = b
			else:
				var a: float = from_bones[from_at + o + k]
				into[at + o + k] = a + (b - a) * weight
# endregion


# region Wardrobe
## True for a file that holds a wardrobe: every piece whole, to be shown or hidden, and colour
## regions to be given other ramps.
func has_look() -> bool:
	return not pieces.is_empty()


## The file's palette with each region in [param ramps] given other colours: a region's name to its
## ramp, 0xRRGGBB, dark to light, as long as the file's own. A region the file does not have is
## passed over, and one that is not named keeps its colours. Returns an empty array, and sets
## [member last_error], when a ramp's length is not the region's.
func dressed_palette(ramps: Dictionary) -> PackedInt32Array:
	var dressed: PackedInt32Array = palette.duplicate()
	for region: Variant in ramps:
		if not regions.has(region):
			continue
		var indices: PackedInt32Array = regions[region]
		var colours: PackedInt32Array = PackedInt32Array(ramps[region])
		if colours.size() != indices.size():
			last_error = "The %s region has %d colours; it was given %d." % [region, indices.size(), colours.size()]
			return PackedInt32Array()
		for c: int in indices.size():
			dressed[indices[c]] = colours[c] & 0xFFFFFF
	return dressed


## How many splats a look shows: those of the pieces named in [param shown], and those of no piece.
func count_shown(shown: PackedStringArray) -> int:
	if not has_look():
		return splat_count
	var wanted: PackedByteArray = PackedByteArray()
	wanted.resize(pieces.size())
	for p: int in pieces.size():
		wanted[p] = 1 if shown.has(pieces[p]) else 0
	var count: int = 0
	for piece: int in piece_of:
		if piece < 0 or wanted[piece] == 1:
			count += 1
	return count


## The splat records as [SplatScene] hands a wardrobe's to its shader: a splat whose colour is one of
## a region's carries, in place of that colour, -(1 + its palette index), for the shader to look up
## in the palette its instance wears. Every other splat is as the file holds it. Made once and kept.
# A splat carries its colour, not its palette index. The exporter makes sure every region colour is
# in the palette once, so the colour finds the index.
func look_splats() -> PackedFloat32Array:
	if _look_splats.size() == splats.size():
		return _look_splats
	var index_of_colour: Dictionary[float, int] = {}
	for region: String in regions:
		for index: int in regions[region]:
			var packed: float = pack(palette[index])
			if not index_of_colour.has(packed):
				index_of_colour[packed] = index
	_look_splats = splats.duplicate()
	for i: int in splat_count:
		var o: int = i * STRIDE + 7
		var index: int = index_of_colour.get(_look_splats[o], -1)
		if index >= 0:
			_look_splats[o] = -(1.0 + index)
	return _look_splats
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
		if clip.takes.is_empty():
			clip.takes.append(clip._own_take(UNNAMED_CLIP))
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
		_section_error = "it ends early"
		if mark == "LOOK":
			next = _parse_look(bytes, at + 4, palette_count)
		elif mark == "CLPS":
			next = _parse_clips(bytes, at + 4, samples)
		else:
			unknown_section = mark
			break
		if next < 0:
			return "The %s section cannot be read: %s." % [mark, _section_error]
		sections.append(mark)
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


# A wardrobe: piece names, a piece per splat, then named colour regions. Returns the offset after it,
# or -1 with _section_error saying why.
func _parse_look(bytes: PackedByteArray, at: int, palette_count: int) -> int:
	var size: int = bytes.size()
	if at + 4 > size:
		return -1
	var piece_count: int = bytes.decode_s32(at)
	at += 4
	if piece_count <= 0 or piece_count > 1024:
		_section_error = "its piece count is out of range"
		return -1
	var names: PackedStringArray = PackedStringArray()
	for p: int in piece_count:
		var name_end: int = _skip_name(bytes, at)
		if name_end < 0:
			_section_error = "a piece's name is out of range"
			return -1
		names.append(bytes.slice(at + 4, name_end).get_string_from_utf8())
		at = name_end
	if at + splat_count * 4 + 4 > size:
		return -1
	var of: PackedInt32Array = bytes.slice(at, at + splat_count * 4).to_int32_array()
	at += splat_count * 4
	for piece: int in of:
		if piece < -1 or piece >= piece_count:
			_section_error = "a splat names a piece the file does not have"
			return -1
	var region_count: int = bytes.decode_s32(at)
	at += 4
	if region_count < 0 or region_count > 256:
		_section_error = "its region count is out of range"
		return -1
	var named: Dictionary[String, PackedInt32Array] = {}
	for r: int in region_count:
		var name_end: int = _skip_name(bytes, at)
		if name_end < 0 or name_end + 4 > size:
			_section_error = "a region's name is out of range"
			return -1
		var region: String = bytes.slice(at + 4, name_end).get_string_from_utf8()
		var colours: int = bytes.decode_s32(name_end)
		at = name_end + 4
		if colours <= 0 or colours > 256 or at + colours * 4 > size:
			_section_error = "the %s region is out of range" % region
			return -1
		var indices: PackedInt32Array = bytes.slice(at, at + colours * 4).to_int32_array()
		for index: int in indices:
			if index < 0 or index >= palette_count:
				_section_error = "the %s region names a colour the palette does not have" % region
				return -1
		named[region] = indices
		at += colours * 4
	pieces = names
	piece_of = of
	regions = named
	return at


# More named clips on the same rig. Returns the offset after them, or -1 with _section_error saying why.
func _parse_clips(bytes: PackedByteArray, at: int, samples: int) -> int:
	var size: int = bytes.size()
	if at + 4 > size:
		return -1
	var clip_count: int = bytes.decode_s32(at)
	at += 4
	if clip_count <= 0 or clip_count > 256:
		_section_error = "its clip count is out of range"
		return -1
	var read_takes: Array[Take] = []
	for c: int in clip_count:
		var name_end: int = _skip_name(bytes, at)
		if name_end < 0 or name_end + 8 > size:
			_section_error = "a clip's name is out of range"
			return -1
		var clip_name: String = bytes.slice(at + 4, name_end).get_string_from_utf8()
		var frames: int = bytes.decode_s32(name_end)
		var clip_fps: float = bytes.decode_float(name_end + 4)
		at = name_end + 8
		for earlier: Take in read_takes:
			if earlier.name == clip_name:
				_section_error = "two clips are called %s" % clip_name
				return -1
		if c == 0:
			# the first clip is the header's: it only gets its name here
			if frames != 0 or at + 4 > size or bytes.decode_s32(at) != -1:
				_section_error = "its first clip must be the header's, with no frames of its own"
				return -1
			at += 4
			read_takes.append(_own_take(clip_name))
			continue
		if frames <= 0 or clip_fps <= 0.0:
			_section_error = "the clip %s is out of range" % clip_name
			return -1
		var floats: int = frames * bone_count * BONE_STRIDE
		if at + floats * 4 + 4 > size:
			return -1
		var take: Take = Take.new()
		take.name = clip_name
		take.frame_count = frames
		take.fps = clip_fps
		take.bones = bytes.slice(at, at + floats * 4).to_float32_array()
		at += floats * 4
		take.reference_frame = bytes.decode_s32(at)
		at += 4
		if take.reference_frame < -1 or take.reference_frame >= frames:
			_section_error = "the clip %s's reference frame is out of range" % clip_name
			return -1
		if take.reference_frame >= 0:
			if at + samples * 12 > size:
				return -1
			take.reference_positions = bytes.slice(at, at + samples * 12).to_float32_array()
			at += samples * 12
		read_takes.append(take)
	takes = read_takes
	return at


# The header's clip as a take.
func _own_take(clip_name: String) -> Take:
	var take: Take = Take.new()
	take.name = clip_name
	take.frame_count = frame_count
	take.fps = fps
	take.bones = bones
	return take


# The offset after the name at [param at] (an int32 length, then that many bytes), or -1.
func _skip_name(bytes: PackedByteArray, at: int) -> int:
	if at + 4 > bytes.size():
		return -1
	var length: int = bytes.decode_s32(at)
	if length <= 0 or length > _MAX_NAME_BYTES or at + 4 + length > bytes.size():
		return -1
	return at + 4 + length
# endregion
