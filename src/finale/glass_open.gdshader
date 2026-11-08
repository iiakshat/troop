shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;
// Broken pieces (the stump left on the shelf, the flying neck): open shells, so both sides
// draw. Shading lives in glass.gdshaderinc.

#include "res://src/finale/glass.gdshaderinc"
