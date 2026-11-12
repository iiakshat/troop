shader_type spatial;
// A flat ring on the road that fills as an arc (spec v2 §2 hero heat, §5 barrel fuse).
// Drawn on a PlaneMesh: the arc grows from the side facing the camera (+z) both ways, so a
// full ring = fill 1. A faint track shows the empty part. `blink` flashes the whole ring.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform vec4 track : source_color = vec4(1.0, 1.0, 1.0, 0.22);
uniform float inner : hint_range(0.0, 1.0) = 0.72;   // ring band, as a share of the plane's half size
uniform float outer : hint_range(0.0, 1.0) = 0.92;
uniform float blink : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = fwidth(r) * 1.5;
	float band = smoothstep(inner - aa, inner, r) * (1.0 - smoothstep(outer, outer + aa, r));
	// 0 at the near side (towards the camera), 1 at the far side, both ways round.
	float u = abs(atan(p.x, p.y)) / PI;
	float on = 1.0 - smoothstep(fill - 0.01, fill + 0.01, u);
	if (fill <= 0.001) {
		on = 0.0;
	}
	vec4 c = mix(track, color, on);
	c.rgb = mix(c.rgb, vec3(1.0), blink * 0.6);
	ALBEDO = c.rgb;
	ALPHA = c.a * band;
}
