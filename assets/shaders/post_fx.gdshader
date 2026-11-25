shader_type canvas_item;
// Full-screen post: chromatic aberration (spikes on hits), vignette, damage /
// low-health red pulse and light film grain.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float aberration = 0.0;
uniform float damage = 0.0;
uniform float low_health = 0.0;
uniform float vignette = 0.55;
uniform float grain = 0.03;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float d = length(c * vec2(1.0, 0.8));
	float ab = (0.002 + aberration * 0.014) * d;
	vec3 col;
	col.r = texture(screen_tex, uv + c * ab).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - c * ab).b;
	float vig = smoothstep(0.85, 0.2, d * (1.0 + vignette));
	col *= mix(1.0, vig, 0.8);
	float pulse = 0.5 + 0.5 * sin(TIME * 7.0);
	float red = clamp(damage + low_health * (0.3 + 0.3 * pulse), 0.0, 1.0) * smoothstep(0.15, 0.7, d);
	col = mix(col, vec3(0.55, 0.0, 0.04), red * 0.7);
	float n = fract(sin(dot(uv * vec2(1920.0, 1080.0) + fract(TIME) * 97.0, vec2(12.9898, 78.233))) * 43758.5453);
	col += (n - 0.5) * grain;
	COLOR = vec4(col, 1.0);
}
