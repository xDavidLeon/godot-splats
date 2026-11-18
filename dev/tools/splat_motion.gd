## Captures the two interior-colour modes of the splat resolve in motion, frame for frame, so they can
## be compared: the average (the default, Unity's look) and the vote ([member SplatScene.interior]).
## It needs a window:
##
##   godot --path . -s res://splats/tools/splat_motion.gd -- --out=<folder>
##
## It writes PNG frames, [code]<shot>-<mode>-<frame>.png[/code], at the art resolution. Three shots:
## the avatar alone through its own camera, the demo scene, and the demo scene with the camera
## turning slowly, which shows how still things hold up when their pixels move.
extends SceneTree


# region Constants
const FRAMES: int = 60
const FRAMES_PER_SECOND: float = 15.0
const SETTLE_FRAMES: int = 3
const INK_FOV_DEGREES: float = 38.0
const INK_STAGE: int = 320
const AVATAR: String = "res://splats/samples/avatar-b.bytes"
const MODES: PackedStringArray = ["vote", "average"]
# endregion


# region State
var _out: String = ""
# endregion


# region Lifecycle
func _initialize() -> void:
	_run.call_deferred()
# endregion


# region Shots
func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	if _out.is_empty():
		push_error("[splat motion] give a folder: -- --out=<folder>")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	await _avatar()
	await _demo("demo", 0.0)
	await _demo("orbit", 0.35)
	print("[splat motion] %d frames a shot at %s fps, in %s" % [FRAMES, FRAMES_PER_SECOND, _out])
	quit(0)


# The avatar alone, as ink-studio frames it.
func _avatar() -> void:
	var clip: SplatClip = SplatInstance.load_shared(AVATAR)
	var target: Vector3 = Vector3(clip.camera[0], clip.camera[1], clip.camera[2])
	var distance: float = clip.camera[3]
	var pitch: float = clip.camera[4]
	var yaw: float = clip.camera[5]
	var px: int = clampi(roundi(INK_STAGE / (2.0 * tan(deg_to_rad(INK_FOV_DEGREES) * 0.5) * clip.detail * distance)), 1, 18)
	var art: int = ceili(INK_STAGE / float(px))

	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	var instance: SplatInstance = SplatInstance.new()
	instance.asset = AVATAR
	holder.add_child(instance)
	var camera: Camera3D = Camera3D.new()
	camera.fov = INK_FOV_DEGREES
	camera.near = maxf(0.4, 0.15 * distance)
	camera.far = distance + 50.0
	holder.add_child(camera)
	camera.look_at_from_position(target + distance * Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)), target, Vector3.UP)
	var scenes: Array[SplatScene] = _both(holder, camera, holder, Vector2i(art, art))
	for f: int in FRAMES:
		await _shoot("avatar", f, scenes)
	holder.queue_free()
	await process_frame


# The demo scene; with [param swing] the camera's yaw swings that many radians each way over the shot.
func _demo(shot: String, swing: float) -> void:
	var demo: Node = (load("res://splats/demo/splat_demo.tscn") as PackedScene).instantiate()
	root.add_child(demo)
	var first: SplatScene = demo.get_splat_scene()
	var camera: Camera3D = first.camera
	# the demo's own renderer takes the first mode; a second one beside it takes the other
	var scenes: Array[SplatScene] = _both(demo, camera, first.instances_root, first.art_size)
	scenes[0].queue_free()
	scenes[0] = first
	first.interior = SplatScene.Interior.VOTE
	var target: Vector3 = demo.camera_target
	var distance: float = demo.camera_distance
	var pitch: float = demo.camera_pitch
	for f: int in FRAMES:
		var yaw: float = demo.camera_yaw + swing * sin(TAU * f / float(FRAMES))
		camera.look_at_from_position(target + distance * Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)), target, Vector3.UP)
		await _shoot(shot, f, scenes)
	demo.queue_free()
	await process_frame


# Two renderers on the same camera and instances: one for each mode, so both draw the same moment.
func _both(parent: Node, camera: Camera3D, instances: Node, art: Vector2i) -> Array[SplatScene]:
	var scenes: Array[SplatScene] = []
	for mode: int in MODES.size():
		var scene: SplatScene = SplatScene.new()
		scene.camera = camera
		scene.instances_root = instances
		scene.art_size = art
		scene.interior = SplatScene.Interior.AVERAGE if mode == 1 else SplatScene.Interior.VOTE
		scene.fixed_time = 0.0
		parent.add_child(scene)
		scenes.append(scene)
	return scenes


func _shoot(shot: String, frame: int, scenes: Array[SplatScene]) -> void:
	for scene: SplatScene in scenes:
		scene.fixed_time = frame / FRAMES_PER_SECOND
	for f: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	for mode: int in MODES.size():
		var picture: Image = scenes[mode].get_picture().get_image()
		picture.convert(Image.FORMAT_RGBA8)
		picture.save_png("%s/%s-%s-%02d.png" % [_out, shot, MODES[mode], frame])
# endregion
