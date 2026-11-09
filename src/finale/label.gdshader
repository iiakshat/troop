shader_type spatial;
render_mode cull_back;
// Bottle label: printed paper wrapped part way round the front, with trim bands and one of
// several pictures (no lettering anywhere): medallion with a star, sash with dots, chevrons,
// crest, or the gold bottle's crown.

uniform vec3 paper : source_color = vec3(0.95, 0.92, 0.82);
uniform vec3 ink : source_color = vec3(0.7, 0.12, 0.15);
uniform vec3 trim : source_color = vec3(0.85, 0.66, 0.25);
uniform int pattern = 0;
uniform float wrap = 0.7;      // fraction of the circumference covered, centred on the front
uniform float front = 0.25;    // u of the label centre (the side facing the thrower)
uniform float aspect = 2.5;    // label width / height, keeps the pictures round
uniform float metal = 0.0;     // foil labels: shinier

float star(vec2 p, float r) {
	float a = atan(p.y, p.x);
	float k = cos(floor(0.5 + a * 5.0 / 6.2832) * 6.2832 / 5.0 - a);
	return length(p) * k / mix(1.0, 0.45, 0.5 + 0.5 * cos(a * 5.0 + 1.5708)) - r;
}

void fragment() {
	float u = fract(UV.x - front + 0.5) - 0.5;
	if (abs(u) > wrap * 0.5) {
		discard;
	}
	vec2 p = vec2(u / wrap * aspect, UV.y - 0.5);   // centred, x stretched to true proportions
	vec3 c = paper;
	float edge = 0.5 - abs(p.y);
	float trims = step(edge, 0.07) * step(0.035, edge);
	c = mix(c, trim, trims);
	c = mix(c, ink, step(edge, 0.025));
	if (pattern == 0) {
		float d = length(p);
		c = mix(c, ink, step(d, 0.3) * step(0.25, d));
		c = mix(c, trim, step(star(p, 0.1), 0.0));
		c = mix(c, ink, step(0.42, abs(p.x)) * step(abs(p.y), 0.04));
	} else if (pattern == 1) {
		float s = abs(p.x * 0.5 + p.y);
		c = mix(c, ink, step(s, 0.12));
		vec2 g = fract(p * 6.0) - 0.5;
		c = mix(c, trim, step(length(g), 0.12) * step(0.16, s) * step(0.12, edge));
	} else if (pattern == 2) {
		float v = fract((abs(p.x) * 0.9 - p.y) * 3.0);
		c = mix(c, ink, step(v, 0.35) * step(0.1, edge) * step(abs(p.x), 0.9));
	} else if (pattern == 3) {
		// a bunch of grapes with a leaf
		float g = 1.0;
		for (int row = 0; row < 4; row++) {
			for (int k = 0; k < 4 - row; k++) {
				vec2 cpos = vec2((float(k) - float(3 - row) * 0.5) * 0.085, 0.13 - float(row) * 0.08);
				g = min(g, length(p - cpos) - 0.042);
			}
		}
		c = mix(c, ink, step(g, 0.0));
		c = mix(c, mix(ink, vec3(1.0), 0.35), step(g, 0.0) * step(length(p - vec2(-0.03, 0.17)), 0.015));
		vec2 lp = p - vec2(0.07, 0.24);
		float leaf = length(vec2(lp.x * 0.7 - lp.y * 0.5, lp.y * 1.3 + lp.x * 0.4)) - 0.06;
		c = mix(c, trim, step(leaf, 0.0));
	} else {
		float d = length(p);
		c = mix(c, ink, step(d, 0.33));
		vec2 q = p * 3.2;
		float crown = step(q.y, 0.35 - 0.35 * abs(sin(q.x * 4.7124))) * step(-0.35, q.y) * step(abs(q.x), 0.7);
		c = mix(c, trim, crown);
		c = mix(c, trim, step(abs(d - 0.36), 0.015));
	}
	ALBEDO = c;
	ROUGHNESS = mix(0.75, 0.25, metal);
	METALLIC = metal * 0.8;
}
