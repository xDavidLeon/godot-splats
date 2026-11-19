## Captures, checks and measures the tint. It needs a window (a headless run draws nothing):
##
##   godot --path . -s res://splats/tools/splat_tint_report.gd
##   ... -- --tag=<word>   added to the file names, to keep one renderer's pictures from another's
##
## The scene is the sample desk set with its avatar, a mug and a teapot, and two more desk sets: one
## on free floor, tinted green, and one that overlaps the first, tinted red, each with its footprint
## as marks. With a floor in [code]splats/samples[/code] (floor.bytes, handed to
## [code]dev/make_project.py --samples[/code]; this repository holds none) they stand on it.
## [br]It writes to [code]splats/comparisons/[/code]:
## [br]- [code]tint[/code]: the frame with both tints and their footprints, and [code]tint-off[/code]:
## the same two things drawn as themselves.
## [br]- [code]tint-shadows[/code]: the tinted frame with floor shadows on.
## [br]Then it checks what a picture can show:
## [br]- that the tints' shaded colours are in the picture, on every other art pixel only, and that
## the pixels between show what is behind;
## [br]- that every sample a tinted splat is nearest at is marked as one, and nothing else is;
## [br]- that every pixel's alpha is 0 or 255, with floor shadows off and on, and with marks too;
## [br]- that a tint given, changed and taken away rebuilds nothing and leaves the picture as it was;
## [br]- that dusk darkens a tint's shading, that a tinted instance darkens the floor only while it
## casts a shadow, and that a floor shadow falling on one leaves it a darker tint.
## [br]It prints what a frame costs with and without the tints.
## Exit code 0: every check passed. The pictures still have to be looked at.
extends SceneTree


# region Constants
const SAMPLES: String = "res://splats/samples/"
const OUT_DIR: String = "res://splats/comparisons"
const SETTLE_FRAMES: int = 4
const MEASURE_FRAMES: int = 200

const ART: Vector2i = Vector2i(320, 180)
const SCALE: int = 4
const CAMERA_HEIGHT: float = 3.3
const CAMERA_PITCH: float = 35.0
const CAMERA_YAW: float = 225.0
const CAMERA_DISTANCE: float = 20.0
const LOOK_AT: Vector3 = Vector3(0.45, 0.4, -0.35)
const SHOT_TIME: float = 1.5

const FITS: Color = Color8(89, 217, 115)
const DOES_NOT_FIT: Color = Color8(242, 77, 71)
const FREE_AT: Vector3 = Vector3(1.9, 0.0, -1.6)
const OVERLAPPING_AT: Vector3 = Vector3(-0.55, 0.0, -0.6)
const LINE_HEIGHT: float = 0.012
# endregion


# region State
var _tag: String = ""
var _failures: int = 0
var _holder: Node3D
var _camera: Camera3D
var _scene: SplatScene
var _desk: SplatInstance
var _free: SplatInstance
var _overlapping: SplatInstance
var _background: Color = Color.BLACK
var _has_floor: bool = false
var _finished: bool = false
var _untouched: Image
# endregion


# region Lifecycle
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--tag="):
			_tag = "-" + argument.trim_prefix("--tag=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build()
	_untouched = await _shoot() # before any instance has ever been tinted
	await _cost() # before anything turns the floor shadows on: their pass, once built, shows in the timings
	await _tints()
	_check(_finished, "the checks ran to their end")
	print("[splat tint] %s" % ("every check passed" if _failures == 0 else "%d check(s) FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
# endregion


# region Checks
func _check(passed: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if passed else "FAIL", message])
	if not passed:
		_failures += 1


# The tinted frame against the same frame without the two things, and with them drawn as themselves.
func _tints() -> void:
	var solid: Image = await _shoot()
	_check(solid.get_data() == _untouched.get_data(), "after the tints the cost was measured with, the picture is what it was before any")
	_free.visible = false
	_overlapping.visible = false
	var without: Image = await _shoot()
	var without_samples: Image = _scene.get_samples().get_image()
	_free.visible = true
	_overlapping.visible = true
	await _shoot()
	var builds: int = _scene.rebuild_count

	var shades: Array[Array] = [_shades(_free, FITS), _shades(_overlapping, DOES_NOT_FIT)]
	_tint(_free, FITS)
	_tint(_overlapping, DOES_NOT_FIT)
	var tinted: Image = await _shoot()
	var tinted_samples: Image = _scene.get_samples().get_image()
	_check(_scene.tinted_count == 2 and _scene.rebuild_count == builds, "two instances tinted, and tinting them rebuilt nothing")

	# the samples: one that the tinted things changed is marked as theirs, and its colour is a tint's as
	# one of the asset's own colours shades it; nothing else is marked
	if _scene.get_tints() == null:
		_check(false, "the scene has a target that says which samples are tinted")
		return
	var marks: Image = _scene.get_tints().get_image()
	var marked: int = 0
	var unmarked: int = 0
	var marked_elsewhere: int = 0
	var marked_between: int = 0
	var marked_clear: int = 0
	for y: int in tinted_samples.get_height():
		for x: int in tinted_samples.get_width():
			var sample: Color = tinted_samples.get_pixel(x, y)
			var behind: Color = without_samples.get_pixel(x, y)
			var changed: bool = sample.r8 != behind.r8 or sample.g8 != behind.g8 or sample.b8 != behind.b8
			if marks.get_pixel(x, y).r > 0.5:
				marked += 1
				if (x / 2 + y / 2) % 2 == 1:
					marked_between += 1
				if sample.a8 != 255:
					marked_clear += 1
				if not _is_shade(sample, shades[0]) and not _is_shade(sample, shades[1]):
					marked_elsewhere += 1
			elif changed:
				unmarked += 1
	_check(marks.get_size() == tinted_samples.get_size() and marked > 1000, "the tinted things' samples are marked in a target of the samples' size (%d samples)" % marked)
	_check(unmarked == 0, "every sample the tinted things changed is marked (%d are not)" % unmarked)
	_check(marked_elsewhere == 0 and marked_clear == 0, "and every marked sample is covered, in a tint as one of the asset's own colours shades it (%d are not)" % (marked_elsewhere + marked_clear))
	_check(marked_between == 0, "none of them on the art pixels between (%d are)" % marked_between)

	# the picture
	var tints: Array[Color] = [FITS, DOES_NOT_FIT]
	var names: PackedStringArray = ["green", "red"]
	var in_tint: Array[int] = [0, 0]
	var in_shade: Array[int] = [0, 0]
	var between_in_tint: int = 0
	var between_changed: int = 0
	var between_changed_inside: int = 0
	var changed_other: int = 0
	var is_tint: Dictionary[Vector2i, bool] = {}
	for y: int in tinted.get_height():
		for x: int in tinted.get_width():
			var pixel: Color = tinted.get_pixel(x, y)
			if pixel == without.get_pixel(x, y):
				continue
			if (x + y) % 2 == 1:
				between_changed += 1
				if _edge(without, x, y) == 0:
					between_changed_inside += 1
			var found: bool = false
			for t: int in tints.size():
				if _on_shade_line(pixel, tints[t]):
					found = true
					if (x + y) % 2 == 1:
						between_in_tint += 1
					else:
						in_tint[t] += 1
						is_tint[Vector2i(x, y)] = true
						if _is_shade(pixel, shades[t]):
							in_shade[t] += 1
			if not found and (x + y) % 2 == 0:
				changed_other += 1
	for t: int in tints.size():
		_check(in_tint[t] > 300, "the %s tint is in the picture, lighter and darker (%d pixels)" % [names[t], in_tint[t]])
		_check(in_shade[t] > 100, "%d of them are exactly the tint as one of the asset's own colours shades it" % in_shade[t])
	_check(between_in_tint == 0, "the tints are on every other art pixel only (%d pixels of them on the others)" % between_in_tint)
	_check(between_changed_inside == 0, "the pixels between are what is behind: %d differ, each on the outline of what is behind, which is inked by what is next to it (%d differ elsewhere)" % [between_changed, between_changed_inside])
	print("[splat tint] %d more pixels on the tints' own pixels changed to a colour that is not a tint's: where one sample of four is a tinted thing's" % changed_other)
	# behind shows: an art pixel between four tinted ones that is covered, and is what the picture without shows
	var through: int = 0
	var through_clear: int = 0
	for y: int in range(1, tinted.get_height() - 1):
		for x: int in range(1, tinted.get_width() - 1):
			if (x + y) % 2 == 0:
				continue
			if is_tint.has(Vector2i(x - 1, y)) and is_tint.has(Vector2i(x + 1, y)) and is_tint.has(Vector2i(x, y - 1)) and is_tint.has(Vector2i(x, y + 1)) \
					and tinted.get_pixel(x, y) == without.get_pixel(x, y):
				if tinted.get_pixel(x, y).a8 == 255:
					through += 1
				else:
					through_clear += 1
	_check(through + through_clear > 300 and (through > 300 or not _has_floor), "what is behind shows between the tinted pixels (%d pixels of it, and %d clear ones)" % [through, through_clear])
	_check(_odd_alpha(tinted) == 0, "with tints, every pixel's alpha is 0 or 255 (%d are neither)" % _odd_alpha(tinted))

	# another colour, and dusk: neither rebuilds, and dusk darkens the tint's shading
	var by_day: float = _mean_light(tinted, FITS)
	_scene.dusk = 2
	var evening: Image = await _shoot()
	_scene.dusk = 0
	var at_dusk: float = _mean_light(evening, FITS)
	_check(at_dusk < by_day - 0.02, "dusk darkens the splats and so the tint's shading (%.3f of the tint by day, %.3f at dusk)" % [by_day, at_dusk])
	_tint(_free, DOES_NOT_FIT)
	var swapped: Image = await _shoot()
	var still_green: int = 0
	for y: int in swapped.get_height():
		for x: int in swapped.get_width():
			if is_tint.has(Vector2i(x, y)) and _on_shade_line(swapped.get_pixel(x, y), FITS):
				still_green += 1
	_check(still_green == 0 and _scene.rebuild_count == builds, "a tint changed to another colour is in the next picture, and rebuilt nothing (%d pixels still green)" % still_green)
	_tint(_free, FITS)

	# with marks
	_scene.set_marks(_footprints())
	var with_marks: Image = await _shoot()
	_scale(_over_background(with_marks)).save_png("%s/tint%s.png" % [OUT_DIR, _tag])
	var lines: int = 0
	for y: int in with_marks.get_height():
		for x: int in with_marks.get_width():
			if with_marks.get_pixel(x, y) != tinted.get_pixel(x, y):
				lines += 1
	_check(lines > 100, "the footprints are drawn with the tints (%d pixels)" % lines)
	_check(_odd_alpha(with_marks) == 0, "with tints and marks, every pixel's alpha is 0 or 255 (%d are neither)" % _odd_alpha(with_marks))

	# with floor shadows: the tinted things cast one while they are let, and the picture stays covered or clear
	_desk.casts_shadow = true
	_scene.floor_shadows = true
	var shaded_marks: Image = await _shoot()
	_scale(_over_background(shaded_marks)).save_png("%s/tint-shadows%s.png" % [OUT_DIR, _tag])
	_check(_odd_alpha(shaded_marks) == 0, "with tints, marks and floor shadows, every pixel's alpha is 0 or 255 (%d are neither)" % _odd_alpha(shaded_marks))
	_scene.set_marks([])
	var shaded: Image = await _shoot()
	_check(_odd_alpha(shaded) == 0, "with tints and floor shadows, every pixel's alpha is 0 or 255 (%d are neither)" % _odd_alpha(shaded))
	_free.casts_shadow = true
	_overlapping.casts_shadow = true
	var casting: Image = await _shoot()
	_free.casts_shadow = false
	_overlapping.casts_shadow = false
	var darker: int = 0
	var tint_kept: int = 0
	var tint_darker: int = 0
	var tint_lost: int = 0
	for y: int in casting.get_height():
		for x: int in casting.get_width():
			if casting.get_pixel(x, y) != shaded.get_pixel(x, y):
				darker += 1
			if is_tint.has(Vector2i(x, y)):
				var lit: Color = tinted.get_pixel(x, y)
				var in_shadow: Color = casting.get_pixel(x, y)
				if in_shadow == lit:
					tint_kept += 1
				elif _light_of(in_shadow, FITS, 0.42) > 0.0 or _light_of(in_shadow, DOES_NOT_FIT, 0.42) > 0.0:
					tint_darker += 1
				else:
					tint_lost += 1
	_check(_odd_alpha(casting) == 0, "and so it is when the tinted things cast shadows too (%d are neither)" % _odd_alpha(casting))
	if _has_floor:
		_check(darker > 100, "a tinted thing darkens the floor only while it casts a shadow (%d pixels differ)" % darker)
	else:
		print("NOTE: no floor.bytes in splats/samples; whether a tinted thing darkens the floor was not looked at")
	_check(tint_lost == 0 and tint_darker > 0, "a floor shadow that falls on a tinted thing leaves it a tint, darker (%d pixels as they were, %d darker, %d no longer a tint)" % [tint_kept, tint_darker, tint_lost])
	_scene.floor_shadows = false
	_desk.casts_shadow = false

	# no tint again
	_free.tinted = false
	_overlapping.tinted = false
	var cleared: Image = await _shoot()
	_scale(_over_background(cleared)).save_png("%s/tint-off%s.png" % [OUT_DIR, _tag])
	_check(_scene.tinted_count == 0 and _scene.rebuild_count == builds, "the tints taken away rebuilt nothing")
	_check(cleared.get_data() == _untouched.get_data(), "and the picture is what it was before any tint")
	var left: int = 0
	for at: Vector2i in is_tint:
		if _on_shade_line(cleared.get_pixelv(at), FITS) or _on_shade_line(cleared.get_pixelv(at), DOES_NOT_FIT):
			left += 1
	_check(left == 0, "with none of a tint's pixels still a tint's (%d are)" % left)
	_finished = true
	print("[splat tint] %s" % _scene.status())


func _tint(instance: SplatInstance, colour: Color) -> void:
	instance.tint = colour
	instance.tinted = true


# Every colour of an instance's palette as the tint shades it.
func _shades(instance: SplatInstance, colour: Color) -> Array[Color]:
	var shades: Array[Color] = []
	for own: int in instance.get_clip().palette:
		shades.append(SplatInstance.tint_shade(colour, Color.hex((own << 8) | 0xff)))
	return shades


# Whether a colour is one of those, to within one step of an 8-bit channel.
func _is_shade(colour: Color, shades: Array) -> bool:
	for shade: Color in shades:
		if absf(colour.r - shade.r) < 1.6 / 255.0 and absf(colour.g - shade.g) < 1.6 / 255.0 and absf(colour.b - shade.b) < 1.6 / 255.0:
			return true
	return false


# Whether a pixel is a tint at some strength from 0.55 to 1.25: every channel the tint's, times one
# number, to within two steps of an 8-bit channel. The number is tried from each channel in turn. A
# pixel's four samples may be shaded differently, and a channel that saturates in some of them
# averages lower.
func _on_shade_line(pixel: Color, colour: Color) -> bool:
	return pixel.a8 == 255 and _light_of(pixel, colour) > 0.0


# The strength of the tint a pixel is, or 0 if it is not that tint. In a floor shadow it can be lower.
func _light_of(pixel: Color, colour: Color, lowest: float = 0.53) -> float:
	var is_pixel: PackedInt32Array = [pixel.r8, pixel.g8, pixel.b8]
	var is_tint: PackedInt32Array = [colour.r8, colour.g8, colour.b8]
	for from: int in 3:
		if is_tint[from] == 0 or is_pixel[from] >= 250:
			continue
		var light: float = is_pixel[from] / float(is_tint[from])
		if light < lowest or light > 1.27:
			continue
		var fits: bool = true
		for channel: int in 3:
			var expected: float = minf(255.0, is_tint[channel] * light)
			var slack: float = 14.0 if is_tint[channel] * 1.25 > 255.0 else 0.0
			if is_pixel[channel] > expected + 2.5 or is_pixel[channel] < expected - 2.5 - slack:
				fits = false
		if fits:
			return light
	return 0.0


# How strong the tint is on average over the pixels that are it.
func _mean_light(picture: Image, colour: Color) -> float:
	var total: float = 0.0
	var count: int = 0
	for y: int in picture.get_height():
		for x: int in picture.get_width():
			var pixel: Color = picture.get_pixel(x, y)
			if (x + y) % 2 == 0 and _on_shade_line(pixel, colour):
				total += _light_of(pixel, colour)
				count += 1
	return total / maxi(1, count)


# How many of a covered pixel's four neighbours are clear: the pixel look inks such a pixel.
func _edge(picture: Image, x: int, y: int) -> int:
	if picture.get_pixel(x, y).a8 == 0:
		return 0
	var clear: int = 0
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var at: Vector2i = Vector2i(x, y) + step
		if at.x < 0 or at.y < 0 or at.x >= picture.get_width() or at.y >= picture.get_height() or picture.get_pixelv(at).a8 == 0:
			clear += 1
	return clear


func _odd_alpha(picture: Image) -> int:
	var odd: int = 0
	for y: int in picture.get_height():
		for x: int in picture.get_width():
			var alpha: int = picture.get_pixel(x, y).a8
			if alpha != 0 and alpha != 255:
				odd += 1
	return odd
# endregion


# region Shots
func _build() -> void:
	_holder = Node3D.new()
	root.add_child(_holder)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CAMERA_HEIGHT
	_camera.near = 0.3
	_camera.far = 60.0
	_holder.add_child(_camera)
	var pitch: float = deg_to_rad(CAMERA_PITCH)
	var yaw: float = deg_to_rad(CAMERA_YAW)
	_camera.look_at_from_position(LOOK_AT + CAMERA_DISTANCE * Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)), LOOK_AT, Vector3.UP)

	var world: Node3D = Node3D.new()
	_holder.add_child(world)
	_has_floor = FileAccess.file_exists(SAMPLES + "floor.bytes")
	if _has_floor:
		_add(world, "floor", Vector3.ZERO)
	_desk = _add(world, "desk-set", Vector3.ZERO)
	_background = Color.hex((_desk.get_clip().palette[0] << 8) | 0xff)
	_add(world, "avatar-b", Vector3.ZERO)
	_add(world, "mug", Vector3(-0.45, 0.445, 0.02))
	_add(world, "teapot", Vector3(0.42, 0.445, 0.0))
	_free = _add(world, "desk-set", FREE_AT)
	_overlapping = _add(world, "desk-set", OVERLAPPING_AT)

	_scene = SplatScene.new()
	_scene.name = "Picture"
	_scene.camera = _camera
	_scene.instances_root = world
	_scene.art_size = ART
	_scene.fixed_time = SHOT_TIME
	_scene.measure_render_time = true
	_holder.add_child(_scene)
	var show: TextureRect = TextureRect.new()
	show.texture = _scene.get_picture()
	show.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	show.set_anchors_preset(Control.PRESET_FULL_RECT)
	show.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(show)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = _background
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	root.move_child(backdrop, show.get_index())


func _add(parent: Node3D, id: String, at: Vector3) -> SplatInstance:
	var instance: SplatInstance = SplatInstance.new()
	instance.asset = SAMPLES + id + ".bytes"
	instance.position = at
	instance.casts_shadow = false
	parent.add_child(instance)
	return instance


# Each tinted thing's footprint, in its tint: the floor under its splats.
func _footprints() -> Array[SplatMark]:
	var lines: Array[SplatMark] = []
	for instance: SplatInstance in [_free, _overlapping]:
		var clip: SplatClip = instance.get_clip()
		var low: Vector2 = Vector2.INF
		var high: Vector2 = -Vector2.INF
		for i: int in clip.splat_count:
			var at: Vector2 = Vector2(clip.splats[i * SplatClip.STRIDE], clip.splats[i * SplatClip.STRIDE + 2])
			low = low.min(at)
			high = high.max(at)
		var middle: Vector3 = instance.position + Vector3((low.x + high.x) * 0.5, LINE_HEIGHT, (low.y + high.y) * 0.5)
		lines.append_array(SplatMark.outline(middle, Vector3((high.x - low.x) * 0.5, 0.0, 0.0), Vector3(0.0, 0.0, (high.y - low.y) * 0.5), Vector3.UP, instance.tint))
	return lines


# What a frame costs with the two things drawn as themselves, with both tinted, and as themselves
# again, which shows how much the numbers wander by themselves.
func _cost() -> void:
	var plain: Array = await _measure()
	_tint(_free, FITS)
	_tint(_overlapping, DOES_NOT_FIT)
	var with_tints: Array = await _measure()
	_free.tinted = false
	_overlapping.tinted = false
	var plain_again: Array = await _measure()
	_scene.fixed_time = SHOT_TIME
	for row: Array in [["no tint", plain], ["two tinted instances", with_tints], ["no tint, again", plain_again]]:
		var cost: Array = row[1]
		print("[splat tint] cost, %s: %d splats; script %.3f ms a frame; passes %.2f ms CPU, %.2f ms GPU; rebuild %.1f ms" % [row[0], cost[0], cost[1], cost[2], cost[3], cost[4]])


func _measure() -> Array:
	_scene.fixed_time = -1.0
	for f: int in SETTLE_FRAMES * 4:
		await process_frame
	var script: float = 0.0
	var passes: Vector2 = Vector2.ZERO
	for f: int in MEASURE_FRAMES:
		await process_frame
		script += _scene.last_cpu_msec
		passes += _scene.get_render_msec()
	return [_scene.splat_count, script / MEASURE_FRAMES, passes.x / MEASURE_FRAMES, passes.y / MEASURE_FRAMES, _scene.last_rebuild_msec]


func _shoot() -> Image:
	for f: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = _scene.get_picture().get_image()
	picture.convert(Image.FORMAT_RGBA8)
	return picture


func _over_background(picture: Image) -> Image:
	var flat: Image = Image.create_empty(picture.get_width(), picture.get_height(), false, Image.FORMAT_RGBA8)
	flat.fill(_background)
	flat.blend_rect(picture, Rect2i(Vector2i.ZERO, picture.get_size()), Vector2i.ZERO)
	return flat


func _scale(picture: Image) -> Image:
	var big: Image = picture.duplicate()
	big.resize(picture.get_width() * SCALE, picture.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
	return big
# endregion
