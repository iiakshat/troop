shader_type spatial;
render_mode cull_back, specular_disabled;
// Animates Humanoid meshes per instance. INSTANCE_CUSTOM:
//   r = phase (0..1), g = white hit flash, b = run amount (0 stand, 1 run), a = aim (right arm forward)

uniform float run_freq = 11.0;
varying float v_flash;

void vertex() {
	float part = UV.x;
	float pivot = UV.y;
	float phase = INSTANCE_CUSTOM.r * 6.2831;
	float run = INSTANCE_CUSTOM.b;
	float aim = INSTANCE_CUSTOM.a;
	float s = sin(TIME * run_freq + phase);
	float ang = 0.0;
	if (part > 0.5 && part < 1.5) {
		ang = s * 0.75 * run;
	} else if (part > 1.5 && part < 2.5) {
		ang = -s * 0.75 * run;
	} else if (part > 2.5 && part < 3.5) {
		ang = -s * 0.6 * run;
	} else if (part > 3.5) {
		ang = mix(s * 0.6 * run, 1.45 + sin(TIME * 17.0 + phase) * 0.12, aim);
	}
	if (part > 0.5) {
		vec3 p = VERTEX;
		p.y -= pivot;
		float c = cos(ang);
		float sn = sin(ang);
		p = vec3(p.x, p.y * c - p.z * sn, p.y * sn + p.z * c);
		p.y += pivot;
		VERTEX = p;
	}
	if (part > -0.5) {
		VERTEX.y += abs(s) * 0.08 * run;
	}
	v_flash = INSTANCE_CUSTOM.g;
}

void fragment() {
	ALBEDO = mix(COLOR.rgb, vec3(1.0, 1.0, 1.0), v_flash);
}
