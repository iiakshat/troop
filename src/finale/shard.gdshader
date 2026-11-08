shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx, shadows_disabled;
// Flying glass shards (one MultiMesh per broken bottle). Mostly clear, with bright cut edges,
// a fresnel sheen and sharp glints as they tumble. INSTANCE_CUSTOM.r fades a shard out.

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
	float e = 1.0 - smoothstep(0.02, 0.14, edge);
	vec3 rw = normalize((INV_VIEW_MATRIX * vec4(reflect(-v, n), 0.0)).xyz);
	float glint = pow(max(dot(rw, normalize(vec3(0.35, 0.8, 0.45))), 0.0), 24.0);
	glint += pow(max(dot(rw, normalize(vec3(-0.4, 0.75, 0.5))), 0.0), 40.0) * 0.6;
	// Clear glass: the body barely shows, the cut edges and glints carry the shape.
	vec3 pale = mix(tint, vec3(1.0), 0.45);
	vec3 col = pale * (1.1 + e * 1.6) + vec3(1.0, 0.97, 0.9) * (glint * 3.5 + fres * 1.2);
	ALBEDO = vec3(0.0);
	EMISSION = col;
	ROUGHNESS = 0.05;
	SPECULAR = 0.8;
	ALPHA = clamp(0.12 + e * 0.85 + glint * 0.9 + fres * 0.45, 0.0, 1.0) * fade;
}
