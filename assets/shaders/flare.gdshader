shader_type spatial;
// Sharp 4-point star flare (muzzle flashes, impacts, crits). Billboarded,
// rotated per particle for variety. Hot white core, tinted rays and halo.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float energy = 3.0;
uniform vec4 tint : source_color = vec4(1.0);

void vertex() {
	mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mat_world = mat_world * mat4(vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0), vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float core = exp(-r * r * 16.0);
	float ray_x = exp(-abs(p.y) * 30.0) * (1.0 - smoothstep(0.0, 1.0, abs(p.x)));
	float ray_y = exp(-abs(p.x) * 30.0) * (1.0 - smoothstep(0.0, 1.0, abs(p.y)));
	float halo = exp(-r * r * 5.0) * 0.18;
	float a = (core * 0.9 + (ray_x + ray_y) * 0.85 + halo) * (1.0 - smoothstep(0.9, 1.0, r));
	vec3 col = mix(COLOR.rgb * tint.rgb, vec3(1.0), clamp(core * 0.6, 0.0, 1.0));
	ALBEDO = col * energy * a;
	ALPHA = clamp(COLOR.a * a, 0.0, 1.0);
}
