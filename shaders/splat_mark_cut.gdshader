// Lines drawn into the picture on top of what lies under them, first half: which samples a line
// covers. Drawn into the samples after the splats and depth-tested against them, a little nearer
// than the line is, so a thing standing in front of a line hides it. It takes the sample's alpha to 0
// and leaves its colour; splat_resolve.gdshader then finds the line's colour in the target that
// splat_mark_colour.gdshader drew. See splat_marks.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled, blend_mul, depth_draw_never;

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
	// multiplied in: the colour stays and the alpha goes to 0, however many lines cross here
	ALBEDO = vec3(1.0);
	ALPHA = 0.0;
}
