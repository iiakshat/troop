shader_type spatial;
render_mode specular_schlick_ggx;
// Painted asphalt (tiled texture) with dashed lane lines, solid edge lines and a soft
// darker band near the curbs; `offset` scrolls everything towards the camera. `wet` (0..1,
// the night district) darkens the asphalt, adds glossy puddles and makes it shine.

uniform float offset = 0.0;
uniform float half_width = 4.9;
uniform sampler2D asphalt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 5.0;
uniform float wet = 0.0;
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
	// Puddles: a slow, large-scale blotch pattern from the asphalt texture itself.
	float pud = 0.0;
	if (wet > 0.0) {
		float blot = texture(asphalt, vec2(wpos.x * 0.7 + 3.1, z) / (tile_m * 4.7)).r;
		blot = mix(blot, texture(asphalt, vec2(z, wpos.x) / (tile_m * 3.1)).g, 0.5);
		pud = smoothstep(0.42, 0.52, blot) * wet;
	}
	col *= 1.0 - wet * (0.42 + 0.25 * pud);
	col = mix(col, vec3(0.97, 0.95, 0.86) * (1.0 - 0.25 * wet), m * 0.92);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.85, 0.6, m), mix(0.3, 0.06, pud), wet);
	SPECULAR = 0.5 + 0.4 * wet;
}
