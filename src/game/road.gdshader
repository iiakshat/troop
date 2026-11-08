shader_type spatial;
render_mode specular_disabled;
// Asphalt with two dashed lane lines and solid edge lines; `offset` scrolls the dashes.

uniform float offset = 0.0;
uniform float half_width = 4.9;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float line(float x, float center, float w) {
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + 0.03, abs(x - center));
}

void fragment() {
	vec3 col = vec3(0.30, 0.32, 0.36);
	// subtle large-scale patches so the asphalt isn't flat
	float z = wpos.z - offset;
	float patch = sin(z * 0.37 + sin(wpos.x * 0.9)) * sin(z * 0.11 + wpos.x * 0.3);
	col *= 0.96 + patch * 0.04;
	float lane_w = half_width * 2.0 / 3.0;
	float dash = step(0.5, fract(z / 4.0));
	float m = 0.0;
	m = max(m, line(wpos.x, -lane_w * 0.5, 0.16) * dash);
	m = max(m, line(wpos.x, lane_w * 0.5, 0.16) * dash);
	m = max(m, line(wpos.x, -half_width + 0.25, 0.14));
	m = max(m, line(wpos.x, half_width - 0.25, 0.14));
	col = mix(col, vec3(0.95, 0.95, 0.9), m);
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
