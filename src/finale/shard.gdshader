shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Flying glass shards (one MultiMesh per broken bottle). Mostly clear, with bright cut edges,
// a fresnel sheen and sharp glints as they tumble. INSTANCE_CUSTOM.r fades a shard out,
// .g gives each shard its own twinkle phase. Unshaded: the studio light is baked into the
// glints here (cheaper on phones, and lit-transparent emission came out black on Mobile).

uniform vec3 tint : source_color = vec3(0.8, 0.95, 0.9);
varying float fade;
varying float phase;

void vertex() {
	fade = INSTANCE_CUSTOM.r;
	phase = INSTANCE_CUSTOM.g;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float ndv = abs(dot(n, v));
	float fres = pow(1.0 - ndv, 3.0);
	float edge = min(min(UV.x, UV.y), 1.0 - UV.x - UV.y);
	float e = 1.0 - smoothstep(0.015, 0.11, edge);
	vec3 rw = normalize((INV_VIEW_MATRIX * vec4(reflect(-v, n), 0.0)).xyz);
	float glint = pow(max(dot(rw, normalize(vec3(0.35, 0.8, 0.45))), 0.0), 24.0);
	glint += pow(max(dot(rw, normalize(vec3(-0.4, 0.75, 0.5))), 0.0), 40.0) * 0.6;
	glint *= 0.55 + 0.45 * sin(TIME * 9.0 + phase * 6.2832);
	// Clear glass: the body barely shows, the cut edges and glints carry the shape.
	vec3 pale = mix(tint, vec3(1.0), 0.4);
	vec3 col = pale * (0.55 + e * 1.1) + vec3(1.0, 0.97, 0.9) * (glint * 3.0 + fres * 0.9);
	ALBEDO = col;
	ALPHA = clamp(0.1 + e * 0.8 + glint * 0.9 + fres * 0.4, 0.0, 1.0) * fade;
}
