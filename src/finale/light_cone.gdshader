shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Faint visible beam of a spotlight: brightest along the middle, fading at the silhouette
// and towards the far end so it never shows a hard line where it meets the wall.

uniform vec3 color : source_color = vec3(1.0, 0.88, 0.68);
uniform float strength = 0.08;
uniform float height = 5.0;

varying float along;

void vertex() {
	along = 0.5 - VERTEX.y / height;   // 0 at the lamp, 1 at the wall
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = pow(facing, 2.5) * (1.0 - smoothstep(0.8, 1.0, along)) * smoothstep(0.0, 0.08, along);
	ALBEDO = color * a * strength;
}
