shader_type spatial;
// Camera-facing tracer ribbon. The node's -Z points along travel; the ribbon
// trails behind along +Z for `trail_len` metres: white-hot head, colored body,
// tapered fading tail. Also reused for dash speed-lines and slash marks.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.3, 0.85, 1.0, 1.0);
uniform float energy = 5.0;
uniform float width = 0.12;
instance uniform float trail_len = 1.0;
instance uniform float fade = 1.0;
instance uniform float taper = 0.7;   // 0 = constant width, 1 = needle tail

void vertex() {
	vec3 head = MODEL_MATRIX[3].xyz;
	vec3 back = normalize(MODEL_MATRIX[2].xyz);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - head);
	vec3 side = cross(back, to_cam);
	float sl = length(side);
	side = sl > 0.0001 ? side / sl : vec3(1.0, 0.0, 0.0);
	float along01 = 0.5 - VERTEX.y;              // 0 at head (top of quad) .. 1 at tail
	float w = width * mix(1.0, 1.0 - taper, along01);
	vec3 world = head + back * along01 * trail_len + side * VERTEX.x * w;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	float t = UV.y;                                // 0 head .. 1 tail
	float core = 1.0 - smoothstep(0.0, 0.5, across);
	float glow = 1.0 - smoothstep(0.25, 1.0, across);
	float body = pow(1.0 - t, 1.4);
	float head_hot = 1.0 - smoothstep(0.0, 0.15, t);
	vec3 c = mix(color.rgb, vec3(1.0), clamp(core * 0.3 + head_hot * 0.7, 0.0, 1.0));
	float a = (core + glow * 0.5) * body * fade;
	ALBEDO = c * energy * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
