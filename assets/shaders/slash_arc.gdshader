shader_type spatial;
// Melee cleave arc. UV.x = angle along arc (0..1), UV.y = radial (0 inner, 1 outer).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 core_color : source_color = vec4(0.85, 0.98, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.2, 0.45, 1.0, 1.0);
uniform float progress = 0.0;
uniform float direction = 1.0;
uniform float energy = 3.2;

void fragment() {
	float a = direction > 0.0 ? UV.x : 1.0 - UV.x;
	float behind = progress - a;
	float sweep = step(0.0, behind) * exp(-max(behind, 0.0) * 5.0);
	float head = smoothstep(0.0, 0.03, behind) * (1.0 - smoothstep(0.03, 0.12, behind));
	float radial = smoothstep(0.0, 0.55, UV.y) * (1.0 - smoothstep(0.9, 1.0, UV.y));
	float hot = smoothstep(0.55, 0.92, UV.y);
	float streaks = 0.75 + 0.25 * sin(UV.y * 60.0 + a * 8.0);
	vec3 col = mix(edge_color.rgb, core_color.rgb, hot * 0.8 + head * 0.5);
	float fade_out = 1.0 - smoothstep(1.0, 1.4, progress);
	float alpha = (sweep * radial * streaks + head * radial * 0.6) * fade_out;
	ALBEDO = col * energy * alpha;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
