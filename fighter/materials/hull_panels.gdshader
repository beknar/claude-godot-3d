// Hull plating from a painted panel texture (tools/generate_textures.py), projected
// in object space from three directions so it needs no UVs. The texture is a packed
// mask map -- R inset plates, G ink linework, B tone/decals, A height -- and the
// colours come from uniforms, so liveries can repaint it. Height drives bump
// mapping, and surface features (detail_lib) layer on top.
shader_type spatial;

// Cel lighting and surface features from the shared include.
#define CEL_SHADING
#define DETAIL_FEATURES
#include "res://fighter/materials/detail_lib.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.77, 0.80, 0.77);
uniform vec3 plate_dark : source_color = vec3(0.50, 0.55, 0.57);
uniform vec3 line_color : source_color = vec3(0.07, 0.08, 0.10);
uniform vec3 marking_color : source_color = vec3(0.85, 0.42, 0.40);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.6;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.3;

group_uniforms panel_texture;
/// Packed panel mask map: R inset, G ink, B tone (> 0.9 = decal), A height.
uniform sampler2D panel_map : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
/// Metres of hull covered by one repeat of the panel texture.
uniform float tile_size = 6.0;
/// How strongly the ink linework shows (0 hides it, e.g. for a clean livery).
uniform float ink_strength : hint_range(0.0, 1.0) = 1.0;
group_uniforms;

group_uniforms relief;
/// Full height range of the texture's relief, in metres.
uniform float relief_depth = 0.05;
uniform float bump_strength = 1.0;
group_uniforms;

varying vec3 obj_pos;
varying vec3 obj_normal;

// Object-space triplanar sample. Every projection puts the texture's U along the
// part's length (Z) where it can, so plates run fore-aft on the top and the sides.
vec4 sample_panels(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(6.0));
	w /= (w.x + w.y + w.z);
	vec3 q = p / tile_size;
	return texture(panel_map, q.zy) * w.x
			+ texture(panel_map, q.zx) * w.y
			+ texture(panel_map, q.xy) * w.z;
}

void vertex() {
	obj_pos = VERTEX;
	obj_normal = NORMAL;
}

void fragment() {
	vec4 panels = sample_panels(obj_pos, normalize(obj_normal));
	float inset = panels.r;
	float ink = panels.g * ink_strength;
	float tone = panels.b;
	float decal = smoothstep(0.88, 0.95, tone);

	vec3 col = mix(base_color, plate_dark, inset) * (0.82 + 0.26 * clamp(tone / 0.8, 0.0, 1.0));
	col = mix(col, marking_color, decal);
	col = mix(col, line_color, ink);
	float height = (panels.a - 0.5) * relief_depth;
	float roughness = mix(roughness_value, 0.85, ink);

	apply_features(obj_pos, col, height, roughness);

	ALBEDO = col;
	ROUGHNESS = roughness;
	METALLIC = metallic_value;
	NORMAL = bump_normal(NORMAL, VERTEX, height * bump_strength);
}
