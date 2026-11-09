class_name FinaleKnife
extends RefCounted
## The hero's throwing knife as seen up close in Bottle Shot: a ground steel blade (in the
## player's knife-skin colour), a dark guard, a cord-wrapped handle and a ring pommel.
## Local frame: the tip points down -Z at distance TIP, the blade's flat faces +-X, so a spin
## about X is the classic end-over-end tumble. Origin = balance point (the guard).

const TIP := 0.19


static func make(blade: Color, cord: Color) -> Node3D:
	var root := Node3D.new()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = blade
	steel.metallic = 0.85
	steel.roughness = 0.22
	steel.rim_enabled = true
	steel.rim = 0.5
	steel.emission_enabled = true
	steel.emission = blade * 0.22
	steel.cull_mode = BaseMaterial3D.CULL_DISABLED
	var bm := MeshInstance3D.new()
	bm.mesh = _blade()
	bm.material_override = steel
	root.add_child(bm)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.2, 0.2, 0.23)
	dark.metallic = 0.85
	dark.roughness = 0.3
	var guard := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(0.014, 0.058, 0.01)
	guard.mesh = gb
	guard.material_override = dark
	guard.position = Vector3(0, -0.002, 0.006)
	root.add_child(guard)
	var handle := MeshInstance3D.new()
	handle.mesh = _handle(cord)
	var hm := StandardMaterial3D.new()
	hm.vertex_color_use_as_albedo = true
	hm.roughness = 0.8
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	handle.material_override = hm
	root.add_child(handle)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.008
	tm.outer_radius = 0.016
	tm.rings = 16
	tm.ring_segments = 8
	ring.mesh = tm
	ring.material_override = dark
	ring.rotation = Vector3(0, 0, PI * 0.5)   # hole along X, like a real throwing knife
	ring.position = Vector3(0, 0, 0.136)
	root.add_child(ring)
	return root


## Leaf blade with a centre ridge: a fan on each face from the ridge to the outline, the
## cutting edge sharp (x = 0) and a thin flat spine joining the faces.
static func _blade() -> ArrayMesh:
	# (z, y) outline from the tip round the cutting edge (y < 0) and back along the spine.
	var edge := [Vector2(-TIP, 0.0), Vector2(-0.15, -0.012), Vector2(-0.09, -0.019), Vector2(-0.03, -0.021), Vector2(0.0, -0.021)]
	var spine := [Vector2(0.0, 0.017), Vector2(-0.06, 0.017), Vector2(-0.12, 0.013), Vector2(-0.16, 0.006)]
	var outline: Array = edge + spine
	var ridge := Vector3(0.0028, -0.002, -0.07)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [1.0, -1.0]:
		var c := Vector3(ridge.x * side, ridge.y, ridge.z)
		for i in outline.size():
			var a: Vector2 = outline[i]
			var b: Vector2 = outline[(i + 1) % outline.size()]
			var ax: float = 0.0016 * side if a.y > 0.0 or i >= edge.size() else 0.0
			var bx: float = 0.0016 * side if b.y > 0.0 or (i + 1) % outline.size() >= edge.size() else 0.0
			var va := Vector3(ax, a.y, a.x)
			var vb := Vector3(bx, b.y, b.x)
			if side > 0.0:
				st.add_vertex(c)
				st.add_vertex(va)
				st.add_vertex(vb)
			else:
				st.add_vertex(c)
				st.add_vertex(vb)
				st.add_vertex(va)
	# Spine strip (and the back end of the blade) between the two faces.
	var back: Array = [edge.back()] + spine
	for i in back.size() - 1:
		var a: Vector2 = back[i]
		var b: Vector2 = back[i + 1]
		var ax := 0.0016 if a.y > 0.0 else 0.0
		var bx := 0.0016 if b.y > 0.0 else 0.0
		var p := [Vector3(ax, a.y, a.x), Vector3(-ax, a.y, a.x), Vector3(-bx, b.y, b.x), Vector3(bx, b.y, b.x)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(p[idx])
	st.generate_normals()
	return st.commit()


## Cord-wrapped grip: rings of alternating cord and dark binding, slightly bulged.
static func _handle(cord: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z0 := 0.011
	var z1 := 0.124
	var bands := 9
	var seg := 12
	for k in bands:
		var za := lerpf(z0, z1, float(k) / bands)
		var zb := lerpf(z0, z1, float(k + 1) / bands)
		var col := cord if k % 2 == 0 else cord.darkened(0.55)
		var ra := 0.0105 + 0.0012 * sin(PI * float(k) / bands)
		var rb := 0.0105 + 0.0012 * sin(PI * float(k + 1) / bands)
		for s in seg:
			var t0 := TAU * s / seg
			var t1 := TAU * (s + 1) / seg
			var a0 := Vector3(cos(t0) * ra * 0.75, sin(t0) * ra, za)
			var a1 := Vector3(cos(t1) * ra * 0.75, sin(t1) * ra, za)
			var b0 := Vector3(cos(t0) * rb * 0.75, sin(t0) * rb, zb)
			var b1 := Vector3(cos(t1) * rb * 0.75, sin(t1) * rb, zb)
			st.set_color(col)
			for v in [a0, a1, b1, a0, b1, b0]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()
