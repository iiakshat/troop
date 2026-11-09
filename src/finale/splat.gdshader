shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;
// Wet stain the drink leaves on the plank wall: an irregular splash that spreads in a blink,
// then a few drips run down. `age` (seconds) animates it; `seed` varies the shape.

uniform vec3 color : source_color = vec3(0.6, 0.1, 0.2);
uniform float age = 0.0;
uniform float seed = 0.0;

float h1(float x) {
	return fract(sin(x * 127.1 + seed * 31.7) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - vec2(0.5, 0.35)) * vec2(2.0, 2.0);   // splash centre a bit above the middle
	float grow = smoothstep(0.0, 0.12, age);
	float a = atan(p.y, p.x);
	float lobes = 0.28 + 0.08 * sin(a * 7.0 + seed * 5.0) + 0.06 * sin(a * 13.0 + seed * 2.0) + 0.05 * sin(a * 3.0 - seed);
	float d = length(p);
	float splash = 1.0 - smoothstep(lobes * grow - 0.02, lobes * grow + 0.02, d);
	// flecks around the splash
	vec2 g = floor(p * 9.0);
	float fleck = step(0.9, h1(g.x * 17.0 + g.y)) * step(length(fract(p * 9.0) - 0.5), 0.25) * step(d, 0.75 * grow) * step(0.3, d);
	// drips: thin runs down from the bottom of the splash (UV.y grows downwards)
	float drips = 0.0;
	for (int i = 0; i < 5; i++) {
		float x = (h1(float(i)) - 0.5) * 0.4;
		float len = (0.15 + h1(float(i) + 9.0) * 0.7) * smoothstep(0.1, 1.6, age);
		float w = 0.02 + h1(float(i) + 3.0) * 0.02;
		float inx = 1.0 - smoothstep(w * 0.6, w, abs(p.x - x));
		float tipw = 1.0 - smoothstep(0.0, 0.05, p.y - (0.12 + len));
		drips = max(drips, inx * step(0.0, p.y) * tipw * step(0.15, grow));
	}
	float m = max(max(splash, fleck), drips);
	ALBEDO = color * 0.35;
	ROUGHNESS = 0.15;
	SPECULAR = 0.7;
	ALPHA = m * 0.7;
}
