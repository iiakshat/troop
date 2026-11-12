extends "res://tests/test_case.gd"
## The shield bubble in the street (src/game/shield_bubble.gd): sized to hold the formation
## the player sees (every figure, feet to head), grows with the squad, stops return fire on its
## surface, and blinks only in its honest last second.

const VIEW_TESTS := preload("res://tests/test_view_rules.gd")


func _cfg() -> Dictionary:
	return ShieldBubble.look()


## Ellipsoid value of p for a fit (<= 1 inside, 1 on the surface).
func _e(p: Vector3, f: Dictionary) -> float:
	var c: Vector3 = f["centre"]
	var r: Vector3 = f["radii"]
	return pow((p.x - c.x) / r.x, 2) + pow((p.y - c.y) / r.y, 2) + pow((p.z - c.z) / r.z, 2)


## A formation's figures as the view stands them: feet (x, z) and height (y).
func _formation(n: int, half: float, x := 0.0) -> Array:
	var pts: Array = []
	for i in n:
		var o := Squad.slot_offset(i, n, half)
		var h := LevelView.CHAR_H * (1.0 if i == 0 else Squad.crowd_scale(n))
		pts.append(Vector3(x + o.x, h, o.y))
	return pts


func test_config_has_the_bubble_look() -> void:
	var c := _cfg()
	for k in ["pad", "min_r", "head", "ease", "pop_s", "burst_s", "blink_s", "blink_hz", "rim", "hit_s"]:
		check(c.has(k), "world_look.json shield_bubble has " + k)


func test_lone_hero_gets_the_smallest_bubble() -> void:
	var c := _cfg()
	var f := ShieldBubble.fit([Vector3(2.8, 1.85, -0.5)], c)
	near(f["radii"].x, float(c["min_r"]), "lone hero: smallest width")
	near(f["radii"].z, float(c["min_r"]), "lone hero: smallest depth")
	near(f["radii"].y, 1.85 + float(c["head"]), "headroom over the hero")
	near(f["centre"].x, 2.8, "centred on him (x)")
	near(f["centre"].z, -0.5, "centred on him (z)")
	near(f["centre"].y, 0.0, "a dome on the road")


func test_bubble_holds_every_figure_head_to_toe() -> void:
	var c := _cfg()
	var half := float(Config.units()["world"]["formation_half_width"])
	var fig_r := float(Config.units()["world"]["figure_radius"])
	for n in [1, 2, 5, 12, 30, 72]:
		var pts := _formation(n, half, 2.8)
		var f := ShieldBubble.fit(pts, c)
		var worst := 0.0
		for p in pts:
			worst = maxf(worst, _e(p, f))   # the top of the head
			for dx in [-fig_r, fig_r]:
				worst = maxf(worst, _e(Vector3(p.x + dx, 0.0, p.z), f))   # both sides of the feet
		check(worst <= 1.0001, "n=%d: every figure inside the bubble (worst %.3f)" % [n, worst])


func test_bubble_grows_with_the_squad_but_stays_close() -> void:
	var c := _cfg()
	var half := float(Config.units()["world"]["formation_half_width"])
	var prev := 0.0
	var prev_w := 0.0
	for n in [1, 3, 8, 20, 40, 72]:
		var pts := _formation(n, half)
		var w := 0.0
		for p in pts:
			w = maxf(w, absf(p.x))
		var f := ShieldBubble.fit(pts, c)
		var rx: float = f["radii"].x
		check(rx >= w + float(c["pad"]) - 0.0001, "n=%d: wider than the formation (%.2f vs %.2f)" % [n, rx, w])
		# A big squad packs a little narrower (Squad.slot_offset) and its troops are drawn
		# smaller: the bubble follows the formation, so allow a few cm either way there.
		if w >= prev_w - 0.0001:
			check(rx >= prev - 0.05, "n=%d: a wider formation never gets a narrower bubble (%.2f < %.2f)" % [n, rx, prev])
		prev = rx
		prev_w = w
	var small := ShieldBubble.fit(_formation(1, half), c)
	var big := ShieldBubble.fit(_formation(72, half), c)
	check(big["radii"].x > small["radii"].x + 0.6, "a full squad's bubble is clearly wider than the hero's")
	# Sized to the formation: a full squad (about one lane wide) never sits in the old 3.4 m dome.
	check(big["radii"].x < 3.0, "a full squad's bubble hugs it (%.2f m half width)" % big["radii"].x)


func test_ray_entry_stops_fire_on_the_surface() -> void:
	var f := {"centre": Vector3(1.0, 0.0, 0.5), "radii": Vector3(2.0, 2.3, 3.0)}
	var from := Vector3(1.0, 1.2, -30.0)
	var to := Vector3(1.0, 1.2, 0.5)
	var t := ShieldBubble.ray_entry(f["centre"], f["radii"], from, to)
	check(t > 0.0 and t < 1.0, "the shot enters the bubble on its way (t=%.3f)" % t)
	var p := from.lerp(to, t)
	near(_e(p, f), 1.0, "it stops on the surface")
	check(p.z < 0.5, "on the side facing the shooter")
	eq(ShieldBubble.ray_entry(f["centre"], f["radii"], Vector3(10, 1, -30), Vector3(10, 1, 30)), -1.0,
		"a line that misses the bubble")


func test_blink_only_in_the_last_second() -> void:
	var c := _cfg()
	for t in [4.0, 2.5, float(c["blink_s"]) + 0.01]:
		eq(ShieldBubble.blink(t, c), 1.0, "steady at %.2f s left" % t)
	var low := 0
	var n := 40
	for i in n:
		if ShieldBubble.blink(float(c["blink_s"]) * (i + 0.5) / n, c) < 0.99:
			low += 1
	check(low >= n / 4 and low <= n * 3 / 4, "blinks in the last second (%d of %d samples dim)" % [low, n])


func test_pop_in_starts_small_and_settles() -> void:
	var c := _cfg()
	check(ShieldBubble.pop_scale(0.0, c) < 0.8, "pops in from small")
	near(ShieldBubble.pop_scale(1.0, c), 1.0, "settles at full size")
	var peak := 0.0
	for i in 21:
		peak = maxf(peak, ShieldBubble.pop_scale(i / 20.0, c))
	check(peak > 1.0, "with a little overshoot (%.3f)" % peak)


## On a real LevelView: the bubble pops up with the sim's shield, holds the squad the player
## sees, ripples where blocked fire hits it, then bursts and is gone once the sim's shield ends.
func test_level_view_bubble_follows_the_sim_shield() -> void:
	var vt = VIEW_TESTS.new()
	var parts: Array = vt._view(4)
	var view: LevelView = parts[0]
	view.sim.squad.add("constable", 30)
	view._sync_allies(Vector3(view._squad_x, 0, 0))
	for i in 40:
		view._update_visuals(0.1)   # the figures settle into their places
	var b: ShieldBubble = view.shield_bubble()
	check(not b.visible, "no bubble before the shield")
	view.sim.charges["shield"] = 1
	check(view.sim.use_power("shield"), "shield up")
	view._handle_events(view.sim.drain())
	for i in 20:
		view._update_visuals(0.05)
	check(b.visible, "the bubble is up")
	var f := {"centre": b.centre, "radii": b.radii}
	var worst := 0.0
	for a in view._allies:
		var p: Vector3 = a["pos"]
		var h := LevelView.CHAR_H * (1.0 if a["kind"] == "hero" else LevelView.crowd_scale(view._allies.size()))
		worst = maxf(worst, _e(Vector3(p.x, h, p.z), f))
	check(worst <= 1.0001, "every figure on screen is inside it (worst %.3f)" % worst)
	var hit := b.hit(Vector3(b.centre.x, 1.2, -30.0), Vector3(b.centre.x, 1.2, b.centre.z))
	near(_e(hit, {"centre": b.centre, "radii": b.scale}), 1.0, "blocked fire ends on its surface as drawn")
	check(hit.z < b.centre.z, "on the side facing the gang")
	eq(b.active_hits(), 1, "and leaves a ripple there")
	view.sim.shield_t = 0.0
	view._update_visuals(0.05)
	check(b.visible, "it bursts as the shield ends")
	for i in 20:
		view._update_visuals(0.05)
	check(not b.visible, "then it is gone")
	eq(b.hit(Vector3(0, 1, -30), Vector3(0, 1, 0)), Vector3(0, 1, 0), "no bubble: nothing stops a shot")
	vt._drop(parts)


## The HUD's shield button shows the shield draining while it is up (a ring around the
## button, full at the press, empty when the sim's shield ends), then nothing.
func test_hud_shield_button_drains_while_up() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var hud := Hud.new()
	tree.root.add_child(hud)
	if not hud.is_node_ready():
		hud._ready()
	var ring: Control = hud.shield_ring()
	check(not ring.visible, "no ring before the shield")
	hud.set_shield(4.0)
	check(ring.visible, "ring up with the shield")
	near(ring.frac, 1.0, "full at the press")
	hud.set_shield(1.5)
	near(ring.frac, 1.5 / 4.0, "drains with the sim's timer")
	hud.set_shield(0.0)
	check(not ring.visible, "gone when the shield ends")
	hud.set_shield(2.0)
	near(ring.frac, 1.0, "a new shield (a revive's 2 s) starts full again")
	tree.root.remove_child(hud)
	hud.free()
