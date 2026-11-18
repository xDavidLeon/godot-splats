## Unit tests for [SplatClip], the reader of TCRS splat files. The expected numbers were read from
## the sample files with a separate script (Python's struct), not with the reader under test.
extends Object


const SplatClipScript: GDScript = preload("res://addons/splats/splat_clip.gd")

var failures: int = 0


func run_tests() -> int:
	failures = 0
	_test_prop()
	_test_lit_clip()
	_test_sections()
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
	_test_skinning(clip)


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
	var b: int = (frame * clip.bone_count + bone) * SplatClipScript.BONE_STRIDE
	var m: PackedFloat32Array = clip.bones
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
	assert_eq(clip.skipped_sections.size(), 0, "no sections")

	# LOOK: one piece "hat", a piece per splat, one region "top" of two colours
	var look: PackedByteArray = "LOOK".to_ascii_buffer()
	look.append_array(_ints([1, 3]))
	look.append_array("hat".to_utf8_buffer())
	look.append_array(_ints([0, 1, 3]))
	look.append_array("top".to_utf8_buffer())
	look.append_array(_ints([2, 0, 0]))
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
	clips.append_array(_floats([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]))
	clips.append_array(_ints([0]))
	clips.append_array(_floats([0, 0, 0]))

	var both: PackedByteArray = plain.duplicate()
	both.append_array(look)
	both.append_array(clips)
	clip = SplatClipScript.read(both)
	if assert_eq(clip != null, true, "a clip with LOOK and CLPS reads (%s)" % SplatClipScript.last_error):
		assert_eq(clip.skipped_sections, PackedStringArray(["LOOK", "CLPS"]), "both sections are read past")
		assert_eq(clip.unknown_section, "", "nothing unknown")

	var unknown: PackedByteArray = plain.duplicate()
	unknown.append_array(clips)
	unknown.append_array("WXYZ".to_ascii_buffer())
	unknown.append_array(_ints([7, 7, 7]))
	clip = SplatClipScript.read(unknown)
	if assert_eq(clip != null, true, "an unknown section does not fail the read (%s)" % SplatClipScript.last_error):
		assert_eq(clip.unknown_section, "WXYZ", "the unknown section is named")
		assert_eq(clip.skipped_sections, PackedStringArray(["CLPS"]), "the section before it is still read past")
		assert_eq(clip.splat_count, 1, "the clip before it is intact")


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
