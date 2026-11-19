## Unit tests for the tint: the rule that shades it, and that a [SplatScene] puts an instance's tint
## in its row, counts the tinted instances, draws the target that says which samples are theirs only
## while there is one, and builds nothing again when a tint is given, changed or taken away. What a tinted instance
## looks like in the picture needs a window: [code]dev/tools/splat_tint_report.gd[/code].
extends Object


const SplatInstanceScript: GDScript = preload("res://addons/splats/splat_instance.gd")
const SplatSceneScript: GDScript = preload("res://addons/splats/splat_scene.gd")
const SplatLampScript: GDScript = preload("res://addons/splats/splat_lamp.gd")

const SAMPLES: String = "res://splats/samples/"
const GREEN: Color = Color8(89, 217, 115)
const RED: Color = Color8(242, 77, 71)
# an instance's row, as the shaders read it
const ROW_TEXELS: int = 6
const TINT_TEXEL: int = 5

var failures: int = 0


func run_tests() -> int:
	failures = 0
	_test_rule()
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


# The rule the shader runs: the tint at 0.55 to 1.25 of its strength, by how light the splat is.
func _test_rule() -> void:
	var on_black: Color = SplatInstanceScript.tint_shade(GREEN, Color.BLACK)
	assert_eq(_near(on_black, Color(GREEN.r * 0.55, GREEN.g * 0.55, GREEN.b * 0.55)), true, "a black splat takes 0.55 of the tint (%s)" % on_black)
	var on_white: Color = SplatInstanceScript.tint_shade(GREEN, Color.WHITE)
	assert_eq(_near(on_white, Color(GREEN.r * 1.25, 1.0, GREEN.b * 1.25)), true, "a white one 1.25 of it, and no channel goes over 1 (%s)" % on_white)
	# how light a splat is: 0.30 of its red, 0.55 of its green, 0.15 of its blue
	var on_red: Color = SplatInstanceScript.tint_shade(Color.WHITE, Color(1.0, 0.0, 0.0))
	var on_green: Color = SplatInstanceScript.tint_shade(Color.WHITE, Color(0.0, 1.0, 0.0))
	var on_blue: Color = SplatInstanceScript.tint_shade(Color.WHITE, Color(0.0, 0.0, 1.0))
	assert_eq([is_equal_approx(on_red.r, 0.76), is_equal_approx(on_green.r, 0.935), is_equal_approx(on_blue.r, 0.655)], [true, true, true],
			"a red, a green and a blue splat weigh 0.30, 0.55 and 0.15 (%s, %s, %s)" % [on_red.r, on_green.r, on_blue.r])
	assert_eq(SplatInstanceScript.tint_shade(Color.BLACK, Color.WHITE), Color.BLACK, "a black tint is black on any splat")


# The scene's share: the row, the count, the second draw, and never rebuilding.
func _test_scene() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not assert_eq(tree != null and tree.root != null, true, "the tests run in a scene tree"):
		return
	var holder: Node3D = Node3D.new()
	tree.root.add_child(holder)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	holder.add_child(camera)
	var mug: SplatInstance = SplatInstanceScript.new()
	mug.asset = SAMPLES + "mug.bytes"
	holder.add_child(mug)
	var teapot: SplatInstance = SplatInstanceScript.new()
	teapot.asset = SAMPLES + "teapot.bytes"
	teapot.position = Vector3(0.5, 0.0, 0.25)
	holder.add_child(teapot)
	var scene: SplatScene = SplatSceneScript.new()
	scene.camera = camera
	scene.instances_root = holder
	scene.art_size = Vector2i(64, 50)
	holder.add_child(scene)
	if not scene.is_node_ready():
		scene._ready()

	assert_eq([teapot.tinted, teapot.tint, teapot.casts_shadow], [false, Color.WHITE, true], "an instance has no tint until it is given one")
	scene.draw(0.0)
	assert_eq([scene.rebuild_count, scene.instance_count, scene.tinted_count], [1, 2, 0], "two instances drawn, neither tinted")
	assert_eq(scene._tints_viewport, null, "and nothing is made for a tint until there is one")
	assert_eq(scene._resolve_material.get_shader_parameter(&"tint_samples"), false, "the pixel look is told there is none")
	var image: Image = scene._instance_texture.get_image()
	assert_eq([image.get_width(), image.get_height()], [ROW_TEXELS, 2], "an instance's row is six texels")
	# A headless run keeps no texture that was updated, so the rows are read from what the scene uploads.
	assert_eq([_texel(scene, TINT_TEXEL, 0).a, _texel(scene, TINT_TEXEL, 1).a], [0.0, 0.0], "the last says neither is tinted")
	var splats: Texture2D = scene._draw_material.get_shader_parameter(&"splats")
	var splat_data: PackedByteArray = splats.get_image().get_data()
	var looks: Texture2D = scene._draw_material.get_shader_parameter(&"looks")
	var ramps: Texture2D = scene._draw_material.get_shader_parameter(&"ramps")
	var palette: PackedVector3Array = scene._resolve_material.get_shader_parameter(&"pal")
	var untinted: PackedFloat32Array = scene._instance_data.duplicate()

	# a tint, as a caller would give it to a thing that is not there yet: green, and no shadow
	teapot.tint = GREEN
	teapot.tinted = true
	teapot.casts_shadow = false
	scene.draw(0.0)
	assert_eq([scene.rebuild_count, scene.look_update_count], [1, 0], "a tint rebuilds nothing, and is no change of look")
	assert_eq([scene.instance_count, scene.tinted_count], [2, 1], "the tinted instance is still in the picture, and counted")
	assert_eq(_near(_texel(scene, TINT_TEXEL, 1), Color(89 / 255.0, 217 / 255.0, 115 / 255.0, 1.0)), true, "its row ends with its tint, and 1: tinted (%s)" % _texel(scene, TINT_TEXEL, 1))
	assert_eq(_texel(scene, TINT_TEXEL, 0).a, 0.0, "the other instance's row still says it is not")
	assert_eq(_texel(scene, 3, 1).a, 0.0, "whether it casts a floor shadow is still what its caller says: here, no")
	assert_eq(_texel(scene, 3, 0).a, 1.0, "and the other instance's still yes")
	var same: bool = true
	for row: int in 2:
		for f: int in TINT_TEXEL * 4:
			if f != 15 and scene._instance_data[row * ROW_TEXELS * 4 + f] != untinted[row * ROW_TEXELS * 4 + f]:
				same = false
	assert_eq(same, true, "nothing else in either row changed")
	assert_eq(scene.lamp_count, 0, "a tinted thing gives no light: a lamp is a node of its own")
	assert_eq(scene._resolve_material.get_shader_parameter(&"tint_samples"), true, "the pixel look is told there is a tint")
	assert_eq(scene._tints_viewport != null and scene._resolve_material.get_shader_parameter(&"tints") == scene._tints_viewport.get_texture(), true, "and reads which samples are tinted from a target of their own")
	assert_eq(scene._tints_viewport.size, Vector2i(128, 100), "which is the samples' size, twice the art's")
	assert_eq(scene._tints_viewport.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "and is drawn while an instance is tinted")
	var quads: MultiMeshInstance3D = null
	for child: Node in scene._tints_viewport.get_children():
		if child is MultiMeshInstance3D:
			quads = child
	assert_eq(quads != null and quads.multimesh == scene._multimesh and quads.material_override == scene._tint_material, true, "by the same quads as the picture, every splat's")
	var reads_the_same: bool = true
	for parameter: StringName in [&"splats", &"instances", &"bones", &"looks", &"clock", &"view", &"size", &"lens"]:
		reads_the_same = reads_the_same and scene._tint_material.get_shader_parameter(parameter) == scene._draw_material.get_shader_parameter(parameter)
	assert_eq(reads_the_same, true, "placed by the same textures, camera and clock as the draw pass")
	assert_eq(scene.status().contains("1 tinted"), true, "the status line counts them (%s)" % scene.status())

	# red, as for a thing that does not fit
	teapot.tint = RED
	scene.draw(0.0)
	assert_eq(_near(_texel(scene, TINT_TEXEL, 1), Color(242 / 255.0, 77 / 255.0, 71 / 255.0, 1.0)), true, "another colour is in its row the next frame (%s)" % _texel(scene, TINT_TEXEL, 1))
	mug.tinted = true
	scene.draw(0.0)
	assert_eq(scene.tinted_count, 2, "two tinted instances are two")
	assert_eq(_near(_texel(scene, TINT_TEXEL, 0), Color(1.0, 1.0, 1.0, 1.0)), true, "one tinted and given no colour is white")
	mug.tinted = false
	assert_eq(scene.rebuild_count, 1, "and none of it rebuilt anything")

	# a lamp put with a tinted thing lights the picture like any lamp: leaving it out is the caller's choice
	var lamp: SplatLamp = SplatLampScript.new()
	teapot.add_child(lamp)
	scene.draw(0.0)
	assert_eq(scene.lamp_count, 1, "a lamp under a tinted instance still gives light")
	teapot.remove_child(lamp)
	lamp.free()
	scene.draw(0.0)
	assert_eq([scene.lamp_count, scene.rebuild_count], [0, 1], "until it is taken away; and a lamp rebuilds nothing either")

	# a new art size rebuilds: the tint is still there, and its quads read the new textures
	scene.art_size = Vector2i(32, 20)
	scene.draw(0.0)
	assert_eq([scene.rebuild_count, scene.tinted_count], [2, 1], "after a rebuild the tint is still counted")
	assert_eq(_texel(scene, TINT_TEXEL, 1).a, 1.0, "and still in its row")
	assert_eq(scene._tint_material.get_shader_parameter(&"splats") == scene._draw_material.get_shader_parameter(&"splats")
			and scene._tint_material.get_shader_parameter(&"size") == Vector2(64, 40), true, "and the tints' quads are placed by the new textures and size")
	assert_eq(scene._tints_viewport.size, Vector2i(64, 40), "in a target of the new size")
	scene.art_size = Vector2i(64, 50)
	scene.draw(0.0)
	splats = scene._draw_material.get_shader_parameter(&"splats")
	looks = scene._draw_material.get_shader_parameter(&"looks")
	ramps = scene._draw_material.get_shader_parameter(&"ramps")

	# no tint again
	var builds: int = scene.rebuild_count
	teapot.tinted = false
	teapot.casts_shadow = true
	scene.draw(0.0)
	assert_eq([scene.rebuild_count, scene.tinted_count], [builds, 0], "taking the tint away rebuilds nothing")
	assert_eq(scene._tints_viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED, "the tints' target is no longer drawn")
	assert_eq(scene._resolve_material.get_shader_parameter(&"tint_samples"), false, "and the pixel look is told there is none")
	assert_eq(_texel(scene, TINT_TEXEL, 1).a, 0.0, "and its row says it is not tinted")
	same = true
	for f: int in untinted.size():
		if f % (ROW_TEXELS * 4) < TINT_TEXEL * 4 and scene._instance_data[f] != untinted[f]:
			same = false
	assert_eq(same, true, "the rows are what they were before any tint")
	assert_eq(scene._draw_material.get_shader_parameter(&"splats") == splats and scene._draw_material.get_shader_parameter(&"looks") == looks
			and scene._draw_material.get_shader_parameter(&"ramps") == ramps, true, "the splats, the looks and the ramps were not made again")
	assert_eq(splats.get_image().get_data() == splat_data, true, "and the splats' data is what it was")
	assert_eq(scene._resolve_material.get_shader_parameter(&"pal") == palette, true, "as is the picture's palette: a tint is outside it")
	holder.free()


# Texel x of instance y's row, as the scene lays the instances out for upload.
func _texel(scene: SplatScene, x: int, y: int) -> Color:
	var o: int = (y * ROW_TEXELS + x) * 4
	return Color(scene._instance_data[o], scene._instance_data[o + 1], scene._instance_data[o + 2], scene._instance_data[o + 3])


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 1e-6 and absf(a.g - b.g) < 1e-6 and absf(a.b - b.b) < 1e-6 and absf(a.a - b.a) < 1e-6
