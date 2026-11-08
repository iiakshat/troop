class_name Shatter
extends Node3D
## One bottle breaking: glass shards peeled off the bottle's surface (one MultiMesh), the
## drink sprayed as thin velocity-stretched streaks, a pinch of glass glitter, the flying
## neck, and a wet stain spreading on the wall. No spheres anywhere. BottleShot drives it
## with the finale's own delta, so it all slows down with the slow motion.

const SHARD_SHADER := preload("res://src/finale/shard.gdshader")
const STREAK_SHADER := preload("res://src/finale/streak.gdshader")
const SPLAT_SHADER := preload("res://src/finale/splat.gdshader")
const GRAV := 9.8

var _mm: MultiMesh
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _axis := PackedVector3Array()
var _spin := PackedFloat32Array()
var _basis: Array = []
var _scl: Array = []            # Vector3 non-uniform scale per shard
var _rest := PackedByteArray()
var _moving := 0

var _smm: MultiMesh
var _spos := PackedVector3Array()
var _svel := PackedVector3Array()
var _slife := PackedFloat32Array()
var _smax := PackedFloat32Array()
var _swidth := PackedFloat32Array()
var _sgrav := PackedFloat32Array()
var _scol: Array = []
var _salive := 0

var _pieces: Array = []         # {node, vel, axis, spin, rest, r}
var _wall_front := 0.0
var _shelf := {}                # {y, x0, x1, z0, z1} or empty
var _splat: ShaderMaterial
var _age := 0.0


## at = bottle base (world), scale = bottle scale, dir = knife travel direction.
func setup(at: Vector3, scale: float, dir: Vector3, glass: Color, drink: Color, gold: bool,
		wall_front: float, shelf: Dictionary, neck: Node3D, height: float) -> Shatter:
	top_level = true
	_wall_front = wall_front
	_shelf = shelf
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_build_shards(rng, at, scale, dir, glass, gold, height)
	_build_streaks(rng, at, scale, dir, drink, gold, height)
	if neck:
		add_child(neck)
		var pivot := float(neck.get_meta("pivot", 0.4))
		neck.position = at + Vector3(0, pivot * scale, 0)
		neck.scale = Vector3.ONE * scale
		_pieces.append({"node": neck, "vel": Vector3(rng.randf_range(0.6, 1.3) * (1.0 if rng.randf() < 0.5 else -1.0), rng.randf_range(1.4, 2.2), rng.randf_range(-0.1, 0.4)),
			"axis": Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1)).normalized(),
			"spin": rng.randf_range(7.0, 12.0), "rest": false, "r": 0.034 * scale})
	_build_splat(rng, at, scale, drink, height)
	return self


func tick(d: float, cam_pos: Vector3) -> void:
	_age += d
	if _splat:
		_splat.set_shader_parameter("age", _age)
	if d <= 0.0:
		_update_streaks(0.0, cam_pos)
		return
	if _moving > 0:
		_update_shards(d)
	if _salive > 0:
		_update_streaks(d, cam_pos)
	for p in _pieces:
		if not p["rest"]:
			_update_piece(p, d)


## True while anything is still flying (used to keep ticking only while needed).
func busy() -> bool:
	return _moving > 0 or _salive > 0 or _age < 2.0


# ---------------------------------------------------------------- shards

func _build_shards(rng: RandomNumberGenerator, at: Vector3, scale: float, dir: Vector3, glass: Color, gold: bool, height: float) -> void:
	var n := 96 if gold else 78
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = _shard_mesh()
	_mm.instance_count = n
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = SHARD_SHADER
	var tint := Color(glass.r, glass.g, glass.b).lerp(Color(1, 1, 1), 0.5)
	if gold:
		tint = Color(1.0, 0.82, 0.38)
	mat.set_shader_parameter("tint", tint)
	mi.material_override = mat
	add_child(mi)
	for i in n:
		var y := rng.randf_range(0.05, height * 0.82) * scale
		var th := rng.randf() * TAU
		var r := (0.088 if y < 0.36 * scale else 0.045) * scale
		var radial := Vector3(cos(th), 0.0, sin(th))
		var p := at + radial * r + Vector3(0, y, 0)
		var tangent := Vector3(-sin(th), 0.0, cos(th))
		var b := Basis(-tangent, Vector3.UP, radial).rotated(radial, rng.randf() * TAU)
		var size := pow(rng.randf(), 1.6)
		var s := Vector3(lerpf(0.014, 0.06, size), lerpf(0.018, 0.075, size) * rng.randf_range(0.7, 1.3), 1.0) * scale
		# Blown outwards, pushed on by the knife, lifted a little; the front of the bottle
		# sprays back towards the thrower, the back slams into the wall and bounces.
		var v := radial * rng.randf_range(0.7, 2.6) + dir * rng.randf_range(0.2, 1.4) + Vector3.UP * rng.randf_range(0.3, 2.0)
		_pos.append(p)
		_vel.append(v)
		_axis.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized())
		_spin.append(rng.randf_range(8.0, 26.0))
		_basis.append(b)
		_scl.append(s)
		_rest.append(0)
		_mm.set_instance_transform(i, Transform3D(b * Basis.from_scale(s), p))
		_mm.set_instance_custom_data(i, Color(1.0, rng.randf(), 0, 0))
	_moving = n


func _update_shards(d: float) -> void:
	_moving = 0
	for i in _pos.size():
		if _rest[i] == 1:
			continue
		var v := _vel[i]
		var p := _pos[i]
		v.y -= GRAV * d
		var prev := p
		p += v * d
		var b: Basis = _basis[i]
		b = b.rotated(_axis[i], _spin[i] * d)
		# bounce off the wall behind the bottles
		if p.z < _wall_front + 0.004 and v.z < 0.0:
			p.z = _wall_front + 0.004
			v = Vector3(v.x * 0.6, v.y * 0.6, -v.z * 0.3)
			_spin[i] *= 0.6
		var ground := _ground_at(p, prev)
		if p.y < ground and v.y < 0.0:
			p.y = ground + 0.002
			if absf(v.y) < 0.8:
				# lies flat where it landed
				_rest[i] = 1
				v = Vector3.ZERO
				b = Basis(Vector3.RIGHT, -PI * 0.5).rotated(Vector3.UP, randf() * TAU)
			else:
				v = Vector3(v.x * 0.45, -v.y * 0.3, v.z * 0.45)
				_spin[i] *= 0.5
		_vel[i] = v
		_pos[i] = p
		_basis[i] = b
		_mm.set_instance_transform(i, Transform3D(b * Basis.from_scale(_scl[i]), p))
		if _rest[i] == 0:
			_moving += 1


## Height of whatever a falling piece would land on at p: the shelf top (static racks only)
## if it is above it, else the street.
func _ground_at(p: Vector3, prev: Vector3) -> float:
	if not _shelf.is_empty():
		var sy := float(_shelf["y"])
		if prev.y >= sy - 0.01 and p.x > float(_shelf["x0"]) and p.x < float(_shelf["x1"]) \
				and p.z > float(_shelf["z0"]) and p.z < float(_shelf["z1"]):
			return sy
	return 0.01


static var _shard_cache: ArrayMesh

## A thin triangle (UVs give the shader its cut edges).
static func _shard_mesh() -> ArrayMesh:
	if _shard_cache:
		return _shard_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.35, 0), Vector3(-0.1, 0.5, 0)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]
	for k in 3:
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(uvs[k])
		st.add_vertex(pts[k])
	_shard_cache = st.commit()
	return _shard_cache


# ---------------------------------------------------------------- streaks (drink + glitter)

func _build_streaks(rng: RandomNumberGenerator, at: Vector3, scale: float, dir: Vector3, drink: Color, gold: bool, height: float) -> void:
	var n_drink := 44
	var n_glit := 48 if gold else 16
	var n := n_drink + n_glit
	_smm = MultiMesh.new()
	_smm.transform_format = MultiMesh.TRANSFORM_3D
	_smm.use_colors = true
	_smm.mesh = _streak_mesh()
	_smm.instance_count = n
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _smm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = STREAK_SHADER
	mi.material_override = mat
	add_child(mi)
	var centre := at + Vector3(0, height * 0.42 * scale, 0)
	for i in n:
		var glitter := i >= n_drink
		var th := rng.randf() * TAU
		var radial := Vector3(cos(th), 0.0, sin(th))
		var v: Vector3
		if glitter:
			v = Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1.0), rng.randf_range(-0.3, 1)).normalized() * rng.randf_range(2.0, 4.5)
		else:
			v = radial * rng.randf_range(0.8, 2.8) + Vector3.UP * rng.randf_range(0.6, 2.6) + dir * rng.randf_range(0.0, 0.8)
		_spos.append(centre + radial * 0.05 * scale + Vector3(0, rng.randf_range(-0.12, 0.08) * scale, 0))
		_svel.append(v)
		var life := rng.randf_range(0.15, 0.35) if glitter else rng.randf_range(0.3, 0.6)
		if glitter and gold:
			life *= 1.8   # the gold bottle sparkles for longer
		_slife.append(life)
		_smax.append(life)
		_swidth.append(rng.randf_range(0.003, 0.006) if glitter else rng.randf_range(0.007, 0.016))
		_sgrav.append(2.5 if glitter else GRAV)
		var c: Color
		if glitter:
			c = Color(1.0, 0.86, 0.45) if gold and i % 2 == 0 else Color(1.0, 0.98, 0.92)
		else:
			c = drink.lerp(Color.WHITE, rng.randf_range(0.0, 0.25))
		_scol.append(c)
	_salive = n


func _update_streaks(d: float, cam_pos: Vector3) -> void:
	_salive = 0
	for i in _spos.size():
		if _slife[i] <= 0.0:
			continue
		var v := _svel[i]
		var p := _spos[i]
		if d > 0.0:
			_slife[i] -= d
			v.y -= _sgrav[i] * d
			p += v * d
			if p.z < _wall_front + 0.01 or p.y < 0.0:
				_slife[i] = 0.0
		_svel[i] = v
		_spos[i] = p
		if _slife[i] <= 0.0:
			_smm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), p))
			continue
		_salive += 1
		var speed := v.length()
		var fwd := v / maxf(speed, 0.001)
		var length := clampf(speed * 0.045, 0.025, 0.17)
		var to_cam := (cam_pos - p).normalized()
		var side := fwd.cross(to_cam)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		side = side.normalized()
		var normal := side.cross(fwd).normalized()
		var b := Basis(side * _swidth[i], fwd * length, normal)
		_smm.set_instance_transform(i, Transform3D(b, p - fwd * length))
		var c: Color = _scol[i]
		c.a = clampf(_slife[i] / _smax[i] * 1.6, 0.0, 1.0)
		_smm.set_instance_color(i, c)


static var _streak_cache: ArrayMesh

## A unit quad from its tail (y = 0) to its head (y = 1).
static func _streak_mesh() -> ArrayMesh:
	if _streak_cache:
		return _streak_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v := [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)]
	var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(uv[k])
		st.add_vertex(v[k])
	_streak_cache = st.commit()
	return _streak_cache


# ---------------------------------------------------------------- pieces and stain

func _update_piece(p: Dictionary, d: float) -> void:
	var node: Node3D = p["node"]
	var v: Vector3 = p["vel"]
	v.y -= GRAV * d
	var prev := node.position
	var pos := prev + v * d
	if pos.z < _wall_front + 0.04 and v.z < 0.0:
		pos.z = _wall_front + 0.04
		v.z = -v.z * 0.3
	node.rotate(p["axis"], float(p["spin"]) * d)
	var ground := _ground_at(pos, prev) + float(p["r"])
	if pos.y < ground and v.y < 0.0:
		pos.y = ground
		if absf(v.y) < 1.0:
			p["rest"] = true
			v = Vector3.ZERO
			# settle on its side
			var yaw := randf() * TAU
			node.basis = Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, yaw).scaled(node.scale)
		else:
			v = Vector3(v.x * 0.5, -v.y * 0.35, v.z * 0.5)
			p["spin"] = float(p["spin"]) * 0.5
	p["vel"] = v
	node.position = pos


func _build_splat(rng: RandomNumberGenerator, at: Vector3, scale: float, drink: Color, height: float) -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.75, 1.0) * scale
	q.mesh = qm
	_splat = ShaderMaterial.new()
	_splat.shader = SPLAT_SHADER
	_splat.set_shader_parameter("color", drink)
	_splat.set_shader_parameter("seed", rng.randf() * 10.0)
	_splat.set_shader_parameter("age", 0.0)
	q.material_override = _splat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(q)
	q.position = Vector3(at.x, at.y + height * 0.62 * scale - 0.15 * scale, _wall_front + 0.003 + rng.randf() * 0.002)
