class_name Fx
extends Node3D
## Pooled visual effects: projectiles (knives, bullets, tracers, pellets, sniper rounds,
## rockets, lobbed firebombs), cube particles, lingering fires and floating numbers.
## All MultiMesh based, so a big fight costs a handful of draw calls.

const MAX_PROJ := 320
const MAX_LOB := 48
const MAX_PARTS := 600
const MAX_FIRES := 6
const MAX_BOMBS := 8
## Bullet-mesh scale per projectile kind (x/y thickness, z length).
const BULLET_SCALE := {
	"bullet": Vector3(0.75, 0.75, 1), "bullet_big": Vector3(1.3, 1.3, 1.6), "tracer": Vector3(0.6, 0.6, 0.8),
	"pellet": Vector3(0.6, 0.6, 0.45), "sniper_round": Vector3(0.7, 0.7, 4.0), "rocket": Vector3(2.4, 2.4, 1.1),
}

var font: Font

var _proj: Array = []      # {pos, vel, t, kind, spin}
var _parts: Array = []     # {pos, vel, t, life, col, size, grav}
var _knife_mm: MultiMesh
var _bullet_mm: MultiMesh
var _lob_mm: MultiMesh     # firebomb bottles and grenades (lit, tumbling)
var _bomb_mm: MultiMesh    # the hero's thrown bombs (round, with a sparking fuse)
var _fires: Array = []     # {pos, t, life}: burning patches on the road
var _part_mm: MultiMesh
var _labels: Array[Label3D] = []
var _label_state: Array = []
var scroll_speed := 0.0    # particles on the ground drift with the road
var _trail := Color.TRANSPARENT
## The street's clock for effects (LevelView sets it every frame): 0 while the game is paused
## or a first-run lesson holds the street, so a bomb in the air waits with the sim.
var time_scale := 1.0
## The bomb in the hero's hand during his wind-up (LevelView sets it; held_bomb_on = false: none).
var held_bomb := Vector3.ZERO
var held_bomb_on := false
const BOMB_HAND_SCALE := 0.8   # the bomb in his hand (r = 0.36 m mesh)
const BOMB_FLY_SCALE := 1.7    # in the air, so it still reads as a bomb far down the street


func _ready() -> void:
	_knife_mm = _mm(_knife_mesh(), MAX_PROJ, false, _lit_vertex_mat())
	# Semi-transparent tracers: a big army's fire reads as streaks, not a white wall.
	var bm := _unshaded_vertex_mat() as StandardMaterial3D
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(1, 1, 1, 0.6)
	_bullet_mm = _mm(_bullet_mesh(), MAX_PROJ, false, bm)
	_lob_mm = _mm(_bottle_mesh(), MAX_LOB, false, _lit_vertex_mat())
	# The bomb is drawn flat and near-black like the HUD's bomb icon, with a pale rim.
	var bomb_mat := _unshaded_vertex_mat() as StandardMaterial3D
	bomb_mat.vertex_color_is_srgb = true
	_bomb_mm = _mm(_bomb_mesh(), MAX_BOMBS, false, bomb_mat)
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	_part_mm = _mm(cube, MAX_PARTS, true, _unshaded_instance_mat())


## Knife skin cosmetic: blade colour and an optional particle trail ("" = none).
func set_knife_skin(blade: Color, trail: String) -> void:
	_knife_mm.mesh = _knife_mesh(blade)
	_trail = Color(trail) if trail != "" else Color.TRANSPARENT


## Spec v2 §3: one of every effect at `at` (below the road, out of sight) so their shaders
## compile while a level loads; the floating-number pool is filled now, not mid-fight.
func prewarm(at: Vector3) -> void:
	for k in ["knife", "bullet"]:
		shoot(k, at, at + Vector3(0, 0, -0.5), 1.0)
	lob(at, at + Vector3(0, 0, -0.5), 0.3, 0.2)
	bomb(at, at + Vector3(0, 0, -0.5), 0.3, 0.2)
	blast(at, 1.0, 0.0)
	burst(at, Color.WHITE, 2, 0.1, 0.2, 0.1, 0.0, 0.0)
	for i in 12:
		float_text("0", at, Color(1, 1, 1, 0), 1.0, 0.0, 0.05)


func clear() -> void:
	_proj.clear()
	held_bomb_on = false
	time_scale = 1.0
	_parts.clear()
	_fires.clear()
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
	_proj.append({"pos": from, "vel": d / t, "t": t, "kind": kind, "spin": randf() * TAU, "grav": 0.0})
	return t


## Lobs a tumbling bottle/grenade from `from` so it lands on `to` after `t` seconds, peaking
## `height` metres above the higher end. It just vanishes on landing: the caller shows the
## outcome when the sim reports it.
func lob(from: Vector3, to: Vector3, t: float, height := 5.0) -> void:
	if _proj.size() >= MAX_PROJ:
		return
	t = maxf(t, 0.2)
	var peak := maxf(from.y, to.y) + height
	# Solve the vertical launch speed and gravity for that apex and flight time.
	var g := 2.0 * ((peak - from.y) + (peak - to.y) + 2.0 * sqrt((peak - from.y) * (peak - to.y))) / (t * t)
	var vy := (to.y - from.y) / t + 0.5 * g * t
	var vel := Vector3((to.x - from.x) / t, vy, (to.z - from.z) / t)
	_proj.append({"pos": from, "vel": vel, "t": t, "kind": "lob", "spin": randf() * TAU, "grav": g})


## Spec v2 §12.5: the hero's bomb, a round black bomb with a sparking fuse, arcing from his
## hand to `to` in `t` seconds. Like lob(), it vanishes on landing: the sim's "bomb" event
## shows the blast (and calls land_bomb(id) so the two always meet).
func bomb(from: Vector3, to: Vector3, t: float, height := 4.0, id := 0) -> void:
	lob(from, to, t, height)
	if not _proj.is_empty() and _proj.back()["kind"] == "lob":
		_proj.back()["kind"] = "bomb"
		_proj.back()["id"] = id
		_proj.back()["t0"] = maxf(t, 0.2)


## The sim's blast went off: the bomb `id` (0: every bomb) leaves the air now.
func land_bomb(id := 0) -> void:
	var i := 0
	while i < _proj.size():
		if String(_proj[i]["kind"]) == "bomb" and (id == 0 or int(_proj[i].get("id", 0)) == id):
			_proj.remove_at(i)
		else:
			i += 1


## The bomb's blast: a fireball that fills `radius` metres (what it hits is what looks hit),
## a shock ring at that radius, smoke and debris. `far` (0..1, by distance from the camera)
## thickens the particles so a blast 50 m down the street still reads.
func blast(at: Vector3, radius: float, far := 0.0) -> void:
	var k := 1.0 + 1.6 * clampf(far, 0.0, 1.0)
	var life := 0.6
	# Particles slow by about half over their life (_tick_parts drag): speed ~ 2 x radius / life.
	var v := 2.0 * radius / life
	burst(at + Vector3(0, 0.4, 0), Color(1.0, 0.62, 0.05), 26, v, 0.45 * k, life, 5.0, 6.0)
	burst(at + Vector3(0, 0.4, 0), Color(0.95, 0.22, 0.02), 22, v * 0.8, 0.6 * k, life * 1.1, 4.0, 5.0)
	burst(at + Vector3(0, 0.6, 0), Color(0.12, 0.11, 0.11), 16, v * 0.45, 0.8 * k, 1.1, 6.0, 1.0)
	burst(at + Vector3(0, 0.3, 0), Color(0.06, 0.06, 0.07), 10, v * 0.7, 0.18 * k, 0.8, 7.0, 16.0)
	for i in 36:
		if _parts.size() >= MAX_PARTS:
			_parts.pop_front()
		var a := TAU * i / 36
		_parts.append({"pos": at + Vector3(0, 0.15, 0), "vel": Vector3(cos(a), 0.0, sin(a)) * (2.0 * radius / 0.45),
			"t": 0.0, "life": 0.45, "col": Color("ffb347"), "size": 0.3 * k, "grav": 0.0})


## A gun's muzzle flash: a quick bright pop (enemy return fire).
func muzzle(at: Vector3) -> void:
	burst(at, Color(1.0, 0.95, 0.6), 3, 1.2, 0.26, 0.07, 0.0, 0.0)
	burst(at, Color(1.0, 0.6, 0.2), 2, 2.0, 0.14, 0.1, 0.0, 0.0)


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


## Flat ring of sparks spreading along the road (revive, new rank).
func ring(at: Vector3, color: Color, n := 36, speed := 9.0, size := 0.2) -> void:
	for i in n:
		if _parts.size() >= MAX_PARTS:
			_parts.pop_front()
		var a := TAU * i / n
		_parts.append({"pos": at, "vel": Vector3(cos(a), 0.15, sin(a)) * speed * randf_range(0.85, 1.1),
			"t": 0.0, "life": 0.55, "col": color, "size": size, "grav": 0.0})


## Splash of burning fuel that keeps flickering on the road for `life` seconds.
func fire(at: Vector3, life := 1.4) -> void:
	burst(at + Vector3(0, 0.3, 0), Color(1.0, 0.55, 0.1), 30, 8.0, 0.45, 0.6, 4.0, 8.0)
	burst(at + Vector3(0, 0.3, 0), Color(1.0, 0.3, 0.08), 16, 6.0, 0.32, 0.5, 5.0, 8.0)
	if _fires.size() >= MAX_FIRES:
		_fires.pop_front()
	_fires.append({"pos": at, "t": 0.0, "life": life})


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
	delta *= maxf(time_scale, 0.0)
	_tick_proj(delta)
	_tick_fires(delta)
	_tick_parts(delta)
	_tick_labels(delta)


func _tick_proj(delta: float) -> void:
	var kn := 0
	var bn := 0
	var ln := 0
	var mn := 0
	var i := 0
	while i < _proj.size():
		var p: Dictionary = _proj[i]
		var kind: String = p["kind"]
		p["t"] = float(p["t"]) - delta
		if float(p["t"]) <= 0.0:
			if kind == "rocket":
				explosion(p["pos"], 0.35)
			_proj.remove_at(i)
			continue
		var vel: Vector3 = p["vel"]
		if float(p["grav"]) != 0.0:
			vel.y -= float(p["grav"]) * delta
			p["vel"] = vel
		p["pos"] = (p["pos"] as Vector3) + vel * delta
		var basis := Basis.looking_at(vel.normalized(), Vector3.UP) if vel.length() > 0.01 else Basis()
		if kind == "lob":
			p["spin"] = float(p["spin"]) + delta * 12.0
			if randf() < 0.7:
				burst(p["pos"], Color(1.0, 0.5 + randf() * 0.3, 0.1), 2, 0.8, 0.55, 0.45, 1.0, -2.0)
			if ln < MAX_LOB:
				_lob_mm.set_instance_transform(ln, Transform3D(Basis(Vector3.RIGHT, float(p["spin"])).scaled(Vector3.ONE * 1.8), p["pos"]))
				ln += 1
		elif kind == "bomb":
			# A slow tumble; it grows from hand size as it flies so it still reads far away.
			p["spin"] = float(p["spin"]) + delta * 5.0
			var u := 1.0 - clampf(float(p["t"]) / float(p.get("t0", 1.0)), 0.0, 1.0)
			var sc := lerpf(BOMB_HAND_SCALE, BOMB_FLY_SCALE, minf(u * 2.5, 1.0))
			var rot := Basis(Vector3.RIGHT, float(p["spin"]))
			_bomb_fuse(p["pos"], rot, sc, true)
			if mn < MAX_BOMBS:
				_bomb_mm.set_instance_transform(mn, Transform3D(rot.scaled(Vector3.ONE * sc), p["pos"]))
				mn += 1
		elif kind == "knife":
			p["spin"] = float(p["spin"]) + delta * 28.0
			if _trail.a > 0.0 and randf() < 0.6:
				burst(p["pos"], _trail, 1, 0.4, 0.1, 0.25, 0.0, 0.0)
			basis = basis * Basis(Vector3.RIGHT, float(p["spin"]))
			_knife_mm.set_instance_transform(kn, Transform3D(basis, p["pos"]))
			kn += 1
		else:
			if kind == "rocket" and randf() < 0.3:
				# Light smoke: many launchers at once must not wall off the street.
				burst(p["pos"], Color(0.75, 0.75, 0.78), 1, 0.5, 0.18, 0.35, 0.6, -1.0)
			var sc: Vector3 = BULLET_SCALE.get(kind, Vector3(0.8, 0.8, 0.8))
			_bullet_mm.set_instance_transform(bn, Transform3D(basis.scaled_local(sc), p["pos"]))
			bn += 1
		i += 1
	if held_bomb_on and mn < MAX_BOMBS:
		_bomb_fuse(held_bomb, Basis(), BOMB_HAND_SCALE, false)
		_bomb_mm.set_instance_transform(mn, Transform3D(Basis().scaled(Vector3.ONE * BOMB_HAND_SCALE), held_bomb))
		mn += 1
	_knife_mm.visible_instance_count = kn
	_bullet_mm.visible_instance_count = bn
	_lob_mm.visible_instance_count = ln
	_bomb_mm.visible_instance_count = mn


## The lit fuse: orange-yellow sparks from its tip (and a thin smoke trail in flight).
func _bomb_fuse(pos: Vector3, rot: Basis, sc: float, flying: bool) -> void:
	var tip := pos + rot * Vector3(0, 0.6 * sc, 0)
	burst(tip, Color(1.0, 0.3 + randf() * 0.35, 0.0), 2, 2.6, 0.12 * sc, 0.2, 1.0, 5.0)
	if randf() < 0.6:
		burst(tip, Color(1.0, 0.7, 0.15), 1, 0.4, 0.18 * sc, 0.08, 0.0, 0.0)
	if flying and randf() < 0.45:
		burst(pos, Color(0.3, 0.3, 0.32), 1, 0.2, 0.14 * sc, 0.45, 0.3, -0.5)


func _tick_fires(delta: float) -> void:
	var i := 0
	while i < _fires.size():
		var f: Dictionary = _fires[i]
		f["t"] = float(f["t"]) + delta
		if float(f["t"]) >= float(f["life"]):
			_fires.remove_at(i)
			continue
		var p: Vector3 = f["pos"]
		p.z += scroll_speed * delta
		f["pos"] = p
		var k := 1.0 - float(f["t"]) / float(f["life"])
		# Flames lick upwards (negative gravity) from a spread-out puddle.
		var at := p + Vector3(randf_range(-1.1, 1.1), 0.15, randf_range(-0.8, 0.8))
		burst(at, Color(1.0, 0.45 + randf() * 0.4, 0.1), 1, 0.6, 0.5 * k + 0.15, 0.45, 2.5, -4.0)
		if randf() < 0.3:
			burst(at + Vector3(0, 0.8, 0), Color(0.25, 0.22, 0.22), 1, 0.4, 0.4, 0.8, 1.5, -2.0)
		i += 1


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


## Firebomb: green glass bottle with a burning rag.
func _bottle_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cube(st, Vector3(0, -0.1, 0), Vector3(0.5, 0.75, 0.5), Color(0.2, 0.55, 0.28))
	_cube(st, Vector3(0, 0.42, 0), Vector3(0.2, 0.3, 0.2), Color(0.2, 0.55, 0.28))
	_cube(st, Vector3(0, 0.68, 0), Vector3(0.28, 0.26, 0.28), Color(1.0, 0.75, 0.3))
	st.generate_normals()
	return st.commit()


## The hero's bomb, like the HUD's bomb icon: a round near-black body with a small shine, a
## steel cap and a fuse, inside a pale inside-out shell that draws as a rim around it
## (unshaded, so it reads as a black bomb on any street). Sparks come from _bomb_fuse.
func _bomb_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := 0.36
	var rings := 8
	var segs := 12
	for shell in 2:
		var rr := r if shell == 0 else r * 1.14
		for j in rings:
			var a0 := PI * j / rings
			var a1 := PI * (j + 1) / rings
			for k in segs:
				var b0 := TAU * k / segs
				var b1 := TAU * (k + 1) / segs
				var col := Color(0.05, 0.05, 0.07)
				if shell == 1:
					col = Color(0.95, 0.9, 0.8)
				elif j == 2 and k == 8:
					col = Color(0.36, 0.38, 0.45)   # a small shine
				var q := [_sph(rr, a0, b0), _sph(rr, a0, b1), _sph(rr, a1, b1), _sph(rr, a1, b0)]
				# Clockwise from outside (like _cube) for the body; the rim shell is wound the
				# other way, so only its far side draws: a pale outline behind the bomb.
				var tris := [[0, 2, 1], [0, 3, 2]] if shell == 0 else [[0, 1, 2], [0, 2, 3]]
				for tri in tris:
					for n in tri:
						st.set_color(col)
						st.add_vertex(q[n])
	_cube(st, Vector3(0, r + 0.05, 0), Vector3(0.2, 0.14, 0.2), Color(0.3, 0.31, 0.35))
	_cube(st, Vector3(0, r + 0.22, 0), Vector3(0.07, 0.24, 0.07), Color(0.5, 0.33, 0.15))
	return st.commit()


static func _sph(r: float, a: float, b: float) -> Vector3:
	return Vector3(sin(a) * cos(b), cos(a), sin(a) * sin(b)) * r


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
