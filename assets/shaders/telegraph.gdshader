shader_type spatial;
// Ground attack telegraph. shape 0 = circle (fills outward), 1 = line/rect (fills
// from origin to tip). Bright outline + filling body so the danger reads instantly.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.15, 0.08, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform int shape = 0;
uniform float energy = 1.8;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float flash = 0.0;

void fragment() {
	float alpha = 0.0;
	float stripes = 0.5 + 0.5 * sin((UV.x + UV.y) * 40.0 - TIME * 12.0);
	if (shape == 0) {
		float r = length(UV - 0.5) * 2.0;
		if (r > 1.0) discard;
		float outline = smoothstep(0.9, 0.96, r) * (1.0 - smoothstep(0.97, 1.0, r));
		float filled = 1.0 - smoothstep(progress - 0.015, progress, r);
		float front = smoothstep(progress - 0.08, progress, r) * (1.0 - smoothstep(progress, progress + 0.01, r));
		alpha = outline * 1.1 + filled * (0.22 + stripes * 0.08) + front * 0.9 + 0.06;
	} else {
		float across = abs(UV.x - 0.5) * 2.0;
		float along = 1.0 - UV.y;
		float outline = smoothstep(0.82, 0.92, across) + smoothstep(0.97, 0.99, along);
		float filled = 1.0 - smoothstep(progress - 0.02, progress, along);
		float front = smoothstep(progress - 0.08, progress, along) * (1.0 - smoothstep(progress, progress + 0.01, along));
		float chevron = step(0.5, fract(along * 6.0 - across * 0.6 - TIME * 3.0)) * 0.12;
		alpha = outline * 0.75 + filled * (0.1 + chevron * 0.5) + front * 0.6 + 0.03;
	}
	vec3 c = mix(color.rgb, vec3(1.0, 0.95, 0.8), flash);
	ALBEDO = c * energy * (1.0 + flash * 2.0);
	ALPHA = clamp(alpha * fade, 0.0, 1.0);
}
