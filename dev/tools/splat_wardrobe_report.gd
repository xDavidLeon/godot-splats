## Captures and checks the wardrobe and the clips: eight avatars standing in a row, each in a look
## of its own, and one avatar at its desk passing through every clip of its file with a fade from
## each to the next. It needs a window (a headless run draws nothing):
##
##   godot --path . -s res://splats/tools/splat_wardrobe_report.gd
##   ... -- --reference=<folder>   also writes the looks under a reference render of the same row
##                                 (avatar-looks.png in that folder)
##   ... -- --seated=<file>        the file whose clips are played (in splats/samples); the default is
##                                 avatar-a.bytes, drawn with the sample desk set
##   ... -- --tag=<word>           added to the file names, to keep one renderer's pictures from another's
##
## It writes to [code]splats/comparisons/[/code]:
## [br]- [code]looks[/code]: the eight looks, three screen pixels an art pixel. With a floor in
## [code]splats/samples[/code] (floor.bytes, handed to [code]dev/make_project.py --samples[/code];
## this repository holds none) they stand on it and shade it.
## [br]- [code]looks-beside[/code]: the reference above, ours below.
## [br]- [code]clips/NNN[/code]: 180 frames at 12 a second, 30 for each clip, to make a GIF of.
## [br]Then it checks what a picture can show: that a change of look or of clip rebuilds nothing,
## that each look's colours are in the picture and the one before it's are gone, and that a piece
## left out is not drawn. It prints what a change of look costs beside what a rebuild costs.
## Exit code 0: every check passed. The pictures still have to be looked at.
##
## Which pieces and colours make a look is a game's own business. The looks here are a table in this
## file: the pieces by the names the sample file gives them, and each colour region's ramp worked out
## from one picked colour the way the sample art does it ([method ramp_of]).
## [br]The reference render is a Unity renderer's of the same row. Unity's z runs the other way, so
## the row below is that row with every z negated and every yaw turned the other way: the same row,
## and the same picture.
extends SceneTree


# region Constants
const SAMPLES: String = "res://splats/samples/"
const OUT_DIR: String = "res://splats/comparisons"
const STANDING: String = "avatar-a-stand.bytes"
const SEATED: String = "avatar-a.bytes"
const DESK: String = "desk-set.bytes"
const FLOOR: String = "floor.bytes"
const SETTLE_FRAMES: int = 4
const MEASURE_FRAMES: int = 200

# The row: a room of half-metre cells, x from 0 to 6 and z from 0 to -6, seen by an orthographic
# camera 35 degrees down and turned 45, as the reference was.
const ART: Vector2i = Vector2i(640, 360)
const SCALE: int = 3
const CELL: float = 0.5
const ROOM: float = 6.0
const CAMERA_PITCH: float = 35.0
const CAMERA_YAW: float = 45.0
const CAMERA_DISTANCE: float = 20.0
const CAMERA_HEIGHT: float = 3.57
const LOOK_AT: Vector3 = Vector3(3.0, 1.1, -3.0)
const AVATAR_SCALE: float = 0.8
const STAND_OFFSET_Z: float = 0.496
const ROW_YAW: float = -60.0
const ROW_TIME: float = 1.5
const ROW_TIME_STEP: float = 1.3

# The desk: a perspective camera three quarters down onto it, and a square picture.
const DESK_ART: Vector2i = Vector2i(107, 107)
const DESK_SCALE: int = 6
const DESK_FOV: float = 30.0
const DESK_LOOK_AT: Vector3 = Vector3(0.12, 0.42, -0.05)
const DESK_PITCH: float = 20.0
const DESK_YAW: float = 30.0
const DESK_DISTANCE: float = 3.45
const SEAT_OFFSET_Z: float = 0.246
const BACKDROP: Color = Color8(70, 90, 120)
const FRAMES_PER_SECOND: float = 12.0
const FRAMES_A_CLIP: int = 30
const FADE_SECONDS: float = 0.3
# The clips in the order they are played, each with the thing on the desk that goes with it.
const CLIPS: Array[Array] = [
	["sitting", "laptop"], ["typing", "laptop"], ["writing", "notebook"], ["drawing", "sketchbook"], ["reading", "book"], ["finished", "book"],
]

# What every look starts from: one picked colour a region.
const BASIC: Dictionary[String, int] = {
	"skin": 0xFAD1B2, "hair": 0x4C301F, "top": 0x5C8FD1, "bottom": 0x4C5775, "socks": 0xF2EDE6, "shoes": 0x4C423D,
}
# The eight looks: the hairstyle, the top, what else is worn, whether the hair shows (a hat hides
# it), and the colours picked.
const LOOKS: Array[Dictionary] = [
	{"hair": "bun", "top": "sweater", "worn": [], "hair_shows": true, "colours": {}},
	{"hair": "messy", "top": "sweater", "worn": [], "hair_shows": true, "colours": {"hair": 0x2A2226, "skin": 0x9A6248, "top": 0x3F8A86}},
	{"hair": "bun", "top": "stripes", "worn": [], "hair_shows": true, "colours": {"top": 0x4F7AA8, "hair": 0xD8B060}},
	{"hair": "messy", "top": "cable-knit", "worn": ["glasses-round"], "hair_shows": true, "colours": {"top": 0xF0E0C0, "bottom": 0x8A6F52}},
	{"hair": "bun", "top": "sweater", "worn": ["headband"], "hair_shows": true, "colours": {"skin": 0x5E3A28, "hair": 0x1E1614, "top": 0xE8C040}},
	{"hair": "messy", "top": "sweater", "worn": ["headphones-round"], "hair_shows": true, "colours": {"top": 0x9A5FB0, "shoes": 0xD8D2C8}},
	{"hair": "bun", "top": "stripes", "worn": ["beanie"], "hair_shows": false, "colours": {"skin": 0xF6DCC8, "top": 0xD0A030}},
	{"hair": "bun", "top": "sweater", "worn": ["glasses-round", "headphones-round"], "hair_shows": true,
		"colours": {"skin": 0xC68A5E, "hair": 0x3A2A4A, "top": 0xB8443F, "socks": 0xC8553A}},
]
# endregion


# region State
var _tag: String = ""
var _reference: String = ""
var _seated: String = SEATED
var _failures: int = 0
# endregion


# region Lifecycle
func _initialize() -> void:
	_run.call_deferred()
# endregion


# region The run
func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--tag="):
			_tag = "-" + argument.trim_prefix("--tag=")
		elif argument.begins_with("--reference="):
			_reference = argument.trim_prefix("--reference=")
		elif argument.begins_with("--seated="):
			_seated = argument.trim_prefix("--seated=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_check_ramps()
	await _looks()
	await _clips()
	print("[wardrobe report] %s" % ("every check passed" if _failures == 0 else "%d check(s) FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


func _check(passed: bool, what: String) -> void:
	print("%s: %s" % ["PASS" if passed else "FAIL", what])
	if not passed:
		_failures += 1
# endregion


# region The looks
func _looks() -> void:
	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAMERA_HEIGHT
	camera.near = 0.3
	camera.far = 60.0
	holder.add_child(camera)
	var yaw: float = deg_to_rad(CAMERA_YAW)
	var pitch: float = deg_to_rad(CAMERA_PITCH)
	camera.look_at_from_position(LOOK_AT + Vector3(-cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * CAMERA_DISTANCE, LOOK_AT, Vector3.UP)

	var room: Node3D = Node3D.new()
	holder.add_child(room)
	var has_floor: bool = FileAccess.file_exists(SAMPLES + FLOOR)
	if has_floor:
		var floor_splat: SplatInstance = SplatInstance.new()
		floor_splat.asset = SAMPLES + FLOOR
		floor_splat.position = Vector3(ROOM / 2.0, 0.0, -ROOM / 2.0)
		floor_splat.casts_shadow = false
		room.add_child(floor_splat)
	var row: Array[SplatInstance] = []
	for i: int in LOOKS.size():
		# a row across the room, each standing over its own cell and facing the camera's side
		var avatar: SplatInstance = _stander(room, Vector2i(2 + i, 9 - i))
		avatar.time_offset = i * ROW_TIME_STEP
		avatar.wear(pieces_of(LOOKS[i]), ramps_of(LOOKS[i]))
		row.append(avatar)
	var clip: SplatClip = row[0].get_clip()
	var background: Color = Color.hex((clip.palette[0] << 8) | 0xff)

	var scene: SplatScene = SplatScene.new()
	scene.camera = camera
	scene.instances_root = room
	scene.art_size = ART
	scene.floor_shadows = has_floor
	scene.fixed_time = ROW_TIME
	scene.measure_render_time = true
	holder.add_child(scene)
	_show(scene)

	var ours: Image = _over(await _picture(scene), background)
	ours.resize(ART.x * SCALE, ART.y * SCALE, Image.INTERPOLATE_NEAREST)
	ours.save_png("%s/looks%s.png" % [OUT_DIR, _tag])
	print("[wardrobe report] looks: %s" % scene.status())
	# what the frame costs with every wardrobe whole in the texture and the pieces not worn skipped
	for f: int in 30:
		await process_frame
	var passes: Vector2 = Vector2.ZERO
	for f: int in MEASURE_FRAMES:
		await process_frame
		passes += scene.get_render_msec()
	passes /= MEASURE_FRAMES
	print("[wardrobe report] looks: passes %.3f ms GPU and %.3f ms CPU a frame, over %d frames" % [passes.y, passes.x, MEASURE_FRAMES])
	_check(scene.rebuild_count == 1, "eight looks were drawn with one build of the splats")
	_check(scene.shown_splat_count() < scene.splat_count * 3 / 4, "the pieces not worn are not shown (%d of %d splats)" % [scene.shown_splat_count(), scene.splat_count])
	if not _reference.is_empty():
		var reference: Image = Image.load_from_file(_reference.path_join("avatar-looks.png"))
		if reference == null:
			_check(false, "the reference render avatar-looks.png is in %s" % _reference)
		else:
			reference.convert(Image.FORMAT_RGBA8)
			var beside: Image = Image.create(maxi(reference.get_width(), ours.get_width()), reference.get_height() + ours.get_height(), false, Image.FORMAT_RGBA8)
			beside.blit_rect(reference, Rect2i(Vector2i.ZERO, reference.get_size()), Vector2i.ZERO)
			beside.blit_rect(ours, Rect2i(Vector2i.ZERO, ours.get_size()), Vector2i(0, reference.get_height()))
			beside.save_png("%s/looks-beside%s.png" % [OUT_DIR, _tag])

	# One avatar alone, changing through the same looks while it is drawn.
	for avatar: SplatInstance in row:
		avatar.visible = false
	var changer: SplatInstance = _stander(room, Vector2i(7, 7))
	var file_hair: int = clip.palette[clip.regions["hair"][1]]
	var whole: int = _count(await _picture(scene), file_hair)
	_check(whole >= 12, "before it is dressed an avatar is drawn whole, in the file's colours (%d pixels of its hair's %06x)" % [whole, file_hair])
	changer.wear(PackedStringArray(["body"]))
	var bare: int = _count(await _picture(scene), file_hair)
	_check(bare == 0, "wearing its body alone, it shows no hair (%d pixels)" % bare)
	var builds: int = scene.rebuild_count
	var updates: int = scene.look_update_count
	var last_top: int = -1
	var worst_msec: float = 0.0
	for i: int in LOOKS.size():
		var ramps: Dictionary = ramps_of(LOOKS[i])
		changer.wear(pieces_of(LOOKS[i]), ramps)
		var started: int = Time.get_ticks_usec()
		scene.draw(ROW_TIME)
		worst_msec = maxf(worst_msec, (Time.get_ticks_usec() - started) / 1000.0)
		var picture: Image = await _picture(scene)
		var top: int = ramps["top"][1]
		_check(_count(picture, top) >= 12, "look %d: its top's colour %06x is in the picture (%d pixels)" % [i, top, _count(picture, top)])
		if last_top >= 0 and last_top != top:
			_check(_count(picture, last_top) == 0, "look %d: the look before's top colour %06x is gone" % [i, last_top])
		last_top = top
	_check(scene.rebuild_count == builds, "eight changes of look rebuilt nothing")
	_check(scene.look_update_count == updates + LOOKS.size(), "each was written as a look (%d)" % (scene.look_update_count - updates))
	# what a rebuild of the same picture costs, to set a change of look beside
	SplatInstance.version += 1
	scene.draw(ROW_TIME)
	print("[wardrobe report] a change of look: at most %.2f ms on the CPU; a rebuild of these %d splats: %.1f ms" % [worst_msec, scene.splat_count, scene.last_rebuild_msec])
	_check(worst_msec < scene.last_rebuild_msec, "a change of look costs less than a rebuild")
	holder.queue_free()
	await process_frame


func _stander(room: Node3D, cell: Vector2i) -> SplatInstance:
	var item: Node3D = Node3D.new()
	item.position = Vector3((cell.x + 0.5) * CELL, 0.0, -(cell.y + 0.5) * CELL)
	item.rotation.y = deg_to_rad(ROW_YAW)
	room.add_child(item)
	var avatar: SplatInstance = SplatInstance.new()
	avatar.asset = SAMPLES + STANDING
	avatar.position = Vector3(0.0, 0.0, STAND_OFFSET_Z)
	avatar.rotation.y = PI
	avatar.scale = Vector3.ONE * AVATAR_SCALE
	item.add_child(avatar)
	return avatar
# endregion


# region The clips
func _clips() -> void:
	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	var camera: Camera3D = Camera3D.new()
	camera.fov = DESK_FOV
	camera.near = 0.1
	camera.far = 40.0
	holder.add_child(camera)
	var yaw: float = deg_to_rad(DESK_YAW)
	var pitch: float = deg_to_rad(DESK_PITCH)
	var forward: Vector3 = Vector3(sin(yaw) * cos(pitch), -sin(pitch), -cos(yaw) * cos(pitch))
	camera.look_at_from_position(DESK_LOOK_AT - forward * DESK_DISTANCE, DESK_LOOK_AT, Vector3.UP)

	var set_root: Node3D = Node3D.new()
	set_root.position = Vector3(0.0, 0.0, SEAT_OFFSET_Z)
	set_root.rotation.y = PI
	set_root.scale = Vector3.ONE * AVATAR_SCALE
	holder.add_child(set_root)
	var avatar: SplatInstance = SplatInstance.new()
	avatar.asset = SAMPLES + _seated
	set_root.add_child(avatar)
	var clip: SplatClip = avatar.get_clip()
	if clip == null:
		_check(false, "%s reads" % _seated)
		return
	# a file whose every splat is of a piece has no desk of its own: it sits at the sample one
	if not clip.piece_of.has(-1):
		var desk: SplatInstance = SplatInstance.new()
		desk.asset = SAMPLES + DESK
		set_root.add_child(desk)

	var scene: SplatScene = SplatScene.new()
	scene.camera = camera
	scene.instances_root = holder
	scene.art_size = DESK_ART
	scene.fixed_time = 0.0
	holder.add_child(scene)
	_show(scene)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("%s/clips%s" % [OUT_DIR, _tag]))

	# What a game keeps, and the library does not: which clip plays, since when, and how far a fade has got.
	var playing: String = ""
	var started: float = 0.0
	var leaving: String = ""
	var leaving_started: float = 0.0
	var builds: int = -1
	var faded_frames: int = 0
	var names: PackedStringArray = PackedStringArray()
	for f: int in FRAMES_A_CLIP * CLIPS.size():
		var now: float = f / FRAMES_PER_SECOND
		var wanted: Array = CLIPS[mini(CLIPS.size() - 1, f / FRAMES_A_CLIP)]
		if wanted[0] != playing:
			leaving = playing
			leaving_started = started
			playing = wanted[0]
			started = now
			names.append(playing)
			_check(clip.find(playing) != null, "%s has the clip %s" % [_seated, playing])
			# the first look's pieces and colours, and this clip's thing on the desk
			var pieces: PackedStringArray = pieces_of(LOOKS[0])
			pieces.append("device:" + wanted[1])
			avatar.wear(pieces, ramps_of(LOOKS[0]))
		var x: float = (now - started) / FADE_SECONDS
		if leaving.is_empty() or x >= 1.0:
			avatar.play(playing, now - started)
		else:
			avatar.cross_fade(leaving, now - leaving_started, playing, now - started, x * x * (3.0 - 2.0 * x))
			faded_frames += 1
		scene.fixed_time = now
		var picture: Image = _over(await _picture(scene), BACKDROP)
		picture.resize(DESK_ART.x * DESK_SCALE, DESK_ART.y * DESK_SCALE, Image.INTERPOLATE_NEAREST)
		picture.save_png("%s/clips%s/%03d.png" % [OUT_DIR, _tag, f])
		if builds < 0:
			builds = scene.rebuild_count
	print("[wardrobe report] clips: %s; %s" % [", ".join(names), scene.status()])
	_check(scene.rebuild_count == builds, "%d clips, %d faded frames and %d changes of look rebuilt nothing" % [names.size(), faded_frames, scene.look_update_count])
	_check(faded_frames >= 3 * (CLIPS.size() - 1), "every change of clip was faded over several frames (%d)" % faded_frames)
	holder.queue_free()
	await process_frame
# endregion


# region A look, as a game might keep it
## The pieces a look shows, by the sample file's names: the body, one top, the bottom, the shoes,
## the hairstyle (or, under a hat, what shows of the hair below it) and whatever else is worn.
static func pieces_of(look: Dictionary) -> PackedStringArray:
	var pieces: PackedStringArray = PackedStringArray(["body", "top:" + look["top"], "bottom:trousers", "shoes:shoes"])
	pieces.append("hair:" + look["hair"] if look["hair_shows"] else "under-hat")
	for worn: String in look["worn"]:
		pieces.append("accessory:" + worn)
	return pieces


## Each region's ramp, dark to light, from the colours a look picks over the basic ones. Skin and
## socks take a soft shadow. The hair's tie follows the hair: halfway to a soft pink, then a fifth
## of the way to white.
static func ramps_of(look: Dictionary) -> Dictionary:
	var ramps: Dictionary = {}
	for region: String in BASIC:
		var colour: int = look["colours"].get(region, BASIC[region])
		ramps[region] = ramp_of(colour, 0.86, 0.7) if region == "skin" or region == "socks" else ramp_of(colour)
	var hair: int = look["colours"].get("hair", BASIC["hair"])
	var tie: int = 0
	for shift: int in [16, 8, 0]:
		var channel: float = (((hair >> shift) & 255) / 255.0 + [0.95, 0.55, 0.65][2 - shift / 8]) / 2.0
		tie |= roundi((channel + (1.0 - channel) * 0.2) * 255.0) << shift
	ramps["pink"] = PackedInt32Array([ramp_of(tie)[0], tie])
	return ramps


## A picked colour as shadow, base and light: the shadow leans toward blue and the light toward a
## warm yellow, as the sample art's own ramps do.
static func ramp_of(colour: int, dark: float = 0.66, saturation: float = 1.05) -> PackedInt32Array:
	var r: float = ((colour >> 16) & 255) / 255.0
	var g: float = ((colour >> 8) & 255) / 255.0
	var b: float = (colour & 255) / 255.0
	var high: float = maxf(r, maxf(g, b))
	var low: float = minf(r, minf(g, b))
	var spread: float = high - low
	var l: float = (high + low) / 2.0
	var h: float = 0.0
	var s: float = 0.0
	if spread >= 1e-6:
		s = spread / (1.0 - absf(2.0 * l - 1.0))
		if high == r:
			h = fposmod((g - b) / spread + 6.0, 6.0)
		elif high == g:
			h = (b - r) / spread + 2.0
		else:
			h = (r - g) / spread + 4.0
		h *= 60.0
	return PackedInt32Array([_rgb(_toward(h, 240.0, 0.08), s * saturation, l * dark), colour, _rgb(_toward(h, 50.0, 0.1), s, l + (1.0 - l) * 0.22)])


# a hue moved a fraction of the way to another, the short way round
static func _toward(from: float, to: float, k: float) -> float:
	return from + (fposmod(fposmod(to - from, 360.0) + 540.0, 360.0) - 180.0) * k


static func _rgb(h: float, s: float, l: float) -> int:
	h = fposmod(h, 360.0)
	s = clampf(s, 0.0, 1.0)
	l = clampf(l, 0.0, 1.0)
	var c: float = (1.0 - absf(2.0 * l - 1.0)) * s
	var x: float = c * (1.0 - absf(fposmod(h / 60.0, 2.0) - 1.0))
	var m: float = l - c / 2.0
	var rgb: Vector3 = Vector3(c, x, 0.0)
	if h >= 300.0:
		rgb = Vector3(c, 0.0, x)
	elif h >= 240.0:
		rgb = Vector3(x, 0.0, c)
	elif h >= 180.0:
		rgb = Vector3(0.0, x, c)
	elif h >= 120.0:
		rgb = Vector3(0.0, c, x)
	elif h >= 60.0:
		rgb = Vector3(x, c, 0.0)
	return (floori((rgb.x + m) * 255.0 + 0.5) << 16) | (floori((rgb.y + m) * 255.0 + 0.5) << 8) | floori((rgb.z + m) * 255.0 + 0.5)


# The ramps of six colours as the sample art's own tool gives them: a wrong ramp is a wrong picture.
func _check_ramps() -> void:
	var cases: Array[Array] = [
		[0xd8783e, false, 0x9c341c, 0xe19b68], [0x7a3220, false, 0x521514, 0xb85430], [0x3f6f8a, false, 0x28475c, 0x5aaab3],
		[0x808080, false, 0x545454, 0x9c9c9c], [0xf0c6a6, true, 0xd79a87, 0xf3d5ba], [0x5e3a28, true, 0x4a2e29, 0x986241],
	]
	var right: bool = true
	for case: Array in cases:
		var ramp: PackedInt32Array = ramp_of(case[0], 0.86, 0.7) if case[1] else ramp_of(case[0])
		if ramp != PackedInt32Array([case[2], case[0], case[3]]):
			right = false
			print("  %06x gives %06x %06x %06x, not %06x and %06x" % [case[0], ramp[0], ramp[1], ramp[2], case[2], case[3]])
	_check(right, "a picked colour's ramp is the sample art's, number for number")
# endregion


# region Pictures
func _show(scene: SplatScene) -> void:
	var show: TextureRect = TextureRect.new()
	show.texture = scene.get_picture()
	show.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	show.set_anchors_preset(Control.PRESET_FULL_RECT)
	show.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	scene.add_child(show)


func _picture(scene: SplatScene) -> Image:
	for f: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = scene.get_picture().get_image()
	picture.convert(Image.FORMAT_RGBA8)
	return picture


# The picture over a colour: its alpha is 0 or 1.
static func _over(picture: Image, colour: Color) -> Image:
	var flat: Image = Image.create(picture.get_width(), picture.get_height(), false, Image.FORMAT_RGBA8)
	flat.fill(colour)
	flat.blend_rect(picture, Rect2i(Vector2i.ZERO, picture.get_size()), Vector2i.ZERO)
	return flat


# How many covered pixels are exactly a colour (0xRRGGBB).
static func _count(picture: Image, colour: int) -> int:
	var data: PackedByteArray = picture.get_data()
	var count: int = 0
	for i: int in range(0, data.size(), 4):
		if data[i + 3] > 127 and data[i] == (colour >> 16) & 255 and data[i + 1] == (colour >> 8) & 255 and data[i + 2] == colour & 255:
			count += 1
	return count
# endregion
