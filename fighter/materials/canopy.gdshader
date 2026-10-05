// Tinted cockpit glass. Frame bars are surface features (raised, metal-coloured)
// instead of separate meshes.
shader_type spatial;

#define DETAIL_FEATURES
#include "res://fighter/materials/detail_lib.gdshaderinc"

uniform vec3 glass_color : source_color = vec3(0.11, 0.14, 0.22);
uniform float glass_metallic : hint_range(0.0, 1.0) = 0.7;
uniform float glass_roughness : hint_range(0.0, 1.0) = 0.15;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.4;
uniform float bump_strength = 1.0;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	vec3 col = glass_color;
	float height = 0.0;
	float roughness = glass_roughness;
	apply_features(obj_pos, col, height, roughness);

	ALBEDO = col;
	ROUGHNESS = roughness;
	METALLIC = glass_metallic;
	RIM = rim_amount;
	RIM_TINT = 0.8;
	NORMAL = bump_normal(NORMAL, VERTEX, height * bump_strength);
}
