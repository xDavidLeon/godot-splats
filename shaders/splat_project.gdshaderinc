// What the draw pass and the tints' pass share: the camera, where a posed splat's quad lies in the
// picture, and which of its fragments are kept. Both passes must put a splat at the same pixels and
// the same depth, so both work it out here. Ported from a Unity shader of the same design, which
// ports the projection of ink-studio's cli/render.js (MIT, Shapeshift Labs).

#include "splat_pose.gdshaderinc"

uniform mat4 view;               // world -> camera view (right-handed, looking down -z)
uniform vec2 size;               // target width, height in pixels
uniform vec4 lens;               // x: pixels per metre (orthographic) or focal length in pixels (perspective); y: 1 if orthographic; z: near; w: far

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

// A corner of a splat's quad in clip space, for a splat that pose_splat placed. False for one that is
// behind the camera or has no size on screen.
//   depth_bias: metres nearer the camera it is depth-tested than it is (its instance's).
//   from_centre: the corner, in pixels from the splat's centre. inverse: the inverse of its screen
//   covariance. at_pixel: the corner in the target, counted from the bottom left.
bool project_splat(vec3 at, mat3 cov, float depth_bias, vec2 corner, out vec4 position, out vec2 from_centre, out vec3 inverse, out vec2 at_pixel) {
	position = vec4(2.0, 2.0, 2.0, 1.0); // outside the clip volume: dropped
	from_centre = vec2(0.0);
	inverse = vec3(0.0);
	at_pixel = vec2(0.0);
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
	if (-v.z < lens.z || det <= 0.0) {
		return false;
	}
	inverse = vec3(C / det, -B / det, A / det);
	// The cut-out keeps exp(power) >= 0.5, which ends 1.18 standard deviations out; the quad need go no
	// further (ink-studio's blended dabs reach 3). A pixel is added for the edge.
	vec2 extent = vec2(min(1.2 * sqrt(A) + 1.0, 2048.0), min(1.2 * sqrt(C) + 1.0, 2048.0));
	from_centre = corner * extent;
	at_pixel = pixel_of(v) + from_centre;
	// a thin thing lying on a surface is tested a little nearer than it is (the instance's depth bias)
	position = clip_of(at_pixel, vec3(v.xy, v.z + depth_bias));
	return true;
}

// Whether a fragment lies outside its splat: solid splats are cut out at half their Gaussian.
bool outside_splat(vec2 d, vec3 inverse) {
	float power = -0.5 * (inverse.x * d.x * d.x + inverse.z * d.y * d.y) - inverse.y * d.x * d.y;
	return power + 0.693147 < 0.0; // exp(power) >= 0.5: the middle of ink-studio's hard edge
}

// A tinted instance is drawn on every other art pixel, so what is behind it shows on the others. The
// target is twice the art resolution, and the art's rows are counted from the top.
bool tint_skipped(vec2 at_pixel) {
	ivec2 art = ivec2(floor(vec2(at_pixel.x, size.y - at_pixel.y))) >> 1;
	return ((art.x + art.y) & 1) != 0;
}
