## Unit tests for [SplatClip], the reader of TCRS splat files. The expected numbers were read from
## the sample files with a separate script (Python's struct), not with the reader under test.
extends Object


const SplatClipScript: GDScript = preload("res://addons/splats/splat_clip.gd")

var failures: int = 0


func run_tests() -> int:
	failures = 0
	_test_prop()
	_test_lit_clip()
	_test_wardrobe_file()
	_test_clips_file()
	_test_sections()
	_test_section_refusals()
	_test_refusals()
	_test_helpers()
	return failures


func assert_eq(actual: Variant, expected: Variant, message: String) -> bool:
	if actual != expected:
		print("FAIL: ", message, " | Expected: ", expected, " Actual: ", actual)
		failures += 1
		return false
	else:
		print("PASS: ", message)
		return true


func assert_near(actual: float, expected: float, message: String) -> bool:
	return assert_eq(is_equal_approx(actual, expected), true, "%s (%s ~ %s)" % [message, actual, expected])


func _test_prop() -> void:
	var clip: SplatClip = SplatClipScript.load_file("res://splats/samples/mug.bytes")
	if not assert_eq(clip != null, true, "mug.bytes reads (%s)" % SplatClipScript.last_error):
		return
	assert_eq(clip.version, 2, "mug is a prop (version 2)")
	assert_eq(clip.is_prop(), true, "mug says it is a prop")
	assert_eq(clip.splat_count, 929, "mug splat count")
	assert_eq(clip.bone_count, 0, "mug has no bones")
	assert_eq(clip.frame_count, 0, "mug has no frames")
	assert_eq(clip.palette.size(), 21, "mug palette size")
	assert_eq(clip.palette[0], 0x2a1f1a, "mug background colour")
	assert_eq(clip.palette[1], 0x3b2418, "mug palette entry 1")
	assert_eq(clip.palette[20], 0xfff8e6, "mug last palette entry")
	assert_near(clip.camera[3], 0.5, "mug camera distance")
	assert_near(clip.camera[5], 0.6, "mug camera yaw")
	assert_near(clip.detail, 260.0, "mug detail")
	# splat 464, as the file holds it (no z flip in Godot)
	var o: int = 464 * SplatClipScript.STRIDE
	assert_near(clip.splats[o], 0.0034317574463784695, "mug splat 464 x")
	assert_near(clip.splats[o + 1], 0.07171875238418579, "mug splat 464 y")
	assert_near(clip.splats[o + 2], -0.03922516480088234, "mug splat 464 z")
	assert_eq(clip.splats[o + 3], 3.0, "mug splat 464 density")
	assert_eq(clip.splats[o + 7], 3295882.0, "mug splat 464 packed colour")
	assert_eq(SplatClipScript.unpack(clip.splats[o + 7]), 0x8a4a32, "mug splat 464 colour is in the palette")
	assert_eq(clip.palette.has(SplatClipScript.unpack(clip.splats[o + 7])), true, "mug splat 464 colour found")
	assert_eq(clip.colour_sets.size(), 4, "mug has four colour sets")
	assert_eq(clip.colour_sets[0].size(), 929, "mug colour set length")
	assert_eq(clip.colour_sets[0][464], clip.splats[o + 7], "set 0 is the records' colour")
	assert_eq(clip.has_light(), true, "mug carries light data")
	assert_eq(clip.ramps.size(), 1, "mug ramps")
	assert_eq(clip.brightness.size(), 4, "mug light sets")
	assert_eq(clip.normals.size(), 929 * 3, "mug normals")
	assert_eq(clip.unknown_section, "", "mug has no unknown section")


func _test_lit_clip() -> void:
	var clip: SplatClip = SplatClipScript.load_file("res://splats/samples/avatar-b.bytes")
	if not assert_eq(clip != null, true, "avatar-b.bytes reads (%s)" % SplatClipScript.last_error):
		return
	assert_eq(clip.version, 3, "avatar-b is a lit clip (version 3)")
	assert_eq(clip.is_prop(), false, "avatar-b is not a prop")
	assert_eq(clip.splat_count, 35860, "avatar-b splat count")
	assert_eq(clip.bone_count, 8, "avatar-b bones")
	assert_eq(clip.frame_count, 240, "avatar-b frames")
	assert_eq(clip.fps, 30.0, "avatar-b fps")
	assert_eq(clip.palette.size(), 36, "avatar-b palette size")
	assert_eq(clip.palette[35], 0xfff8e6, "avatar-b last palette entry")
	assert_eq(clip.bones.size(), 240 * 8 * 12, "avatar-b bone floats")
	var o: int = 17930 * SplatClipScript.STRIDE
	assert_near(clip.splats[o], 0.08134642243385315, "avatar-b splat 17930 x")
	assert_near(clip.splats[o + 2], 0.46152639389038086, "avatar-b splat 17930 z")
	assert_eq(SplatClipScript.is_boned(clip.splats[o + 11]), true, "avatar-b splat 17930 rides a bone")
	assert_eq(clip.splats[o + 12], 1.0, "avatar-b splat 17930 bone")
	assert_eq(SplatClipScript.is_boned(clip.splats[11]), false, "avatar-b splat 0 is plain")
	assert_eq(clip.reference_frames.size(), 3, "avatar-b reference frames")
	assert_eq(clip.reference_splats.size(), 256, "avatar-b reference sample")
	assert_eq(clip.ramps.size(), 14, "avatar-b ramps")
	assert_eq(clip.brightness.size(), 1, "avatar-b light sets")
	assert_near(clip.duration(), 8.0, "avatar-b duration")
	assert_eq(clip.frame_at(0.0), 0, "frame at 0 s")
	assert_eq(clip.frame_at(3.0), 90, "frame at 3 s")
	assert_eq(clip.frame_at(8.0), 0, "the clip loops")
	assert_eq(clip.frame_at(-0.01), 239, "a time before 0 wraps")
	assert_eq(clip.has_look(), false, "avatar-b has no wardrobe")
	assert_eq(clip.sections.size(), 0, "avatar-b has no optional section")
	assert_eq(clip.takes.size(), 1, "a file that names no clips has one")
	assert_eq(clip.takes[0].name, "clip", "and it is called \"clip\"")
	assert_eq(clip.takes[0].frame_count, 240, "the one clip is the header's")
	assert_eq(clip.takes[0].bones == clip.bones, true, "with the header's bones")
	assert_eq(clip.find("typing") == null, true, "no clip is found by another name")
	_test_skinning(clip)


# A file with a wardrobe (a LOOK section). Every number here was read with the separate script.
func _test_wardrobe_file() -> void:
	var clip: SplatClip = SplatClipScript.load_file("res://splats/samples/avatar-a-stand.bytes")
	if not assert_eq(clip != null, true, "avatar-a-stand.bytes reads (%s)" % SplatClipScript.last_error):
		return
	assert_eq(clip.version, 3, "avatar-a-stand is a lit clip")
	assert_eq(clip.splat_count, 74516, "avatar-a-stand splat count")
	assert_eq(clip.palette.size(), 31, "avatar-a-stand palette size")
	assert_eq(clip.bone_count, 8, "avatar-a-stand bones")
	assert_eq(clip.sections, PackedStringArray(["LOOK", "CLPS"]), "avatar-a-stand has both sections, in the file's order")
	assert_eq(clip.unknown_section, "", "and nothing unknown after them")
	assert_eq(clip.has_look(), true, "avatar-a-stand holds a wardrobe")
	assert_eq(clip.pieces, PackedStringArray(["shoes:shoes", "bottom:trousers", "top:sweater", "top:stripes", "top:cable-knit",
			"body", "hair:bun", "hair:messy", "under-hat", "accessory:glasses-round", "accessory:headband",
			"accessory:headphones-round", "accessory:beanie"]), "avatar-a-stand's pieces, in the file's order")
	assert_eq(clip.piece_of.size(), 74516, "a piece for every splat")
	assert_eq(clip.piece_of[0], 0, "splat 0 is of piece 0")
	assert_eq(clip.piece_of[30000], 5, "splat 30000 is of the body")
	assert_eq(clip.piece_of[74515], 12, "the last splat is of the last piece")
	var sizes: PackedInt32Array = PackedInt32Array()
	sizes.resize(clip.pieces.size())
	var of_none: int = 0
	for piece: int in clip.piece_of:
		if piece < 0:
			of_none += 1
		else:
			sizes[piece] += 1
	assert_eq(sizes, PackedInt32Array([3270, 3879, 5805, 5805, 5805, 20534, 7338, 7745, 2026, 1577, 1591, 2825, 6316]), "splats in each piece")
	assert_eq(of_none, 0, "every splat is of a piece")
	assert_eq(clip.regions.keys(), ["skin", "hair", "top", "bottom", "socks", "shoes", "pink"], "the colour regions, in the file's order")
	assert_eq(clip.regions["skin"], PackedInt32Array([1, 2, 3]), "the skin's palette indices")
	assert_eq(clip.regions["bottom"], PackedInt32Array([13, 14, 15]), "the bottom's palette indices")
	assert_eq(clip.regions["pink"], PackedInt32Array([25, 26]), "a region of two colours")
	assert_eq(clip.palette[clip.regions["top"][1]], 0xd8783e, "the top's middle colour")
	assert_eq(clip.palette[clip.regions["hair"][0]], 0x521514, "the hair's dark colour")
	assert_eq(clip.takes.size(), 1, "avatar-a-stand has one clip")
	assert_eq(clip.takes[0].name, "standing", "named by its CLPS section")
	assert_eq(clip.takes[0].frame_count, 240, "and it is the header's clip")
	assert_eq(clip.ramps.size(), 20, "the light data before the sections is intact")


# A file with several clips (a CLPS section). Every number here was read with the separate script.
func _test_clips_file() -> void:
	var clip: SplatClip = SplatClipScript.load_file("res://splats/samples/avatar-a.bytes")
	if not assert_eq(clip != null, true, "avatar-a.bytes reads (%s)" % SplatClipScript.last_error):
		return
	assert_eq(clip.splat_count, 90636, "avatar-a splat count")
	assert_eq(clip.palette.size(), 46, "avatar-a palette size")
	assert_eq(clip.bone_count, 9, "avatar-a bones")
	assert_eq(clip.sections, PackedStringArray(["LOOK", "CLPS"]), "avatar-a has both sections")
	assert_eq(clip.pieces.size(), 17, "avatar-a pieces")
	assert_eq(clip.pieces[16], "device:book", "avatar-a's last piece")
	assert_eq(clip.piece_of[45000], 5, "avatar-a splat 45000 is of the body")
	assert_eq(clip.piece_of[90635], 16, "avatar-a's last splat is of the last piece")
	assert_eq(clip.regions.size(), 7, "avatar-a regions")
	var names: PackedStringArray = PackedStringArray()
	for take: SplatClip.Take in clip.takes:
		names.append(take.name)
	assert_eq(names, PackedStringArray(["typing", "sitting", "writing", "drawing", "reading", "finished"]), "avatar-a's clips, in the file's order")
	assert_eq(clip.takes[0].bones == clip.bones, true, "the first clip is the header's")
	assert_eq(clip.takes[0].reference_frame, -1, "and its references are the file's own")
	assert_eq(clip.index_of("drawing"), 3, "a clip is found by name")
	assert_eq(clip.index_of("flying"), -1, "and a name the file does not have is not")
	# bone 6 at frame 100 of each clip: its first entry, then its translation
	var expected: Dictionary[String, Array] = {
		"typing": [0.8795025944709778, -0.3395000696182251, 0.7023429870605469, 0.004233829211443663],
		"sitting": [0.8740120530128479, 0.07571177184581757, 0.16045615077018738, -0.1131439357995987],
		"writing": [0.8927561044692993, -0.12071391195058823, 0.37585291266441345, -0.13710543513298035],
		"drawing": [0.8234009146690369, 0.09876324236392975, 0.18319685757160187, -0.12428367882966995],
		"reading": [0.7759047746658325, 0.05024242773652077, 0.2693299651145935, -0.15090331435203552],
		"finished": [0.8061444163322449, 0.11232250183820724, 0.18363380432128906, -0.12487686425447464],
	}
	# and where ink-studio posed sample 248 (splat 84699) at each later clip's reference frame
	var posed: Dictionary[String, Vector3] = {
		"sitting": Vector3(-0.06919380277395248, 0.45828816294670105, 0.4638846516609192),
		"writing": Vector3(-0.006603339221328497, 0.5209535360336304, 0.38666006922721863),
		"drawing": Vector3(0.030383210629224777, 0.5343320965766907, 0.41277071833610535),
		"reading": Vector3(-0.1393231749534607, 0.4699835777282715, 0.39249011874198914),
		"finished": Vector3(-0.06922832131385803, 0.4532555937767029, 0.46624812483787537),
	}
	assert_eq(clip.reference_splats[248], 84699, "sample 248 is splat 84699")
	for take: SplatClip.Take in clip.takes:
		assert_eq(take.frame_count, 240, "%s frames" % take.name)
		assert_eq(take.fps, 30.0, "%s fps" % take.name)
		assert_eq(take.bones.size(), 240 * 9 * 12, "%s bone floats" % take.name)
		assert_near(take.duration(), 8.0, "%s duration" % take.name)
		var o: int = (100 * 9 + 6) * SplatClipScript.BONE_STRIDE
		var want: Array = expected[take.name]
		assert_eq(is_equal_approx(take.bones[o], want[0]) and is_equal_approx(take.bones[o + 9], want[1])
				and is_equal_approx(take.bones[o + 10], want[2]) and is_equal_approx(take.bones[o + 11], want[3]), true,
				"%s bone 6 at frame 100" % take.name)
		if take.name == "typing":
			continue
		assert_eq(take.reference_frame, 89, "%s reference frame" % take.name)
		assert_eq(take.reference_positions.size(), 256 * 3, "%s reference positions" % take.name)
		var at: Vector3 = Vector3(take.reference_positions[248 * 3], take.reference_positions[248 * 3 + 1], take.reference_positions[248 * 3 + 2])
		assert_eq(at.is_equal_approx(posed[take.name]), true, "%s posed sample 248 (%s)" % [take.name, at])
		# the skinning is ink-studio's in every clip: pose the samples with this clip's bones and compare
		var worst: float = 0.0
		for s: int in clip.reference_splats.size():
			var so: int = clip.reference_splats[s] * SplatClipScript.STRIDE
			var p: Vector3 = Vector3(clip.splats[so], clip.splats[so + 1], clip.splats[so + 2])
			var moved: Vector3 = _bone_of(take.bones, clip.bone_count, take.reference_frame, int(clip.splats[so + 12]), p)
			var weight: float = clip.splats[so + 14]
			if weight > 0.0:
				moved += (_bone_of(take.bones, clip.bone_count, take.reference_frame, int(clip.splats[so + 13]), p) - moved) * weight
			worst = maxf(worst, moved.distance_to(Vector3(take.reference_positions[s * 3], take.reference_positions[s * 3 + 1], take.reference_positions[s * 3 + 2])))
		assert_eq(worst < 0.0001, true, "%s skinning matches ink-studio's posed positions (worst %s m)" % [take.name, worst])


# The file carries ink-studio's own posed positions for a sample of splats: pose them here and compare.
func _test_skinning(clip: SplatClip) -> void:
	var worst: float = 0.0
	for r: int in clip.reference_frames.size():
		var frame: int = clip.reference_frames[r]
		for s: int in clip.reference_splats.size():
			var o: int = clip.reference_splats[s] * SplatClipScript.STRIDE
			var p: Vector3 = Vector3(clip.splats[o], clip.splats[o + 1], clip.splats[o + 2])
			var posed: Vector3 = _bone(clip, frame, int(clip.splats[o + 12]), p)
			var weight: float = clip.splats[o + 14]
			if weight > 0.0:
				posed += (_bone(clip, frame, int(clip.splats[o + 13]), p) - posed) * weight
			var want: Vector3 = Vector3(clip.reference_positions[r][s * 3], clip.reference_positions[r][s * 3 + 1], clip.reference_positions[r][s * 3 + 2])
			worst = maxf(worst, posed.distance_to(want))
	assert_eq(worst < 0.0001, true, "skinning matches ink-studio's posed positions (worst %s m)" % worst)


func _bone(clip: SplatClip, frame: int, bone: int, p: Vector3) -> Vector3:
	return _bone_of(clip.bones, clip.bone_count, frame, bone, p)


func _bone_of(m: PackedFloat32Array, bone_count: int, frame: int, bone: int, p: Vector3) -> Vector3:
	var b: int = (frame * bone_count + bone) * SplatClipScript.BONE_STRIDE
	return Vector3(
		m[b] * p.x + m[b + 1] * p.y + m[b + 2] * p.z + m[b + 9],
		m[b + 3] * p.x + m[b + 4] * p.y + m[b + 5] * p.z + m[b + 10],
		m[b + 6] * p.x + m[b + 7] * p.y + m[b + 8] * p.z + m[b + 11])


func _test_sections() -> void:
	var plain: PackedByteArray = _tiny_clip()
	var clip: SplatClip = SplatClipScript.read(plain)
	if not assert_eq(clip != null, true, "a one-splat clip reads (%s)" % SplatClipScript.last_error):
		return
	assert_eq(clip.splat_count, 1, "one-splat clip count")
	assert_eq(clip.sections.size(), 0, "no sections")
	assert_eq(clip.has_look(), false, "no wardrobe")
	assert_eq(clip.takes.size(), 1, "one clip")

	# LOOK: one piece "hat", a piece per splat, one region "top" of two colours
	var look: PackedByteArray = "LOOK".to_ascii_buffer()
	look.append_array(_ints([1, 3]))
	look.append_array("hat".to_utf8_buffer())
	look.append_array(_ints([0, 1, 3]))
	look.append_array("top".to_utf8_buffer())
	look.append_array(_ints([2, 0, 1]))
	# CLPS: the header's clip "idle" (no frames here, reference -1), then "wave": 1 frame, a reference at frame 0
	var clips: PackedByteArray = "CLPS".to_ascii_buffer()
	clips.append_array(_ints([2, 4]))
	clips.append_array("idle".to_utf8_buffer())
	clips.append_array(_ints([0]))
	clips.append_array(_floats([30.0]))
	clips.append_array(_ints([-1, 4]))
	clips.append_array("wave".to_utf8_buffer())
	clips.append_array(_ints([1]))
	clips.append_array(_floats([30.0]))
	clips.append_array(_floats([1, 0, 0, 0, 1, 0, 0, 0, 1, 0.5, 0, 0]))
	clips.append_array(_ints([0]))
	clips.append_array(_floats([0.5, 1, 0]))

	var both: PackedByteArray = plain.duplicate()
	both.append_array(look)
	both.append_array(clips)
	clip = SplatClipScript.read(both)
	if assert_eq(clip != null, true, "a clip with LOOK and CLPS reads (%s)" % SplatClipScript.last_error):
		assert_eq(clip.sections, PackedStringArray(["LOOK", "CLPS"]), "both sections are read")
		assert_eq(clip.unknown_section, "", "nothing unknown")
		assert_eq(clip.pieces, PackedStringArray(["hat"]), "the piece is named")
		assert_eq(clip.piece_of, PackedInt32Array([0]), "the splat is of it")
		assert_eq(clip.regions.keys(), ["top"], "the region is named")
		assert_eq(clip.regions["top"], PackedInt32Array([0, 1]), "with its palette indices")
		assert_eq(clip.takes.size(), 2, "two clips")
		assert_eq(clip.takes[0].name, "idle", "the header's clip takes its name from the section")
		assert_eq(clip.takes[0].frame_count, 1, "and keeps the header's frames")
		assert_eq(clip.takes[1].name, "wave", "the second clip is named")
		assert_eq(clip.takes[1].frame_count, 1, "with its own frames")
		assert_eq(clip.takes[1].bones[9], 0.5, "and its own bones")
		assert_eq(clip.takes[1].reference_frame, 0, "its reference frame")
		assert_eq(clip.takes[1].reference_positions, PackedFloat32Array([0.5, 1, 0]), "and its posed sample")
		assert_eq(clip.find("wave") == clip.takes[1], true, "a clip is found by name")

	# the sections may come in the other order
	var swapped: PackedByteArray = plain.duplicate()
	swapped.append_array(clips)
	swapped.append_array(look)
	clip = SplatClipScript.read(swapped)
	if assert_eq(clip != null, true, "CLPS before LOOK reads (%s)" % SplatClipScript.last_error):
		assert_eq(clip.sections, PackedStringArray(["CLPS", "LOOK"]), "in the file's order")
		assert_eq(clip.pieces.size() == 1 and clip.takes.size() == 2, true, "with both read")

	var unknown: PackedByteArray = plain.duplicate()
	unknown.append_array(clips)
	unknown.append_array("WXYZ".to_ascii_buffer())
	unknown.append_array(_ints([7, 7, 7]))
	clip = SplatClipScript.read(unknown)
	if assert_eq(clip != null, true, "an unknown section does not fail the read (%s)" % SplatClipScript.last_error):
		assert_eq(clip.unknown_section, "WXYZ", "the unknown section is named")
		assert_eq(clip.sections, PackedStringArray(["CLPS"]), "the section before it is still read")
		assert_eq(clip.takes.size(), 2, "with its clips")
		assert_eq(clip.splat_count, 1, "the clip before it is intact")


# A section that is there but wrong fails the read, and says which section and why.
func _test_section_refusals() -> void:
	var plain: PackedByteArray = _tiny_clip()
	# a splat of piece 3 where there is one piece
	_refused(plain, _look_section(3, [0, 1]), "LOOK", "a splat that names a piece the file does not have")
	# a region that names palette entry 2 of 2
	_refused(plain, _look_section(0, [0, 2]), "LOOK", "a region that names a colour the palette does not have")
	# a wardrobe cut short
	var cut: PackedByteArray = _look_section(0, [0, 1])
	cut.resize(cut.size() - 4)
	_refused(plain, cut, "LOOK", "a wardrobe cut short")
	# the first clip must be the header's
	_refused(plain, _clips_section(1, 30.0, 0, "wave"), "CLPS", "a first clip with frames of its own")
	# two clips of one name
	_refused(plain, _clips_section(0, 30.0, 0, "idle"), "CLPS", "two clips of one name")
	# a reference frame the clip does not have
	_refused(plain, _clips_section(0, 30.0, 5, "wave"), "CLPS", "a reference frame out of range")
	# no frames a second
	_refused(plain, _clips_section(0, 0.0, 0, "wave"), "CLPS", "a clip with no frame rate")
	assert_eq(SplatClipScript.read(plain + _look_section(0, [0, 1]) + _clips_section(0, 30.0, 0, "wave")) != null, true,
			"and the same sections, right, are read")


func _refused(plain: PackedByteArray, section: PackedByteArray, mark: String, what: String) -> void:
	var clip: SplatClip = SplatClipScript.read(plain + section)
	assert_eq(clip == null and SplatClipScript.last_error.contains(mark), true, "%s is refused, by section (%s)" % [what, SplatClipScript.last_error])


# LOOK: one piece "hat", the one splat's piece, one region "top" of two palette indices.
func _look_section(piece: int, indices: Array) -> PackedByteArray:
	var look: PackedByteArray = "LOOK".to_ascii_buffer()
	look.append_array(_ints([1, 3]))
	look.append_array("hat".to_utf8_buffer())
	look.append_array(_ints([piece, 1, 3]))
	look.append_array("top".to_utf8_buffer())
	look.append_array(_ints([2, indices[0], indices[1]]))
	return look


# CLPS: the header's clip "idle" with [param first_frames] frames of its own (0 is right), then a clip
# of one frame at [param fps], posed for reference at [param reference].
func _clips_section(first_frames: int, fps: float, reference: int, second: String) -> PackedByteArray:
	var clips: PackedByteArray = "CLPS".to_ascii_buffer()
	clips.append_array(_ints([2, 4]))
	clips.append_array("idle".to_utf8_buffer())
	clips.append_array(_ints([first_frames]))
	clips.append_array(_floats([30.0]))
	clips.append_array(_ints([-1, 4]))
	clips.append_array(second.to_utf8_buffer())
	clips.append_array(_ints([1]))
	clips.append_array(_floats([fps]))
	clips.append_array(_floats([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]))
	clips.append_array(_ints([reference]))
	clips.append_array(_floats([0, 0, 0]))
	return clips


func _test_refusals() -> void:
	assert_eq(SplatClipScript.read("NOPE".to_ascii_buffer()) == null, true, "a short file is refused")
	var wrong: PackedByteArray = _tiny_clip()
	wrong[0] = 88
	assert_eq(SplatClipScript.read(wrong) == null, true, "a wrong mark is refused")
	assert_eq(SplatClipScript.last_error.begins_with("Not a splat file"), true, "and says why")
	var version: PackedByteArray = _tiny_clip()
	version.encode_s32(4, 9)
	assert_eq(SplatClipScript.read(version) == null, true, "an unknown version is refused")
	var cut: PackedByteArray = _tiny_clip()
	cut.resize(cut.size() - 6)
	assert_eq(SplatClipScript.read(cut) == null, true, "a file cut short is refused")
	assert_eq(SplatClipScript.load_file("res://splats/samples/none.bytes") == null, true, "a missing file is refused")


func _test_helpers() -> void:
	assert_eq(SplatClipScript.pack(0x8a4a32), 3295882.0, "pack")
	assert_eq(SplatClipScript.unpack(3295882.0), 0x8a4a32, "unpack")
	assert_eq(SplatClipScript.turn_of(0.0), 0, "no turn is set 0")
	assert_eq(SplatClipScript.turn_of(PI * 0.5), 3, "Godot's +90 degrees is the file's set 3")
	assert_eq(SplatClipScript.turn_of(-PI * 0.5), 1, "Godot's -90 degrees is the file's set 1")
	assert_eq(SplatClipScript.turn_of(PI), 2, "a half turn is set 2")
	assert_eq(SplatClipScript.turn_of(TAU + 0.1), 0, "a full turn is set 0 again")


# A version 1 clip: one splat on one bone, one frame, one reference of one sample.
func _tiny_clip() -> PackedByteArray:
	var bytes: PackedByteArray = "TCRS".to_ascii_buffer()
	bytes.append_array(_ints([1, 1, 2, 1, 1]))
	bytes.append_array(_floats([30.0]))
	bytes.append_array(_floats([0, 0, 0, 1, 0, 0, 60]))
	bytes.append_array(_ints([0x101010, 0xff8040]))
	bytes.append_array(_floats([0, 1, 0, 3, 0.01, 0, 0, SplatClipScript.pack(0xff8040), 0.01, 0, 0.01, 12, 0, 0, 0, 0]))
	bytes.append_array(_floats([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]))
	bytes.append_array(_ints([1, 1, 0, 0]))
	bytes.append_array(_floats([0, 1, 0]))
	return bytes


func _ints(values: Array) -> PackedByteArray:
	return PackedInt32Array(values).to_byte_array()


func _floats(values: Array) -> PackedByteArray:
	return PackedFloat32Array(values).to_byte_array()
