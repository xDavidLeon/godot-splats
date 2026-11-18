## Measures the renderer under a room-sized load: 16 instances of a furnished room's assets, about
## 174,000 splats with the set it was written for, at 640 x 360 art pixels. Those
## assets are not in this repository: give the folder that holds the room's .bytes files. It needs a window:
##
##   godot --path . -s res://splats/tools/splat_scale.gd -- --assets=<folder> --out=<folder>
##
## The layout is only a load, not the game's room: the pieces stand on a grid over the floor.
extends SceneTree


# region Constants
const ART: Vector2i = Vector2i(640, 360)
const MEASURE_FRAMES: int = 600
## File, then where it stands (x, z in metres) and its quarter turns.
const PIECES: Array[Array] = [
	["floor", 0.0, 0.0, 0], ["wall", 0.0, 0.0, 0], ["wall", 0.0, 0.0, 1], ["shell-window", 0.0, 0.0, 0],
	["shell-light", 0.0, 0.0, 1], ["desk-set", -1.5, -1.0, 0], ["avatar-b", -1.5, -1.0, 0], ["bed", 1.5, -1.5, 0],
	["shelf", -1.8, 1.6, 0], ["rug", 0.3, 0.4, 0], ["poster", 1.0, 0.0, 0], ["plant", 2.2, 1.8, 0], ["plant", -0.4, 2.2, 0],
	["lamp", 2.3, 0.2, 0], ["lamp", -2.4, 0.3, 0], ["chair", 0.9, 1.6, 2],
]
# endregion


# region Lifecycle
func _initialize() -> void:
	_run.call_deferred()
# endregion


# region Measuring
func _run() -> void:
	var assets: String = ""
	var out: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--assets="):
			assets = argument.trim_prefix("--assets=")
		elif argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
	if assets.is_empty() or out.is_empty():
		push_error("[splat scale] give two folders: -- --assets=<folder> --out=<folder>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)

	var world: Node3D = Node3D.new()
	root.add_child(world)
	for piece: Array in PIECES:
		var instance: SplatInstance = SplatInstance.new()
		instance.asset = assets.path_join("%s.bytes" % piece[0])
		instance.position = Vector3(piece[1], 0.0, piece[2])
		instance.rotation.y = piece[3] * PI * 0.5
		world.add_child(instance)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.4
	camera.near = 0.1
	camera.far = 60.0
	world.add_child(camera)
	var target: Vector3 = Vector3(0.0, 0.9, 0.0)
	camera.look_at_from_position(target + 14.0 * Vector3(cos(0.6) * sin(PI + 0.7), sin(0.6), cos(0.6) * cos(PI + 0.7)), target, Vector3.UP)
	var scene: SplatScene = SplatScene.new()
	scene.camera = camera
	scene.instances_root = world
	scene.art_size = ART
	scene.measure_render_time = true
	world.add_child(scene)
	var shown: TextureRect = TextureRect.new()
	shown.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shown.set_anchors_preset(Control.PRESET_FULL_RECT)
	shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(shown)
	for f: int in 4:
		await process_frame
	shown.texture = scene.get_picture()

	scene.fixed_time = 3.0
	for f: int in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = scene.get_picture().get_image()
	picture.convert(Image.FORMAT_RGBA8)
	var covered: int = 0
	for y: int in picture.get_height():
		for x: int in picture.get_width():
			if picture.get_pixel(x, y).a >= 0.5:
				covered += 1
	picture.resize(ART.x * 3, ART.y * 3, Image.INTERPOLATE_NEAREST)
	picture.save_png(out.path_join("scale-%s.png" % RenderingServer.get_current_rendering_method()))

	scene.fixed_time = -1.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for f: int in 60:
		await process_frame
	var started: int = Time.get_ticks_usec()
	var script_msec: float = 0.0
	var script_peak: float = 0.0
	var render: Vector2 = Vector2.ZERO
	for f: int in MEASURE_FRAMES:
		await process_frame
		script_msec += scene.last_cpu_msec
		script_peak = maxf(script_peak, scene.last_cpu_msec)
		render += scene.get_render_msec()
	var frame_msec: float = (Time.get_ticks_usec() - started) / 1000.0 / MEASURE_FRAMES
	print("[splat scale] %s on %s, %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name()])
	print("[splat scale] %s; %.0f%% of the picture covered" % [scene.status(), 100.0 * covered / (ART.x * ART.y)])
	print("[splat scale] %.2f ms a frame (%.0f fps) with vsync off in a %s window, over %d frames" % [frame_msec, 1000.0 / frame_msec, str(root.size), MEASURE_FRAMES])
	print("[splat scale] the scene's script: %.3f ms a frame (peak %.2f); its two passes: %.3f ms on the CPU, %.3f ms on the GPU; rebuilds: %d" % [
		script_msec / MEASURE_FRAMES, script_peak, render.x / MEASURE_FRAMES, render.y / MEASURE_FRAMES, scene.rebuild_count])
	quit(0)
# endregion
