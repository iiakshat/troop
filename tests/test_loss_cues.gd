extends "res://tests/test_case.gd"
## Owner play-test 2026-11-13, checked on a real LevelView, headless: a gang is never drawn
## inside or behind the stash and is on screen until it dies; every troop loss shows what did it
## (the cause icon beside the red -N) and who shot (a gun over the gang, a line per volley, a
## ring the first time ever).


var _keep: Array = []


func _view(level: Dictionary, upgrades: Dictionary = {}) -> Array:
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
	var view := LevelView.new().setup(level, upgrades, world, fx, UiKit.FONT)
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


func _tick(view: LevelView, fx: Fx, secs: float) -> void:
	for i in maxi(int(round(secs * 60.0)), 1):
		view._process(1.0 / 60.0)
		fx._process(1.0 / 60.0)


func _fight_level() -> Dictionary:
	return {"id": 11, "district": 2, "events": [
		{"at": 60, "type": "wave", "groups": [{"enemy": "gunman", "n": 30}]},
		{"at": 400, "type": "finish"}]}


func _first_gang(view: LevelView) -> int:
	for f in 1200:
		if not view._hordes.is_empty():
			return int(view._hordes.keys()[0])
		view._process(1.0 / 60.0)
	return -1


## The last waves of a short street come out where the old sim put them behind the stash: a
## deep, tough gunman line and a sniper gang (its 40 m stop line was inside the stash at the
## HQ hold). Frame by frame, every living gang is drawn, and no figure stands inside or behind
## the stash's front face.
func test_late_gangs_stay_drawn_in_front_of_the_stash() -> void:
	var lv := {"id": 23, "district": 3, "events": [
		{"at": 20, "type": "wave", "groups": [{"enemy": "thug", "n": 5}]},
		{"at": 118, "type": "wave", "groups": [{"enemy": "gunman", "n": 1500, "hp": 40},
			{"enemy": "sniper_foe", "n": 300, "gap": 4, "hp": 40}]},
		{"at": 125, "type": "finish"}]}
	var parts := _view(lv, {"squad": 200})
	var view: LevelView = parts[0]
	var fx: Fx = parts[2]
	var seen := {}
	var problems: Array = []
	var frames := 0
	while view.sim.state == "run" and frames < 60 * 70:
		_tick(view, fx, 1.0 / 60.0)
		frames += 1
		for id in view._hordes:
			var hv: Dictionary = view._hordes[id]
			var h: Dictionary = hv["h"]
			if int(h["count"]) <= 0 or not view._finish_live:
				continue
			seen[id] = true
			if view.drawn_figures(int(id)) <= 0 and problems.size() < 5:
				problems.append("frame %d: %s gang of %d not drawn" % [frames, h["enemy"], h["count"]])
			var face := view.sim.stash_z()
			for o in hv["offs"]:
				var z := view._fig_pos(hv, o).z
				if z < face + LevelView.STASH_PAD - 0.01 and problems.size() < 5:
					problems.append("frame %d: a %s figure at z %.1f, stash face %.1f" % [frames, h["enemy"], z, face])
					break
	check(seen.size() >= 2, "both late gangs came out with the finish in sight (%d)" % seen.size())
	eq(problems, [], "every living gang is on screen, in front of the stash")
	_drop(parts)


## A volley: the shooters' gun shows over their count while their guns reach the squad, one
## line per volley runs from them to the squad, and the -N that lands carries the gun icon. The
## first volley ever circles the shooters (once per save).
func test_volley_shows_who_shot_and_what_it_cost() -> void:
	var parts := _view(_fight_level(), {"squad": 40})
	var view: LevelView = parts[0]
	var fx: Fx = parts[2]
	var id := _first_gang(view)
	check(id >= 0, "the gang came")
	check(not Game.hint_seen(LevelView.FIRST_FIRE_HINT), "a fresh save has never been shot at")
	var h: Dictionary = view._hordes[id]["h"]
	h["rf_rate"] = 1.0
	h["z"] = -30.0   # within its guns' reach
	h["silent"] = 1000.0   # (the sim's own volleys stay out of it: this test sends its own)
	_tick(view, fx, 1.0 / 60.0)
	check(LevelSim.fires_back(h), "its guns reach the squad")
	eq(view.cues.guns_shown(), 1, "a gun shows over the gang that fires")
	view.sim.squad.lose(3)
	view._handle_events([{"type": "return_fire", "horde": id, "x": 0.0, "z": -30.0, "shots": 3, "lost": 3,
		"blocked": false, "opening": true}])
	_tick(view, fx, 1.0 / 60.0)
	eq(view.cues.lines_shown(), 1, "one line from the shooters to the squad")
	eq(view.cues.focus_id, id, "the first volley ever circles its gang")
	check(Game.hint_seen(LevelView.FIRST_FIRE_HINT), "and is remembered")
	_tick(view, fx, Fx.GUN_MAX_S + 0.1)
	eq(view._minus_label.text, "-3", "the volley's -3 lands at the squad")
	eq(view.minus_cause(), LevelView.GUN_ICON, "with the gun beside it")
	_tick(view, fx, LossCues.FOCUS_S)
	eq(view.cues.focus_id, -1, "the ring goes after a moment")
	view.sim.squad.lose(2)
	view._handle_events([{"type": "return_fire", "horde": id, "x": 0.0, "z": -30.0, "shots": 2, "lost": 2,
		"blocked": false, "opening": false}])
	_tick(view, fx, 1.0 / 60.0)
	eq(view.cues.focus_id, -1, "only the first volley ever gets the ring")
	_tick(view, fx, LossCues.LINE_S + 0.1)
	eq(view.cues.lines_shown(), 0, "a volley's line fades")
	h["z"] = -80.0   # out of its guns' reach
	_tick(view, fx, 2.0)
	eq(view.cues.guns_shown(), 0, "no gun once its guns no longer reach")
	_drop(parts)


## Every other loss carries its own cause: the clash a fist, a firebomb fire, a grenade a blast,
## a sniper the crosshair, an obstacle its own icon; a new cause starts its own -N.
func test_every_loss_carries_its_cause() -> void:
	var parts := _view(_fight_level(), {"squad": 40})
	var view: LevelView = parts[0]
	var fx: Fx = parts[2]
	var id := _first_gang(view)
	view._handle_events([{"type": "melee", "horde": id, "enemies": 2, "lost": 2, "shielded": false}])
	eq(view.minus_cause(), "fist", "a clash: the fist")
	eq(view._minus_label.text, "-2", "its -2")
	for kind in ["firebomb", "grenade", "snipe", "barrage", "crane"]:
		_tick(view, fx, 1.2)
		view._handle_events([{"type": "attack_land", "kind": kind, "lane": view.sim.lane, "lost": 4,
			"blocked": false, "hit": true}])
		eq(view.minus_cause(), String(LevelView.CAUSE_ICON[kind]), "%s: its icon" % kind)
	_tick(view, fx, 0.1)
	view._handle_events([{"type": "attack_land", "kind": "firebomb", "lane": view.sim.lane, "lost": 1,
		"blocked": false, "hit": true}])
	eq(view._minus_label.text, "-1", "another cause right after starts its own number")
	_tick(view, fx, 1.2)
	var ob := {"id": 9001, "kind": "car", "lane": view.sim.lane, "z": 0.0, "hp": 0.0, "hp_max": 10.0, "dmg": 3}
	view._handle_events([{"type": "obstacle_hit", "ob": ob, "lost": 3, "slots": [], "figures": 0, "x": 0.0}])
	eq(view.minus_cause(), "car", "a car crash: the car")
	eq(view._minus_label.text, "-3", "its -3 at the squad")
	_tick(view, fx, 1.5)
	eq(view.minus_cause(), "", "the cause fades with its number")
	_drop(parts)
