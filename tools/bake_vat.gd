extends SceneTree
## Bakes the role characters (config/characters.json) into vertex-animation textures.
##   godot --headless --path . --script res://tools/bake_vat.gd [-- only=hero]
##
## For every role: load the Quaternius FBX in art_src/characters, recolour its materials,
## attach the weapon to the hand bone, then sample each clip and write every vertex's
## position per frame into one texture row. In game a whole crowd is one MultiMesh whose
## shader reads its pose from that texture (src/game/crowd_vat.gdshader), so hundreds
## of animated people cost a single draw call per role.
##
## Output (res://assets/characters/): <role>_mesh.res, <role>_vat.res, clips.json.

const OUT := "res://assets/characters/"
const SRC := "res://art_src/characters/"

var _cfg: Dictionary
var _done := false
var _lengths := {}


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
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
	DirAccess.make_dir_recursive_absolute(OUT)
	var clip_table := _clip_table()
	for role in _cfg["roles"]:
		if only != "" and role != only:
			continue
		var t0 := Time.get_ticks_msec()
		var info := _bake_role(String(role), _cfg["roles"][role])
		print("baked %-10s verts=%d tris=%d rows=%d  %.1fs" % [role, info["verts"], info["tris"], info["rows"], (Time.get_ticks_msec() - t0) / 1000.0])
	for name in _lengths:
		clip_table[name]["length"] = _lengths[name]
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
	var first_frame := PackedVector3Array()
	for c in _cfg["clips"]:
		var anim_name := _find_anim(ap, String(c["src"]))
		var length := ap.get_animation(anim_name).length
		_lengths[c["name"]] = length
		var frames := int(c["frames"])
		var row0 := int(table[c["name"]]["row"])
		for f in frames:
			var t := length * f / frames if bool(c["loop"]) else length * f / maxf(frames - 1, 1)
			_pose(ap, String(c["src"]), t)
			var ps := _skin_all(sk, verts, meshes)
			for vi in n:
				var p := to_model * (ps[vi] - foot)
				var o := ((row0 + f) * n + vi) * 4
				data[o] = p.x
				data[o + 1] = p.y
				data[o + 2] = p.z
				data[o + 3] = 1.0
				if c["name"] == "idle" and f == 0:
					first_frame.append(p)

	var img := Image.create_from_data(n, rows, false, Image.FORMAT_RGBAF, data.to_byte_array())
	img.convert(Image.FORMAT_RGBAH)
	ResourceSaver.save(ImageTexture.create_from_image(img), OUT + role + "_vat.res")

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
