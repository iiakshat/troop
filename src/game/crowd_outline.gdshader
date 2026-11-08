shader_type spatial;
render_mode unshaded, cull_front;
// Ink outline for VAT crowds: the same posed mesh, pushed out along its normals and drawn
// back faces only (inverted hull). Used as next_pass of crowd_vat.gdshader.

uniform sampler2D vat : filter_nearest;
uniform sampler2D nrm : filter_nearest;
uniform float width = 0.028;
uniform vec3 ink : source_color = vec3(0.09, 0.07, 0.12);
varying float v_gone;

void vertex() {
	int vid = int(UV2.x + 0.5);
	ivec2 ra = ivec2(vid, int(INSTANCE_CUSTOM.r + 0.5));
	ivec2 rb = ivec2(vid, int(INSTANCE_CUSTOM.g + 0.5));
	vec3 p = mix(texelFetch(vat, ra, 0).xyz, texelFetch(vat, rb, 0).xyz, INSTANCE_CUSTOM.b);
	vec3 n = normalize(mix(texelFetch(nrm, ra, 0).xyz, texelFetch(nrm, rb, 0).xyz, INSTANCE_CUSTOM.b) * 2.0 - 1.0);
	VERTEX = p + n * width;
	v_gone = INSTANCE_CUSTOM.a < -0.05 ? 1.0 : 0.0;   // dissolving bodies lose the outline
}

void fragment() {
	if (v_gone > 0.5) {
		discard;
	}
	ALBEDO = ink;
}
