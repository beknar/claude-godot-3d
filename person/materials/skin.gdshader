// Skin with a painted anime-style face. tools/build_person.gd gives every head vertex
// UV = its rest-pose head-local (x, y) in metres (x toward the character's left is
// negative) and UV2.x = its head-local z (negative = front), so the features are
// drawn analytically in metres and stay sharp at any distance. Only the front of the
// head gets features.
shader_type spatial;

#define CEL_SHADING
#include "res://fighter/materials/detail_lib.gdshaderinc"

uniform vec3 skin_color : source_color = vec3(0.86, 0.74, 0.69);
uniform vec3 blush_color : source_color = vec3(0.93, 0.6, 0.6);
uniform float blush_strength : hint_range(0.0, 1.0) = 0.25;

group_uniforms eyes;
uniform vec3 sclera_color : source_color = vec3(0.95, 0.96, 0.97);
uniform vec3 iris_color : source_color = vec3(0.30, 0.86, 0.56);
uniform vec3 iris_dark : source_color = vec3(0.04, 0.30, 0.20);
uniform vec3 lash_color : source_color = vec3(0.03, 0.03, 0.05);
/// Self-illumination of the irises (the reference's eyes glow faintly).
uniform float iris_glow = 0.8;
/// Eye centre (x = distance from the face's midline, y = height), metres.
uniform vec2 eye_center = vec2(0.031, -0.004);
/// Half width and half height of the eye opening, metres.
uniform vec2 eye_size = vec2(0.0185, 0.0105);
uniform float iris_radius = 0.0098;
group_uniforms;

group_uniforms mouth;
uniform vec3 lip_color : source_color = vec3(0.80, 0.47, 0.48);
uniform float mouth_y = -0.056;
uniform float mouth_width = 0.0125;
group_uniforms;

// Signed distance to an ellipse-ish shape (negative inside), in metres.
float ellipse_sd(vec2 p, vec2 r) {
	float k = length(p / r);
	return (k - 1.0) * min(r.x, r.y);
}

// Anti-aliased coverage of a signed distance field.
float fill(float sd) {
	float aa = max(fwidth(sd), 1e-5);
	return 1.0 - smoothstep(-aa, aa, sd);
}

// Anti-aliased line of half-width `w` along the zero set of `sd`.
float stroke(float sd, float w) {
	return fill(abs(sd) - w);
}

void fragment() {
	vec2 p = UV;
	float front = smoothstep(-0.035, -0.06, UV2.x);
	vec2 q = vec2(abs(p.x), p.y);            // mirrored to one side of the face

	vec3 col = skin_color;
	float glow = 0.0;

	// Cheek blush.
	float blush = 1.0 - smoothstep(0.0, 1.0, length((q - vec2(0.047, -0.03)) / vec2(0.016, 0.009)));
	col = mix(col, blush_color, blush * blush_strength * front);

	// Eye: almond opening tilted up toward the outer corner.
	vec2 e = q - eye_center;
	e.y -= 0.12 * e.x;
	float upper = eye_size.y * (1.0 - pow(abs(e.x) / eye_size.x, 2.2));
	float lower = -eye_size.y * 0.75 * (1.0 - pow(abs(e.x) / eye_size.x, 1.6));
	float inside_x = abs(e.x) - eye_size.x;
	float eye_sd = max(inside_x, max(e.y - upper, lower - e.y));
	float eye = fill(eye_sd) * front;

	// Iris (sits high, its top hidden under the lid), pupil and highlights.
	vec2 ic = e - vec2(0.0, 0.0012);
	float ir = length(ic);
	float iris = fill(ir - iris_radius);
	float iris_shade = smoothstep(-iris_radius, iris_radius, ic.y);   // darker toward the top
	vec3 iris_col = mix(iris_color, iris_dark, 0.15 + 0.6 * iris_shade);
	iris_col = mix(iris_col, iris_dark, stroke(ir - iris_radius * 0.92, iris_radius * 0.09));
	iris_col = mix(iris_col, vec3(0.02, 0.05, 0.04), fill(ir - iris_radius * 0.38));
	float spark = fill(length(ic - vec2(-0.0035, 0.0035)) - 0.0024)
			+ fill(length(ic - vec2(0.004, -0.004)) - 0.0011);
	vec3 eye_col = mix(sclera_color, iris_col, iris);
	eye_col = mix(eye_col, vec3(1.0), clamp(spark, 0.0, 1.0));
	col = mix(col, eye_col, eye);
	glow += eye * iris * (1.0 - clamp(spark, 0.0, 1.0)) * iris_glow;

	// Thick upper lash line with an outer flick, thin partial lower line, lid crease.
	float lash_w = 0.0016 + 0.0009 * smoothstep(-eye_size.x, eye_size.x, e.x);
	float lash = stroke(e.y - upper, lash_w) * step(abs(e.x), eye_size.x * 1.02);
	vec2 flick = e - vec2(eye_size.x, 0.0);
	lash = max(lash, fill(ellipse_sd(flick - vec2(0.0025, 0.0015), vec2(0.004, 0.0012))));
	float lower_line = stroke(e.y - lower, 0.0005) * smoothstep(-0.2, 0.6, e.x / eye_size.x);
	float crease = stroke(e.y - upper - 0.0045 - 0.0015 * (1.0 - pow(e.x / eye_size.x, 2.0)), 0.00045)
			* step(abs(e.x + 0.002), eye_size.x * 0.85);
	col = mix(col, lash_color, max(lash, max(lower_line, crease * 0.7)) * front);

	// Brows: thin, slightly arched.
	float bx = q.x - 0.033;
	float brow_y = 0.022 + 0.004 * (1.0 - pow(bx / 0.019, 2.0));
	float brow = stroke(q.y - brow_y, 0.0011 * (1.0 - smoothstep(0.0, 0.02, bx))) * step(abs(bx), 0.019);
	col = mix(col, lash_color * 1.5, brow * front);

	// Nose: a small shadow tick, and the mouth.
	float nose = fill(ellipse_sd(p - vec2(0.003, -0.03), vec2(0.0022, 0.0011)));
	col = mix(col, skin_color * 0.72, nose * front);
	vec2 m = p - vec2(0.0, mouth_y);
	float lip = fill(ellipse_sd(m - vec2(0.0, -0.0028), vec2(mouth_width * 0.72, 0.0034)));
	float mouth_line = stroke(m.y - 0.0012 * (1.0 - pow(m.x / mouth_width, 2.0)), 0.00055)
			* step(abs(m.x), mouth_width);
	col = mix(col, lip_color, lip * front * 0.8);
	col = mix(col, vec3(0.35, 0.16, 0.17), mouth_line * front);

	ALBEDO = col;
	ROUGHNESS = 0.7;
	EMISSION = iris_color * glow * 0.6;
}
