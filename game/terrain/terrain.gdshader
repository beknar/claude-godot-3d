// Rolling-hills ground: grass that dries out with altitude, dirt on steeper slopes,
// rock on the steepest faces, with low-frequency patches so it doesn't look tiled.
shader_type spatial;

uniform vec3 grass_low : source_color = vec3(0.23, 0.40, 0.16);
uniform vec3 grass_high : source_color = vec3(0.50, 0.56, 0.27);
uniform vec3 dirt : source_color = vec3(0.46, 0.38, 0.25);
uniform vec3 rock : source_color = vec3(0.45, 0.44, 0.42);
uniform float max_height = 140.0;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float patches = value_noise(world_pos.xz * 0.012) * 0.6 + value_noise(world_pos.xz * 0.09) * 0.4;
	float detail = value_noise(world_pos.xz * 0.8);
	float h = clamp(world_pos.y / max_height, 0.0, 1.0);
	float slope = 1.0 - normalize(world_normal).y;

	vec3 col = mix(grass_low, grass_high, smoothstep(0.15, 0.8, h + (patches - 0.5) * 0.35));
	col = mix(col, dirt, smoothstep(0.10, 0.22, slope + (patches - 0.5) * 0.08) * 0.8);
	col = mix(col, rock, smoothstep(0.28, 0.42, slope));
	col *= 0.88 + detail * 0.2;

	ALBEDO = col;
	ROUGHNESS = 0.95;
}
