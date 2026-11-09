class_name FinaleStash
extends RefCounted
## The gang's stash, one set per district (config finale.json "district_stash"), built from
## primitives around Bottle Shot's bottle plane, plus the street-end facade the squad runs at.
##   bar       back-alley bar: plank wall, bulbs, two spotlights with dusty beams (knives)
##   carnival  market shooting-gallery stall: striped back, awning, bulb frame (pistol)
##   docks     crate stack in front of a container wall, harbour lamps (bow)
##   factory   conveyor belts, steel wall with hazard stripes, steel plates (stars)
##   rooftop   neon lounge on a far roof across the street, seen from our own roof (sniper)
## Every stash carries the gang's sign: a neon bottle silhouette (no words).

const NEON := {"bar": Color("ffb347"), "carnival": Color("ff4fa8"), "docks": Color("3fe0ff"),
	"factory": Color("8dff4f"), "rooftop": Color("ff3bd5")}


static func theme_of(district: int) -> String:
	return ["bar", "carnival", "docks", "factory", "rooftop"][clampi(district, 1, 5) - 1]


# ---------------------------------------------------------------- pieces

static func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, emit := 0.0) -> MeshInstance3D:
	var b := World._box(size, color)
	if emit > 0.0:
		b.material_override = WeaponModels.mat(color, 0.0, 0.5, emit)
	b.position = pos
	parent.add_child(b)
	return b


## A thin bar from a to b (neon tubes, rails, ropes).
static func seg(parent: Node3D, a: Vector3, b: Vector3, thick: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, a.distance_to(b), thick)
	mi.mesh = bm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized()
	mi.basis = Basis(x, y, x.cross(y).normalized())
	mi.position = (a + b) * 0.5
	parent.add_child(mi)
	return mi


## Neon bottle outline `h` metres tall standing at `pos` (facing +Z), with a soft glow light.
static func neon_bottle(parent: Node3D, pos: Vector3, h: float, color: Color, light := true) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var m := WeaponModels.mat(color, 0.0, 0.4, 2.2)
	var prof := [Vector2(0.0, 0.0), Vector2(0.3, 0.0), Vector2(0.34, 0.06), Vector2(0.34, 0.56),
		Vector2(0.28, 0.72), Vector2(0.11, 0.84), Vector2(0.11, 1.08), Vector2(0.14, 1.12), Vector2(0.0, 1.12)]
	for s in [-1.0, 1.0]:
		for k in prof.size() - 1:
			var a: Vector2 = prof[k]
			var b: Vector2 = prof[k + 1]
			seg(root, Vector3(a.x * s * h, a.y * h, 0), Vector3(b.x * s * h, b.y * h, 0), 0.06 * h, m)
	# A label band across the belly.
	seg(root, Vector3(-0.22 * h, 0.3 * h, 0), Vector3(0.22 * h, 0.3 * h, 0), 0.05 * h, m)
	if light:
		var l := OmniLight3D.new()
		l.light_color = color
		l.light_energy = 1.4
		l.omni_range = h * 3.5
		l.position = Vector3(0, h * 0.5, 0.4)
		root.add_child(l)
	return root


static func bulbs(parent: Node3D, from: Vector3, to: Vector3, n: int, sag: float, color := Color("ffd98a")) -> void:
	var m := WeaponModels.mat(color, 0.0, 0.4, 4.0)
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	for i in n:
		var f := i / float(maxi(n - 1, 1))
		var b := MeshInstance3D.new()
		b.mesh = sm
		b.material_override = m
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.position = from.lerp(to, f) - Vector3(0, sag * sin(f * PI), 0)
		parent.add_child(b)


static func stripes(parent: Node3D, center: Vector3, size: Vector2, n: int, a: Color, b: Color, depth := 0.08) -> void:
	var w := size.x / n
	for i in n:
		box(parent, Vector3(w, size.y, depth), center + Vector3(-size.x * 0.5 + w * (i + 0.5), 0, 0), a if i % 2 == 0 else b)


# ---------------------------------------------------------------- shelves

## One shelf `width` metres wide in the stash's style, its top at local y = 0.
static func shelf(theme: String, width: float, depth := 0.5) -> Node3D:
	var n := Node3D.new()
	match theme:
		"carnival":
			box(n, Vector3(width, 0.08, depth), Vector3(0, -0.04, 0), Color("b8262e"))
			stripes(n, Vector3(0, -0.2, depth * 0.5), Vector2(width, 0.24), int(width / 0.3), Color("fff1d6"), Color("d8283a"), 0.02)
		"docks":
			# A row of crates: the bottles stand on their lids.
			var k := maxi(int(round(width / 0.9)), 1)
			var cw := width / k
			for i in k:
				var c := box(n, Vector3(cw - 0.04, 0.7, depth + 0.2), Vector3(-width * 0.5 + cw * (i + 0.5), -0.35, 0), Color("8a6236").lerp(Color("6e4a28"), float(i % 2)))
				box(c, Vector3(cw - 0.02, 0.06, depth + 0.24), Vector3(0, 0.2, 0), Color("4d331b"))
				box(c, Vector3(cw - 0.02, 0.06, depth + 0.24), Vector3(0, -0.2, 0), Color("4d331b"))
		"factory":
			# Conveyor: a dark belt with rollers peeking out and a steel frame.
			box(n, Vector3(width, 0.06, depth), Vector3(0, -0.03, 0), Color("1d1f22"))
			box(n, Vector3(width + 0.1, 0.12, 0.05), Vector3(0, -0.07, depth * 0.5 + 0.03), Color("7b828a"))
			box(n, Vector3(width + 0.1, 0.12, 0.05), Vector3(0, -0.07, -depth * 0.5 - 0.03), Color("7b828a"))
			var rm := WeaponModels.mat(Color("9aa3ad"), 0.8, 0.3)
			var k := int(width / 0.35)
			for i in k:
				var r := WeaponModels.tube(n, 0.04, depth, Vector3(-width * 0.5 + 0.35 * (i + 0.5), -0.07, depth * 0.5), rm)
				r.rotation.y = 0.0
		"rooftop":
			box(n, Vector3(width, 0.07, depth), Vector3(0, -0.035, 0), Color("2a2230"))
			box(n, Vector3(width, 0.03, 0.03), Vector3(0, -0.06, depth * 0.5), Color("ff3bd5"), 3.0)
		_:
			box(n, Vector3(width, 0.08, depth), Vector3(0, -0.04, 0), Color("8a5a32"))
	return n


# ---------------------------------------------------------------- sets

## Builds the stash around `shot`'s bottle plane (shot._wall_z = the back wall, shot._floor_y).
static func build(shot: BottleShot, theme: String) -> void:
	var c := Vector3(shot.hero_pos.x, shot._floor_y, shot._wall_z)
	match theme:
		"carnival": _carnival(shot, c)
		"docks": _docks(shot, c)
		"factory": _factory(shot, c)
		"rooftop": _rooftop(shot, c)
		_: _bar(shot, c)


static func _spots(shot: BottleShot, c: Vector3, height: float, back: float, aim_y: float, energy: float, beams: bool) -> void:
	var spots: Array = []
	for side in [-1, 1]:
		var spot := SpotLight3D.new()
		spot.light_color = Color("ffe2b0")
		spot.light_energy = energy
		spot.spot_range = back + 10.0
		spot.spot_angle = 32.0
		spot.shadow_enabled = true
		spot.position = c + Vector3(side * 2.4, height, back)
		shot.add_child(spot)
		var target := c + Vector3(side * 0.4, aim_y, 0)
		spot.look_at(target, Vector3.UP)
		spots.append({"pos": spot.position, "dir": (target - spot.position).normalized()})
		if beams:
			shot._add_beam(spot.position, target, 32.0)
	if beams:
		shot._add_dust(spots, 32.0)


static func _bar(shot: BottleShot, c: Vector3) -> void:
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(6.4, 4.4, 0.25)
	wall.mesh = wm
	var pm := ShaderMaterial.new()
	pm.shader = load("res://src/finale/planks.gdshader")
	wall.material_override = pm
	wall.position = c + Vector3(0, 2.0, -0.1)
	shot.add_child(wall)
	for side in [-1, 1]:
		box(shot, Vector3(0.3, 4.6, 0.4), c + Vector3(side * 3.25, 2.1, 0), Color("3b2414"))
		# Side walls: we are inside the bar now.
		box(shot, Vector3(0.2, 4.6, 6.0), c + Vector3(side * 3.5, 2.1, 3.0), Color("2a1a10"))
	box(shot, Vector3(6.9, 0.32, 0.45), c + Vector3(0, 4.3, 0), Color("3b2414"))
	bulbs(shot, c + Vector3(-3.0, 4.05, 0.3), c + Vector3(3.0, 4.05, 0.3), 13, 0.12)
	neon_bottle(shot, c + Vector3(-2.55, 2.6, 0.06), 1.0, NEON["bar"])
	_spots(shot, c, 4.6, 4.0, 1.8, 3.2, true)


static func _carnival(shot: BottleShot, c: Vector3) -> void:
	# Shooting gallery booth: striped back, red frame with bulbs, scalloped awning, counter.
	stripes(shot, c + Vector3(0, 2.2, -0.1), Vector2(6.4, 4.4), 16, Color("fff1d6"), Color("d8283a"), 0.2)
	for side in [-1, 1]:
		box(shot, Vector3(0.35, 5.0, 0.35), c + Vector3(side * 3.3, 2.5, 0.2), Color("b8262e"))
		bulbs(shot, c + Vector3(side * 3.1, 0.6, 0.4), c + Vector3(side * 3.1, 4.6, 0.4), 9, 0.0)
	box(shot, Vector3(7.0, 0.5, 0.4), c + Vector3(0, 4.95, 0.2), Color("b8262e"))
	bulbs(shot, c + Vector3(-3.1, 4.95, 0.45), c + Vector3(3.1, 4.95, 0.45), 15, 0.0)
	# Awning: alternating panels tilting out over the counter.
	for i in 10:
		var p := box(shot, Vector3(0.7, 0.05, 1.4), c + Vector3(-3.15 + 0.7 * i, 5.35, 0.9), Color("fff1d6") if i % 2 == 0 else Color("d8283a"))
		p.rotation.x = deg_to_rad(-18)
	box(shot, Vector3(7.0, 0.75, 0.5), c + Vector3(0, 0.375, 2.2), Color("6b1a20"))
	box(shot, Vector3(7.2, 0.08, 0.7), c + Vector3(0, 0.77, 2.2), Color("e8c27a"))
	# Pennants on a string out front.
	var pm := WeaponModels.mat(Color("ffd23f"), 0.0, 0.6)
	for i in 12:
		var f := box(shot, Vector3(0.3, 0.35, 0.02), c + Vector3(-3.3 + 0.6 * i, 5.9 - 0.25 * sin(i / 11.0 * PI), 3.2), Color.WHITE)
		f.material_override = pm if i % 2 == 0 else WeaponModels.mat(Color("3fa9ff"), 0.0, 0.6)
	neon_bottle(shot, c + Vector3(0, 5.55, 0.6), 0.9, NEON["carnival"])
	_spots(shot, c, 6.0, 6.0, 1.8, 4.0, false)


static func _docks(shot: BottleShot, c: Vector3) -> void:
	# A container wall, crates stacked to the sides, bollards and a harbour lamp.
	for k in 3:
		var col: Color = [Color("2f6fa8"), Color("b2462a"), Color("2f8a5a")][k]
		var cont := box(shot, Vector3(2.5, 2.6, 6.0), c + Vector3(-2.6 + 2.6 * k, 1.3, -3.1), col)
		for r in 8:
			box(cont, Vector3(0.06, 2.4, 0.02), Vector3(-1.05 + r * 0.3, 0, 3.01), col.darkened(0.25))
	box(shot, Vector3(2.5, 2.6, 6.0), c + Vector3(-1.3, 3.9, -3.1), Color("c78a2a"))
	for side in [-1, 1]:
		for h in 3:
			box(shot, Vector3(1.0, 0.9, 1.0), c + Vector3(side * (3.0 + 0.1 * h), 0.45 + 0.9 * h, 0.4), Color("8a6236").darkened(0.1 * h))
	var lamp := box(shot, Vector3(0.14, 6.0, 0.14), c + Vector3(3.9, 3.0, 2.0), Color("2b2b2b"))
	var head := box(lamp, Vector3(0.5, 0.18, 0.3), Vector3(-0.3, 3.0, 0), Color("ffe9b0"), 3.0)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	neon_bottle(shot, c + Vector3(1.2, 3.0, 0.02), 1.2, NEON["docks"])
	_spots(shot, c, 6.5, 7.0, 1.8, 4.5, false)


static func _factory(shot: BottleShot, c: Vector3) -> void:
	box(shot, Vector3(7.0, 5.0, 0.3), c + Vector3(0, 2.5, -0.15), Color("4a5058"))
	for r in 6:
		box(shot, Vector3(7.0, 0.05, 0.02), c + Vector3(0, 0.6 + r * 0.8, 0.01), Color("3a3f46"))
	# Hazard band and side columns.
	for i in 18:
		var s := box(shot, Vector3(0.45, 0.3, 0.04), c + Vector3(-3.6 + 0.42 * i, 4.6, 0.04), Color("ffc22e") if i % 2 == 0 else Color("1b1b1b"))
		s.rotation.z = 0.0
	for side in [-1, 1]:
		box(shot, Vector3(0.4, 5.4, 0.4), c + Vector3(side * 3.4, 2.7, 0.2), Color("5d6670"))
		var lamp := box(shot, Vector3(0.5, 0.2, 0.5), c + Vector3(side * 2.0, 5.2, 1.2), Color("ffab3d"), 4.0)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	neon_bottle(shot, c + Vector3(-2.6, 3.0, 0.06), 1.1, NEON["factory"])
	_spots(shot, c, 5.5, 5.0, 1.8, 3.6, false)


static func _rooftop(shot: BottleShot, c: Vector3) -> void:
	# The far building: its roof is the lounge floor (c.y = elevation).
	var tower := box(shot, Vector3(16.0, c.y, 10.0), Vector3(c.x, c.y * 0.5, c.z - 2.0), Color("23202e"))
	var wm := WeaponModels.mat(Color("ffd98a"), 0.0, 0.5, 1.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for fl in int(c.y / 3.2):
		for k in 7:
			if rng.randf() < 0.55:
				var w := box(tower, Vector3(1.2, 1.4, 0.05), Vector3(-6.0 + 2.0 * k, -c.y * 0.5 + 1.8 + fl * 3.2, 5.03), Color.WHITE)
				w.material_override = wm
	box(shot, Vector3(16.4, 0.5, 0.4), c + Vector3(0, 0.25, 3.0), Color("17141f"))
	# Lounge: back wall with neon, bar counter, string lights, a parasol.
	box(shot, Vector3(8.0, 3.4, 0.3), c + Vector3(0, 1.7, -0.2), Color("2e2440"))
	neon_bottle(shot, c + Vector3(-2.9, 1.0, 0.0), 1.6, NEON["rooftop"])
	neon_bottle(shot, c + Vector3(2.9, 1.0, 0.0), 1.6, Color("3fe0ff"))
	bulbs(shot, c + Vector3(-4.0, 3.4, 1.0), c + Vector3(4.0, 3.4, 1.0), 15, 0.4, Color("ffcf7a"))
	var umb := box(shot, Vector3(0.08, 2.4, 0.08), c + Vector3(3.6, 1.2, 1.6), Color("ddd"))
	box(umb, Vector3(1.8, 0.1, 1.8), Vector3(0, 1.2, 0), Color("ff3bd5"))
	_spots(shot, c, 4.0, 4.0, 1.4, 3.0, false)
	# Our own roof: a parapet just below the scope, gravel, a water tank to the side.
	var h := shot.hero_pos
	box(shot, Vector3(6.0, 1.0, 0.5), Vector3(h.x, c.y + 0.5, h.z - 1.0), Color("6b6460"))
	box(shot, Vector3(6.0, c.y, 6.0), Vector3(h.x, c.y * 0.5 - 0.02, h.z + 1.5), Color("4a4542"))
	var tank := WeaponModels.tube(shot, 0.9, 2.0, Vector3(h.x - 3.4, c.y + 1.6, h.z - 0.4), WeaponModels.mat(Color("7a5236"), 0.0, 0.8))
	tank.rotation.x = PI * 0.5


# ---------------------------------------------------------------- street-end facade

## The stash's street front for district `d`: what the squad runs at before bursting in.
## About 9 m wide, front face at local z = +2.
static func facade(d: int) -> Node3D:
	var root := Node3D.new()
	var theme := theme_of(d)
	var neon: Color = NEON[theme]
	match theme:
		"carnival":
			stripes(root, Vector3(0, 3.0, 0), Vector2(9.0, 6.0), 12, Color("fff1d6"), Color("d8283a"), 4.0)
			for i in 12:
				var t := box(root, Vector3(0.75, 0.6, 0.05), Vector3(-4.12 + 0.75 * i, 6.2, 2.1), Color("ffd23f") if i % 2 == 0 else Color("3fa9ff"))
				t.rotation.z = PI * 0.25
			bulbs(root, Vector3(-4.4, 6.0, 2.15), Vector3(4.4, 6.0, 2.15), 13, 0.0)
			box(root, Vector3(3.0, 1.1, 0.3), Vector3(0, 0.55, 2.2), Color("6b1a20"))
		"docks":
			box(root, Vector3(9.0, 6.0, 4.0), Vector3(0, 3.0, 0), Color("4d6a80"))
			for r in 14:
				box(root, Vector3(0.08, 5.8, 0.04), Vector3(-4.2 + r * 0.65, 3.0, 2.02), Color("3b5466"))
			for side in [-1, 1]:
				for h in 2:
					box(root, Vector3(1.2, 1.1, 1.2), Vector3(side * 3.4, 0.55 + 1.1 * h, 3.0), Color("8a6236").darkened(0.12 * h))
		"factory":
			box(root, Vector3(9.0, 6.5, 4.0), Vector3(0, 3.25, 0), Color("5d6670"))
			WeaponModels.tube(root, 0.6, 5.0, Vector3(3.2, 8.0, -1.0), WeaponModels.mat(Color("8a4a3a"), 0.0, 0.8)).rotation.x = PI * 0.5
			for i in 16:
				box(root, Vector3(0.5, 0.35, 0.04), Vector3(-4.2 + 0.56 * i, 6.0, 2.02), Color("ffc22e") if i % 2 == 0 else Color("1b1b1b"))
		"rooftop":
			box(root, Vector3(9.0, 14.0, 4.0), Vector3(0, 7.0, 0), Color("23202e"))
			var wm := WeaponModels.mat(Color("ffd98a"), 0.0, 0.5, 1.6)
			for fl in 4:
				for k in 4:
					var w := box(root, Vector3(1.2, 1.4, 0.05), Vector3(-3.0 + 2.0 * k, 4.5 + fl * 2.6, 2.03), Color.WHITE)
					w.material_override = wm
		_:
			box(root, Vector3(9.0, 6.0, 4.0), Vector3(0, 3.0, 0), Color("4a3b3b"))
			box(root, Vector3(9.6, 0.6, 4.6), Vector3(0, 6.3, 0), Color("2b2222"))
			var aw := box(root, Vector3(4.0, 0.1, 1.2), Vector3(0, 3.6, 2.6), Color("6b1a20"))
			aw.rotation.x = deg_to_rad(-15)
			for x in [-3.0, 3.0]:
				box(root, Vector3(1.6, 1.0, 0.1), Vector3(x, 2.4, 2.05), Color("ffcf7a"), 1.2)
	if theme != "carnival":
		box(root, Vector3(2.4, 3.2, 0.2), Vector3(0, 1.6, 2.05), Color("8c2a2a"))
	var sign_y := 12.0 if theme == "rooftop" else 4.2
	neon_bottle(root, Vector3(0, sign_y, 2.2), 1.6, neon)
	return root
