// Additive engine trail: bright at the nozzle, fading out along the cone and at grazing angles.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.30, 0.55, 1.0);
uniform float intensity = 2.5;
uniform bool flip = false;

void fragment() {
	float t = flip ? 1.0 - UV.y : UV.y;
	float a = pow(t, 2.2) * pow(abs(dot(NORMAL, VIEW)), 1.5);
	ALBEDO = color * intensity * a;
	ALPHA = a;
}
