## Captures and measures the splat renderer. It needs a window (a headless run draws nothing):
##
##   godot --path . -s res://splats/tools/splat_report.gd
##   godot --path . --rendering-method gl_compatibility -s res://splats/tools/splat_report.gd -- --tag=compat
##
## For each sample asset it draws the asset alone through the file's own camera, as ink-studio's
## reference render does (cli/render.js: a 38 degree lens, a 320 x 320 stage), and writes
## [code]splats/comparisons/<id>.png[/code]: ink-studio's picture on the left, Godot's on the
## right, both scaled up with nearest-neighbour. Then it captures the demo scene and reports its
## splat count and frame time.
extends SceneTree


# region Constants
const SAMPLES: Array[Dictionary] = [
	{"id": "desk-mug", "asset": "res://splats/samples/mug.bytes", "time": 0.0},
	{"id": "desk-teapot", "asset": "res://splats/samples/teapot.bytes", "time": 0.0},
	{"id": "room-desk-set", "asset": "res://splats/samples/desk-set.bytes", "time": 0.0},
	{"id": "room-avatar-b", "asset": "res://splats/samples/avatar-b.bytes", "time": 3.0},
]
const INK_FOV_DEGREES: float = 38.0
const INK_STAGE: int = 320
const OUT_DIR: String = "res://splats/comparisons"
const REFERENCE_DIR: String = "res://splats/reference"
const SETTLE_FRAMES: int = 6
const MEASURE_FRAMES: int = 600
# endregion


# region Lifecycle
func _initialize() -> void:
	_run.call_deferred()
# endregion


# region Report
func _run() -> void:
	var tag: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--tag="):
			tag = "-" + argument.trim_prefix("--tag=")
	print("[splat report] renderer: %s, %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])

	for sample: Dictionary in SAMPLES:
		await _compare(sample, tag)
	await _frames(SAMPLES[3], tag)
	await _demo(tag)
	quit(0)


# One asset alone, through its own camera, beside ink-studio's render of it.
func _compare(sample: Dictionary, tag: String) -> void:
	var clip: SplatClip = SplatInstance.load_shared(sample["asset"])
	var holder: Node3D = _stage(sample)
	var scene: SplatScene = holder.get_meta(&"scene")
	var px: int = holder.get_meta(&"px")
	var art: int = scene.art_size.x

	for f: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = scene.get_picture().get_image()
	picture.convert(Image.FORMAT_RGBA8)
	var part_transparent: int = 0
	for y: int in picture.get_height():
		for x: int in picture.get_width():
			var alpha: float = picture.get_pixel(x, y).a
			if alpha > 0.0 and alpha < 1.0:
				part_transparent += 1
	var background: Color = Color.hex((clip.palette[0] << 8) | 0xff)
	var ours: Image = _over(picture, background)

	var reference: Image = Image.load_from_file(ProjectSettings.globalize_path("%s/%s@%s.png" % [REFERENCE_DIR, sample["id"], str(int(sample["time"]))]))
	reference.convert(Image.FORMAT_RGBA8)
	var same_size: bool = reference.get_size() == ours.get_size()
	var equal: int = 0
	var same_cover: int = 0
	if same_size:
		for y: int in ours.get_height():
			for x: int in ours.get_width():
				var a: Color = reference.get_pixel(x, y)
				var b: Color = ours.get_pixel(x, y)
				if a.is_equal_approx(b):
					equal += 1
				if a.is_equal_approx(background) == b.is_equal_approx(background):
					same_cover += 1
	var total: int = ours.get_width() * ours.get_height()
	print("[splat report] %s: %d splats, art %dx%d (ink-studio's %dx%d), art pixel %d stage px; %.1f%% of pixels the same colour, %.1f%% the same coverage, %d part-transparent pixels" % [
		sample["id"], clip.splat_count, ours.get_width(), ours.get_height(), reference.get_width(), reference.get_height(), px,
		100.0 * equal / total, 100.0 * same_cover / total, part_transparent])

	var scale: int = maxi(1, 480 / art)
	var gap: int = 16
	var sheet: Image = Image.create_empty(reference.get_width() * scale + gap + ours.get_width() * scale, maxi(reference.get_height(), ours.get_height()) * scale, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.5, 0.5, 0.5))
	var left: Image = reference.duplicate()
	left.resize(reference.get_width() * scale, reference.get_height() * scale, Image.INTERPOLATE_NEAREST)
	var right: Image = ours.duplicate()
	right.resize(ours.get_width() * scale, ours.get_height() * scale, Image.INTERPOLATE_NEAREST)
	sheet.blit_rect(left, Rect2i(Vector2i.ZERO, left.get_size()), Vector2i.ZERO)
	sheet.blit_rect(right, Rect2i(Vector2i.ZERO, right.get_size()), Vector2i(left.get_width() + gap, 0))
	sheet.save_png(ProjectSettings.globalize_path("%s/%s%s.png" % [OUT_DIR, sample["id"], tag]))

	holder.queue_free()
	await process_frame


# The asset alone under ink-studio's own camera for it: a holder with its [SplatScene] in its "scene" meta.
func _stage(sample: Dictionary) -> Node3D:
	var clip: SplatClip = SplatInstance.load_shared(sample["asset"])
	var target: Vector3 = Vector3(clip.camera[0], clip.camera[1], clip.camera[2])
	var distance: float = clip.camera[3]
	var pitch: float = clip.camera[4]
	var yaw: float = clip.camera[5]
	# ink-studio's art pixel, in stage pixels, and so the picture's size (cli/render.js)
	var half_tan: float = tan(deg_to_rad(INK_FOV_DEGREES) * 0.5)
	var px: int = clampi(roundi(INK_STAGE / (2.0 * half_tan * clip.detail * distance)), 1, 18)
	var art: int = ceili(INK_STAGE / float(px))

	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	var instance: SplatInstance = SplatInstance.new()
	instance.asset = sample["asset"]
	holder.add_child(instance)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = INK_FOV_DEGREES
	camera.near = maxf(0.4, 0.15 * distance)
	camera.far = distance + 50.0
	holder.add_child(camera)
	var eye: Vector3 = target + distance * Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	camera.look_at_from_position(eye, target, Vector3.UP)
	var scene: SplatScene = SplatScene.new()
	scene.camera = camera
	scene.instances_root = holder
	scene.art_size = Vector2i(art, art)
	scene.fixed_time = sample["time"]
	holder.add_child(scene)
	holder.set_meta(&"scene", scene)
	holder.set_meta(&"px", px)
	return holder


# A clip at four times side by side, and how many art pixels change between them: it is playing.
func _frames(sample: Dictionary, tag: String) -> void:
	var holder: Node3D = _stage(sample)
	var scene: SplatScene = holder.get_meta(&"scene")
	var clip: SplatClip = SplatInstance.load_shared(sample["asset"])
	var background: Color = Color.hex((clip.palette[0] << 8) | 0xff)
	var times: PackedFloat32Array = PackedFloat32Array([0.0, 0.5, 3.0, 5.5])
	var scale: int = 4
	var art: Vector2i = scene.art_size
	var strip: Image = Image.create_empty(art.x * scale * times.size(), art.y * scale, false, Image.FORMAT_RGBA8)
	var before: Image = null
	var changes: PackedStringArray = PackedStringArray()
	for n: int in times.size():
		scene.fixed_time = times[n]
		for f: int in SETTLE_FRAMES:
			await process_frame
		await RenderingServer.frame_post_draw
		var picture: Image = scene.get_picture().get_image()
		picture.convert(Image.FORMAT_RGBA8)
		var shown: Image = _over(picture, background)
		if before != null:
			var changed: int = 0
			for y: int in art.y:
				for x: int in art.x:
					if not shown.get_pixel(x, y).is_equal_approx(before.get_pixel(x, y)):
						changed += 1
			changes.append("%s s -> %s s: %d" % [times[n - 1], times[n], changed])
		before = shown.duplicate()
		shown.resize(art.x * scale, art.y * scale, Image.INTERPOLATE_NEAREST)
		strip.blit_rect(shown, Rect2i(Vector2i.ZERO, shown.get_size()), Vector2i(n * art.x * scale, 0))
	strip.save_png(ProjectSettings.globalize_path("%s/%s-frames%s.png" % [OUT_DIR, sample["id"], tag]))
	print("[splat report] %s frames: art pixels that change, %s" % [sample["id"], ", ".join(changes)])
	holder.queue_free()
	await process_frame


# The demo scene: a capture at a fixed time, then its frame time with the clips running.
func _demo(tag: String) -> void:
	var demo: Node = (load("res://splats/demo/splat_demo.tscn") as PackedScene).instantiate()
	root.add_child(demo)
	var scene: SplatScene = demo.get_splat_scene()
	scene.fixed_time = 3.0
	for f: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = scene.get_picture().get_image()
	picture.convert(Image.FORMAT_RGBA8)
	var shown: Image = _over(picture, Color.hex(0x2a1f1aff))
	shown.resize(shown.get_width() * 4, shown.get_height() * 4, Image.INTERPOLATE_NEAREST)
	shown.save_png(ProjectSettings.globalize_path("%s/demo%s.png" % [OUT_DIR, tag]))
	var window: Image = root.get_texture().get_image()
	window.save_png(ProjectSettings.globalize_path("%s/demo-window%s.png" % [OUT_DIR, tag]))

	# the demo's look switch: press it, and capture the other look
	var look: CheckButton = demo.get_node("%LookToggle")
	look.button_pressed = true
	for f: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/demo-window-vote%s.png" % [OUT_DIR, tag]))
	print("[splat report] demo: look switch on, vote = %s" % (scene.interior == SplatScene.Interior.VOTE))
	look.button_pressed = false

	scene.fixed_time = -1.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for f: int in 30:
		await process_frame
	var started: int = Time.get_ticks_usec()
	var cpu: float = 0.0
	var cpu_peak: float = 0.0
	for f: int in MEASURE_FRAMES:
		await process_frame
		cpu += scene.last_cpu_msec
		cpu_peak = maxf(cpu_peak, scene.last_cpu_msec)
	var frame_msec: float = (Time.get_ticks_usec() - started) / 1000.0 / MEASURE_FRAMES
	print("[splat report] demo: %s" % scene.status())
	print("[splat report] demo: %.2f ms a frame (%.0f fps) over %d frames with vsync off, window %s; the scene's script %.3f ms a frame (peak %.2f), %d rebuilds" % [
		frame_msec, 1000.0 / frame_msec, MEASURE_FRAMES, str(root.size), cpu / MEASURE_FRAMES, cpu_peak, scene.rebuild_count])
	demo.queue_free()
	await process_frame


# The picture over a flat colour: a transparent pixel shows the colour.
func _over(picture: Image, background: Color) -> Image:
	var out: Image = Image.create_empty(picture.get_width(), picture.get_height(), false, Image.FORMAT_RGBA8)
	for y: int in picture.get_height():
		for x: int in picture.get_width():
			var c: Color = picture.get_pixel(x, y)
			out.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0) if c.a >= 0.5 else background)
	return out
# endregion
