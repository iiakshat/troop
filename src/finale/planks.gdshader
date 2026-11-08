shader_type spatial;
// Warm painted wooden planks for the bottle gallery wall: vertical boards with darker
// seams, grain streaks and a little per-board colour variation.

uniform vec3 wood : source_color = vec3(0.36, 0.2, 0.11);
uniform float board_w = 0.32;
varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

float h1(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

void fragment() {
	float b = floor(lpos.x / board_w);
	float fx = fract(lpos.x / board_w);
	float seam = smoothstep(0.0, 0.05, fx) * smoothstep(1.0, 0.95, fx);
	float grain = sin((lpos.y * 9.0 + h1(b) * 20.0) + sin(lpos.y * 2.0 + fx * 6.0) * 1.5) * 0.5 + 0.5;
	vec3 c = wood * (0.8 + 0.3 * h1(b + 7.0)) * (0.88 + 0.12 * grain);
	ALBEDO = c * mix(0.35, 1.0, seam);
	ROUGHNESS = 0.75;
}
