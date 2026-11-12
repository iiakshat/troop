shader_type spatial;
// The squad's shield in the street (src/game/shield_bubble.gd): a clear bubble sitting on the
// road, a unit sphere scaled to the formation (the road hides what is below it). Fresnel rim
// (clear centre, so troops keep their true colours; a bright cyan-white edge), a glow where it
// meets the road, a hex lattice and a scan band that drift slowly, a gentle pulse, white
// ripples where blocked fire hits it, and a flash on pop-in and burst.
// Cheap on Forward Mobile and Compatibility: one unshaded draw, no screen or depth texture
// reads. Both walls are drawn: the far wall (behind the squad, hidden where the troops stand)
// is the side gangs shoot at, so their ripples show there. Every number comes from config/world_look.json "shield_bubble".
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 rim_color : source_color = vec4(0.5, 0.95, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power = 2.6;
uniform float rim_alpha = 0.85;
uniform float rim_top = 0.5;         // rim strength over the top (share of the sides')
uniform float base_alpha = 0.03;
uniform float contact = 0.6;         // glow where the bubble meets the road
uniform float contact_m = 0.12;      // its height (m)
uniform float hex_cells = 14.0;      // hex cells around the bubble (whole number: no seam)
uniform float hex_alpha = 0.22;
uniform float scan_speed = 0.45;     // scan bands per second climbing the bubble
uniform float pulse_hz = 1.2;
uniform float pulse = 0.12;
uniform float t = 0.0;               // the street's clock (stops with pause and lesson holds)
uniform float fade = 1.0;            // pop-in, honest last-second blink, burst
uniform float flash = 0.0;           // white flash on pop-in and burst
uniform float hit_reach = 0.9;       // how far a ripple runs over the unit sphere
uniform float hit_width = 0.12;
uniform float back_wall = 0.6;       // the far wall's strength (ripples keep theirs)
uniform vec4 hits[4];                // xyz = point on the unit sphere, w = age 0..1 (1 = none)

varying vec3 v_local;
varying float v_height;

void vertex() {
	v_local = VERTEX;
	v_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

// Distance from the centre of the nearest hex cell (0 in the middle, 0.5 on an edge).
float hex_dist(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - hc.xy * s, p - (hc.zw + 0.5) * s);
	vec2 g = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? h.xy : h.zw;
	vec2 a = abs(g);
	return max(dot(a, s * 0.5), a.x);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float facing = clamp(abs(dot(n, normalize(VIEW))), 0.0, 1.0);
	float fres = 1.0 - facing;
	float rim = pow(fres, rim_power);
	vec3 d = normalize(v_local);
	// Softer over the top, where the far edge passes over the heads of the front rank.
	rim *= mix(1.0, rim_top, smoothstep(0.35, 0.95, d.y));
	float beat = 1.0 + pulse * sin(t * pulse_hz * 6.2831853);

	// Hex lattice (around x elevation), drifting slowly, seen mostly towards the rim.
	float around = atan(d.z, d.x) / 6.2831853 + 0.5;
	float up = asin(clamp(d.y, -1.0, 1.0)) / 1.5707963;   // -1 bottom .. 1 top
	vec2 hp = vec2(around * hex_cells, up * hex_cells * 0.3 - t * 0.15);
	float edge = smoothstep(0.40, 0.48, hex_dist(hp));
	// A bright scan band climbs from the road over the top and lights the lattice it passes.
	float band = fract(t * scan_speed) * 1.6 - 0.4;
	float scan = exp(-pow((up - band) / 0.09, 2.0));
	float lattice = edge * hex_alpha * (0.2 + 0.8 * smoothstep(0.2, 0.8, fres)) * (0.55 + 1.6 * scan);
	lattice *= 1.0 - smoothstep(0.55, 0.85, d.y);   // no pinched cells round the top pole
	float wall = FRONT_FACING ? 1.0 : back_wall;   // the far wall is fainter

	// Where it meets the road: a bright seam, so it stands on the street.
	float seam = contact * exp(-pow(v_height / contact_m, 2.0));

	// Ripples where blocked fire hit: a white ring running out from the hit, and a core flash.
	float ripple = 0.0;
	for (int i = 0; i < 4; i++) {
		float age = hits[i].w;
		if (age < 1.0) {
			float dist = distance(d, hits[i].xyz);
			float k = 1.0 - age;
			float ring = exp(-pow((dist - age * hit_reach) / hit_width, 2.0));
			float core = exp(-dist * dist / 0.03) * k * k;
			ripple += ring * k + core;
		}
	}
	ripple = min(ripple, 1.5);

	float a = (base_alpha + rim * rim_alpha * beat + lattice + seam * beat) * wall + ripple * 0.9 + flash * (0.25 + 0.6 * rim);
	vec3 col = mix(rim_color.rgb, edge_color.rgb, clamp(rim * rim * 1.3 + ripple + flash * 0.8 + seam * 0.5, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * fade;
}
