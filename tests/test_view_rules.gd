extends "res://tests/test_case.gd"
## LevelView rules (spec v2 §3-§5) checked on a real view, headless, frame by frame.


var _keep: Array = []


## Builds a playing LevelView for level n with its own World and Fx under the root.
## Returns [view, world, fx]; free them with _drop.
func _view(n: int) -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node("Game")
	_keep = [game.save.duplicate(true), game.save_path]
	game.save_path = ""
	game.boot({})
	var world := World.new()
	tree.root.add_child(world)
	var fx := Fx.new()
	fx.font = UiKit.FONT
	tree.root.add_child(fx)
	for node in [world, fx]:
		if not node.is_node_ready():
			node._ready()   # a SceneTree script's root is not live yet: ready by hand
	var view := LevelView.new().setup(Config.level(n), {}, world, fx, UiKit.FONT)
	view.input_enabled = false
	tree.root.add_child(view)
	if not view.is_node_ready():
		view._ready()
	return [view, world, fx]


func _drop(parts: Array) -> void:
	for n in parts:
		(n as Node).get_parent().remove_child(n)
		(n as Node).free()
	var game: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Game")
	game.save = _keep[0]
	game.save_path = _keep[1]


## Spec v2 §3: no slow-downs during a level. L7 has a first rank join (the old 0.3x
## spotlight) and red gates (the old 0.3x lesson) in the first 20 s.
func test_level_view_never_slows_time() -> void:
	var parts := _view(7)
	var view: LevelView = parts[0]
	var lv := Config.level(7)
	var route: Array = lv.get("route", [2, 1, 1, 0, 0])
	var pilot := Autopilot.new(route if not route.is_empty() else [2, 1, 1, 0, 0], true)
	var slow := 0
	var joined := [false]
	view.rank_joined.connect(func(_u, _f): joined[0] = true)
	for f in 1200:
		if view.sim.state != "run":
			break
		pilot.drive(view.sim)
		view._process(1.0 / 60.0)
		if view.time_scale() != 1.0:
			slow += 1
	check(joined[0], "a rank joined during the run (the old spotlight case)")
	eq(slow, 0, "frames run at anything but full speed")
	_drop(parts)


## Spec v2 §5: the explosive barrel is a drum with a fuse ring, never a box.
func test_barrel_is_a_drum_with_a_fuse_ring() -> void:
	var bm := GateRowView.barrel_model()
	var root: Node3D = bm["root"]
	var boxes := 0
	var drums := 0
	for c in root.get_children():
		if c is MeshInstance3D:
			if (c as MeshInstance3D).mesh is BoxMesh:
				boxes += 1
			if (c as MeshInstance3D).mesh is CylinderMesh:
				drums += 1
	eq(boxes, 0, "box parts in the barrel")
	check(drums >= 1, "the barrel is a cylinder drum")
	check(bm["fuse"] is ShaderMaterial, "the barrel has a fuse ring")
	root.free()


## Shooting a barrel fills its fuse ring; once armed the ring is full.
func test_barrel_fuse_fills_with_hits() -> void:
	var parts := _view(4)
	var view: LevelView = parts[0]
	var ob := {"id": 900, "kind": "barrel", "lane": 2, "z": -30.0, "hp": 10.0, "hp_max": 10.0, "dmg": 4}
	view._spawn_obstacle(ob)
	var od: Dictionary = view._obstacles[900]
	var fm: ShaderMaterial = od["fuse"]
	view._update_obstacle(od, 0.016)
	eq(float(fm.get_shader_parameter("fill")), 0.0, "an untouched barrel's fuse is empty")
	ob["hp"] = 4.0
	view._update_obstacle(od, 0.016)
	check(absf(float(fm.get_shader_parameter("fill")) - 0.6) < 0.001, "6 of 10 hits fill 60% of the fuse")
	ob["hp"] = 0.0
	ob["armed"] = true
	view._update_obstacle(od, 0.016)
	eq(float(fm.get_shader_parameter("fill")), 1.0, "an armed barrel's fuse is full")
	_drop(parts)


## Spec v2 §2: the heat arc at the hero's feet fills with taps and empties again.
func test_heat_arc_follows_taps() -> void:
	var parts := _view(1)
	var view: LevelView = parts[0]
	view._process(1.0 / 60.0)
	check(view._heat_ring.visible, "the heat arc shows during play")
	var idle := float(view._heat_mat.get_shader_parameter("fill"))
	for i in 4:
		view.tap()
		view._process(1.0 / 60.0)
	var hot := float(view._heat_mat.get_shader_parameter("fill"))
	check(hot > idle + 0.5, "four quick taps heat the arc (%.2f -> %.2f)" % [idle, hot])
	for i in 150:
		view._process(1.0 / 60.0)
	check(float(view._heat_mat.get_shader_parameter("fill")) < hot - 0.5, "the heat decays without taps")
	_drop(parts)


## Spec v2 §4: a full squad spreads about one lane wide (formation_half_width), not a blob.
func test_full_squad_is_about_one_lane_wide() -> void:
	var w: Dictionary = Config.units()["world"]
	var half := float(w["formation_half_width"])
	var lane := float(w["lane_width"])
	var n := int(w["formation_figures"])
	var lo := 0.0
	var hi := 0.0
	for i in n:
		var o := Squad.slot_offset(i, n, half)
		lo = minf(lo, o.x)
		hi = maxf(hi, o.x)
	check(hi - lo >= lane * 0.9, "a full squad spans %.2f m, about one lane (%.1f m)" % [hi - lo, lane])
	check(hi - lo <= lane * 1.2, "a full squad stays within about one lane (%.2f m)" % (hi - lo))


## Spec v2 §5: every district has a full colour grade in config/world_look.json.
func test_world_look_has_every_district() -> void:
	for d in range(1, 6):
		var t := World.look(d)
		for k in ["fog", "fog_density", "sun_color", "exposure", "saturation", "contrast", "tint"]:
			check(t.has(k), "district %d look has %s" % [d, k])
	eq(World.look_count(), 5, "districts with a look")
