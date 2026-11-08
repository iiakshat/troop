shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;
// Whole bottle glass (outer surface only). Shading lives in glass.gdshaderinc.

#include "res://src/finale/glass.gdshaderinc"
