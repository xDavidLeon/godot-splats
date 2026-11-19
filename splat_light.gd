## The light rules of the splat renderer, in plain script: how a lamp and the dusk move a splat along
## the ramp it was shaded on, and which floor cells a thing's shadow marks.
##
## An asset's colours are baked (ink-studio shades every splat on a ramp of palette colours, dark to
## light), but a file with light data also says how each splat was lit: its ramp, how bright it came
## out and its normal ([method SplatClip.has_light]). So a lamp standing near, or the day dimming,
## only moves a splat along its own ramp: the picture keeps its palette and its hand-picked colours.
## [br][br]
## [b]Dusk[/b] is whole steps down the ramp. Scaling the brightness instead looks wrong: the faint
## tone wobble baked into a flat floor straddles a step and comes out as blotches.
## [br][br]
## [b]A lamp[/b] adds what ink-studio's own point lights add: (1 - distance / reach)² × strength ×
## (0.2 + 0.8 × how much the surface faces it). Nothing blocks a lamp's light; it casts no shadows.
## [br][br]
## [b]A floor shadow[/b] is cast by the game, not baked, because it falls on another asset and has to
## follow the thing: every splat is carried down the sun's ray to the floor and marks the cell it
## lands in.
## [br][br]
## [SplatScene] applies these rules on the GPU every frame ([code]splat_scene_draw.gdshader[/code],
## [code]splat_shadow_cast.gdshader[/code]). The functions here are the same rules for anything that
## wants the answer in script, and they are what the tests check.
# In Unity, these are SplatLight.Relight and SplatShadow.Cast, run on the CPU whenever the room's
# contents changed. Unity's reader flips z; nothing is flipped here.
class_name SplatLight
extends RefCounted


# region Constants
## The share of a lamp's light a surface gets however it is turned.
const AMBIENT: float = 0.2
## Splats lower than this above the floor cast no shadow, in metres: a rug, or the floor itself.
const SHADOW_MIN_HEIGHT: float = 0.03
# endregion


# region Colours
## The packed colour a splat takes at a [param brightness]: its ramp's entry at
## floor(brightness × length), then [param dusk] steps darker. The splat must have a ramp.
static func colour_at(clip: SplatClip, splat: int, brightness: float, dusk: int = 0) -> float:
	var ramp: PackedInt32Array = clip.ramps[clip.ramp_of[splat]]
	var index: int = clampi(floori(brightness * ramp.size()) - dusk, 0, ramp.size() - 1)
	return SplatClip.pack(clip.palette[ramp[index]])


## What the lamps add to the brightness of a surface at [param position] with [param normal] (a unit
## vector), both in the world. A lamp is a [Vector4]: where it is, and how far it reaches in metres.
## [param strengths] holds what each adds right next to it, where 1 is a whole ramp.
static func added_by_lamps(position: Vector3, normal: Vector3, lamps: PackedVector4Array, strengths: PackedFloat32Array) -> float:
	var added: float = 0.0
	for l: int in lamps.size():
		var lamp: Vector4 = lamps[l]
		var to_lamp: Vector3 = Vector3(lamp.x, lamp.y, lamp.z) - position
		var squared: float = to_lamp.length_squared()
		if squared >= lamp.w * lamp.w:
			continue
		var distance: float = sqrt(squared)
		var falloff: float = 1.0 - distance / lamp.w
		var facing: float = normal.dot(to_lamp) / distance if distance > 1e-5 else 1.0
		added += falloff * falloff * strengths[l] * (AMBIENT + (1.0 - AMBIENT) * maxf(0.0, facing))
	return added


## Writes the colours of an asset's splats into [param data] (splat records, the asset's first at
## index [param at]) as the lamps and the dusk make them. [param turn] picks the bake (a prop's
## quarter turn; a clip has one), [param to_world] places the asset, [param dusk] is how many ramp
## steps the day has dimmed (0 is the bake). Splats with no ramp and assets with no light data are
## left alone. Returns how many splats changed colour.
## [br][br]
## Splats are lit where the file has them: a clip's bones are not applied (the scene's shader does
## apply them).
static func relight(clip: SplatClip, turn: int, to_world: Transform3D, lamps: PackedVector4Array, strengths: PackedFloat32Array,
		dusk: int, data: PackedFloat32Array, at: int = 0) -> int:
	if not clip.has_light():
		return 0
	var baked: PackedFloat32Array = clip.brightness[mini(turn, clip.brightness.size() - 1)]
	var changed: int = 0
	for i: int in clip.splat_count:
		if clip.ramp_of[i] < 0:
			continue
		var added: float = 0.0
		if not lamps.is_empty():
			var o: int = i * SplatClip.STRIDE
			var normal: Vector3 = to_world.basis * Vector3(clip.normals[i * 3], clip.normals[i * 3 + 1], clip.normals[i * 3 + 2])
			if normal.length_squared() > 1e-12:
				normal = normal.normalized()
			added = added_by_lamps(to_world * Vector3(clip.splats[o], clip.splats[o + 1], clip.splats[o + 2]), normal, lamps, strengths)
		if added == 0.0 and dusk == 0:
			continue # exactly the bake
		var colour: float = colour_at(clip, i, baked[i] + added, dusk)
		var into: int = (at + i) * SplatClip.STRIDE + 7
		if data[into] != colour:
			data[into] = colour
			changed += 1
	return changed
# endregion


# region Shadows
## Marks, in [param cells], the floor cells under an asset placed by [param to_world]: each splat is
## carried along [param sun] (which points at the sun, and must rise) down to the floor at
## [param floor_height]. A cell is [param cell] metres across; cell (x, z) spans x × cell to
## (x + 1) × cell. Splats lower than [constant SHADOW_MIN_HEIGHT] above the floor cast nothing.
## [br][br]
## Splats are cast from where the file has them: a clip's bones are not applied (the scene's shader
## does apply them).
static func shadow_cells(clip: SplatClip, to_world: Transform3D, sun: Vector3, cell: float, cells: Dictionary[Vector2i, bool],
		floor_height: float = 0.0) -> void:
	if sun.y <= 0.0 or cell <= 0.0:
		push_error("[SplatLight] The sun must be above the horizon, and a cell must have a size.")
		return
	var slope: Vector2 = Vector2(sun.x, sun.z) / sun.y
	for i: int in clip.splat_count:
		var o: int = i * SplatClip.STRIDE
		var p: Vector3 = to_world * Vector3(clip.splats[o], clip.splats[o + 1], clip.splats[o + 2])
		var height: float = p.y - floor_height
		if height < SHADOW_MIN_HEIGHT:
			continue
		# down the sun's ray to the floor
		cells[Vector2i(floori((p.x - slope.x * height) / cell), floori((p.z - slope.y * height) / cell))] = true
# endregion
