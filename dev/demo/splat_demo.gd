## Demo of the splat renderer ([SplatScene]): a desk set
## with its typing avatar, a mug that steams and a teapot on the desk, and a second desk set and
## avatar behind, turned a quarter turn, all in one pixel-art picture. Run it by itself with F6.
## The switch in the corner, or the Tab key, changes how the inside of a shape is coloured: the average
## of the samples (the default, Unity's look) or the vote. In a debug build F1 opens the debug panel
## ([SplatDebugPanel]), which changes the look, the dither and the art size.
extends Node


# region State
## What the camera looks at, in metres.
@export var camera_target: Vector3 = Vector3(0.7, 0.45, 0.82)
## How far the camera stands from it.
@export var camera_distance: float = 6.0
## The camera's pitch above the floor and yaw about y, in radians, as ink-studio counts them.
@export var camera_pitch: float = 0.5
@export var camera_yaw: float = PI + 0.6

@onready var _camera: Camera3D = %Camera
@onready var _scene: SplatScene = %SplatScene
@onready var _picture: TextureRect = %Picture
@onready var _status: Label = %Status
@onready var _look: CheckButton = %LookToggle

var _next_status: float = 0.0
# endregion


# region Lifecycle
func _ready() -> void:
	var cp: float = cos(camera_pitch)
	var eye: Vector3 = camera_target + camera_distance * Vector3(cp * sin(camera_yaw), sin(camera_pitch), cp * cos(camera_yaw))
	_camera.look_at_from_position(eye, camera_target, Vector3.UP)
	_picture.texture = _scene.get_picture()
	_scene.measure_render_time = true
	_look.button_pressed = _scene.interior == SplatScene.Interior.VOTE
	_look.toggled.connect(_on_look_toggled)
	_show_look()
	SplatDebugPanel.add_to(self) # nothing in a release build


func _process(delta: float) -> void:
	if _look.button_pressed != (_scene.interior == SplatScene.Interior.VOTE):
		# the debug panel changed the look
		_look.set_pressed_no_signal(_scene.interior == SplatScene.Interior.VOTE)
		_show_look()
	_next_status -= delta
	if _next_status > 0.0 or _scene.rebuild_count == 0:
		return
	var passes: Vector2 = _scene.get_render_msec()
	_status.text = "%s; passes %.2f ms CPU, %.2f ms GPU; %d fps" % [_scene.status(), passes.x, passes.y, Engine.get_frames_per_second()]
	_next_status = 0.5
# endregion


# region Input
# The demo has no input action of its own, so the game's input map stays as it is: the key is read raw.
func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_TAB:
		_look.button_pressed = not _look.button_pressed
		get_viewport().set_input_as_handled()
# endregion


# region Signal Handlers
func _on_look_toggled(vote: bool) -> void:
	_scene.interior = SplatScene.Interior.VOTE if vote else SplatScene.Interior.AVERAGE
	_show_look()
# endregion


# region Helpers
func _show_look() -> void:
	_look.text = "Look: vote  [Tab]" if _scene.interior == SplatScene.Interior.VOTE else "Look: average  [Tab]"
# endregion


# region Public API
## The demo's renderer, for tools that capture or measure it.
func get_splat_scene() -> SplatScene:
	return _scene
# endregion
