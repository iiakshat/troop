shader_type spatial;
render_mode specular_schlick_ggx;
// The drink inside a bottle: deeper colour through the middle, thinner at the rim, a bright
// meniscus line at the fill height, and rising bubbles for fizzy drinks.

uniform vec3 color : source_color = vec3(0.8, 0.2, 0.3);
uniform float fill_top = 0.4;
uniform float bubbles = 0.0;
varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	vec3 c = color * mix(0.55, 1.25, pow(ndv, 0.8));
	float men = smoothstep(fill_top - 0.014, fill_top - 0.002, lpos.y);
	c = mix(c, color * 1.8 + vec3(0.12), men * 0.65);
	if (bubbles > 0.0) {
		float ang = atan(lpos.z, lpos.x);
		vec2 g = vec2(ang * 7.0, lpos.y * 55.0 - TIME * 2.6);
		vec2 cell = floor(g);
		vec2 f = fract(g) - 0.5;
		float h = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		f.x += (h - 0.5) * 0.5;
		float b = step(0.78, h) * (1.0 - smoothstep(0.08, 0.2, length(f)));
		c += vec3(b * bubbles) * (1.0 - men);
	}
	ALBEDO = c * 0.45;
	EMISSION = c * 0.4;
	ROUGHNESS = 0.12;
	SPECULAR = 0.5;
}
