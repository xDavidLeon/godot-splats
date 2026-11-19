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
// Not ported: particles (an instance's motion), the tinted ghost and the edit marks.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

#include "splat_pose.gdshaderinc"

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
uniform mat4 view;               // world -> camera view (right-handed, looking down -z)
uniform vec2 size;               // target width, height in pixels
uniform vec4 lens;               // x: pixels per metre (orthographic) or focal length in pixels (perspective); y: 1 if orthographic; z: near; w: far

varying vec2 offset; // pixels from the splat's centre
varying vec3 conic;  // the inverse of its screen covariance
varying vec3 colour; // sRGB, 0..1

// a view-space point's pixel
vec2 pixel_of(vec3 v) {
	float k = lens.y > 0.5 ? lens.x : lens.x / -v.z;
	return v.xy * k + size * 0.5;
}

vec4 clip_of(vec2 pixel, vec3 v) {
	vec2 ndc = pixel / size * 2.0 - 1.0;
	float depth = clamp((-v.z - lens.z) / (lens.w - lens.z), 0.0, 1.0); // 0 near, 1 far
	// POSITION is written as it is, and a viewport's clip space has y pointing down in every renderer.
	// Godot's depth is reversed: the near plane is 1. The far plane is 0, or -1 in the Compatibility renderer.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return vec4(ndc.x, -ndc.y, 1.0 - 2.0 * depth, 1.0);
#else
	return vec4(ndc.x, -ndc.y, 1.0 - depth, 1.0);
#endif
}

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

	vec3 at;
	mat3 cov;
	mat3 carry;
	float pk;
	vec4 of_instance;
	if (pose_splat(INSTANCE_ID, at, cov, carry, pk, of_instance)) {
		vec3 v = (view * vec4(at, 1.0)).xyz;
		mat3 r = transpose(mat3(view)); // r[0], r[1], r[2]: the rows of the view's rotation
		vec3 a;
		vec3 c;
		if (lens.y > 0.5) {
			a = lens.x * r[0];
			c = lens.x * r[1];
		} else {
			float iz = -1.0 / v.z;
			a = lens.x * iz * r[0] + lens.x * v.x * iz * iz * r[2];
			c = lens.x * iz * r[1] + lens.x * v.y * iz * iz * r[2];
		}
		float A = dot(a, cov * a) + 0.15;
		float B = dot(c, cov * a);
		float C = dot(c, cov * c) + 0.15;
		float det = A * C - B * B;
		if (-v.z >= lens.z && det > 0.0) {
			conic = vec3(C / det, -B / det, A / det);
			// The cut-out keeps exp(power) >= 0.5, which ends 1.18 standard deviations out; the quad need go no
			// further (ink-studio's blended dabs reach 3). A pixel is added for the edge.
			vec2 extent = vec2(min(1.2 * sqrt(A) + 1.0, 2048.0), min(1.2 * sqrt(C) + 1.0, 2048.0));
			offset = VERTEX.xy * extent; // the quad's corners are at -1 and 1
			// a thin thing lying on a surface is tested a little nearer than it is (the instance's depth bias)
			POSITION = clip_of(pixel_of(v) + offset, vec3(v.xy, v.z + of_instance.z));
			if (lamp_count > 0 || dusk > 0) {
				pk = relit(INSTANCE_ID, at, carry, of_instance.y, pk);
			}
			colour = min(vec3(mod(pk, 256.0), mod(floor(pk / 256.0), 256.0), floor(pk / 65536.0)) / 255.0, vec3(1.0));
		}
	}
}

void fragment() {
	vec2 d = offset;
	float power = -0.5 * (conic.x * d.x * d.x + conic.z * d.y * d.y) - conic.y * d.x * d.y;
	if (power + 0.693147 < 0.0) { // exp(power) >= 0.5: the middle of ink-studio's hard edge
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
