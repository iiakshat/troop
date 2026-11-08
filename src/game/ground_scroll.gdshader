shader_type spatial;
// A tiled ground texture (world-space x/z) that scrolls with the street.

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 3.0;
uniform float offset = 0.0;
uniform vec3 tint : source_color = vec3(1.0);
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = texture(tex, vec2(wpos.x, wpos.z - offset) / tile_m).rgb * tint;
	ROUGHNESS = 0.9;
}
