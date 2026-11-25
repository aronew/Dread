shader_type spatial;
// Energy bolt / tracer body. Hot white core fading to the bolt color at the rim.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.3, 0.85, 1.0, 1.0);
uniform float energy = 6.0;
uniform float alpha = 1.0;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float core = pow(facing, 3.0);
	vec3 c = mix(color.rgb, vec3(1.0), core * 0.75);
	float a = (0.35 + core * 0.65) * alpha;
	ALBEDO = c * energy * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
