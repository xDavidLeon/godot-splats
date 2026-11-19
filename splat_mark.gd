## A line drawn into a [SplatScene]'s picture on top of what lies under it
## ([method SplatScene.set_marks]): from and to in world space, the normal of the surface it lies on,
## and its colour. The line is a flat strip lying on that surface, [member SplatScene.mark_width] art
## pixels wide. A colour with an alpha under 255 is drawn on every other art pixel, for a lighter
## line; no line is ever see-through.
##
## What the lines are for is the caller's business: an editor's grid, an outline round what is
## selected, the footprint of a thing being placed.
# In Unity, this is the scene component's Mark struct.
class_name SplatMark
extends RefCounted


# region State
## Where the line starts, in the world.
var from: Vector3
## Where it ends.
var to: Vector3
## The normal of the surface it lies on: the strip is flat against it.
var normal: Vector3
## Its colour, sRGB. An alpha under 255 makes it dotted.
var colour: Color
# endregion


# region Lifecycle
func _init(line_from: Vector3 = Vector3.ZERO, line_to: Vector3 = Vector3.ZERO, surface_normal: Vector3 = Vector3.UP, line_colour: Color = Color.WHITE) -> void:
	from = line_from
	to = line_to
	normal = surface_normal
	colour = line_colour
# endregion


# region Public API
## Whether it is drawn on every other art pixel.
func is_dotted() -> bool:
	return colour.a8 < 255


## The four sides of a parallelogram as lines, one after the other: its [param centre], and half of
## each side as a vector ([param half_u], [param half_v]). For an outline.
static func outline(centre: Vector3, half_u: Vector3, half_v: Vector3, surface_normal: Vector3, line_colour: Color) -> Array[SplatMark]:
	var a: Vector3 = centre - half_u - half_v
	var b: Vector3 = centre + half_u - half_v
	var c: Vector3 = centre + half_u + half_v
	var d: Vector3 = centre - half_u + half_v
	return [SplatMark.new(a, b, surface_normal, line_colour), SplatMark.new(b, c, surface_normal, line_colour),
			SplatMark.new(c, d, surface_normal, line_colour), SplatMark.new(d, a, surface_normal, line_colour)]
# endregion
