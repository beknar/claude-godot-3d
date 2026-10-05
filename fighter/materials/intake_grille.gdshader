// Engine intake for a flat disc in its local XZ plane: a raised outer lip, a ring of
// twisted fan blades and a glowing core, all as colour, emission and bump relief on
// one disc instead of separate ring, grille and core meshes.
shader_type spatial;

#include "res://fighter/materials/detail_lib.gdshaderinc"

uniform vec3 metal_color : source_color = vec3(0.17, 0.18, 0.21);
uniform vec3 grille_color : source_color = vec3(0.07, 0.075, 0.09);
uniform vec3 glow_color : source_color = vec3(1.0, 0.42, 0.08);
uniform float glow_energy = 2.2;
/// Disc radius in object units.
uniform float outer_radius = 0.68;
/// Core radius as a fraction of outer_radius.
uniform float core_fraction = 0.32;
uniform int blade_count = 18;
/// Blade twist: turns of offset from hub to lip.
uniform float blade_twist = 0.35;
uniform float blade_relief = 0.03;
uniform float bump_strength = 1.0;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	float r = length(obj_pos.xz) / outer_radius;
	float angle = atan(obj_pos.z, obj_pos.x);

	float lip = smoothstep(0.84, 0.88, r);
	float core = 1.0 - smoothstep(core_fraction - 0.04, core_fraction + 0.02, r);
	float fan = (1.0 - lip) * (1.0 - core);

	float t = fract(angle / TAU * float(blade_count) + r * blade_twist * float(blade_count) * 0.1);
	float blade = smoothstep(0.08, 0.35, t) * (1.0 - smoothstep(0.55, 0.85, t));

	vec3 col = mix(grille_color, metal_color * 1.2, blade * 0.85);
	col = mix(col, metal_color, lip);
	float height = fan * blade_relief * (blade - 1.0) + lip * 0.02 * smoothstep(0.88, 0.92, r);

	// Hot core, plus a faint glow leaking between the blades near the hub.
	float glow = core * (1.0 - 0.45 * r / core_fraction)
			+ fan * (1.0 - blade) * 0.18 * (1.0 - smoothstep(core_fraction, 0.8, r));
	col = mix(col, glow_color, core);

	ALBEDO = col;
	ROUGHNESS = mix(0.45, 0.3, lip);
	METALLIC = 0.6;
	EMISSION = glow_color * glow_energy * glow;
	NORMAL = bump_normal(NORMAL, VERTEX, height * bump_strength);
}
