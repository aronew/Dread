shader_type spatial;
// Expanding shockwave ring on a flat quad. progress 0..1 drives radius + fade.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform float progress = 0.0;
uniform float thickness = 0.08;
uniform float energy = 2.2;

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float p = 1.0 - pow(1.0 - progress, 2.5);
	float w = thickness * (1.0 - progress * 0.6);
	float ring = 1.0 - smoothstep(0.0, w, abs(r - p));
	float inner = smoothstep(p - w * 4.0, p, r) * step(r, p) * 0.35;
	float fade = 1.0 - progress;
	float a = (ring + inner) * fade;
	ALBEDO = color.rgb * energy * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
