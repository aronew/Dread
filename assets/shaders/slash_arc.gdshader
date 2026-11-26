shader_type spatial;
// Melee crescent. UV.x = angle along the arc (0..1), UV.y = radial (0 inner, 1 outer).
// progress 0..1 sweeps the head across the arc, 1..1.5 fades it out.
// Crescent profile: fat in the middle of the swing, needle-thin at both ends,
// white-hot outer edge and a bright flare riding the leading edge.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 core_color : source_color = vec4(0.88, 0.98, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.25, 0.55, 1.0, 1.0);
uniform float progress = 0.0;
uniform float direction = 1.0;
uniform float energy = 4.0;

void fragment() {
	float a = direction > 0.0 ? UV.x : 1.0 - UV.x;
	float head = min(progress, 1.0);
	float behind = head - a;
	if (behind < 0.0) {
		discard;
	}
	float trail = exp(-behind * 3.2);
	float fade = 1.0 - smoothstep(1.0, 1.5, progress);
	float profile = sin(3.14159 * clamp(a, 0.0, 1.0));
	float inner = mix(0.94, 0.2, profile);
	float r = UV.y;
	float band = smoothstep(inner, inner + 0.14, r) * (1.0 - smoothstep(0.965, 1.0, r));
	float rim = smoothstep(0.82, 0.965, r) * (1.0 - smoothstep(0.965, 1.0, r));
	float head_glow = exp(-behind * 28.0);
	float streaks = 0.8 + 0.2 * sin(r * 70.0 + a * 6.0);
	vec3 col = mix(edge_color.rgb, core_color.rgb, clamp(rim * 1.3 + head_glow * 0.7, 0.0, 1.0));
	float alpha = (band * (0.5 + 0.5 * trail) * streaks + rim * 0.9) * trail * fade;
	alpha += head_glow * band * 0.7 * fade;
	ALBEDO = col * energy * alpha;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
