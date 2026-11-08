shader_type spatial;
render_mode specular_disabled;
// Plain box building with a window grid drawn procedurally from local position.

uniform vec3 base : source_color = vec3(0.9, 0.85, 0.78);
uniform vec3 size = vec3(8.0, 12.0, 8.0);
varying vec3 lpos;
varying vec3 lnorm;

void vertex() {
	lpos = VERTEX + size * 0.5;
	lnorm = NORMAL;
}

void fragment() {
	vec3 col = base;
	vec2 uv;
	if (abs(lnorm.x) > 0.5) {
		uv = vec2(lpos.z, lpos.y);
	} else if (abs(lnorm.z) > 0.5) {
		uv = vec2(lpos.x, lpos.y);
	} else {
		uv = vec2(-1.0);
	}
	if (uv.x >= 0.0 && uv.y > 2.4) {
		vec2 cell = fract(uv / vec2(2.0, 2.6));
		float win = step(0.25, cell.x) * step(cell.x, 0.75) * step(0.25, cell.y) * step(cell.y, 0.8);
		vec2 id = floor(uv / vec2(2.0, 2.6));
		float lit = fract(sin(dot(id, vec2(12.9898, 78.233))) * 43758.5453);
		vec3 glass = mix(vec3(0.33, 0.45, 0.58), vec3(0.55, 0.68, 0.8), lit);
		col = mix(col, glass, win);
	}
	if (uv.x >= 0.0 && uv.y < 2.4) {
		col *= 0.82; // darker ground floor band
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
