// Marks the floor under things: a disc on every cell that splat_shadow_cast.gdshader marked. It is
// drawn into the samples after the splats and before the pixel look, which darkens the marked
// samples, so a shadow takes the palette and the pixel grid like everything else.
// Ported from the floor shadow pass of a Unity shader of the same design, which drew one quad a disc,
// multiplied the colour under it, and used a stencil so that discs that overlap darken a pixel once.
// Here it is one quad over the whole target: each pixel finds its point on the floor and asks the
// cells round it, so it is marked once by construction, with no stencil. And it only marks: it halves
// the sample's alpha and leaves its colour, and splat_resolve.gdshader darkens a sample whose alpha
// is a half. The colour is darkened there because the picture holds sRGB values, and Forward+ and
// Mobile hold linear ones while they draw, where no one factor takes a share of an sRGB value.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled, blend_mul, depth_draw_never;

uniform sampler2D cells : filter_nearest, repeat_disable; // the floor's grid from above, one texel a cell: marked where alpha is 1
uniform mat4 eye;         // camera view -> world
uniform vec2 size;        // target width, height in pixels
uniform vec4 lens;        // as in splat_scene_draw.gdshader
uniform vec4 grid;        // x: a cell in metres; y: the discs' height; z: a disc's radius in cells; w: cells across the grid
uniform vec2 first_cell;  // the cell at the grid's first texel
uniform float depth_bias; // metres nearer the camera the discs are depth-tested than they are

varying vec2 pixel;

void vertex() {
	// the quad's corners are at -1 and 1: the whole target. Clip space y points down in a viewport.
	pixel = (vec2(VERTEX.x, -VERTEX.y) * 0.5 + 0.5) * size;
	POSITION = vec4(VERTEX.xy, 0.5, 1.0);
}

void fragment() {
	// this pixel's ray, in the camera's space: it leaves the camera's plane at `from` and goes along `along`
	vec2 p = (pixel - size * 0.5) / lens.x;
	vec3 from = lens.y > 0.5 ? vec3(p, 0.0) : vec3(0.0);
	vec3 along = lens.y > 0.5 ? vec3(0.0, 0.0, -1.0) : vec3(p, -1.0);
	vec3 world_from = (eye * vec4(from, 1.0)).xyz;
	vec3 world_along = mat3(eye) * along;
	if (abs(world_along.y) < 1e-6) {
		discard; // the camera looks along the floor
	}
	float t = (grid.y - world_from.y) / world_along.y; // also how far in front of the camera the point is
	if (t < lens.z) {
		discard;
	}
	vec2 on_floor = (world_from.xz + world_along.xz * t) / grid.x; // in cells
	vec2 here = floor(on_floor);
	bool shadowed = false;
	for (int i = 0; i < 9; i++) {
		vec2 cell = here + vec2(float(i % 3 - 1), float(i / 3 - 1));
		vec2 texel = cell - first_cell;
		if (texel.x < 0.0 || texel.y < 0.0 || texel.x >= grid.w || texel.y >= grid.w) {
			continue;
		}
		vec2 d = on_floor - (cell + 0.5);
		if (dot(d, d) < grid.z * grid.z && texelFetch(cells, ivec2(texel), 0).a > 0.5) {
			shadowed = true;
		}
	}
	if (!shadowed) {
		discard;
	}
	// A floor splat is a flat quad at its centre's depth, so the floor's depth is only right to within
	// a splat. The discs are tested a little nearer than they are, or the floor shows through as a hatch.
	// Depth is written as the splats write it: reversed, the near plane at 1.
	DEPTH = 1.0 - clamp((t - depth_bias - lens.z) / (lens.w - lens.z), 0.0, 1.0);
	// multiplied in: the colour stays, a covered sample's alpha goes from 1 to a half, and where nothing
	// was drawn it stays 0
	ALPHA = 0.5;
#if CURRENT_RENDERER == RENDERER_MOBILE
	ALBEDO = vec3(2.0); // the Mobile renderer multiplies the colour by the alpha first
#else
	ALBEDO = vec3(1.0);
#endif
}
