## Captures, checks and measures the particles, the marks and the debug panel. It needs a window (a
## headless run draws nothing):
##
##   godot --path . -s res://splats/tools/splat_fx_report.gd
##   ... -- --tag=<word>   added to the file names, to keep one renderer's pictures from another's
##
## The scene is the sample desk set with its avatar, a mug and a teapot that steam, flames on the
## floor beside it and dust in the air. With a floor in [code]splats/samples[/code] (floor.bytes,
## handed to [code]dev/make_project.py --samples[/code]; this repository holds none) they stand on it.
## [br]It writes to [code]splats/comparisons/[/code]:
## [br]- [code]fx-particles/NN[/code]: 48 frames at 12 a second at the art resolution, to make a GIF of,
## and [code]fx-particles-strip[/code]: six of them, half a second apart.
## [br]- [code]fx-marks[/code]: one frame with a dotted grid, an outline round the desk set and a
## smaller outline on a free piece of floor, and [code]fx-marks-off[/code]: the same frame without.
## [br]- [code]fx-panel-average[/code], [code]fx-panel-vote[/code], [code]fx-panel-art-90[/code]: the
## window with the debug panel open, in each look, and with the picture made 90 art pixels high.
## [br]Then it checks what a picture can show:
## [br]- that the shader moves a cloud's splats where [SplatParticles] says, by drawing one cloud alone
## and looking for each splat where the rule puts it (with the seed rounded one of the two ways a
## driver was seen to round it, see [member SplatParticles.fused]);
## [br]- that time passing, with particles and marks, rebuilds nothing;
## [br]- that every pixel of the picture with marks is covered or clear, that the lines' own colours
## are in it, and how many other pixels the lines changed;
## [br]- that the panel's keys switch the look and that it changes the art size.
## [br]It prints what a frame costs without particles and marks, with particles, and with both.
## Exit code 0: every check passed. The pictures still have to be looked at.
extends SceneTree


# region Constants
const SAMPLES: String = "res://splats/samples/"
const OUT_DIR: String = "res://splats/comparisons"
const SETTLE_FRAMES: int = 4
const MEASURE_FRAMES: int = 200

const ART: Vector2i = Vector2i(320, 180)
const SCALE: int = 4
const CAMERA_HEIGHT: float = 2.4
const CAMERA_PITCH: float = 35.0
const CAMERA_YAW: float = 225.0
const CAMERA_DISTANCE: float = 20.0
const LOOK_AT: Vector3 = Vector3(0.1, 0.4, 0.2)
const FRAMES_PER_SECOND: float = 12.0
const FRAMES: int = 48
const STRIP_EVERY: int = 6
const MARK_TIME: float = 1.5

# The lines: a dotted grid of half-metre cells, an outline round the desk set, a small one on free floor.
const CELL: float = 0.5
const GRID_CELLS: int = 6 # each way from the middle
const LINE_HEIGHT: float = 0.012
const GRID_COLOUR: Color = Color8(244, 238, 222, 128)
const OUTLINE_COLOUR: Color = Color8(255, 217, 77)
const FREE_COLOUR: Color = Color8(89, 217, 115)

# One cloud alone, seen straight on, for checking the shader against the rule.
const RULE_ART: int = 256
const RULE_TIMES: PackedFloat32Array = [0.0, 0.7, 1.9, 3.3, 7.1, 12.6, 3500.25]
# endregion


# region State
var _tag: String = ""
var _failures: int = 0
var _holder: Node3D
var _camera: Camera3D
var _scene: SplatScene
var _clouds: Array[SplatInstance] = []
var _desk: SplatInstance
var _background: Color = Color.BLACK
var _has_floor: bool = false
# endregion


# region Lifecycle
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--tag="):
			_tag = "-" + argument.trim_prefix("--tag=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# a seed's last bits are the driver's: the rule is tried rounded each way, and one must fit throughout
	var fits: PackedStringArray = PackedStringArray()
	for fused: bool in [false, true]:
		SplatParticles.fused = fused
		var steam: bool = await _check_rule("fx-steam", SplatInstance.Motion.RISE, 0.5, 0.1, 1.0)
		var dust: bool = await _check_rule("fx-dust", SplatInstance.Motion.DRIFT, 0.12, 0.0, 5.0)
		if steam and dust:
			fits.append("fused" if fused else "rounded after every step")
	SplatParticles.fused = false
	_check(fits.size() == 1, "the shader moves every splat where the rule puts it, with the seed %s" % (fits[0] if fits.size() == 1 else "rounded neither way, or both: %s" % [fits]))
	_build()
	await _particles()
	await _cost() # before anything turns the floor shadows on: their pass, once built, shows in the timings
	await _marks()
	await _panel()
	print("[splat fx] %s" % ("every check passed" if _failures == 0 else "%d check(s) FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
# endregion


# region Checks
func _check(passed: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if passed else "FAIL", message])
	if not passed:
		_failures += 1


# One cloud alone, drawn from straight in front at several times. Each splat the rule says is drawn
# must be found at the sample the rule puts it at, and no sample may be covered far from all of them.
# Returns whether all of them were, and nothing else; prints the counts either way.
func _check_rule(asset: String, motion: SplatInstance.Motion, reach: float, wobble: float, metres: float) -> bool:
	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	var cloud: SplatInstance = SplatInstance.new()
	cloud.asset = SAMPLES + asset + ".bytes"
	cloud.motion = motion
	cloud.motion_reach = reach
	cloud.motion_wobble = wobble
	holder.add_child(cloud)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = metres
	camera.near = 0.1
	camera.far = 40.0
	holder.add_child(camera)
	var middle: Vector3 = Vector3(0.0, reach * 0.5 if motion == SplatInstance.Motion.RISE else 0.0, 0.0)
	camera.look_at_from_position(middle + Vector3(0.0, 0.0, 10.0), middle, Vector3.UP)
	var scene: SplatScene = SplatScene.new()
	scene.camera = camera
	scene.instances_root = holder
	scene.art_size = Vector2i(RULE_ART, RULE_ART)
	scene.fixed_time = 0.0
	holder.add_child(scene)

	var clip: SplatClip = cloud.get_clip()
	var to_pixels: float = RULE_ART * 2.0 / metres
	var reach_pixels: int = 3 + ceili(0.03 * to_pixels) # a splat's own size, and a sample of slack
	var shown_total: int = 0
	var missing: int = 0
	var stray: int = 0
	var hidden_total: int = 0
	for f: int in SETTLE_FRAMES:
		await process_frame
	var builds: int = scene.rebuild_count # the scene before this one leaving the tree may have asked for one more
	for seconds: float in RULE_TIMES:
		scene.fixed_time = seconds
		for f: int in SETTLE_FRAMES:
			await process_frame
		await RenderingServer.frame_post_draw
		var samples: Image = scene.get_samples().get_image()
		var centres: Array[Vector2i] = []
		for i: int in clip.splat_count:
			var moved: Vector4 = SplatParticles.offset_at(motion, i, seconds, reach, wobble, 1.0)
			if moved.w == 0.0:
				hidden_total += 1
				continue
			var o: int = i * SplatClip.STRIDE
			var at: Vector3 = Vector3(clip.splats[o], clip.splats[o + 1], clip.splats[o + 2]) + Vector3(moved.x, moved.y, moved.z) - middle
			var centre: Vector2i = Vector2i(floori(at.x * to_pixels + RULE_ART), floori(RULE_ART - at.y * to_pixels))
			centres.append(centre)
			shown_total += 1
			if not _covered_near(samples, centre, 1):
				missing += 1
		for y: int in samples.get_height():
			for x: int in samples.get_width():
				if samples.get_pixel(x, y).a < 0.5:
					continue
				var near: bool = false
				for centre: Vector2i in centres:
					if absi(centre.x - x) <= reach_pixels and absi(centre.y - y) <= reach_pixels:
						near = true
						break
				if not near:
					stray += 1
	print("[splat fx] %s, seed %s: over %d times the rule draws %d splats and drops %d; %d of those drawn are not where the shader drew one, and %d samples are covered away from all of them" % [
		asset, "fused" if SplatParticles.fused else "rounded after every step", RULE_TIMES.size(), shown_total, hidden_total, missing, stray])
	_check(shown_total > 0 and hidden_total > 0, "%s: the rule draws some splats and drops some" % asset)
	_check(scene.rebuild_count == builds, "%s: the clock moving rebuilt nothing" % asset)
	holder.queue_free()
	await process_frame
	return missing == 0 and stray == 0


func _covered_near(samples: Image, at: Vector2i, slack: int) -> bool:
	for dy: int in range(-slack, slack + 1):
		for dx: int in range(-slack, slack + 1):
			var x: int = at.x + dx
			var y: int = at.y + dy
			if x >= 0 and y >= 0 and x < samples.get_width() and y < samples.get_height() and samples.get_pixel(x, y).a > 0.5:
				return true
	return false
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
	# what a cloud needs: where it starts, how it moves, how far, how wide
	_clouds.append(_cloud(world, "fx-steam", Vector3(-0.45, 0.535, 0.02), SplatInstance.Motion.RISE, 0.18, 0.02))
	_clouds.append(_cloud(world, "fx-steam", Vector3(0.42, 0.6, 0.0), SplatInstance.Motion.RISE, 0.2, 0.03))
	_clouds.append(_cloud(world, "fx-flames", Vector3(1.3, 0.0, 0.1), SplatInstance.Motion.RISE, 0.3, 0.03))
	_clouds.append(_cloud(world, "fx-dust", Vector3(0.0, 1.3, 0.0), SplatInstance.Motion.DRIFT, 0.12, 0.0))

	_scene = SplatScene.new()
	_scene.name = "Picture"
	_scene.camera = _camera
	_scene.instances_root = world
	_scene.art_size = ART
	_scene.fixed_time = 0.0
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


func _cloud(parent: Node3D, id: String, at: Vector3, motion: SplatInstance.Motion, reach: float, wobble: float) -> SplatInstance:
	var cloud: SplatInstance = _add(parent, id, at)
	cloud.motion = motion
	cloud.motion_reach = reach
	cloud.motion_wobble = wobble
	return cloud


# The three kinds of cloud in one scene, frame by frame on a fixed clock.
func _particles() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "/fx-particles" + _tag))
	var strip: Image = Image.create_empty(ART.x * 2 * 3, ART.y * 2 * 2, false, Image.FORMAT_RGBA8)
	var first: Image = null
	var differing: int = 0
	var builds: int = 0
	for f: int in FRAMES:
		var picture: Image = await _shoot(f / FRAMES_PER_SECOND)
		var flat: Image = _over_background(picture)
		flat.save_png("%s/fx-particles%s/%02d.png" % [OUT_DIR, _tag, f])
		if first == null:
			first = picture
			builds = _scene.rebuild_count # a scene of the checks before leaving the tree may have asked for one more
		elif picture.get_data() != first.get_data():
			differing += 1
		if f % STRIP_EVERY == 0 and f / STRIP_EVERY < 6:
			var cell: Image = flat.duplicate()
			cell.resize(ART.x * 2, ART.y * 2, Image.INTERPOLATE_NEAREST)
			var n: int = f / STRIP_EVERY
			strip.blit_rect(cell, Rect2i(Vector2i.ZERO, cell.get_size()), Vector2i((n % 3) * ART.x * 2, (n / 3) * ART.y * 2))
	strip.save_png("%s/fx-particles-strip%s.png" % [OUT_DIR, _tag])
	_check(differing == FRAMES - 1, "the particles move: %d of %d later frames differ from the first" % [differing, FRAMES - 1])
	_check(_scene.rebuild_count == builds, "%d frames of particles rebuilt nothing" % FRAMES)
	var again: Image = await _shoot(0.0)
	_check(again.get_data() == first.get_data(), "the frame at a given time is the same frame when asked for again")
	# what the clouds add to a still frame
	for cloud: SplatInstance in _clouds:
		cloud.motion = SplatInstance.Motion.NONE
	var still_a: Image = await _shoot(0.0)
	var still_b: Image = await _shoot(2.0)
	for c: int in _clouds.size():
		_clouds[c].motion = SplatInstance.Motion.DRIFT if c == _clouds.size() - 1 else SplatInstance.Motion.RISE
	_check(_same_but_avatar(still_a, still_b), "with no motion the clouds stand still")
	_check(_scene.rebuild_count == builds, "giving and taking a motion rebuilt nothing")
	print("[splat fx] %s" % _scene.status())


# With no motion only the avatar's clip changes the picture between two times: compare outside its box.
func _same_but_avatar(a: Image, b: Image) -> bool:
	var changed: Rect2i = Rect2i()
	for y: int in a.get_height():
		for x: int in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				changed = Rect2i(x, y, 1, 1) if changed.size == Vector2i.ZERO else changed.expand(Vector2i(x, y))
	# the avatar is a third of a metre across and typing: its hands and head move within a small box
	return changed.size.x < ART.x / 4 and changed.size.y < ART.y / 3


# A grid, an outline round the desk set and one on free floor, over the scene.
func _marks() -> void:
	var off: Image = await _shoot(MARK_TIME)
	var builds: int = _scene.rebuild_count
	var lines: Array[SplatMark] = _lines()
	_scene.set_marks(lines)
	var on: Image = await _shoot(MARK_TIME)
	_scale(_over_background(on)).save_png("%s/fx-marks%s.png" % [OUT_DIR, _tag])
	_scale(_over_background(off)).save_png("%s/fx-marks-off%s.png" % [OUT_DIR, _tag])
	_check(_scene.mark_count == lines.size() and _scene.rebuild_count == builds, "%d lines, and showing them rebuilt nothing" % _scene.mark_count)
	var uploads: int = _scene.mark_upload_count
	_scene.set_marks(lines)
	await _shoot(MARK_TIME)
	_check(_scene.mark_upload_count == uploads, "the same lines again are not uploaded again")

	var odd_alpha: int = 0
	var covered: int = 0
	var counts: Dictionary[Color, int] = {}
	var changed: int = 0
	var changed_to_other: int = 0
	var grid_on_odd: int = 0
	var marks: Array[Color] = [Color8(GRID_COLOUR.r8, GRID_COLOUR.g8, GRID_COLOUR.b8), OUTLINE_COLOUR, FREE_COLOUR]
	for y: int in on.get_height():
		for x: int in on.get_width():
			var pixel: Color = on.get_pixel(x, y)
			if pixel.a8 != 0 and pixel.a8 != 255:
				odd_alpha += 1
			if pixel.a8 == 255:
				covered += 1
			var is_mark: bool = false
			for mark: Color in marks:
				if pixel.r8 == mark.r8 and pixel.g8 == mark.g8 and pixel.b8 == mark.b8 and pixel.a8 == 255:
					counts[mark] = counts.get(mark, 0) + 1
					is_mark = true
					if mark == marks[0] and (x + y) % 2 == 1:
						grid_on_odd += 1
			if pixel != off.get_pixel(x, y):
				changed += 1
				if not is_mark:
					changed_to_other += 1
	var total: int = on.get_width() * on.get_height()
	_check(odd_alpha == 0, "with marks, every pixel's alpha is 0 or 255: %d of %d are neither (%d covered, %d clear)" % [odd_alpha, total, covered, total - covered])
	_check(counts.get(marks[0], 0) > 100, "the grid's own colour is in the picture (%d pixels)" % counts.get(marks[0], 0))
	_check(grid_on_odd == 0, "the grid is dotted: its colour is on every other art pixel only (%d on the others)" % grid_on_odd)
	_check(counts.get(marks[1], 0) > 50, "the outline's own colour is in the picture (%d pixels)" % counts.get(marks[1], 0))
	_check(counts.get(marks[2], 0) > 20, "the free outline's own colour is in the picture (%d pixels)" % counts.get(marks[2], 0))
	print("[splat fx] the lines changed %d pixels; %d of them took a colour that is not a line's" % [changed, changed_to_other])

	# hidden by what stands in front: the outline passes behind the desk, so with the desk gone it gains pixels
	var with_desk: int = counts.get(marks[1], 0)
	_desk.visible = false
	var bare: Image = await _shoot(MARK_TIME)
	_desk.visible = true
	var without_desk: int = 0
	for y: int in bare.get_height():
		for x: int in bare.get_width():
			var pixel: Color = bare.get_pixel(x, y)
			if pixel.r8 == OUTLINE_COLOUR.r8 and pixel.g8 == OUTLINE_COLOUR.g8 and pixel.b8 == OUTLINE_COLOUR.b8:
				without_desk += 1
	_check(without_desk > with_desk, "the desk hides part of the outline behind it (%d pixels of it with the desk, %d without)" % [with_desk, without_desk])

	# with floor shadows: a shadow's samples are marked by their alpha too, and a line over one keeps its colour
	_desk.casts_shadow = true
	_scene.floor_shadows = true
	var shaded: Image = await _shoot(MARK_TIME)
	_scene.set_marks([])
	var shaded_off: Image = await _shoot(MARK_TIME)
	_scene.floor_shadows = false
	_desk.casts_shadow = false
	_scene.set_marks(lines)
	var shaded_counts: Array[int] = [0, 0, 0]
	var shaded_odd: int = 0
	var darkened: int = 0
	for y: int in shaded.get_height():
		for x: int in shaded.get_width():
			var pixel: Color = shaded.get_pixel(x, y)
			if pixel.a8 != 0 and pixel.a8 != 255:
				shaded_odd += 1
			if shaded_off.get_pixel(x, y) != off.get_pixel(x, y):
				darkened += 1
			for m: int in marks.size():
				if pixel.r8 == marks[m].r8 and pixel.g8 == marks[m].g8 and pixel.b8 == marks[m].b8:
					shaded_counts[m] += 1
	_check(darkened > 100, "floor shadows on: the desk's shadow darkens the floor (%d pixels)" % darkened)
	_check(shaded_odd == 0, "and with the lines over it every pixel's alpha is still 0 or 255")
	_check(shaded_counts == [counts.get(marks[0], 0), counts.get(marks[1], 0), counts.get(marks[2], 0)],
			"and the lines' colours are on as many pixels as without shadows (%s)" % [shaded_counts])

	_scene.set_marks([])
	var cleared: Image = await _shoot(MARK_TIME)
	_check(cleared.get_data() == off.get_data(), "with the lines taken away the picture is what it was")


func _lines() -> Array[SplatMark]:
	var lines: Array[SplatMark] = []
	var reach: float = GRID_CELLS * CELL
	for i: int in range(-GRID_CELLS, GRID_CELLS + 1):
		lines.append(SplatMark.new(Vector3(i * CELL, LINE_HEIGHT, -reach), Vector3(i * CELL, LINE_HEIGHT, reach), Vector3.UP, GRID_COLOUR))
		lines.append(SplatMark.new(Vector3(-reach, LINE_HEIGHT, i * CELL), Vector3(reach, LINE_HEIGHT, i * CELL), Vector3.UP, GRID_COLOUR))
	lines.append_array(SplatMark.outline(Vector3(0.0, LINE_HEIGHT, 0.25), Vector3(0.75, 0.0, 0.0), Vector3(0.0, 0.0, 0.75), Vector3.UP, OUTLINE_COLOUR))
	lines.append_array(SplatMark.outline(Vector3(-1.25, LINE_HEIGHT, 0.25), Vector3(0.25, 0.0, 0.0), Vector3(0.0, 0.0, 0.25), Vector3.UP, FREE_COLOUR))
	return lines


# What a frame costs: without clouds or lines, with the clouds, with both, and without again, which
# shows how much the numbers wander by themselves.
func _cost() -> void:
	for cloud: SplatInstance in _clouds:
		cloud.visible = false
	var plain: Array = await _measure()
	for cloud: SplatInstance in _clouds:
		cloud.visible = true
	var with_clouds: Array = await _measure()
	_scene.set_marks(_lines())
	var with_both: Array = await _measure()
	_scene.set_marks([])
	for cloud: SplatInstance in _clouds:
		cloud.visible = false
	var plain_again: Array = await _measure()
	for cloud: SplatInstance in _clouds:
		cloud.visible = true
	_scene.fixed_time = 0.0
	for row: Array in [["no clouds, no lines", plain], ["four clouds", with_clouds], ["four clouds and %d lines" % _lines().size(), with_both], ["no clouds, no lines, again", plain_again]]:
		var cost: Array = row[1]
		print("[splat fx] cost, %s: %d splats; script %.3f ms a frame; passes %.2f ms CPU, %.2f ms GPU; rebuild %.1f ms" % [row[0], cost[0], cost[1], cost[2], cost[3], cost[4]])


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


# The debug panel over the picture: opened and switched by its keys, as a player would.
func _panel() -> void:
	var panel: SplatDebugPanel = SplatDebugPanel.add_to(root)
	if panel == null:
		_check(not OS.is_debug_build(), "a release build makes no debug panel")
		return
	_scene.fixed_time = MARK_TIME
	await process_frame
	_check(panel.get_scenes().size() == 1 and not panel.open, "the panel found the picture and starts closed")
	_press(panel.toggle_key)
	await _settle()
	_check(panel.open, "its key opens it")
	root.get_texture().get_image().save_png("%s/fx-panel-average%s.png" % [OUT_DIR, _tag])
	var average: Image = _scene.get_picture().get_image()
	_press(panel.look_key)
	await _settle()
	_check(_scene.interior == SplatScene.Interior.VOTE, "its look key switches the picture to the vote")
	root.get_texture().get_image().save_png("%s/fx-panel-vote%s.png" % [OUT_DIR, _tag])
	var vote: Image = _scene.get_picture().get_image()
	var differing: int = 0
	for y: int in vote.get_height():
		for x: int in vote.get_width():
			if vote.get_pixel(x, y) != average.get_pixel(x, y):
				differing += 1
	_check(differing > 0, "and the picture changes with it (%d of %d pixels)" % [differing, vote.get_width() * vote.get_height()])
	panel.set_art_height(0, 90)
	await _settle()
	var small: Vector2i = _scene.get_picture().get_image().get_size()
	_check(small == Vector2i(160, 90), "the art size changes live (%d x %d)" % [small.x, small.y])
	root.get_texture().get_image().save_png("%s/fx-panel-art-90%s.png" % [OUT_DIR, _tag])
	panel.reset_art_sizes()
	_press(panel.look_key)
	await _settle()
	_check(_scene.art_size == ART and _scene.interior == SplatScene.Interior.AVERAGE, "and both go back")


func _press(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var key: InputEventKey = InputEventKey.new()
		key.keycode = keycode
		key.physical_keycode = keycode
		key.pressed = pressed
		Input.parse_input_event(key)


func _settle() -> void:
	for f: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw


func _shoot(seconds: float) -> Image:
	_scene.fixed_time = seconds
	await _settle()
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
