shader_type spatial;
render_mode cull_back, specular_disabled;
// Vertex-animation-texture crowd shader. Each vertex stores its index in UV2.x; the pose
// for this instance comes from two rows of `vat` (one per baked frame), blended.
// INSTANCE_CUSTOM: r = row A, g = row B, b = blend A->B, a = white hit flash.
// Normals are not baked: flat facets are rebuilt per pixel from screen derivatives,
// which also gives the low-poly look.

uniform sampler2D vat : filter_nearest;
varying float v_flash;

void vertex() {
	int vid = int(UV2.x + 0.5);
	vec3 a = texelFetch(vat, ivec2(vid, int(INSTANCE_CUSTOM.r + 0.5)), 0).xyz;
	vec3 b = texelFetch(vat, ivec2(vid, int(INSTANCE_CUSTOM.g + 0.5)), 0).xyz;
	VERTEX = mix(a, b, INSTANCE_CUSTOM.b);
	v_flash = INSTANCE_CUSTOM.a;
}

void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	ALBEDO = mix(COLOR.rgb, vec3(1.0), v_flash);
}
