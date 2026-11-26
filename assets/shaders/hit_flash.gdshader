shader_type spatial;
// Overlay pass applied to every mesh of an actor (GeometryInstance3D.material_overlay).
// flash        -> solid additive burst on hit (holds white briefly, then fades)
// rim_strength -> fresnel glow for attack wind-ups / finisher-ready
// highlight    -> thin cool rim when the actor is the player's aim target
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash : hint_range(0.0, 2.0) = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.25, 0.15, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 highlight_color : source_color = vec4(0.45, 0.95, 1.0, 1.0);
uniform float highlight : hint_range(0.0, 1.0) = 0.0;
uniform vec4 base_rim_color : source_color = vec4(1.0, 0.3, 0.6, 1.0);
uniform float base_rim : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float pulse = 0.75 + 0.25 * sin(TIME * 22.0);
	vec3 c = flash_color.rgb * min(flash, 1.0) * 2.2;
	c += rim_color.rgb * rim_strength * (fres * 3.0 + 0.25) * pulse;
	c += highlight_color.rgb * highlight * pow(fres, 1.5) * 2.5;
	c += base_rim_color.rgb * base_rim * pow(fres, 2.5) * 1.6;
	ALBEDO = c;
}
