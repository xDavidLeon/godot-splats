// Which samples are a tinted instance's: every splat of the scene drawn once more, into a target of
// its own of the samples' size, white where its instance is tinted and black where it is not, with
// depth, so a sample is white only where a tinted splat is the nearest thing. splat_resolve.gdshader
// reads it, and shows the samples it marks as they are, outside the palette and never inked.
// The Unity shader of the same design wrote a tinted splat's colour with an alpha of a half in its
// one draw, and its pixel look knew the sample by that alpha. A Godot spatial shader cannot write a
// colour and an alpha of its own choosing in one draw. Marking the samples afterwards by another
// alpha, as the floor shadows do, was tried: the Mobile renderer keeps two bits of alpha while it
// draws, which a floor shadow's half already uses up, and two tinted splats at one depth marked a
// sample twice. Here nothing depends on what the target can hold: the same quads, placed by the same
// code (splat_project.gdshaderinc), are won by the same splat in both targets.
// Drawn only while an instance is tinted.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

#include "splat_project.gdshaderinc"

varying vec2 offset;  // pixels from the splat's centre
varying vec3 conic;   // the inverse of its screen covariance
varying vec2 pixel;   // where in the target, counted from the bottom left
varying float tinted; // 1 for a splat of a tinted instance

void vertex() {
	POSITION = vec4(2.0, 2.0, 2.0, 1.0); // outside the clip volume: dropped
	offset = vec2(0.0);
	conic = vec3(0.0);
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
			tinted = splat_tint(INSTANCE_ID).w;
		}
	}
}

void fragment() {
	// kept and dropped as splat_scene_draw.gdshader keeps and drops it
	if (outside_splat(offset, conic) || (tinted > 0.5 && tint_skipped(pixel))) {
		discard;
	}
	ALBEDO = vec3(step(0.5, tinted));
}
