## Unit tests for the debug panel ([code]addons/splats/debug/splat_debug_panel.gd[/code]): that it is
## made only when asked for, finds the pictures in the tree, and that its keys and its controls
## change their look, their dither and their art size. These run in a debug build, so that a release
## build makes none is checked by exporting one (see the README), not here.
extends Object


const SplatSceneScript: GDScript = preload("res://addons/splats/splat_scene.gd")
const SplatDebugPanelScript: GDScript = preload("res://addons/splats/debug/splat_debug_panel.gd")

const AVERAGE: int = 0
const VOTE: int = 1

var failures: int = 0


func run_tests() -> int:
	failures = 0
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not assert_eq(tree != null and tree.root != null, true, "the tests run in a scene tree"):
		return failures
	var holder: Node3D = Node3D.new()
	tree.root.add_child(holder)
	_test_created(holder)
	_test_changes(holder)
	holder.free()
	return failures


func assert_eq(actual: Variant, expected: Variant, message: String) -> bool:
	if actual != expected:
		print("FAIL: ", message, " | Expected: ", expected, " Actual: ", actual)
		failures += 1
		return false
	else:
		print("PASS: ", message)
		return true


# It exists only where it was asked for.
func _test_created(holder: Node3D) -> void:
	assert_eq(OS.is_debug_build(), true, "the tests run in a debug build")
	assert_eq(SplatDebugPanelScript.add_to(holder, false), null, "not wanted: no panel")
	assert_eq(SplatDebugPanelScript.add_to(null), null, "nowhere to put it: no panel")
	assert_eq(holder.get_child_count(), 0, "and nothing was made")
	var panel: SplatDebugPanel = SplatDebugPanelScript.add_to(holder)
	if not assert_eq(panel != null and panel.get_parent() == holder, true, "wanted, in a debug build: a panel under the node given"):
		return
	assert_eq(panel.is_queued_for_deletion(), false, "which stays")
	assert_eq(panel.open, false, "closed until its key")
	assert_eq(panel._window.visible, false, "so nothing of it shows")
	assert_eq([panel.toggle_key, panel.look_key], [KEY_F1, KEY_V], "its keys are F1 and V")
	assert_eq(panel.get_scenes().size(), 0, "with no picture in the tree it lists none")
	assert_eq([panel.is_vote(), panel.get_dither()], [false, 0.021], "and answers with the defaults")
	panel.set_vote(true)
	panel.set_art_height(0, 100)
	panel.reset_art_sizes()
	assert_eq(panel.is_vote(), false, "and changing nothing does nothing")
	holder.remove_child(panel)
	panel.free()


# Its keys and its controls, on two pictures.
func _test_changes(holder: Node3D) -> void:
	var camera: Camera3D = Camera3D.new()
	holder.add_child(camera)
	var wide: SplatScene = _scene(holder, camera, Vector2i(640, 360))
	var square: SplatScene = _scene(holder, camera, Vector2i(200, 200))
	var panel: SplatDebugPanel = SplatDebugPanelScript.add_to(holder)
	assert_eq(panel.get_scenes(), [wide, square] as Array[SplatScene], "it finds every picture in the tree")
	assert_eq(panel._size_sliders.size(), 2, "and has a slider for each")

	_press(panel, KEY_F1)
	assert_eq([panel.open, panel._window.visible], [true, true], "F1 opens it")
	_press(panel, KEY_F1, false)
	assert_eq(panel.open, true, "letting the key go does nothing")
	_press(panel, KEY_F1, true, true)
	assert_eq(panel.open, true, "nor does the key repeating while held")
	_press(panel, KEY_F1)
	assert_eq([panel.open, panel._window.visible], [false, false], "F1 again closes it")

	assert_eq([wide.interior, square.interior], [AVERAGE, AVERAGE], "the pictures start with the average")
	_press(panel, KEY_V)
	assert_eq([wide.interior, square.interior], [VOTE, VOTE], "V gives every picture the vote, with the panel closed")
	assert_eq(panel.is_vote(), true, "and the panel says so")
	_press(panel, KEY_V)
	assert_eq([wide.interior, square.interior], [AVERAGE, AVERAGE], "V again gives the average back")
	_press(panel, KEY_TAB)
	assert_eq([panel.open, wide.interior], [false, AVERAGE], "another key is none of its business")
	panel.look_key = KEY_L
	_press(panel, KEY_V)
	_press(panel, KEY_L)
	assert_eq(wide.interior, VOTE, "the look's key can be another")
	panel.set_vote(false)

	panel.open = true
	panel._vote_button.pressed.emit()
	assert_eq([wide.interior, panel._vote_button.button_pressed, panel._average_button.button_pressed], [VOTE, true, false], "its Vote button switches the look and shows which is on")
	assert_eq(panel._dither_slider.editable, false, "and the dither, which the vote does not use, cannot be moved")
	panel._average_button.pressed.emit()
	assert_eq([square.interior, panel._dither_slider.editable], [AVERAGE, true], "its Average button switches back")

	panel._dither_slider.value = 0.1
	assert_eq([is_equal_approx(wide.dither, 0.1), is_equal_approx(square.dither, 0.1)], [true, true], "the dither slider sets every picture's dither")
	panel.set_dither(5.0)
	assert_eq(wide.dither, 0.3, "which stops at 0.3")
	panel.set_dither(-1.0)
	assert_eq(square.dither, 0.0, "and at 0")

	panel._size_sliders[0].value = 180.0
	assert_eq([wide.art_size, square.art_size], [Vector2i(320, 180), Vector2i(200, 200)], "a picture's slider sets its height and keeps its shape, and leaves the other alone")
	panel.set_art_height(1, 90)
	assert_eq(square.art_size, Vector2i(90, 90), "the second picture's too")
	panel.set_art_height(0, 20)
	assert_eq(wide.art_size, Vector2i(160, 90), "no lower than 90 art pixels")
	panel.set_art_height(0, 5000)
	assert_eq(wide.art_size, Vector2i(1280, 720), "no higher than 720")
	panel.set_art_height(7, 100)
	assert_eq([wide.art_size, square.art_size], [Vector2i(1280, 720), Vector2i(90, 90)], "a picture it does not have changes nothing")
	assert_eq(panel._size_labels[1].text.contains("90 x 90"), true, "the panel shows the size (%s)" % panel._size_labels[1].text)
	panel.reset_art_sizes()
	assert_eq([wide.art_size, square.art_size], [Vector2i(640, 360), Vector2i(200, 200)], "Reset gives each the size it had when the panel found it")

	# pictures come and go with a game's scenes
	var late: SplatScene = _scene(holder, camera, Vector2i(100, 50))
	panel.set_art_height(0, 180)
	panel.find_scenes()
	assert_eq(panel.get_scenes().size(), 3, "a picture added later is found")
	panel.reset_art_sizes()
	assert_eq([wide.art_size, late.art_size], [Vector2i(640, 360), Vector2i(100, 50)], "and Reset still knows the first one's own size")
	holder.remove_child(square)
	square.free()
	panel.find_scenes()
	assert_eq(panel.get_scenes(), [wide, late] as Array[SplatScene], "one that has gone is dropped")
	panel.set_art_height(1, 100)
	assert_eq(late.art_size, Vector2i(200, 100), "and the sliders follow the pictures that are left")


func _scene(holder: Node3D, camera: Camera3D, art: Vector2i) -> SplatScene:
	var scene: SplatScene = SplatSceneScript.new()
	scene.camera = camera
	scene.instances_root = holder
	scene.art_size = art
	holder.add_child(scene)
	return scene


func _press(panel: SplatDebugPanel, keycode: Key, pressed: bool = true, echo: bool = false) -> void:
	var key: InputEventKey = InputEventKey.new()
	key.keycode = keycode
	key.pressed = pressed
	key.echo = echo
	panel._unhandled_key_input(key)
