shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Soft additive light blob on a quad: the caustic a bottle throws on the wall, the gold
// bottle's halo, a lamp's pool of light. `stretch` squashes it into an oval; `pulse` breathes.
// fog_disabled: fog on an additive quad adds the fog colour over the whole quad, which showed
// as a pale rectangle behind every bottle.

uniform vec3 color : source_color = vec3(1.0, 0.8, 0.4);
uniform float strength = 1.0;
uniform float pulse = 0.0;
uniform float falloff = 2.0;

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = pow(clamp(1.0 - d, 0.0, 1.0), falloff);
	float k = 1.0 + pulse * sin(TIME * 3.0);
	ALBEDO = color * a * strength * k;
}
