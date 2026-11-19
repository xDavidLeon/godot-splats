// What the two mark shaders share: the lines, and where a line's quad lies in the picture.
// Ported from the marks pass of a Unity shader of the same design, which drew each line as one quad
// with blending off, straight into the samples, with an alpha of a half. A Godot spatial shader cannot
// replace both a colour and its alpha in one draw, so here a line is drawn twice by the same quads:
//   - splat_mark_cut.gdshader, in the samples, depth-tested against the splats: it takes the alpha
//     of the samples the line covers to 0 and leaves their colour;
//   - splat_mark_colour.gdshader, in a target of its own of the same size, with no depth: the line's
//     colour, opaque.
// A sample that is clear in the first and drawn in the second is a line's, and splat_resolve.gdshader
// reads its colour from the second. Both are the same whatever lines overlap.

// 16 floats a line in 4 texels, one line a row:
//   (from, 0) (to, 0) (the normal of the surface it lies on, 0) (its colour, sRGB 0..1; 1 if dotted)
uniform sampler2D lines : filter_nearest, repeat_disable;
uniform mat4 view;   // world -> camera view (right-handed, looking down -z)
uniform vec2 size;   // target width, height in pixels
uniform vec4 lens;   // as in splat_scene_draw.gdshader
uniform vec2 mark;   // x: half a line's width in metres; y: metres nearer the camera it is depth-tested than it is

varying vec2 pixel;   // where in the target, counted from the bottom left
varying vec4 paint;   // the line's colour; w: 1 if dotted

// A corner of a line's quad in clip space, with what the fragment needs: where it is in the target, and
// the line's colour.
vec4 mark_position(int line, vec2 corner, out vec2 at_pixel, out vec4 line_paint) {
	at_pixel = vec2(0.0);
	line_paint = vec4(0.0);
	vec3 from = texelFetch(lines, ivec2(0, line), 0).xyz;
	vec3 to = texelFetch(lines, ivec2(1, line), 0).xyz;
	vec3 normal = texelFetch(lines, ivec2(2, line), 0).xyz;
	vec3 along = to - from;
	vec3 across = cross(normal, along);
	if (dot(along, along) < 1e-12 || dot(across, across) < 1e-12) {
		return vec4(2.0, 2.0, 2.0, 1.0); // no length, or it stands on its surface: dropped
	}
	along = normalize(along);
	across = normalize(across);
	// the ends go half a width further, so the lines of an outline meet at its corners
	vec3 at = (corner.x > 0.0 ? to : from) + along * corner.x * mark.x + across * corner.y * mark.x;
	vec3 v = (view * vec4(at, 1.0)).xyz;
	float k = lens.y > 0.5 ? lens.x : lens.x / -v.z;
	at_pixel = v.xy * k + size * 0.5;
	line_paint = texelFetch(lines, ivec2(3, line), 0);
	vec2 ndc = at_pixel / size * 2.0 - 1.0;
	float depth = clamp((-(v.z + mark.y) - lens.z) / (lens.w - lens.z), 0.0, 1.0); // 0 near, 1 far
	// as splat_scene_draw.gdshader writes it: y down, depth reversed
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return vec4(ndc.x, -ndc.y, 1.0 - 2.0 * depth, 1.0);
#else
	return vec4(ndc.x, -ndc.y, 1.0 - depth, 1.0);
#endif
}

// A dotted line is drawn on every other art pixel. The target is twice the art resolution, and the
// art's rows are counted from the top.
bool mark_skipped(vec2 at_pixel, float dotted) {
	if (dotted < 0.5) {
		return false;
	}
	ivec2 art = ivec2(floor(vec2(at_pixel.x, size.y - at_pixel.y))) >> 1;
	return ((art.x + art.y) & 1) != 0;
}
