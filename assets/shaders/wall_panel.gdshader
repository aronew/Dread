shader_type spatial;
// White sci-fi wall panels with red livery stripe, dark plinth and a neon kick line.

uniform vec3 panel_color : source_color = vec3(0.78, 0.78, 0.76);
uniform vec3 stripe_color : source_color = vec3(0.55, 0.05, 0.07);
uniform vec3 plinth_color : source_color = vec3(0.05, 0.055, 0.06);
uniform vec3 neon_color : source_color = vec3(0.25, 0.45, 1.0);
uniform float neon_energy = 4.0;
uniform float panel_width = 2.0;

varying vec3 wpos;
varying vec3 wnormal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float top = step(0.7, wnormal.y);
	float u = abs(wnormal.x) > 0.5 ? wpos.z : wpos.x;
	float y = wpos.y;
	float fu = fract(u / panel_width);
	float seam = 1.0 - smoothstep(0.0, 0.02, min(fu, 1.0 - fu));
	float grime = noise(vec2(u, y) * 2.5) * noise(vec2(u, y) * 0.4);

	vec3 col = panel_color * (0.92 + noise(vec2(u, y) * 8.0) * 0.08);
	// diagonal red livery swoosh
	float band_center = 1.75 + sin(u * 0.35) * 0.18;
	float stripe = smoothstep(0.2, 0.17, abs(y - band_center));
	col = mix(col, stripe_color, stripe);
	// plinth
	float plinth = step(y, 0.45);
	col = mix(col, plinth_color, plinth);
	col = mix(col, col * 0.25, seam);
	col *= 1.0 - grime * 0.35 * (1.0 - plinth);
	col = mix(col, plinth_color * 1.5, top);

	ALBEDO = col;
	ROUGHNESS = mix(0.32, 0.6, plinth + grime * 0.5);
	METALLIC = mix(0.15, 0.8, plinth);
	float neon = smoothstep(0.035, 0.0, abs(y - 0.5)) * (1.0 - top);
	EMISSION = neon_color * neon * neon_energy;
}
