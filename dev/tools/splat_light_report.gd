## Captures, checks and measures the splat renderer's light: lamps, dusk and floor shadows, in a
## furnished room. It needs a window (a headless run draws nothing), and a room's assets, which this
## repository does not hold: hand them to [code]dev/make_project.py --samples <folder>[/code]. It
## looks for floor, wall, shell-window, shell-light, desk-set, lamp, plant and avatar-a to avatar-d.
##
##   godot --path . -s res://splats/tools/splat_light_report.gd
##   godot --path . --rendering-method forward_plus -s res://splats/tools/splat_light_report.gd -- --tag=forward
##   ... -- --reference=<folder>     also writes each picture beside the reference render of the same name
##   ... -- --look=vote              the vote look inside shapes (the references were made with it); the default is the average
##
## It writes to [code]splats/comparisons/[/code]:
## [br]- [code]light-day-lamp[/code], [code]light-evening-lamp[/code]: the furnished room with floor
## shadows and a standing lamp, by day and two ramp steps into dusk.
## [br]- [code]shell-dusk-step0[/code]: the empty room at dusk, lit by its two hanging lights.
## [br]- [code]shell-day-step0[/code]: the empty room by day. Nothing in it is lit again or shaded,
## so what differs from its reference here is what differed before there was any light.
## [br]- [code]<name>-beside[/code]: the reference on the left, ours on the right, and
## [code]<name>-differs[/code]: ours dimmed, with every pixel that differs from the reference marked.
## [br]- [code]light-plain[/code]: the furnished room with none of it, as the renderer drew it before.
## [br]The reference renders are a Unity renderer's of the same room. Unity's z runs north where
## Godot's runs south, so the room below is that room with every z negated and every yaw turned the
## other way: the same room, and the same picture.
## [br][br]
## Then it checks the shaders against the rules in script ([SplatLight]): the lit picture against one
## whose colours the script worked out, and the shadow cells the GPU marked against the script's.
## Last it measures a frame and a rebuild, without and with the light, for the whole room and for a
## smaller one.
extends SceneTree


# region Constants
const SAMPLES: String = "res://splats/samples/"
const OUT_DIR: String = "res://splats/comparisons"
const NEEDED: PackedStringArray = ["floor", "wall", "shell-window", "shell-light", "desk-set", "lamp", "plant", "avatar-a", "avatar-b", "avatar-c", "avatar-d"]
const ART: Vector2i = Vector2i(640, 360)
const SCALE: int = 2
const SETTLE_FRAMES: int = 6
const MEASURE_FRAMES: int = 400

# The room: 12 x 12 cells of half a metre, x from 0 to 6 and z from 0 to -6, walls 3 m high.
const CELL: float = 0.5
const SIZE: float = 6.0
# The camera: orthographic, 35 degrees down, turned in quarter turns about the room's middle.
const CAMERA_PITCH: float = 35.0
const CAMERA_DISTANCE: float = 20.0
const CAMERA_HEIGHT: float = 8.4
const LOOK_AT: Vector3 = Vector3(3.0, 1.1, -3.0)
# The desk set's and the sitter's own frame: their scale, and where their origin lies in the art.
const SET_SCALE: float = 0.8
const SET_OFFSET_Z: float = 0.246
# What lies on a wall is depth-tested this much nearer, so the wall does not hatch through it.
const LYING_BIAS: float = 0.06
const LAMP_REACH: float = 3.0
const LAMP_STRENGTH: float = 0.9
const HANGING_REACH: float = 2.2
const HANGING_STRENGTH: float = 0.5
const EVENING: int = 2
# Walls by the side they stand on: the middle of the base, the yaw of the wall's splat, the way its
# face looks, and the yaw of what hangs on it. Degrees about y, Godot's way (counter-clockwise from above).
const WALLS: Dictionary[String, Dictionary] = {
	"north": {"base": Vector3(3.0, 0.0, -6.0), "yaw": 0.0, "inward": Vector2(0.0, 1.0), "hung": 180.0},
	"east": {"base": Vector3(6.0, 0.0, -3.0), "yaw": -90.0, "inward": Vector2(-1.0, 0.0), "hung": 90.0},
	"south": {"base": Vector3(3.0, 0.0, 0.0), "yaw": 180.0, "inward": Vector2(0.0, -1.0), "hung": 0.0},
	"west": {"base": Vector3(0.0, 0.0, -3.0), "yaw": 90.0, "inward": Vector2(1.0, 0.0), "hung": -90.0},
}
# What the room has on its walls: a window (4 x 3 cells) or a hanging light (1 x 2), by its first cell.
const FIXTURES: Array[Dictionary] = [
	{"wall": "north", "light": false, "x": 4, "y": 2}, {"wall": "south", "light": false, "x": 4, "y": 2},
	{"wall": "east", "light": true, "x": 2, "y": 3}, {"wall": "east", "light": true, "x": 9, "y": 3},
	{"wall": "west", "light": true, "x": 2, "y": 3}, {"wall": "west", "light": true, "x": 9, "y": 3},
]
# Desk sets, each with a typist: the first cell of its 2 x 2 cells, its yaw, and who sits at it.
const DESKS: Array[Dictionary] = [
	{"x": 2, "y": 7, "yaw": 0.0, "avatar": "avatar-a"}, {"x": 7, "y": 7, "yaw": 0.0, "avatar": "avatar-b"},
	{"x": 8, "y": 2, "yaw": 90.0, "avatar": "avatar-c"}, {"x": 2, "y": 2, "yaw": -90.0, "avatar": "avatar-d"},
]
const LAMP_CELL: Vector2i = Vector2i(4, 9)
const PLANT_CELLS: Array[Vector2i] = [Vector2i(0, 11), Vector2i(5, 5)]
# endregion


# region State
var _tag: String = ""
var _reference: String = ""
var _vote: bool = false
var _holder: Node3D
var _camera: Camera3D
var _scene: SplatScene
var _furniture: Node3D
var _avatars: Array[SplatInstance] = []
var _walls: Dictionary[String, Node3D] = {}
var _standing_lamp: SplatLamp
var _hanging: Array[SplatLamp] = []
var _fixtures: Array[SplatInstance] = []
var _background: Color
# endregion


# region Lifecycle
func _initialize() -> void:
	_run.call_deferred()
# endregion


# region Report
func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--tag="):
			_tag = "-" + argument.trim_prefix("--tag=")
		if argument.begins_with("--reference="):
			_reference = argument.trim_prefix("--reference=")
		if argument == "--look=vote":
			_vote = true
	for id: String in NEEDED:
		if not FileAccess.file_exists(SAMPLES + id + ".bytes"):
			print("[light report] %s%s.bytes is missing. Assemble the project with --samples <a room's assets>." % [SAMPLES, id])
			quit(1)
			return
	print("[light report] renderer: %s, %s; the %s look" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), "vote" if _vote else "average"])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_build()

	# as the renderer drew it before: no lamp, no dusk, no shadow
	_set_light(1, 0, false, false, false, true)
	var plain: Image = await _shoot("light-plain")
	_scene.lamp_light = true
	_scene.dusk = 0
	_scene.floor_shadows = false
	_standing_lamp.visible = false
	var plain_again: Image = await _picture()
	print("[light report] with no lamp shown, no dusk and no shadows the picture is the plain one: %s" % _same(plain, plain_again))

	_set_light(1, 0, true, false, true, true)
	await _shoot("light-day-lamp")
	_set_light(1, EVENING, true, false, true, true)
	await _shoot("light-evening-lamp")
	_set_light(0, EVENING, false, true, true, false)
	_scene.fixed_time = 0.0
	await _shoot("shell-dusk-step0")
	_set_light(0, 0, false, false, true, false)
	await _shoot("shell-day-step0")
	_scene.fixed_time = 3.0

	await _check_relight()
	await _check_shadow_cells()
	await _measure("the whole room")
	# a smaller room, of about 174,000 splats: without what hangs on the walls and two of the typists
	for look: SplatInstance in _fixtures:
		look.visible = false
	_avatars[0].visible = false
	_avatars[2].visible = false
	await _measure("the smaller room")
	quit(0)


# One picture: saved over the background, scaled up, and beside its reference when there is one.
func _shoot(id: String) -> Image:
	var ours: Image = await _picture()
	var big: Image = ours.duplicate()
	big.resize(ART.x * SCALE, ART.y * SCALE, Image.INTERPOLATE_NEAREST)
	big.save_png(ProjectSettings.globalize_path("%s/%s%s.png" % [OUT_DIR, id, _tag]))
	print("[light report] %s: %s" % [id, _scene.status()])
	var path: String = _reference.path_join(id + ".png")
	if _reference.is_empty() or not FileAccess.file_exists(path):
		return ours

	# The reference is a window's capture, each art pixel a block: take each block's middle.
	var shot: Image = Image.load_from_file(path)
	shot.convert(Image.FORMAT_RGBA8)
	# its background is its camera's own colour: ours is put over the same one
	var behind: Color = shot.get_pixel(0, 0)
	for y: int in ART.y:
		for x: int in ART.x:
			if ours.get_pixel(x, y).to_rgba32() == _background.to_rgba32():
				ours.set_pixel(x, y, behind)
	big = ours.duplicate()
	big.resize(ART.x * SCALE, ART.y * SCALE, Image.INTERPOLATE_NEAREST)
	var block: int = shot.get_width() / ART.x
	var reference: Image = Image.create_empty(ART.x, ART.y, false, Image.FORMAT_RGBA8)
	var differs: Image = Image.create_empty(ART.x, ART.y, false, Image.FORMAT_RGBA8)
	var equal: int = 0
	var same_cover: int = 0
	for y: int in ART.y:
		for x: int in ART.x:
			var theirs: Color = shot.get_pixel(x * block + block / 2, y * block + block / 2)
			reference.set_pixel(x, y, theirs)
			var mine: Color = ours.get_pixel(x, y)
			if theirs.to_rgba32() == mine.to_rgba32():
				equal += 1
				differs.set_pixel(x, y, mine.darkened(0.65))
			else:
				differs.set_pixel(x, y, Color.MAGENTA)
			if (theirs.to_rgba32() == behind.to_rgba32()) == (mine.to_rgba32() == behind.to_rgba32()):
				same_cover += 1
	var total: float = ART.x * ART.y
	print("[light report] %s against its reference: %d of %d pixels differ (%.2f%% the same colour), %.1f%% the same coverage" % [
			id, ART.x * ART.y - equal, ART.x * ART.y, 100.0 * equal / total, 100.0 * same_cover / total])
	differs.resize(ART.x * SCALE, ART.y * SCALE, Image.INTERPOLATE_NEAREST)
	differs.save_png(ProjectSettings.globalize_path("%s/%s-differs%s.png" % [OUT_DIR, id, _tag]))
	reference.resize(ART.x * SCALE, ART.y * SCALE, Image.INTERPOLATE_NEAREST)
	var gap: int = 16
	var sheet: Image = Image.create_empty(big.get_width() * 2 + gap, big.get_height(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.5, 0.5, 0.5))
	sheet.blit_rect(reference, Rect2i(Vector2i.ZERO, reference.get_size()), Vector2i.ZERO)
	sheet.blit_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i(big.get_width() + gap, 0))
	sheet.save_png(ProjectSettings.globalize_path("%s/%s-beside%s.png" % [OUT_DIR, id, _tag]))
	return ours


# The scene's picture over the background colour, once it has settled.
func _picture() -> Image:
	for f: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = _scene.get_picture().get_image()
	picture.convert(Image.FORMAT_RGBA8)
	var over: Image = Image.create_empty(picture.get_width(), picture.get_height(), false, Image.FORMAT_RGBA8)
	over.fill(_background)
	over.blend_rect(picture, Rect2i(Vector2i.ZERO, picture.get_size()), Vector2i.ZERO)
	return over


static func _same(a: Image, b: Image) -> String:
	var different: int = 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			if a.get_pixel(x, y).to_rgba32() != b.get_pixel(x, y).to_rgba32():
				different += 1
	return "every pixel the same" if different == 0 else "%d of %d pixels differ" % [different, a.get_width() * a.get_height()]
# endregion


# region Checks
# The shader's lamps and dusk against SplatLight.relight: the same room drawn with the colours the
# script works out and no light asked of the shader. Without the typists: the script lights a clip
# where the file has it, the shader where its bones put it.
func _check_relight() -> void:
	_set_light(1, EVENING, true, true, false, true)
	for avatar: SplatInstance in _avatars:
		avatar.visible = false
	var by_shader: Image = await _picture()

	var lamps: PackedVector4Array = PackedVector4Array()
	var strengths: PackedFloat32Array = PackedFloat32Array()
	for lamp: SplatLamp in _scene._lamps:
		var at: Vector3 = lamp.global_position
		lamps.append(Vector4(at.x, at.y, at.z, lamp.radius))
		strengths.append(lamp.strength)
	var data: PackedFloat32Array = PackedFloat32Array()
	var splats: int = 0
	var changed: int = 0
	var started: int = Time.get_ticks_usec()
	for n: int in _scene._instances.size():
		var instance: SplatInstance = _scene._instances[n]
		var clip: SplatClip = instance.get_clip()
		var turn: int = SplatClip.turn_of(instance.global_rotation.y)
		data.append_array(clip.splats)
		for i: int in clip.splat_count:
			var o: int = (splats + i) * SplatClip.STRIDE
			if clip.is_prop():
				data[o + 7] = clip.colour_sets[turn][i]
			data[o + 15] = n
		changed += SplatLight.relight(clip, turn, instance.global_transform, lamps, strengths, EVENING, data, splats)
		splats += clip.splat_count
	var script_msec: float = (Time.get_ticks_usec() - started) / 1000.0
	var rows: int = maxi(1, ceili(splats / 256.0))
	data.resize(rows * 1024 * 4)
	_scene._draw_material.set_shader_parameter(&"splats", ImageTexture.create_from_image(
			Image.create_from_data(1024, rows, false, Image.FORMAT_RGBAF, data.to_byte_array())))
	_scene.dusk = 0
	_scene.lamp_light = false
	var by_script: Image = await _picture()
	print("[light report] lamps and dusk, the shader against the script's rules (%d lamps, dusk %d, %d splats, %d of them relit): %s" % [
			lamps.size(), EVENING, splats, changed, _same(by_shader, by_script)])
	print("[light report] the script took %.0f ms to light those splats; the shader does it within the frame" % script_msec)
	for avatar: SplatInstance in _avatars:
		avatar.visible = true # the scene gathers again, with its own colours


# The cells the shadow pass marked against SplatLight.shadow_cells, without the typists (as above).
func _check_shadow_cells() -> void:
	_set_light(1, 0, true, false, true, true)
	for avatar: SplatInstance in _avatars:
		avatar.visible = false
	await _picture()
	var marked: Image = _scene.get_shadow_cells().get_image()
	var first: Vector2i = _scene.get_shadow_first_cell()
	var by_shader: Dictionary[Vector2i, bool] = {}
	for y: int in marked.get_height():
		for x: int in marked.get_width():
			if marked.get_pixel(x, y).a > 0.5:
				by_shader[first + Vector2i(x, y)] = true
	var by_script: Dictionary[Vector2i, bool] = {}
	for instance: SplatInstance in _scene._instances:
		if instance.casts_shadow:
			SplatLight.shadow_cells(instance.get_clip(), instance.global_transform, _scene.sun, _scene.shadow_cell, by_script, _scene.floor_height)
	var only_shader: int = 0
	var only_script: int = 0
	for cell: Vector2i in by_shader:
		if not by_script.has(cell):
			only_shader += 1
	for cell: Vector2i in by_script:
		if not by_shader.has(cell):
			only_script += 1
	print("[light report] shadow cells, the shader against the script's rule: %d and %d cells, %d only the shader's, %d only the script's" % [
			by_shader.size(), by_script.size(), only_shader, only_script])
	for avatar: SplatInstance in _avatars:
		avatar.visible = true
# endregion


# region Measuring
func _measure(what: String) -> void:
	_scene.measure_render_time = true
	_scene.fixed_time = -1.0 # the clips play
	_set_light(1, 0, false, false, false, true)
	var plain: Dictionary = await _cost()
	_set_light(1, EVENING, true, false, true, true)
	var rebuilds: int = _scene.rebuild_count
	var lit: Dictionary = await _cost(true)
	print("[light report] %s: %d splats in %d instances, art %dx%d" % [what, _scene.splat_count, _scene.instance_count, ART.x, ART.y])
	for row: Array in [["no light", plain], ["floor shadows, one lamp, dusk %d" % EVENING, lit]]:
		var cost: Dictionary = row[1]
		print("[light report] %s: passes %.3f ms GPU and %.3f ms CPU a frame, the scene's script %.3f ms, the whole frame %.2f ms (%d frames)" % [
				row[0], cost["gpu"], cost["cpu"], cost["script"], cost["frame"], MEASURE_FRAMES])
	print("[light report] the lamp was carried round the room for those frames: %d rebuilds" % (_scene.rebuild_count - rebuilds))

	var total: float = 0.0
	var worst: float = 0.0
	for r: int in 10:
		SplatInstance.version += 1 # as when an instance appears
		await process_frame
		await process_frame
		total += _scene.last_rebuild_msec
		worst = maxf(worst, _scene.last_rebuild_msec)
	print("[light report] rebuild, when the room's contents change: %.1f ms on average over 10, %.1f ms at worst" % [total / 10.0, worst])


# What a frame costs, averaged. With carry, the standing lamp moves every frame.
func _cost(carry: bool = false) -> Dictionary:
	for f: int in 30:
		await process_frame
	var gpu: float = 0.0
	var cpu: float = 0.0
	var script: float = 0.0
	var started: int = Time.get_ticks_usec()
	var home: Vector3 = _standing_lamp.get_parent_node_3d().position
	for f: int in MEASURE_FRAMES:
		if carry:
			_standing_lamp.get_parent_node_3d().position = home + Vector3(sin(f * 0.05), 0.0, cos(f * 0.05) - 1.0)
		await process_frame
		var passes: Vector2 = _scene.get_render_msec()
		cpu += passes.x
		gpu += passes.y
		script += _scene.last_cpu_msec
	var frame: float = (Time.get_ticks_usec() - started) / 1000.0 / MEASURE_FRAMES
	_standing_lamp.get_parent_node_3d().position = home
	return {"gpu": gpu / MEASURE_FRAMES, "cpu": cpu / MEASURE_FRAMES, "script": script / MEASURE_FRAMES, "frame": frame}
# endregion


# region The room
# The camera's quarter turn, the dusk, and what is lit and shown.
func _set_light(step: int, dusk: int, standing_lamp: bool, hanging_lights: bool, shadows: bool, furnished: bool) -> void:
	# the camera stands off the room's middle, turned 45 degrees and then a quarter turn a step
	var yaw: float = deg_to_rad(45.0 + 90.0 * step)
	var pitch: float = deg_to_rad(CAMERA_PITCH)
	var away: Vector3 = Vector3(-cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * CAMERA_DISTANCE
	_camera.look_at_from_position(LOOK_AT + away, LOOK_AT, Vector3.UP)
	# the two walls between the camera and the room hide, with what hangs on them
	var forward: Vector2 = Vector2(-away.x, -away.z)
	for side: String in WALLS:
		_walls[side].visible = (WALLS[side]["inward"] as Vector2).dot(forward) < -1e-6
	_furniture.visible = furnished
	_scene.dusk = dusk
	_scene.lamp_light = true
	_scene.floor_shadows = shadows
	_standing_lamp.visible = standing_lamp
	for light: SplatLamp in _hanging:
		light.visible = hanging_lights


func _build() -> void:
	_holder = Node3D.new()
	root.add_child(_holder)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CAMERA_HEIGHT
	_camera.near = 0.3
	_camera.far = 60.0
	_holder.add_child(_camera)

	var room: Node3D = Node3D.new()
	_holder.add_child(room)
	var floor_splat: SplatInstance = _add(room, "floor", Vector3(SIZE / 2.0, 0.0, -SIZE / 2.0), 0.0, false)
	_background = Color.hex((floor_splat.get_clip().palette[0] << 8) | 0xff)
	for side: String in WALLS:
		var wall: Dictionary = WALLS[side]
		var wall_root: Node3D = Node3D.new()
		room.add_child(wall_root)
		_walls[side] = wall_root
		_add(wall_root, "wall", wall["base"], wall["yaw"], false)
	for fixture: Dictionary in FIXTURES:
		var wall: Dictionary = WALLS[fixture["wall"]]
		var hung: Basis = Basis(Vector3.UP, deg_to_rad(wall["hung"]))
		var cells: Vector2 = Vector2(1.0, 2.0) if fixture["light"] else Vector2(4.0, 3.0)
		var at: Vector3 = (wall["base"] as Vector3) + hung.x * ((fixture["x"] + cells.x / 2.0) * CELL - SIZE / 2.0) + Vector3.UP * ((fixture["y"] + cells.y / 2.0) * CELL)
		var look: SplatInstance = _add(_walls[fixture["wall"]], "shell-light" if fixture["light"] else "shell-window", at, wall["hung"], false)
		look.depth_bias = LYING_BIAS
		_fixtures.append(look)
		if fixture["light"]:
			# the shade hangs out from the wall
			var bulb: SplatLamp = SplatLamp.new()
			bulb.radius = HANGING_REACH
			bulb.strength = HANGING_STRENGTH
			bulb.position = at + hung * Vector3(0.0, 0.02, -0.3)
			_walls[fixture["wall"]].add_child(bulb)
			_hanging.append(bulb)

	_furniture = Node3D.new()
	room.add_child(_furniture)
	for d: int in DESKS.size():
		var desk: Dictionary = DESKS[d]
		var item: Node3D = _item(Vector2i(desk["x"], desk["y"]), 2, desk["yaw"])
		for id: String in ["desk-set", desk["avatar"]]:
			var splat: SplatInstance = _add(item, id, Vector3(0.0, 0.0, SET_OFFSET_Z), 180.0, true)
			splat.scale = Vector3.ONE * SET_SCALE
			if id != "desk-set":
				splat.time_offset = d * 1.7
				_avatars.append(splat)
	var lamp: Node3D = _item(LAMP_CELL, 1, 0.0)
	_add(lamp, "lamp", Vector3.ZERO, 0.0, true)
	_standing_lamp = SplatLamp.new()
	_standing_lamp.radius = LAMP_REACH
	_standing_lamp.strength = LAMP_STRENGTH
	_standing_lamp.position = Vector3(0.0, 1.05, 0.0) # the middle of its shade
	lamp.add_child(_standing_lamp)
	for cell: Vector2i in PLANT_CELLS:
		_add(_item(cell, 1, 0.0), "plant", Vector3.ZERO, 0.0, true)

	_scene = SplatScene.new()
	_scene.camera = _camera
	_scene.instances_root = room
	_scene.art_size = ART
	_scene.interior = SplatScene.Interior.VOTE if _vote else SplatScene.Interior.AVERAGE
	_scene.fixed_time = 3.0
	_holder.add_child(_scene)
	var show: TextureRect = TextureRect.new()
	show.texture = _scene.get_picture()
	show.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	show.set_anchors_preset(Control.PRESET_FULL_RECT)
	show.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(show)


# A floor item on its cells: its origin in the middle of them.
func _item(cell: Vector2i, cells: int, yaw_degrees: float) -> Node3D:
	var item: Node3D = Node3D.new()
	item.position = Vector3((cell.x + cells / 2.0) * CELL, 0.0, -(cell.y + cells / 2.0) * CELL)
	item.rotation.y = deg_to_rad(yaw_degrees)
	_furniture.add_child(item)
	return item


func _add(parent: Node3D, id: String, at: Vector3, yaw_degrees: float, shadow: bool) -> SplatInstance:
	var instance: SplatInstance = SplatInstance.new()
	instance.asset = SAMPLES + id + ".bytes"
	instance.position = at
	instance.rotation.y = deg_to_rad(yaw_degrees)
	instance.casts_shadow = shadow
	parent.add_child(instance)
	return instance
# endregion
