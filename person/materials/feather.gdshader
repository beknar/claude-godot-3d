// Mechanical wing feathers on flat cards. tools/generate_person_textures.py paints
// four feathers side by side (R ink, G barb tone, B height, A coverage); each card's
// UV picks one of them, with UV.y running from the root (0) to the tip (1).
shader_type spatial;
render_mode cull_disabled;

#define CEL_SHADING
#include "res://fighter/materials/detail_lib.gdshaderinc"

uniform sampler2D feather_map : hint_default_black, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 root_color : source_color = vec3(0.05, 0.06, 0.08);
uniform vec3 tip_color : source_color = vec3(0.20, 0.36, 0.40);
uniform vec3 ink_color : source_color = vec3(0.02, 0.02, 0.03);
uniform float relief_depth = 0.004;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
uniform vec3 rim_color : source_color = vec3(0.35, 0.62, 0.68);
uniform float rim_strength = 0.25;

void fragment() {
	vec4 f = texture(feather_map, UV);
	float ink = f.r;
	float tone = f.g;
	vec3 col = mix(root_color, tip_color, smoothstep(0.05, 1.0, UV.y)) * (0.6 + 0.8 * tone);
	col = mix(col, ink_color, ink);
	ALBEDO = col;
	ALPHA = f.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.45;
	METALLIC = 0.3;
	NORMAL = bump_normal(NORMAL, VERTEX, (f.b - 0.5) * relief_depth);
	float facing = abs(dot(NORMAL, VIEW));
	EMISSION = rim_color * rim_strength * pow(1.0 - facing, 3.0) * (1.0 - ink);
}
