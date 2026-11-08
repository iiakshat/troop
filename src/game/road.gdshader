shader_type spatial;
render_mode specular_schlick_ggx;
// Painted asphalt (tiled texture) with dashed lane lines, solid edge lines and a soft
// darker band near the curbs; `offset` scrolls everything towards the camera.

uniform float offset = 0.0;
uniform float half_width = 4.9;
uniform sampler2D asphalt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 5.0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float line(float x, float center, float w) {
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + 0.04, abs(x - center));
}

void fragment() {
	float z = wpos.z - offset;
	vec3 col = texture(asphalt, vec2(wpos.x, z) / tile_m).rgb;
	// a second, rotated sample at another scale breaks up visible repeats
	col = mix(col, texture(asphalt, vec2(z, -wpos.x) / (tile_m * 2.3)).rgb, 0.35);
	col = mix(vec3(dot(col, vec3(0.33))), col, 0.15) * vec3(0.86, 0.84, 0.84);
	col *= 0.82 + 0.18 * smoothstep(half_width, half_width - 1.4, abs(wpos.x));
	float lane_w = half_width * 2.0 / 3.0;
	float dash = smoothstep(0.48, 0.5, fract(z / 4.0)) * (1.0 - smoothstep(0.98, 1.0, fract(z / 4.0)));
	float m = 0.0;
	m = max(m, line(wpos.x, -lane_w * 0.5, 0.18) * dash);
	m = max(m, line(wpos.x, lane_w * 0.5, 0.18) * dash);
	m = max(m, line(wpos.x, -half_width + 0.3, 0.16));
	m = max(m, line(wpos.x, half_width - 0.3, 0.16));
	col = mix(col, vec3(0.97, 0.95, 0.86), m * 0.92);
	ALBEDO = col;
	ROUGHNESS = mix(0.85, 0.6, m);
}
