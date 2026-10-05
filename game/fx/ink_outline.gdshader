// Comic-style ink outlines as a full-screen pass. Attach the InkOutline quad to a
// camera. Each pixel rebuilds view-space positions from the depth buffer and inks
// it where the surface's second difference is large compared with one pixel's
// footprint: huge at silhouettes (depth jumps), moderate at creases (the surface
// turns), and ~0 on flat or smoothly curved surfaces. Transparent effects such as
// exhaust don't write depth, so they stay un-outlined.
// Depth-buffer quantization (coarse in the Compatibility renderer) is measured per
// pixel and bends below it are ignored, so flat faces don't speckle. Precision
// still depends on the camera's near plane: keep `near` as large as the scene allows.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 ink_color : source_color = vec3(0.03, 0.035, 0.05);
/// Line half-width in pixels at 1080p; scales with the render height.
uniform float thickness = 1.8;
/// Edge strength where lines start (lower inks gentler creases, e.g. cylinder facets).
uniform float crease_threshold = 0.9;
/// Edge strength where lines reach full opacity.
uniform float crease_full = 1.6;
/// Distance (metres) where outlines start fading out, and where they are gone.
uniform float fade_start = 120.0;
uniform float fade_end = 350.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
/// Smallest representable step of the depth texture (1/65536 for 16-bit depth).
uniform float depth_step = 0.0000153;
/// How many depth steps of wobble to tolerate before a bend counts as an edge.
uniform float noise_margin = 4.0;

vec3 view_from_depth(vec2 uv, float depth, mat4 inv_projection) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#endif
	vec4 view = inv_projection * vec4(ndc, 1.0);
	return view.xyz / view.w;
}

vec3 view_position(vec2 uv, mat4 inv_projection) {
	return view_from_depth(uv, texture(depth_texture, uv).r, inv_projection);
}

void vertex() {
	// Cover the whole screen regardless of where the quad sits.
	POSITION = vec4(VERTEX.xy, 0.5, 1.0);
}

void fragment() {
	float px_size = thickness * VIEWPORT_SIZE.y / 1080.0;
	vec2 step_uv = vec2(px_size) / VIEWPORT_SIZE;
	vec3 c = view_position(SCREEN_UV, INV_PROJECTION_MATRIX);
	vec3 l = view_position(SCREEN_UV - vec2(step_uv.x, 0.0), INV_PROJECTION_MATRIX);
	vec3 r = view_position(SCREEN_UV + vec2(step_uv.x, 0.0), INV_PROJECTION_MATRIX);
	vec3 d = view_position(SCREEN_UV - vec2(0.0, step_uv.y), INV_PROJECTION_MATRIX);
	vec3 u = view_position(SCREEN_UV + vec2(0.0, step_uv.y), INV_PROJECTION_MATRIX);

	// The nearest of the samples decides the scale, so a silhouette is judged
	// against the object in front, not the background behind it.
	float dist = min(-c.z, min(min(-l.z, -r.z), min(-u.z, -d.z)));
	// World size of the sample step at that distance.
	float footprint = 2.0 * dist * px_size / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float bend = length(l + r - 2.0 * c) + length(u + d - 2.0 * c);
	// Depth-buffer quantization: how far one depth step moves the surface here.
	// Bends smaller than a few steps are noise, not geometry.
	float raw = texture(depth_texture, SCREEN_UV).r;
	vec3 c_step = view_from_depth(SCREEN_UV, raw + depth_step, INV_PROJECTION_MATRIX);
	float noise = noise_margin * length(c_step - c);
	float edge = bend / max(max(footprint, noise), 1e-5);

	float ink = smoothstep(crease_threshold, crease_full, edge);
	ink *= 1.0 - smoothstep(fade_start, fade_end, dist);
	ALBEDO = ink_color;
	ALPHA = ink * opacity;
}
