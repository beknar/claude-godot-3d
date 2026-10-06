// Asphalt street with painted markings, laid out in world space so road segments
// line up: the street runs along X centred on z = 0. Double yellow centre line, white
// lines between the driving and parking lanes, parking-stall ticks, and a zebra
// crossing around x = crosswalk_x.
shader_type spatial;

uniform vec3 asphalt : source_color = vec3(0.13, 0.13, 0.14);
uniform vec3 paint_white : source_color = vec3(0.85, 0.85, 0.82);
uniform vec3 paint_yellow : source_color = vec3(0.86, 0.68, 0.18);
/// Half the width of one driving lane, metres (the centre line sits at z = 0).
uniform float lane_width = 3.5;
uniform float stall_length = 6.0;
uniform float crosswalk_x = 0.0;
uniform float crosswalk_half_width = 2.5;
/// Half-width of the whole road (kerb to kerb).
uniform float road_half_width = 6.0;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float band(float x, float center, float half_width) {
	float aa = fwidth(x) * 0.75;
	return 1.0 - smoothstep(half_width - aa, half_width + aa, abs(x - center));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float grain = noise(p * 3.0) * 0.5 + noise(p * 17.0) * 0.5;
	float patch = smoothstep(0.55, 0.75, noise(p * 0.15));
	vec3 col = asphalt * (0.8 + 0.35 * grain) * mix(1.0, 0.8, patch);

	float z = p.y;
	float yellow = band(z, 0.12, 0.06) + band(z, -0.12, 0.06);
	// White line between the driving and parking lanes, and stall ticks in the parking lanes.
	float edge = band(abs(z), lane_width, 0.06);
	float in_parking = step(lane_width, abs(z)) * step(abs(z), road_half_width - 0.2);
	float tick = band(fract(p.x / stall_length + 0.5) - 0.5, 0.0, 0.08 / stall_length) * in_parking;
	// Zebra crossing: bars across the road, interrupting the other markings.
	float in_cross = band(p.x, crosswalk_x, crosswalk_half_width);
	float zebra = in_cross * band(fract(z / 1.2) - 0.5, 0.0, 0.25) * step(abs(z), road_half_width - 0.3);
	float wear = 0.75 + 0.25 * noise(p * 6.0);
	col = mix(col, paint_yellow * wear, clamp(yellow, 0.0, 1.0) * (1.0 - in_cross));
	col = mix(col, paint_white * wear, clamp(edge + tick, 0.0, 1.0) * (1.0 - in_cross));
	col = mix(col, paint_white * wear, zebra);

	ALBEDO = col;
	ROUGHNESS = mix(0.9, 0.6, clamp(yellow + edge + zebra, 0.0, 1.0));
	SPECULAR = 0.3;
}
