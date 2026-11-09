extends SceneTree
## Bakes the role characters (config/characters.json) into vertex-animation textures.
##   godot --headless --path . --script res://tools/bake_vat.gd [-- only=hero,sniper]
##
## For every role: load the Quaternius FBX in art_src/characters, recolour its materials,
## attach the weapon to the hand bone, then sample each clip and write every vertex's
## position per frame into one texture row. In game a whole crowd is one MultiMesh whose
## shader reads its pose from that texture (src/game/crowd_vat.gdshader), so hundreds
## of animated people cost a single draw call per role.
##
## Output (res://assets/characters/): <role>_mesh.res, <role>_vat.res (positions),
## <role>_nrm.res (smooth normals per frame, for toon lighting and outlines), clips.json.

const OUT := "res://assets/characters/"
const SRC := "res://art_src/characters/"

var _cfg: Dictionary
var _done := false
var _lengths := {}
var _idle_base: Array = []   # local [pos, rot, scale] of every bone at Idle frame 0
var _throw_ref := {}         # per-role measurements of the idle pose for the throw


func _initialize() -> void:
	pass


## Baking runs on the first frame, once nodes added to the tree are really inside it.
func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _run() -> void:
	_cfg = Config.load_json("res://config/characters.json")
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = Array(a.substr(5).split(","))
	DirAccess.make_dir_recursive_absolute(OUT)
	var clip_table := _clip_table()
	for role in _cfg["roles"]:
		if not only.is_empty() and not only.has(role):
			continue
		var t0 := Time.get_ticks_msec()
		var info := _bake_role(String(role), _cfg["roles"][role])
		print("baked %-10s verts=%d tris=%d rows=%d  %.1fs" % [role, info["verts"], info["tris"], info["rows"], (Time.get_ticks_msec() - t0) / 1000.0])
	for name in _lengths:
		clip_table[name]["length"] = _lengths[name]
	for c in _cfg["clips"]:
		if String(c.get("proc", "")) == "throw":
			# seconds into the clip when the knife leaves the hand (game code times the throw on it)
			clip_table[c["name"]]["release"] = THROW_RELEASE * float(_lengths.get(c["name"], 0.0))
	var f := FileAccess.open(OUT + "clips.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(clip_table, "\t"))
	quit()


func _clip_table() -> Dictionary:
	var rows := 0
	var table := {}
	for c in _cfg["clips"]:
		table[c["name"]] = {"row": rows, "frames": int(c["frames"]), "loop": bool(c["loop"]), "length": 0.0}
		rows += int(c["frames"])
	table["_rows"] = rows
	return table


func _bake_role(role: String, recipe: Dictionary) -> Dictionary:
	var scene: Node3D = (load(SRC + String(recipe["base"]) + ".fbx") as PackedScene).instantiate()
	root.add_child(scene)
	var ap: AnimationPlayer = scene.find_child("AnimationPlayer", true, false)
	var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	var colors: Dictionary = recipe.get("colors", {})

	# --- gather skinned vertices (positions in each mesh's bind space)
	var verts: Array = []      # {v, binds:PackedInt32Array, w:PackedFloat32Array, mesh:int, col}
	var indices := PackedInt32Array()
	var meshes: Array = []     # {skin_poses:Array[Transform3D], bones:PackedInt32Array, to_sk:Transform3D}
	var eye_ids: Array = []
	var seen := {}
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var skin: Skin = m.skin
		var binds := PackedInt32Array()
		var poses: Array = []
		for i in skin.get_bind_count():
			var b := skin.get_bind_bone(i)
			if b < 0:
				b = sk.find_bone(skin.get_bind_name(i))
			binds.append(b)
			poses.append(skin.get_bind_pose(i))
		var mesh_index := meshes.size()
		meshes.append({"binds": binds, "poses": poses})
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var mat := m.mesh.surface_get_material(s)
			var mat_name := mat.resource_name if mat else ""
			var col := Color.MAGENTA
			if mat is StandardMaterial3D:
				col = (mat as StandardMaterial3D).albedo_color
			if colors.has(mat_name):
				col = Color(String(colors[mat_name]))
			var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / maxi(pos.size(), 1)
			var remap := PackedInt32Array()
			remap.resize(pos.size())
			for vi in pos.size():
				var key := "%d|%.4f|%.4f|%.4f|%s" % [mesh_index, pos[vi].x, pos[vi].y, pos[vi].z, col.to_html()]
				if seen.has(key):
					remap[vi] = seen[key]
					continue
				remap[vi] = verts.size()
				seen[key] = verts.size()
				var bb := PackedInt32Array()
				var ww := PackedFloat32Array()
				var total := 0.0
				for k in per:
					var w := weights[vi * per + k]
					if w > 0.0001:
						bb.append(bones[vi * per + k])
						ww.append(w)
						total += w
				for k in ww.size():
					ww[k] /= total
				if mat_name == "Face":
					eye_ids.append(verts.size())
				verts.append({"v": pos[vi], "binds": bb, "w": ww, "mesh": mesh_index, "col": col, "bone": -1})
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				for vi in pos.size():
					indices.append(remap[vi])
			else:
				for i in idx:
					indices.append(remap[i])

	# --- reference frame from the idle pose: height, feet, facing
	_pose(ap, "Idle", 0.0)
	_idle_base = _capture(sk)
	_throw_ref = {}
	var rest: PackedVector3Array = _skin_all(sk, verts, meshes)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var centre := Vector3.ZERO
	for p in rest:
		lo = lo.min(p)
		hi = hi.max(p)
		centre += p
	centre /= rest.size()
	var height := hi.y - lo.y
	var units_per_m := height / float(_cfg["height"])

	# --- weapons: rigid boxes following the hand bones (built in skeleton rest space)
	# Weapons are built in skeleton space, which can have its own unit scale.
	var sk_scale := _to_scene(sk).basis.get_scale().x
	var weapon_verts := _weapons(sk, recipe, units_per_m / maxf(sk_scale, 0.000001), indices, verts.size())
	for wv in weapon_verts:
		verts.append(wv)

	var eye := Vector3.ZERO
	for i in eye_ids:
		eye += rest[i]
	eye /= maxf(eye_ids.size(), 1)
	var faces_plus_z := eye.z > centre.z
	var k := float(_cfg["height"]) * float(recipe.get("scale", 1.0)) / height
	var to_model := Transform3D(Basis(Vector3.UP, PI if faces_plus_z else 0.0).scaled(Vector3.ONE * k), Vector3.ZERO)
	var foot := Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5)

	# --- sample every clip into texture rows
	var table := _clip_table()
	var rows := int(table["_rows"])
	var n := verts.size()
	var data := PackedFloat32Array()
	data.resize(n * rows * 4)
	var ndata := PackedByteArray()
	ndata.resize(n * rows * 4)
	var flip := 0.0  # 1 or -1 once the winding is known
	var first_frame := PackedVector3Array()
	for c in _cfg["clips"]:
		var proc := String(c.get("proc", ""))
		var length := float(c.get("length", 1.0))
		if proc == "":
			length = ap.get_animation(_find_anim(ap, String(c["src"]))).length
		_lengths[c["name"]] = length
		var frames := int(c["frames"])
		var row0 := int(table[c["name"]]["row"])
		for f in frames:
			var t := length * f / frames if bool(c["loop"]) else length * f / maxf(frames - 1, 1)
			if proc == "":
				_pose(ap, String(c["src"]), t)
			else:
				_proc_pose(ap, sk, proc, t / maxf(length, 0.0001))
			var ps := _skin_all(sk, verts, meshes)
			var pm := PackedVector3Array()
			pm.resize(n)
			for vi in n:
				var p := to_model * (ps[vi] - foot)
				pm[vi] = p
				var o := ((row0 + f) * n + vi) * 4
				data[o] = p.x
				data[o + 1] = p.y
				data[o + 2] = p.z
				data[o + 3] = 1.0
				if c["name"] == "idle" and f == 0:
					first_frame.append(p)
			var nm := _normals(pm, indices)
			if flip == 0.0:
				flip = _outward(pm, nm)
			for vi in n:
				var nv := nm[vi] * flip
				var o := ((row0 + f) * n + vi) * 4
				ndata[o] = int(clampf(nv.x * 0.5 + 0.5, 0.0, 1.0) * 255.0)
				ndata[o + 1] = int(clampf(nv.y * 0.5 + 0.5, 0.0, 1.0) * 255.0)
				ndata[o + 2] = int(clampf(nv.z * 0.5 + 0.5, 0.0, 1.0) * 255.0)
				ndata[o + 3] = 255

	var img := Image.create_from_data(n, rows, false, Image.FORMAT_RGBAF, data.to_byte_array())
	img.convert(Image.FORMAT_RGBAH)
	ResourceSaver.save(ImageTexture.create_from_image(img), OUT + role + "_vat.res")
	var nimg := Image.create_from_data(n, rows, false, Image.FORMAT_RGBA8, ndata)
	ResourceSaver.save(ImageTexture.create_from_image(nimg), OUT + role + "_nrm.res")

	var cols := PackedColorArray()
	var uv2 := PackedVector2Array()
	for vi in n:
		cols.append(verts[vi]["col"])
		uv2.append(Vector2(vi, 0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = first_frame
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	ResourceSaver.save(am, OUT + role + "_mesh.res")
	scene.queue_free()
	return {"verts": n, "tris": indices.size() / 3, "rows": rows}


## Smooth vertex normals: area-weighted sum of the faces around each vertex.
func _normals(p: PackedVector3Array, idx: PackedInt32Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(p.size())
	for t in range(0, idx.size(), 3):
		var a := idx[t]
		var b := idx[t + 1]
		var c := idx[t + 2]
		var fn := (p[b] - p[a]).cross(p[c] - p[a])
		out[a] += fn
		out[b] += fn
		out[c] += fn
	for i in out.size():
		out[i] = out[i].normalized() if out[i].length_squared() > 1e-12 else Vector3.UP
	return out


## 1 if the normals point away from the body's centre line, else -1 (winding varies).
func _outward(p: PackedVector3Array, nm: PackedVector3Array) -> float:
	var c := Vector3.ZERO
	for v in p:
		c += v
	c /= maxf(p.size(), 1)
	var score := 0.0
	for i in p.size():
		var d := p[i] - Vector3(c.x, p[i].y, c.z)
		score += d.dot(nm[i])
	return 1.0 if score >= 0.0 else -1.0


func _find_anim(ap: AnimationPlayer, src: String) -> String:
	for a in ap.get_animation_list():
		if String(a).ends_with("|" + src) or String(a) == src:
			return a
	push_error("missing clip " + src)
	return ap.get_animation_list()[0]


func _pose(ap: AnimationPlayer, src: String, t: float) -> void:
	var a := _find_anim(ap, src)
	if ap.current_animation != a:
		ap.play(a)
	ap.seek(t, true)


## Transform of `n` relative to the instanced scene root (works even outside the tree).
func _to_scene(n: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur != null and cur is Node3D and cur.get_parent() != root:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Skinned position of every vertex for the skeleton's current pose, in scene space.
func _skin_all(sk: Skeleton3D, verts: Array, meshes: Array) -> PackedVector3Array:
	sk.force_update_all_bone_transforms()
	var sk_xf := _to_scene(sk)
	var mats: Array = []
	for m in meshes:
		var list: Array = []
		var binds: PackedInt32Array = m["binds"]
		for i in binds.size():
			list.append(sk_xf * sk.get_bone_global_pose(binds[i]) * (m["poses"][i] as Transform3D))
		mats.append(list)
	var bone_xf := {}
	var out := PackedVector3Array()
	out.resize(verts.size())
	for vi in verts.size():
		var vd: Dictionary = verts[vi]
		if int(vd["bone"]) >= 0:
			var b := int(vd["bone"])
			if not bone_xf.has(b):
				bone_xf[b] = sk_xf * sk.get_bone_global_pose(b) * sk.get_bone_global_rest(b).affine_inverse()
			out[vi] = (bone_xf[b] as Transform3D) * (vd["v"] as Vector3)
			continue
		var list: Array = mats[int(vd["mesh"])]
		var binds: PackedInt32Array = vd["binds"]
		var ws: PackedFloat32Array = vd["w"]
		var p := Vector3.ZERO
		for k in binds.size():
			p += ((list[binds[k]] as Transform3D) * (vd["v"] as Vector3)) * ws[k]
		out[vi] = p
	return out


# ---------------------------------------------------------------- procedural clips

## Clips the Quaternius rig does not have. Each frame starts from Idle frame 0 and the
## bake poses the skeleton itself. The overhand knife throw: torso twist and lean, a
## weight shift, two-bone IK for both arms and both legs (the left foot steps), and a
## wrist snap. Keys are in the body frame [right, forward, up]: hands in arm lengths from
## their shoulder, body and step in leg lengths, elbows / wrist as directions, angles in
## degrees (twist > 0 = right shoulder back, lean > 0 = forward). "I" = the idle value.
const THROW_RELEASE := 0.54  # fraction of the clip where the knife leaves the hand
const THROW_KEYS := [
	{"t": 0.0, "twist": 0.0, "lean": 0.0, "body": [0.0, 0.0], "step": [0.0, 0.0],
		"rh": "I", "re": "I", "rw": "I", "lh": "I", "le": "I"},
	# wind-up: knife cocked behind the head, elbow up and out, front arm points at the target
	{"t": 0.3, "twist": 30.0, "lean": -6.0, "body": [-0.03, 0.0], "step": [0.08, 0.1],
		"rh": [0.15, -0.42, 0.45], "re": [1.0, 0.2, 0.3], "rw": [0.0, -0.6, 0.8],
		"lh": [-0.2, 0.6, 0.35], "le": [-1.0, 0.0, -0.3]},
	{"t": 0.38, "twist": 34.0, "lean": -8.0, "body": [-0.04, 0.0], "step": [0.14, 0.1],
		"rh": [0.15, -0.48, 0.42], "re": [1.0, 0.1, 0.3], "rw": [0.0, -0.7, 0.7],
		"lh": [-0.2, 0.62, 0.38], "le": [-1.0, 0.0, -0.3]},
	# elbow leads, hand comes over the top
	{"t": 0.46, "twist": 8.0, "lean": 4.0, "body": [0.03, -0.01], "step": [0.24, 0.04],
		"rh": [0.18, 0.2, 0.72], "re": [0.7, 0.6, 0.2], "rw": [0.0, -0.1, 1.0],
		"lh": [-0.3, 0.4, 0.1], "le": [-1.0, -0.3, -0.3]},
	# release: arm long and forward, front foot planted, front arm pulled in
	{"t": THROW_RELEASE, "twist": -22.0, "lean": 14.0, "body": [0.08, -0.04], "step": [0.28, 0.0],
		"rh": [0.08, 0.82, 0.32], "re": [1.0, 0.0, -0.4], "rw": [0.0, 1.0, 0.1],
		"lh": [-0.38, 0.0, -0.4], "le": [-0.6, -0.8, 0.0]},
	# follow-through: hand finishes low across the body
	{"t": 0.72, "twist": -34.0, "lean": 22.0, "body": [0.1, -0.05], "step": [0.28, 0.0],
		"rh": [-0.28, 0.55, -0.45], "re": [1.0, 0.3, -0.1], "rw": [-0.3, 0.6, -0.7],
		"lh": [-0.35, -0.15, -0.55], "le": [-0.6, -0.8, 0.0]},
	{"t": 1.0, "twist": 0.0, "lean": 0.0, "body": [0.0, 0.0], "step": [0.0, 0.0],
		"rh": "I", "re": "I", "rw": "I", "lh": "I", "le": "I"},
]


func _proc_pose(_ap: AnimationPlayer, sk: Skeleton3D, kind: String, u: float) -> void:
	_restore(sk, _idle_base)
	match kind:
		"throw":
			_throw_pose(sk, u)
		_:
			push_error("unknown procedural clip " + kind)
	sk.force_update_all_bone_transforms()


func _capture(sk: Skeleton3D) -> Array:
	var out: Array = []
	for i in sk.get_bone_count():
		out.append([sk.get_bone_pose_position(i), sk.get_bone_pose_rotation(i), sk.get_bone_pose_scale(i)])
	return out


func _restore(sk: Skeleton3D, base: Array) -> void:
	for i in mini(base.size(), sk.get_bone_count()):
		sk.set_bone_pose_position(i, base[i][0])
		sk.set_bone_pose_rotation(i, base[i][1])
		sk.set_bone_pose_scale(i, base[i][2])
	sk.force_update_all_bone_transforms()


func _gp(sk: Skeleton3D, bone: String) -> Vector3:
	var i := sk.find_bone(bone)
	return sk.get_bone_global_pose(i).origin if i >= 0 else Vector3.ZERO


func _has(sk: Skeleton3D, bones: Array) -> bool:
	for b in bones:
		if sk.find_bone(String(b)) < 0:
			return false
	return true


## Skeleton-space vector -> [right, forward, up] coordinates, and back.
func _to_body(v: Vector3, r: Dictionary) -> Vector3:
	return Vector3(v.dot(r["R"]), v.dot(r["F"]), v.dot(r["U"]))


func _from_body(v: Vector3, r: Dictionary) -> Vector3:
	return r["R"] * v.x + r["F"] * v.y + r["U"] * v.z


## Idle measurements (skeleton space) the throw keys are relative to.
func _throw_measure(sk: Skeleton3D) -> Dictionary:
	var r := {}
	var rt := _gp(sk, "UpperArm.R") - _gp(sk, "UpperArm.L")
	r["R"] = rt.normalized()
	var up := _gp(sk, "Head") - _gp(sk, "Hips")
	up = (up - r["R"] * up.dot(r["R"])).normalized()
	r["U"] = up
	r["F"] = up.cross(r["R"])
	for s in ["R", "L"]:
		var sh := _gp(sk, "UpperArm." + s)
		var el := _gp(sk, "LowerArm." + s)
		var ha := _gp(sk, "Fist." + s)
		var arm := sh.distance_to(el) + el.distance_to(ha)
		r["arm" + s] = arm
		var k := String(s).to_lower()
		r[k + "h"] = _to_body((ha - sh) / arm, r)
		var line := (ha - sh).normalized()
		var off := (el - sh) - line * (el - sh).dot(line)
		r[k + "e"] = _to_body(off.normalized(), r) if off.length() > arm * 0.02 else Vector3(0.6 if s == "R" else -0.6, -0.8, 0.0)
		r[k + "w"] = _to_body((_gp(sk, "Fist.%s_end" % s) - ha).normalized(), r)
		r["ankle" + s] = _gp(sk, "LowerLeg.%s_end" % s)
		var fb := sk.find_bone("Foot." + s)
		r["foot" + s] = sk.get_bone_global_pose(fb) if fb >= 0 else Transform3D()
	r["leg"] = _gp(sk, "UpperLeg.L").distance_to(_gp(sk, "LowerLeg.L")) + _gp(sk, "LowerLeg.L").distance_to(_gp(sk, "LowerLeg.L_end"))
	if OS.get_cmdline_user_args().has("verbose=1"):
		print("throw ref: ", r)
	return r


func _throw_pose(sk: Skeleton3D, u: float) -> void:
	if not _has(sk, ["UpperArm.R", "LowerArm.R", "Fist.R", "Fist.R_end", "UpperArm.L", "LowerArm.L", "Fist.L", "Fist.L_end", "Head", "Hips"]):
		return  # unknown rig: hold the idle pose rather than break
	if _throw_ref.is_empty():
		_throw_ref = _throw_measure(sk)
	var r := _throw_ref
	var k := _sample(THROW_KEYS, u, r)
	var leg := float(r["leg"])
	# weight shift, then lean and twist up the spine; the head counters to keep its aim
	var body := sk.find_bone("Body")
	if body >= 0:
		var g := sk.get_bone_global_pose(body)
		var bv: Vector2 = k["body"]
		g.origin += _from_body(Vector3(0.0, bv.x, bv.y) * leg, r)
		sk.set_bone_global_pose(body, g)
	var lean_axis: Vector3 = (r["U"] as Vector3).cross(r["F"])
	var twist_axis: Vector3 = -(r["U"] as Vector3)
	var tw := float(k["twist"])
	var ln := float(k["lean"])
	_turn(sk, "Hips", lean_axis, ln * 0.5)
	_turn(sk, "Hips", twist_axis, tw * 0.25)
	_turn(sk, "Abdomen", twist_axis, tw * 0.35)
	_turn(sk, "Abdomen", lean_axis, ln * 0.25)
	_turn(sk, "Torso", twist_axis, tw * 0.4)
	_turn(sk, "Torso", lean_axis, ln * 0.25)
	_turn(sk, "Neck", twist_axis, -tw * 0.7)
	_turn(sk, "Neck", lean_axis, -ln * 0.6)
	# legs: the right foot stays planted, the left one steps forward
	if _has(sk, ["UpperLeg.L", "LowerLeg.L", "LowerLeg.L_end", "UpperLeg.R", "LowerLeg.R", "LowerLeg.R_end"]):
		var sv: Vector2 = k["step"]
		var step := _from_body(Vector3(0.0, sv.x, sv.y) * leg, r)
		_ik2(sk, "UpperLeg.R", "LowerLeg.R", "LowerLeg.R_end", r["ankleR"], r["F"])
		_ik2(sk, "UpperLeg.L", "LowerLeg.L", "LowerLeg.L_end", r["ankleL"] + step, r["F"])
		var fb := sk.find_bone("Foot.L")
		if fb >= 0:
			var fx: Transform3D = r["footL"]
			fx.origin += step
			sk.set_bone_global_pose(fb, fx)
	# arms
	for s in ["R", "L"]:
		var c := String(s).to_lower()
		var sh := _gp(sk, "UpperArm." + s)
		var target := sh + _from_body(k[c + "h"], r) * float(r["arm" + s])
		_ik2(sk, "UpperArm." + s, "LowerArm." + s, "Fist." + s, target, _from_body(k[c + "e"], r))
	sk.force_update_all_bone_transforms()
	_aim(sk, sk.find_bone("Fist.R"), _gp(sk, "Fist.R_end") - _gp(sk, "Fist.R"), _from_body(k["rw"], r))


## Rotates bone `name` about its own origin by `deg` around a skeleton-space axis.
func _turn(sk: Skeleton3D, name: String, axis: Vector3, deg: float) -> void:
	var i := sk.find_bone(name)
	if i < 0 or is_zero_approx(deg):
		return
	sk.force_update_all_bone_transforms()
	var g := sk.get_bone_global_pose(i)
	g.basis = Basis(axis.normalized(), deg_to_rad(deg)) * g.basis
	sk.set_bone_global_pose(i, g)


## Turns bone `i` so its direction `from` points along `to` (skeleton space).
func _aim(sk: Skeleton3D, i: int, from: Vector3, to: Vector3) -> void:
	if i < 0 or from.length_squared() < 1e-14 or to.length_squared() < 1e-14:
		return
	var g := sk.get_bone_global_pose(i)
	g.basis = Basis(Quaternion(from.normalized(), to.normalized())) * g.basis
	sk.set_bone_global_pose(i, g)
	sk.force_update_all_bone_transforms()


## Two-bone IK: upper `a`, lower `b` and end joint `c` reach `target`; the middle joint
## bends towards `pole` (a direction).
func _ik2(sk: Skeleton3D, a_name: String, b_name: String, c_name: String, target: Vector3, pole: Vector3) -> void:
	var a := sk.find_bone(a_name)
	var b := sk.find_bone(b_name)
	sk.force_update_all_bone_transforms()
	var pa := _gp(sk, a_name)
	var pb := _gp(sk, b_name)
	var pc := _gp(sk, c_name)
	var l1 := pa.distance_to(pb)
	var l2 := pb.distance_to(pc)
	var to := target - pa
	var d := clampf(to.length(), absf(l1 - l2) + (l1 + l2) * 0.02, (l1 + l2) * 0.999)
	var dir := to.normalized()
	var pp := pole - dir * pole.dot(dir)
	if pp.length_squared() < 1e-12:
		pp = (pb - pa) - dir * (pb - pa).dot(dir)
	pp = pp.normalized()
	var x := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - x * x, 0.0))
	var elbow := pa + dir * x + pp * h
	_aim(sk, a, pb - pa, elbow - pa)
	pb = _gp(sk, b_name)
	pc = _gp(sk, c_name)
	_aim(sk, b, pc - pb, pa + dir * d - pb)


## Hermite spline through the keys (Catmull-Rom tangents, at rest at both ends).
func _sample(keys: Array, u: float, ref: Dictionary) -> Dictionary:
	var n := keys.size()
	var i := 0
	while i < n - 2 and u > float(keys[i + 1]["t"]):
		i += 1
	var t0 := float(keys[i]["t"])
	var t1 := float(keys[i + 1]["t"])
	var s := clampf((u - t0) / maxf(t1 - t0, 0.000001), 0.0, 1.0)
	var h00 := 2.0 * s * s * s - 3.0 * s * s + 1.0
	var h10 := s * s * s - 2.0 * s * s + s
	var h01 := -2.0 * s * s * s + 3.0 * s * s
	var h11 := s * s * s - s * s
	var out := {}
	for f in keys[0]:
		if f == "t":
			continue
		var p0: Variant = _kv(keys[i], f, ref)
		var p1: Variant = _kv(keys[i + 1], f, ref)
		var m0: Variant = p0 * 0.0
		var m1: Variant = p0 * 0.0
		if i > 0:
			m0 = (p1 - _kv(keys[i - 1], f, ref)) * ((t1 - t0) / (t1 - float(keys[i - 1]["t"])))
		if i + 2 < n:
			m1 = (_kv(keys[i + 2], f, ref) - p0) * ((t1 - t0) / (float(keys[i + 2]["t"]) - t0))
		out[f] = p0 * h00 + m0 * h10 + p1 * h01 + m1 * h11
	return out


func _kv(key: Dictionary, f: String, ref: Dictionary) -> Variant:
	var v: Variant = key[f]
	if v is String:
		return ref[f]
	if v is Array:
		return Vector2(v[0], v[1]) if v.size() == 2 else Vector3(v[0], v[1], v[2])
	return float(v)


# ---------------------------------------------------------------- weapons

func _weapons(sk: Skeleton3D, recipe: Dictionary, u: float, indices: PackedInt32Array, base: int) -> Array:
	var out: Array = []
	var w := String(recipe.get("weapon", ""))
	if w != "":
		_weapon_on(sk, "Fist.R", "LowerArm.R", w, u, out, indices, base)
	var off := String(recipe.get("offhand", ""))
	if off != "":
		_weapon_on(sk, "Fist.L", "LowerArm.L", off, u, out, indices, base)
	return out


func _weapon_on(sk: Skeleton3D, hand: String, fore: String, kind: String, u: float, out: Array, indices: PackedInt32Array, base: int) -> void:
	var hb := sk.find_bone(hand)
	var fb := sk.find_bone(fore)
	if hb < 0 or fb < 0:
		return
	var hp := sk.get_bone_global_rest(hb).origin
	var dir := (hp - sk.get_bone_global_rest(fb).origin).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var up := side.cross(dir).normalized()
	var grip := hp + dir * 0.07 * u
	var dark := Color(0.12, 0.12, 0.14)
	var metal := Color(0.82, 0.85, 0.9)
	var wood := Color(0.5, 0.33, 0.18)
	match kind:
		"knife":
			_box(out, indices, base, hb, grip + dir * 0.06 * u, dir, up, side, Vector3(0.05, 0.05, 0.12) * u, dark)
			_box(out, indices, base, hb, grip + dir * 0.22 * u, dir, up, side, Vector3(0.025, 0.06, 0.22) * u, metal)
		"pistol":
			_box(out, indices, base, hb, grip + up * 0.06 * u + dir * 0.06 * u, dir, up, side, Vector3(0.06, 0.1, 0.26) * u, dark)
		"revolver":
			_box(out, indices, base, hb, grip + up * 0.06 * u + dir * 0.08 * u, dir, up, side, Vector3(0.07, 0.11, 0.32) * u, Color(0.35, 0.35, 0.38))
		"rifle":
			_box(out, indices, base, hb, grip + up * 0.06 * u + dir * 0.2 * u, dir, up, side, Vector3(0.07, 0.12, 0.75) * u, dark)
		"bat":
			_box(out, indices, base, hb, grip + dir * 0.36 * u, dir, up, side, Vector3(0.07, 0.07, 0.75) * u, wood)
		"club":
			_box(out, indices, base, hb, grip + dir * 0.38 * u, dir, up, side, Vector3(0.12, 0.12, 0.8) * u, Color(0.3, 0.3, 0.33))
		"baton":
			_box(out, indices, base, hb, grip + dir * 0.24 * u, dir, up, side, Vector3(0.05, 0.05, 0.5) * u, dark)
		"chain":
			_box(out, indices, base, hb, grip + dir * 0.3 * u, dir, up, side, Vector3(0.04, 0.04, 0.6) * u, Color(0.6, 0.6, 0.62))
		"shield":
			_box(out, indices, base, hb, grip + dir * 0.05 * u, side, up, dir, Vector3(0.06, 1.0, 0.7) * u, Color(0.75, 0.82, 0.9))
		"shotgun":
			_box(out, indices, base, hb, grip + up * 0.06 * u + dir * 0.2 * u, dir, up, side, Vector3(0.07, 0.1, 0.62) * u, dark)
			_box(out, indices, base, hb, grip + up * 0.03 * u + dir * 0.3 * u, dir, up, side, Vector3(0.08, 0.06, 0.16) * u, wood)
			_box(out, indices, base, hb, grip + up * 0.04 * u - dir * 0.1 * u, dir, up, side, Vector3(0.06, 0.1, 0.18) * u, wood)
		"sniper":
			_box(out, indices, base, hb, grip + up * 0.06 * u + dir * 0.32 * u, dir, up, side, Vector3(0.05, 0.08, 0.98) * u, dark)
			_box(out, indices, base, hb, grip + up * 0.15 * u + dir * 0.14 * u, dir, up, side, Vector3(0.05, 0.05, 0.24) * u, Color(0.05, 0.05, 0.06))
			_box(out, indices, base, hb, grip + up * 0.04 * u - dir * 0.12 * u, dir, up, side, Vector3(0.06, 0.11, 0.2) * u, Color(0.25, 0.27, 0.22))
		"launcher":
			_box(out, indices, base, hb, grip + up * 0.1 * u + dir * 0.16 * u, dir, up, side, Vector3(0.15, 0.15, 0.88) * u, Color(0.33, 0.38, 0.22))
			_box(out, indices, base, hb, grip + up * 0.1 * u + dir * 0.62 * u, dir, up, side, Vector3(0.18, 0.18, 0.06) * u, dark)
		"molotov":
			_box(out, indices, base, hb, grip + dir * 0.1 * u, dir, up, side, Vector3(0.09, 0.09, 0.2) * u, Color(0.22, 0.55, 0.3))
			_box(out, indices, base, hb, grip + dir * 0.24 * u, dir, up, side, Vector3(0.04, 0.04, 0.08) * u, Color(0.22, 0.55, 0.3))
			_box(out, indices, base, hb, grip + dir * 0.3 * u, dir, up, side, Vector3(0.06, 0.06, 0.06) * u, Color(1.0, 0.55, 0.15))


## Oriented box: `size` is (width along x_axis, height along y_axis, length along z_axis).
func _box(out: Array, indices: PackedInt32Array, base: int, bone: int, c: Vector3, z_axis: Vector3, y_axis: Vector3, x_axis: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var corners: Array = []
	for sz in [-1, 1]:
		for sy in [-1, 1]:
			for sx in [-1, 1]:
				corners.append(c + x_axis * h.x * sx + y_axis * h.y * sy + z_axis * h.z * sz)
	var start := base + out.size()
	for p in corners:
		out.append({"v": p, "binds": PackedInt32Array(), "w": PackedFloat32Array(), "mesh": -1, "col": col, "bone": bone})
	# corner index = sx + 2*sy + 4*sz (0/1 each)
	for q in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
		indices.append_array(PackedInt32Array([start + q[0], start + q[1], start + q[2], start + q[0], start + q[2], start + q[3]]))
