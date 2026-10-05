// Deep-navy space backdrop with procedural stars.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.02, 0.05, 0.16);
uniform vec3 horizon_color : source_color = vec3(0.05, 0.10, 0.27);
uniform float star_threshold : hint_range(0.9, 1.0) = 0.982;
uniform float star_brightness = 1.6;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float star_layer(vec3 dir, float scale, float threshold) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	vec3 f = fract(p) - 0.5;
	float h = hash3(cell);
	if (h < threshold) {
		return 0.0;
	}
	vec3 offset = vec3(hash3(cell + 1.3), hash3(cell + 2.7), hash3(cell + 5.1)) - 0.5;
	float dist = length(f - offset * 0.6);
	return smoothstep(0.14, 0.0, dist) * (0.4 + 0.6 * hash3(cell + 9.1));
}

void sky() {
	vec3 col = mix(horizon_color, top_color, smoothstep(-0.7, 0.9, EYEDIR.y));
	float stars = star_layer(EYEDIR, 240.0, star_threshold) + star_layer(EYEDIR, 130.0, star_threshold + 0.008);
	COLOR = col + vec3(0.85, 0.9, 1.0) * stars * star_brightness;
}
