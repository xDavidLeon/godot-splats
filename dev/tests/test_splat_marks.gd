## Unit tests for the marks: what a [SplatMark] is, and that a [SplatScene] counts the lines it is
## given, lays them out as the shaders read them, hands them to the GPU only when they differ and
## builds nothing again for them. What they look like in the picture needs a window:
## [code]dev/tools/splat_fx_report.gd[/code].
extends Object


const SplatInstanceScript: GDScript = preload("res://addons/splats/splat_instance.gd")
const SplatSceneScript: GDScript = preload("res://addons/splats/splat_scene.gd")
const SplatMarkScript: GDScript = preload("res://addons/splats/splat_mark.gd")

const MUG: String = "res://splats/samples/mug.bytes"
const SOLID: Color = Color8(255, 217, 77)
const DOTTED: Color = Color8(244, 238, 222, 128)

var failures: int = 0


func run_tests() -> int:
	failures = 0
	_test_mark()
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


# A line, and the four sides of an outline.
func _test_mark() -> void:
	var line: SplatMark = SplatMarkScript.new(Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3.RIGHT, SOLID)
	assert_eq([line.from, line.to, line.normal, line.colour], [Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3.RIGHT, SOLID], "a line keeps what it was given")
	assert_eq(line.is_dotted(), false, "a colour with an alpha of 255 is a solid line")
	assert_eq(SplatMarkScript.new(Vector3.ZERO, Vector3.ONE, Vector3.UP, DOTTED).is_dotted(), true, "one with an alpha of 128 is dotted")
	assert_eq(SplatMarkScript.new(Vector3.ZERO, Vector3.ONE, Vector3.UP, Color8(1, 2, 3, 254)).is_dotted(), true, "and so is one with 254")
	var sides: Array[SplatMark] = SplatMarkScript.outline(Vector3(1.0, 0.5, 2.0), Vector3(0.5, 0.0, 0.0), Vector3(0.0, 0.0, 0.25), Vector3.UP, SOLID)
	assert_eq(sides.size(), 4, "an outline is four lines")
	var corners: Array[Vector3] = []
	var joined: bool = true
	for s: int in sides.size():
		corners.append(sides[s].from)
		joined = joined and sides[s].to == sides[(s + 1) % 4].from and sides[s].normal == Vector3.UP and sides[s].colour == SOLID
	assert_eq(corners, [Vector3(0.5, 0.5, 1.75), Vector3(1.5, 0.5, 1.75), Vector3(1.5, 0.5, 2.25), Vector3(0.5, 0.5, 2.25)], "round the four corners of its parallelogram")
	assert_eq(joined, true, "each ending where the next starts, on the one surface, in the one colour")


# The scene's share: counting, laying out, uploading only what differs, and never rebuilding.
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
	mug.asset = MUG
	holder.add_child(mug)
	var scene: SplatScene = SplatSceneScript.new()
	scene.camera = camera
	scene.instances_root = holder
	scene.art_size = Vector2i(64, 50)
	holder.add_child(scene)
	if not scene.is_node_ready():
		scene._ready()

	scene.draw(0.0)
	assert_eq(scene.mark_count, 0, "nothing is drawn over a picture that was given no lines")
	assert_eq(scene._marks_viewport, null, "and nothing is made for lines until there is one")
	assert_eq(scene._resolve_material.get_shader_parameter(&"mark_samples"), false, "the pixel look is told there are none")

	# a dotted grid line and an outline, as an editor would give them
	var lines: Array[SplatMark] = [SplatMarkScript.new(Vector3(-1.0, 0.012, 0.5), Vector3(1.0, 0.012, 0.5), Vector3.UP, DOTTED)]
	lines.append_array(SplatMarkScript.outline(Vector3(0.0, 0.012, 0.0), Vector3(0.5, 0.0, 0.0), Vector3(0.0, 0.0, 0.25), Vector3.UP, SOLID))
	scene.set_marks(lines)
	assert_eq(scene.mark_count, 5, "five lines given, five counted")
	scene.draw(0.0)
	assert_eq(scene.rebuild_count, 1, "lines never rebuild the scene")
	assert_eq(scene.mark_upload_count, 1, "they are handed to the GPU once")
	assert_eq(scene._resolve_material.get_shader_parameter(&"mark_samples"), true, "the pixel look is told there are lines")
	assert_eq(scene._resolve_material.get_shader_parameter(&"marks") == scene._marks_viewport.get_texture(), true, "and reads their colours from their own target")
	assert_eq(scene._marks_viewport.size, Vector2i(128, 100), "which is the samples' size, twice the art's")
	assert_eq(scene._marks_viewport.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "and is drawn while there are lines")
	assert_eq(scene._mark_cut.visible, true, "as are the quads that clear what a line covers")
	assert_eq(scene._mark_multimesh.visible_instance_count, 5, "one quad a line")
	# the texture as the shaders read it: a row a line, (from) (to) (normal) (colour, dotted). A headless
	# run keeps no texture that was updated, so the rows are read from what the scene uploads.
	var image: Image = scene._mark_texture.get_image()
	assert_eq([image.get_width(), image.get_height()], [4, 16], "a line's row is four texels; the rows start at sixteen")
	assert_eq(_xyz(_texel(scene, 0, 0)).is_equal_approx(Vector3(-1.0, 0.012, 0.5)), true, "row 0 starts with where the first line starts")
	assert_eq(_xyz(_texel(scene, 1, 0)).is_equal_approx(Vector3(1.0, 0.012, 0.5)), true, "then where it ends")
	assert_eq(_xyz(_texel(scene, 2, 0)), Vector3.UP, "then the surface's normal")
	assert_eq(_near(_texel(scene, 3, 0), Color(244 / 255.0, 238 / 255.0, 222 / 255.0, 1.0)), true, "then its colour, and 1 for a dotted line (%s)" % _texel(scene, 3, 0))
	assert_eq(_near(_texel(scene, 3, 1), Color(1.0, 217 / 255.0, 77 / 255.0, 0.0)), true, "an outline's side has its colour and 0: solid (%s)" % _texel(scene, 3, 1))
	assert_eq(_xyz(_texel(scene, 0, 4)).is_equal_approx(Vector3(-0.5, 0.012, 0.25)), true, "row 4 is the outline's last side")
	# the width: an art pixel is two samples, so with 100 samples over 2 m, 1.6 art pixels across is 0.032 m each side
	var mark: Vector2 = scene._mark_cut_material.get_shader_parameter(&"mark")
	assert_eq(is_equal_approx(mark.x, 1.6 / 50.0), true, "half a line's width is %s m: 1.6 samples" % mark.x)
	assert_eq(is_equal_approx(mark.y, 0.1), true, "and it is tested 0.1 m nearer the camera than it is")
	assert_eq(scene._mark_colour_material.get_shader_parameter(&"mark"), mark, "both of the lines' passes are given the same")

	scene.set_marks(lines)
	scene.draw(0.0)
	assert_eq(scene.mark_upload_count, 1, "the same lines again are not handed over again")
	lines[2] = SplatMarkScript.new(lines[2].from, lines[2].to, Vector3.UP, Color8(255, 217, 77, 128))
	scene.set_marks(lines)
	scene.draw(0.0)
	assert_eq(scene.mark_upload_count, 2, "a line that only became dotted is")
	assert_eq(_texel(scene, 3, 2).a, 1.0, "and its row says it is dotted now")
	lines[0].to = Vector3(2.0, 0.012, 0.5)
	scene.set_marks(lines)
	scene.draw(0.0)
	assert_eq(scene.mark_upload_count, 3, "so is one that moved")

	scene.set_marks(lines.slice(1))
	assert_eq(scene.mark_count, 4, "four lines: the outline alone")
	scene.draw(0.0)
	assert_eq(scene.mark_upload_count, 4, "fewer lines are handed over")
	assert_eq(scene._mark_multimesh.visible_instance_count, 4, "and fewer quads drawn")

	var many: Array[SplatMark] = []
	for i: int in 17:
		many.append(SplatMarkScript.new(Vector3(i, 0.0, 0.0), Vector3(i, 0.0, 1.0), Vector3.UP, SOLID))
	scene.set_marks(many)
	scene.draw(0.0)
	assert_eq(scene._mark_texture.get_image().get_height(), 32, "the rows double when there are more lines than rows")
	assert_eq(_xyz(_texel(scene, 0, 16)), Vector3(16.0, 0.0, 0.0), "and the seventeenth line is in its row")

	scene.set_marks([])
	scene.draw(0.0)
	assert_eq(scene.mark_count, 0, "no lines: the overlays are gone")
	assert_eq(scene._resolve_material.get_shader_parameter(&"mark_samples"), false, "the pixel look is told so")
	assert_eq(scene._marks_viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED, "their target is no longer drawn")
	assert_eq(scene._mark_cut.visible, false, "nor the quads over the samples")
	assert_eq(scene.rebuild_count, 1, "and through all of it the scene was built once")

	scene.art_size = Vector2i(32, 20)
	scene.set_marks(lines)
	scene.draw(0.0)
	assert_eq(scene._marks_viewport.size, Vector2i(64, 40), "a new art size is the lines' target's too")
	assert_eq(scene.status().contains("5 marks"), true, "the status line counts them (%s)" % scene.status())
	holder.free()


# Texel x of line y's row, as the scene lays the lines out for upload.
func _texel(scene: SplatScene, x: int, y: int) -> Color:
	var o: int = (y * 4 + x) * 4
	return Color(scene._mark_data[o], scene._mark_data[o + 1], scene._mark_data[o + 2], scene._mark_data[o + 3])


func _xyz(texel: Color) -> Vector3:
	return Vector3(texel.r, texel.g, texel.b)


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 1e-6 and absf(a.g - b.g) < 1e-6 and absf(a.b - b.b) < 1e-6 and absf(a.a - b.a) < 1e-6
