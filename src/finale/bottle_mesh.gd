class_name BottleMesh
extends RefCounted
## Smooth high-detail bottles built by spinning a profile (lathe), plus the glass,
## liquid, label and cap materials. A bottle node's origin is its base centre.

const GLASS := preload("res://src/finale/glass.gdshader")
const SEGMENTS := 32

# (radius, height) from the base up, in metres.
const PROFILE := [
	Vector2(0.0, 0.0), Vector2(0.082, 0.0), Vector2(0.09, 0.012), Vector2(0.09, 0.33), Vector2(0.086, 0.37),
	Vector2(0.066, 0.42), Vector2(0.04, 0.46), Vector2(0.031, 0.5), Vector2(0.03, 0.58), Vector2(0.034, 0.59),
	Vector2(0.034, 0.615), Vector2(0.0, 0.615),
]

static var _glass_mesh: ArrayMesh
static var _liquid_mesh: ArrayMesh
static var _label_mesh: ArrayMesh
static var _cap_mesh: ArrayMesh


static func make(gold: bool, hue: float) -> Node3D:
	_ensure()
	var root := Node3D.new()
	var liquid := MeshInstance3D.new()
	liquid.mesh = _liquid_mesh
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color.from_hsv(hue, 0.75, 0.55) if not gold else Color("e3a51f")
	lm.roughness = 0.2
	lm.metallic_specular = 0.8
	liquid.material_override = lm
	root.add_child(liquid)
	var label := MeshInstance3D.new()
	label.mesh = _label_mesh
	var labm := StandardMaterial3D.new()
	labm.albedo_color = Color.from_hsv(fmod(hue + 0.5, 1.0), 0.35, 0.95) if not gold else Color("fff1b0")
	labm.roughness = 0.8
	label.material_override = labm
	root.add_child(label)
	var cap := MeshInstance3D.new()
	cap.mesh = _cap_mesh
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color("c9a227") if gold else Color("b3282d")
	cm.metallic = 0.7
	cm.roughness = 0.3
	cap.material_override = cm
	root.add_child(cap)
	var glass := MeshInstance3D.new()
	glass.mesh = _glass_mesh
	var gm := ShaderMaterial.new()
	gm.shader = GLASS
	gm.set_shader_parameter("tint", Color(0.95, 0.75, 0.2, 0.4) if gold else Color.from_hsv(hue, 0.55, 0.55, 0.3))
	glass.material_override = gm
	root.add_child(glass)
	return root


static func glass_material(tint: Color) -> ShaderMaterial:
	var gm := ShaderMaterial.new()
	gm.shader = GLASS
	gm.set_shader_parameter("tint", tint)
	return gm


static func _ensure() -> void:
	if _glass_mesh:
		return
	_glass_mesh = _lathe(PROFILE, 1.0, 0.0, 0.615)
	_liquid_mesh = _lathe(PROFILE, 0.9, 0.0, 0.36, true)
	_label_mesh = _band(0.093, 0.12, 0.27)
	_cap_mesh = _band(0.038, 0.585, 0.625, true)


static func _lathe(profile: Array, scale_r: float, y0: float, y1: float, cap_top := false) -> ArrayMesh:
	var pts: Array = []
	for p in profile:
		var v: Vector2 = p
		if v.y <= y1 + 0.0001:
			pts.append(Vector2(v.x * scale_r, v.y))
	if cap_top:
		# Cut at y1 with a flat top: interpolate the radius at the fill line.
		var r_top := 0.0
		for i in profile.size() - 1:
			var a: Vector2 = profile[i]
			var b: Vector2 = profile[i + 1]
			if a.y <= y1 and b.y >= y1 and b.y > a.y:
				r_top = lerpf(a.x, b.x, (y1 - a.y) / (b.y - a.y)) * scale_r
		pts.append(Vector2(r_top, y1))
		pts.append(Vector2(0.0, y1))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		for s in SEGMENTS:
			var t0 := TAU * s / SEGMENTS
			var t1 := TAU * (s + 1) / SEGMENTS
			var a0 := Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x)
			var a1 := Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x)
			var b0 := Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x)
			var b1 := Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x)
			for v in [a0, b0, b1, a0, b1, a1]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func _band(r: float, y0: float, y1: float, closed := false) -> ArrayMesh:
	var prof: Array = [Vector2(r, y0), Vector2(r, y1)]
	if closed:
		prof = [Vector2(0, y0), Vector2(r, y0), Vector2(r, y1), Vector2(0, y1)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in prof.size() - 1:
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[i + 1]
		for s in SEGMENTS:
			var t0 := TAU * s / SEGMENTS
			var t1 := TAU * (s + 1) / SEGMENTS
			var a0 := Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x)
			var a1 := Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x)
			var b0 := Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x)
			var b1 := Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x)
			for v in [a0, b0, b1, a0, b1, a1]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()
