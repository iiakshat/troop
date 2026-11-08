class_name Crowd
extends MultiMeshInstance3D
## One MultiMesh per character role, animated on the GPU from a baked vertex-animation
## texture (tools/bake_vat.gd). Fill it every frame: begin(), push()..., finish().
## push() takes a clip name and that figure's time in the clip; the crowd turns it into
## texture rows so the shader can pose the mesh.

const SHADER := preload("res://src/game/crowd_vat.gdshader")
const OUTLINE := preload("res://src/game/crowd_outline.gdshader")
const DIR := "res://assets/characters/"

static var clips: Dictionary = {}

var _n := 0
var _cap := 0


func setup(kind: String, capacity: int) -> Crowd:
	if clips.is_empty():
		clips = Config.load_json(DIR + "clips.json")
	_cap = capacity
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var vat: Texture2D = load(DIR + kind + "_vat.res")
	var nrm: Texture2D = load(DIR + kind + "_nrm.res")
	mat.set_shader_parameter("vat", vat)
	mat.set_shader_parameter("nrm", nrm)
	var ink := ShaderMaterial.new()
	ink.shader = OUTLINE
	ink.set_shader_parameter("vat", vat)
	ink.set_shader_parameter("nrm", nrm)
	mat.next_pass = ink
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true  # compat renderer multiplies vertex colour by instance colour
	mm.mesh = load(DIR + kind + "_mesh.res")
	mm.instance_count = capacity
	for i in capacity:
		mm.set_instance_color(i, Color.WHITE)
	mm.visible_instance_count = 0
	multimesh = mm
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	custom_aabb = AABB(Vector3(-60, -5, -200), Vector3(120, 40, 260))
	name = "Crowd_" + kind
	return self


## Swaps vertex colours (outfit cosmetics): {from Color: to Color}, matched loosely.
func recolor(map: Dictionary) -> void:
	var arrays := (multimesh.mesh as ArrayMesh).surface_get_arrays(0)
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in cols.size():
		for from in map:
			var f: Color = from
			if absf(cols[i].r - f.r) + absf(cols[i].g - f.g) + absf(cols[i].b - f.b) < 0.03:
				cols[i] = map[from]
	arrays[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	multimesh.mesh = am


func begin() -> void:
	_n = 0


## `t` is seconds into `clip` (looping clips wrap, one-shots hold their last frame).
func push(xf: Transform3D, clip: String, t: float, flash := 0.0) -> void:
	if _n >= _cap:
		return
	multimesh.set_instance_transform(_n, xf)
	multimesh.set_instance_custom_data(_n, pose(clip, t, flash))
	_n += 1


func finish() -> void:
	multimesh.visible_instance_count = _n


static func pose(clip: String, t: float, flash := 0.0) -> Color:
	var c: Dictionary = clips.get(clip, clips.get("idle", {}))
	var frames := int(c.get("frames", 1))
	var row0 := float(c.get("row", 0))
	var length := maxf(float(c.get("length", 1.0)), 0.01)
	var f: float
	var a: int
	var b: int
	if bool(c.get("loop", true)):
		f = fposmod(t / length, 1.0) * frames
		a = int(f) % frames
		b = (a + 1) % frames
	else:
		f = clampf(t / length, 0.0, 1.0) * (frames - 1)
		a = int(f)
		b = mini(a + 1, frames - 1)
	return Color(row0 + a, row0 + b, f - floorf(f), flash)


static func clip_length(clip: String) -> float:
	return float(clips.get(clip, {}).get("length", 1.0))
