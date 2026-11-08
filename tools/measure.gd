extends SceneTree
## Prints the bounding box of every model under a folder: godot --headless --path . --script res://tools/measure.gd -- dir=res://assets/env/commercial
func _initialize() -> void:
	var dir := "res://assets/env"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("dir="):
			dir = a.substr(4)
	for sub in [dir] + Array(DirAccess.get_directories_at(dir)).map(func(d): return dir + "/" + d):
		for f in DirAccess.get_files_at(sub):
			if not (f.ends_with(".glb") or f.ends_with(".gltf")):
				continue
			var n: Node = (load(sub + "/" + f) as PackedScene).instantiate()
			var box := AABB()
			var first := true
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				var xf := Transform3D()
				var cur: Node = mi
				while cur != null and cur != n and cur is Node3D:
					xf = (cur as Node3D).transform * xf
					cur = cur.get_parent()
				var b: AABB = xf * (mi as MeshInstance3D).mesh.get_aabb()
				box = b if first else box.merge(b)
				first = false
			print("%s/%s size=%s pos=%s" % [sub.get_file(), f, str(box.size.snapped(Vector3.ONE * 0.01)), str(box.position.snapped(Vector3.ONE * 0.01))])
			n.free()
	quit()
