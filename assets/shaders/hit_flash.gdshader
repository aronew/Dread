shader_type spatial;
// Overlay pass applied to every mesh of an actor (GeometryInstance3D.material_overlay).
// flash        -> solid additive burst on hit
// rim_strength -> fresnel glow used for attack wind-ups / stagger indicators
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.25, 0.15, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float pulse = 0.75 + 0.25 * sin(TIME * 22.0);
	vec3 c = flash_color.rgb * flash * 1.6;
	c += rim_color.rgb * rim_strength * (fres * 3.0 + 0.25) * pulse;
	ALBEDO = c;
}
