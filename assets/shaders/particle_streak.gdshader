shader_type spatial;
// Velocity-aligned spark streak. Particles use align_y (Y = velocity); this
// rotates the quad around that axis to face the camera, so sparks always read
// as bright streaks from the isometric view (never edge-on).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float energy = 3.0;

void vertex() {
	vec3 y_axis = MODEL_MATRIX[1].xyz;
	float ylen = max(length(y_axis), 0.0001);
	vec3 y_dir = y_axis / ylen;
	float xlen = length(MODEL_MATRIX[0].xyz);
	vec3 pos = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - pos);
	vec3 x_dir = cross(y_dir, to_cam);
	float xl = length(x_dir);
	x_dir = xl > 0.0001 ? x_dir / xl : vec3(1.0, 0.0, 0.0);
	vec3 world = pos + x_dir * VERTEX.x * xlen + y_dir * VERTEX.y * ylen;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	float core = 1.0 - smoothstep(0.0, 1.0, across);
	float head = 1.0 - UV.y * 0.75;  // brighter at the leading end
	vec3 c = mix(COLOR.rgb, vec3(1.0), (1.0 - across) * 0.35);
	float a = core * head;
	ALBEDO = c * energy * a;
	ALPHA = clamp(COLOR.a * a, 0.0, 1.0);
}
