## Unit tests for the wardrobe: what [SplatClip] makes of a file's pieces and colour regions, what a
## [SplatInstance] wears, and that a [SplatScene] gives a drawn instance a new look without building
## its splats again. The counts were read from the sample file with a separate script (Python's
## struct), not with the reader under test.
extends Object


const SplatClipScript: GDScript = preload("res://addons/splats/splat_clip.gd")
const SplatInstanceScript: GDScript = preload("res://addons/splats/splat_instance.gd")
const SplatSceneScript: GDScript = preload("res://addons/splats/splat_scene.gd")

const STANDING: String = "res://splats/samples/avatar-a-stand.bytes"
const FIXED: String = "res://splats/samples/avatar-b.bytes"
const PLAIN: PackedStringArray = ["body", "top:sweater", "bottom:trousers", "shoes:shoes", "hair:bun"]

var failures: int = 0


func run_tests() -> int:
	failures = 0
	var clip: SplatClip = SplatClipScript.load_file(STANDING)
	if not assert_eq(clip != null, true, "avatar-a-stand.bytes reads (%s)" % SplatClipScript.last_error):
		return failures
	_test_dressed_palette(clip)
	_test_count_shown(clip)
	_test_look_splats(clip)
	_test_instance()
	_test_scene(clip)
	return failures


func assert_eq(actual: Variant, expected: Variant, message: String) -> bool:
	if actual != expected:
		print("FAIL: ", message, " | Expected: ", expected, " Actual: ", actual)
		failures += 1
		return false
	else:
		print("PASS: ", message)
		return true


# A region takes the ramp it is given; the others keep the file's colours.
func _test_dressed_palette(clip: SplatClip) -> void:
	var palette: PackedInt32Array = clip.dressed_palette({"top": [0x1e5a38, 0x2e8b57, 0x55b08a], "pink": PackedInt32Array([0x101010, 0x202020])})
	assert_eq(palette.size(), clip.palette.size(), "a dressed palette is as long as the file's")
	assert_eq([palette[7], palette[8], palette[9]], [0x1e5a38, 0x2e8b57, 0x55b08a], "the top's entries are the ramp given, dark to light")
	assert_eq([palette[25], palette[26]], [0x101010, 0x202020], "a ramp may be a packed array")
	var kept: bool = true
	for c: int in clip.palette.size():
		if c not in [7, 8, 9, 25, 26] and palette[c] != clip.palette[c]:
			kept = false
	assert_eq(kept, true, "every other entry keeps the file's colour")
	assert_eq(clip.palette[8], 0xd8783e, "and the file's own palette is untouched")
	assert_eq(clip.dressed_palette({}), clip.palette, "no ramps: the file's palette")
	assert_eq(clip.dressed_palette({"cape": [1, 2, 3]}), clip.palette, "a region the file does not have is passed over")
	assert_eq(clip.dressed_palette({"top": [0xffffff, 0x000000]}).is_empty(), true, "a ramp shorter than its region is refused")
	assert_eq(SplatClipScript.last_error.contains("top"), true, "and the error names the region (%s)" % SplatClipScript.last_error)
	assert_eq(clip.dressed_palette({"top": [0xff123456, 0, 0]})[7], 0x123456, "only a colour's 24 bits are kept")


# How many splats a look shows. The piece sizes were counted by the separate script.
func _test_count_shown(clip: SplatClip) -> void:
	assert_eq(clip.count_shown(PLAIN), 20534 + 5805 + 3879 + 3270 + 7338, "body, sweater, trousers, shoes and a bun")
	assert_eq(clip.count_shown(PackedStringArray(["body", "accessory:beanie", "under-hat"])), 20534 + 6316 + 2026, "body, a hat and the hair under it")
	assert_eq(clip.count_shown(PackedStringArray(["body", "hair:mohawk"])), 20534, "a piece the file does not have shows nothing")
	assert_eq(clip.count_shown(PackedStringArray()), 0, "no piece: nothing, in a file whose every splat is of a piece")
	assert_eq(clip.count_shown(clip.pieces), 74516, "every piece: every splat")
	var fixed: SplatClip = SplatClipScript.load_file(FIXED)
	assert_eq(fixed.count_shown(PackedStringArray()), fixed.splat_count, "a file with no wardrobe shows every splat")


# The records the shader gets: region colours by palette index, everything else as the file has it.
func _test_look_splats(clip: SplatClip) -> void:
	var records: PackedFloat32Array = clip.look_splats()
	assert_eq(records.size(), clip.splats.size(), "as many records as the file's")
	# splat 0's colour is 0xd7bfac, the socks' dark colour: palette entry 16
	assert_eq(clip.splats[7], 11321303.0, "the file's splat 0 keeps its packed colour")
	assert_eq(records[7], -17.0, "splat 0 names palette entry 16 as -(1 + 16)")
	var by_index: PackedInt32Array = PackedInt32Array()
	by_index.resize(clip.palette.size())
	var named: int = 0
	var right: bool = true
	var others_same: bool = true
	for i: int in clip.splat_count:
		var o: int = i * SplatClipScript.STRIDE
		for k: int in SplatClipScript.STRIDE:
			if k != 7 and records[o + k] != clip.splats[o + k]:
				others_same = false
		if records[o + 7] < 0.0:
			named += 1
			var index: int = int(-records[o + 7]) - 1
			by_index[index] += 1
			if SplatClipScript.pack(clip.palette[index]) != clip.splats[o + 7]:
				right = false
		elif records[o + 7] != clip.splats[o + 7]:
			right = false
	assert_eq(named, 18926 + 17292 + 17415 + 3879 + 490 + 2780 + 230, "the splats of the seven regions name an index")
	assert_eq(right, true, "each names the palette entry of its own colour, and the rest keep theirs")
	assert_eq(others_same, true, "nothing but the colour is changed")
	assert_eq(by_index[13] + by_index[14] + by_index[15], 3879, "the bottom's three entries carry the trousers' splats")
	assert_eq(by_index[0] + by_index[10] + by_index[22] + by_index[27], 0, "no entry outside a region is named")
	assert_eq(clip.look_splats() == records, true, "made once and kept")


# What an instance wears.
func _test_instance() -> void:
	var instance: SplatInstance = SplatInstanceScript.new()
	instance.asset = STANDING
	var clip: SplatClip = instance.get_clip()
	assert_eq(instance.look_version, 0, "nothing worn yet")
	assert_eq(instance.shows("hair:bun") and instance.shows("hair:messy"), true, "until it is dressed it shows every piece")
	assert_eq(instance.shown_splat_count(), 74516, "which is every splat")
	assert_eq(instance.look_palette(), clip.palette, "in the file's colours")

	assert_eq(instance.wear(PLAIN, {"hair": [0x1b1618, 0x2a2226, 0x4a4044]}), true, "a look is worn")
	assert_eq(instance.look_version, 1, "and the instance says its look changed")
	assert_eq(instance.shows("hair:bun"), true, "a piece of the look shows")
	assert_eq(instance.shows("hair:messy"), false, "a piece left out does not")
	assert_eq(instance.shown_splat_count(), 40826, "the look's splats")
	assert_eq(instance.look_palette()[5], 0x2a2226, "the hair's middle colour is the one given")
	assert_eq(instance.look_palette()[8], 0xd8783e, "the top keeps the file's")
	assert_eq(clip.palette[5], 0x7a3220, "the shared file is untouched")

	assert_eq(instance.wear(PLAIN, {"hair": [0x1b1618, 0x2a2226, 0x4a4044]}), true, "the same look again is accepted")
	assert_eq(instance.look_version, 1, "and changes nothing")
	assert_eq(instance.wear(PLAIN, {"hair": [0x1b1618, 0x2a2226]}), false, "a ramp of the wrong length is refused")
	assert_eq(instance.look_version, 1, "changing nothing")
	assert_eq(instance.look_palette()[5], 0x2a2226, "the look worn before stays")

	# a second instance of the same file wears something else
	var other: SplatInstance = SplatInstanceScript.new()
	other.asset = STANDING
	other.wear(PackedStringArray(["body", "hair:messy"]))
	assert_eq(other.shows("hair:messy") and not other.shows("hair:bun"), true, "another instance of the file wears its own pieces")
	assert_eq(other.look_palette()[5], 0x7a3220, "in its own colours")
	assert_eq(instance.shows("hair:bun"), true, "and the first keeps its own")

	instance.wear_everything()
	assert_eq(instance.look_version, 2, "undressing is a change of look")
	assert_eq(instance.shown_splat_count(), 74516, "back to every splat")
	assert_eq(instance.look_palette(), clip.palette, "in the file's colours")

	# a file with no wardrobe ignores it
	var fixed: SplatInstance = SplatInstanceScript.new()
	fixed.asset = FIXED
	assert_eq(fixed.wear(PLAIN, {"hair": [1, 2]}), true, "a file with no wardrobe takes any look")
	assert_eq(fixed.shown_splat_count(), 35860, "and shows every splat")
	assert_eq(fixed.look_palette(), fixed.get_clip().palette, "in its own colours")
	instance.free()
	other.free()
	fixed.free()


# A drawn instance changes its look, and the scene writes that instance's row and ramps, not its splats.
func _test_scene(clip: SplatClip) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not assert_eq(tree != null and tree.root != null, true, "the tests run in a scene tree"):
		return
	var holder: Node3D = Node3D.new()
	tree.root.add_child(holder)
	var camera: Camera3D = Camera3D.new()
	holder.add_child(camera)
	var first: SplatInstance = SplatInstanceScript.new()
	first.asset = STANDING
	holder.add_child(first)
	var second: SplatInstance = SplatInstanceScript.new()
	second.asset = STANDING
	holder.add_child(second)
	second.wear(PLAIN)
	var scene: SplatScene = SplatSceneScript.new()
	scene.camera = camera
	scene.instances_root = holder
	scene.art_size = Vector2i(64, 64)
	holder.add_child(scene)
	if not scene.is_node_ready():
		scene._ready()

	scene.draw(0.0)
	assert_eq(scene.rebuild_count, 1, "the first draw builds the splats")
	assert_eq(scene.splat_count, 74516 * 2, "every splat of both wardrobes is in the picture's texture")
	assert_eq(scene.shown_splat_count(), 74516 + 40826, "and the pieces worn are what shows")
	assert_eq(scene.look_update_count, 0, "no look has changed since")
	var width: int = scene._look_width
	assert_eq(width, 31, "a look's row is as wide as the longer of pieces (13) and palette (31)")
	# the rows as the shader reads them: texel n is (piece n shows, palette colour n)
	assert_eq(_shown_row(scene, 0, clip), clip.pieces, "the first instance's row shows every piece")
	assert_eq(_shown_row(scene, 1, clip), PackedStringArray(["shoes:shoes", "bottom:trousers", "top:sweater", "body", "hair:bun"]), "the second's shows the look's pieces")
	assert_eq(scene._look_data[(1 * width + 8) * 4 + 1], SplatClipScript.pack(0xd8783e), "with the file's top colour")
	# the tag each splat carries: its instance, and its piece
	var last: int = (74516 * 2 - 1) * SplatClipScript.STRIDE
	var data: PackedFloat32Array = (scene._draw_material.get_shader_parameter(&"splats") as Texture2D).get_image().get_data().to_float32_array()
	assert_eq(data[15], 0.0 + 4096.0 * 1, "the first splat is instance 0's, of piece 0")
	assert_eq(data[last + 15], 1.0 + 4096.0 * 13, "the last splat is instance 1's, of piece 12")
	assert_eq(data[7], -17.0, "and a region's colour is a palette index")
	var first_ramp_before: float = scene._ramp_data[0]

	# the second instance changes its sweater, its hair and its hair's colour
	second.wear(PackedStringArray(["body", "top:stripes", "bottom:trousers", "shoes:shoes", "hair:messy"]),
			{"top": [0x1e5a38, 0x2e8b57, 0x55b08a]})
	scene.draw(0.0)
	assert_eq(scene.rebuild_count, 1, "a change of look rebuilds nothing")
	assert_eq(scene.look_update_count, 1, "it is written as a look")
	assert_eq(_shown_row(scene, 1, clip), PackedStringArray(["shoes:shoes", "bottom:trousers", "top:stripes", "body", "hair:messy"]), "the row shows the new pieces")
	assert_eq(scene._look_data[(1 * width + 8) * 4 + 1], SplatClipScript.pack(0x2e8b57), "and the new top colour")
	assert_eq(_shown_row(scene, 0, clip), clip.pieces, "the first instance's row is as it was")
	assert_eq(scene._look_data[(0 * width + 8) * 4 + 1], SplatClipScript.pack(0xd8783e), "with the file's top colour")
	# the ramps it is lit along follow: the file's ramp 5 is the top's (palette 7, 8, 9)
	assert_eq(clip.ramps[5], PackedInt32Array([7, 8, 9]), "ramp 5 is the top's")
	var ramp_width: int = scene._ramp_width
	var second_first: int = scene._first_ramp[1]
	assert_eq(scene._ramp_data[((second_first + 5) * ramp_width + 1) * 4], SplatClipScript.pack(0x2e8b57), "the second instance is lit along its new top ramp")
	assert_eq(scene._ramp_data[((scene._first_ramp[0] + 5) * ramp_width + 1) * 4], SplatClipScript.pack(0xd8783e), "and the first along the file's")
	assert_eq(scene._ramp_data[0], first_ramp_before, "its other rows untouched")
	assert_eq(scene.shown_splat_count(), 74516 + 20534 + 5805 + 3879 + 3270 + 7745, "the count shown follows the look")

	scene.draw(0.0)
	assert_eq(scene.look_update_count, 1, "a frame with no change of look writes none")
	second.wear(PackedStringArray(["body", "top:stripes", "bottom:trousers", "shoes:shoes", "hair:messy"]),
			{"top": [0x1e5a38, 0x2e8b57, 0x55b08a]})
	scene.draw(0.0)
	assert_eq(scene.look_update_count, 1, "nor does wearing the same look again")
	assert_eq(scene.rebuild_count, 1, "and still one build")
	holder.free()


func _shown_row(scene: SplatScene, instance: int, clip: SplatClip) -> PackedStringArray:
	var shown: PackedStringArray = PackedStringArray()
	for p: int in clip.pieces.size():
		if scene._look_data[(instance * scene._look_width + p) * 4] > 0.5:
			shown.append(clip.pieces[p])
	return shown
