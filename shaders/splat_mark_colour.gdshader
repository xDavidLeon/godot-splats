// Lines drawn into the picture on top of what lies under them, second half: their colours, in a
// target of their own of the samples' size. Nothing is depth-tested here: a line hidden by a thing is
// drawn too, and splat_resolve.gdshader reads this only where splat_mark_cut.gdshader cleared the
// sample. Where lines cross, the one given last shows. See splat_marks.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled, depth_test_disabled, depth_draw_never;

#include "splat_marks.gdshaderinc"

void vertex() {
	vec2 at_pixel;
	vec4 line_paint;
	POSITION = mark_position(INSTANCE_ID, VERTEX.xy, at_pixel, line_paint); // the quad's corners are at -1 and 1
	pixel = at_pixel;
	paint = line_paint;
}

void fragment() {
	if (mark_skipped(pixel, paint.w)) {
		discard;
	}
	// the line's own sRGB colour, as splat_scene_draw.gdshader writes a splat's
	vec3 colour = paint.rgb;
	if (OUTPUT_IS_SRGB) {
		ALBEDO = colour;
	} else {
		ALBEDO = mix(colour / 12.92, pow((colour + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), colour));
	}
}
