// Hair locks: blue-black with fine strands and the bright "angel ring" highlight of
// anime hair. UV.x runs across a lock and UV.y from root (0) to tip (1).
shader_type spatial;

uniform vec3 hair_color : source_color = vec3(0.045, 0.05, 0.07);
uniform vec3 tip_color : source_color = vec3(0.07, 0.10, 0.14);
uniform vec3 sheen_color : source_color = vec3(0.42, 0.55, 0.68);
/// Strands across each lock.
uniform float strand_count = 7.0;

group_uniforms cel_shading;
uniform float cel_threshold : hint_range(-0.5, 0.5) = 0.05;
uniform float cel_softness : hint_range(0.0, 0.3) = 0.03;
uniform float cel_light_scale = 0.3;
/// Highlight band: how tightly it follows the light, and its brightness.
uniform float sheen_sharpness : hint_range(0.5, 0.999) = 0.95;
uniform float sheen_strength = 0.45;
group_uniforms;

varying float along;

void vertex() {
	along = UV.y;
}

void fragment() {
	float strands = 0.5 + 0.5 * sin(UV.x * 6.2832 * strand_count + 3.0 * sin(UV.y * 9.0));
	ALBEDO = mix(hair_color, tip_color, smoothstep(0.3, 1.0, UV.y)) * (0.75 + 0.5 * strands);
	ROUGHNESS = 0.6;
	// Fine strand grooves as bump.
	NORMAL = normalize(NORMAL + 0.15 * (strands - 0.5) * cross(NORMAL, vec3(0.0, 1.0, 0.0)));
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(cel_threshold - cel_softness, cel_threshold + cel_softness, ndl);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * lit * cel_light_scale;
	// A hard-edged highlight band, kept to the upper half of each lock.
	vec3 h = normalize(LIGHT + VIEW);
	float band = smoothstep(sheen_sharpness, sheen_sharpness + 0.015, dot(NORMAL, h));
	band *= 1.0 - smoothstep(0.25, 0.55, along);
	SPECULAR_LIGHT += sheen_color * LIGHT_COLOR * ATTENUATION * band * sheen_strength * lit;
}
