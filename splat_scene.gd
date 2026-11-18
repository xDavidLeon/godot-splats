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
## Not ported from Unity: floor shadows, relighting by lamps and dusk, the wardrobe, clip cross-fades,
## particles and the editing overlays.
# In Unity, the draw is a CommandBuffer with DrawProcedural and StructuredBuffers. Here two
# SubViewports do it: a 3D one (it has a depth buffer) holding one MultiMesh of quads, and a 2D one
# for the resolve. Neither needs compute shaders, so the Compatibility renderer can run it.
class_name SplatScene
extends Node


# region Constants
const DRAW_SHADER: Shader = preload("res://addons/splats/shaders/splat_scene_draw.gdshader")
const RESOLVE_SHADER: Shader = preload("res://addons/splats/shaders/splat_resolve.gdshader")

## Colours the pixel look can tell apart in one picture.
const MAX_PALETTE: int = 128

const _SPLATS_WIDTH: int = 1024       # texels in a row: 256 splats
const _BONES_WIDTH: int = 768         # texels in a row: 256 bones
const _INSTANCE_FLOATS: int = 16
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

## The clips' clock in seconds. Negative: the engine's own time.
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
## How many times the big texture has been rebuilt.
var rebuild_count: int = 0
## What the last frame cost this script, in milliseconds (uploads included, the GPU's work not).
var last_cpu_msec: float = 0.0
## What the last rebuild cost, in milliseconds.
var last_rebuild_msec: float = 0.0

var _instances: Array[SplatInstance] = []
var _first_bone: PackedInt32Array = PackedInt32Array()
var _last_frame: PackedInt32Array = PackedInt32Array()
var _turns: PackedInt32Array = PackedInt32Array()
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


## The picture before the pixel look: twice the art resolution, coverage in alpha. For debugging.
func get_samples() -> ViewportTexture:
	return _samples_viewport.get_texture()


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
	var bones_changed: bool = false
	for i: int in _instances.size():
		var instance: SplatInstance = _instances[i]
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
		_instance_data[o + 14] = instance.depth_bias
		var clip: SplatClip = instance.get_clip()
		if clip.bone_count == 0:
			continue
		var frame: int = instance.frame_at(seconds)
		if frame == _last_frame[i]:
			continue
		_last_frame[i] = frame
		var from: int = frame * clip.bone_count * SplatClip.BONE_STRIDE
		var to: int = _first_bone[i] * SplatClip.BONE_STRIDE
		for f: int in clip.bone_count * SplatClip.BONE_STRIDE:
			_bone_data[to + f] = clip.bones[from + f]
		bones_changed = true
	if not _instances.is_empty():
		_instance_texture.update(Image.create_from_data(4, _instances.size(), false, Image.FORMAT_RGBAF, _instance_data.to_byte_array()))
	if bones_changed:
		_bone_texture.update(Image.create_from_data(_BONES_WIDTH, _bone_rows, false, Image.FORMAT_RGBAF, _bone_data.to_byte_array()))

	var samples_height: float = art_size.y * 2.0
	var orthographic: bool = camera.projection == Camera3D.PROJECTION_ORTHOGONAL
	var lens: float = samples_height * 0.5 / (camera.size * 0.5) if orthographic \
			else samples_height * 0.5 / tan(deg_to_rad(camera.fov) * 0.5)
	_draw_material.set_shader_parameter(&"view", camera.global_transform.affine_inverse())
	_draw_material.set_shader_parameter(&"size", Vector2(art_size * 2))
	_draw_material.set_shader_parameter(&"lens", Vector4(lens, 1.0 if orthographic else 0.0, camera.near, camera.far))
	_resolve_material.set_shader_parameter(&"average_interior", interior == Interior.AVERAGE)
	_resolve_material.set_shader_parameter(&"dither", dither)
	last_cpu_msec = (Time.get_ticks_usec() - started) / 1000.0


## What the two passes (draw and resolve) cost last frame, in milliseconds: x on the CPU, y on the
## GPU. Zero unless [member measure_render_time] is on.
func get_render_msec() -> Vector2:
	if not measure_render_time or _samples_viewport == null:
		return Vector2.ZERO
	var draw: RID = _samples_viewport.get_viewport_rid()
	var resolve: RID = _picture_viewport.get_viewport_rid()
	return Vector2(
			RenderingServer.viewport_get_measured_render_time_cpu(draw) + RenderingServer.viewport_get_measured_render_time_cpu(resolve),
			RenderingServer.viewport_get_measured_render_time_gpu(draw) + RenderingServer.viewport_get_measured_render_time_gpu(resolve))


## One line on what the picture holds and costs.
func status() -> String:
	return "%d splats in %d instances, %d colours, art %dx%d; CPU %.3f ms a frame, last rebuild %.1f ms" % [
		splat_count, instance_count, palette_count, art_size.x, art_size.y, last_cpu_msec, last_rebuild_msec]
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

	var quad: ArrayMesh = ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_draw_material = ShaderMaterial.new()
	_draw_material.shader = DRAW_SHADER
	_draw_material.set_shader_parameter(&"splats_width", _SPLATS_WIDTH)
	_draw_material.set_shader_parameter(&"bones_width", _BONES_WIDTH)
	quad.surface_set_material(0, _draw_material)

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


# Gathers the instances and lays their splats end to end. Each splat's last float carries its instance.
func _rebuild() -> void:
	var started: int = Time.get_ticks_usec()
	rebuild_count += 1
	_built_version = SplatInstance.version
	_built_art_size = art_size
	_samples_viewport.size = art_size * 2
	_picture_viewport.size = art_size
	_resolve_rect.position = Vector2.ZERO
	_resolve_rect.size = Vector2(art_size)

	_instances.clear()
	_gather(instances_root if instances_root != null else get_parent())
	instance_count = _instances.size()
	_first_bone.resize(instance_count)
	_last_frame.resize(instance_count)
	_turns.resize(instance_count)

	var data: PackedFloat32Array = PackedFloat32Array()
	var palette: PackedInt32Array = PackedInt32Array()
	var splats: int = 0
	var bone_total: int = 0
	for n: int in instance_count:
		var instance: SplatInstance = _instances[n]
		var clip: SplatClip = instance.get_clip()
		_first_bone[n] = bone_total
		_last_frame[n] = -1
		_turns[n] = _turn_of(instance)
		data.append_array(clip.splats)
		var colours: PackedFloat32Array = clip.colour_sets[_turns[n]] if clip.is_prop() else PackedFloat32Array()
		for i: int in clip.splat_count:
			var o: int = (splats + i) * SplatClip.STRIDE
			if not colours.is_empty():
				data[o + 7] = colours[i]
			data[o + 15] = n
		splats += clip.splat_count
		bone_total += clip.bone_count
		# one palette for the picture: the first asset's background, then every colour once
		for c: int in range(0 if palette.is_empty() else 1, clip.palette.size()):
			if not palette.has(clip.palette[c]):
				palette.append(clip.palette[c])
	splat_count = splats

	var splats_in_a_row: int = _SPLATS_WIDTH / 4
	var rows: int = maxi(1, ceili(splats / float(splats_in_a_row)))
	data.resize(rows * _SPLATS_WIDTH * 4)
	var splat_image: Image = Image.create_from_data(_SPLATS_WIDTH, rows, false, Image.FORMAT_RGBAF, data.to_byte_array())
	_draw_material.set_shader_parameter(&"splats", ImageTexture.create_from_image(splat_image))

	_instance_data.resize(maxi(1, instance_count) * _INSTANCE_FLOATS)
	_instance_data.fill(0.0)
	_instance_texture = ImageTexture.create_from_image(
			Image.create_from_data(4, maxi(1, instance_count), false, Image.FORMAT_RGBAF, _instance_data.to_byte_array()))
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

	if palette.size() > MAX_PALETTE:
		push_warning("[SplatScene] %d colours in the picture; the pixel look reads the first %d." % [palette.size(), MAX_PALETTE])
	palette_count = mini(MAX_PALETTE, palette.size())
	var colour_vectors: PackedVector3Array = PackedVector3Array()
	colour_vectors.resize(MAX_PALETTE)
	for i: int in palette_count:
		colour_vectors[i] = Vector3(((palette[i] >> 16) & 255) / 255.0, ((palette[i] >> 8) & 255) / 255.0, (palette[i] & 255) / 255.0)
	_resolve_material.set_shader_parameter(&"pal", colour_vectors)
	_resolve_material.set_shader_parameter(&"pal_count", maxi(1, palette_count))
	last_rebuild_msec = (Time.get_ticks_usec() - started) / 1000.0


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
