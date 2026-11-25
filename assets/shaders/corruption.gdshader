shader_type spatial;
// Bioluminescent alien corruption: pulsing veins over dark goo. Used for floor
// growths and corrosive puddles. UV (0..1) disc fades at the edge.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 goo_color : source_color = vec3(0.05, 0.02, 0.07);
uniform vec3 vein_a : source_color = vec3(0.35, 1.0, 0.25);
uniform vec3 vein_b : source_color = vec3(0.75, 0.15, 1.0);
uniform float energy = 3.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float seed = 0.0;
uniform float edge_noise = 0.35;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.1; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	float edge = fbm(c * 4.0 + seed) * edge_noise;
	float mask = smoothstep(1.0, 0.75, r + edge);
	vec2 p = c * 6.0 + seed;
	float t = TIME * 0.35;
	float n = fbm(p + vec2(t, -t * 0.7));
	float veins = 1.0 - smoothstep(0.0, 0.06, abs(n - 0.5));
	float n2 = fbm(p * 1.7 - vec2(t * 0.5, t));
	float veins2 = 1.0 - smoothstep(0.0, 0.04, abs(n2 - 0.5));
	float pulse = 0.6 + 0.4 * sin(TIME * 3.0 + r * 8.0 + seed);
	vec3 glow = vein_a * veins * pulse + vein_b * veins2 * (1.0 - pulse * 0.5);
	ALBEDO = goo_color;
	ROUGHNESS = 0.15;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	EMISSION = glow * energy * mask;
	ALPHA = mask * opacity * (0.85 + veins * 0.15);
}
