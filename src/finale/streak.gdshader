shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Velocity-stretched streaks (liquid spray and glass glitter). Each instance is a quad from
// its tail (UV.y = 0) to its head (UV.y = 1), turned to face the camera on the CPU; the
// instance colour carries tint and fade.

varying vec4 col;

void vertex() {
	col = COLOR;
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float a = smoothstep(0.0, 0.7, across) * smoothstep(0.0, 0.55, UV.y) * (1.0 - smoothstep(0.92, 1.0, UV.y) * 0.5);
	ALBEDO = col.rgb * (0.85 + 0.7 * pow(across, 6.0));
	ALPHA = a * col.a;
}
