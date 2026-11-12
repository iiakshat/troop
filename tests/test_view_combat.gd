extends "res://tests/test_case.gd"
## LevelView combat visuals (spec v2 §12.2, §12.4, §12.5), checked on a real view, headless.


var _keep: Array = []


## A playing LevelView for `level` with its own World and Fx under the root. Returns
## [view, world, fx]; free them with _drop.
func _view(level: Dictionary) -> Array:
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
			node._ready()
	var view := LevelView.new().setup(level, {}, world, fx, UiKit.FONT)
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


func _proj_kinds(fx: Fx) -> Array:
	var out: Array = []
	for p in fx._proj:
		out.append(String(p["kind"]))
	return out


func _frames(view: LevelView, n: int) -> void:
	for i in n:
		if view.sim.state != "run":
			break
		view._process(1.0 / 60.0)
		view.fx._process(1.0 / 60.0)   # the tree is not processing in a --script run


func test_bomb_is_thrown_with_the_throw_clip_and_a_visible_arc() -> void:
	var parts := _view({"id": 3, "district": 1, "charges": {"bomb": 1}, "events": [{"at": 300, "type": "finish"}]})
	var view: LevelView = parts[0]
	var fx: Fx = parts[2]
	_frames(view, 3)
	fx._proj.clear()   # the level-load prewarm's bomb
	check(view.use_power("bomb"), "the bomb button works with nothing in reach")
	check(view._bomb_throw_t >= 0.0, "the hero starts his throw clip")
	_frames(view, 2)
	check(fx.held_bomb_on, "the bomb is in his hand during the wind-up")
	check(not _proj_kinds(fx).has("bomb"), "not thrown yet")
	var hand0 := fx.held_bomb
	var windup := float(Game.units["powers"]["bomb"]["windup"])
	_frames(view, int(windup * 60.0) - 6)
	check(fx.held_bomb.y > hand0.y + 0.4, "cocked up behind his head (%.2f -> %.2f)" % [hand0.y, fx.held_bomb.y])
	_frames(view, 8)
	check(not fx.held_bomb_on, "let go at the release")
	check(_proj_kinds(fx).has("bomb"), "a bomb flies (with its fuse)")
	# Pause: the bomb waits in the air with the sim.
	view.paused = true
	var at: Vector3 = fx._proj.filter(func(p): return p["kind"] == "bomb")[0]["pos"]
	view._process(1.0 / 60.0)
	fx._process(1.0 / 60.0)
	eq(fx._proj.filter(func(p): return p["kind"] == "bomb")[0]["pos"], at, "frozen while paused")
	check(not view.use_power("bomb"), "no power while paused")
	view.paused = false
	var landed := -1
	for i in 120:
		_frames(view, 1)
		if not _proj_kinds(fx).has("bomb"):
			landed = i
			break
	check(landed >= 0, "it landed")
	check(view.sim.bombs.is_empty(), "together with the sim's blast")
	_frames(view, 30)
	check(view._bomb_throw_t < 0.0, "the throw clip ended")
	eq(int(view.sim.charges["bomb"]), 0, "spent")
	_drop(parts)


func test_powers_wait_for_a_lesson_hold_and_steering_resets_after_a_revive() -> void:
	var parts := _view({"id": 3, "district": 1, "charges": {"bomb": 1}, "events": [{"at": 300, "type": "finish"}]})
	var view: LevelView = parts[0]
	_frames(view, 3)
	view.hold = true
	_frames(view, 1)
	check(not view.use_power("bomb"), "no bomb while a first-run lesson holds the street")
	eq(int(view.sim.charges["bomb"]), 1, "nothing spent")
	view.hold = false
	_frames(view, 1)
	view._steer_id = 0
	view._touching = true
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	view._state = "done"
	view.input_enabled = true
	view._unhandled_input(up)
	check(view._steer_id < 0 and not view._touching, "a finger lifted while the squad was down lets go")
	view._steer_id = 0
	view._touching = true
	view._on_revive({})
	check(view._steer_id < 0 and not view._touching, "a revive starts with no stale steering")
	view.input_enabled = false
	_drop(parts)


func test_return_fire_shows_tracers_and_followers_fall() -> void:
	var parts := _view({"id": 3, "district": 1, "events": [
		{"at": 10, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 19}]},
		{"at": 80, "type": "wave", "groups": [{"enemy": "gunman", "n": 4, "hp": 100000}]},
		{"at": 300, "type": "finish"}]})
	var view: LevelView = parts[0]
	var fx: Fx = parts[2]
	view.sim.set_lane(1)
	var fired := false
	var shown_before := -1
	for i in 2400:
		if view.sim.state != "run":
			break
		var before := view.sim.squad.total()
		view.sim.step(1.0 / 60.0)
		var evs := view.sim.drain()
		var rf := evs.filter(func(e): return e["type"] == "return_fire" and int(e["lost"]) > 0)
		if not rf.is_empty() and not fired:
			shown_before = view._allies.size()
			fx.clear()
		view._handle_events(evs)
		if not rf.is_empty() and not fired:
			fired = true
			# Spec v2.1 §1.1: orange-red tracers in their own pool; the hit figures fall when
			# the tracers land (about a second later), not before.
			check(fx.enemy_projectiles() > 0, "tracers fly at the squad")
			eq(view._allies.size(), shown_before, "nobody falls before the shots land")
			for f in 70:
				view._update_visuals(1.0 / 60.0)
				fx._process(1.0 / 60.0)
				if view._allies.size() < shown_before:
					break
			check(view._allies.size() < shown_before, "hit followers fall (%d -> %d)" % [shown_before, view._allies.size()])
			check(view._dying.size() > 0, "they topple")
			eq(view.sim.squad.total(), before - int(rf[0]["lost"]), "one troop per hit")
			break
	check(fired, "the gunmen fired back")
	_drop(parts)


func test_huge_gang_figures_are_capped_and_rows_match_the_sim() -> void:
	var parts := _view({"id": 31, "district": 4, "events": [
		{"at": 10, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": 24999}]},
		{"at": 150, "type": "wave", "groups": [{"enemy": "thug", "n": 18000}]},
		{"at": 300, "type": "finish"}]})
	var view: LevelView = parts[0]
	var spawned := false
	for i in 4000:
		view.sim.step(1.0 / 60.0)
		view._handle_events(view.sim.drain())
		if not view._hordes.is_empty():
			spawned = true
			break
	check(spawned, "the gang spawned")
	if spawned:
		var hv: Dictionary = view._hordes.values()[0]
		eq((hv["offs"] as Array).size(), int(Config.units()["world"]["gang_figures"]), "figures capped")
		eq(int(hv["per"]), 100, "each figure is 100 people")
		var cols := int(hv["h"]["cols"])
		var dz: float = (hv["offs"][cols] as Vector3).z - (hv["offs"][0] as Vector3).z
		check(absf(dz - float(hv["h"]["row_gap"])) < 0.3, "a figure row is one sim row (%.2f m)" % dz)
		view._process(1.0 / 60.0)
		eq((hv["label"] as Label3D).text, NumFormat.fmt(int(hv["h"]["count"])), "its count label is short (18K)")
	_drop(parts)


## Review: late gate rows ("+512", "+2,800", "945") ran into one unreadable number. Every
## sign and troop tag of every gate row in L1-50 (and each red gate at its max) fits its lane.
func test_gate_numbers_fit_their_lanes_in_every_level() -> void:
	var worst := 0.0
	var where := ""
	for n in range(1, Config.LEVEL_COUNT + 1):
		for e in Config.level(n)["events"]:
			if String(e["type"]) != "gates":
				continue
			for at_max in [false, true]:
				var gates: Array = (e["gates"] as Array).duplicate(true)
				for g in gates:
					if at_max and g.has("max"):
						g["v"] = int(g["max"])
				var v := GateRowView.new().setup({"gates": gates, "z": 0.0}, UiKit.FONT, LevelView.LANE_X)
				for lane in v._panels:
					var p: Dictionary = v._panels[lane]
					var tag: Label3D = p["tag"]
					var label: Label3D = p["label"]
					var w := 0.0
					if tag.visible:
						w = GateRowView.text_w(tag, tag.text)
					elif label.text != "":
						w = GateRowView.text_w(label, label.text) + (GateRowView.ICON_W + 0.1 if (p["icon"] as Sprite3D).visible else 0.0)
					if w > worst:
						worst = w
						where = "L%d at %s lane %d '%s'" % [n, str(e["at"]), lane, tag.text if tag.visible else label.text]
				v.free()
	check(worst <= GateRowView.FIT_W + 0.001, "widest gate number %.2f m <= %.2f m (%s)" % [worst, GateRowView.FIT_W, where])
