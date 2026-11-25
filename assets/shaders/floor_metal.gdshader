shader_type spatial;
// Procedural sci-fi industrial floor (world-space, tiles seamlessly on any flat mesh).
// Panels with beveled seams, diamond tread plates, grime, corrupted stains and
// emissive guide lines. Replaced automatically by a PolyHaven set when present.

uniform vec3 base_color : source_color = vec3(0.24, 0.27, 0.28);
uniform vec3 alt_color : source_color = vec3(0.15, 0.17, 0.18);
uniform vec3 seam_color : source_color = vec3(0.008, 0.01, 0.012);
uniform vec3 stain_color : source_color = vec3(0.22, 0.02, 0.06);
uniform vec3 line_color : source_color = vec3(0.1, 0.85, 1.0);
uniform float line_energy = 1.2;
uniform float panel_size = 4.0;
uniform float tread_scale = 5.0;
uniform float stain_amount : hint_range(0.0, 1.0) = 0.35;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

float panel_edge(vec2 p) {
	vec2 f = fract(p / panel_size);
	return min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * panel_size;
}

float tread(vec2 p) {
	vec2 q = p * tread_scale;
	vec2 cell = floor(q);
	vec2 g = fract(q) - 0.5;
	// alternating elongated studs, like real diamond plate
	float flip = mod(cell.x + cell.y, 2.0);
	vec2 r = flip > 0.5 ? vec2(g.x + g.y, g.x - g.y) : vec2(g.x - g.y, g.x + g.y);
	float d = length(r * vec2(1.0, 3.2));
	return smoothstep(0.42, 0.3, d);
}

float height(vec2 p) {
	vec2 cid = floor(p / panel_size);
	float e = panel_edge(p);
	float h = smoothstep(0.03, 0.12, e) * 0.6;
	float use_tread = step(0.45, hash(cid * 1.7));
	h += tread(p) * 0.25 * use_tread;
	return h;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 cid = floor(p / panel_size);
	float pv = hash(cid);
	float e = panel_edge(p);

	// bump normal from height field (world space -> view space)
	float eps = 0.02;
	float h0 = height(p);
	float hx = height(p + vec2(eps, 0.0));
	float hz = height(p + vec2(0.0, eps));
	vec3 wn = normalize(vec3(-(hx - h0) / eps * 0.06, 1.0, -(hz - h0) / eps * 0.06));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	float grime = fbm(p * 0.35);
	float fine = fbm(p * 3.0);
	vec3 col = mix(base_color, alt_color, step(0.5, pv));
	col *= 0.8 + fine * 0.4;
	float seam = 1.0 - smoothstep(0.015, 0.045, e);
	col = mix(col, seam_color, seam);
	// dark grime gathers near seams
	col *= mix(1.0, 0.55, (1.0 - smoothstep(0.0, 0.35, e)) * grime);
	// corrupted organic stains
	float stain = smoothstep(0.58, 0.75, fbm(p * 0.12 + vec2(13.0, 7.0))) * stain_amount;
	col = mix(col, stain_color * (0.6 + fine * 0.6), stain);

	float tr = tread(p) * step(0.45, hash(cid * 1.7));
	ALBEDO = col;
	METALLIC = mix(0.2, 0.45, tr);
	ROUGHNESS = clamp(0.42 + grime * 0.35 - tr * 0.2 + seam * 0.4 - stain * 0.15, 0.12, 1.0);
	SPECULAR = 0.6;

	// emissive guide lines on every 3rd seam line
	float lx = abs(fract(p.x / (panel_size * 3.0) + 0.5) - 0.5) * panel_size * 3.0;
	float lines = (1.0 - smoothstep(0.03, 0.06, lx)) * step(0.5, fract(p.y / (panel_size * 2.0)));
	EMISSION = line_color * lines * line_energy * (0.75 + 0.25 * sin(TIME * 2.0 + p.y * 0.5));
}
