shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// Night neon tubes on the facades: the vertex colour times `energy` (above 1 it blooms).
// One mesh per building, set up by World._add_neon; energy comes from the district theme.

uniform float energy = 3.0;

void fragment() {
	ALBEDO = COLOR.rgb * energy;
}
