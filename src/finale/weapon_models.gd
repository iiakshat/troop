class_name WeaponModels
extends RefCounted
## Simple but convincing first-person weapons built from primitives (no asset files):
## a pistol with a moving slide and a removable magazine, a scoped bolt-action rifle, a recurve
## bow with a live string, arrows, throwing stars and brass casings. Logged in docs/assets_finale.md.
## Frames: every weapon points down -Z; +Y is up; units are metres.


static func mat(color: Color, metal := 0.0, rough := 0.6, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	return m


static func box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, n := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if n != "":
		mi.name = n
	parent.add_child(mi)
	return mi


## A cylinder along -Z (length `len`), centred at `pos`.
static func tube(parent: Node3D, r: float, length: float, pos: Vector3, m: Material, r2 := -1.0, seg := 14) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r if r2 < 0.0 else r2
	cm.height = length
	cm.radial_segments = seg
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.rotation.x = -PI * 0.5   # +Y (top) points to -Z
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Stylised "toy-premium" paint: a soft rim light and a clear coat so bevels catch highlights.
static func paint(color: Color, metal := 0.0, rough := 0.45, rim := 0.35, coat := 0.0) -> StandardMaterial3D:
	var m := mat(color, metal, rough)
	m.rim_enabled = true
	m.rim = rim
	m.rim_tint = 0.4
	if coat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = coat
		m.clearcoat_roughness = 0.2
	return m


## A box with chamfered edges and corners (flat-shaded, so every bevel catches a highlight).
static func bevel_box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, bevel := -1.0, n := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := bevel if bevel >= 0.0 else minf(minf(size.x, size.y), size.z) * 0.18
	mi.mesh = bevel_mesh(size, b)
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if n != "":
		mi.name = n
	parent.add_child(mi)
	return mi


static var _bevel_cache := {}


static func bevel_mesh(size: Vector3, b: float) -> ArrayMesh:
	var key := "%s|%.4f" % [size, b]
	if _bevel_cache.has(key):
		return _bevel_cache[key]
	var h := size * 0.5
	b = minf(b, minf(minf(h.x, h.y), h.z) * 0.95)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Corner points: for a corner with signs s, the three chamfer points pull in on two axes.
	for ax in 3:
		for s in [-1.0, 1.0]:
			# Main face on axis `ax`, side s.
			var nrm := Vector3.ZERO
			nrm[ax] = s
			var u := (ax + 1) % 3
			var v := (ax + 2) % 3
			var q: Array = []
			for c in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
				var p := Vector3.ZERO
				p[ax] = s * h[ax]
				p[u] = c[0] * (h[u] - b)
				p[v] = c[1] * (h[v] - b)
				q.append(p)
			_poly(st, q, nrm)
	# Edge chamfers: between faces on axes a1 (sign s1) and a2 (sign s2), running along the third.
	for a1 in 3:
		for a2 in range(a1 + 1, 3):
			var run := 3 - a1 - a2
			for s1 in [-1.0, 1.0]:
				for s2 in [-1.0, 1.0]:
					var nrm := Vector3.ZERO
					nrm[a1] = s1
					nrm[a2] = s2
					var q: Array = []
					for e in [-1.0, 1.0]:
						var p := Vector3.ZERO
						p[run] = e * (h[run] - b)
						p[a1] = s1 * h[a1]
						p[a2] = s2 * (h[a2] - b)
						q.append(p)
					for e in [1.0, -1.0]:
						var p := Vector3.ZERO
						p[run] = e * (h[run] - b)
						p[a1] = s1 * (h[a1] - b)
						p[a2] = s2 * h[a2]
						q.append(p)
					_poly(st, q, nrm.normalized())
	# Corner triangles.
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var s := Vector3(sx, sy, sz)
				var q: Array = []
				for ax in 3:
					var p := s * (h - Vector3.ONE * b)
					p[ax] = s[ax] * h[ax]
					q.append(p)
				_poly(st, q, s.normalized())
	var mesh := st.commit()
	_bevel_cache[key] = mesh
	return mesh


## A flat convex polygon with outward normal `nrm` (fanned; winding fixed to Godot's front face).
static func _poly(st: SurfaceTool, q: Array, nrm: Vector3) -> void:
	for i in range(1, q.size() - 1):
		var a: Vector3 = q[0]
		var b: Vector3 = q[i]
		var c: Vector3 = q[i + 1]
		if (b - a).cross(c - a).dot(nrm) > 0.0:
			var t := b
			b = c
			c = t
		for p in [a, b, c]:
			st.set_normal(nrm)
			st.add_vertex(p)


## Screen rects (pixels) of every mesh part of `model` placed at `pose` in camera space, for the
## game camera (`fov_h` horizontal, KEEP_WIDTH) on a `vp` viewport. Works off the tree.
static func screen_rects(model: Node3D, pose: Transform3D, fov_h: float, vp: Vector2) -> Array:
	var out: Array = []
	_collect_rects(model, pose, fov_h, vp, out, true)
	return out


static func _collect_rects(n: Node3D, xf: Transform3D, fov_h: float, vp: Vector2, out: Array, root: bool) -> void:
	var here := xf if root else xf * n.transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh and n.visible:
		var bb := _mesh_aabb((n as MeshInstance3D).mesh)
		if bb.size.length() > 0.0:
			var r := Rect2()
			for k in 8:
				var s := FinaleWeapon.project_cam(here * bb.get_endpoint(k), fov_h, vp)
				r = Rect2(s, Vector2.ZERO) if k == 0 else r.expand(s)
			if r.intersects(Rect2(Vector2.ZERO, vp)):
				out.append(r)
	for c in n.get_children():
		if c is Node3D and (c as Node3D).visible and not (c as Node3D).top_level:
			_collect_rects(c, here, fov_h, vp, out, false)


static func _mesh_aabb(m: Mesh) -> AABB:
	if m is BoxMesh:
		var s := (m as BoxMesh).size
		return AABB(-s * 0.5, s)
	if m is CylinderMesh:
		var cm := m as CylinderMesh
		var r := maxf(cm.top_radius, cm.bottom_radius)
		return AABB(Vector3(-r, -cm.height * 0.5, -r), Vector3(r * 2.0, cm.height, r * 2.0))
	if m is SphereMesh:
		var sm := m as SphereMesh
		return AABB(Vector3(-sm.radius, -sm.height * 0.5, -sm.radius), Vector3(sm.radius * 2.0, sm.height, sm.radius * 2.0))
	return m.get_aabb()


static func skin() -> StandardMaterial3D:
	return mat(Color("c98f6a"), 0.0, 0.75)


## Jacket sleeve (the hero's casual clothes): forearms read as sleeves, not bare slabs.
static func sleeve() -> StandardMaterial3D:
	return mat(Color("34405a"), 0.0, 0.9)


static func glove() -> StandardMaterial3D:
	return mat(Color("2a2d33"), 0.0, 0.85)


## Pistol. Origin = the line of sight: the top of the front sight post sits at (0, 0, -FRONT),
## the rear notch at (0, 0, -REAR), so a camera at the origin looking down -Z sees the classic
## sight picture. Children: Slide (moves back on each shot), Mag (drops out on reload), Hand.
const P_FRONT := 0.36
const P_REAR := 0.2


static func pistol() -> Node3D:
	# Premium stylised: a two-tone pistol (satin steel slide over a navy polymer frame), every
	# edge bevelled, gold barrel and trigger, a glowing orange front sight. No real model.
	var root := Node3D.new()
	var steel := paint(Color("c4ccd6"), 0.85, 0.26, 0.3, 0.4)
	var dark := paint(Color("1c2230"), 0.6, 0.4, 0.2)
	var poly := paint(Color("27355a"), 0.0, 0.5, 0.45, 0.6)
	var panel := paint(Color("161d30"), 0.0, 0.75, 0.25)
	var gold := paint(Color("e7b54c"), 0.9, 0.25, 0.3, 0.5)
	var glow := mat(Color("ff8a2a"), 0.0, 0.4, 2.2)
	var gun := Node3D.new()
	gun.name = "Gun"
	root.add_child(gun)
	var slide := Node3D.new()
	slide.name = "Slide"
	gun.add_child(slide)
	# Slide: top at y = -0.006 (sights stand on it), from z -0.17 (rear) to -0.375 (muzzle).
	bevel_box(slide, Vector3(0.03, 0.034, 0.205), Vector3(0, -0.023, -0.2725), steel, 0.005)
	bevel_box(slide, Vector3(0.024, 0.006, 0.17), Vector3(0, -0.0045, -0.28), dark, 0.002)   # top rib
	for k in 4:  # rear serrations, cut deep
		bevel_box(slide, Vector3(0.031, 0.024, 0.0035), Vector3(0, -0.024, -0.183 - k * 0.008), dark, 0.0008)
	for s in [-1.0, 1.0]:  # lightening cuts along both sides
		bevel_box(slide, Vector3(0.002, 0.008, 0.07), Vector3(s * 0.0151, -0.02, -0.31), dark, 0.0008)
	bevel_box(slide, Vector3(0.004, 0.012, 0.03), Vector3(0.0152, -0.018, -0.25), gold, 0.001)  # port: the barrel hood shows
	# Front post with a glowing insert, rear sight with a notch (two blocks).
	bevel_box(slide, Vector3(0.005, 0.008, 0.007), Vector3(0, -0.003, -P_FRONT), dark, 0.0012)
	bevel_box(slide, Vector3(0.0045, 0.003, 0.002), Vector3(0, -0.003, -P_FRONT + 0.0036), glow, 0.0006)
	for s in [-1.0, 1.0]:
		bevel_box(slide, Vector3(0.009, 0.009, 0.007), Vector3(s * 0.0072, -0.0025, -P_REAR), dark, 0.0015)
	tube(slide, 0.0075, 0.012, Vector3(0, -0.026, -0.379), gold)   # gold barrel crown
	tube(slide, 0.0042, 0.013, Vector3(0, -0.026, -0.38), mat(Color("0d0f14"), 0.0, 0.9))  # bore
	# Frame with an accessory rail, trigger guard, gold trigger, flared grip with the magazine in it.
	bevel_box(gun, Vector3(0.027, 0.022, 0.19), Vector3(0, -0.048, -0.275), poly, 0.005)
	for k in 3:
		bevel_box(gun, Vector3(0.022, 0.004, 0.008), Vector3(0, -0.06, -0.33 - k * 0.013), dark, 0.0012)
	bevel_box(gun, Vector3(0.012, 0.006, 0.055), Vector3(0, -0.078, -0.3), poly, 0.002)
	bevel_box(gun, Vector3(0.012, 0.03, 0.006), Vector3(0, -0.065, -0.327), poly, 0.002)
	bevel_box(gun, Vector3(0.005, 0.02, 0.007), Vector3(0, -0.063, -0.29), gold, 0.0015)   # trigger
	var grip := bevel_box(gun, Vector3(0.032, 0.11, 0.052), Vector3(0, -0.1, -0.205), poly, 0.008)
	grip.rotation.x = deg_to_rad(-16)
	for s in [-1.0, 1.0]:  # textured grip panels
		var p := bevel_box(gun, Vector3(0.004, 0.075, 0.036), Vector3(s * 0.016, -0.1, -0.205), panel, 0.0015)
		p.rotation.x = deg_to_rad(-16)
	var tail := bevel_box(gun, Vector3(0.028, 0.012, 0.03), Vector3(0, -0.045, -0.163), poly, 0.004)  # beavertail
	tail.rotation.x = deg_to_rad(18)
	var mag := Node3D.new()
	mag.name = "Mag"
	mag.position = Vector3(0, -0.1, -0.205)
	mag.rotation.x = deg_to_rad(-16)
	gun.add_child(mag)
	_mag_parts(mag)
	# The shooting hand wraps the grip (gloved, with the jacket cuff behind it).
	var hand := Node3D.new()
	hand.name = "Hand"
	gun.add_child(hand)
	var g := paint(Color("2a2f3a"), 0.0, 0.7, 0.3)
	var palm := bevel_box(hand, Vector3(0.05, 0.08, 0.07), Vector3(0.006, -0.105, -0.2), g, 0.012)
	palm.rotation.x = deg_to_rad(-16)
	for k in 3:
		bevel_box(hand, Vector3(0.036, 0.017, 0.02), Vector3(-0.012, -0.095 - k * 0.022, -0.235 - k * 0.006), g, 0.006)
	bevel_box(hand, Vector3(0.015, 0.015, 0.05), Vector3(-0.022, -0.05, -0.28), g, 0.005)   # thumb along the frame
	var cuff := bevel_box(hand, Vector3(0.056, 0.035, 0.05), Vector3(0.0, -0.165, -0.185), paint(Color("34405a"), 0.0, 0.85, 0.3), 0.01)
	cuff.rotation.x = deg_to_rad(-16)
	return root


static func _mag_parts(n: Node3D) -> void:
	bevel_box(n, Vector3(0.022, 0.11, 0.036), Vector3(0, -0.012, 0), paint(Color("2b2f38"), 0.8, 0.35), 0.003)
	bevel_box(n, Vector3(0.028, 0.013, 0.044), Vector3(0, -0.07, 0), paint(Color("e7b54c"), 0.9, 0.25, 0.3), 0.004)


## A brass pistol/rifle casing (local Y = the case axis).
static func casing(rifle := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0045 if not rifle else 0.0055
	cm.bottom_radius = cm.top_radius
	cm.height = 0.019 if not rifle else 0.05
	cm.radial_segments = 8
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat(Color("d6a84a"), 0.9, 0.28, 0.15)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A spare magazine for the reload.
static func magazine() -> Node3D:
	var n := Node3D.new()
	_mag_parts(n)
	var top := box(n, Vector3(0.01, 0.008, 0.016), Vector3(0, 0.046, 0.004), mat(Color("d6a84a"), 0.9, 0.3))
	top.name = "Round"
	return n


## Bolt-action rifle seen from the shooter (stock against the shoulder, low right).
## Children: Bolt (handle that lifts and slides), Scope.
static func rifle() -> Node3D:
	var root := Node3D.new()
	var wood := mat(Color("5a3a22"), 0.0, 0.55)
	var steel := mat(Color("1d2024"), 0.85, 0.3)
	var lens := mat(Color("3b6fb0"), 0.2, 0.05, 0.4)
	box(root, Vector3(0.05, 0.07, 0.42), Vector3(0, -0.07, 0.05), wood)          # stock
	box(root, Vector3(0.045, 0.05, 0.3), Vector3(0, -0.06, -0.3), wood)          # fore-end
	box(root, Vector3(0.036, 0.04, 0.22), Vector3(0, -0.035, -0.18), steel)      # receiver
	tube(root, 0.009, 0.62, Vector3(0, -0.03, -0.66), steel, 0.011)               # barrel
	tube(root, 0.016, 0.03, Vector3(0, -0.03, -0.98), steel)                      # muzzle brake
	var scope := Node3D.new()
	scope.name = "Scope"
	root.add_child(scope)
	tube(scope, 0.02, 0.3, Vector3(0, 0.03, -0.2), steel)
	tube(scope, 0.026, 0.07, Vector3(0, 0.03, -0.38), steel, 0.02)
	tube(scope, 0.024, 0.06, Vector3(0, 0.03, -0.03), steel, 0.02)
	tube(scope, 0.022, 0.004, Vector3(0, 0.03, -0.416), lens)
	for z in [-0.14, -0.26]:
		box(scope, Vector3(0.016, 0.03, 0.02), Vector3(0, 0.0, z), steel)
	tube(scope, 0.008, 0.03, Vector3(0.0, 0.055, -0.2), steel).rotation = Vector3.ZERO  # turret
	var bolt := Node3D.new()
	bolt.name = "Bolt"
	bolt.position = Vector3(0.02, -0.025, -0.1)
	root.add_child(bolt)
	var arm := box(bolt, Vector3(0.05, 0.008, 0.008), Vector3(0.025, 0, 0), steel)
	arm.name = "Arm"
	var knob := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.011
	sm.height = 0.022
	knob.mesh = sm
	knob.material_override = steel
	knob.position = Vector3(0.05, 0, 0)
	bolt.add_child(knob)
	# Gloved hand on the grip and one under the fore-end.
	var g := glove()
	box(root, Vector3(0.05, 0.08, 0.07), Vector3(0.0, -0.11, -0.08), g)
	box(root, Vector3(0.055, 0.05, 0.1), Vector3(0.0, -0.1, -0.36), g)
	var sk := sleeve()
	var a1 := box(root, Vector3(0.065, 0.065, 0.3), Vector3(0.04, -0.2, 0.02), sk)
	a1.rotation.x = deg_to_rad(25)
	var a2 := box(root, Vector3(0.065, 0.065, 0.32), Vector3(-0.06, -0.21, -0.22), sk)
	a2.rotation = Vector3(deg_to_rad(28), deg_to_rad(-22), 0)
	return root


## Recurve bow, held upright. Origin = the grip; the string's nock point starts at
## (0, 0, BOW_BRACE) and is pulled back towards +Z. Limb tips at (0, +-TIP_Y, TIP_Z).
const BOW_TIP_Y := 0.62
const BOW_TIP_Z := 0.05
const BOW_BRACE := 0.17


static func bow() -> Node3D:
	# Premium stylised recurve: a bevelled graphite riser with a gold inlay and a red leather grip,
	# navy limbs that sweep forward and recurve back to gold tips. No real model.
	var root := Node3D.new()
	var riser := paint(Color("2a2e38"), 0.55, 0.35, 0.35, 0.5)
	var limb := paint(Color("223559"), 0.1, 0.35, 0.5, 0.7)
	var gold := paint(Color("e7b54c"), 0.9, 0.25, 0.3, 0.5)
	var leather := paint(Color("a8322d"), 0.0, 0.7, 0.3)
	bevel_box(root, Vector3(0.036, 0.2, 0.05), Vector3(0, 0.0, -0.004), riser, 0.009)        # riser
	bevel_box(root, Vector3(0.04, 0.09, 0.054), Vector3(0, -0.01, 0.002), leather, 0.012)    # grip wrap
	bevel_box(root, Vector3(0.006, 0.15, 0.012), Vector3(-0.019, 0.0, -0.02), gold, 0.002)   # inlay
	bevel_box(root, Vector3(0.03, 0.012, 0.04), Vector3(0.02, 0.05, -0.006), riser, 0.004)   # arrow shelf
	for s in [-1.0, 1.0]:
		bevel_box(root, Vector3(0.042, 0.05, 0.05), Vector3(0, s * 0.11, -0.012), riser, 0.01)  # limb pockets
		# Each limb: segments along a gentle curve that sweeps forward, then recurves back.
		var prev := Vector3(0, s * 0.12, -0.012)
		for k in range(1, 9):
			var f := k / 8.0
			var y: float = s * (0.12 + (BOW_TIP_Y - 0.12) * f)
			var z: float = -0.012 - 0.09 * sin(f * PI * 0.85) + (BOW_TIP_Z + 0.032) * f * f
			var p := Vector3(0, y, z)
			var seg := bevel_box(root, Vector3(0.03 - f * 0.014, prev.distance_to(p) + 0.006, 0.012), (prev + p) * 0.5, limb if k < 8 else gold, 0.003)
			seg.basis = Basis(Vector3.RIGHT, -atan2(p.z - prev.z, p.y - prev.y))
			prev = p
	var string := MeshInstance3D.new()
	string.name = "String"
	string.mesh = ImmediateMesh.new()
	var sm2 := StandardMaterial3D.new()
	sm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm2.albedo_color = Color("f1ead8")
	string.material_override = sm2
	root.add_child(string)
	var g := paint(Color("2a2f3a"), 0.0, 0.7, 0.3)
	bevel_box(root, Vector3(0.05, 0.08, 0.058), Vector3(0.006, -0.012, 0.012), g, 0.014)   # gloved bow hand
	return root


## Redraws the bow string through the nock point (bow-local): a doubled strand, thick enough to
## read at phone size.
static func bow_string(bow_node: Node3D, nock: Vector3) -> void:
	var s: MeshInstance3D = bow_node.get_node("String")
	var im: ImmediateMesh = s.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for tip in [Vector3(0, BOW_TIP_Y, BOW_TIP_Z), Vector3(0, -BOW_TIP_Y, BOW_TIP_Z)]:
		for dx in [-0.002, -0.0007, 0.0007, 0.002]:
			im.surface_add_vertex(tip + Vector3(dx, 0, 0))
			im.surface_add_vertex(nock + Vector3(dx, 0, 0))
	im.surface_end()


## Arrow along -Z, origin at the nock (tail); the tip is ARROW_LEN ahead. Reads as an arrow at
## a glance: a steel broadhead wider than the shaft, a gold ferrule, a thick wooden shaft with
## crest bands, three big vanes (two red, one white) and an orange nock.
const ARROW_LEN := 0.72


static func arrow() -> Node3D:
	var root := Node3D.new()
	var wood := paint(Color("d9b77a"), 0.0, 0.5, 0.3)
	tube(root, 0.0058, ARROW_LEN - 0.08, Vector3(0, 0, -(ARROW_LEN - 0.08) * 0.5 - 0.01), wood, -1.0, 10)
	for k in 2:  # crest bands
		tube(root, 0.0062, 0.008, Vector3(0, 0, -0.15 - k * 0.014), paint(Color("e8414b") if k == 0 else Color("1c2230"), 0.0, 0.5), -1.0, 10)
	tube(root, 0.0072, 0.014, Vector3(0, 0, -ARROW_LEN + 0.076), paint(Color("e7b54c"), 0.9, 0.25), -1.0, 10)  # ferrule
	# Broadhead: a four-sided steel point with a bright edge.
	tube(root, 0.0001, 0.07, Vector3(0, 0, -ARROW_LEN + 0.035), paint(Color("dfe6ee"), 0.95, 0.15, 0.6, 0.6), 0.019, 4)
	var vane_red := mat(Color("e8414b"), 0.0, 0.55)
	vane_red.cull_mode = BaseMaterial3D.CULL_DISABLED
	var vane_white := mat(Color("f4f1e8"), 0.0, 0.55)
	vane_white.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k in 3:
		var a := TAU * k / 3.0 + PI * 0.5
		var v := MeshInstance3D.new()
		v.mesh = _vane_mesh()
		v.material_override = vane_white if k == 0 else vane_red
		v.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		v.rotation.z = a - PI * 0.5
		root.add_child(v)
	tube(root, 0.0068, 0.016, Vector3(0, 0, -0.006), paint(Color("ff8a2a"), 0.0, 0.4, 0.4), -1.0, 10)  # nock
	return root


static var _vane: ArrayMesh


## One vane in the local YZ plane, standing up from the shaft (+Y), tail at z = 0.
static func _vane_mesh() -> ArrayMesh:
	if _vane:
		return _vane
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(0, 0.005, -0.028), Vector3(0, 0.005, -0.135), Vector3(0, 0.012, -0.125),
		Vector3(0, 0.03, -0.065), Vector3(0, 0.03, -0.034)]
	for i in range(1, pts.size() - 1):
		for p in [pts[0], pts[i], pts[i + 1]]:
			st.set_normal(Vector3.RIGHT)
			st.add_vertex(p)
	_vane = st.commit()
	return _vane


## Four-point throwing star in the XZ plane (flat, spins about Y).
static func star() -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r_out := 0.085
	var r_in := 0.026
	var th := 0.004
	var pts: Array = []
	for k in 8:
		var a := TAU * k / 8.0
		var r := r_out if k % 2 == 0 else r_in
		pts.append(Vector2(cos(a), sin(a)) * r)
	for side in [1.0, -1.0]:
		st.set_normal(Vector3(0, side, 0))
		for k in 8:
			var a2: Vector2 = pts[k]
			var b2: Vector2 = pts[(k + 1) % 8]
			var verts := [Vector3(0, side * th, 0), Vector3(a2.x, side * th * 0.2, a2.y), Vector3(b2.x, side * th * 0.2, b2.y)]
			if side < 0.0:
				verts = [verts[0], verts[2], verts[1]]
			for v in verts:
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := mat(Color("cfd6de"), 0.95, 0.18)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.rim_enabled = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var hub := tube(root, 0.012, 0.01, Vector3.ZERO, mat(Color("2a2d33"), 0.6, 0.4))
	hub.rotation.x = PI * 0.5
	return root


## Bullet: a small copper ogive along -Z.
static func bullet(scale := 1.0) -> Node3D:
	var root := Node3D.new()
	var cu := mat(Color("c47a3a"), 0.9, 0.25, 0.25)
	tube(root, 0.0045 * scale, 0.02 * scale, Vector3(0, 0, 0), cu)
	tube(root, 0.0001, 0.014 * scale, Vector3(0, 0, -0.017 * scale), cu, 0.0045 * scale, 10)
	return root
