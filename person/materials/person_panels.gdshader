// Armour, gunmetal and undersuit for the winged cyborg. The fighter's hull shader
// projects its panel map in object space, which would slide over a skinned mesh as
// it deforms, so this one samples through UVs instead: tools/build_person.gd lays
// every part's UVs out in metres, and `tile_size` sets metres per texture repeat.
// Same packed map as the hull: R inset plates, G ink linework, B tone, A height.
shader_type spatial;

#define CEL_SHADING
#include "res://fighter/materials/detail_lib.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.36, 0.47, 0.57);
uniform vec3 plate_dark : source_color = vec3(0.22, 0.29, 0.36);
uniform vec3 line_color : source_color = vec3(0.04, 0.05, 0.07);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.5;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.2;

group_uniforms panel_texture;
/// Packed panel mask map: R inset, G ink, B tone, A height.
uniform sampler2D panel_map : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
/// Metres of surface covered by one repeat of the panel texture.
uniform float tile_size = 0.5;
/// How strongly the ink linework shows.
uniform float ink_strength : hint_range(0.0, 1.0) = 1.0;
group_uniforms;

group_uniforms relief;
/// Full height range of the texture's relief, in metres.
uniform float relief_depth = 0.006;
uniform float bump_strength = 1.0;
group_uniforms;

group_uniforms sheen;
/// Cool metallic rim glancing off edges, like the illustration's lighting.
uniform vec3 rim_color : source_color = vec3(0.35, 0.62, 0.68);
uniform float rim_strength = 0.0;
uniform float rim_power = 3.0;
/// Flat self-illumination, for glowing parts.
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
group_uniforms;

void fragment() {
	vec4 panels = texture(panel_map, UV / tile_size);
	float inset = panels.r;
	float ink = panels.g * ink_strength;
	float tone = panels.b;

	vec3 col = mix(base_color, plate_dark, inset) * (0.82 + 0.26 * clamp(tone / 0.8, 0.0, 1.0));
	col = mix(col, line_color, ink);
	float height = (panels.a - 0.5) * relief_depth;

	ALBEDO = col;
	ROUGHNESS = mix(roughness_value, 0.85, ink);
	METALLIC = metallic_value;
	NORMAL = bump_normal(NORMAL, VERTEX, height * bump_strength);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	EMISSION = rim_color * rim_strength * pow(1.0 - facing, rim_power) * (1.0 - ink)
			+ emission_color * emission_energy;
}
