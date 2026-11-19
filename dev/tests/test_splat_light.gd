## Unit tests for [SplatLight]: lamps, dusk and ground shadows, as rules in script. The first three are
## counterparts of the lighting tests of the Unity renderer this was ported from. They run on small
## assets built here (a flat floor, a wall with a face and a back), and again on a room's own ground
## and wall when [code]floor.bytes[/code] and [code]wall.bytes[/code] were handed to
## [code]dev/make_project.py --samples[/code].
## [br][br]
## What the scene's shaders draw is not checked here (a headless run draws nothing):
## [code]dev/tools/splat_light_report.gd[/code] compares their picture with these rules.
extends Object


const FLOOR_PATH: String = "res://splats/samples/floor.bytes"
const WALL_PATH: String = "res://splats/samples/wall.bytes"
var NO_LAMPS: PackedVector4Array = PackedVector4Array()
var NO_STRENGTHS: PackedFloat32Array = PackedFloat32Array()

var failures: int = 0


func run_tests() -> int:
	failures = 0
	_test_bake_is_given_back()
	_test_lamp_lifts_near_splats(_make_floor(), "a built floor")
	_test_lamp_lights_facing_side(_make_wall(), "a built wall", 300)
	_test_dusk_is_one_step_down(_make_floor(), "a built floor")
	_test_no_ramp_keeps_its_colour()
	_test_placed_asset()
	_test_floor_shadow()
	_test_light_texels()
	if FileAccess.file_exists(FLOOR_PATH) and FileAccess.file_exists(WALL_PATH):
		var ground: SplatClip = SplatClip.load_file(FLOOR_PATH)
		var wall: SplatClip = SplatClip.load_file(WALL_PATH)
		_test_lamp_lifts_near_splats(ground, "floor.bytes")
		_test_lamp_lights_facing_side(wall, "wall.bytes", 500)
		_test_dusk_is_one_step_down(ground, "floor.bytes")
	else:
		print("NOTE: floor.bytes and wall.bytes are not in splats/samples; the three lighting tests ran on built assets only")
	return failures


func check(passed: bool, message: String) -> bool:
	if passed:
		print("PASS: ", message)
	else:
		print("FAIL: ", message)
		failures += 1
	return passed


# How light a packed colour is: the sum of its three channels.
static func _light_of(packed: float) -> int:
	var c: int = roundi(packed)
	return (c & 255) + ((c >> 8) & 255) + ((c >> 16) & 255)


# region Assets built here
# A clip from positions, normals, a ramp for each splat (or -1) and how bright each came out. Its
# palette is the background, then two ramps: five greys and three browns, dark to light.
static func _make(positions: PackedVector3Array, normals: PackedVector3Array, ramp_of: PackedInt32Array, brightness: PackedFloat32Array) -> SplatClip:
	var clip: SplatClip = SplatClip.new()
	clip.version = SplatClip.PROP_VERSION
	clip.splat_count = positions.size()
	clip.palette = PackedInt32Array([0x101010, 0x303030, 0x505050, 0x808080, 0xb0b0b0, 0xe0e0e0, 0x402010, 0x805030, 0xc09060, 0xffee88])
	clip.ramps = [PackedInt32Array([1, 2, 3, 4, 5]), PackedInt32Array([6, 7, 8])]
	clip.ramp_of = ramp_of
	clip.splats.resize(clip.splat_count * SplatClip.STRIDE)
	clip.normals.resize(clip.splat_count * 3)
	var colours: PackedFloat32Array = PackedFloat32Array()
	colours.resize(clip.splat_count)
	for i: int in clip.splat_count:
		var o: int = i * SplatClip.STRIDE
		clip.splats[o] = positions[i].x
		clip.splats[o + 1] = positions[i].y
		clip.splats[o + 2] = positions[i].z
		clip.splats[o + 3] = 3.0
		clip.normals[i * 3] = normals[i].x
		clip.normals[i * 3 + 1] = normals[i].y
		clip.normals[i * 3 + 2] = normals[i].z
		if ramp_of[i] < 0:
			colours[i] = SplatClip.pack(clip.palette[9]) # a glowing splat
		else:
			var ramp: PackedInt32Array = clip.ramps[ramp_of[i]]
			colours[i] = SplatClip.pack(clip.palette[ramp[clampi(floori(brightness[i] * ramp.size()), 0, ramp.size() - 1)]])
		clip.splats[o + 7] = colours[i]
	for k: int in SplatClip.TURNS:
		clip.colour_sets.append(colours)
		clip.brightness.append(brightness)
	return clip


# A flat floor 8 m square on y = 0, a splat every 10 cm, lit near the top of its ramps with a wobble,
# as a baked floor is; every 50th splat glows.
static func _make_floor() -> SplatClip:
	var positions: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var ramp_of: PackedInt32Array = PackedInt32Array()
	var brightness: PackedFloat32Array = PackedFloat32Array()
	for z: int in 81:
		for x: int in 81:
			var i: int = positions.size()
			positions.append(Vector3(-4.0 + x * 0.1, 0.0, -4.0 + z * 0.1))
			normals.append(Vector3.UP)
			ramp_of.append(-1 if i % 50 == 49 else (x / 8 + z / 8) % 2)
			brightness.append(0.62 + 0.3 * absf(sin(i * 0.37)))
	return _make(positions, normals, ramp_of, brightness)


# A wall 6 m wide and 3 m high: its face on z = 0 looking along +z, and its back 20 cm behind,
# looking the other way. Both are lit in the middle of their ramps.
static func _make_wall() -> SplatClip:
	var positions: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var ramp_of: PackedInt32Array = PackedInt32Array()
	var brightness: PackedFloat32Array = PackedFloat32Array()
	for side: int in 2:
		for y: int in 31:
			for x: int in 61:
				positions.append(Vector3(-3.0 + x * 0.1, y * 0.1, -0.2 * side))
				normals.append(Vector3(0.0, 0.0, 1.0 - 2.0 * side))
				ramp_of.append(0)
				brightness.append(0.55)
	return _make(positions, normals, ramp_of, brightness)
# endregion


# region The three lighting tests
# A lamp lifts the splats near it, and only those.
func _test_lamp_lifts_near_splats(ground: SplatClip, what: String) -> void:
	var data: PackedFloat32Array = ground.splats.duplicate()
	check(SplatLight.relight(ground, 0, Transform3D.IDENTITY, NO_LAMPS, NO_STRENGTHS, 0, data) == 0, "%s: no lamp and full daylight change nothing" % what)
	check(data == ground.splats, "%s: no lamp and full daylight is the bake" % what)

	# By day a floor is already at the top of its ramp, so the lamp shows at dusk: against the dusk alone.
	var dusk: PackedFloat32Array = ground.splats.duplicate()
	SplatLight.relight(ground, 0, Transform3D.IDENTITY, NO_LAMPS, NO_STRENGTHS, 1, dusk)
	var lamps: PackedVector4Array = PackedVector4Array([Vector4(0.0, 1.0, 0.0, 2.0)])
	var strengths: PackedFloat32Array = PackedFloat32Array([0.6])
	SplatLight.relight(ground, 0, Transform3D.IDENTITY, lamps, strengths, 1, data)
	var lifted: int = 0
	var far_changed: int = 0
	var darkened: int = 0
	for i: int in ground.splat_count:
		var o: int = i * SplatClip.STRIDE
		var from_lamp: Vector3 = Vector3(ground.splats[o], ground.splats[o + 1] - 1.0, ground.splats[o + 2])
		var before: int = _light_of(dusk[o + 7])
		var after: int = _light_of(data[o + 7])
		if from_lamp.length_squared() >= 4.0 and after != before:
			far_changed += 1
		if after < before:
			darkened += 1
		if after > before:
			lifted += 1
	check(far_changed == 0, "%s: a splat out of the lamp's reach keeps its colour (%d changed)" % [what, far_changed])
	check(darkened == 0, "%s: a lamp never darkens (%d darkened)" % [what, darkened])
	check(lifted > 100, "%s: the floor under the lamp steps back up its ramp (%d lifted)" % [what, lifted])


# A lamp lights the side that faces it. The face is on z = 0 and looks along +z; the body stands behind it.
func _test_lamp_lights_facing_side(wall: SplatClip, what: String, at_least: int) -> void:
	var in_front: int = _face_lifted(wall, 1.0)
	var behind: int = _face_lifted(wall, -1.2)
	check(in_front > at_least, "%s: a lamp in front lights the wall's face (%d lifted)" % [what, in_front])
	check(in_front > behind * 2, "%s: a lamp behind the wall lights that face far less (%d against %d)" % [what, behind, in_front])


func _face_lifted(wall: SplatClip, lamp_z: float) -> int:
	var data: PackedFloat32Array = wall.splats.duplicate()
	SplatLight.relight(wall, 0, Transform3D.IDENTITY, PackedVector4Array([Vector4(0.0, 1.5, lamp_z, 3.0)]), PackedFloat32Array([0.6]), 0, data)
	var lifted: int = 0
	for i: int in wall.splat_count:
		var o: int = i * SplatClip.STRIDE + 7
		if wall.normals[i * 3 + 2] > 0.9 and _light_of(data[o]) > _light_of(wall.splats[o]):
			lifted += 1
	return lifted


# Dusk takes every splat one step down its own ramp.
func _test_dusk_is_one_step_down(ground: SplatClip, what: String) -> void:
	var data: PackedFloat32Array = ground.splats.duplicate()
	var changed: int = SplatLight.relight(ground, 0, Transform3D.IDENTITY, NO_LAMPS, NO_STRENGTHS, 1, data)
	check(changed > ground.splat_count / 2, "%s: dusk changes most splats (%d of %d)" % [what, changed, ground.splat_count])
	var wrong: int = 0
	for i: int in ground.splat_count:
		var expected: float = ground.splats[i * SplatClip.STRIDE + 7]
		if ground.ramp_of[i] >= 0:
			var ramp: PackedInt32Array = ground.ramps[ground.ramp_of[i]]
			var baked: int = mini(ramp.size() - 1, floori(ground.brightness[0][i] * ramp.size()))
			expected = SplatClip.pack(ground.palette[ramp[maxi(0, baked - 1)]])
		if data[i * SplatClip.STRIDE + 7] != expected:
			wrong += 1
	check(wrong == 0, "%s: every splat is one step down its own ramp (%d are not)" % [what, wrong])
# endregion


# region More of the rules
# The light data gives back every colour of every bake, for the sample files.
func _test_bake_is_given_back() -> void:
	for file: String in ["desk-set", "mug", "teapot", "avatar-b"]:
		var clip: SplatClip = SplatClip.load_file("res://splats/samples/%s.bytes" % file)
		if not check(clip != null and clip.has_light(), "%s.bytes carries light data" % file):
			continue
		check(clip.brightness.size() == (SplatClip.TURNS if clip.is_prop() else 1), "%s has a bake for each way it can stand" % file)
		var lit: int = 0
		var wrong: int = 0
		for k: int in clip.brightness.size():
			for i: int in clip.splat_count:
				if clip.ramp_of[i] < 0:
					continue
				lit += 1
				var baked: float = clip.colour_sets[k][i] if clip.is_prop() else clip.splats[i * SplatClip.STRIDE + 7]
				if SplatLight.colour_at(clip, i, clip.brightness[k][i]) != baked:
					wrong += 1
		check(wrong == 0, "%s: a ramp and a brightness give back every baked colour (%d of %d do not)" % [file, wrong, lit])
		check(lit * 4 > clip.splat_count * clip.brightness.size() * 3, "%s: most splats are shaded on a ramp (%d)" % [file, lit])


func _test_no_ramp_keeps_its_colour() -> void:
	var ground: SplatClip = _make_floor()
	var data: PackedFloat32Array = ground.splats.duplicate()
	SplatLight.relight(ground, 0, Transform3D.IDENTITY, PackedVector4Array([Vector4(0.0, 0.5, 0.0, 8.0)]), PackedFloat32Array([1.5]), 3, data)
	var glowing: int = 0
	var kept: int = 0
	for i: int in ground.splat_count:
		if ground.ramp_of[i] < 0:
			glowing += 1
			if data[i * SplatClip.STRIDE + 7] == ground.splats[i * SplatClip.STRIDE + 7]:
				kept += 1
	check(glowing > 100 and kept == glowing, "a splat with no ramp keeps its colour under a lamp and at dusk (%d of %d)" % [kept, glowing])

	var unlit: SplatClip = SplatClip.load_file("res://splats/samples/mug.bytes")
	unlit.ramps = []
	data = unlit.splats.duplicate()
	check(SplatLight.relight(unlit, 0, Transform3D.IDENTITY, NO_LAMPS, NO_STRENGTHS, 2, data) == 0 and data == unlit.splats, "an asset with no light data keeps its colours")

	var deep: PackedFloat32Array = ground.splats.duplicate()
	SplatLight.relight(ground, 0, Transform3D.IDENTITY, NO_LAMPS, NO_STRENGTHS, 99, deep)
	var darkest: int = 0
	for i: int in ground.splat_count:
		if ground.ramp_of[i] >= 0 and deep[i * SplatClip.STRIDE + 7] == SplatClip.pack(ground.palette[ground.ramps[ground.ramp_of[i]][0]]):
			darkest += 1
	check(darkest == ground.splat_count - glowing, "dusk stops at the dark end of a ramp")


# The lamp is in the world: an asset that is moved or turned is lit where it stands, by its turned normals.
func _test_placed_asset() -> void:
	var ground: SplatClip = _make_floor()
	var lamps: PackedVector4Array = PackedVector4Array([Vector4(10.0, 1.0, 0.0, 2.0)])
	var strengths: PackedFloat32Array = PackedFloat32Array([0.6])
	var data: PackedFloat32Array = ground.splats.duplicate()
	check(SplatLight.relight(ground, 0, Transform3D.IDENTITY, lamps, strengths, 0, data) == 0, "a lamp 10 m away lights nothing")
	var moved: Transform3D = Transform3D(Basis.IDENTITY, Vector3(10.0, 0.0, 0.0))
	check(SplatLight.relight(ground, 0, moved, lamps, strengths, 1, data) > 100, "the same lamp lights the floor once it is moved under it")

	var wall: SplatClip = _make_wall()
	var half_turn: Transform3D = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var facing: PackedFloat32Array = wall.splats.duplicate()
	var turned: PackedFloat32Array = wall.splats.duplicate()
	var lamp: PackedVector4Array = PackedVector4Array([Vector4(0.0, 1.5, 1.0, 3.0)])
	var face: int = 0
	var face_turned: int = 0
	SplatLight.relight(wall, 0, Transform3D.IDENTITY, lamp, strengths, 0, facing)
	SplatLight.relight(wall, 0, half_turn, lamp, strengths, 0, turned)
	for i: int in wall.splat_count:
		var o: int = i * SplatClip.STRIDE + 7
		if wall.normals[i * 3 + 2] > 0.9:
			face += 1 if facing[o] != wall.splats[o] else 0
			face_turned += 1 if turned[o] != wall.splats[o] else 0
	check(face > face_turned * 2, "a wall turned away from the lamp has its face lit far less (%d against %d)" % [face_turned, face])
	check(is_equal_approx(SplatLight.added_by_lamps(Vector3.ZERO, Vector3.UP, PackedVector4Array([Vector4(0.0, 1.5, 0.0, 3.0)]), PackedFloat32Array([0.9])), 0.225),
			"a lamp of strength 0.9 that reaches 3 m adds 0.225 to a floor 1.5 m under it")
	check(is_equal_approx(SplatLight.added_by_lamps(Vector3.ZERO, Vector3.DOWN, PackedVector4Array([Vector4(0.0, 1.5, 0.0, 3.0)]), PackedFloat32Array([0.9])), 0.045),
			"and a fifth of that to a surface that faces away")


# A ground shadow falls away from the sun, and follows the thing.
func _test_floor_shadow() -> void:
	# one splat 1 m up, in the middle of a 10 cm cell; the sun up and towards -x: the shadow lands 1 m towards +x
	var pole: SplatClip = _make(PackedVector3Array([Vector3(0.05, 1.0, 0.05)]), PackedVector3Array([Vector3.UP]), PackedInt32Array([0]), PackedFloat32Array([0.5]))
	var sun: Vector3 = Vector3(-1.0, 1.0, 0.0)
	var cells: Dictionary[Vector2i, bool] = {}
	SplatLight.shadow_cells(pole, Transform3D.IDENTITY, sun, 0.1, cells)
	check(cells.keys() == [Vector2i(10, 0)], "a splat 1 m up shades the cell 1 m away from the sun (%s)" % str(cells.keys()))

	cells.clear()
	SplatLight.shadow_cells(pole, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 2.0)), sun, 0.1, cells)
	check(cells.keys() == [Vector2i(10, 20)], "moved 2 m along z, its shadow moves with it (%s)" % str(cells.keys()))

	cells.clear()
	SplatLight.shadow_cells(pole, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), sun, 0.1, cells, 1.0)
	check(cells.keys() == [Vector2i(10, 0)], "a floor 1 m up, under a thing 1 m above it, is shaded the same (%s)" % str(cells.keys()))

	cells.clear()
	SplatLight.shadow_cells(pole, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.99, 0.0)), sun, 0.1, cells)
	check(cells.is_empty(), "something lying on the floor casts nothing")

	cells.clear()
	SplatLight.shadow_cells(SplatClip.load_file("res://splats/samples/desk-set.bytes"), Transform3D.IDENTITY, Vector3(-0.3, 0.75, 0.6), 0.05, cells)
	check(cells.size() > 200, "a desk set shades a few hundred 5 cm cells (%d)" % cells.size())


func _test_light_texels() -> void:
	var clip: SplatClip = SplatClip.load_file("res://splats/samples/desk-set.bytes")
	var texels: PackedFloat32Array = clip.light_texels()
	check(texels.size() == clip.splat_count * 4, "a clip hands the shader four floats a splat")
	var i: int = clip.splat_count / 2
	check(texels[i * 4] == clip.normals[i * 3] and texels[i * 4 + 2] == clip.normals[i * 3 + 2] and texels[i * 4 + 3] == clip.ramp_of[i],
			"a splat's normal and ramp are in them")
	var bare: SplatClip = SplatClip.load_file("res://splats/samples/mug.bytes")
	bare.ramps = []
	check(bare.light_texels()[3] == -1.0 and bare.light_texels()[bare.splat_count * 4 - 1] == -1.0, "a clip with no light data says every splat keeps its colour")
