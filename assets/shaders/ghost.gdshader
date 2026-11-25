shader_type spatial;
// Dash afterimage: hollow fresnel hologram that fades out.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.2, 0.7, 1.0, 1.0);
uniform float alpha = 1.0;
uniform float energy = 2.5;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	float scan = 0.8 + 0.2 * sin(FRAGCOORD.y * 0.8 + TIME * 30.0);
	float a = (0.18 + fres * 0.9) * alpha * scan;
	ALBEDO = color.rgb * energy * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
