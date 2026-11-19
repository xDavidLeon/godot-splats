## Draws every [SplatInstance] under [member instances_root] into one pixel-art picture for one
## [Camera3D], orthographic or perspective. A port of a Unity renderer of the same design.
##
## The splats of every instance sit end to end in one float texture. Posing (bones), placing (each
## instance's transform), projecting and ordering (a depth buffer) all happen on the GPU
## ([code]splat_scene_draw.gdshader[/code]), so a frame costs the CPU a few small uploads: instance
## matrices, and the bones of clips whose frame changed. The big texture is rebuilt only when the
## scene's contents change: an instance appears or goes, or a prop turns (its colours are baked per
## quarter turn). Then [code]splat_resolve.gdshader[/code] makes the pixel look at the art resolution.
## Show [method get_picture] with nearest-neighbour filtering ([code]splat_present.gdshader[/code]).
##
## An instance that wears a look ([method SplatInstance.wear]) has every splat of its wardrobe in the
## big texture; a small texture says, for each instance, which pieces show and what its palette is,
## and the shader asks it. So a change of look writes that instance's row and its ramps and rebuilds
## nothing. A change of clip, and a fade from one to another ([method SplatInstance.cross_fade]), are
## that instance's bones for the frame, mixed on the CPU.
##
## Light, all of it off until asked for, so a scene that sets none of this draws its assets' bakes:
## [br]- [b]Lamps:[/b] every [SplatLamp] under [member instances_root] lifts the splats near it and
## facing it along the ramp each was shaded on.
## [br]- [b]Dusk:[/b] [member dusk] takes every splat down its ramp by whole steps.
## [br]- [b]Floor shadows:[/b] with [member floor_shadows], instances darken the floor under them,
## away from [member sun].
## [br]The rules are [SplatLight]'s. They run in the shaders every frame, so a lamp or a piece of
## furniture that moves, the dusk falling and a clip playing cost the CPU nothing and rebuild nothing.
## Only files with light data are lit again ([method SplatClip.has_light]); the others keep their colours.
##
## [b]Particles.[/b] An instance with a [member SplatInstance.motion] is a cloud whose splats each move
## by themselves, by a formula of the clock ([SplatParticles]), in the vertex shader. Nothing is
## simulated, uploaded or rebuilt for them, and a frame at a given time is always the same frame.
##
## [b]Marks.[/b] [method set_marks] draws lines into the picture on top of what lies under them, in
## colours of their own that the pixel look leaves alone: an editor's grid, an outline round a thing.
##
## Not ported from Unity: the tinted ghost.
# In Unity, the draw is a CommandBuffer with DrawProcedural and StructuredBuffers, and lamps, dusk
# and shadows were worked out on the CPU at each rebuild. Here SubViewports do it: a 3D one (it has a
# depth buffer) holding one MultiMesh of quads, a 2D one for the resolve, and, only while floor
# shadows are on, a small 3D one for the floor's grid. None needs compute shaders, so the
# Compatibility renderer can run it. Unity's instance made a new clip holding only the shown splats for
# every look, and the scene rebuilt its buffers; here the pieces not worn are skipped by the shader.
# Unity drew a mark's quad straight into the samples with an alpha of a half. Here that alpha is the
# floor shadows', and a spatial shader cannot replace a colour and its alpha in one draw, so the marks
# are drawn twice: once into the samples to clear what they cover, once into a target of their own
# for their colours (splat_marks.gdshaderinc).
class_name SplatScene
extends Node


# region Constants
const DRAW_SHADER: Shader = preload("res://addons/splats/shaders/splat_scene_draw.gdshader")
const RESOLVE_SHADER: Shader = preload("res://addons/splats/shaders/splat_resolve.gdshader")
const SHADOW_CAST_SHADER: Shader = preload("res://addons/splats/shaders/splat_shadow_cast.gdshader")
const SHADOW_SHADER: Shader = preload("res://addons/splats/shaders/splat_shadow.gdshader")
const MARK_CUT_SHADER: Shader = preload("res://addons/splats/shaders/splat_mark_cut.gdshader")
const MARK_COLOUR_SHADER: Shader = preload("res://addons/splats/shaders/splat_mark_colour.gdshader")

## Colours the pixel look can tell apart in one picture.
const MAX_PALETTE: int = 128
## Lamps that light one picture. More are left out, with a warning.
const MAX_LAMPS: int = 16
## Instances in one picture. A splat carries its instance and its wardrobe piece in one float.
const MAX_INSTANCES: int = 4096
## Floor shadows fall within this many cells of where the camera looks, each way: 12.8 m with the
## default [member shadow_cell].
const SHADOW_REACH_CELLS: int = 256
## Lines one picture draws. More are left out, with a warning.
const MAX_MARKS: int = 4096
## The particles' clock starts again after this many seconds, so a float keeps its precision.
const CLOCK_WRAP: float = 3600.0

const _SPLATS_WIDTH: int = 1024       # texels in a row: 256 splats
const _BONES_WIDTH: int = 768         # texels in a row: 256 bones
const _LIGHTS_WIDTH: int = 1024       # texels in a row: 1024 splats' normals and ramps, or 4096 splats' brightness
const _INSTANCE_FLOATS: int = 20
const _MARK_FLOATS: int = 16
const _MARK_DEPTH_BIAS: float = 0.1   # metres nearer the camera the marks are depth-tested
const _SHADOW_HEIGHT: float = 0.004   # metres above the floor the shadow discs lie
const _SHADOW_DEPTH_BIAS: float = 0.1 # metres nearer the camera they are depth-tested
const _SHADOW_DISC: float = 0.75      # a disc's radius, in cells: neighbours overlap
# endregion


# region State
## How an art pixel inside a shape gets its colour from the four samples under it.
enum Interior {
	## The palette colour nearest the samples' average, with an ordered dither.
	AVERAGE,
	## The palette colour most samples vote for: every pixel is a colour a splat has.
	VOTE,
}

## The camera the picture is taken from. Only its transform, projection, size or fov, near and far
## are used; the picture's shape is [member art_size], not the camera's viewport.
@export var camera: Camera3D

## The instances under this node are drawn. Empty: this node's parent.
@export var instances_root: Node

## The picture's size in art pixels. 640 x 360 is three screen pixels each at 1080p.
@export var art_size: Vector2i = Vector2i(640, 360)

## How the inside of a shape is coloured. [constant Interior.AVERAGE] is the Unity renderer's look
## and the default; [constant Interior.VOTE] is flatter and has no stray pixels.
@export var interior: Interior = Interior.AVERAGE

## With [constant Interior.AVERAGE] only: how much ordered noise is added to the average.
@export_range(0.0, 0.3) var dither: float = 0.021

@export_group("Light")
## Whether the [SplatLamp]s under [member instances_root] light the picture.
@export var lamp_light: bool = true

## How far the day has dimmed, in steps of each splat's own colour ramp: 0 is the bake, and 2 reads
## as evening. Splats with no ramp (glowing things) keep their colour.
@export_range(0, 8) var dusk: int = 0

## Whether instances darken the floor under them ([member SplatInstance.casts_shadow]).
@export var floor_shadows: bool = false

## The world's one sun, pointing at it (it need not be a unit vector, and must rise). Keep it equal
## to the sun the assets were baked with: the game's manifest's, or the exporter's default, which
## this is.
@export var sun: Vector3 = Vector3(-0.3, 0.75, 0.6)

## The height of the floor that shadows fall on, in metres.
@export var floor_height: float = 0.0

## The floor shadows' cell, in metres: a shadow is a disc on every cell something stands over.
@export_range(0.02, 0.2, 0.005) var shadow_cell: float = 0.05

## How much light a floor shadow leaves.
@export_range(0.4, 1.0, 0.01) var shadow_light: float = 0.8

@export_group("")
## How wide the lines of [method set_marks] are, in art pixels (with a perspective camera, at one
## metre from it).
@export_range(0.5, 8.0, 0.1) var mark_width: float = 1.6

## The clips' and the particles' clock in seconds. Negative: the engine's own time.
@export var fixed_time: float = -1.0

## Have the engine time both passes, for [method get_render_msec]. Off by default: timing has a cost.
@export var measure_render_time: bool = false:
	set(value):
		measure_render_time = value
		_apply_measuring()

## Splats in the picture at the last rebuild.
var splat_count: int = 0
## Instances drawn at the last rebuild.
var instance_count: int = 0
## Colours in the picture's palette at the last rebuild.
var palette_count: int = 0
## Lamps lighting the picture this frame.
var lamp_count: int = 0
## How many times the big texture has been rebuilt.
var rebuild_count: int = 0
## How many times an instance's look has been written again without a rebuild.
var look_update_count: int = 0
## Lines drawn over the picture ([method set_marks]).
var mark_count: int = 0
## How many times the lines have been handed to the GPU: only when they differ.
var mark_upload_count: int = 0
## What the last frame cost this script, in milliseconds (uploads included, the GPU's work not).
var last_cpu_msec: float = 0.0
## What the last rebuild cost, in milliseconds.
var last_rebuild_msec: float = 0.0

var _instances: Array[SplatInstance] = []
var _first_bone: PackedInt32Array = PackedInt32Array()
var _last_stamp: PackedInt64Array = PackedInt64Array()
var _worn: PackedInt32Array = PackedInt32Array()
var _turns: PackedInt32Array = PackedInt32Array()
var _first_ramp: PackedInt32Array = PackedInt32Array()
var _built_version: int = -1
var _built_art_size: Vector2i = Vector2i.ZERO

var _samples_viewport: SubViewport
var _picture_viewport: SubViewport
var _multimesh: MultiMesh
var _draw_material: ShaderMaterial
var _resolve_material: ShaderMaterial
var _resolve_rect: ColorRect
var _instance_data: PackedFloat32Array = PackedFloat32Array()
var _instance_texture: ImageTexture
var _bone_data: PackedFloat32Array = PackedFloat32Array()
var _bone_texture: ImageTexture
var _bone_rows: int = 1
var _look_data: PackedFloat32Array = PackedFloat32Array()
var _look_texture: ImageTexture
var _look_width: int = 1
var _ramp_data: PackedFloat32Array = PackedFloat32Array()
var _ramp_texture: ImageTexture
var _ramp_width: int = 1
var _ramp_rows: int = 1
var _lamps: Array[SplatLamp] = []
var _built_lamp_version: int = -1
var _lamp_root: Node = null
var _lamp_data: PackedVector4Array = PackedVector4Array()
var _lamp_strengths: PackedFloat32Array = PackedFloat32Array()
var _shadow_viewport: SubViewport
var _shadow_cast_material: ShaderMaterial
var _shadow_material: ShaderMaterial
var _shadow_plane: MeshInstance3D
var _warned_sun: bool = false
var _mark_data: PackedFloat32Array = PackedFloat32Array()
var _mark_rows: int = 0
var _marks_changed: bool = false
var _mark_texture: ImageTexture
var _mark_multimesh: MultiMesh
var _marks_viewport: SubViewport
var _mark_cut_material: ShaderMaterial
var _mark_colour_material: ShaderMaterial
var _mark_cut: MultiMeshInstance3D
# endregion


# region Lifecycle
func _ready() -> void:
	_build_passes()


func _process(_delta: float) -> void:
	draw(fixed_time if fixed_time >= 0.0 else Time.get_ticks_usec() / 1000000.0)
# endregion


# region Public API
## The resolved picture, [member art_size] pixels: sRGB palette colours, alpha 0 or 1.
func get_picture() -> ViewportTexture:
	return _picture_viewport.get_texture()


## The picture before the pixel look: twice the art resolution, coverage in alpha (a half where a
## floor shadow falls on something, and none where a mark lies over it). For debugging.
func get_samples() -> ViewportTexture:
	return _samples_viewport.get_texture()


## The floor's grid from above, one texel a cell, marked where a shadow falls; [code]null[/code]
## until floor shadows have been drawn. Its first texel is the cell [method get_shadow_first_cell]
## gives, and a row is a step along z. For debugging.
func get_shadow_cells() -> ViewportTexture:
	return _shadow_viewport.get_texture() if _shadow_viewport != null else null


## The floor cell (x, z) at the first texel of [method get_shadow_cells] this frame. Cell (x, z) spans
## x × [member shadow_cell] to (x + 1) × [member shadow_cell] metres.
func get_shadow_first_cell() -> Vector2i:
	var eye: Transform3D = camera.global_transform
	var forward: Vector3 = -eye.basis.z
	var focus: Vector3 = eye.origin
	if absf(forward.y) > 1e-4:
		var t: float = (floor_height - eye.origin.y) / forward.y
		if t > 0.0:
			focus += forward * t
	return Vector2i(floori(focus.x / shadow_cell), floori(focus.z / shadow_cell)) - Vector2i.ONE * SHADOW_REACH_CELLS


## The lines to draw from now on, on top of what lies under them; none with an empty array. They are
## outside the palette and the pixel look leaves them alone, so showing them never changes a colour
## of anything else, and every pixel of the picture stays covered or clear. A thing standing in
## front of a line hides it. Where lines cross, the one given last shows.
## [br]Cheap to call every frame: the lines are handed to the GPU only when they differ, and they
## never rebuild the scene.
func set_marks(marks: Array[SplatMark]) -> void:
	var count: int = marks.size()
	if count > MAX_MARKS:
		push_warning("[SplatScene] %d marks; one picture draws %d." % [count, MAX_MARKS])
		count = MAX_MARKS
	if count != mark_count:
		_marks_changed = true
	mark_count = count
	if _mark_data.size() < count * _MARK_FLOATS:
		_mark_data.resize(count * _MARK_FLOATS)
		_marks_changed = true
	for i: int in count:
		var line: SplatMark = marks[i]
		var o: int = i * _MARK_FLOATS
		_put_mark(o, line.from.x)
		_put_mark(o + 1, line.from.y)
		_put_mark(o + 2, line.from.z)
		_put_mark(o + 4, line.to.x)
		_put_mark(o + 5, line.to.y)
		_put_mark(o + 6, line.to.z)
		_put_mark(o + 8, line.normal.x)
		_put_mark(o + 9, line.normal.y)
		_put_mark(o + 10, line.normal.z)
		_put_mark(o + 12, line.colour.r8 / 255.0)
		_put_mark(o + 13, line.colour.g8 / 255.0)
		_put_mark(o + 14, line.colour.b8 / 255.0)
		_put_mark(o + 15, 1.0 if line.is_dotted() else 0.0)


## Uploads what the picture needs for the clock at [param seconds]. [method _process] calls it; the
## viewports then draw with the rest of the frame.
func draw(seconds: float) -> void:
	if camera == null:
		return
	var stale: bool = _built_version != SplatInstance.version or _built_art_size != art_size
	var n: int = 0
	while not stale and n < _instances.size():
		var instance: SplatInstance = _instances[n]
		stale = not is_instance_valid(instance) or _turn_of(instance) != _turns[n]
		n += 1
	if stale:
		_rebuild()

	var started: int = Time.get_ticks_usec()
	var looks_changed: bool = false
	var bones_changed: bool = false
	for i: int in _instances.size():
		var instance: SplatInstance = _instances[i]
		if _worn[i] != instance.look_version:
			_worn[i] = instance.look_version
			_write_look(i)
			looks_changed = true
		var to_world: Transform3D = instance.global_transform
		var o: int = i * _INSTANCE_FLOATS
		# the 3x4 by rows: Godot's basis holds columns
		_instance_data[o] = to_world.basis.x.x
		_instance_data[o + 1] = to_world.basis.y.x
		_instance_data[o + 2] = to_world.basis.z.x
		_instance_data[o + 3] = to_world.origin.x
		_instance_data[o + 4] = to_world.basis.x.y
		_instance_data[o + 5] = to_world.basis.y.y
		_instance_data[o + 6] = to_world.basis.z.y
		_instance_data[o + 7] = to_world.origin.y
		_instance_data[o + 8] = to_world.basis.x.z
		_instance_data[o + 9] = to_world.basis.y.z
		_instance_data[o + 10] = to_world.basis.z.z
		_instance_data[o + 11] = to_world.origin.z
		_instance_data[o + 12] = _first_bone[i]
		_instance_data[o + 13] = _first_ramp[i]
		_instance_data[o + 14] = instance.depth_bias
		_instance_data[o + 15] = 1.0 if instance.casts_shadow else 0.0
		_instance_data[o + 16] = instance.motion
		_instance_data[o + 17] = instance.motion_reach
		_instance_data[o + 18] = instance.motion_wobble
		_instance_data[o + 19] = instance.motion_speed
		var clip: SplatClip = instance.get_clip()
		if clip.bone_count == 0:
			continue
		var stamp: int = instance.write_bones(seconds, _bone_data, _first_bone[i] * SplatClip.BONE_STRIDE, _last_stamp[i])
		if stamp == _last_stamp[i] and stamp >= 0:
			continue
		_last_stamp[i] = stamp
		bones_changed = true
	if looks_changed:
		look_update_count += 1
		_upload_looks()
	if not _instances.is_empty():
		_instance_texture.update(Image.create_from_data(_INSTANCE_FLOATS / 4, _instances.size(), false, Image.FORMAT_RGBAF, _instance_data.to_byte_array()))
	if bones_changed:
		_bone_texture.update(Image.create_from_data(_BONES_WIDTH, _bone_rows, false, Image.FORMAT_RGBAF, _bone_data.to_byte_array()))

	var samples_height: float = art_size.y * 2.0
	var orthographic: bool = camera.projection == Camera3D.PROJECTION_ORTHOGONAL
	var lens: float = samples_height * 0.5 / (camera.size * 0.5) if orthographic \
			else samples_height * 0.5 / tan(deg_to_rad(camera.fov) * 0.5)
	var lens_vector: Vector4 = Vector4(lens, 1.0 if orthographic else 0.0, camera.near, camera.far)
	_draw_material.set_shader_parameter(&"view", camera.global_transform.affine_inverse())
	_draw_material.set_shader_parameter(&"size", Vector2(art_size * 2))
	_draw_material.set_shader_parameter(&"lens", lens_vector)
	_draw_material.set_shader_parameter(&"clock", fmod(seconds, CLOCK_WRAP))
	_light(lens_vector)
	_mark(lens_vector)
	_resolve_material.set_shader_parameter(&"average_interior", interior == Interior.AVERAGE)
	_resolve_material.set_shader_parameter(&"dither", dither)
	last_cpu_msec = (Time.get_ticks_usec() - started) / 1000.0


## What the passes (the floor's shadow cells when they are on, draw, the marks' and resolve) cost last frame, in
## milliseconds: x on the CPU, y on the GPU. Zero unless [member measure_render_time] is on.
func get_render_msec() -> Vector2:
	if not measure_render_time or _samples_viewport == null:
		return Vector2.ZERO
	var total: Vector2 = Vector2.ZERO
	for viewport: SubViewport in [_shadow_viewport, _samples_viewport, _marks_viewport, _picture_viewport]:
		if viewport == null or viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED:
			continue
		total.x += RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid())
		total.y += RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
	return total


## How many splats the picture's instances show: [member splat_count] less the wardrobe pieces not worn.
func shown_splat_count() -> int:
	var shown: int = 0
	for instance: SplatInstance in _instances:
		if is_instance_valid(instance):
			shown += instance.shown_splat_count()
	return shown


## One line on what the picture holds and costs.
func status() -> String:
	return "%d splats (%d shown) in %d instances, %d colours, %d lamps, dusk %d, floor shadows %s, %d marks, art %dx%d; CPU %.3f ms a frame, last rebuild %.1f ms" % [
		splat_count, shown_splat_count(), instance_count, palette_count, lamp_count, dusk, "on" if _shadows_wanted() else "off", mark_count,
		art_size.x, art_size.y, last_cpu_msec, last_rebuild_msec]
# endregion


# region Light
# This frame's lamps, dusk and floor shadows: a few uniforms, and nothing when none is asked for.
func _light(lens_vector: Vector4) -> void:
	var root: Node = instances_root if instances_root != null else get_parent()
	if _built_lamp_version != SplatLamp.version or _lamp_root != root:
		_built_lamp_version = SplatLamp.version
		_lamp_root = root
		_lamps.clear()
		_gather_lamps(root)
		if _lamps.size() > MAX_LAMPS:
			push_warning("[SplatScene] %d lamps; the picture is lit by the first %d." % [_lamps.size(), MAX_LAMPS])
			_lamps.resize(MAX_LAMPS)
	lamp_count = _lamps.size() if lamp_light else 0
	for l: int in lamp_count:
		var lamp: SplatLamp = _lamps[l]
		var at: Vector3 = lamp.global_position
		_lamp_data[l] = Vector4(at.x, at.y, at.z, maxf(lamp.radius, 0.001))
		_lamp_strengths[l] = lamp.strength
	_draw_material.set_shader_parameter(&"lamps", _lamp_data)
	_draw_material.set_shader_parameter(&"lamp_strengths", _lamp_strengths)
	_draw_material.set_shader_parameter(&"lamp_count", lamp_count)
	_draw_material.set_shader_parameter(&"dusk", maxi(0, dusk))

	var shadows: bool = _shadows_wanted()
	if floor_shadows and sun.y <= 0.0 and not _warned_sun:
		_warned_sun = true
		push_warning("[SplatScene] The sun is not above the horizon; no floor shadows are drawn.")
	if shadows and _shadow_viewport == null:
		_build_shadow_pass()
	if _shadow_viewport == null:
		return
	_shadow_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shadows else SubViewport.UPDATE_DISABLED
	_shadow_plane.visible = shadows
	if not shadows:
		return
	var first_cell: Vector2 = Vector2(get_shadow_first_cell())
	var across: float = SHADOW_REACH_CELLS * 2.0
	_shadow_cast_material.set_shader_parameter(&"splats", _draw_material.get_shader_parameter(&"splats"))
	_shadow_cast_material.set_shader_parameter(&"instances", _instance_texture)
	_shadow_cast_material.set_shader_parameter(&"bones", _bone_texture)
	_shadow_cast_material.set_shader_parameter(&"looks", _look_texture)
	_shadow_cast_material.set_shader_parameter(&"slope", Vector2(sun.x, sun.z) / sun.y)
	_shadow_cast_material.set_shader_parameter(&"grid", Vector4(shadow_cell, floor_height, SplatLight.SHADOW_MIN_HEIGHT, across))
	_shadow_cast_material.set_shader_parameter(&"first_cell", first_cell)
	_shadow_cast_material.set_shader_parameter(&"clock", _draw_material.get_shader_parameter(&"clock"))
	_shadow_material.set_shader_parameter(&"eye", camera.global_transform)
	_shadow_material.set_shader_parameter(&"size", Vector2(art_size * 2))
	_shadow_material.set_shader_parameter(&"lens", lens_vector)
	_shadow_material.set_shader_parameter(&"grid", Vector4(shadow_cell, floor_height + _SHADOW_HEIGHT, _SHADOW_DISC, across))
	_shadow_material.set_shader_parameter(&"first_cell", first_cell)
	_shadow_material.set_shader_parameter(&"depth_bias", _SHADOW_DEPTH_BIAS)
	_resolve_material.set_shader_parameter(&"shadow_light", shadow_light)


func _shadows_wanted() -> bool:
	return floor_shadows and sun.y > 0.0 and shadow_cell > 0.0 and splat_count > 0


func _gather_lamps(node: Node) -> void:
	if node == null:
		return
	if node is SplatLamp and (node as SplatLamp).is_visible_in_tree():
		_lamps.append(node)
	for child: Node in node.get_children():
		_gather_lamps(child)


# The floor's grid from above, one texel a cell, drawn by the same quads as the picture with another
# shader; and one quad over the samples that reads it. Built the first time floor shadows are wanted.
func _build_shadow_pass() -> void:
	_shadow_viewport = SubViewport.new()
	_shadow_viewport.name = "ShadowCells"
	_shadow_viewport.own_world_3d = true
	_shadow_viewport.transparent_bg = true
	_shadow_viewport.size = Vector2i.ONE * SHADOW_REACH_CELLS * 2
	_shadow_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_shadow_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_shadow_viewport.use_taa = false
	_shadow_viewport.use_debanding = false
	_shadow_viewport.positional_shadow_atlas_size = 0
	add_child(_shadow_viewport)
	move_child(_shadow_viewport, 0) # before the samples, which read it

	var eye: Camera3D = Camera3D.new()
	eye.environment = Environment.new()
	_shadow_viewport.add_child(eye)
	eye.make_current()

	_shadow_cast_material = ShaderMaterial.new()
	_shadow_cast_material.shader = SHADOW_CAST_SHADER
	_shadow_cast_material.set_shader_parameter(&"splats_width", _SPLATS_WIDTH)
	_shadow_cast_material.set_shader_parameter(&"bones_width", _BONES_WIDTH)
	var everywhere: AABB = AABB(Vector3.ONE * -100000.0, Vector3.ONE * 200000.0)
	var casters: MultiMeshInstance3D = MultiMeshInstance3D.new()
	casters.multimesh = _multimesh
	casters.material_override = _shadow_cast_material
	casters.custom_aabb = everywhere
	casters.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	casters.ignore_occlusion_culling = true
	_shadow_viewport.add_child(casters)

	var quad: ArrayMesh = _quad_mesh()
	_shadow_material = ShaderMaterial.new()
	_shadow_material.shader = SHADOW_SHADER
	_shadow_material.set_shader_parameter(&"cells", _shadow_viewport.get_texture())
	quad.surface_set_material(0, _shadow_material)
	_shadow_plane = MeshInstance3D.new()
	_shadow_plane.mesh = quad
	_shadow_plane.custom_aabb = everywhere
	_shadow_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow_plane.ignore_occlusion_culling = true
	_samples_viewport.add_child(_shadow_plane)
	RenderingServer.viewport_set_measure_render_time(_shadow_viewport.get_viewport_rid(), measure_render_time)
# endregion


# region Marks
func _put_mark(at: int, value: float) -> void:
	var before: float = _mark_data[at]
	_mark_data[at] = value # kept in single precision: compared as it is kept
	if _mark_data[at] != before:
		_marks_changed = true


# This frame's lines: their texture when they differ, and a few uniforms. Nothing when there are none.
func _mark(lens_vector: Vector4) -> void:
	_resolve_material.set_shader_parameter(&"mark_samples", mark_count > 0)
	if mark_count > 0 and _marks_viewport == null:
		_build_mark_pass()
	if _marks_viewport == null:
		return
	_marks_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if mark_count > 0 else SubViewport.UPDATE_DISABLED
	_mark_cut.visible = mark_count > 0
	if mark_count == 0:
		return
	if _marks_changed:
		_marks_changed = false
		mark_upload_count += 1
		# a row a line; the texture and the quads grow by doubling, and never shrink
		if _mark_rows < mark_count:
			_mark_rows = maxi(16, _mark_rows)
			while _mark_rows < mark_count:
				_mark_rows *= 2
			_mark_texture = null
			_mark_multimesh.instance_count = _mark_rows
			var transforms: PackedFloat32Array = PackedFloat32Array()
			transforms.resize(_mark_rows * 12)
			_mark_multimesh.buffer = transforms # never read: the quads take only their number
		var data: PackedFloat32Array = _mark_data.slice(0, mark_count * _MARK_FLOATS)
		data.resize(_mark_rows * _MARK_FLOATS)
		var image: Image = Image.create_from_data(_MARK_FLOATS / 4, _mark_rows, false, Image.FORMAT_RGBAF, data.to_byte_array())
		if _mark_texture == null:
			_mark_texture = ImageTexture.create_from_image(image)
		else:
			_mark_texture.update(image)
		_mark_multimesh.visible_instance_count = mark_count
	for material: ShaderMaterial in [_mark_cut_material, _mark_colour_material]:
		material.set_shader_parameter(&"lines", _mark_texture)
		material.set_shader_parameter(&"view", camera.global_transform.affine_inverse())
		material.set_shader_parameter(&"size", Vector2(art_size * 2))
		material.set_shader_parameter(&"lens", lens_vector)
		# an art pixel is two samples, and the lens is samples to the metre: half a width, in metres
		material.set_shader_parameter(&"mark", Vector2(mark_width / lens_vector.x, _MARK_DEPTH_BIAS))


# The lines' quads, drawn twice: over the samples, to clear what a line covers, and into a target of
# the samples' size for their colours. Built the first time there is a line to draw.
func _build_mark_pass() -> void:
	_mark_multimesh = MultiMesh.new()
	_mark_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_mark_multimesh.mesh = _quad_mesh()
	var everywhere: AABB = AABB(Vector3.ONE * -100000.0, Vector3.ONE * 200000.0)
	_mark_multimesh.custom_aabb = everywhere

	_mark_cut_material = ShaderMaterial.new()
	_mark_cut_material.shader = MARK_CUT_SHADER
	_mark_cut = MultiMeshInstance3D.new()
	_mark_cut.multimesh = _mark_multimesh
	_mark_cut.material_override = _mark_cut_material
	_mark_cut.custom_aabb = everywhere
	_mark_cut.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mark_cut.ignore_occlusion_culling = true
	_samples_viewport.add_child(_mark_cut)

	_marks_viewport = SubViewport.new()
	_marks_viewport.name = "Marks"
	_marks_viewport.own_world_3d = true
	_marks_viewport.transparent_bg = true
	_marks_viewport.size = art_size * 2
	_marks_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_marks_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_marks_viewport.use_taa = false
	_marks_viewport.use_debanding = false
	_marks_viewport.positional_shadow_atlas_size = 0
	add_child(_marks_viewport)
	move_child(_marks_viewport, _picture_viewport.get_index()) # before the picture, which reads it

	var eye: Camera3D = Camera3D.new()
	eye.environment = Environment.new()
	_marks_viewport.add_child(eye)
	eye.make_current()

	_mark_colour_material = ShaderMaterial.new()
	_mark_colour_material.shader = MARK_COLOUR_SHADER
	var colours: MultiMeshInstance3D = MultiMeshInstance3D.new()
	colours.multimesh = _mark_multimesh
	colours.material_override = _mark_colour_material
	colours.custom_aabb = everywhere
	colours.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	colours.ignore_occlusion_culling = true
	_marks_viewport.add_child(colours)
	_resolve_material.set_shader_parameter(&"marks", _marks_viewport.get_texture())
	RenderingServer.viewport_set_measure_render_time(_marks_viewport.get_viewport_rid(), measure_render_time)


# A quad with its corners at -1 and 1.
static func _quad_mesh() -> ArrayMesh:
	var quad: ArrayMesh = ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return quad
# endregion


# region Building
func _build_passes() -> void:
	# Pass 1: one quad a splat, with depth, at twice the art resolution.
	_samples_viewport = SubViewport.new()
	_samples_viewport.name = "Samples"
	_samples_viewport.own_world_3d = true
	_samples_viewport.transparent_bg = true
	_samples_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_samples_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_samples_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_samples_viewport.use_taa = false
	_samples_viewport.use_debanding = false
	_samples_viewport.positional_shadow_atlas_size = 0
	add_child(_samples_viewport)

	# A 3D viewport draws nothing without a camera. The shader places every vertex itself, so this one
	# only has to keep the quads from being culled; its environment keeps the project's default
	# environment (tonemapping, glow) out of the picture.
	var eye: Camera3D = Camera3D.new()
	eye.environment = Environment.new()
	_samples_viewport.add_child(eye)
	eye.make_current()

	var quad: ArrayMesh = _quad_mesh()
	_draw_material = ShaderMaterial.new()
	_draw_material.shader = DRAW_SHADER
	_draw_material.set_shader_parameter(&"splats_width", _SPLATS_WIDTH)
	_draw_material.set_shader_parameter(&"bones_width", _BONES_WIDTH)
	_draw_material.set_shader_parameter(&"lights_width", _LIGHTS_WIDTH)
	quad.surface_set_material(0, _draw_material)
	_lamp_data.resize(MAX_LAMPS)
	_lamp_strengths.resize(MAX_LAMPS)

	var everywhere: AABB = AABB(Vector3.ONE * -100000.0, Vector3.ONE * 200000.0)
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = quad
	_multimesh.custom_aabb = everywhere
	var quads: MultiMeshInstance3D = MultiMeshInstance3D.new()
	quads.multimesh = _multimesh
	quads.custom_aabb = everywhere
	quads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quads.ignore_occlusion_culling = true
	_samples_viewport.add_child(quads)

	# Pass 2: the pixel look, at the art resolution.
	_picture_viewport = SubViewport.new()
	_picture_viewport.name = "Picture"
	_picture_viewport.disable_3d = true
	_picture_viewport.transparent_bg = true
	_picture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_picture_viewport)

	_resolve_material = ShaderMaterial.new()
	_resolve_material.shader = RESOLVE_SHADER
	_resolve_material.set_shader_parameter(&"samples", _samples_viewport.get_texture())
	_resolve_rect = ColorRect.new()
	_resolve_rect.material = _resolve_material
	_picture_viewport.add_child(_resolve_rect)
	_apply_measuring()


func _apply_measuring() -> void:
	if _samples_viewport == null:
		return
	RenderingServer.viewport_set_measure_render_time(_samples_viewport.get_viewport_rid(), measure_render_time)
	RenderingServer.viewport_set_measure_render_time(_picture_viewport.get_viewport_rid(), measure_render_time)
	if _shadow_viewport != null:
		RenderingServer.viewport_set_measure_render_time(_shadow_viewport.get_viewport_rid(), measure_render_time)
	if _marks_viewport != null:
		RenderingServer.viewport_set_measure_render_time(_marks_viewport.get_viewport_rid(), measure_render_time)


# Gathers the instances and lays their splats end to end. Each splat's last float carries its instance.
func _rebuild() -> void:
	var started: int = Time.get_ticks_usec()
	rebuild_count += 1
	_built_version = SplatInstance.version
	_built_art_size = art_size
	_samples_viewport.size = art_size * 2
	_picture_viewport.size = art_size
	if _marks_viewport != null:
		_marks_viewport.size = art_size * 2
	_resolve_rect.position = Vector2.ZERO
	_resolve_rect.size = Vector2(art_size)

	_instances.clear()
	_gather(instances_root if instances_root != null else get_parent())
	instance_count = _instances.size()
	_first_bone.resize(instance_count)
	_last_stamp.resize(instance_count)
	_worn.resize(instance_count)
	if instance_count > MAX_INSTANCES:
		push_warning("[SplatScene] %d instances; one picture holds %d." % [instance_count, MAX_INSTANCES])
	_turns.resize(instance_count)
	_first_ramp.resize(instance_count)

	# Light data, for the shader to light splats again: each splat's normal and ramp, how bright its bake
	# came out, and every file's ramps as rows of packed colours. Whole arrays are appended, so this costs
	# no loop over the splats.
	var lights: PackedFloat32Array = PackedFloat32Array()
	var brights: PackedFloat32Array = PackedFloat32Array()
	var ramp_rows: Array[PackedInt32Array] = []
	var ramp_palettes: Array[PackedInt32Array] = []
	var first_ramp_of: Dictionary[SplatClip, int] = {}
	var longest_ramp: int = 1
	_look_width = 1

	var data: PackedFloat32Array = PackedFloat32Array()
	var splats: int = 0
	var bone_total: int = 0
	for n: int in instance_count:
		var instance: SplatInstance = _instances[n]
		var clip: SplatClip = instance.get_clip()
		_first_bone[n] = bone_total
		_last_stamp[n] = -1
		_worn[n] = instance.look_version
		_turns[n] = _turn_of(instance)
		var wardrobe: bool = clip.has_look()
		# a wardrobe's splats say which piece they are, and name a region's colour by its palette index
		data.append_array(clip.look_splats() if wardrobe else clip.splats)
		var colours: PackedFloat32Array = clip.colour_sets[_turns[n]] if clip.is_prop() else PackedFloat32Array()
		for i: int in clip.splat_count:
			var o: int = (splats + i) * SplatClip.STRIDE
			if not colours.is_empty():
				data[o + 7] = colours[i]
			data[o + 15] = n + MAX_INSTANCES * (clip.piece_of[i] + 1) if wardrobe else n
		if wardrobe:
			# its ramps are its own rows: they hold the colours it wears
			_look_width = maxi(_look_width, maxi(clip.pieces.size(), clip.palette.size()))
			_first_ramp[n] = ramp_rows.size()
			for ramp: PackedInt32Array in clip.ramps:
				ramp_rows.append(ramp)
				ramp_palettes.append(instance.look_palette())
				longest_ramp = maxi(longest_ramp, ramp.size())
		else:
			if not first_ramp_of.has(clip):
				first_ramp_of[clip] = ramp_rows.size()
				for ramp: PackedInt32Array in clip.ramps:
					ramp_rows.append(ramp)
					ramp_palettes.append(clip.palette)
					longest_ramp = maxi(longest_ramp, ramp.size())
			_first_ramp[n] = first_ramp_of[clip]
		lights.append_array(clip.light_texels())
		if clip.has_light():
			brights.append_array(clip.brightness[mini(_turns[n], clip.brightness.size() - 1)])
		else:
			brights.resize(brights.size() + clip.splat_count) # never read: these splats have no ramp
		splats += clip.splat_count
		bone_total += clip.bone_count
	splat_count = splats

	var splats_in_a_row: int = _SPLATS_WIDTH / 4
	var rows: int = maxi(1, ceili(splats / float(splats_in_a_row)))
	data.resize(rows * _SPLATS_WIDTH * 4)
	var splat_image: Image = Image.create_from_data(_SPLATS_WIDTH, rows, false, Image.FORMAT_RGBAF, data.to_byte_array())
	_draw_material.set_shader_parameter(&"splats", ImageTexture.create_from_image(splat_image))

	var light_rows: int = maxi(1, ceili(splats / float(_LIGHTS_WIDTH)))
	lights.resize(light_rows * _LIGHTS_WIDTH * 4)
	_draw_material.set_shader_parameter(&"lights", ImageTexture.create_from_image(
			Image.create_from_data(_LIGHTS_WIDTH, light_rows, false, Image.FORMAT_RGBAF, lights.to_byte_array())))
	var bright_rows: int = maxi(1, ceili(splats / float(_LIGHTS_WIDTH * 4)))
	brights.resize(bright_rows * _LIGHTS_WIDTH * 4)
	_draw_material.set_shader_parameter(&"brightness", ImageTexture.create_from_image(
			Image.create_from_data(_LIGHTS_WIDTH, bright_rows, false, Image.FORMAT_RGBAF, brights.to_byte_array())))
	_ramp_width = longest_ramp
	_ramp_rows = maxi(1, ramp_rows.size())
	_ramp_data.resize(_ramp_rows * _ramp_width * 4)
	_ramp_data.fill(0.0)
	for r: int in ramp_rows.size():
		_write_ramp(r, ramp_rows[r], ramp_palettes[r])
	_ramp_texture = ImageTexture.create_from_image(
			Image.create_from_data(_ramp_width, _ramp_rows, false, Image.FORMAT_RGBAF, _ramp_data.to_byte_array()))
	_draw_material.set_shader_parameter(&"ramps", _ramp_texture)

	# What each instance wears, one instance a row: a texel's first float says whether the piece of that
	# number shows, its second is the palette colour of that number.
	_look_data.resize(maxi(1, instance_count) * _look_width * 4)
	_look_data.fill(0.0)
	for n: int in instance_count:
		_write_look(n, false)
	_look_texture = ImageTexture.create_from_image(
			Image.create_from_data(_look_width, maxi(1, instance_count), false, Image.FORMAT_RGBAF, _look_data.to_byte_array()))
	_draw_material.set_shader_parameter(&"looks", _look_texture)

	_instance_data.resize(maxi(1, instance_count) * _INSTANCE_FLOATS)
	_instance_data.fill(0.0)
	_instance_texture = ImageTexture.create_from_image(
			Image.create_from_data(_INSTANCE_FLOATS / 4, maxi(1, instance_count), false, Image.FORMAT_RGBAF, _instance_data.to_byte_array()))
	_draw_material.set_shader_parameter(&"instances", _instance_texture)

	_bone_rows = maxi(1, ceili(bone_total * 3 / float(_BONES_WIDTH)))
	_bone_data.resize(_bone_rows * _BONES_WIDTH * 4)
	_bone_data.fill(0.0)
	_bone_texture = ImageTexture.create_from_image(
			Image.create_from_data(_BONES_WIDTH, _bone_rows, false, Image.FORMAT_RGBAF, _bone_data.to_byte_array()))
	_draw_material.set_shader_parameter(&"bones", _bone_texture)

	# The quads take nothing from the MultiMesh but their number; its transforms are never read.
	_multimesh.instance_count = splats
	if splats > 0:
		var transforms: PackedFloat32Array = PackedFloat32Array()
		transforms.resize(splats * 12)
		_multimesh.buffer = transforms

	_set_palette()
	last_rebuild_msec = (Time.get_ticks_usec() - started) / 1000.0


# One palette for the picture: the first asset's background, then every colour once, each instance's
# as it wears it.
func _set_palette() -> void:
	var palette: PackedInt32Array = PackedInt32Array()
	var seen: Dictionary[int, bool] = {}
	var last: PackedInt32Array = PackedInt32Array()
	for instance: SplatInstance in _instances:
		var colours: PackedInt32Array = instance.look_palette()
		if colours == last:
			continue # the same asset in the same colours again
		last = colours
		for c: int in range(0 if palette.is_empty() else 1, colours.size()):
			if not seen.has(colours[c]):
				seen[colours[c]] = true
				palette.append(colours[c])
	if palette.size() > MAX_PALETTE:
		push_warning("[SplatScene] %d colours in the picture; the pixel look reads the first %d." % [palette.size(), MAX_PALETTE])
	palette_count = mini(MAX_PALETTE, palette.size())
	var colour_vectors: PackedVector3Array = PackedVector3Array()
	colour_vectors.resize(MAX_PALETTE)
	for i: int in palette_count:
		colour_vectors[i] = Vector3(((palette[i] >> 16) & 255) / 255.0, ((palette[i] >> 8) & 255) / 255.0, (palette[i] & 255) / 255.0)
	_resolve_material.set_shader_parameter(&"pal", colour_vectors)
	_resolve_material.set_shader_parameter(&"pal_count", maxi(1, palette_count))


# One ramp's row: (packed colour, the ramp's length, 0, 0) for each of its colours, dark to light.
func _write_ramp(row: int, ramp: PackedInt32Array, palette: PackedInt32Array) -> void:
	for c: int in ramp.size():
		var o: int = (row * _ramp_width + c) * 4
		_ramp_data[o] = SplatClip.pack(palette[ramp[c]])
		_ramp_data[o + 1] = ramp.size()


# What instance n wears, into its row of the look data; with ramps, into its rows of the ramp data too.
# Nothing for an instance whose asset has no wardrobe.
func _write_look(n: int, ramps: bool = true) -> void:
	var instance: SplatInstance = _instances[n]
	var clip: SplatClip = instance.get_clip()
	if not clip.has_look():
		return
	var palette: PackedInt32Array = instance.look_palette()
	var row: int = n * _look_width * 4
	for p: int in clip.pieces.size():
		_look_data[row + p * 4] = 1.0 if instance.shows(clip.pieces[p]) else 0.0
	for c: int in palette.size():
		_look_data[row + c * 4 + 1] = SplatClip.pack(palette[c])
	if ramps:
		for r: int in clip.ramps.size():
			_write_ramp(_first_ramp[n] + r, clip.ramps[r], palette)


# After a change of look: the two small textures and the picture's palette. The splats stay as they are.
func _upload_looks() -> void:
	_look_texture.update(Image.create_from_data(_look_width, maxi(1, instance_count), false, Image.FORMAT_RGBAF, _look_data.to_byte_array()))
	_ramp_texture.update(Image.create_from_data(_ramp_width, _ramp_rows, false, Image.FORMAT_RGBAF, _ramp_data.to_byte_array()))
	_set_palette()


func _gather(node: Node) -> void:
	if node == null:
		return
	if node is SplatInstance:
		var instance: SplatInstance = node
		if instance.is_visible_in_tree() and instance.get_clip() != null:
			_instances.append(instance)
	for child: Node in node.get_children():
		_gather(child)


# A prop's colours were baked for the quarter turn it stands at, about the world's y.
static func _turn_of(instance: SplatInstance) -> int:
	return SplatClip.turn_of(instance.global_rotation.y)
# endregion
