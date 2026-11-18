## The splat picture in a transparent, borderless, always-on-top window that only catches the mouse
## where the picture is drawn: an avatar at its desk, sitting on the desktop.
## Clicks beside it go to whatever is behind. Drag the avatar to move the window, turn the mouse
## wheel over it to make it bigger or smaller, and press Escape or right-click to close it.
##
## There are two ways it decides where the mouse is caught ([member click_through]; the C key, or
## [code]-- --click=pixel[/code] or [code]--click=outline[/code] on the command line, switches):
## by the pixel under the cursor, or by an outline round the picture.
##
## The project must allow it (dev/make_project.py --overlay makes one that does): set
## [code]display/window/per_pixel_transparency/allowed[/code] and
## [code]display/window/size/transparent[/code] to true (and borderless, to have no frame at start).
## Without them the scene still runs, in an ordinary opaque window, and says so.
# In Unity, this takes native calls (DwmExtendFrameIntoClientArea, WS_EX_LAYERED and a hit test),
# which a plugin such as UniWindowController supplies. Godot has the pieces built in: a transparent
# window, a flag that lets the mouse through the whole window, and a polygon outside which it passes.
extends Node


## How the window decides where it catches the mouse.
enum ClickThrough {
	## By the pixel under the cursor, each frame: the whole window lets the mouse through unless
	## that pixel of the picture is covered. Exact to the art pixel, and nothing is cut off what is
	## drawn. This is what UniWindowController does in Unity.
	PIXEL,
	## By a polygon round the picture, handed to the operating system. It needs a margin, because
	## Windows also cuts what the window draws to that polygon, so clicks in the margin are caught.
	OUTLINE,
}


# region State
## What the camera looks at, in metres.
@export var camera_target: Vector3 = Vector3(0.0, 0.5, 0.42)
## How far the camera stands from it.
@export var camera_distance: float = 6.0
## The camera's pitch above the floor and yaw about y, in radians, as ink-studio counts them.
@export var camera_pitch: float = 0.42
@export var camera_yaw: float = PI + 0.5
## Screen pixels to an art pixel: the window's size. Whole numbers only, so art pixels stay square.
@export_range(1, 8) var pixel_scale: int = 3:
	set(value):
		pixel_scale = clampi(value, 1, 8)
		if is_node_ready():
			_resize()
## Where the mouse is caught: see [enum ClickThrough].
@export var click_through: ClickThrough = ClickThrough.PIXEL:
	set(value):
		click_through = value
		if is_node_ready():
			_apply_click_through()
## Seconds between two readings of the picture for the mouse: its alpha, or its outline.
@export var outline_interval: float = 0.1
## Art pixels the outline is drawn outside the picture. Windows also cuts what the window draws to
## the outline, and the outline is a simplified polygon: with no margin it shaves pixels off the
## picture's edge.
@export_range(1, 8) var outline_margin: int = 2

## Left clicks the window has caught since it opened.
var clicks_caught: int = 0
## Turns of the mouse wheel the window has caught since it opened.
var wheel_caught: int = 0

@onready var _camera: Camera3D = %Camera
@onready var _scene: SplatScene = %SplatScene
@onready var _picture: TextureRect = %Picture
@onready var _notice: Label = %Notice

var _next_outline: float = 0.0
var _covered: Image = null
var _catching: bool = true
var _dragging: bool = false
var _grab: Vector2i = Vector2i.ZERO
# endregion


# region Lifecycle
func _ready() -> void:
	var cp: float = cos(camera_pitch)
	var eye: Vector3 = camera_target + camera_distance * Vector3(cp * sin(camera_yaw), sin(camera_pitch), cp * cos(camera_yaw))
	_camera.look_at_from_position(eye, camera_target, Vector3.UP)
	_picture.texture = _scene.get_picture()

	var window: Window = get_window()
	_resize()
	window.borderless = true
	window.always_on_top = true
	window.transparent = true
	get_viewport().transparent_bg = true
	_notice.visible = not is_transparent()
	if _notice.visible:
		_notice.text = "Not transparent: the project does not allow it.\nSee the top of splat_overlay.gd."
	# started with -- --selftest=<folder>, it checks itself and quits (splats/tools/splat_overlay_test.gd)
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--click=outline":
			click_through = ClickThrough.OUTLINE
		elif argument == "--click=pixel":
			click_through = ClickThrough.PIXEL
	_apply_click_through()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--selftest="):
			add_child((load("res://splats/tools/splat_overlay_test.gd") as GDScript).new())


func _process(delta: float) -> void:
	if _scene.rebuild_count == 0:
		return
	_next_outline -= delta
	if _next_outline <= 0.0:
		_next_outline = outline_interval
		if click_through == ClickThrough.PIXEL:
			_covered = _scene.get_picture().get_image()
		else:
			_update_outline()
	if click_through == ClickThrough.PIXEL:
		_update_catching()


func _input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		if button.pressed:
			clicks_caught += 1
			_grab = DisplayServer.mouse_get_position() - get_window().position
	elif button != null and button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
		wheel_caught += 1
		pixel_scale += 1
	elif button != null and button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		wheel_caught += 1
		pixel_scale -= 1
	elif button != null and button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
		get_tree().quit()
	elif event is InputEventMouseMotion and _dragging:
		get_window().position = DisplayServer.mouse_get_position() - _grab
	elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_tree().quit()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_C:
		click_through = ClickThrough.OUTLINE if click_through == ClickThrough.PIXEL else ClickThrough.PIXEL
# endregion


# region Public API
## True when the window really is see-through: the project allowed it and the platform can.
func is_transparent() -> bool:
	return get_window().transparent and DisplayServer.is_window_transparency_available()


## True while the window is catching the mouse. With [constant ClickThrough.OUTLINE] it always is,
## inside its outline.
func is_catching() -> bool:
	return _catching


## The demo's renderer, for tools that capture or measure it.
func get_splat_scene() -> SplatScene:
	return _scene
# endregion


# region Window
# The window is the picture at a whole number of screen pixels; it keeps its middle where it was.
func _resize() -> void:
	var window: Window = get_window()
	var size: Vector2i = _scene.art_size * pixel_scale
	window.position += (window.size - size) / 2
	window.size = size
	_next_outline = 0.0
# endregion


# region Mouse by pixel
# Starts the chosen way afresh: by pixel there is no outline, by outline the window always catches.
func _apply_click_through() -> void:
	var window: Window = get_window()
	_next_outline = 0.0
	if click_through == ClickThrough.PIXEL:
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array(), window.get_window_id())
		_catching = true
		_update_catching()
	else:
		_catching = true
		window.mouse_passthrough = false


# The whole window lets the mouse through unless the art pixel under the cursor is covered. The
# cursor's place is asked of the system, not taken from mouse events: a window that lets the mouse
# through gets none. While the avatar is dragged the window keeps catching, wherever the cursor is.
func _update_catching() -> void:
	var window: Window = get_window()
	var catching: bool = _dragging
	if not catching and _covered != null:
		var at: Vector2i = DisplayServer.mouse_get_position() - window.position + _cursor_centre()
		var art: Vector2i = Vector2i(floori(at.x / float(pixel_scale)), floori(at.y / float(pixel_scale)))
		if Rect2i(Vector2i.ZERO, _covered.get_size()).has_point(art):
			catching = _covered.get_pixelv(art).a >= 0.5
	if catching != _catching or window.mouse_passthrough == catching:
		_catching = catching
		window.mouse_passthrough = not catching


# What to add to the cursor's reported place to get the middle of where it can be. On macOS the
# cursor is reported in whole points, as pixels: x floored and y rounded up, so on a 2x screen the
# report is the bottom-left pixel of a point, and the catching area was up to a point off at the top,
# right and bottom edges (the Mac session's sweep, 2026-11-18). Taking the point's middle brings every
# edge within half a point, which the same sweep confirmed.
func _cursor_centre() -> Vector2i:
	if OS.get_name() != "macOS":
		return Vector2i.ZERO
	var half: int = int(DisplayServer.screen_get_scale(get_window().current_screen)) / 2
	return Vector2i(half, -half)
# endregion


# region Mouse outline
# The window catches the mouse inside the picture's outline (and a small margin) and nowhere else.
func _update_outline() -> void:
	var picture: Image = _scene.get_picture().get_image()
	var covered: BitMap = BitMap.new()
	covered.create_from_image_alpha(picture, 0.5)
	covered.grow_mask(outline_margin, Rect2i(Vector2i.ZERO, picture.get_size()))
	var shapes: Array[PackedVector2Array] = covered.opaque_to_polygons(Rect2i(Vector2i.ZERO, picture.get_size()), 1.0)
	DisplayServer.window_set_mouse_passthrough(as_one_outline(shapes, float(pixel_scale)), get_window().get_window_id())


## Several outlines as the one polygon the window takes, scaled by [param scale]: the first, with a
## walk out to each of the others and back along the same line, which encloses nothing itself.
## With no outline at all the polygon is a sliver in the corner, so the whole window lets the mouse
## through; an empty polygon would mean the opposite.
static func as_one_outline(shapes: Array[PackedVector2Array], scale: float) -> PackedVector2Array:
	if shapes.is_empty():
		return PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(0, 1)])
	var outline: PackedVector2Array = PackedVector2Array()
	var home: Vector2 = shapes[0][0] * scale
	for point: Vector2 in shapes[0]:
		outline.append(point * scale)
	for n: int in range(1, shapes.size()):
		outline.append(home)
		for point: Vector2 in shapes[n]:
			outline.append(point * scale)
		outline.append(shapes[n][0] * scale)
	if shapes.size() > 1:
		outline.append(home)
	return outline
# endregion
