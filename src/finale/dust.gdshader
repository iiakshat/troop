shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Dust motes drifting in the gallery spotlights. One MultiMesh of tiny quads; each mote
// drifts on its own slow loop (finale time `t`, so it slows down with the slow motion),
// faces the camera, twinkles, and only shows while it is inside one of the two beams.

uniform vec3 color : source_color = vec3(1.0, 0.92, 0.75);
uniform float t = 0.0;
uniform float size = 0.014;
uniform vec3 spot_a = vec3(0.0);
uniform vec3 dir_a = vec3(0.0, -1.0, 0.0);
uniform vec3 spot_b = vec3(0.0);
uniform vec3 dir_b = vec3(0.0, -1.0, 0.0);
uniform float cos_angle = 0.9;

varying float bright;

void vertex() {
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = INSTANCE_CUSTOM.r * 100.0;
	vec3 drift = vec3(sin(t * 0.23 + s), sin(t * 0.15 + s * 1.7) * 0.7, cos(t * 0.19 + s * 0.7)) * 0.18;
	vec3 wp = base + drift;
	float ba = dot(normalize(wp - spot_a), dir_a);
	float bb = dot(normalize(wp - spot_b), dir_b);
	bright = max(smoothstep(cos_angle, cos_angle + 0.03, ba), smoothstep(cos_angle, cos_angle + 0.03, bb));
	bright *= 0.35 + 0.65 * pow(0.5 + 0.5 * sin(t * (1.2 + INSTANCE_CUSTOM.g * 3.0) + s), 3.0);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = wp + (right * VERTEX.x + up * VERTEX.y) * size * (0.5 + INSTANCE_CUSTOM.b);
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = pow(clamp(1.0 - d, 0.0, 1.0), 2.0);
	ALBEDO = color * a * bright * 1.6;
}
