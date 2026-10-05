// Engine nacelle skin for a cylinder whose axis is its local Y. A painted panel
// texture (same packed layout as the hull's) wraps once around the nacelle, and
// circumferential trim bands are overlaid as colour plus bump relief.
shader_type spatial;

// Cel lighting from the shared include.
#define CEL_SHADING
#include "res://fighter/materials/detail_lib.gdshaderinc"

uniform vec3 body_color : source_color = vec3(0.77, 0.80, 0.77);
uniform vec3 inset_color : source_color = vec3(0.50, 0.55, 0.57);
uniform vec3 band_color : source_color = vec3(0.35, 0.38, 0.41);
uniform vec3 line_color : source_color = vec3(0.07, 0.08, 0.10);
uniform vec3 marking_color : source_color = vec3(0.95, 0.55, 0.15);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.6;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.3;

group_uniforms panel_texture;
/// Packed panel mask map: R inset, G ink, B tone (> 0.9 = decal), A height.
uniform sampler2D panel_map : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
/// Metres of nacelle length covered by one repeat of the texture's V axis.
uniform float tile_length = 2.7;
group_uniforms;

/// Up to four trim bands: x = start, y = end (local Y, metres), z = relief (metres, + raised).
uniform vec4 bands[4];
uniform int band_count = 0;
uniform float relief_depth = 0.05;
uniform float groove_depth = 0.012;
uniform float bump_strength = 1.0;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	float y = obj_pos.y;
	float turn = atan(obj_pos.z, obj_pos.x) / TAU;
	vec2 uv = vec2(turn + 0.5, y / tile_length + 0.5);
	// The wrap-around seam makes the derivative of U jump; take gradients from a
	// copy whose seam sits on the opposite side so mip selection stays smooth.
	vec2 uv_alt = vec2(fract(turn + 1.0), uv.y);
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec2 dx_alt = dFdx(uv_alt);
	vec2 dy_alt = dFdy(uv_alt);
	if (dot(dx_alt, dx_alt) + dot(dy_alt, dy_alt) < dot(dx, dx) + dot(dy, dy)) {
		dx = dx_alt;
		dy = dy_alt;
	}
	vec4 panels = textureGrad(panel_map, uv, dx, dy);

	float decal = smoothstep(0.88, 0.95, panels.b);
	vec3 col = mix(body_color, inset_color, panels.r) * (0.82 + 0.26 * clamp(panels.b / 0.8, 0.0, 1.0));
	col = mix(col, marking_color, decal);
	float line = panels.g;
	float height = (panels.a - 0.5) * relief_depth;

	for (int i = 0; i < 4; i++) {
		if (i >= band_count) {
			break;
		}
		float edge = min(y - bands[i].x, bands[i].y - y); // > 0 inside the band
		float cover = smoothstep(-0.003, 0.003, edge);
		col = mix(col, band_color, cover);
		height = mix(height, bands[i].z * smoothstep(0.0, 0.03, edge), cover);
		line = max(line, 1.0 - smoothstep(0.008, 0.018, abs(edge)));
		height -= groove_depth * (1.0 - smoothstep(0.0, 0.04, abs(edge)));
	}

	col = mix(col, line_color, line);
	ALBEDO = col;
	ROUGHNESS = mix(roughness_value, 0.85, line);
	METALLIC = metallic_value;
	NORMAL = bump_normal(NORMAL, VERTEX, height * bump_strength);
}
