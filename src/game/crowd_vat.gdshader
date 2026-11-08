shader_type spatial;
render_mode cull_back;
// Vertex-animation-texture crowd shader with cartoon lighting. Each vertex stores its index
// in UV2.x; the pose for this instance comes from two rows of `vat` (positions) and `nrm`
// (smooth normals), one row per baked frame, blended.
// INSTANCE_CUSTOM: r = row A, g = row B, b = blend A->B,
//   a = white hit flash (0..1), or a dissolve amount when negative (-1 = fully gone).

uniform sampler2D vat : filter_nearest;
uniform sampler2D nrm : filter_nearest;
uniform float rim_strength = 0.22;
varying float v_flash;
varying float v_dissolve;
varying vec3 v_local;

void vertex() {
	int vid = int(UV2.x + 0.5);
	ivec2 ra = ivec2(vid, int(INSTANCE_CUSTOM.r + 0.5));
	ivec2 rb = ivec2(vid, int(INSTANCE_CUSTOM.g + 0.5));
	VERTEX = mix(texelFetch(vat, ra, 0).xyz, texelFetch(vat, rb, 0).xyz, INSTANCE_CUSTOM.b);
	vec3 n = mix(texelFetch(nrm, ra, 0).xyz, texelFetch(nrm, rb, 0).xyz, INSTANCE_CUSTOM.b) * 2.0 - 1.0;
	NORMAL = normalize(n);
	v_flash = max(INSTANCE_CUSTOM.a, 0.0);
	v_dissolve = max(-INSTANCE_CUSTOM.a, 0.0);
	v_local = VERTEX;
}

float hash(vec3 p) {
	return fract(sin(dot(floor(p * 9.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void fragment() {
	if (v_dissolve > 0.0 && hash(v_local) < v_dissolve) {
		discard;
	}
	// Baked vertex colours are sRGB; lighting works in linear.
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = mix(base, vec3(1.0), v_flash);
	ROUGHNESS = 0.8;
	SPECULAR = 0.0;
	// Bright rim on the silhouette makes figures pop off the road.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = base * rim * rim_strength + vec3(v_flash * 0.6);
}

void light() {
	// Two clean tones plus a soft highlight band: the textured-cartoon look.
	float ndl = dot(NORMAL, LIGHT);
	float tone = smoothstep(-0.02, 0.08, ndl) * 0.75 + smoothstep(0.62, 0.7, ndl) * 0.25;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (0.1 + tone) / PI;
}
