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
	var root := Node3D.new()
	var steel := mat(Color("23262b"), 0.8, 0.35)
	var dark := mat(Color("15171a"), 0.5, 0.55)
	var poly := mat(Color("2e2a26"), 0.0, 0.8)
	var white := mat(Color("f2f2f2"), 0.0, 0.4, 0.6)
	var gun := Node3D.new()
	gun.name = "Gun"
	root.add_child(gun)
	var slide := Node3D.new()
	slide.name = "Slide"
	gun.add_child(slide)
	# Slide: top at y = -0.006 (sights stand on it), from z -0.17 (rear) to -0.375 (muzzle).
	box(slide, Vector3(0.028, 0.032, 0.205), Vector3(0, -0.022, -0.2725), steel)
	for k in 5:  # rear serrations
		box(slide, Vector3(0.029, 0.026, 0.003), Vector3(0, -0.022, -0.182 - k * 0.007), dark)
	box(slide, Vector3(0.004, 0.012, 0.03), Vector3(0.0145, -0.018, -0.25), dark)  # ejection port
	# Front post with a white dot, rear sight with a notch (two blocks).
	box(slide, Vector3(0.004, 0.007, 0.006), Vector3(0, -0.0035, -P_FRONT), steel)
	box(slide, Vector3(0.0045, 0.0025, 0.002), Vector3(0, -0.004, -P_FRONT + 0.0032), white)
	for s in [-1.0, 1.0]:
		box(slide, Vector3(0.009, 0.008, 0.006), Vector3(s * 0.0072, -0.003, -P_REAR), steel)
		box(slide, Vector3(0.0025, 0.0022, 0.001), Vector3(s * 0.0072, -0.0045, -P_REAR + 0.0032), white)
	tube(slide, 0.0068, 0.012, Vector3(0, -0.026, -0.378), dark)  # muzzle
	# Frame, trigger guard, grip with the magazine in it.
	box(gun, Vector3(0.026, 0.02, 0.19), Vector3(0, -0.047, -0.275), poly)
	box(gun, Vector3(0.006, 0.004, 0.05), Vector3(0, -0.075, -0.3), poly)
	box(gun, Vector3(0.006, 0.026, 0.004), Vector3(0, -0.064, -0.325), poly)
	box(gun, Vector3(0.004, 0.018, 0.006), Vector3(0, -0.063, -0.29), steel)   # trigger
	var grip := box(gun, Vector3(0.03, 0.105, 0.05), Vector3(0, -0.1, -0.205), poly)
	grip.rotation.x = deg_to_rad(-16)
	var mag := Node3D.new()
	mag.name = "Mag"
	mag.position = Vector3(0, -0.1, -0.205)
	mag.rotation.x = deg_to_rad(-16)
	gun.add_child(mag)
	box(mag, Vector3(0.022, 0.11, 0.036), Vector3(0, -0.012, 0), steel)
	box(mag, Vector3(0.026, 0.012, 0.042), Vector3(0, -0.07, 0), dark)
	# The shooting hand wraps the grip, the support hand cups it.
	var hand := Node3D.new()
	hand.name = "Hand"
	gun.add_child(hand)
	var g := glove()
	var sk := sleeve()
	var palm := box(hand, Vector3(0.05, 0.08, 0.07), Vector3(0.006, -0.105, -0.2), g)
	palm.rotation.x = deg_to_rad(-16)
	for k in 3:
		box(hand, Vector3(0.036, 0.016, 0.02), Vector3(-0.012, -0.095 - k * 0.022, -0.235 - k * 0.006), g)
	box(hand, Vector3(0.014, 0.014, 0.05), Vector3(-0.022, -0.05, -0.28), g)   # thumb along the frame
	# Only the gloved hands show: the forearms stay below the frame (at this narrow field of view
	# any sleeve read as a big flat slab filling the lower screen).
	var support := box(hand, Vector3(0.042, 0.06, 0.07), Vector3(-0.026, -0.115, -0.215), g)
	support.rotation.z = deg_to_rad(-12)
	var cuff := box(hand, Vector3(0.05, 0.03, 0.05), Vector3(0.0, -0.165, -0.185), sk)
	cuff.rotation.x = deg_to_rad(-16)
	return root


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
	box(n, Vector3(0.022, 0.11, 0.036), Vector3(0, -0.012, 0), mat(Color("23262b"), 0.8, 0.35))
	box(n, Vector3(0.026, 0.012, 0.042), Vector3(0, -0.07, 0), mat(Color("15171a"), 0.5, 0.55))
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
	var root := Node3D.new()
	var wood := mat(Color("6b3f1f"), 0.0, 0.45)
	var dark := mat(Color("2a1a10"), 0.0, 0.6)
	box(root, Vector3(0.035, 0.16, 0.045), Vector3.ZERO, dark)                    # riser grip
	box(root, Vector3(0.028, 0.06, 0.03), Vector3(0.022, 0.06, -0.005), dark)    # arrow shelf
	for s in [-1.0, 1.0]:
		# Each limb: segments along a gentle curve that sweeps forward, then recurves back.
		var prev := Vector3(0, s * 0.08, 0)
		for k in range(1, 9):
			var f := k / 8.0
			var y: float = s * (0.08 + (BOW_TIP_Y - 0.08) * f)
			var z: float = -0.09 * sin(f * PI * 0.85) + (BOW_TIP_Z + 0.02) * f * f
			var p := Vector3(0, y, z)
			var seg := box(root, Vector3(0.02 - f * 0.009, 1.0, 0.01), (prev + p) * 0.5, wood)
			seg.scale.y = prev.distance_to(p) + 0.004
			seg.basis = Basis(Vector3.RIGHT, atan2(p.z - prev.z, p.y - prev.y) * -1.0) * Basis.from_scale(Vector3(1, prev.distance_to(p) + 0.004, 1))
			prev = p
	# The pin sight: a glowing bead on a short bar out to the side, at eye line (set by the view).
	var pin := Node3D.new()
	pin.name = "Pin"
	root.add_child(pin)
	box(pin, Vector3(0.05, 0.004, 0.004), Vector3(-0.025, 0, 0), dark)
	var bead := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.0035
	sm.height = 0.007
	bead.mesh = sm
	bead.material_override = mat(Color("6dff7a"), 0.0, 0.3, 3.0)
	pin.add_child(bead)
	var string := MeshInstance3D.new()
	string.name = "String"
	string.mesh = ImmediateMesh.new()
	var sm2 := StandardMaterial3D.new()
	sm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm2.albedo_color = Color("e8e2d0")
	string.material_override = sm2
	root.add_child(string)
	var g := glove()
	box(root, Vector3(0.042, 0.075, 0.05), Vector3(0.004, -0.005, 0.01), g)
	# No forearm: it filled the left third of the view. The riser, string and arrow are enough.
	return root


## Redraws the bow string through the nock point (bow-local).
static func bow_string(bow_node: Node3D, nock: Vector3) -> void:
	var s: MeshInstance3D = bow_node.get_node("String")
	var im: ImmediateMesh = s.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for tip in [Vector3(0, BOW_TIP_Y, BOW_TIP_Z), Vector3(0, -BOW_TIP_Y, BOW_TIP_Z)]:
		for dx in [-0.0012, 0.0012]:
			im.surface_add_vertex(tip + Vector3(dx, 0, 0))
			im.surface_add_vertex(nock + Vector3(dx, 0, 0))
	im.surface_end()


## Arrow along -Z, origin at the nock (tail); the tip is ARROW_LEN ahead.
const ARROW_LEN := 0.72


static func arrow() -> Node3D:
	var root := Node3D.new()
	var shaft := mat(Color("c9a46a"), 0.0, 0.5)
	tube(root, 0.0045, ARROW_LEN - 0.04, Vector3(0, 0, -(ARROW_LEN - 0.04) * 0.5), shaft)
	tube(root, 0.0001, 0.045, Vector3(0, 0, -ARROW_LEN + 0.0225), mat(Color("9aa3ad"), 0.9, 0.25), 0.009, 6)
	var red := mat(Color("e0484f"), 0.0, 0.7)
	red.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k in 3:
		var a := TAU * k / 3.0
		var f := box(root, Vector3(0.0008, 0.018, 0.08), Vector3(cos(a) * 0.009, sin(a) * 0.009, -0.06), red)
		f.rotation.z = a - PI * 0.5
	return root


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
