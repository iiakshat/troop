extends "res://tests/test_case.gd"
## LevelView rules (spec v2 §3-§5) checked on a real view, headless, frame by frame.


var _keep: Array = []


## Builds a playing LevelView for level n with its own World and Fx under the root.
## Returns [view, world, fx]; free them with _drop.
func _view(n: Variant, upgrades: Dictionary = {}) -> Array:
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
	var view := LevelView.new().setup(n if n is Dictionary else Config.level(n), upgrades, world, fx, UiKit.FONT)
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
	# (A level of its own: the generated L7 no longer has to put a recruit in its first 20 s.)
	var lv := {"id": 7, "district": 1, "events": [
		{"at": 30, "type": "gates", "gates": [{"lane": 0, "op": "recruit", "unit": "sergeant", "n": 4},
			{"lane": 1, "op": "num", "v": 6}, {"lane": 2, "op": "num", "v": -3, "step": 0.5, "max": 5}]},
		{"at": 70, "type": "wave", "groups": [{"enemy": "thug", "n": 10}]},
		{"at": 110, "type": "gates", "gates": [{"lane": 0, "op": "num", "v": -5, "step": 1.0, "max": 6},
			{"lane": 1, "op": "recruit", "unit": "inspector", "n": 3}, {"lane": 2, "op": "num", "v": 8}]},
		{"at": 400, "type": "finish"}]}
	var parts := _view(lv)
	var view: LevelView = parts[0]
	var pilot := Autopilot.new([0, 0], true)
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


## Spec v2 §3 (no join hitch): a level with a new-item hint draws the card once, nearly
## transparent, while it loads (L13's first SWAT card was a 99 ms canvas-compile frame), then
## the card is hidden and fully opaque again for the real hint.
func test_new_item_card_is_prewarmed_at_load() -> void:
	var parts := _view(13)
	var view: LevelView = parts[0]
	check(view.item_card != null, "the card exists from level load")
	if view.item_card:
		check(view.item_card._card.visible and view.item_card._card.modulate.a < 0.1, "drawn nearly transparent while loading")
		for i in 6:
			view.item_card.tick(1.0 / 60.0)
		check(not view.item_card._card.visible, "hidden after the warm frames")
		eq(view.item_card._card.modulate.a, 1.0, "opaque again for the real card")
		check(not view.item_card.showing(), "no card is showing")
	_drop(parts)


## Spec v2 §2 analytics: every hero tap is counted (taps per minute on level_end) and feeds the
## 10 s tap_rate buckets (tap fatigue), which close at the level end.
func test_taps_feed_the_tap_rate_analytics() -> void:
	var analytics: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Analytics")
	analytics.end_taps()   # an earlier test's open bucket
	var seen: Array = []
	analytics.sink = func(n: String, p: Dictionary): seen.append([n, p])
	var parts := _view(1)
	var view: LevelView = parts[0]
	view._process(1.0 / 60.0)
	for i in 5:
		view.tap()
	eq(view.taps, 5, "five taps counted")
	analytics.end_taps()
	var rates := seen.filter(func(e): return e[0] == "tap_rate")
	eq(rates.size(), 1, "one tap_rate bucket closed")
	if rates.size() == 1:
		eq(int(rates[0][1]["taps"]), 5, "with the five taps")
		eq(int(rates[0][1]["level"]), 1, "of level 1")
	analytics.sink = Callable()
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


# ---------------------------------------------------------------- v2.1 fights (FIGHTVIEW)
# The sim's v2.1 events (return_fire, telegraph, attack_land, boss_shot) are fed to the view by
# hand here, in the Task 1 interface's shape, so these checks hold whatever the sim's numbers.

## A district-2 street with one armed gang far up the road and nothing else.
func _fight_level() -> Dictionary:
	return {"id": 11, "district": 2, "events": [
		{"at": 60, "type": "wave", "groups": [{"enemy": "gunman", "n": 30}]},
		{"at": 400, "type": "finish"}]}


## Plays `secs` of view and effects (the tree is not processing in a --script run).
func _tick(view: LevelView, fx: Fx, secs: float) -> void:
	for i in maxi(int(round(secs * 60.0)), 1):
		view._process(1.0 / 60.0)
		fx._process(1.0 / 60.0)


## Steps the view until the first gang is on the street; its horde id (-1: none came).
func _first_gang(view: LevelView) -> int:
	for f in 1200:
		if not view._hordes.is_empty():
			return int(view._hordes.keys()[0])
		view._process(1.0 / 60.0)
	return -1


## Spec v2.1 §1.1: incoming fire has its own tracer pool. A full squad volley (320) never hides
## it and it never takes the squad's projectiles; one event draws at most 8 tracers, each on
## screen for about a second.
func test_enemy_tracers_have_own_pool() -> void:
	var parts := _view(_fight_level(), {"squad": 40})
	var view: LevelView = parts[0]
	var fx: Fx = parts[2]
	var id := _first_gang(view)
	check(id >= 0, "a gang came")
	fx.clear()
	for i in Fx.MAX_PROJ + 20:
		fx.shoot("bullet", Vector3(0, 1, 0), Vector3(0, 1, -90), 10.0)
	eq(fx.squad_projectiles(), Fx.MAX_PROJ, "the squad's pool is full")
	view._handle_events([{"type": "return_fire", "horde": id, "x": 0.0, "z": -48.0, "shots": 40, "lost": 0,
		"blocked": false, "opening": true}])
	var one := fx.enemy_projectiles()
	check(one >= 1 and one <= 8, "one volley draws 1 to 8 tracers (%d)" % one)
	eq(fx.squad_projectiles(), Fx.MAX_PROJ, "the squad's pool is untouched")
	view._handle_events([{"type": "return_fire", "horde": id, "x": 0.0, "z": -48.0, "shots": 3, "lost": 0,
		"blocked": true, "opening": false}])
	eq(fx.enemy_projectiles(), one + 3, "three shots, three more tracers")
	_tick(view, fx, 0.6)
	eq(fx.enemy_projectiles(), one + 3, "still on screen after 0.6 s")
	_tick(view, fx, 0.9)
	eq(fx.enemy_projectiles(), 0, "landed within about 1.5 s")
	_drop(parts)


## Spec v2.1 §1.1: the red -N over the squad sums what is lost within 0.3 s; a loss after that
## starts a new -N; it fades out on its own.
func test_minus_n_sums_window() -> void:
	var parts := _view(_fight_level(), {"squad": 40})
	var view: LevelView = parts[0]
	var fx: Fx = parts[2]
	_tick(view, fx, 1.0 / 60.0)
	check(not view._minus_label.visible, "no -N before any loss")
	view._add_loss(2)
	_tick(view, fx, 0.1)
	view._add_loss(3)
	_tick(view, fx, 0.1)
	view._add_loss(1)
	check(view._minus_label.visible, "the -N shows")
	eq(view._minus_label.text, "-6", "losses within 0.3 s add up")
	_tick(view, fx, 0.15)
	view._add_loss(4)
	eq(view._minus_label.text, "-4", "a loss after the window starts a new -N")
	view._add_loss(0)
	eq(view._minus_label.text, "-4", "a zero loss changes nothing")
	_tick(view, fx, 1.5)
	check(not view._minus_label.visible, "the -N fades out")
	_drop(parts)


## Spec v2.1 §1.1: a volley's loss lands with its tracers: the count, the figures and the red -N
## drop when the shots arrive, not before, exactly once.
func test_volley_loss_lands_with_its_tracers() -> void:
	var parts := _view(_fight_level(), {"squad": 40})
	var view: LevelView = parts[0]
	var fx: Fx = parts[2]
	var id := _first_gang(view)
	_tick(view, fx, 0.2)
	var shown := view._allies.size()
	var total := view.sim.squad.total()
	view.sim.squad.lose(3)   # what the sim's volley took
	view._handle_events([{"type": "return_fire", "horde": id, "x": 0.0, "z": -48.0, "shots": 3, "lost": 3,
		"blocked": false, "opening": true}])
	eq(view.shown_total(), total, "the count holds while the shots fly")
	eq(view._allies.size(), shown, "nobody falls before the tracers land")
	var landed := -1.0
	for i in 90:
		_tick(view, fx, 1.0 / 60.0)
		if view.shown_total() < total:
			landed = (i + 1) / 60.0
			break
	check(landed > 0.2 and landed <= 1.1, "the loss lands with the tracers (%.2f s)" % landed)
	eq(view.shown_total(), total - 3, "exactly the volley's loss")
	eq(view._minus_label.text, "-3", "a red -3 over the squad")
	check(view._allies.size() < shown, "hit figures fall (%d -> %d)" % [shown, view._allies.size()])
	_tick(view, fx, 1.0)
	eq(view.shown_total(), view.sim.squad.total(), "nothing left pending")
	_drop(parts)


## Spec v2.1 §1.2-1.3: a telegraph marks its lane (a sniper also draws his laser) until it lands;
## its countdown runs on the street's clock; the landing clears the mark and shows the loss; a
## revive clears whatever was pending.
func test_telegraph_marks_its_lane_until_it_lands() -> void:
	var parts := _view(_fight_level(), {"squad": 40})
	var view: LevelView = parts[0]
	var fx: Fx = parts[2]
	var id := _first_gang(view)
	var t := view.sim.time
	view._handle_events([{"type": "telegraph", "kind": "grenade", "lane": 2, "src": id, "x": 0.0, "z": -50.0,
		"land_t": t + 1.0}])
	_tick(view, fx, 1.0 / 60.0)
	check(view.lane_marked(2), "the grenade's lane is marked")
	check(not view.lane_marked(0) and not view.lane_marked(1), "and no other lane")
	check(fx.enemy_projectiles() >= 1, "the grenade is in the air")
	view._handle_events([{"type": "telegraph", "kind": "snipe", "lane": 0, "src": id, "x": 0.0, "z": -60.0,
		"land_t": t + 1.2}])
	_tick(view, fx, 1.0 / 60.0)
	check(view.lasers_shown() > 0, "the sniper's laser shows")
	check(view.lane_marked(0), "on the lane he aims at")
	var f0 := view.lane_fill(2)
	view.paused = true
	_tick(view, fx, 0.3)
	view.paused = false
	eq(view.lane_fill(2), f0, "the countdown waits while the street is paused")
	_tick(view, fx, 0.3)
	check(view.lane_fill(2) > f0, "and runs in play (%.2f -> %.2f)" % [f0, view.lane_fill(2)])
	view._handle_events([{"type": "attack_land", "kind": "grenade", "lane": 2, "lost": 3, "blocked": false, "hit": true}])
	_tick(view, fx, 0.3)
	check(not view.lane_marked(2), "the landing clears its mark")
	check(view.lane_marked(0), "the sniper's mark stays")
	eq(view._minus_label.text, "-3", "the landing's loss shows")
	view._on_revive({})
	_tick(view, fx, 1.0 / 60.0)
	check(not view.lane_marked(0) and view.lasers_shown() == 0, "a revive clears what was pending")
	_drop(parts)


## Spec v2.1 §1.3: the lieutenant is the boss's rig at 2.4x (the boss is 3.2x) in his own
## colours, with a smaller bar.
func test_lieutenant_is_a_smaller_tinted_boss() -> void:
	var lvl := {"id": 15, "district": 2, "events": [
		{"at": 60, "type": "wave", "groups": [{"enemy": "boss", "n": 1, "hp": 900}]},
		{"at": 400, "type": "finish"}]}
	var parts := _view(lvl)
	var view: LevelView = parts[0]
	var fx: Fx = parts[2]
	var id := _first_gang(view)
	var lt: Dictionary = (view._hordes[id]["h"] as Dictionary).duplicate(true)
	lt["id"] = 9001
	lt["lieutenant"] = true
	view._handle_events([{"type": "horde_spawn", "horde": lt}])
	_tick(view, fx, 1.0 / 60.0)
	var boss: Dictionary = view._hordes[id]
	var lv: Dictionary = view._hordes[9001]
	eq(String(lv["kind"]), "lieutenant", "drawn as the lieutenant")
	near(view._boss_scale(lv), LevelView.LT_SCALE, "at the lieutenant's scale")
	near(LevelView.LT_SCALE, float(Game.units["lieutenant"]["scale"]), "the view's fallback is units.json lieutenant.scale")
	check(LevelView.LT_SCALE >= 2.8, "drawn big enough to read at range (%.1fx)" % LevelView.LT_SCALE)
	check(view._boss_scale(lv) < view._boss_scale(boss), "smaller than the district boss")
	check(lv.has("bar"), "he has a health bar")
	if lv.has("bar"):
		check((lv["bar"] as Node3D).scale.x < (boss["bar"] as Node3D).scale.x * 0.9, "a smaller one")
	var lc: Crowd = view._crowds.get("lieutenant", null)
	check(lc != null, "his own crowd")
	if lc != null:
		check(lc.multimesh.visible_instance_count >= 1, "drawn on the street")
		check(lc.multimesh.mesh != (view._crowds["boss"] as Crowd).multimesh.mesh, "in his own colours")
	_drop(parts)


## Spec v2.1 §1.1: the HUD's troop pill pulses red when troops are lost (not on a gain).
func test_troop_pill_pulses_red_on_a_loss() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var hud := Hud.new()
	tree.root.add_child(hud)
	if not hud.is_node_ready():
		hud._ready()
	hud.set_troops(50)
	hud._process(0.05)
	eq(hud._troops.modulate, Color.WHITE, "no pulse at the start")
	hud.set_troops(60)
	hud._process(0.05)
	eq(hud._troops.modulate, Color.WHITE, "a gain is not red")
	hud.set_troops(55)
	hud._process(0.05)
	check(hud._troops.modulate.r > 0.9 and hud._troops.modulate.g < 0.8, "a loss pulses the pill red (%s)" % hud._troops.modulate)
	hud._process(1.0)
	eq(hud._troops.modulate, Color.WHITE, "then it settles")
	tree.root.remove_child(hud)
	hud.free()


# ---------------------------------------------------------------- v2.1 §6: honest hints

const _DT := 1.0 / 60.0


## A stand-in camera for NewItemCard (a test's view is not in a live tree): 8 m behind and
## 6 m above the squad, 700 px focal length, x < 0 when behind it.
static func _proj(p: Vector3) -> Vector2:
	var d := 8.0 - p.z
	if d <= 0.5:
		return Vector2(-1, -1)
	return Vector2(360.0 + p.x * 700.0 / d, 420.0 + (6.0 - p.y) * 700.0 / d)


func _card(view: LevelView) -> NewItemCard:
	var card := view.new_item_card()
	card.project = _proj
	return card


## Steps the view until its sim has `n` gangs on the street (at most 2 s).
func _until_gangs(view: LevelView, n: int) -> void:
	for f in 120:
		if view.sim.hordes.size() >= n or view.sim.state != "run":
			return
		view._process(_DT)


## Two brute gangs on a short level (the nearer at 72 m, the other at 92 m) and the armour
## hint, whose `at` is only the far fallback: the sim reports it when a brute gang comes in.
func _brute_level() -> Dictionary:
	return {"id": 5, "district": 1, "events": [
		{"at": 72, "type": "wave", "groups": [{"enemy": "brute", "n": 4}]},
		{"at": 92, "type": "wave", "groups": [{"enemy": "brute", "n": 6}]},
		{"at": 400, "type": "hint", "id": "armour", "icon": "armour", "enemy": "brute"},
		{"at": 600, "type": "finish"}]}


## The live gang nearest the squad.
func _nearest_gang(sim: LevelSim) -> Dictionary:
	var best: Dictionary = {}
	for h in sim.hordes:
		if int(h["count"]) > 0 and (best.is_empty() or LevelSim.front_z(h) > LevelSim.front_z(best)):
			best = h
	return best


func _armour_ev(horde_id: int) -> Dictionary:
	return {"type": "hint", "ev": {"at": 400, "type": "hint", "id": "armour", "icon": "armour", "enemy": "brute", "horde": horde_id}}


## Review focus 5: the hinted gang dies in the same frame the hint fires. Its marker never
## shows, and it never moves to the other brute gang still walking in.
func test_hint_bound_object_dies_immediately() -> void:
	var parts := _view(_brute_level())
	var view: LevelView = parts[0]
	var card := _card(view)
	_until_gangs(view, 2)
	eq(view.sim.hordes.size(), 2, "both brute gangs are on the street")
	var a := _nearest_gang(view.sim)
	a["count"] = 0
	view._handle_events([_armour_ev(int(a["id"]))])
	check(card != null and card.showing(), "the card still shows: the item is new")
	if card == null:
		_drop(parts)
		return
	var drawn := 0
	var other := 0
	for f in 240:
		card.tick(_DT)
		if card.marker_alpha() > 0.0:
			drawn += 1
		if int(card.bound().get("id", -1)) != int(a["id"]):
			other += 1
	eq(drawn, 0, "frames the marker was drawn for a gang that died as the hint fired")
	eq(other, 0, "frames the marker was bound to another object")
	_drop(parts)


## The sim's hint carries the gang that came in; when that gang dies the marker fades out in
## 0.2 s and stays gone while another gang of the same kind is on the street.
func test_marker_never_reattaches() -> void:
	var parts := _view(_brute_level())
	var view: LevelView = parts[0]
	var card := _card(view)
	var shown := false
	for f in 900:
		if view.sim.state != "run":
			break
		view._process(_DT)
		if card.showing():
			shown = true
			break
	check(shown, "the sim reported the armour hint as a brute gang came in")
	if not shown:
		_drop(parts)
		return
	var a := _nearest_gang(view.sim)
	eq(card.bound(), {"kind": "horde", "id": int(a["id"])}, "the marker is bound to the gang that came in")
	card.tick(_DT)
	check(card.marker_alpha() > 0.5, "the marker shows on its gang")
	var p := card.marker_pos()
	check(p.x > 0.0 and p.y > 0.0, "on screen")
	a["count"] = 0
	view.sim.hordes.erase(a)
	card.tick(0.1)
	check(card.marker_alpha() > 0.0 and card.marker_alpha() < 1.0, "fading out (%.2f)" % card.marker_alpha())
	card.tick(0.11)
	eq(card.marker_alpha(), 0.0, "gone 0.2 s after its gang")
	check(not _nearest_gang(view.sim).is_empty(), "another brute gang is still on the street")
	var back := 0
	while card.active():
		card.tick(_DT)
		if card.marker_alpha() > 0.0 or int(card.bound()["id"]) != int(a["id"]):
			back += 1
	eq(back, 0, "frames the marker came back on another gang")
	_drop(parts)


## One clock: the card and the marker share hints.json show_s, and nothing waits for an
## object to come on screen.
func test_marker_and_card_same_duration() -> void:
	var tbl := NewItemCard.table()
	check(not tbl.has("card_s") and not tbl.has("outline_s"), "one duration in hints.json (show_s)")
	var show_s := float(tbl.get("show_s", 0.0))
	check(show_s >= 2.0 and show_s <= 3.5, "show_s is about 2-3 s")
	var parts := _view(_brute_level())
	var view: LevelView = parts[0]
	var card := _card(view)
	_until_gangs(view, 1)
	var a := _nearest_gang(view.sim)
	view._handle_events([_armour_ev(int(a["id"]))])
	var card_last := -1
	var mark_last := -1
	for f in 600:
		card.tick(_DT)
		if card.showing():
			card_last = f
		if card.marker_alpha() > 0.0:
			mark_last = f
	check(mark_last > 0, "the marker showed")
	check(absi(card_last - mark_last) <= 1, "the card (%d) and the marker (%d) end together" % [card_last, mark_last])
	check(absf((card_last + 1) * _DT - show_s) < 0.05, "both last show_s (%.2f s)" % ((card_last + 1) * _DT))
	check(not card.active(), "nothing is left running")
	# An object that never comes on screen: no 8 s wait, the marker's time ends with the card.
	Game.save["seen_hints"] = []
	view._handle_events([_armour_ev(99999)])
	var left := 0
	for f in 600:
		card.tick(_DT)
		if card.active():
			left = f
	check((left + 1) * _DT < show_s + 0.05, "a marker with no object ends with its card (%.2f s)" % ((left + 1) * _DT))
	_drop(parts)


## Spec v2.1 §6.2: good, bad and to-use items read apart at a glance (colour and shape), on
## the card frame and numbers and in the Tutorial's rings.
func test_tone_per_item() -> void:
	var want := {
		"gain": ["sergeant", "inspector", "swat", "sniper", "commando", "smg", "turncoat", "no_armour", "gang_split", "shield", "bomb"],
		"threat": ["pothole", "barricade", "car", "armour", "riot", "molotov", "sniper_foe", "grenadier", "boss", "lieutenant", "return_fire"],
		"use": ["barrel", "red_gate"]}
	var items: Dictionary = NewItemCard.table().get("items", {})
	for tone in want:
		for id in want[tone]:
			check(items.has(id), "hints.json has %s" % id)
			eq(NewItemCard.tone(id), tone, "%s's tone" % id)
	for id in items:
		check(String(items[id].get("tone", "")) in ["gain", "threat", "use"], "%s has a tone" % id)
	var cols := {}
	var shapes := {}
	for tone in want:
		cols[NewItemCard.tone_color(tone).to_html()] = true
		shapes[NewItemCard.tone_shape(tone)] = true
	eq(cols.size(), 3, "three tone colours")
	eq(shapes.size(), 3, "three tone shapes (colour-blind safe)")
	for e in items["riot"]["effects"]:
		check(String(e.get("icon", "")) != "shield", "the riot card shows the enemy's riot shield, not the player's")
	eq(Tutorial.ring_color("red_gate"), NewItemCard.tone_color("use"), "the red-gate lesson ring is the use tone")
	eq(Tutorial.ring_color("barrel"), NewItemCard.tone_color("use"), "the barrel lesson ring is the use tone")
	# The card's frame and numbers take the tone.
	var parts := _view(_brute_level())
	var view: LevelView = parts[0]
	var card := _card(view)
	_until_gangs(view, 1)
	view._handle_events([_armour_ev(int(_nearest_gang(view.sim)["id"]))])
	eq(card.frame_color(), NewItemCard.tone_color("threat"), "the armour card has a threat frame")
	eq(card.marker_color(), NewItemCard.tone_color("threat"), "and a threat marker")
	eq(card.marker_shape(), "ring", "a gang gets a ring with the tone chip")
	_drop(parts)


## Spec v2.1 §6.3: no lane singled out. Two sergeant offers in one row: both signs sparkle in
## the gain tone, no ellipse; the plain +5 lane gets nothing.
func test_two_matching_offers_both_sparkle() -> void:
	var parts := _view(4)
	var view: LevelView = parts[0]
	var card := _card(view)
	Game.save["seen_hints"] = []
	view.sim.rows.append({"id": 900, "at": 20, "z": -20.0, "gates": [
		{"lane": 0, "op": "recruit", "unit": "sergeant", "n": 2},
		{"lane": 1, "op": "recruit", "unit": "sergeant", "n": 3},
		{"lane": 2, "op": "num", "v": 5}]})
	view._handle_events([{"type": "hint", "ev": {"at": 6, "type": "hint", "id": "sergeant", "icon": "sergeant"}}])
	card.tick(_DT)
	eq(card.bound(), {"kind": "row", "id": 900}, "bound to the row")
	eq(card.marker_shape(), "sparkle", "gates get sparkles, not an ellipse")
	eq(card.marker_color(), NewItemCard.tone_color("gain"), "in the gain tone")
	var sp: Array = card.sparkles()
	eq(sp.size(), 2, "both sergeant signs sparkle")
	if sp.size() == 2:
		var x0 := _proj(Vector3(LevelView.LANE_X[0], 1.7, -20.0)).x
		var x1 := _proj(Vector3(LevelView.LANE_X[1], 1.7, -20.0)).x
		var x2 := _proj(Vector3(LevelView.LANE_X[2], 1.7, -20.0)).x
		for p in sp:
			var px := (p as Vector2).x
			check(minf(absf(px - x0), absf(px - x1)) < absf(px - x2), "a sparkle sits on a sergeant sign, not the +5")
		check(absf((sp[0] as Vector2).x - (sp[1] as Vector2).x) > 40.0, "one per sign")
	# The row passes: the sparkles fade with it and nothing jumps to the next row.
	view.sim.rows.clear()
	view.sim.rows.append({"id": 901, "at": 60, "z": -60.0, "gates": [{"lane": 1, "op": "recruit", "unit": "sergeant", "n": 9}]})
	card.tick(0.25)
	eq(card.marker_alpha(), 0.0, "gone with its row")
	eq(card.sparkles().size(), 0, "no sparkle on the next row")
	_drop(parts)


## An obstacle hint is a small toned tag over that obstacle, gone 0.2 s after it is passed.
func test_obstacle_tag_bound_and_toned() -> void:
	var parts := _view(4)
	var view: LevelView = parts[0]
	var card := _card(view)
	Game.save["seen_hints"] = []
	var ob := {"id": 950, "kind": "pothole", "lane": 2, "z": -25.0, "fall": 3, "hp": 0.0, "hp_max": 0.0}
	view.sim.obstacles.append(ob)
	view._handle_events([{"type": "hint", "ev": {"at": 6, "type": "hint", "id": "pothole", "icon": "pothole"}}])
	card.tick(_DT)
	eq(card.bound(), {"kind": "obstacle", "id": 950}, "bound to the pothole")
	eq(card.marker_shape(), "tag", "a tag, not a ring")
	eq(card.marker_color(), NewItemCard.tone_color("threat"), "in the threat tone")
	var at := _proj(Vector3(LevelView.LANE_X[2], 0.0, -25.0))
	check(absf(card.marker_pos().x - at.x) < 30.0 and card.marker_pos().y < at.y, "over the pothole")
	view.sim.obstacles.erase(ob)
	card.tick(0.21)
	eq(card.marker_alpha(), 0.0, "gone 0.2 s after it is passed")
	_drop(parts)


## Spec v2.1 §6.4: every hint shown is logged (item, level, t).
func test_hint_shown_is_logged() -> void:
	var analytics: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Analytics")
	var seen: Array = []
	analytics.sink = func(n: String, p: Dictionary): seen.append([n, p])
	var parts := _view(4)
	var view: LevelView = parts[0]
	Game.save["seen_hints"] = []
	view._handle_events([{"type": "hint", "ev": {"at": 6, "type": "hint", "id": "sergeant", "icon": "sergeant"}}])
	var ev := seen.filter(func(e): return e[0] == "hint_shown")
	eq(ev.size(), 1, "one hint_shown")
	if ev.size() == 1:
		eq(String(ev[0][1]["item"]), "sergeant", "the item")
		eq(int(ev[0][1]["level"]), 4, "the level")
		check(ev[0][1].has("t"), "the time into the level")
	analytics.sink = Callable()
	_drop(parts)


# ---------------------------------------------------------------- v2.1 review fixes

## Review v2.1 (code): a mark the sim called off (the squad fell or revived, the finish, a
## sniper who died) goes quietly: no flash, no blast, no shake.
func test_cancelled_attack_lands_silently() -> void:
	var parts := _view(_fight_level(), {"squad": 40})
	var view: LevelView = parts[0]
	var fx: Fx = parts[2]
	var id := _first_gang(view)
	var t := view.sim.time
	view._handle_events([{"type": "telegraph", "id": 77, "kind": "barrage", "lane": 1, "lanes": [1], "src": id,
		"x": 0.0, "z": 0.0, "land_t": t + 1.0}])
	_tick(view, fx, 1.0 / 60.0)
	check(view.lane_marked(1), "the barrage marks the lane")
	var shake0 := float(view.world.get("_shake")) if view.world.get("_shake") != null else 0.0
	view._handle_events([{"type": "attack_land", "id": 77, "kind": "barrage", "lane": 1, "lanes": [1], "lost": 0,
		"blocked": false, "hit": false, "cancelled": true}])
	_tick(view, fx, 1.0 / 60.0)
	check(not view.lane_marked(1), "the mark is gone")
	eq(float((view._zones[1] as Dictionary)["flash"]), 0.0, "no landing flash")
	if view.world.get("_shake") != null:
		check(float(view.world.get("_shake")) <= shake0, "no shake")
	_drop(parts)


## Review v2.1 (code): a boss in melee swings his own fists; he never queues a thug-sized charge,
## so his death later is his own big fall.
func test_boss_melee_queues_no_charge() -> void:
	var lvl := {"id": 10, "district": 1, "events": [
		{"at": 60, "type": "wave", "groups": [{"enemy": "boss", "n": 1, "hp": 5000}]},
		{"at": 400, "type": "finish"}]}
	var parts := _view(lvl, {"squad": 40})
	var view: LevelView = parts[0]
	var fx: Fx = parts[2]
	var id := _first_gang(view)
	check(id >= 0, "the boss comes")
	if id < 0:
		_drop(parts)
		return
	var hv: Dictionary = view._hordes[id]
	view._handle_events([{"type": "melee", "horde": id, "enemies": 1, "lost": 3, "shielded": false}])
	eq(float(hv.get("strike", 0.0)), 0.0, "no strikers queued for him")
	view.sim.hordes[0]["count"] = 0
	_tick(view, fx, 0.2)
	for c in view._charging:
		check(String(c["kind"]) != String(hv["kind"]), "he never charges as a thug-sized figure")
	_drop(parts)


## Review v2.1 (honest numbers): a bar under every gang's count, measured against the squad's
## firepower: full red when the people who would reach the squad are worth all of it, empty when
## the squad's fire melts the gang first.
func test_reach_bar_measures_against_firepower() -> void:
	for case in [[6, false], [6000, true]]:
		var lvl := {"id": 11, "district": 2, "events": [
			{"at": 60, "type": "wave", "groups": [{"enemy": "thug", "n": int(case[0])}]},
			{"at": 400, "type": "finish"}]}
		var parts := _view(lvl, {"squad": 20})
		var view: LevelView = parts[0]
		var fx: Fx = parts[2]
		var id := _first_gang(view)
		_tick(view, fx, 0.1)
		var hv: Dictionary = view._hordes.get(id, {})
		check(hv.has("reach_bg"), "%d thugs: the gang has a reach bar" % int(case[0]))
		if hv.has("reach_bg"):
			check((hv["reach_bg"] as Node3D).visible, "%d thugs: shown in play" % int(case[0]))
			eq((hv["reach_fill"] as Node3D).visible, bool(case[1]), "%d thugs vs 21: red only when some would reach" % int(case[0]))
			eq(view.sim.reach_estimate(hv["h"]) > 0, bool(case[1]), "%d thugs: the estimate agrees" % int(case[0]))
		_drop(parts)
