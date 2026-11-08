class_name Fx
extends Node3D
## Pooled visual effects: projectiles (knives, bullets, tracers), cube particles and
## floating numbers. All MultiMesh based, so a big fight costs a handful of draw calls.

const MAX_PROJ := 320
const MAX_PARTS := 600

var font: Font

var _proj: Array = []      # {pos, vel, t, kind, spin}
var _parts: Array = []     # {pos, vel, t, life, col, size, grav}
var _knife_mm: MultiMesh
var _bullet_mm: MultiMesh
var _part_mm: MultiMesh
var _labels: Array[Label3D] = []
var _label_state: Array = []
var scroll_speed := 0.0    # particles on the ground drift with the road
var _trail := Color.TRANSPARENT


func _ready() -> void:
	_knife_mm = _mm(_knife_mesh(), MAX_PROJ, false, _lit_vertex_mat())
	_bullet_mm = _mm(_bullet_mesh(), MAX_PROJ, false, _unshaded_vertex_mat())
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	_part_mm = _mm(cube, MAX_PARTS, true, _unshaded_instance_mat())


## Knife skin cosmetic: blade colour and an optional particle trail ("" = none).
func set_knife_skin(blade: Color, trail: String) -> void:
	_knife_mm.mesh = _knife_mesh(blade)
	_trail = Color(trail) if trail != "" else Color.TRANSPARENT


func clear() -> void:
	_proj.clear()
	_parts.clear()
	for i in _labels.size():
		_labels[i].visible = false
		_label_state[i]["t"] = 0.0


# ---------------------------------------------------------------- projectiles

## Fires from `from` to `to`; returns the flight time so callers can sync impacts.
func shoot(kind: String, from: Vector3, to: Vector3, speed := 48.0) -> float:
	if _proj.size() >= MAX_PROJ:
		return 0.0
	var d := to - from
	var t := maxf(d.length() / speed, 0.05)
	_proj.append({"pos": from, "vel": d / t, "t": t, "kind": kind, "spin": randf() * TAU})
	return t


# ---------------------------------------------------------------- particles

func burst(at: Vector3, color: Color, n: int, speed := 4.0, size := 0.18, life := 0.5, up := 3.0, grav := 14.0) -> void:
	for i in n:
		if _parts.size() >= MAX_PARTS:
			_parts.pop_front()
		var dir := Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)).normalized()
		_parts.append({"pos": at, "vel": dir * speed * randf_range(0.5, 1.0) + Vector3.UP * up * randf(),
			"t": 0.0, "life": life * randf_range(0.7, 1.2), "col": color, "size": size * randf_range(0.7, 1.3), "grav": grav})


func puff(at: Vector3) -> void:
	burst(at + Vector3(0, 0.8, 0), Color(0.95, 0.95, 0.95), 5, 2.5, 0.28, 0.45, 1.5, 3.0)
	burst(at + Vector3(0, 0.8, 0), Color(1.0, 0.85, 0.3), 2, 5.0, 0.12, 0.3, 3.0, 12.0)


func explosion(at: Vector3, scale := 1.0) -> void:
	burst(at, Color(1.0, 0.75, 0.2), int(30 * scale), 9.0 * scale, 0.4, 0.7, 6.0, 9.0)
	burst(at, Color(1.0, 0.35, 0.15), int(20 * scale), 7.0 * scale, 0.5, 0.6, 4.0, 6.0)
	burst(at, Color(0.35, 0.35, 0.38), int(18 * scale), 4.0 * scale, 0.7, 1.0, 5.0, 2.0)


func confetti(at: Vector3, n := 40) -> void:
	var cols := [Color("2fd17a"), Color("f2c14e"), Color("3b82f6"), Color("ffffff"), Color("ff5d8f")]
	for i in n:
		burst(at, cols[i % cols.size()], 1, 7.0, 0.16, 1.1, 6.0, 9.0)


# ---------------------------------------------------------------- floating text

func float_text(text: String, at: Vector3, color: Color, size := 1.0, rise := 2.4, dur := 1.0) -> void:
	var idx := -1
	for i in _labels.size():
		if not _labels[i].visible:
			idx = i
			break
	if idx < 0:
		if _labels.size() >= 24:
			idx = 0
		else:
			var l := Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.render_priority = 10
			l.outline_render_priority = 9
			l.font = font
			l.font_size = 96
			l.outline_size = 22
			l.outline_modulate = Color(0.05, 0.05, 0.08)
			l.pixel_size = 0.01
			add_child(l)
			_labels.append(l)
			_label_state.append({})
			idx = _labels.size() - 1
	var lab := _labels[idx]
	lab.text = text
	lab.modulate = color
	lab.position = at
	lab.visible = true
	_label_state[idx] = {"t": 0.0, "dur": dur, "rise": rise, "size": size, "base": at}


# ---------------------------------------------------------------- tick

func _process(delta: float) -> void:
	_tick_proj(delta)
	_tick_parts(delta)
	_tick_labels(delta)


func _tick_proj(delta: float) -> void:
	var kn := 0
	var bn := 0
	var i := 0
	while i < _proj.size():
		var p: Dictionary = _proj[i]
		p["t"] = float(p["t"]) - delta
		if float(p["t"]) <= 0.0:
			_proj.remove_at(i)
			continue
		p["pos"] = (p["pos"] as Vector3) + (p["vel"] as Vector3) * delta
		var vel: Vector3 = p["vel"]
		var basis := Basis.looking_at(vel.normalized(), Vector3.UP) if vel.length() > 0.01 else Basis()
		if p["kind"] == "knife":
			p["spin"] = float(p["spin"]) + delta * 28.0
			if _trail.a > 0.0 and randf() < 0.6:
				burst(p["pos"], _trail, 1, 0.4, 0.1, 0.25, 0.0, 0.0)
			basis = basis * Basis(Vector3.RIGHT, float(p["spin"]))
			_knife_mm.set_instance_transform(kn, Transform3D(basis, p["pos"]))
			kn += 1
		else:
			var sc := 1.6 if p["kind"] == "bullet_big" else (1.0 if p["kind"] == "bullet" else 0.8)
			_bullet_mm.set_instance_transform(bn, Transform3D(basis.scaled(Vector3(sc, sc, sc)), p["pos"]))
			bn += 1
		i += 1
	_knife_mm.visible_instance_count = kn
	_bullet_mm.visible_instance_count = bn


func _tick_parts(delta: float) -> void:
	var n := 0
	var i := 0
	while i < _parts.size():
		var p: Dictionary = _parts[i]
		p["t"] = float(p["t"]) + delta
		if float(p["t"]) >= float(p["life"]):
			_parts.remove_at(i)
			continue
		var v: Vector3 = p["vel"]
		v.y -= float(p["grav"]) * delta
		v *= 1.0 - minf(delta * 1.5, 0.5)
		p["vel"] = v
		var pos: Vector3 = p["pos"] + v * delta
		pos.z += scroll_speed * delta
		if pos.y < 0.05:
			pos.y = 0.05
			v.y = absf(v.y) * 0.3
			p["vel"] = v
		p["pos"] = pos
		var k := 1.0 - float(p["t"]) / float(p["life"])
		var s := float(p["size"]) * (0.4 + 0.6 * k)
		_part_mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(s, s, s)), pos))
		var c: Color = p["col"]
		_part_mm.set_instance_color(n, c)
		n += 1
		i += 1
	_part_mm.visible_instance_count = n


func _tick_labels(delta: float) -> void:
	for i in _labels.size():
		var lab := _labels[i]
		if not lab.visible:
			continue
		var st: Dictionary = _label_state[i]
		st["t"] = float(st["t"]) + delta
		var k := float(st["t"]) / float(st["dur"])
		if k >= 1.0:
			lab.visible = false
			continue
		var pop := 1.0 + 0.6 * maxf(0.0, 1.0 - k * 6.0)
		lab.scale = Vector3.ONE * float(st["size"]) * pop
		lab.position = (st["base"] as Vector3) + Vector3(0, float(st["rise"]) * ease(k, 0.4), 0)
		var c := lab.modulate
		c.a = 1.0 if k < 0.7 else 1.0 - (k - 0.7) / 0.3
		lab.modulate = c
		var oc := lab.outline_modulate
		oc.a = c.a
		lab.outline_modulate = oc


# ---------------------------------------------------------------- meshes / materials

func _mm(mesh: Mesh, cap: int, colors: bool, mat: Material) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-60, -5, -200), Vector3(120, 60, 260))
	add_child(mi)
	return mm


func _knife_mesh(blade := Color(0.92, 0.95, 1.0)) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cube(st, Vector3(0, 0, -0.28), Vector3(0.1, 0.18, 0.66), blade)
	_cube(st, Vector3(0, 0, 0.2), Vector3(0.13, 0.2, 0.32), Color(0.35, 0.22, 0.12))
	st.generate_normals()
	return st.commit()


func _bullet_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cube(st, Vector3.ZERO, Vector3(0.15, 0.15, 1.1), Color(1.0, 0.9, 0.4))
	return st.commit()


static func _cube(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var v := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	for f in [[0, 3, 2, 1], [5, 6, 7, 4], [4, 7, 3, 0], [1, 2, 6, 5], [3, 7, 6, 2], [4, 0, 1, 5]]:
		for tri in [[0, 2, 1], [0, 3, 2]]:
			for k in tri:
				st.set_color(col)
				st.add_vertex(c + v[f[k]])


static func _lit_vertex_mat() -> Material:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.4
	return m


static func _unshaded_vertex_mat() -> Material:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _unshaded_instance_mat() -> Material:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
