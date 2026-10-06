// Concrete sidewalk slabs (world-space 1.5 m grid) with a lighter granite kerb along
// the road edge. The road edge is at |z| = kerb_z.
shader_type spatial;

uniform vec3 concrete : source_color = vec3(0.52, 0.51, 0.49);
uniform vec3 kerb : source_color = vec3(0.62, 0.62, 0.6);
uniform float slab = 1.5;
uniform float kerb_z = 6.0;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 cell = floor(p / slab);
	vec2 f = fract(p / slab);
	float aa = fwidth(p.x / slab) * 1.5;
	float joint = 1.0 - smoothstep(0.0, 0.02 + aa, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
	vec3 col = concrete * (0.88 + 0.18 * hash(cell)) * (1.0 - 0.35 * joint);
	float is_kerb = 1.0 - smoothstep(0.3, 0.32, abs(world_pos.z) - kerb_z);
	// The kerb's vertical face, too.
	is_kerb = max(is_kerb, step(0.5, abs(world_normal.z)) * step(abs(abs(world_pos.z) - kerb_z), 0.05));
	col = mix(col, kerb * (0.9 + 0.1 * hash(floor(p * 2.0))), is_kerb);
	ALBEDO = col;
	ROUGHNESS = 0.85;
}
