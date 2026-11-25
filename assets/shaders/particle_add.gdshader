shader_type spatial;
// HDR additive particle: soft round sprite (billboard) or hard streak (non-billboard
// mesh aligned to velocity). COLOR comes from the particle process color ramp.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float energy = 4.0;
uniform bool billboard = true;
uniform float softness = 1.0;
uniform vec4 tint : source_color = vec4(1.0);

void vertex() {
	if (billboard) {
		mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
		mat_world = mat_world * mat4(vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0), vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	float a = 1.0;
	if (softness > 0.0) {
		float r = length(UV - 0.5) * 2.0;
		a = pow(clamp(1.0 - r, 0.0, 1.0), 1.0 + softness);
	}
	ALBEDO = COLOR.rgb * tint.rgb * energy * a;
	ALPHA = clamp(COLOR.a * a, 0.0, 1.0);
}
