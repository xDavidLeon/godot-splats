// Where things darken the floor: every splat of an instance that casts a shadow is carried down the
// sun's ray to the floor and marks the cell it lands in. The target is the floor's grid seen from
// above, one texel a cell; splat_shadow.gdshader reads it. The rule is SplatLight.shadow_cells
// (splat_light.gd), which a Unity renderer of the same design ran on the CPU whenever the scene's
// contents changed. Here it runs every frame on the GPU, with the splats posed as they are drawn,
// so a shadow follows the thing that moves and the clip that plays.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled, depth_test_disabled;

#include "splat_pose.gdshaderinc"

uniform vec2 slope;       // the sun's x and z over its y: how far a shadow falls for each metre of height
uniform vec4 grid;        // x: a cell in metres; y: the floor's height; z: lower than this above the floor casts nothing; w: cells across the target
uniform vec2 first_cell;  // the cell at the target's first texel

void vertex() {
	POSITION = vec4(2.0, 2.0, 2.0, 1.0); // outside the clip volume: dropped
	vec3 at;
	mat3 cov;
	mat3 carry;
	float pk;
	vec4 of_instance;
	if (pose_splat(INSTANCE_ID, at, cov, carry, pk, of_instance) && of_instance.w > 0.5) {
		float height = at.y - grid.y;
		if (height >= grid.z) {
			vec2 cell = floor((at.xz - slope * height) / grid.x) - first_cell;
			if (cell.x >= 0.0 && cell.y >= 0.0 && cell.x < grid.w && cell.y < grid.w) {
				// A quad a little larger than its texel covers that texel's centre and no other's. Clip space y
				// points down in a viewport, so a row counted from the top is written as it is.
				POSITION = vec4((cell + 0.5 + VERTEX.xy * 0.6) / grid.w * 2.0 - 1.0, 0.5, 1.0);
			}
		}
	}
}

void fragment() {
	ALBEDO = vec3(1.0);
}
