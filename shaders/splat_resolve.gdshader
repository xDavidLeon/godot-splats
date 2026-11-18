// The pixel look. Each art pixel reads the 2x2 samples under it. Inside a shape it takes the palette
// colour nearest their average, with an ordered dither; on the outside of a silhouette it takes the
// colour most of its samples vote for, inked darker. Ported from a Unity shader of the same
// design, which ports ink-studio's src/pixel-look.js (MIT, Shapeshift Labs) with one
// change: the silhouette is not blended toward the background colour by coverage. A pixel is either
// covered (alpha 1) or not (alpha 0).
// A second mode, not in the Unity shader: with average_interior off, the inside takes the voted
// colour too. An average of two tones can be nearest a palette colour that is in neither, which shows
// as stray pixels (dark red and blue-grey in dark hair); the vote has none, and no dither, and looks
// flatter. The average is the default.
// Not ported: the edit marks (samples with alpha 0.5).
// Drawn on a rectangle that fills a viewport of the art's size.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D samples : filter_nearest, repeat_disable; // twice the art resolution: rgb, coverage in alpha
uniform vec3 pal[128];                                       // sRGB, 0..1; index 0 is the background
uniform int pal_count = 1;
uniform bool average_interior = true;  // inside a shape: the palette colour nearest the samples' average, or the vote
uniform float dither = 0.021;          // only with average_interior: ordered noise added to the average

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

const float COVERED_ABOVE = 0.02;
const vec3 WEIGHTS = vec3(0.30, 0.55, 0.15);

int nearest(vec3 c, bool solid) {
	int best = solid && pal_count > 1 ? 1 : 0;
	float best_distance = 1e9;
	for (int i = 0; i < 128; i++) {
		if (i >= pal_count) {
			break;
		}
		if (solid && i == 0 && pal_count > 1) {
			continue;
		}
		vec3 df = c - pal[i];
		float distance = dot(df * df, WEIGHTS);
		if (distance < best_distance) {
			best_distance = distance;
			best = i;
		}
	}
	return best;
}

ivec2 clamped(ivec2 p) {
	return clamp(p, ivec2(0), textureSize(samples, 0) - 1);
}

// whether any of an art pixel's four samples is covered
bool covered(ivec2 p) {
	for (int i = 0; i < 4; i++) {
		if (texelFetch(samples, clamped(p * 2 + ivec2(i & 1, i >> 1)), 0).a > COVERED_ABOVE) {
			return true;
		}
	}
	return false;
}

void fragment() {
	ivec2 art = textureSize(samples, 0) / 2;
	ivec2 p = clamp(ivec2(floor(UV * vec2(art))), ivec2(0), art - 1); // row 0 is the top of the picture
	int labels[4];
	bool solid[4];
	float coverage = 0.0;
	vec3 native = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		vec4 s = texelFetch(samples, clamped(p * 2 + ivec2(i & 1, i >> 1)), 0);
		solid[i] = s.a > COVERED_ABOVE;
		labels[i] = nearest(s.rgb, solid[i]);
		native += s.rgb * 0.25;
		if (solid[i]) {
			coverage += 0.25;
		}
	}
	if (coverage <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		// the colour most covered samples vote for. With the vote look a tie goes to the one nearest the
		// samples' average (the first one read left specks on fringes at room scale); with the average
		// look it goes to the first one read, which only the silhouette uses. Both as the Unity shader.
		int best = 0;
		int score = 0;
		float best_distance = 1e9;
		for (int k = 0; k < 4; k++) {
			if (!solid[k]) {
				continue;
			}
			int n = 0;
			for (int j = 0; j < 4; j++) {
				if (solid[j] && labels[j] == labels[k]) {
					n++;
				}
			}
			vec3 df = native - pal[labels[k]];
			float distance = dot(df * df, WEIGHTS);
			if (n > score || (!average_interior && n == score && distance < best_distance)) {
				best = labels[k];
				score = n;
				best_distance = distance;
			}
		}
		bool outer = coverage < 1.0 || !covered(p - ivec2(1, 0)) || !covered(p + ivec2(1, 0)) || !covered(p - ivec2(0, 1)) || !covered(p + ivec2(0, 1));
		vec3 c = pal[best];
		if (average_interior) {
			// ink-studio counts the dither's rows from the bottom of the picture
			int up = art.y - 1 - p.y;
			float noise = ((BAYER[(p.x & 3) + ((up & 3) << 2)] + 0.5) / 16.0 - 0.5) * dither;
			c = pal[nearest(clamp(native + noise, 0.0, 1.0), false)];
		}
		if (outer) {
			vec3 body = pal[best];
			vec3 tone = body * 0.64;
			tone = min(vec3(1.0), tone * max(1.0, 0.12 / max(dot(tone, WEIGHTS), 0.001)));
			c = mix(body, tone, 0.65); // ink-studio blends this toward the background by coverage; this keeps alpha binary
		}
		COLOR = vec4(c, 1.0);
	}
}
