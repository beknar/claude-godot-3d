// Building facades from world position: floors of windows (a random share lit warm
// for the evening), a glowing storefront band at street level, and a dark roof.
// Works on any axis-aligned box, so buildings need no UVs.
shader_type spatial;

uniform vec3 wall_color : source_color = vec3(0.45, 0.4, 0.36);
uniform vec3 trim_color : source_color = vec3(0.3, 0.28, 0.26);
uniform vec3 glass_color : source_color = vec3(0.07, 0.09, 0.12);
uniform vec3 window_light : source_color = vec3(1.0, 0.78, 0.5);
uniform vec3 shop_light : source_color = vec3(1.0, 0.86, 0.62);
uniform float lit_fraction : hint_range(0.0, 1.0) = 0.35;
uniform float window_energy = 1.6;
uniform float floor_height = 3.2;
uniform float bay_width = 2.8;
uniform float ground_floor = 4.2;
uniform float seed = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.17) * 43758.5453);
}

float box(vec2 f, vec2 half_size) {
	vec2 aa = fwidth(f) * 0.75;
	vec2 d = smoothstep(half_size + aa, half_size - aa, abs(f - 0.5));
	return d.x * d.y;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = world_normal;
	if (n.y > 0.7) {
		ALBEDO = vec3(0.12, 0.12, 0.13);
		ROUGHNESS = 0.95;
	} else {
		// Horizontal coordinate along this face.
		float u = abs(n.x) > abs(n.z) ? world_pos.z : world_pos.x;
		float y = world_pos.y;
		vec3 col = wall_color;
		vec3 glow = vec3(0.0);
		float rough = 0.85;
		if (y < ground_floor) {
			// Storefront: a long glass band over a low base, lit from inside.
			float glass = smoothstep(0.45, 0.5, y) * (1.0 - smoothstep(ground_floor - 0.75, ground_floor - 0.7, y));
			float mullion = 1.0 - box(vec2(fract(u / 3.6), 0.5), vec2(0.47, 1.0));
			glass *= 1.0 - mullion;
			col = mix(trim_color, glass_color, glass);
			glow = shop_light * glass * step(0.25, hash(vec2(floor(u / 7.2), 7.0))) * 0.9;
			rough = mix(0.8, 0.15, glass);
		} else {
			vec2 cell = vec2(u / bay_width, (y - ground_floor) / floor_height);
			vec2 f = fract(cell);
			float win = box(f, vec2(0.28, 0.32));
			float sill = box(f - vec2(0.0, -0.18), vec2(0.33, 0.035));
			float lit = step(1.0 - lit_fraction, hash(floor(cell)));
			col = mix(col, trim_color, sill);
			col = mix(col, glass_color, win);
			glow = window_light * win * lit * (0.6 + 0.4 * hash(floor(cell) + 3.1));
			rough = mix(rough, 0.2, win);
		}
		ALBEDO = col;
		ROUGHNESS = rough;
		EMISSION = glow * window_energy;
	}
}
