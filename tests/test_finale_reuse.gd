extends "res://tests/test_case.gd"
## The Bottle Shot built while the level loads is the one that plays (no build on the burst into
## the stash): a dormant finale moved to the hero matches a fresh build there, it stays hidden
## and still until the squad reaches the stash, it is only ever reused by its own level, and a
## finale left half way (restart, home) gives the street its camera back.


var _keep: Array = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Readies `n` by hand when the tree is not live yet (a SceneTree script's root).
func _ready_by_hand(n: Node) -> void:
	if n != null and not n.is_node_ready():
		n._ready()


## A dormant finale for level `lv` built for a hero at `hero`, under the root (built, with its
## HUD and weapon ready).
func _dormant(lv: int, hero: Vector3, world: World = null) -> BottleShot:
	var s := BottleShot.new().setup(world, null, UiKit.FONT, lv, 40, hero, 0.0)
	s.dormant = true
	_tree().root.add_child(s)
	_ready_by_hand(s)
	_ready_by_hand(s.hud)
	_ready_by_hand(s._mode)
	return s


func _drop_node(n: Node) -> void:
	if n.get_parent():
		n.get_parent().remove_child(n)
	n.free()


## Where everything drawn under `n` stands in the finale's frame, in tree order: each mesh and
## light, and each instance of a MultiMesh (the dust motes).
func _xforms(n: Node, xf: Transform3D, out: Array) -> Array:
	var x := xf
	if n is Node3D:
		x = xf * (n as Node3D).transform
	if n is MultiMeshInstance3D:
		# Its instances are placed in its own frame; headless keeps no instance data, so check
		# the box they fill (custom_aabb, set from the same hero) instead.
		out.append(Transform3D(x.basis, x * (n as MultiMeshInstance3D).custom_aabb.get_center()))
	elif n is VisualInstance3D:
		out.append(x)
	for c in n.get_children():
		_xforms(c, x, out)
	return out


## Tests that build a finale need a booted Game (the knife skin, the Armory); this keeps the
## real one untouched.
func _boot() -> void:
	var game: Node = _tree().root.get_node("Game")
	_keep = [game.save.duplicate(true), game.save_path]
	game.save_path = ""
	game.boot({})


func _unboot() -> void:
	var game: Node = _tree().root.get_node("Game")
	game.save = _keep[0]
	game.save_path = _keep[1]


func _same_xforms(a: Array, b: Array) -> String:
	if a.size() != b.size():
		return "%d nodes vs %d" % [a.size(), b.size()]
	for i in a.size():
		var p: Transform3D = a[i]
		var q: Transform3D = b[i]
		if p.origin.distance_to(q.origin) > 0.001 or not p.basis.is_equal_approx(q.basis):
			return "node %d at %s, fresh build at %s" % [i, p.origin, q.origin]
	return ""


## One level per stash and weapon (bar knives, carnival pistol, docks bow, factory stars,
## rooftop sniper, and the L50 boss set): built for a hero at the origin, then moved to a hero
## in the right lane, the set stands exactly where a fresh build for that hero stands.
func test_woken_set_matches_a_fresh_build() -> void:
	_boot()
	var to := Vector3(1.35, 0.0, 0.42)
	for lv in [5, 11, 21, 31, 41, 50]:
		var a := _dormant(lv, Vector3.ZERO)
		var b := _dormant(lv, to)
		a._place(to)
		eq(a.hero_pos, to, "level %d: hero" % lv)
		near(a._wall_z, b._wall_z, "level %d: back wall" % lv)
		near(a._wall_front, b._wall_front, "level %d: wall front" % lv)
		eq(a._built.size(), b._built.size(), "level %d: set pieces" % lv)
		check(a._built.size() > 10, "level %d: the set is built (%d pieces)" % [lv, a._built.size()])
		var bad := ""
		for i in mini(a._built.size(), b._built.size()):
			if a._built[i] == a._reticle:
				continue   # the aim ring is placed on every aiming frame (and drawn while warming)
			var why := _same_xforms(_xforms(a._built[i], Transform3D(), []), _xforms(b._built[i], Transform3D(), []))
			if why != "" and bad == "":
				bad = "level %d piece %d (%s): %s" % [lv, i, (a._built[i] as Node).name, why]
		check(bad == "", bad)
		if b._dust_mat:
			for k in ["spot_a", "spot_b"]:
				var da: Vector3 = a._dust_mat.get_shader_parameter(k)
				var db: Vector3 = b._dust_mat.get_shader_parameter(k)
				check(da.distance_to(db) < 0.001, "level %d: dust %s %s vs %s" % [lv, k, da, db])
		_drop_node(a)
		_drop_node(b)
	_unboot()


## The stash's spotlights aim in the finale's own frame: built out of sight under the road (the
## warm instance), they must still light the bottle wall once the set moves to the hero.
func test_set_lights_aim_at_the_wall_wherever_it_is_built() -> void:
	_boot()
	for lv in [5, 11, 21, 31, 41]:
		var s := BottleShot.new().setup(null, null, UiKit.FONT, lv, 40, Vector3.ZERO, 0.0)
		s.dormant = true
		s.position = Vector3(0, -22.0, -30.0)   # where LevelView builds it while loading
		_tree().root.add_child(s)
		_ready_by_hand(s)
		var n := 0
		for l in s.find_children("*", "SpotLight3D", true, false):
			var spot := l as SpotLight3D
			var dir := -spot.transform.basis.z.normalized()
			var hit := spot.position + dir * ((s._wall_z - spot.position.z) / minf(dir.z, -0.001))
			check(absf(hit.x - s.hero_pos.x) < 1.0 and hit.y > s._floor_y and hit.y < s._floor_y + 3.0,
				"level %d (%s): a spotlight at %s aims at %s, not the bottle wall" % [lv, s.theme, spot.position, hit])
			n += 1
		check(n >= 2, "level %d: the stash has its spotlights" % lv)
		_drop_node(s)
	_unboot()


## Resting until the stash: hidden, no process or input, its HUD and weapon overlays hidden,
## the warm-only extras gone or hidden, and the logic untouched.
func test_resting_finale_is_hidden_and_still() -> void:
	_boot()
	for lv in [5, 11, 41]:
		var s := _dormant(lv, Vector3.ZERO)
		var fresh := BottleLogic.new(Armory.apply_finale(Config.load_json("res://config/finale.json"), Game.save), lv)
		s.rest()
		check(not s.visible, "level %d: hidden" % lv)
		eq(s.process_mode, Node.PROCESS_MODE_DISABLED, "level %d: no process or input" % lv)
		check(s.hud != null and not s.hud.visible, "level %d: HUD hidden" % lv)
		for l in s.find_children("*", "CanvasLayer", true, false):
			check(not (l as CanvasLayer).visible or (l as Node).is_queued_for_deletion(), "level %d: overlay %s hidden" % [lv, (l as Node).name])
		check(s._ghost == null, "level %d: the see-through HUD goes" % lv)
		check(s._warm_root != null and not s._warm_root.visible, "level %d: warm extras hidden" % lv)
		eq(s.logic.shots_left, fresh.shots_left, "level %d: no shot taken" % lv)
		eq(s.logic.broken_count(), 0, "level %d: nothing broken" % lv)
		eq(s._state, "intro", "level %d: not started" % lv)
		eq(s._shatters.size(), 0, "level %d: no bottle broken on screen" % lv)
		_drop_node(s)
	_unboot()


## Only this level's resting finale is reused; anything else is built fresh.
func test_reuse_only_this_levels_resting_finale() -> void:
	_boot()
	var s := _dormant(11, Vector3.ZERO)
	check(BottleShot.reusable(s, 11), "the resting L11 finale plays L11")
	check(not BottleShot.reusable(s, 12), "never another level's")
	check(not BottleShot.reusable(null, 11), "none built")
	s.dormant = false
	check(not BottleShot.reusable(s, 11), "never one already playing")
	_drop_node(s)
	var gone := _dormant(11, Vector3.ZERO)
	gone.queue_free()
	check(not BottleShot.reusable(gone, 11), "never one on its way out")
	_drop_node(gone)
	_unboot()


## Woken in front of the hero it plays like a fresh finale (troops, bonus, intro, camera); freed
## half way (restart or home from the pause menu) it hands the camera and lens back.
func test_woken_finale_plays_and_gives_the_camera_back() -> void:
	_boot()
	var world := World.new()
	_tree().root.add_child(world)
	_ready_by_hand(world)
	var s := _dormant(21, Vector3.ZERO, world)
	s.rest()
	var hero := Vector3(1.2, 0.0, 0.3)
	s.wake(57, hero, 0.25)
	eq(s.position, Vector3.ZERO, "at the street's origin")
	eq(s.hero_pos, hero, "in front of the hero")
	check(s.visible and s.hud.visible, "shown with its HUD")
	eq(s.process_mode, Node.PROCESS_MODE_INHERIT, "playing")
	check(not s.dormant, "no longer dormant")
	eq(s.troops, 57, "pays for the squad that reached it")
	near(s.station_bonus, 0.25, "with the level's coin bonus")
	eq(s._state, "intro", "bursting in")
	check(world._cam_override != null, "it holds the camera")
	_drop_node(s)
	check(world._cam_override == null, "freed half way, it gives the camera back")
	near(world.camera.near, World.BASE_NEAR, "and the lens")
	_drop_node(world)
	_unboot()


# ---------------------------------------------------------------- in a real level

func _view(n: int) -> Array:
	var tree := _tree()
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
		_ready_by_hand(node)
	var view := LevelView.new().setup(Config.level(n), {}, world, fx, UiKit.FONT)
	view.input_enabled = false
	tree.root.add_child(view)
	_ready_by_hand(view)
	return [view, world, fx]


func _drop(parts: Array) -> void:
	for n in parts:
		if is_instance_valid(n):
			_drop_node(n)
	var game: Node = _tree().root.get_node("Game")
	game.save = _keep[0]
	game.save_path = _keep[1]


## L11 (pistol): the finale built at load rests through the level (a loss and a revive too),
## is the one that plays, and the level lets go of it.
func test_level_plays_the_finale_it_built_at_load() -> void:
	var parts := _view(11)
	var view: LevelView = parts[0]
	var warm: BottleShot = view._finale_warm
	check(warm != null and warm.dormant, "a dormant finale is built at load")
	if warm == null:
		_drop(parts)
		return
	_ready_by_hand(warm)
	_ready_by_hand(warm.hud)
	_ready_by_hand(warm._mode)
	for f in LevelView.WARM_FRAMES + 2:
		view._process(1.0 / 60.0)
	check(is_instance_valid(warm) and not warm.is_queued_for_deletion(), "it outlives the warm frames")
	check(not warm.visible, "and rests hidden")
	# Lost, then revived (the rewarded ad): the same finale still rests, untouched.
	view.sim.state = "lost"
	view._state = "done"
	check(view.revive(view.sim.revive_troops()), "revived")
	view._process(1.0 / 60.0)
	check(BottleShot.reusable(warm, 11) and not warm.visible, "the finale still rests after a revive")
	view._begin_strike()
	check(view.finale == warm, "the squad bursts into the finale built at load")
	check(view._finale_warm == null, "the level lets go of it")
	eq(warm.hero_pos, view._slot_pos(0, view._allies.size()), "in front of the hero")
	check(warm.visible and not warm.dormant, "playing")
	_drop(parts)


## The burst-in rushes the camera into the hero's head for the pistol, bow and sniper: his body
## is hidden before the camera gets near his head, so his hair and its outline never sweep up
## over the screen as a dark slab (they did for 2 frames at 60 fps). Knives and stars rest
## behind him and keep him.
func test_burst_in_never_flies_through_the_heros_head() -> void:
	_boot()
	var world := World.new()
	_tree().root.add_child(world)
	_ready_by_hand(world)
	for lv in [11, 21, 41]:
		var s := _dormant(lv, Vector3.ZERO, world)
		s.rest()
		var hero := Vector3(1.2, 0.0, 0.3)
		s.wake(40, hero, 0.0)
		var head := s.to_world(Vector3(0.0, float(s.logic.wcfg.get("eye_y", 1.6)), 0.0))
		var near_head := 0
		var bad := ""
		eq(s._state, "intro", "L%d: bursting in" % lv)
		for i in 101:  # along the rush's own path (as _process moves it), street to stash
			s._cam = s._intro_from.interpolate_with(s._rest_view(), i / 100.0)
			if s._cam.origin.distance_to(head) < 1.0:
				near_head += 1
				if not s.camera_in_head() and bad == "":
					bad = "step %d, %.2f m from his head" % [i, s._cam.origin.distance_to(head)]
		check(near_head > 0, "L%d: the rush ends in his head" % lv)
		eq(bad, "", "L%d: he is hidden whenever the rushing camera is within 1 m of his head" % lv)
		_drop_node(s)
	var k := _dormant(1, Vector3.ZERO, world)
	k.rest()
	k.wake(40, Vector3.ZERO, 0.0)
	k._cam = k._rest_view()
	check(not k.camera_in_head(), "the knife finale rests behind him: he stays drawn to the end of the rush")
	_drop_node(k)
	_drop_node(world)
	_unboot()


## Spec v2.1 §4.3 on the finale built at load: a guest level's resting finale is built (and
## warmed) with the guest weapon, not the district's, so its model and set compile while the
## level loads; woken, it hands the weapon over as a gift (the real weapon hidden until the gift
## reaches the hand), then aims with it.
func test_guest_level_rests_with_its_gift_weapon() -> void:
	var cases := {4: "pistol", 13: "bow", 19: "sniper"}
	for lv in cases:
		var parts := _view(lv)
		var view: LevelView = parts[0]
		var warm: BottleShot = view._finale_warm
		check(warm != null and warm.dormant, "L%d: a dormant finale is built at load" % lv)
		if warm == null:
			_drop(parts)
			continue
		_ready_by_hand(warm)
		_ready_by_hand(warm.hud)
		_ready_by_hand(warm._mode)
		check(warm.logic.guest, "L%d: a guest level" % lv)
		eq(warm.logic.weapon, cases[lv], "L%d: built with the guest weapon" % lv)
		check(warm._mode != null and warm._mode.is_inside_tree(), "L%d: its weapon model is built at load" % lv)
		for f in LevelView.WARM_FRAMES + 2:
			view._process(1.0 / 60.0)
		check(BottleShot.reusable(warm, lv) and not warm.visible, "L%d: rests hidden" % lv)
		view._begin_strike()
		check(view.finale == warm, "L%d: the squad bursts into it" % lv)
		check(warm._gift != null, "L%d: the guest weapon comes as a gift" % lv)
		if warm._gift == null:
			_drop(parts)
			continue
		eq(warm._gift.weapon, cases[lv], "L%d: the gift is the guest weapon" % lv)
		check(not warm._mode.visible, "L%d: the real weapon waits for the gift" % lv)
		var states := {}
		var secs := 0.0
		while secs < BottleShot.INTRO + 2.5 and warm._state != "aim":
			warm._process(1.0 / 60.0)
			warm._gift._process(1.0 / 60.0)
			states[warm._state] = true
			secs += 1.0 / 60.0
		check(states.has("gift"), "L%d: the gift plays after the burst-in" % lv)
		eq(warm._state, "aim", "L%d: then aiming starts" % lv)
		check(secs <= BottleShot.INTRO + 1.5 + 0.1, "L%d: within the intro and 1.5 s (%.2f s)" % [lv, secs])
		check(warm._mode.visible, "L%d: the weapon is in the hand" % lv)
		_drop(parts)
