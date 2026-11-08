class_name Crowd
extends MultiMeshInstance3D
## One MultiMesh per character type. Fill it every frame: begin(), push()..., finish().

const SHADER := preload("res://src/game/crowd.gdshader")

static var _material: ShaderMaterial

var _n := 0
var _cap := 0


func setup(kind: String, capacity: int) -> Crowd:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	_cap = capacity
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true  # compat renderer multiplies vertex colour by instance colour
	mm.mesh = Humanoid.mesh(kind)
	mm.instance_count = capacity
	for i in capacity:
		mm.set_instance_color(i, Color.WHITE)
	mm.visible_instance_count = 0
	multimesh = mm
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-60, -5, -200), Vector3(120, 40, 260))
	name = "Crowd_" + kind
	return self


func begin() -> void:
	_n = 0


func push(xf: Transform3D, custom: Color) -> void:
	if _n >= _cap:
		return
	multimesh.set_instance_transform(_n, xf)
	multimesh.set_instance_custom_data(_n, custom)
	_n += 1


func finish() -> void:
	multimesh.visible_instance_count = _n
