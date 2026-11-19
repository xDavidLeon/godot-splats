## Unit tests for clips and the fade between two: [method SplatClip.blend_bones], and the bones a
## [SplatInstance] writes for the clip it plays or the two it is between.
extends Object


const SplatClipScript: GDScript = preload("res://addons/splats/splat_clip.gd")
const SplatInstanceScript: GDScript = preload("res://addons/splats/splat_instance.gd")

const SEATED: String = "res://splats/samples/avatar-a.bytes"
const FIXED: String = "res://splats/samples/avatar-b.bytes"
const BONES: int = 9
const STRIDE: int = 12

var failures: int = 0


func run_tests() -> int:
	failures = 0
	_test_blend_rule()
	var clip: SplatClip = SplatClipScript.load_file(SEATED)
	if not assert_eq(clip != null, true, "avatar-a.bytes reads (%s)" % SplatClipScript.last_error):
		return failures
	_test_blend_of_two_clips(clip)
	_test_hidden_parts(clip)
	_test_instance_plays(clip)
	_test_instance_fades(clip)
	_test_one_clip_file()
	return failures


func assert_eq(actual: Variant, expected: Variant, message: String) -> bool:
	if actual != expected:
		print("FAIL: ", message, " | Expected: ", expected, " Actual: ", actual)
		failures += 1
		return false
	else:
		print("PASS: ", message)
		return true


# The rule by hand: two bones, one of them hidden in the clip being left.
func _test_blend_rule() -> void:
	var from: PackedFloat32Array = PackedFloat32Array([
		1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0,
		1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -99, 0])
	var to: PackedFloat32Array = PackedFloat32Array([
		0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 4, 8,
		3, 0, 0, 0, 3, 0, 0, 0, 3, 5, 6, 7])
	var into: PackedFloat32Array = PackedFloat32Array()
	into.resize(2 * STRIDE + 3)
	into.fill(-1.0)
	SplatClipScript.blend_bones(from, 0, to, 0, 0.25, 2, into, 3)
	assert_eq(into.slice(0, 3), PackedFloat32Array([-1, -1, -1]), "nothing is written before the offset")
	assert_eq(into.slice(3, 15), PackedFloat32Array([0.75, 0, 0, 0, 0.75, 0, 0, 0, 0.75, 0.5, 1, 2]), "a bone both clips show is a quarter of the way")
	assert_eq(into.slice(15, 27), to.slice(12, 24), "a bone the clip being left hides takes the new clip's matrix at once")
	SplatClipScript.blend_bones(to, 0, from, 0, 0.25, 2, into, 3)
	assert_eq(into.slice(15, 27), from.slice(12, 24), "and one the new clip hides is hidden at once")
	assert_eq(into[3 + 10], 3.0, "while the other bone goes on mixing")
	SplatClipScript.blend_bones(from, 0, to, 0, 0.0, 2, into, 3)
	assert_eq(into.slice(3, 15), from.slice(0, 12), "a weight of 0 is the clip being left")
	SplatClipScript.blend_bones(from, 0, to, 0, 1.0, 2, into, 3)
	assert_eq(into.slice(3, 27), to, "a weight of 1 is the new clip")


# Halfway between two of the file's clips, each visible bone is halfway between the two.
func _test_blend_of_two_clips(clip: SplatClip) -> void:
	var typing: SplatClip.Take = clip.find("typing")
	var finished: SplatClip.Take = clip.find("finished")
	var count: int = BONES * STRIDE
	var from: int = typing.frame_at(2.15) * count
	var to: int = finished.frame_at(0.15) * count
	var into: PackedFloat32Array = PackedFloat32Array()
	into.resize(count)
	SplatClipScript.blend_bones(typing.bones, from, finished.bones, to, 0.5, BONES, into, 0)
	var mixed: int = 0
	var right: bool = true
	for bone: int in BONES:
		var o: int = bone * STRIDE
		var hidden: bool = typing.bones[from + o + 10] < -30.0 or finished.bones[to + o + 10] < -30.0
		for k: int in STRIDE:
			var expected: float = finished.bones[to + o + k] if hidden else (typing.bones[from + o + k] + finished.bones[to + o + k]) / 2.0
			if absf(into[o + k] - expected) > 0.0001:
				right = false
		if not hidden:
			mixed += 1
	assert_eq(right, true, "halfway through a fade every bone is halfway, or the new clip's where a part is hidden")
	assert_eq(mixed > 4, true, "most bones are visible and were mixed (%d of %d)" % [mixed, BONES])
	var differ: bool = false
	for f: int in count * 20:
		if absf(typing.bones[f] - finished.bones[f]) > 0.001:
			differ = true
	assert_eq(differ, true, "and the two clips are not the same motion")


# The eyes blink by parking a part far below the floor: a fade across a blink must not put it in between.
func _test_hidden_parts(clip: SplatClip) -> void:
	var typing: SplatClip.Take = clip.find("typing")
	var sitting: SplatClip.Take = clip.find("sitting")
	var reading: SplatClip.Take = clip.find("reading")
	var count: int = BONES * STRIDE
	var into: PackedFloat32Array = PackedFloat32Array()
	into.resize(count)
	var hanging: int = 0
	var parked: int = 0
	var start: float = 0.0
	while start < 8.0:
		for pair: Array in [[typing, sitting], [sitting, reading], [reading, typing]]:
			var a: SplatClip.Take = pair[0]
			var b: SplatClip.Take = pair[1]
			# early and late in the fade: halfway, a part mixed with a parked one would still be out of sight
			for weight: float in [0.2, 0.9]:
				SplatClipScript.blend_bones(a.bones, a.frame_at(start + 0.15) * count, b.bones, b.frame_at(0.15) * count, weight, BONES, into, 0)
				for bone: int in BONES:
					var y: float = into[bone * STRIDE + 10]
					if y < -30.0:
						parked += 1
					elif y < -1.0:
						hanging += 1
		start += 0.05
	assert_eq(hanging, 0, "no part hangs between the room and where hidden parts are parked")
	assert_eq(parked > 0, true, "and the fades did cross hidden parts (%d)" % parked)


# An instance plays a clip by name, on the scene's clock or at a time it is given.
func _test_instance_plays(clip: SplatClip) -> void:
	var instance: SplatInstance = SplatInstanceScript.new()
	instance.asset = SEATED
	var count: int = BONES * STRIDE
	var into: PackedFloat32Array = PackedFloat32Array()
	into.resize(count + 5)
	assert_eq(instance.get_take().name, "typing", "with no clip named it plays the file's first")

	var stamp: int = instance.write_bones(2.0, into, 5, -1)
	assert_eq(into.slice(5), clip.takes[0].bones.slice(60 * count, 61 * count), "at 2 s on the clock: the first clip's frame 60, from the offset")
	assert_eq(stamp >= 0, true, "what was written has a stamp")
	into.fill(7.0)
	assert_eq(instance.write_bones(2.001, into, 5, stamp), stamp, "the same frame again has the same stamp")
	assert_eq(into[5], 7.0, "and writes nothing")
	assert_eq(instance.write_bones(2.001, into, 5, -1), stamp, "unless the caller's buffer is new")
	assert_eq(into[5] != 7.0, true, "then it writes")

	instance.time_offset = 1.0
	instance.write_bones(2.0, into, 5, -1)
	assert_eq(into.slice(5), clip.takes[0].bones.slice(90 * count, 91 * count), "the instance's offset is added to the clock")
	instance.time_offset = 0.0

	instance.play("reading")
	assert_eq(instance.get_take().name, "reading", "a clip is played by name")
	var reading_stamp: int = instance.write_bones(2.0, into, 5, stamp)
	assert_eq(reading_stamp != stamp, true, "another clip at the same frame is another stamp")
	assert_eq(into.slice(5), clip.find("reading").bones.slice(60 * count, 61 * count), "and its own bones")

	instance.play("reading", 0.5)
	instance.write_bones(2.0, into, 5, -1)
	assert_eq(into.slice(5), clip.find("reading").bones.slice(15 * count, 16 * count), "given a time of its own, the clock is not asked")
	instance.play("reading", 8.5)
	instance.write_bones(2.0, into, 5, -1)
	assert_eq(into.slice(5), clip.find("reading").bones.slice(15 * count, 16 * count), "and the clip loops")

	instance.frozen = true
	instance.write_bones(2.0, into, 5, -1)
	assert_eq(into.slice(5), clip.find("reading").bones.slice(0, count), "frozen, it holds the clip's first frame")
	instance.frozen = false

	instance.play("flying")
	assert_eq(instance.get_take().name, "typing", "a clip the file does not have plays its first")
	instance.write_bones(2.0, into, 5, -1)
	assert_eq(into.slice(5), clip.takes[0].bones.slice(60 * count, 61 * count), "with the first clip's bones")
	instance.free()


# Between two clips, the instance writes them mixed by the weight it is handed, every time.
func _test_instance_fades(clip: SplatClip) -> void:
	var instance: SplatInstance = SplatInstanceScript.new()
	instance.asset = SEATED
	var count: int = BONES * STRIDE
	var typing: SplatClip.Take = clip.find("typing")
	var finished: SplatClip.Take = clip.find("finished")
	var into: PackedFloat32Array = PackedFloat32Array()
	into.resize(count)
	var expected: PackedFloat32Array = PackedFloat32Array()
	expected.resize(count)

	instance.cross_fade("typing", 2.15, "finished", 0.15, 0.5)
	assert_eq(instance.get_take().name, "finished", "the clip it plays is the one being faded to")
	var stamp: int = instance.write_bones(9.0, into, 0, 12345)
	SplatClipScript.blend_bones(typing.bones, typing.frame_at(2.15) * count, finished.bones, finished.frame_at(0.15) * count, 0.5, BONES, expected, 0)
	assert_eq(into, expected, "halfway: the two clips at their own times, mixed by half")
	assert_eq(stamp, -1, "a fade has no stamp")
	into.fill(7.0)
	assert_eq(instance.write_bones(9.0, into, 0, stamp), -1, "so it is written again every time")
	assert_eq(into, expected, "the same bones")

	instance.cross_fade("typing", 2.15, "finished", 0.15, 0.0)
	instance.write_bones(9.0, into, 0, -1)
	SplatClipScript.blend_bones(typing.bones, typing.frame_at(2.15) * count, finished.bones, finished.frame_at(0.15) * count, 0.0, BONES, expected, 0)
	assert_eq(into, expected, "at the start it is the clip being left (hidden parts apart)")

	instance.cross_fade("typing", 2.45, "finished", 0.45, 1.0)
	assert_eq(instance.write_bones(9.0, into, 0, -1) >= 0, true, "a weight of 1 is no fade: it has a stamp again")
	assert_eq(into, finished.bones.slice(finished.frame_at(0.45) * count, (finished.frame_at(0.45) + 1) * count), "and is the new clip alone")

	instance.cross_fade("typing", 2.15, "finished", 0.15, 0.5)
	instance.play("finished", 1.0)
	assert_eq(instance.write_bones(9.0, into, 0, -1) >= 0, true, "play ends a fade")
	assert_eq(into, finished.bones.slice(30 * count, 31 * count), "the new clip at its own time")

	instance.cross_fade("flying", 0.0, "finished", 1.0, 0.5)
	instance.write_bones(9.0, into, 0, -1)
	assert_eq(into, finished.bones.slice(30 * count, 31 * count), "fading from a clip the file does not have is the new clip alone")
	instance.free()


# A file that names no clips plays its one clip whatever is asked.
func _test_one_clip_file() -> void:
	var instance: SplatInstance = SplatInstanceScript.new()
	instance.asset = FIXED
	var clip: SplatClip = instance.get_clip()
	var count: int = clip.bone_count * STRIDE
	var into: PackedFloat32Array = PackedFloat32Array()
	into.resize(count)
	instance.cross_fade("typing", 0.0, "reading", 0.0, 0.5)
	assert_eq(instance.get_take().name, "clip", "a file with one clip plays it whatever is asked")
	assert_eq(instance.write_bones(3.0, into, 0, -1) >= 0, true, "with no fade")
	assert_eq(into, clip.bones.slice(0, count), "at the time it was given")
	instance.play("")
	instance.write_bones(3.0, into, 0, -1)
	assert_eq(into, clip.bones.slice(90 * count, 91 * count), "or on the clock")
	instance.free()
