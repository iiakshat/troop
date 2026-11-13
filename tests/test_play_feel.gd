extends "res://tests/test_case.gd"
## Owner play-test round, 2026-11-13 (the level): dodging a marked attack with the view's real
## steering, the clear run to the stash, no bar on the stash, and a level clock that waits for
## the level to load.

var units := Config.units()
var _keep: Array = []


# ---------------------------------------------------------------- helpers

## A molotov gang that keeps throwing (the squad cannot kill it), squad of 300 in lane 1.
func _thrower_sim() -> LevelSim:
	var events: Array = [{"at": 70, "type": "wave", "groups": [{"enemy": "molotov", "n": 30, "hp": 4000}]},
		{"at": 470, "type": "finish"}]
	var sim := LevelSim.new({"district": 2, "events": events}, units)
	sim.squad.cap = 0
	sim.squad.add("constable", 299)
	sim.peak_squad = sim.squad.total()
	sim.set_lane(1)
	return sim


## Steps 60 fps until the first telegraph; that event (empty: none came).
func _first_telegraph(sim: LevelSim) -> Dictionary:
	for i in 12000:
		sim.set_squad_x(sim.squad_x)
		sim.step(1.0 / 60.0)
		for e in sim.drain():
			if e["type"] == "telegraph":
				return e
		if sim.state != "run":
			break
	return {}


## Plays a player's flick the way LevelView steers: `lead` s before the attack lands the finger
## moves `metres` toward lane `to_dir` over `swipe_s`, then lifts. Every 60 fps frame the squad's
## x eases toward the finger (LevelView.steer_toward), the sim gets that x, then steps; on the
## lift the lane is LevelView.release_lane (or, `old_release`, the lane the drag had flipped to:
## past the midpoint + LANE_SLACK). Returns {hit, x_at_land, lane}.
func _flick(base: LevelSim, tg: Dictionary, lead: float, metres: float, swipe_s := 0.1,
		old_release := false, to_dir := -1) -> Dictionary:
	var sim := base.clone()
	var id := int(tg["id"])
	var land := float(tg["land_t"])
	var x := sim.squad_x
	var lane := sim.lane
	var start := land - lead
	var finger := x
	var touching := false
	var dir := 0
	var released := false
	for f in 600:
		var t := sim.time
		if t >= start and not released:
			var u := clampf((t - start) / swipe_s, 0.0, 1.0)
			var nf: float = LevelView.LANE_X[1] + to_dir * metres * u
			if absf(nf - finger) > 0.02:
				dir = signi(int(signf(nf - finger)))
			finger = nf
			touching = true
			# The drag flips the sim's lane past the midpoint + slack (LevelView._unhandled_input).
			var half: float = (LevelView.LANE_X[1] - LevelView.LANE_X[0]) * 0.5 + LevelView.LANE_SLACK
			if finger > LevelView.LANE_X[lane] + half:
				lane += 1
			elif finger < LevelView.LANE_X[lane] - half:
				lane -= 1
			if u >= 1.0:
				released = true
				touching = false
				if not old_release:
					lane = LevelView.release_lane(finger, dir)
		var target: float = finger if touching else LevelView.LANE_X[lane]
		x = LevelView.steer_toward(x, target, 1.0 / 60.0)
		sim.set_lane(lane)
		sim.set_squad_x(x)
		sim.step(1.0 / 60.0)
		for e in sim.drain():
			if e["type"] == "attack_land" and int(e["id"]) == id:
				return {"hit": bool(e["hit"]), "x_at_land": x, "lane": lane}
		if sim.state != "run":
			break
	return {}


# ---------------------------------------------------------------- 1. dodging

## Release: a flick a third of the way to the next lane takes it; dragged back, it stays.
func test_release_lane_follows_the_flick() -> void:
	eq(LevelView.release_lane(0.6, 1), 2, "a 0.6 m flick right takes the right lane")
	eq(LevelView.release_lane(-0.6, -1), 0, "a 0.6 m flick left takes the left lane")
	eq(LevelView.release_lane(1.5, 1), 2, "past the midpoint (short of the old 1.75 m flip): the next lane")
	eq(LevelView.release_lane(0.3, 1), 1, "a nudge keeps the lane")
	eq(LevelView.release_lane(2.0, 1), 2, "over the right lane: the right lane")
	eq(LevelView.release_lane(1.0, -1), 1, "dragged back toward the middle: the middle")
	eq(LevelView.release_lane(-2.8, -1), 0, "never past the edge")
	eq(LevelView.release_lane(1.2, 0), 1, "a still finger: the nearest lane")


## The owner's bug ("I tried moving but at the last moment it came to me"): a quick flick that
## had the squad's centre out of the marked lane but short of the lane flip sprang back into the
## lane on release and was hit. Now the squad commits to the lane it was heading for; a squad
## whose centre is out of the marked lane when the attack lands is never hit.
func test_dodge_with_the_views_real_steering() -> void:
	var base := _thrower_sim()
	var tg := _first_telegraph(base)
	check(not tg.is_empty(), "a firebomb is telegraphed")
	if tg.is_empty():
		return
	eq(int(tg["lane"]), 1, "it marks the middle lane")
	# The old release: a 1.5 m flick (centre past the 1.4 m midpoint, short of the 1.75 m flip).
	var old := _flick(base, tg, 0.5, 1.5, 0.1, true)
	check(bool(old.get("hit", false)), "repro: the old release sprang back into the marked lane: hit (%s)" % str(old))
	for lead in [0.6, 0.45, 0.35, 0.3]:
		for m in [0.6, 1.0, 1.5, 2.8]:
			var r := _flick(base, tg, lead, m)
			check(not r.is_empty(), "the attack landed")
			check(not bool(r.get("hit", true)), "a %.1f m flick %.2f s before the landing dodges (%s)" % [m, lead, str(r)])
			eq(int(r.get("lane", -1)), 0, "and the squad settles in the next lane")
	# Whatever the timing, the sim's verdict is the squad's centre at land time.
	for lead in [0.25, 0.2, 0.15, 0.1, 0.05]:
		var r := _flick(base, tg, lead, 2.8, 0.05)
		var out_of_lane := absf(float(r.get("x_at_land", 0.0))) > base.lane_w * 0.5
		eq(bool(r.get("hit", true)), not out_of_lane,
			"%.2f s before the landing: hit only while the centre is in the lane (x %.2f)" % [lead, float(r.get("x_at_land", 0.0))])


## The view steers before it steps the sim: the sim decides every hit on the x drawn this frame.
func test_sim_gets_this_frames_x() -> void:
	var parts := _view(_fight_level())
	var view: LevelView = parts[0]
	view.input_enabled = true
	_frames(view, parts[2], 10)
	check(view.started, "the level started")
	view._touching = true
	view._steer_x = -2.8
	for i in 6:
		view._process(1.0 / 60.0)
		near(view.sim.squad_x, view._squad_x, "frame %d: the sim stands where the squad is drawn" % i)
	check(view._squad_x < -1.4, "the squad steered out of the middle lane (%.2f)" % view._squad_x)
	_drop(parts)


## The view's mark and its landing run on the sim's clock: the threat lands exactly at the
## sim's land_t, and the lobbed bottle is in the air for exactly that long.
func test_view_mark_lands_with_the_sim() -> void:
	var lv := {"id": 11, "district": 2, "events": [
		{"at": 70, "type": "wave", "groups": [{"enemy": "molotov", "n": 30, "hp": 4000}]},
		{"at": 470, "type": "finish"}]}
	var parts := _view(lv, {"squad": 40})
	var view: LevelView = parts[0]
	var fx: Fx = parts[2]
	var land := -1.0
	var shown := -1.0
	for f in 9000:
		view._process(1.0 / 60.0)
		fx._process(1.0 / 60.0)
		if land < 0.0 and not view.sim.attacks.is_empty():
			land = float(view.sim.attacks[0]["land"])
			for th in view._threats:
				shown = float(th["land"])
			break
	check(land > 0.0, "a firebomb was thrown")
	near(shown, land, "the view's mark lands at the sim's land_t")
	_drop(parts)


## Gunfire (return fire, the boss's gun) cannot be dodged: it is drawn as fast bullets that hit
## within Fx.GUN_MAX_S, not as slow tracers chasing the squad across the lanes.
func test_gunfire_is_fast_and_unlike_the_marked_attacks() -> void:
	check(Fx.gun_flight(60.0) <= Fx.GUN_MAX_S and Fx.GUN_MAX_S <= 0.3, "a 60 m shot hits within 0.3 s")
	check(Fx.enemy_flight(50.0) > 2.0 * Fx.GUN_MAX_S, "the dodgeable shots fly at least twice as long")
	var parts := _view(_fight_level(), {"squad": 40})
	var view: LevelView = parts[0]
	var fx: Fx = parts[2]
	var id := -1
	for f in 1200:
		if not view._hordes.is_empty():
			id = int(view._hordes.keys()[0])
			break
		view._process(1.0 / 60.0)
	fx.clear()
	view._handle_events([{"type": "return_fire", "horde": id, "x": 0.0, "z": -48.0, "shots": 3, "lost": 0,
		"blocked": false, "opening": false}])
	check(fx.enemy_projectiles() >= 3, "the volley is in the air")
	for i in int(ceil(Fx.GUN_MAX_S * 60.0)) + 1:
		fx._process(1.0 / 60.0)
	eq(fx.enemy_projectiles(), 0, "every shot hit within %.2f s" % Fx.GUN_MAX_S)
	_drop(parts)


# ---------------------------------------------------------------- 2. the clear run

func _one_gang_level() -> Dictionary:
	return {"id": 3, "district": 1, "events": [
		{"at": 40, "type": "wave", "groups": [{"enemy": "thug", "n": 3}]},
		{"at": 160, "type": "finish"}]}


func _finish(sim: LevelSim, taps := 0.0) -> Dictionary:
	var clear_at := -1.0
	var troops_at_clear := -1
	var shots_after := 0
	var events := 0
	var top := 0.0
	var next_tap := 0.0
	while sim.state == "run" and sim.time < 120.0:
		if taps > 0.0 and sim.time >= next_tap:
			sim.tap()
			next_tap += 1.0 / taps
		sim.step(1.0 / 60.0)
		for e in sim.drain():
			if e["type"] == "street_clear":
				events += 1
				clear_at = sim.time
				troops_at_clear = sim.squad.total()
		if sim.clear:
			if sim.target_kind != "":
				shots_after += 1
			top = maxf(top, sim.S)
	return {"clear_at": clear_at, "troops_at_clear": troops_at_clear, "shots_after": shots_after,
		"events": events, "top": top, "time": sim.time, "troops": sim.squad.total(), "stars": sim.stars(),
		"state": sim.state, "heat_t": sim.heat_t, "mean": sim.mean_heat()}


func test_clear_run_stops_fire_and_speeds_to_the_stash() -> void:
	var rush := float(units["world"].get("clear_run_speed", 1.0))
	check(rush > 1.0 and rush <= 2.0, "the clear run is faster (%.2f x)" % rush)
	var sim := LevelSim.new(_one_gang_level(), units, {"squad": 20})
	check(not sim.street_clear(), "a gang to come: not clear")
	var r := _finish(sim, 4.0)
	eq(r["state"], "strike", "the squad reaches the stash")
	eq(int(r["events"]), 1, "street_clear comes once")
	check(float(r["clear_at"]) > 0.0, "the street cleared when the gang died")
	eq(int(r["shots_after"]), 0, "nobody shoots on the clear run")
	near(float(r["top"]), sim.S_base * rush, "the squad runs %.1f x to the stash" % rush)
	eq(int(r["troops"]), int(r["troops_at_clear"]), "nothing changes the squad on the clear run")
	check(float(r["heat_t"]) <= float(r["clear_at"]) + 1e-6, "the clear run is not part of the mean heat")
	# The same level without the rush: the same squad and stars, only later.
	var u2 := units.duplicate(true)
	u2["world"]["clear_run_speed"] = 1.0
	var slow := _finish(LevelSim.new(_one_gang_level(), u2, {"squad": 20}), 4.0)
	eq(int(slow["troops"]), int(r["troops"]), "same troops at the stash")
	eq(int(slow["stars"]), int(r["stars"]), "same stars")
	check(float(r["time"]) < float(slow["time"]), "and sooner (%.1f s vs %.1f s)" % [float(r["time"]), float(slow["time"])])
	# A tap on the clear run does nothing.
	var t := LevelSim.new(_one_gang_level(), units, {"squad": 20})
	while not t.clear and t.state == "run":
		t.step(1.0 / 60.0)
		t.drain()
	var heat := t.tap_heat
	t.tap()
	eq(t.tap_heat, heat, "a tap on the clear run does nothing")


func test_clear_waits_for_gates_obstacles_and_cages() -> void:
	var lv := {"id": 3, "district": 1, "events": [
		{"at": 40, "type": "wave", "groups": [{"enemy": "thug", "n": 2}]},
		{"at": 90, "type": "gates", "gates": [{"lane": 1, "op": "num", "v": -5, "step": 1.0, "max": 5}]},
		{"at": 120, "type": "obstacle", "kind": "barricade", "lane": 0},
		{"at": 200, "type": "finish"}]}
	var sim := LevelSim.new(lv, units, {"squad": 20})
	sim.set_lane(1)
	var cleared_at := -1.0
	var row_passed_at := -1.0
	var ob_gone_at := -1.0
	while sim.state == "run" and sim.time < 120.0:
		sim.step(1.0 / 60.0)
		for e in sim.drain():
			if e["type"] == "row_pass":
				row_passed_at = sim.traveled
			if e["type"] in ["obstacle_pass", "obstacle_broken", "obstacle_hit"]:
				ob_gone_at = sim.traveled
			if e["type"] == "street_clear":
				cleared_at = sim.traveled
	check(cleared_at > 0.0, "the street cleared")
	check(cleared_at >= row_passed_at and cleared_at >= ob_gone_at,
		"only after the red gate (%.1f) and the barricade (%.1f): %.1f" % [row_passed_at, ob_gone_at, cleared_at])


func test_view_holds_fire_on_the_clear_run() -> void:
	var parts := _view(_one_gang_level(), {"squad": 10})
	var view: LevelView = parts[0]
	var fx: Fx = parts[2]
	for f in 9000:
		view._process(1.0 / 60.0)
		fx._process(1.0 / 60.0)
		if view.clear_run or view.sim.state != "run":
			break
	check(view.clear_run, "the view saw the street clear")
	for i in 120:
		view._process(1.0 / 60.0)
		fx._process(1.0 / 60.0)
	eq(fx.squad_projectiles(), 0, "no knife or bullet in the air on the clear run")
	check(not view._heat_ring.visible, "no tap-heat ring on the clear run")
	_drop(parts)


# ---------------------------------------------------------------- 3. the stash

func test_stash_has_no_bar() -> void:
	var parts := _view(_one_gang_level())
	var view: LevelView = parts[0]
	var bars := 0
	for c in view._hq.get_children():
		# The old bar: a 6 m wide, half-metre-high strip 7.3 m up the stash front.
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh and absf((c as Node3D).position.y - 7.3) < 0.2:
			var size: Vector3 = ((c as MeshInstance3D).mesh as BoxMesh).size
			if size.x >= 5.0 and size.y <= 0.6:
				bars += 1
	eq(bars, 0, "no life bar over the stash")
	_drop(parts)


# ---------------------------------------------------------------- 4. the level start

## The street's clock waits for the level to load: the slow loading frames move nothing, the
## clock starts after the warm frames and START_HOLD_FRAMES drawn frames, and the first played
## frame is one fixed step.
func test_level_clock_waits_for_the_load() -> void:
	var parts := _view(_one_gang_level())
	var view: LevelView = parts[0]
	view._process(2.5)   # the level's build frame
	eq(view.sim.time, 0.0, "the load frame moves nothing")
	eq(view.sim.traveled, 0.0, "the squad stands where the level starts")
	var frames := 1
	while not view.started and frames < 100:
		view._process(0.3 if frames < 4 else 1.0 / 60.0)   # shaders compiling, then smooth
		frames += 1
		if not view.started:
			eq(view.sim.time, 0.0, "still loading (frame %d): the clock waits" % frames)
	check(view.started, "the level started")
	check(frames >= LevelView.WARM_FRAMES + LevelView.START_HOLD_FRAMES + 1, "after the warm frames (%d)" % frames)
	near(view.sim.time, LevelView.DT, "the first played frame is one fixed step")
	# A frame that stays slow never holds the level for good.
	var parts2 := _view(_one_gang_level())
	var v2: LevelView = parts2[0]
	for i in LevelView.START_HOLD_MAX + 1:
		v2._process(0.2)
	check(v2.started, "a slow phone starts after START_HOLD_MAX frames")
	_drop(parts2)
	_drop(parts)


# ---------------------------------------------------------------- view helpers

func _fight_level() -> Dictionary:
	return {"id": 11, "district": 2, "events": [
		{"at": 60, "type": "wave", "groups": [{"enemy": "gunman", "n": 30}]},
		{"at": 400, "type": "finish"}]}


func _frames(view: LevelView, fx: Fx, n: int) -> void:
	for i in n:
		view._process(1.0 / 60.0)
		fx._process(1.0 / 60.0)


func _view(lv: Dictionary, upgrades: Dictionary = {}) -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node("Game")
	if _keep.is_empty():
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
	var view := LevelView.new().setup(lv, upgrades, world, fx, UiKit.FONT)
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
	if not _keep.is_empty():
		game.save = _keep[0]
		game.save_path = _keep[1]
		_keep = []
