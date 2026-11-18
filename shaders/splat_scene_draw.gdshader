// Draws every splat of a scene into one small render target, one quad a splat (a MultiMesh instance).
// Ported from a Unity shader of the same design, which ports the projection of
// ink-studio's cli/render.js (MIT, Shapeshift Labs).
//   - Nothing is sorted and nothing is posed on the CPU: each splat is posed here, by its bone and
//     then by its instance's transform.
//   - Solid splats are cut out at half their Gaussian and written with depth, so the depth buffer
//     orders them.
// No compute or geometry shader. Where Unity reads StructuredBuffers in the vertex shader, this reads
// float textures with texelFetch, which the Compatibility renderer (and WebGL 2) can do.
// Not ported: floor shadows, particles (an instance's motion), the tinted ghost and the edit marks.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

// 16 floats a splat in 4 texels, row after row:
//   (x, y, z, density) (c00, c01, c02, packed colour) (c11, c12, c22, kind) (bone, second bone, its weight, instance)
uniform sampler2D splats : filter_nearest, repeat_disable;
// 16 floats an instance in 4 texels, one instance a row: its 3x4 object-to-world by rows, then
//   (first bone, unused, depth bias in metres, unused)
uniform sampler2D instances : filter_nearest, repeat_disable;
// 12 floats a bone in 3 texels: every instance's bones for this frame, end to end
uniform sampler2D bones : filter_nearest, repeat_disable;
uniform int splats_width = 1024; // texels in a row of the splat texture: a multiple of 4
uniform int bones_width = 768;   // texels in a row of the bone texture: a multiple of 3
uniform mat4 view;               // world -> camera view (right-handed, looking down -z)
uniform vec2 size;               // target width, height in pixels
uniform vec4 lens;               // x: pixels per metre (orthographic) or focal length in pixels (perspective); y: 1 if orthographic; z: near; w: far

varying vec2 offset; // pixels from the splat's centre
varying vec3 conic;  // the inverse of its screen covariance
varying vec3 colour; // sRGB, 0..1

vec4 splat_texel(int splat, int part) {
	int i = splat * 4 + part;
	return texelFetch(splats, ivec2(i % splats_width, i / splats_width), 0);
}

// a 3x3 given by its rows, so that m * v is (dot(r0, v), dot(r1, v), dot(r2, v))
mat3 by_rows(vec3 r0, vec3 r1, vec3 r2) {
	return transpose(mat3(r0, r1, r2));
}

void bone(int index, out mat3 m, out vec3 t) {
	int i = index * 3;
	ivec2 at = ivec2(i % bones_width, i / bones_width);
	vec4 a = texelFetch(bones, at, 0);
	vec4 b = texelFetch(bones, at + ivec2(1, 0), 0);
	vec4 c = texelFetch(bones, at + ivec2(2, 0), 0);
	m = by_rows(a.xyz, vec3(a.w, b.xy), vec3(b.zw, c.x));
	t = c.yzw;
}

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

void vertex() {
	POSITION = vec4(2.0, 2.0, 2.0, 1.0); // outside the clip volume: dropped
	offset = vec2(0.0);
	conic = vec3(0.0);
	colour = vec3(0.0);

	vec4 s0 = splat_texel(INSTANCE_ID, 0);
	if (s0.w >= 1.0) { // soft splats are not drawn (the room's assets have none)
		vec4 s1 = splat_texel(INSTANCE_ID, 1);
		vec4 s2 = splat_texel(INSTANCE_ID, 2);
		vec4 s3 = splat_texel(INSTANCE_ID, 3);
		vec3 p = s0.xyz;
		mat3 cov = mat3(vec3(s1.x, s1.y, s1.z), vec3(s1.y, s2.x, s2.y), vec3(s1.z, s2.y, s2.z)); // symmetric
		int inst = int(s3.w);
		vec4 i0 = texelFetch(instances, ivec2(0, inst), 0);
		vec4 i1 = texelFetch(instances, ivec2(1, inst), 0);
		vec4 i2 = texelFetch(instances, ivec2(2, inst), 0);
		vec4 i3 = texelFetch(instances, ivec2(3, inst), 0);
		bool shown = true;

		if (int(round(s2.w)) % 16 == 12) {
			int first = int(i3.x);
			mat3 m;
			vec3 t;
			bone(first + int(s3.x), m, t);
			vec3 posed = m * p + t;
			if (s3.z > 0.0) {
				mat3 m2;
				vec3 t2;
				bone(first + int(s3.y), m2, t2);
				posed += (m2 * p + t2 - posed) * s3.z;
			}
			if (posed.y < -30.0) {
				shown = false; // a hidden part (ink-studio parks it at y = -99)
			}
			p = posed;
			cov = m * cov * transpose(m);
		}

		mat3 world = by_rows(i0.xyz, i1.xyz, i2.xyz);
		vec3 at = world * p + vec3(i0.w, i1.w, i2.w);
		cov = world * cov * transpose(world);

		vec3 v = (view * vec4(at, 1.0)).xyz;
		if (-v.z < lens.z) {
			shown = false;
		}
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
		if (shown && det > 0.0) {
			conic = vec3(C / det, -B / det, A / det);
			// The cut-out keeps exp(power) >= 0.5, which ends 1.18 standard deviations out; the quad need go no
			// further (ink-studio's blended dabs reach 3). A pixel is added for the edge.
			vec2 extent = vec2(min(1.2 * sqrt(A) + 1.0, 2048.0), min(1.2 * sqrt(C) + 1.0, 2048.0));
			offset = VERTEX.xy * extent; // the quad's corners are at -1 and 1
			// a thin thing lying on a surface is tested a little nearer than it is (the instance's depth bias)
			POSITION = clip_of(pixel_of(v) + offset, vec3(v.xy, v.z + i3.z));
			float pk = s1.w;
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
