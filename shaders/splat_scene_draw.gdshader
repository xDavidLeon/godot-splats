// Draws every splat of a scene into one small render target, one quad a splat (a MultiMesh instance).
// Ported from a Unity shader of the same design, which ports the projection of
// ink-studio's cli/render.js (MIT, Shapeshift Labs).
//   - Nothing is sorted and nothing is posed on the CPU: each splat is posed here, by its bone and
//     then by its instance's transform (splat_pose.gdshaderinc).
//   - Solid splats are cut out at half their Gaussian and written with depth, so the depth buffer
//     orders them.
//   - A splat is lit again here: a lamp near it and facing it lifts it along the ramp it was shaded
//     on, and dusk takes it down that ramp by whole steps (the rules are SplatLight's, in
//     splat_light.gd). With no lamp and no dusk its baked colour is used and nothing more is read.
// No compute or geometry shader.
// The floor shadows are drawn after this, by splat_shadow.gdshader.
// Particles (an instance's motion) move in splat_pose.gdshaderinc. The lines drawn over the picture
// (marks) are splat_mark_cut.gdshader and splat_mark_colour.gdshader.
// A tinted instance is drawn in its tint, shaded by how light each splat was so its shape still
// reads, and only on every other art pixel, so what is behind it shows on the others.
// splat_tint.gdshader says which samples those are, and the pixel look leaves them as they are.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

#include "splat_project.gdshaderinc"

const int MAX_LAMPS = 16;

// 4 floats a splat in 1 texel: its normal, and the ramp it was shaded on (counted in its own file; -1: it keeps its colour)
uniform sampler2D lights : filter_nearest, repeat_disable;
// 1 float a splat, four splats a texel: how bright it came out of the bake for the way its instance stands
uniform sampler2D brightness : filter_nearest, repeat_disable;
// one ramp a row, dark to light: (packed colour, the ramp's length, 0, 0)
uniform sampler2D ramps : filter_nearest, repeat_disable;
uniform int lights_width = 1024; // texels in a row of the two textures above
uniform vec4 lamps[16];          // xyz: where it is in the world; w: how far it reaches, in metres
uniform float lamp_strengths[16]; // what it adds right next to it, where 1 is a whole ramp
uniform int lamp_count = 0;
uniform int dusk = 0;            // ramp steps the day has dimmed

varying vec2 offset;  // pixels from the splat's centre
varying vec3 conic;   // the inverse of its screen covariance
varying vec3 colour;  // sRGB, 0..1
varying vec2 pixel;   // where in the target, counted from the bottom left
varying float tinted; // 1 for a splat of a tinted instance

// The splat's packed colour once the lamps and the dusk have moved it along its ramp.
float relit(int splat, vec3 at, mat3 carry, float first_ramp, float baked) {
	vec4 light = texelFetch(lights, ivec2(splat % lights_width, splat / lights_width), 0);
	if (light.w < 0.0) {
		return baked; // not shaded on a ramp (a glowing splat): it keeps its colour
	}
	vec3 normal = carry * light.xyz;
	float normal_length = length(normal);
	if (normal_length > 1e-6) {
		normal /= normal_length;
	}
	float added = 0.0;
	for (int k = 0; k < MAX_LAMPS; k++) {
		if (k >= lamp_count) {
			break;
		}
		vec3 to_lamp = lamps[k].xyz - at;
		float squared = dot(to_lamp, to_lamp);
		float reach = lamps[k].w;
		if (squared >= reach * reach) {
			continue;
		}
		float away = sqrt(squared);
		float falloff = 1.0 - away / reach;
		float facing = away > 1e-5 ? dot(normal, to_lamp) / away : 1.0;
		added += falloff * falloff * lamp_strengths[k] * (0.2 + 0.8 * max(0.0, facing));
	}
	if (added == 0.0 && dusk == 0) {
		return baked; // exactly the bake
	}
	int row = int(first_ramp) + int(light.w);
	int steps = int(texelFetch(ramps, ivec2(0, row), 0).y);
	int quarter = splat / 4;
	float bright = texelFetch(brightness, ivec2(quarter % lights_width, quarter / lights_width), 0)[splat % 4];
	int index = clamp(int(floor((bright + added) * float(steps))) - dusk, 0, steps - 1);
	return texelFetch(ramps, ivec2(index, row), 0).x;
}

void vertex() {
	POSITION = vec4(2.0, 2.0, 2.0, 1.0); // outside the clip volume: dropped
	offset = vec2(0.0);
	conic = vec3(0.0);
	colour = vec3(0.0);
	pixel = vec2(0.0);
	tinted = 0.0;

	vec3 at;
	mat3 cov;
	mat3 carry;
	float pk;
	vec4 of_instance;
	if (pose_splat(INSTANCE_ID, at, cov, carry, pk, of_instance)) {
		vec4 position;
		vec2 from_centre;
		vec3 inverse;
		vec2 at_pixel;
		if (project_splat(at, cov, of_instance.z, VERTEX.xy, position, from_centre, inverse, at_pixel)) { // the quad's corners are at -1 and 1
			POSITION = position;
			offset = from_centre;
			conic = inverse;
			pixel = at_pixel;
			if (lamp_count > 0 || dusk > 0) {
				pk = relit(INSTANCE_ID, at, carry, of_instance.y, pk);
			}
			colour = min(vec3(mod(pk, 256.0), mod(floor(pk / 256.0), 256.0), floor(pk / 65536.0)) / 255.0, vec3(1.0));
			vec4 tint = splat_tint(INSTANCE_ID);
			if (tint.w > 0.5) {
				// the tint, shaded by how light the splat is, so the thing's shape still reads
				// (SplatInstance.tint_shade is the same rule in script)
				colour = clamp(tint.rgb * (0.55 + 0.7 * dot(colour, vec3(0.30, 0.55, 0.15))), 0.0, 1.0);
				tinted = 1.0;
			}
		}
	}
}

void fragment() {
	if (outside_splat(offset, conic) || (tinted > 0.5 && tint_skipped(pixel))) {
		discard;
	}
	// The picture holds the palette's own sRGB values. Forward+ and Mobile encode what a shader writes
	// from linear to sRGB, so there the colour is decoded first and comes out as it went in. The
	// Compatibility renderer writes an unshaded colour as it is.
	if (OUTPUT_IS_SRGB) {
		ALBEDO = colour;
	} else {
		ALBEDO = mix(colour / 12.92, pow((colour + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), colour));
	}
}
