extends "res://tests/test_case.gd"
## LevelView rules (spec v2 §3-§5) checked on a real view, headless, frame by frame.


var _keep: Array = []


## Builds a playing LevelView for level n with its own World and Fx under the root.
## Returns [view, world, fx]; free them with _drop.
func _view(n: Variant) -> Array:
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
	var view := LevelView.new().setup(n if n is Dictionary else Config.level(n), {}, world, fx, UiKit.FONT)
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


## Spec v2 §4 smudge: a full squad's shown figures stand on the sim's x places (obstacle hits
## stay true) but their rows open up in depth, so the centre is not one blob of caps; the
## hero stays in front of everyone.
func test_big_squad_keeps_sim_x_and_opens_in_depth() -> void:
	var parts := _view(21)
	var view: LevelView = parts[0]
	var n := int(Config.units()["world"]["formation_figures"])
	var half: float = view.sim.form_half
	var xs_sim: Array = []
	var xs_view: Array = []
	var z_sim := [INF, -INF]
	var z_view := [INF, -INF]
	for i in range(1, n):
		var o := Squad.slot_offset(i, n, half)
		xs_sim.append(snappedf(o.x, 0.0001))
		z_sim = [minf(z_sim[0], o.y), maxf(z_sim[1], o.y)]
		var p: Vector3 = view._slot_pos(i, n)
		xs_view.append(snappedf(p.x - view._squad_x, 0.0001))
		z_view = [minf(z_view[0], p.z), maxf(z_view[1], p.z)]
	xs_sim.sort()
	xs_view.sort()
	eq(xs_view, xs_sim, "the shown figures stand on exactly the sim's x places")
	check(z_view[1] - z_view[0] > (z_sim[1] - z_sim[0]) * 1.2, "rows open up in depth (%.2f m vs %.2f m)" % [z_view[1] - z_view[0], z_sim[1] - z_sim[0]])
	check(view._slot_pos(0, n).z < z_view[0], "the hero stays in front of every follower")
	eq(LevelView.depth_spread(10), 1.0, "a small squad keeps the sim's rows")
	_drop(parts)


## Spec v2 §4 smudge: a packed squad's followers draw thinner ink, so the outlines between
## overlapping heads do not merge into a grey-purple blob; a small squad keeps full ink.
func test_packed_squad_draws_thin_ink() -> void:
	eq(LevelView.ink_width(10), LevelView.INK_W, "a small squad keeps full ink")
	check(LevelView.ink_width(72) <= LevelView.INK_W * 0.5, "a full squad draws at most half the ink")
	var parts := _view(1)
	var view: LevelView = parts[0]
	var c: Crowd = view._crowds["constable"]
	c.set_ink_width(0.012)
	var ink := (c.material_override as ShaderMaterial).next_pass as ShaderMaterial
	check(is_equal_approx(float(ink.get_shader_parameter("width")), 0.012), "the crowd's ink pass takes the width")
	_drop(parts)


## Spec v2 §5: the boss is visible all fight. Far up the street he is drawn bigger (easing to
## his true size by 30 m), and a gang walking ahead of him keeps its count low over its own
## heads, below his head, instead of on his chest.
func test_boss_towers_over_escorts_while_walking_in() -> void:
	check(LevelView.boss_grow(-70.0) >= 1.4, "a boss 70 m away is drawn at least 1.4x bigger")
	eq(LevelView.boss_grow(-30.0), 1.0, "a boss 30 m away is his true size")
	var lvl := {"id": 10, "district": 1, "events": [
		{"at": 90, "type": "wave", "groups": [{"enemy": "thug", "n": 60}, {"enemy": "boss", "n": 1, "gap": 22, "hp": 900}]},
		{"at": 160, "type": "finish"}]}
	var parts := _view(lvl)
	var view: LevelView = parts[0]
	var seen := 0
	for f in 900:
		if view.sim.state != "run":
			break
		view._process(1.0 / 60.0)
		var boss: Dictionary = {}
		for id in view._hordes:
			if view._hordes[id].has("bar"):
				boss = view._hordes[id]
		if boss.is_empty():
			continue
		var bz := float(boss["h"]["z"])
		var head := LevelView.CHAR_H * LevelView.BOSS_SCALE * LevelView.boss_grow(bz) * LevelView.crowd_scale(1)
		for id in view._hordes:
			var hv: Dictionary = view._hordes[id]
			if hv.has("bar") or not hv.has("label"):
				continue
			var lab: Label3D = hv["label"]
			if lab.position.z > bz + 7.0:
				seen += 1
				# The label's top edge (about 0.45 m per unit of scale above its centre) stays
				# below the boss's shoulders, so his head and chest show above the count.
				var top := lab.position.y + 0.45 * lab.scale.y
				check(top < head * 0.75, "an escort count ahead of the boss stays below his shoulders (%.1f < %.1f m)" % [top, head * 0.75])
				if top >= head * 0.75:
					_drop(parts)
					return
	check(seen > 0, "an escort gang walked ahead of the boss")
	_drop(parts)
