shader_type spatial;
// Spec v2.1 §4.1 per-level looks: a screen-filling quad just in front of the street camera.
// mode 0 = Storm rain (slanted streaks in three depths, falling), mode 1 = Rush speed lines
// (streaks flying out from the vanishing point, only near the screen edges). amount 0 = off.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform int mode = 0;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float phase = 0.0;         // speed lines: advances with the street's speed (World)
uniform vec2 vanish = vec2(0.5, 0.26);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float a = 0.0;
	if (mode == 0) {
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float cols = 34.0 + fi * 22.0;
			vec2 p = vec2(uv.x * cols + uv.y * cols * 0.22, uv.y * (2.6 + fi * 1.4) - TIME * (2.2 + fi * 0.9));
			vec2 cell = floor(p);
			vec2 f = fract(p);
			float r = hash(cell + fi * 17.0);
			float x0 = 0.2 + 0.6 * hash(cell.yx + 3.1 + fi);
			float line = smoothstep(0.09, 0.0, abs(f.x - x0));
			float len = smoothstep(0.0, 0.18, f.y) * smoothstep(0.62, 0.3, f.y);
			a += line * len * step(0.62, r) * (0.42 - 0.1 * fi);
		}
		ALBEDO = vec3(0.82, 0.88, 0.98);
		ALPHA = clamp(a * amount, 0.0, 0.55);
	} else {
		vec2 c = uv - vanish;
		c.x *= 0.5625;
		float ang = atan(c.y, c.x);
		float r = length(c);
		float spokes = 64.0;
		float s = ang / 6.2831853 * spokes;
		float cell = floor(s);
		float fx = fract(s);
		float rnd = hash(vec2(cell, 7.0));
		float run = fract(r * 2.2 - phase * (1.6 + 1.4 * rnd) + rnd);
		float line = smoothstep(0.12, 0.0, abs(fx - 0.5)) * smoothstep(0.0, 0.25, run) * smoothstep(0.6, 0.35, run);
		float edge = smoothstep(0.24, 0.42, r);
		a = line * edge * step(0.55, rnd);
		ALBEDO = vec3(1.0);
		ALPHA = clamp(a * amount * 0.32, 0.0, 0.32);
	}
}
