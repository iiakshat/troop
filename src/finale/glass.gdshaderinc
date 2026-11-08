// Shared bottle-glass shading (included by glass.gdshader and glass_open.gdshader).
// Refracts the scene behind (screen texture, bent more towards the rim like a lens, with a
// touch of colour dispersion), absorbs light by path length (thick, saturated rims), reflects
// a warm studio with two softbox strips, draws the bright inner rim of the far wall and a
// caustic smear where the round body focuses the key light.

uniform vec4 tint : source_color = vec4(0.25, 0.6, 0.35, 0.32);   // rgb glass colour, a = density
uniform vec3 caustic_color : source_color = vec3(1.0, 0.8, 0.5);
uniform float refraction = 0.05;
uniform float thickness = 1.0;
uniform float caustic = 0.6;
uniform float sparkle = 0.0;          // > 0: a glint sweeps across now and then (the gold bottle)
uniform float body_top = 0.33;         // local height where the shoulder starts (caustic stays below)
uniform vec3 studio_top : source_color = vec3(1.0, 0.93, 0.8);
uniform vec3 studio_low : source_color = vec3(0.22, 0.14, 0.09);
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float rimw = 1.0 - ndv;
	float fres = 0.04 + 0.96 * pow(rimw, 4.0);
	// Light crosses two walls; at the rim the path through the glass is much longer.
	float path = thickness / max(ndv, 0.14);
	vec3 absorb = pow(clamp(tint.rgb, vec3(0.03), vec3(1.0)), vec3(path * tint.a * 1.6));
	// A round bottle is a lens: the background bends more towards the edges.
	vec2 bend = n.xy * refraction * (0.3 + 1.6 * rimw);
	float lod = 0.5 + 2.0 * rimw;
	vec3 behind;
	behind.r = textureLod(screen, SCREEN_UV - bend * 1.06, lod).r;
	behind.g = textureLod(screen, SCREEN_UV - bend, lod).g;
	behind.b = textureLod(screen, SCREEN_UV - bend * 0.94, lod).b;
	vec3 rw = normalize((INV_VIEW_MATRIX * vec4(reflect(-v, n), 0.0)).xyz);
	vec3 env = mix(studio_low, studio_top, smoothstep(-0.35, 0.7, rw.y));
	float strips = smoothstep(0.78, 0.94, abs(rw.x)) * smoothstep(-0.25, 0.25, rw.y) * (1.0 - smoothstep(0.7, 0.95, rw.y));
	float spot = pow(clamp(dot(rw, normalize(vec3(0.45, 0.75, 0.5))), 0.0, 1.0), 110.0);
	float spot2 = pow(clamp(dot(rw, normalize(vec3(-0.5, 0.7, 0.5))), 0.0, 1.0), 60.0) * 0.5;
	// The far wall's edge, seen through the near one: a thin bright line inside the silhouette.
	float rim = smoothstep(0.1, 0.2, ndv) * (1.0 - smoothstep(0.22, 0.36, ndv));
	// Caustic: the body focuses the key light into a bright smear on the side away from it.
	float c = smoothstep(0.15, 0.65, -n.x) * smoothstep(0.25, 0.6, ndv) * (1.0 - smoothstep(body_top - 0.08, body_top, lpos.y)) * smoothstep(0.02, 0.1, lpos.y);
	vec3 col = behind * absorb * (1.05 + tint.a * 0.4);
	col = mix(col, env, fres * 0.85);
	col += (strips * 1.2 + spot * 3.5 + spot2) * studio_top;
	col += rim * 0.22 * studio_top * mix(vec3(1.0), tint.rgb, 0.5);
	col += c * caustic * caustic_color;
	if (sparkle > 0.0) {
		float sweep = fract(TIME * 0.45);
		float band = 1.0 - smoothstep(0.0, 0.05, abs((lpos.y * 1.6 + lpos.x * 2.0) - (sweep * 2.6 - 0.6)));
		col += band * sparkle * vec3(1.0, 0.9, 0.6) * smoothstep(0.2, 0.6, ndv);
	}
	ALBEDO = vec3(0.0);
	EMISSION = col;
	ROUGHNESS = 0.03;
	SPECULAR = 0.7;
	ALPHA = 1.0;
}
