## Unit tests for the particles: the three sample clouds as files, the rule that moves a cloud's
## splats ([SplatParticles]), and that a [SplatScene] hands an instance's motion and the clock to the
## shader without building anything again. The files' counts and the seeds were worked out with a
## separate script (Python's struct, in single precision), not with the code under test.
## What the shader makes of them needs a window: [code]dev/tools/splat_fx_report.gd[/code].
extends Object


const SplatClipScript: GDScript = preload("res://addons/splats/splat_clip.gd")
const SplatInstanceScript: GDScript = preload("res://addons/splats/splat_instance.gd")
const SplatSceneScript: GDScript = preload("res://addons/splats/splat_scene.gd")
const SplatParticlesScript: GDScript = preload("res://addons/splats/splat_particles.gd")

const SAMPLES: String = "res://splats/samples/"
const RISE: int = 1
const DRIFT: int = 2

var failures: int = 0


func run_tests() -> int:
	failures = 0
	_test_files()
	_test_seed()
	_test_rise()
	_test_drift()
	_test_clock()
	_test_scene()
	return failures


func assert_eq(actual: Variant, expected: Variant, message: String) -> bool:
	if actual != expected:
		print("FAIL: ", message, " | Expected: ", expected, " Actual: ", actual)
		failures += 1
		return false
	else:
		print("PASS: ", message)
		return true


func assert_near(actual: float, expected: float, message: String, within: float = 1e-6) -> bool:
	return assert_eq(absf(actual - expected) <= within, true, "%s (%s, expected %s)" % [message, actual, expected])


# A cloud's file is an ordinary prop: where its particles start, and their one colour. Every particle
# is solid, and glows: it was shaded on no ramp, so lamps and dusk leave it alone.
func _test_files() -> void:
	# name, splats, palette, packed colour
	for row: Array in [["fx-steam", 38, 23, 15003636.0], ["fx-flames", 270, 24, 9097983.0], ["fx-dust", 130, 23, 11589868.0]]:
		var clip: SplatClip = SplatClipScript.load_file(SAMPLES + row[0] + ".bytes")
		if not assert_eq(clip != null, true, "%s.bytes reads (%s)" % [row[0], SplatClipScript.last_error]):
			continue
		assert_eq([clip.version, clip.splat_count, clip.palette.size(), clip.bone_count], [2, row[1], row[2], 0], "%s: a prop of %d splats" % [row[0], row[1]])
		var solid: bool = true
		var one_colour: bool = true
		var glows: bool = clip.ramp_of.size() == clip.splat_count
		for i: int in clip.splat_count:
			var o: int = i * SplatClipScript.STRIDE
			solid = solid and clip.splats[o + 3] >= 1.0
			one_colour = one_colour and clip.splats[o + 7] == row[3]
			glows = glows and clip.ramp_of[i] < 0
		assert_eq(solid, true, "%s: every particle is solid" % row[0])
		assert_eq(one_colour, true, "%s: every particle is the one colour" % row[0])
		assert_eq(glows, true, "%s: every particle glows" % row[0])
		assert_eq(clip.ramps.size(), 0, "%s: so the file has no ramp" % row[0])


# A particle's seed, against the separate script's numbers: rounded after every step, and with the
# hash's products added in before rounding, which is how the two drivers tried work it.
func _test_seed() -> void:
	assert_eq(SplatParticlesScript.fused, false, "the rule rounds after every step unless told otherwise")
	for row: Array in [
		[3.0, Vector3(0.295166015625, 0.8238525390625, 0.8330078125), Vector3(0.2947998046875, 0.8236083984375, 0.8328857421875)],
		[4.0, Vector3(0.114990234375, 0.057861328125, 0.07470703125), Vector3(0.115966796875, 0.05859375, 0.074951171875)],
		[16.0, Vector3(0.06689453125, 0.86767578125, 0.96923828125), Vector3(0.06494140625, 0.86572265625, 0.96728515625)],
		[40.0, Vector3(0.994873046875, 0.489501953125, 0.645263671875), Vector3(0.994873046875, 0.489501953125, 0.645263671875)],
		[133.0, Vector3(0.501953125, 0.921875, 0.001953125), Vector3(0.501953125, 0.921875, 0.001953125)],
		[1000.0, Vector3(0.47235107421875, 0.4337158203125, 0.799896240234375), Vector3(0.47235107421875, 0.4337158203125, 0.799896240234375)],
		[76231.0, Vector3(0.93603515625, 0.0693359375, 0.05322265625), Vector3(0.93505859375, 0.068359375, 0.05224609375)],
	]:
		var plain: Vector3 = SplatParticlesScript.seed_of(row[0])
		assert_eq((plain - row[1]).length() < 1e-7, true, "the seed of %d is %s (%s)" % [row[0], row[1], plain])
		SplatParticles.fused = true
		var fused: Vector3 = SplatParticlesScript.seed_of(row[0])
		SplatParticles.fused = false
		assert_eq((fused - row[2]).length() < 1e-7, true, "and %s with its products added in before rounding (%s)" % [row[2], fused])
	assert_eq(SplatParticlesScript.seed_of(40.0), SplatParticlesScript.seed_of(40.0), "a seed is the same every time")


# A rise: up its reach on a loop of its own, wobbling and shrinking, gone at both ends.
func _test_rise() -> void:
	# splat 0 (seed of 3) at 1.9 s with a reach of 0.5 and a wobble of 0.1, from the separate script
	var moved: Vector4 = SplatParticlesScript.offset_at(RISE, 0, 1.9, 0.5, 0.1)
	assert_near(moved.y, 0.09901595115661621, "splat 0 has climbed 0.0990 m at 1.9 s")
	assert_near(moved.x, -0.010267701931297779, "wobbled -0.0103 m along x")
	assert_near(moved.z, 0.01604234054684639, "and 0.0160 m along z")
	assert_near(moved.w, 0.8811808824539185, "and kept 0.881 of its size")
	var r: Vector3 = SplatParticlesScript.seed_of(3.0)
	assert_near(SplatParticlesScript.rise_phase(r, 1.9), 0.19803190231323242, "that is 0.198 of the way through its loop")
	assert_near(SplatParticlesScript.rise_end(r), 0.958251953125, "which it leaves at 0.958")
	assert_near(SplatParticlesScript.rise_seconds(r), 5.0777782736545625, "a loop of 5.08 s", 1e-4)

	# over a loop: hidden at both ends, never above its reach, no wider than its wobble, never larger
	var seconds: float = SplatParticlesScript.rise_seconds(r)
	var shown: int = 0
	var hidden_early: bool = true
	var hidden_late: bool = true
	var within: bool = true
	var top: float = 0.0
	var smallest: float = 1.0
	var last_y: float = -1.0
	var climbs: bool = true
	for step: int in 400:
		var t: float = 100.0 * seconds + step * seconds / 400.0 # a loop from wherever it is then
		var k: float = SplatParticlesScript.rise_phase(r, t)
		var at: Vector4 = SplatParticlesScript.offset_at(RISE, 0, t, 0.5, 0.1)
		if at.w == 0.0:
			last_y = -1.0
			continue
		shown += 1
		hidden_early = hidden_early and k >= 0.04 - 1e-6
		hidden_late = hidden_late and k <= 0.958251953125 + 1e-6
		within = within and at.y <= 0.5 and absf(at.x) <= 0.1 * k + 1e-6 and absf(at.z) <= 0.1 * k + 1e-6
		climbs = climbs and at.y > last_y
		last_y = at.y
		top = maxf(top, at.y)
		smallest = minf(smallest, at.w)
	assert_eq(shown > 340 and shown < 380, true, "it is drawn for about 0.92 of its loop (%d of 400 steps)" % shown)
	assert_eq(hidden_early, true, "never before 4% of the loop")
	assert_eq(hidden_late, true, "never after its own end")
	assert_eq(within, true, "never above its reach or wider than its wobble")
	assert_eq(climbs, true, "it only climbs while it is drawn")
	assert_near(top, 0.5 * 0.958, "its top is 0.958 of its reach", 0.002)
	assert_near(smallest, 1.0 - 0.6 * 0.958, "where it has shrunk to 0.425 of its size", 0.002)
	assert_eq(SplatParticlesScript.offset_at(RISE, 0, 1.9, 0.5, 0.0).x, 0.0, "with no wobble it goes straight up")
	assert_eq(SplatParticlesScript.offset_at(RISE, 0, 1.9, 1.0, 0.1).y, SplatParticlesScript.offset_at(RISE, 0, 1.9, 0.5, 0.1).y * 2.0, "twice the reach is twice the height")
	assert_eq(SplatParticlesScript.offset_at(RISE, 0, 1.9, 0.5, 0.1) != SplatParticlesScript.offset_at(RISE, 1, 1.9, 0.5, 0.1), true, "another splat is elsewhere in its own loop")
	assert_eq(SplatParticlesScript.offset_at(0, 0, 1.9, 0.5, 0.1), Vector4(0.0, 0.0, 0.0, 1.0), "with no motion a splat stays where it is, whole")


# A drift: a wander within its reach, in view for half of a slower cycle.
func _test_drift() -> void:
	var shown: int = 0
	var within: bool = true
	var whole: bool = true
	var furthest: Vector3 = Vector3.ZERO
	var samples: int = 0
	for splat: int in 20:
		for step: int in 200:
			var at: Vector4 = SplatParticlesScript.offset_at(DRIFT, splat, step * 0.37, 0.12)
			samples += 1
			if at.w == 0.0:
				continue
			shown += 1
			whole = whole and at.w == 1.0
			within = within and absf(at.x) <= 0.12 + 1e-6 and absf(at.y) <= 0.12 + 1e-6 and absf(at.z) <= 0.12 + 1e-6
			furthest = furthest.max(Vector3(at.x, at.y, at.z).abs())
	assert_eq(shown > samples * 0.45 and shown < samples * 0.55, true, "a mote is in view about half the time (%d of %d)" % [shown, samples])
	assert_eq(within, true, "never further than its reach along any axis")
	assert_eq(whole, true, "and never shrunk")
	assert_eq(furthest.x > 0.11 and furthest.y > 0.11 and furthest.z > 0.11, true, "it does go as far as its reach each way (%s)" % furthest)
	var r: Vector3 = SplatParticlesScript.seed_of(3.0)
	assert_eq(SplatParticlesScript.drift_shown(r, 0.0), 0.5 * sin(60.0 * r.x) + 0.5 >= 0.5, "at the start a mote shows by its seed alone")


# The clock: an instance's speed scales it, and it starts again after an hour.
func _test_clock() -> void:
	assert_eq(SplatParticlesScript.offset_at(RISE, 5, 3.0, 0.3, 0.03, 2.0), SplatParticlesScript.offset_at(RISE, 5, 6.0, 0.3, 0.03, 1.0), "at twice the speed a rise is where it would be at twice the time")
	assert_eq(SplatParticlesScript.offset_at(DRIFT, 5, 3.0, 0.3, 0.0, 0.5), SplatParticlesScript.offset_at(DRIFT, 5, 1.5, 0.3, 0.0, 1.0), "and at half the speed a drift at half")
	assert_eq(SplatParticlesScript.offset_at(RISE, 5, 3602.5, 0.3, 0.03), SplatParticlesScript.offset_at(RISE, 5, 2.5, 0.3, 0.03), "after an hour the clock starts again")
	assert_eq(SplatSceneScript.CLOCK_WRAP, 3600.0, "an hour is 3600 s")


# The scene hands each instance's motion to the shader in its row, and the clock as one number.
# Nothing about a cloud is built again: not as time passes, not when its motion changes.
func _test_scene() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not assert_eq(tree != null and tree.root != null, true, "the tests run in a scene tree"):
		return
	var holder: Node3D = Node3D.new()
	tree.root.add_child(holder)
	var camera: Camera3D = Camera3D.new()
	holder.add_child(camera)
	var mug: SplatInstance = SplatInstanceScript.new()
	mug.asset = SAMPLES + "mug.bytes"
	holder.add_child(mug)
	var steam: SplatInstance = SplatInstanceScript.new()
	steam.asset = SAMPLES + "fx-steam.bytes"
	steam.motion = RISE
	steam.motion_reach = 0.18
	steam.motion_wobble = 0.02
	holder.add_child(steam)
	var dust: SplatInstance = SplatInstanceScript.new()
	dust.asset = SAMPLES + "fx-dust.bytes"
	dust.motion = DRIFT
	dust.motion_reach = 0.12
	dust.motion_speed = 0.5
	holder.add_child(dust)
	var scene: SplatScene = SplatSceneScript.new()
	scene.camera = camera
	scene.instances_root = holder
	scene.art_size = Vector2i(64, 64)
	holder.add_child(scene)
	if not scene.is_node_ready():
		scene._ready()

	assert_eq([mug.motion, mug.motion_reach, mug.motion_wobble, mug.motion_speed], [0, 0.0, 0.0, 1.0], "an instance has no motion until it is given one")
	scene.draw(7.25)
	assert_eq(scene.rebuild_count, 1, "the first draw builds the splats")
	assert_eq(scene.splat_count, 929 + 38 + 130, "the mug and both clouds are in the picture")
	var image: Image = scene._instance_texture.get_image()
	assert_eq([image.get_width(), image.get_height()], [5, 3], "an instance's row is five texels")
	# the fifth texel as the shader reads it: (motion, reach, wobble, speed). A headless run keeps no
	# texture that was updated, so the rows are read from what the scene uploads.
	assert_eq(_texel(scene, 4, 0), Color(0.0, 0.0, 0.0, 1.0), "the mug's says no motion")
	assert_eq(_near(_texel(scene, 4, 1), Color(1.0, 0.18, 0.02, 1.0)), true, "the steam's: a rise of 0.18 m, 0.02 m wide (%s)" % _texel(scene, 4, 1))
	assert_eq(_near(_texel(scene, 4, 2), Color(2.0, 0.12, 0.0, 0.5)), true, "the dust's: a drift of 0.12 m at half speed (%s)" % _texel(scene, 4, 2))
	assert_eq([_texel(scene, 3, 1).b, _texel(scene, 3, 1).a], [0.0, 1.0], "and the texel before it still ends with its depth bias and whether it casts a shadow")
	assert_eq(scene._draw_material.get_shader_parameter(&"clock"), 7.25, "the shader's clock is the time drawn")
	# the number the rule takes: a cloud's splats are numbered on from the instances before it
	var data: PackedFloat32Array = (scene._draw_material.get_shader_parameter(&"splats") as Texture2D).get_image().get_data().to_float32_array()
	assert_eq([data[929 * 16 + 15], data[(929 + 38) * 16 + 15]], [1.0, 2.0], "the steam's first splat is number 929 in the picture, the dust's 967")

	scene.draw(3600.0 + 7.25)
	assert_eq(scene._draw_material.get_shader_parameter(&"clock"), 7.25, "after an hour the shader's clock starts again")
	for frame: int in 6:
		scene.draw(8.0 + frame / 60.0)
	assert_eq(scene.rebuild_count, 1, "particles never rebuild the scene")
	steam.motion_reach = 0.3
	steam.motion = DRIFT
	mug.motion = RISE
	scene.draw(9.0)
	assert_eq(scene.rebuild_count, 1, "nor does a change of motion")
	assert_eq(_near(_texel(scene, 4, 1), Color(2.0, 0.3, 0.02, 1.0)), true, "the steam's row follows (%s)" % _texel(scene, 4, 1))
	assert_eq(_texel(scene, 4, 0).r, 1.0, "and any instance can be given one")
	holder.free()


# Texel x of instance y's row, as the scene lays the instances out for upload.
func _texel(scene: SplatScene, x: int, y: int) -> Color:
	var o: int = (y * 5 + x) * 4
	return Color(scene._instance_data[o], scene._instance_data[o + 1], scene._instance_data[o + 2], scene._instance_data[o + 3])


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 1e-6 and absf(a.g - b.g) < 1e-6 and absf(a.b - b.b) < 1e-6 and absf(a.a - b.a) < 1e-6
