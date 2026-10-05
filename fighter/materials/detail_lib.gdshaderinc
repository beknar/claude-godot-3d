// Shared helpers for the fighter's procedural surface detail.

// Bump mapping without tangents or UVs (Mikkelsen 2010, "Bump Mapping
// Unparametrized Surfaces on the GPU"): tilts the shading normal by the
// screen-space gradient of a height field. `height` is in metres along the
// normal; pass the fragment's view-space NORMAL and VERTEX.
vec3 bump_normal(vec3 normal, vec3 view_pos, float height) {
	vec3 dpdx = dFdx(view_pos);
	vec3 dpdy = dFdy(view_pos);
	vec3 r1 = cross(dpdy, normal);
	vec3 r2 = cross(normal, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(height) * r1 + dFdy(height) * r2);
	return normalize(abs(det) * normal - grad);
}

#ifdef CEL_SHADING
// Two-tone "comic" lighting: each light either fully lights a face or not at all,
// with a narrow soft edge, so unlit faces fall back to the scene's (blue) ambient
// light like the shadows in an inked illustration. Matte: no specular highlight,
// since a hard highlight on these flat faces lights whole panels at once.
group_uniforms cel_shading;
/// N.L value where the light/shadow edge sits; above 0 pushes more faces into shadow.
uniform float cel_threshold : hint_range(-0.5, 0.5) = 0.05;
/// Width of the light/shadow edge (0 = razor sharp).
uniform float cel_softness : hint_range(0.0, 0.3) = 0.03;
/// Brightness of the lit tone (Godot's own Lambert term includes 1/PI, about 0.32).
uniform float cel_light_scale = 0.3;
group_uniforms;

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(cel_threshold - cel_softness, cel_threshold + cel_softness, ndl);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * lit * cel_light_scale;
}
#endif

#ifdef DETAIL_FEATURES
// Surface features: painted marks, panels, vents and hatches drawn as colour plus
// bump relief instead of geometry. Each feature is a box in object space; any
// surface passing through the box gets the feature. The box's smallest axis
// should point along the surface normal and be thick enough to contain the
// surface's curvature or slope across the feature.
#define MAX_FEATURES 12
#define FEATURE_PAINT 0
#define FEATURE_RAISED 1
#define FEATURE_RECESSED 2
#define FEATURE_VENT 3
#define FEATURE_HATCH 4

group_uniforms surface_features;
/// Number of active entries in the feature arrays.
uniform int feature_count = 0;
/// xyz = box centre (object space); w = kind: 0 paint, 1 raised panel, 2 recessed panel, 3 vent slats, 4 round hatch.
uniform vec4 feature_center[MAX_FEATURES];
/// xyz = box half extents; w = relief height in metres.
uniform vec4 feature_size[MAX_FEATURES];
/// rgb = colour; a = how strongly it replaces the underlying colour.
uniform vec4 feature_color[MAX_FEATURES];
group_uniforms;

// Blends every feature covering object-space point `p` into the surface.
void apply_features(vec3 p, inout vec3 albedo, inout float height, inout float roughness) {
	for (int i = 0; i < MAX_FEATURES; i++) {
		if (i >= feature_count) {
			break;
		}
		vec3 d = p - feature_center[i].xyz;
		vec3 s = feature_size[i].xyz;
		vec3 q = abs(d) - s;
		// Signed distance to the box: negative inside.
		float sd = length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
		if (sd > 0.03) {
			continue;
		}

		// In-plane coordinates: drop the thinnest (normal-facing) axis.
		vec2 pd;
		vec2 ps;
		float thin_q;
		if (s.x <= s.y && s.x <= s.z) {
			pd = d.yz; ps = s.yz; thin_q = q.x;
		} else if (s.y <= s.z) {
			pd = d.xz; ps = s.xz; thin_q = q.y;
		} else {
			pd = d.xy; ps = s.xy; thin_q = q.z;
		}

		int kind = int(feature_center[i].w + 0.5);
		float relief = feature_size[i].w;
		vec4 tint = feature_color[i];
		float hatch_radius = min(ps.x, ps.y);
		if (kind == FEATURE_HATCH) {
			sd = max(length(pd) - hatch_radius, thin_q);
		}

		float coverage = 1.0 - smoothstep(-0.004, 0.004, sd);
		float bevel = smoothstep(0.0, 0.025, -sd);
		float outline = 1.0 - smoothstep(0.003, 0.009, abs(sd));
		vec3 colour = tint.rgb;

		if (kind == FEATURE_PAINT) {
			// Paint fills the hull seams beneath it, so they don't shimmer through.
			height = mix(height, 0.0, coverage * tint.a);
		} else if (kind == FEATURE_RAISED) {
			height += relief * bevel;
		} else if (kind == FEATURE_RECESSED) {
			height -= relief * bevel;
		} else if (kind == FEATURE_VENT) {
			// A recessed well crossed by slats running across its long axis.
			float along = ps.x > ps.y ? pd.x : pd.y;
			float t = fract(along / 0.07);
			float slat = smoothstep(0.05, 0.4, t) * (1.0 - smoothstep(0.6, 0.95, t));
			height += relief * bevel * (0.8 * slat - 1.0);
			colour *= 0.6 + 0.9 * slat;
		} else if (kind == FEATURE_HATCH) {
			// Raised rim around a slightly sunken lid.
			float r = length(pd) / hatch_radius;
			float rim = smoothstep(0.62, 0.75, r) * (1.0 - smoothstep(0.9, 1.0, r));
			float lid = 1.0 - smoothstep(0.5, 0.62, r);
			height += relief * (rim - 0.4 * lid);
			outline = max(outline, 1.0 - smoothstep(0.004, 0.01, abs(r - 0.56) * hatch_radius));
		}

		albedo = mix(albedo, colour, coverage * tint.a);
		roughness = mix(roughness, 0.5, coverage * tint.a);
		if (kind != FEATURE_PAINT) {
			albedo *= 1.0 - 0.5 * outline;
		}
	}
}
#endif
