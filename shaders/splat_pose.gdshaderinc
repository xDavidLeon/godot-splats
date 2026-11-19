// What the draw pass and the shadow pass share: the scene's float textures, and posing a splat by its
// bone and then by its instance's transform. Where Unity reads StructuredBuffers in the vertex shader,
// this reads float textures with texelFetch, which the Compatibility renderer (and WebGL 2) can do.

// 16 floats a splat in 4 texels, row after row:
//   (x, y, z, density) (c00, c01, c02, packed colour) (c11, c12, c22, kind) (bone, second bone, its weight, instance)
// A splat of a wardrobe carries more in two of those. Its last float is its instance plus 4096 times
// (its piece + 1), so 0 there is a splat of no piece. And where its colour is one of a colour region's,
// the packed colour is -(1 + that colour's palette index).
uniform sampler2D splats : filter_nearest, repeat_disable;
// 16 floats an instance in 4 texels, one instance a row: its 3x4 object-to-world by rows, then
//   (first bone, first ramp, depth bias in metres, 1 if it casts a floor shadow)
uniform sampler2D instances : filter_nearest, repeat_disable;
// 12 floats a bone in 3 texels: every instance's bones for this frame, end to end
uniform sampler2D bones : filter_nearest, repeat_disable;
// What each instance wears, one instance a row. Texel n: x is 1 when the instance shows its piece n,
// y is its palette's colour n, packed. Only wardrobe splats read it.
uniform sampler2D looks : filter_nearest, repeat_disable;
uniform int splats_width = 1024; // texels in a row of the splat texture: a multiple of 4
uniform int bones_width = 768;   // texels in a row of the bone texture: a multiple of 3

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

// A splat where it stands in the world this frame. False for one that is not drawn: a soft splat (the
// renderer draws only solid ones), a hidden part (ink-studio parks it at y = -99), or a splat of a
// wardrobe piece its instance does not wear.
//   at: its centre. carry: what took its own space to the world's (its bone, then its instance), for
//   its covariance and its normal. colour_packed: its colour. of_instance: its instance's last texel.
bool pose_splat(int splat, out vec3 at, out mat3 cov, out mat3 carry, out float colour_packed, out vec4 of_instance) {
	at = vec3(0.0);
	cov = mat3(0.0);
	carry = mat3(1.0);
	colour_packed = 0.0;
	of_instance = vec4(0.0);
	vec4 s0 = splat_texel(splat, 0);
	if (s0.w < 1.0) {
		return false;
	}
	vec4 s1 = splat_texel(splat, 1);
	vec4 s2 = splat_texel(splat, 2);
	vec4 s3 = splat_texel(splat, 3);
	vec3 p = s0.xyz;
	cov = mat3(vec3(s1.x, s1.y, s1.z), vec3(s1.y, s2.x, s2.y), vec3(s1.z, s2.y, s2.z)); // symmetric
	colour_packed = s1.w;
	int tag = int(s3.w);
	int inst = tag % 4096;
	int piece = tag / 4096; // 0: of no piece
	if (piece > 0 && texelFetch(looks, ivec2(piece - 1, inst), 0).x < 0.5) {
		return false;
	}
	if (colour_packed < 0.0) {
		colour_packed = texelFetch(looks, ivec2(int(-colour_packed) - 1, inst), 0).y;
	}
	vec4 i0 = texelFetch(instances, ivec2(0, inst), 0);
	vec4 i1 = texelFetch(instances, ivec2(1, inst), 0);
	vec4 i2 = texelFetch(instances, ivec2(2, inst), 0);
	of_instance = texelFetch(instances, ivec2(3, inst), 0);
	bool shown = true;

	if (int(round(s2.w)) % 16 == 12) {
		int first = int(of_instance.x);
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
			shown = false;
		}
		p = posed;
		carry = m;
	}

	mat3 world = by_rows(i0.xyz, i1.xyz, i2.xyz);
	at = world * p + vec3(i0.w, i1.w, i2.w);
	carry = world * carry;
	cov = carry * cov * transpose(carry);
	return shown;
}
