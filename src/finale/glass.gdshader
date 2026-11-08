shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;
// Glass bottle: refracts the scene behind it (screen texture, bent by the surface normal),
// tints it, and adds fresnel reflections of a warm studio plus two softbox strips.

uniform vec4 tint : source_color = vec4(0.25, 0.6, 0.35, 0.32);
uniform float refraction = 0.045;
uniform vec3 studio_top : source_color = vec3(1.0, 0.92, 0.78);
uniform vec3 studio_low : source_color = vec3(0.25, 0.16, 0.1);
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 2.6);
	vec2 bend = n.xy * refraction * (0.4 + (1.0 - ndv));
	vec3 behind = textureLod(screen, SCREEN_UV - bend, 1.0).rgb;
	vec3 rw = normalize((INV_VIEW_MATRIX * vec4(reflect(-v, n), 0.0)).xyz);
	vec3 env = mix(studio_low, studio_top, smoothstep(-0.3, 0.6, rw.y));
	float strip = smoothstep(0.82, 0.96, abs(rw.x)) * smoothstep(-0.1, 0.4, rw.y);
	float spot = pow(clamp(dot(rw, normalize(vec3(0.4, 0.8, 0.45))), 0.0, 1.0), 60.0);
	vec3 glass = behind * mix(vec3(1.0), tint.rgb * 1.6, 0.75) * (0.75 + tint.a);
	vec3 col = mix(glass, env, fres * 0.8) + (strip * 1.3 + spot * 3.0) * studio_top;
	ALBEDO = vec3(0.0);
	EMISSION = col;
	ROUGHNESS = 0.03;
	SPECULAR = 0.9;
	ALPHA = 1.0;
}
