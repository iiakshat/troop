shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// Stylised glass: tinted body, bright fresnel rim, a fake sky/studio reflection and two
// vertical highlight strips. Works on the Compatibility renderer (no screen textures).

uniform vec4 tint : source_color = vec4(0.25, 0.6, 0.35, 0.32);
uniform vec3 sky_top : source_color = vec3(0.45, 0.65, 0.95);
uniform vec3 horizon : source_color = vec3(0.95, 0.97, 1.0);
uniform vec3 ground : source_color = vec3(0.35, 0.33, 0.3);

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float fres = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 3.0);
	vec3 r = reflect(-v, n);
	vec3 rw = normalize((INV_VIEW_MATRIX * vec4(r, 0.0)).xyz);
	vec3 env = rw.y > 0.0 ? mix(horizon, sky_top, clamp(rw.y * 1.6, 0.0, 1.0)) : mix(horizon, ground, clamp(-rw.y * 2.0, 0.0, 1.0));
	// Studio softbox strips: bright bands where the reflection points left/right.
	float strip = smoothstep(0.80, 0.95, abs(rw.x)) * smoothstep(-0.2, 0.3, rw.y);
	vec3 col = mix(tint.rgb * 0.7, env, 0.25 + 0.75 * fres) + strip * 1.2;
	ALBEDO = vec3(0.0);
	EMISSION = col;
	ROUGHNESS = 0.04;
	SPECULAR = 0.9;
	ALPHA = clamp(tint.a + fres * 0.55 + strip * 0.6, 0.0, 1.0);
}
