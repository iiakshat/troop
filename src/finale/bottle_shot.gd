class_name BottleShot
extends Node3D
## End-of-level Bottle Shot, played inside the gang's stash (FinaleStash, one set per
## district). The district also picks the weapon, and the weapon decides the whole set-up:
## distance, camera, aiming, ammo and physics (BottleLogic has the rules, config/finale.json
## the numbers).
##   knife   (here) drag to aim at the bottles, release to throw. Each throw is a little film:
##           a side-on tracking shot beside the spinning knife in slow motion, a cut to a
##           close-up ~0.15 s before contact, the bottle bursting into glass and drink, the
##           knife buried in the planks (a miss thunks into the wood and the camera holds on it).
##   pistol, bow, stars, sniper: FinaleWeapon subclasses (weapon_*.gd) drive input, camera and
##           projectiles; they call break_bottle / show_miss / shot_over here.
## The HUD (FinaleHud) shows bottles left, ammo, the combo and the multiplier.

signal done(result: Dictionary)

const SLOW := 0.2               # time scale while a knife flies
const SLOW_IN := 0.12           # real seconds to ease into the slow motion
const CUT_LEAD := 0.15          # real seconds before contact: cut to the close-up
const HIT_STOP := 0.045         # real seconds the frame freezes on contact
const HOLD_HIT := 0.85          # real seconds on the close-up after a bottle breaks
const HOLD_MISS := 0.3          # real seconds on the stuck knife after a miss
const ARC := 0.25               # metres the knife rises mid-flight
const SPIN_PER_S := 4.2         # knife turns per second of (game) flight
const NORMAL_VIEW := Vector3(0.9, 2.25, 1.2)  # behind and above the hero, clear of his head
const AIM_FOV := 34.0           # telephoto: the bottle wall fills the screen
const TRACK_FOV := 52.0
const CLOSE_FOV := 40.0
const NEAR := 0.04              # close-ups need a near clip plane right by the lens
const TRACK_SIDE := 0.3        # tracking camera: metres beside the flight line
const TRACK_BACK := 0.45        # ... and behind the knife
const TRACK_LEAD := 0.15        # it looks this far ahead of the knife
const CLOSE_DIST := 1.3         # close-up distance from the bottle
const CLOSE_DOLLY := 0.5       # extra pull-back while the glass flies
const MISS_DIST := 0.75         # close-up distance from a knife stuck in the wood
const BOTTLE_SCALE := 1.3
const STAGE_KNIFE_IN := 0.04    # metres a stuck knife's tip sinks into the planks
const INTRO := 0.75             # real seconds of the burst-in camera move

## LevelView's level-load prewarm (spec v2 §3): the finale is built while the level loads
## (`dormant`: stash, bottles, HUD, weapon), drawn out of sight for the first frames with one of
## each thing a shot makes later (a shattered bottle, the knife, tracers, casings...) so every
## pipeline compiles then, and rests hidden (`rest`) until the squad reaches the stash, when
## `wake` moves it in front of the hero and plays it. The burst into the stash builds nothing.
var dormant := false
var _built: Array = []          # the set as built (stash, rack, bottles, plates): `_place` moves it
var _built_hero := Vector3.ZERO # the hero the set was built around
var _ghost: FinaleHud = null    # a see-through HUD drawn while warming (canvas pipelines, glyphs)
var _warm_root: Node3D = null   # the warm-only extras; hidden after warming, kept so their
                                # materials' shaders stay compiled for the finale
var _took_camera := false       # the finale holds the street camera (given back when it ends)
var _lens_warm := false         # the street camera carries an unseen depth of field while warming
const WARM_FOCUS := 1000.0      # warm depth of field: focused past everything the street shows
const WARM_BLUR := 0.001        # ... and far too faint to see; only its pipelines matter

var logic: BottleLogic
var world: World
var fx: Fx
var font: Font
var troops := 0
var station_bonus := 0.0
var hero_pos := Vector3.ZERO
var on_throw: Callable        # LevelView plays the hero's throw animation
var hud: FinaleHud
var theme := "bar"

var _mode: FinaleWeapon = null  # null = knives (handled here)
var _floor_y := 0.0           # stand floor height (the sniper shoots from roof to roof)
var _bscale := BOTTLE_SCALE   # bottle scale (shrinks with the level's difficulty row)
var _wall_z := -7.5
var _wall_front := -7.475
var _ft := 0.0                # finale clock (game time; slows down in slow motion)
var _scale := 1.0             # current time scale
var _bottles: Array = []      # Node3D per bottle (decoys are clay jugs)
var _glows: Array = []        # caustic blob (and halo) per bottle
var _plates: Array = []       # steel plates (stars)
var _rack: Node3D
var _reticle: MeshInstance3D
var _aim := Vector2(0, 1.8)
var _aiming := false
var _knife: Node3D = null
var _knife_from := Vector3.ZERO
var _knife_to := Vector3.ZERO   # aimed point (BottleLogic's line)
var _knife_end := Vector3.ZERO  # where the knife's balance point stops (tip in the wood)
var _knife_dir := Vector3.FORWARD
var _knife_t0 := 0.0
var _knife_t1 := 0.0
var _knife_hit := -1
var _knife_streak := 0
var _t_contact := 0.0
var _k_contact := 1.0
var _contacted := false
var _turns := 2.0
var _real := 0.0              # real seconds since the throw
var _hitstop := 0.0
var _cam := Transform3D()
var _cam_mode := "aim"        # aim | track | close
var _close_target := Vector3.ZERO
var _close_t := 0.0           # real seconds since the cut
var _side := 1.0              # which side the close-up camera sits on
var _roll := 0.0
var _track_h := 0.05
var _fov := AIM_FOV
var _aim_fov := AIM_FOV
var _aim_focus := 6.0
var _focus := 6.0
var _blur := 0.1
var _state := "intro"         # intro | aim | flying | impact | tally | finished
var _wait := 0.0
var _intro_t := 0.0
var _intro_from := Transform3D()
var _intro_fov := 50.0
var _shown_bottles := 0       # bottles left as the HUD shows them (drops on the visible break)
var _throw_n := 0
var _shatters: Array = []
var _stuck: Array = []
var _quiver: Array = []       # {node, tip, basis, t, amp}
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_mat: StandardMaterial3D
var _trail_pts: Array = []    # {p, t}
var _trail_color := Color(0.85, 0.95, 1.0)
var _blade_color := Color("e6eaf0")
var _cord_color := Color(0.55, 0.1, 0.12)
var _later: Array = []        # {t, id, vol}: sounds scheduled in real time
var _dust_mat: ShaderMaterial


func setup(w: World, f: Fx, fnt: Font, level_id: int, troop_count: int, hero: Vector3, bonus: float) -> BottleShot:
	world = w
	fx = f
	font = fnt
	troops = troop_count
	hero_pos = hero
	station_bonus = bonus
	# v2 Armory: the Bottle Shot weapon's handling steps (magazine, kick, draw, sway...).
	var cfg: Dictionary = Armory.apply_finale(Config.load_json("res://config/finale.json"), Game.save)
	logic = BottleLogic.new(cfg, level_id)
	theme = String((cfg.get("district_stash", {}) as Dictionary).get(str(logic.district), FinaleStash.theme_of(logic.district)))
	_floor_y = float(logic.wcfg.get("elevation", 0.0))
	_bscale = BOTTLE_SCALE * logic.size
	# Bottles stand on the plane z = hero - distance; the back wall is 0.25 m behind them.
	_wall_z = hero.z - logic.distance - 0.25
	_wall_front = _wall_z + 0.025
	return self


func _ready() -> void:
	_build()
	if dormant:
		process_mode = Node.PROCESS_MODE_DISABLED   # no process, no input until `wake`
		_warm_up()
		return
	_begin()


## Everything the finale shows, before it starts: the stash and bottles, the HUD, the weapon.
func _build() -> void:
	var ks: Dictionary = Game.knife_skin()
	_blade_color = Color(String(ks.get("blade", "e6eaf0")))
	if String(ks.get("trail", "")) != "":
		_trail_color = Color(String(ks["trail"]))
		_cord_color = _trail_color.darkened(0.35)
	_built_hero = hero_pos
	var n0 := get_child_count()
	_build_wall()
	for c in get_children().slice(n0):
		if c is Node3D:
			_built.append(c)
	_build_trail()
	hud = FinaleHud.new().setup(logic)
	hud.layer = 2
	add_child(hud)
	match logic.weapon:
		"pistol": _mode = WeaponPistol.new()
		"bow": _mode = WeaponBow.new()
		"stars": _mode = WeaponStars.new()
		"sniper": _mode = WeaponSniper.new()
	if _mode:
		_mode.setup(self)
		add_child(_mode)


## Burst in: the squad kicks the door; the camera rushes from the street into the stash.
func _begin() -> void:
	_aim_lens()
	_intro_from = world.camera.transform
	_cam = _intro_from
	_intro_fov = world.camera.fov
	_fov = _intro_fov
	_focus = -1.0
	_shown_bottles = logic.remaining()
	hud.flash(0.85)
	world.shake(0.5)
	Sfx.play("punch", 2.0, 0.8)
	Sfx.play("boom", -6.0, 1.3)
	_later.append({"t": 0.25, "id": "swoosh", "vol": 0.0})
	_took_camera = true
	_apply_camera()


## True when `s` is a resting finale built for `level_id` that can play now.
static func reusable(s, level_id: int) -> bool:
	if not is_instance_valid(s) or not (s is BottleShot):
		return false
	var b := s as BottleShot
	return not b.is_queued_for_deletion() and b.dormant and b.logic != null and b.logic.level == level_id


## The squad bursts into the stash: the finale built at load moves in front of `hero` (a dormant
## finale only) and plays, exactly as a fresh one built here would.
func wake(troop_count: int, hero: Vector3, bonus: float) -> void:
	troops = troop_count
	station_bonus = bonus
	_end_warm()
	dormant = false
	position = Vector3.ZERO
	_place(hero)
	if _mode:
		_mode.position = Vector3.ZERO
	visible = true
	_show_layers(true)
	process_mode = Node.PROCESS_MODE_INHERIT
	_begin()


## After the warm frames: hidden and still until `wake` (the HUD and weapon overlays too).
func rest() -> void:
	if not dormant:
		return
	_end_warm()
	visible = false
	_show_layers(false)


## Moves the set built around `_built_hero` to stand around `hero`. The set is the same around
## any hero (everything is placed from hero_pos, _wall_z and _floor_y), so this is a pure shift
## of its pieces; bottles and plates are placed from hero_pos every frame anyway.
func _place(hero: Vector3) -> void:
	var d := hero - _built_hero
	hero_pos = hero
	_wall_z = hero.z - logic.distance - 0.25
	_wall_front = _wall_z + 0.025
	_built_hero = hero
	if d == Vector3.ZERO:
		return
	for n in _built:
		# The aim ring is placed every aiming frame; bottles and plates by _move_bottles below.
		if is_instance_valid(n) and n != _reticle and not (n as Node3D).top_level:
			(n as Node3D).position += d
	if _dust_mat:
		# The motes test themselves against the two spotlights in world space.
		for k in ["spot_a", "spot_b"]:
			_dust_mat.set_shader_parameter(k, (_dust_mat.get_shader_parameter(k) as Vector3) + d)
	_move_bottles()


## The HUD and the weapon's own overlays (scope, swipe line) on or off.
func _show_layers(on: bool) -> void:
	var layers: Array = [hud] if hud != null else []
	if _mode:
		layers.append_array(_mode.find_children("*", "CanvasLayer", true, false))
	for l in layers:
		(l as CanvasLayer).visible = on


## Dormant, the first frames: everything stands where LevelView put this node (out of sight),
## the HUD stays hidden behind a see-through copy, and one of each thing a shot makes later
## stands in front of the wall, so their pipelines and glyphs are ready before the stash.
func _warm_up() -> void:
	_show_layers(false)
	var at := Vector3(hero_pos.x, 1.5, _wall_z + 2.0)   # in front of the wall, on LevelView's view ray
	_ghost = FinaleHud.new().setup(logic)
	_ghost.layer = 2
	_ghost.ghosted = true
	add_child(_ghost)
	_warm_root = Node3D.new()
	_warm_root.name = "Warm"
	add_child(_warm_root)
	# A bottle as a knife leaves it: the jagged stump, the flying neck, shards, spray and stain.
	var b := BottleMesh.make(false, 0.31, 0)
	b.position = at + Vector3(0.6, 0, 0)
	b.scale = Vector3.ONE * _bscale
	_warm_root.add_child(b)
	var neck := BottleMesh.break_apart(b, true, true)
	var sh := Shatter.new().setup(b.position, _bscale, Vector3.FORWARD, BottleMesh.glass_color(b),
		BottleMesh.drink_color(b), false, b.position.z - 0.3, {}, neck, BottleMesh.height(0))
	sh.top_level = false   # placed in this node's frame (it is out of sight down here)
	_warm_root.add_child(sh)
	sh.tick(0.02, at + Vector3(0, 0.5, 3.0))
	# The knife's aim and close-ups blur the background (depth of field): those post-process
	# pipelines compile now too, on an invisible lens (it was a 30-50 ms frame as the burst-in
	# camera settled).
	if world != null and world.camera != null:
		world.set_lens(world.camera.fov, WARM_FOCUS, -1.0, WARM_BLUR)
		_lens_warm = true
	var at_world := global_transform * at if is_inside_tree() else at
	if _mode == null:
		# Knives: the thrown knife, a scrap of its air streak (drawn in world space) and the aim
		# ring (placed every aiming frame once playing).
		var knife := FinaleKnife.make(_blade_color, _cord_color)
		knife.position = at + Vector3(-0.6, 0, 0)
		_warm_root.add_child(knife)
		_reticle.position = at + Vector3(0, 0.6, 0)
		_reticle.visible = true
		_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _trail_mat)
		for p in [Vector3(-0.3, 0, 0), Vector3(0.3, 0, 0), Vector3(-0.3, 0.05, 0), Vector3(0.3, 0.05, 0)]:
			_trail_mesh.surface_set_color(Color(_trail_color, 0.4))
			_trail_mesh.surface_add_vertex(at_world + (p as Vector3))
		_trail_mesh.surface_end()
	elif _mode.is_node_ready():
		# The weapon in hand stands in front of the wall too (its tick places it once playing),
		# with its fill light, and one of each thing it fires or throws off.
		_mode.position = at
		_mode.place_fill(Transform3D(Basis(), at_world))
		_mode.warm(true)
		var k := 0
		for part in _mode.warm_parts():
			var n := part as Node3D
			n.top_level = false
			n.position = at + Vector3(-1.2 + 0.4 * k, 0.4, 0)
			_warm_root.add_child(n)
			k += 1


## The warm frames are over: the see-through HUD goes, the extras hide, the trail is cleared.
func _end_warm() -> void:
	if _ghost:
		_ghost.visible = false
		_ghost.queue_free()
		_ghost = null
	if _warm_root:
		_warm_root.visible = false
	if _trail_mesh:
		_trail_mesh.clear_surfaces()
	if _reticle:
		_reticle.visible = false
	if _mode and _mode.is_node_ready():
		_mode.warm(false)
	if _lens_warm:
		_lens_warm = false
		if is_instance_valid(world):
			world.set_lens(-1.0)


## Leaving mid-finale (restart or home from the pause menu) gives the street its camera and
## lens back (also a level left while its finale is still warming).
func _notification(what: int) -> void:
	if what != NOTIFICATION_EXIT_TREE and what != NOTIFICATION_PREDELETE:
		return
	if (_took_camera or _lens_warm) and is_instance_valid(world):
		if _took_camera:
			world.set_camera_override(null)
		world.set_lens(-1.0)
	_took_camera = false
	_lens_warm = false


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if _mode:
		if _state == "aim" or (_mode.input_while_busy and _state in ["intro", "flying", "impact"]):
			_mode.handle_input(event)
		return
	if _state != "aim":
		return
	var pos := Vector2.ZERO
	var pressed := false
	var released := false
	if event is InputEventScreenTouch:
		pos = (event as InputEventScreenTouch).position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenDrag:
		pos = (event as InputEventScreenDrag).position
		pressed = true
	else:
		return
	if pressed:
		_aiming = true
		_aim = _screen_to_wall(pos)
	elif released and _aiming:
		_aiming = false
		_aim = _screen_to_wall(pos)
		_throw_knife(_aim)


func _screen_to_wall(p: Vector2) -> Vector2:
	var cam := world.camera
	var from := cam.project_ray_origin(p)
	var dir := cam.project_ray_normal(p)
	if absf(dir.z) < 0.001:
		return _aim
	var t := (_wall_z - from.z) / dir.z
	var hit := from + dir * t
	return Vector2(clampf(hit.x - hero_pos.x, -2.4, 2.4), clampf(hit.y - _floor_y, 0.6, 3.6))


## Autoplay (and tests): a perfect shot at the next target bottle with whatever weapon this
## district uses. `aim` is ignored except as a fallback for knives.
func throw_at(aim: Vector2) -> void:
	if _state != "aim":
		return
	if _mode:
		_mode.auto_fire()
		return
	var i := logic.next_target()
	if i >= 0:
		aim = logic.position(i, _ft + logic.flight_time(logic.distance - 0.15))
	_throw_knife(aim)


## Throws a knife at a wall point (x relative to the hero, y = height).
func _throw_knife(aim: Vector2) -> void:
	if _state != "aim" or logic.shots_left <= 0:
		return
	_knife_from = hero_pos + Vector3(0.25, 1.45, -0.4)
	_knife_to = Vector3(hero_pos.x + aim.x, aim.y, _wall_z + 0.12)
	var flight := logic.flight_time(_knife_from.distance_to(_knife_to))
	_knife_t0 = _ft
	_knife_t1 = _ft + flight
	_knife_hit = logic.throw(aim, _knife_t1)
	_knife_streak = logic.streak
	_knife_dir = (_knife_to - _knife_from).normalized()
	# The tip ends buried in the planks on the same line; the balance point sits TIP behind.
	var tip := _knife_from + _knife_dir * ((_wall_front - STAGE_KNIFE_IN - _knife_from.z) / _knife_dir.z)
	_knife_end = tip - _knife_dir * FinaleKnife.TIP
	_turns = maxf(1.0, round(flight * SPIN_PER_S))
	_t_contact = _knife_t1
	_k_contact = 1.0
	if _knife_hit >= 0:
		# Contact = the tip reaching the front of the bottle (it carries on into the wall).
		var front_z := _wall_z + 0.25 + _bottle_radius(_knife_hit)
		var centre_z := front_z - _knife_dir.z * FinaleKnife.TIP
		var k := clampf((_knife_from.z - centre_z) / maxf(_knife_from.z - _knife_end.z, 0.01), 0.0, 1.0)
		_t_contact = _knife_t0 + k * flight
		_k_contact = maxf(k, 0.05)
	_contacted = false
	_knife = FinaleKnife.make(_blade_color, _cord_color)
	add_child(_knife)
	_knife.position = _knife_from
	_knife.basis = Basis.looking_at(_knife_dir, Vector3.UP)
	_trail_pts.clear()
	_throw_n += 1
	_side = 1.0 if _throw_n % 2 == 1 else -1.0
	_roll = 0.09 * _side
	_track_h = 0.06 if _throw_n % 2 == 1 else -0.04
	_state = "flying"
	_cam_mode = "track"
	_real = 0.0
	_scale = 1.0
	_reticle.visible = false
	_cam = _track_view(_knife_from)
	_fov = TRACK_FOV
	_blur = 0.05
	hud.refresh(_shown_bottles)
	Sfx.play("knife", 2.0)
	Sfx.play("swoosh", -4.0, 0.55)
	if on_throw.is_valid():
		on_throw.call()


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if _state == "finished":
		return
	_tick_sounds(delta)
	var d := delta * _scale
	if _hitstop > 0.0:
		_hitstop -= delta
		d = 0.0
	_ft += d
	_move_bottles()
	var cam_pos := world.camera.global_position
	for s in _shatters:
		(s as Shatter).tick(d, cam_pos)
	_tick_quiver(delta)
	if _dust_mat:
		_dust_mat.set_shader_parameter("t", _ft)
	match _state:
		"intro":
			if _mode:
				_mode.tick(delta, d)   # the weapon is already in hand at the end of the rush
			_intro_t += delta
			var k := smoothstep(0.0, INTRO, _intro_t)
			_cam = _intro_from.interpolate_with(_rest_view(), k)
			_fov = lerpf(_intro_fov, _rest_fov(), k)
			if _intro_t >= INTRO:
				_state = "aim"
				_cam_mode = "aim"
				_focus = _aim_focus
				if _mode:
					_mode.begin()
		"aim", "flying", "impact":
			if _mode:
				_mode.tick(delta, d)
			else:
				_knife_frame(delta)
		"tally":
			_wait -= delta
			var k := minf(delta * 3.0, 1.0)
			if _mode:
				_mode.tick(delta, d)
			else:
				_cam = _cam.interpolate_with(_aim_view(), k)
				_fov = lerpf(_fov, _aim_fov, k)
				_focus = lerpf(_focus, _aim_focus, k)
			if _wait <= 0.0:
				_state = "finished"
				_took_camera = false
				world.set_camera_override(null)
				world.set_lens(-1.0)
				hud.queue_free()
				if _mode:
					_mode.finish()
				if theme == "rooftop":
					visible = false   # our roof would cover the squad on the street
				done.emit({"broken": logic.broken_count(), "gold": logic.broken_count(true),
					"mult": logic.multiplier(), "coins": logic.coins(troops, station_bonus),
					"combo": logic.best_streak})
				return  # the camera is handed back; don't take it again below
	_apply_camera()


func _knife_frame(delta: float) -> void:
	match _state:
		"aim":
			_reticle.visible = true
			_reticle.position = Vector3(hero_pos.x + _aim.x, _floor_y + _aim.y, _wall_z + 0.3)
			_reticle.rotation.z += delta * 2.0
			var k := minf(delta * 6.0, 1.0)
			_cam = _cam.interpolate_with(_aim_view(), k)
			_fov = lerpf(_fov, _aim_fov, k)
			_focus = lerpf(_focus, _aim_focus, k)
			_blur = lerpf(_blur, 0.1, k)
			_roll = 0.0
		"flying":
			_fly(delta)
		"impact":
			_wait -= delta
			_close_t += delta
			_cam = _close_view()
			if _wait <= 0.0:
				shot_over()


## A shot (and its film) is over: aim again, or tally when nothing is left to do.
func shot_over() -> void:
	if not logic.finished():
		_state = "aim"
		_cam_mode = "aim"
		_aim_lens()
	else:
		_state = "tally"
		_cam_mode = "aim"
		_wait = 1.0
		Sfx.play("win")


## Camera and lens the finale rests on between shots.
func _rest_view() -> Transform3D:
	return _mode.rest_view() if _mode else _aim_view()


func _rest_fov() -> float:
	return _mode.rest_fov() if _mode else _aim_fov

func _fly(delta: float) -> void:
	_real += delta
	if not _contacted:
		_scale = lerpf(1.0, SLOW, smoothstep(0.0, SLOW_IN, _real))
	var k := clampf((_ft - _knife_t0) / maxf(_knife_t1 - _knife_t0, 0.001), 0.0, 1.0)
	var p := _knife_from.lerp(_knife_end, k) + Vector3.UP * sin(k * PI) * ARC
	_knife.position = p
	# End over end, tip first again exactly when it reaches the bottle (or the wall).
	var spin := (1.0 - minf(k / _k_contact, 1.0)) * _turns * TAU
	_knife.basis = Basis.looking_at(_knife_dir, Vector3.UP) * Basis(Vector3.RIGHT, spin)
	_push_trail(p)
	if not _contacted:
		var left_real := (_t_contact - _ft) / maxf(_scale, 0.05)
		if _cam_mode == "track" and left_real <= CUT_LEAD:
			_cut_to_close()
		if _ft >= _t_contact:
			_contact()
	match _cam_mode:
		"track":
			_cam = _track_view(p)
			_focus = (_cam.origin.distance_to(p)) + 1.2
		"close":
			_close_t += delta
			_cam = _close_view()
	if k >= 1.0:
		_stick()


func _cut_to_close() -> void:
	_cam_mode = "close"
	_close_t = 0.0
	if _knife_hit >= 0:
		_close_target = _bottle_center(_knife_hit, _t_contact)
	else:
		_close_target = _knife_end + _knife_dir * 0.03   # the middle of the stuck knife
	_fov = CLOSE_FOV
	_blur = 0.06
	_roll = 0.0
	_cam = _close_view()
	_focus = CLOSE_DIST + 0.6


func _contact() -> void:
	_contacted = true
	_scale = 1.0
	if _knife_hit < 0:
		return
	_close_target = _bottle_center(_knife_hit, _ft)
	break_bottle(_knife_hit, _knife_dir, _knife_streak)


## Bottle (or decoy jug) `i` bursts, hit along `dir`; `streak` = hits in a row after this one
## (0 for a decoy), for the combo display. Weapons call this when their projectile arrives.
func break_bottle(i: int, dir: Vector3, streak: int, loud := true) -> void:
	var b: Node3D = _bottles[i]
	if not b.visible:
		return
	var gold := logic.is_gold(i)
	var decoy := logic.is_decoy(i)
	var motion := String(logic.layout.get("motion", "static"))
	var shelf := {}
	if motion == "static":
		shelf = {"y": b.global_position.y, "x0": hero_pos.x - 2.5, "x1": hero_pos.x + 2.5,
			"z0": _wall_z - 0.03, "z1": _wall_z + 0.47}
	var neck: Node3D = null
	if decoy:
		for c in b.get_children():
			(c as Node3D).visible = false
	elif motion == "swing":
		# Hanging bottles keep their neck on the string; it swings on alone.
		neck = BottleMesh.break_apart(b, false, true)
		b.add_child(neck)
		neck.position.y = float(neck.get_meta("pivot", 0.4))
		neck = null
	else:
		neck = BottleMesh.break_apart(b, true, true)
	for g in _glows[i]:
		(g as Node3D).visible = false
	var shape := int(b.get_meta("shape", 0))
	var sh := Shatter.new().setup(b.global_position, _bscale, dir, BottleMesh.glass_color(b),
		BottleMesh.drink_color(b), gold, _wall_front, shelf, neck, BottleMesh.height(shape))
	add_child(sh)
	_shatters.append(sh)
	_hitstop = HIT_STOP
	if loud:
		world.shake(0.22 if _mode == null else 0.0)
	Sfx.play("glass_break", 2.0 if loud else -2.0, 0.8 if decoy else 1.0)
	_later.append({"t": 0.3, "id": "glass_tinkle", "vol": -3.0})
	Game.vibrate(60)
	if decoy:
		# A clay jug: it breaks, but it is the gang's trap; the combo is gone.
		Sfx.play("blocked", -2.0)
		hud.flash(0.25, Color(1.0, 0.3, 0.2))
		hud.set_combo(0, 1.0)
		return
	_shown_bottles = maxi(_shown_bottles - 1, 0)
	hud.set_bottles(_shown_bottles)
	hud.flash(0.32 if gold else 0.22)
	Sfx.play("coin", -4.0, 1.0 + 0.1 * mini(streak, 6))
	if gold:
		Game.vibrate(120)
	hud.set_combo(streak, logic.combo_for(streak))
	hud.set_multiplier(logic.multiplier(), gold)


## A shot that broke nothing: the combo is gone.
func show_miss() -> void:
	hud.set_combo(0, 1.0)


func _stick() -> void:
	_knife.position = _knife_end
	var base := Basis.looking_at(_knife_dir, Vector3.UP)
	var tilt := 0.0 if _knife_hit >= 0 else randf_range(-0.12, 0.12)
	base = base * Basis(Vector3.UP, tilt)
	_knife.basis = base
	var tip := _knife_end + _knife_dir * FinaleKnife.TIP
	_quiver.append({"node": _knife, "tip": tip, "basis": base, "t": 0.0, "amp": 0.16 if _knife_hit < 0 else 0.09})
	_stuck.append(_knife)
	if _knife_hit >= 0:
		Sfx.play("thunk", -8.0)
		fx.burst(tip + Vector3(0, 0, 0.02), Color(0.55, 0.38, 0.22), 4, 1.6, 0.012, 0.3)
	else:
		show_miss()
		Sfx.play("thunk", 2.0)
		fx.burst(tip + Vector3(0, 0, 0.02), Color(0.55, 0.38, 0.22), 9, 2.0, 0.015, 0.35)
		world.shake(0.12)
		if _cam_mode != "close":
			_cut_to_close()
	_knife = null
	_trail_pts.clear()
	_draw_trail()
	_scale = 1.0
	_state = "impact"
	_wait = HOLD_HIT if _knife_hit >= 0 else HOLD_MISS


## Stuck knives quiver for a moment, pivoting on the buried tip.
func _tick_quiver(delta: float) -> void:
	var i := 0
	while i < _quiver.size():
		var q: Dictionary = _quiver[i]
		q["t"] = float(q["t"]) + delta
		var t := float(q["t"])
		var node: Node3D = q["node"]
		if t > 0.6 or not is_instance_valid(node):
			if is_instance_valid(node):
				node.basis = q["basis"]
				node.position = (q["tip"] as Vector3) - node.basis * Vector3(0, 0, -FinaleKnife.TIP)
			_quiver.remove_at(i)
			continue
		var a := float(q["amp"]) * exp(-t * 9.0) * sin(t * 62.0)
		node.basis = (q["basis"] as Basis) * Basis(Vector3.RIGHT, a)
		node.position = (q["tip"] as Vector3) - node.basis * Vector3(0, 0, -FinaleKnife.TIP)
		i += 1


func _tick_sounds(delta: float) -> void:
	var i := 0
	while i < _later.size():
		var s: Dictionary = _later[i]
		s["t"] = float(s["t"]) - delta
		if float(s["t"]) <= 0.0:
			Sfx.play(String(s["id"]), float(s["vol"]))
			_later.remove_at(i)
			continue
		i += 1


# ---------------------------------------------------------------- cameras

func _apply_camera() -> void:
	var xf := _cam
	if _roll != 0.0:
		xf.basis = xf.basis * Basis(Vector3(0, 0, 1), _roll)
	world.set_camera_override(xf)
	world.set_lens(_fov, _focus, NEAR, _blur)


## Telephoto lens framing this level's bottles (plus their motion) edge to edge.
func _aim_lens() -> void:
	_aim_fov = aim_fov_at(logic, hero_pos, _wall_z)
	_aim_focus = _aim_view().origin.distance_to(Vector3(hero_pos.x, 1.8, _wall_z)) + 0.4


func _aim_view() -> Transform3D:
	return aim_view_at(hero_pos, _wall_z)


## The knife and star aim view for a hero at `hero` and the back wall at `wall_z`.
static func aim_view_at(hero: Vector3, wall_z: float) -> Transform3D:
	var eye := hero + NORMAL_VIEW
	var look := Vector3(hero.x, 1.75, wall_z)
	return Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)


## The knife and star lens: frames the set (plus its motion) edge to edge, but never so tight
## that a bottle at either end of its motion leaves the frame (a wide boss set opens it up).
static func aim_fov_at(l: BottleLogic, hero: Vector3, wall_z: float) -> float:
	var extent := 0.0
	for b in l.layout["bottles"]:
		extent = maxf(extent, absf(float(b["x"])))
	var amp := float(l.layout.get("amp", 0.0))
	extent += amp + 0.55
	var view := aim_view_at(hero, wall_z)
	var d := view.origin.distance_to(Vector3(hero.x, 1.8, wall_z))
	var fov := clampf(rad_to_deg(2.0 * atan(extent / d)), 22.0, AIM_FOV)
	var inv := view.affine_inverse()
	var reach := amp + 0.16 * l.size + 0.03   # the motion plus half a bottle and a hair
	for b in l.layout["bottles"]:
		for side in [-1.0, 1.0]:
			var q := inv * Vector3(hero.x + float(b["x"]) + side * reach, float(b["y"]), wall_z + 0.25)
			fov = maxf(fov, rad_to_deg(2.0 * atan(absf(q.x) / maxf(-q.z, 0.1))))
	return fov


## The camera when aiming starts, in hero space (hero at the origin, the stand's floor at y = 0,
## -Z ahead), and its horizontal field of view: [Transform3D, fov]. Knives and stars use the
## telephoto aim view; pistol, bow and sniper (unscoped) look from the eye at the set's middle.
static func aim_camera(l: BottleLogic) -> Array:
	if l.weapon == "knife" or l.weapon == "stars":
		var wall_z := -l.distance - 0.25
		return [aim_view_at(Vector3.ZERO, wall_z), aim_fov_at(l, Vector3.ZERO, wall_z)]
	var r := FinaleWeapon.rest_aim(l)
	return [Transform3D(Basis.from_euler(Vector3(r.y, r.x, 0.0)), FinaleWeapon.eye_point(l.wcfg)),
		float(l.wcfg.get("fov", 34.0))]


## Beside and a little behind the knife, looking ahead of it so the knife sits big in the
## foreground and the bottle wall fills the background.
func _track_view(p: Vector3) -> Transform3D:
	var side := _knife_dir.cross(Vector3.UP).normalized()
	var eye := p + side * TRACK_SIDE - _knife_dir * TRACK_BACK + Vector3.UP * _track_h
	var look := p + _knife_dir * TRACK_LEAD
	return Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)


## Front three-quarter close-up of the target (bottle or wall spot); pulls back slowly
## after contact so the flying glass stays in frame.
func _close_view() -> Transform3D:
	if _knife_hit < 0:
		# A miss is filmed side-on to the knife, from the wall's middle side, so the whole
		# knife sticking out of the planks reads (never from inside the wall).
		var s := signf(hero_pos.x - _close_target.x)
		if absf(hero_pos.x - _close_target.x) < 0.3:
			s = _side
		var across := _knife_dir.cross(Vector3.UP).normalized()
		if across.x * s < 0.0:
			across = -across
		var e := _close_target + (across * 0.8 + Vector3(0, 0.25, 0.45)).normalized() * MISS_DIST
		e.z = maxf(e.z, _wall_front + 0.3)
		return Transform3D(Basis.looking_at(_close_target - e, Vector3.UP), e)
	var dolly := 0.0
	if _contacted:
		dolly = CLOSE_DOLLY * (1.0 - pow(1.0 - clampf(_close_t / HOLD_HIT, 0.0, 1.0), 2.0))
	var off := Vector3(-_side * 0.55, 0.14, 0.85).normalized() * (CLOSE_DIST + dolly)
	var target := _close_target
	if _knife_hit >= 0 and not _contacted:
		target = _bottle_center(_knife_hit, _ft)
	var eye := target + off
	return Transform3D(Basis.looking_at(target + Vector3(0, 0.06, 0) - eye, Vector3.UP), eye)


# ---------------------------------------------------------------- bottles

## Half a bottle's height: logic heights are bottle centres, the meshes stand on their base.
func _half_h() -> float:
	return 0.4 * _bscale / BOTTLE_SCALE


func _bottle_world(i: int, t: float) -> Vector3:
	var p := logic.position(i, t)
	return Vector3(hero_pos.x + p.x, _floor_y + p.y - _half_h(), _wall_z + 0.25)


func _bottle_center(i: int, t: float) -> Vector3:
	var b: Node3D = _bottles[i]
	var h := BottleMesh.height(int(b.get_meta("shape", 0))) * _bscale
	return _bottle_world(i, t) + Vector3(0, h * 0.5, 0)


func _bottle_radius(i: int) -> float:
	var b: Node3D = _bottles[i]
	var r := 0.0
	for p in BottleMesh.SHAPES[int(b.get_meta("shape", 0))]["profile"]:
		r = maxf(r, (p as Vector2).x)
	return r * _bscale


## World point of a hero-space point (BottleLogic's frame: hero at the origin, floor y = 0).
## True while the camera sits in the hero's head (pistol sights, bow, scope): the hero's own
## body must not be drawn then, or his shoulders and arms fill the screen as big slabs.
func camera_in_head() -> bool:
	var e := to_world(Vector3(0.0, float(logic.wcfg.get("eye_y", 1.6)), -0.35))
	return _cam.origin.distance_to(e) < 0.6


func to_world(p: Vector3) -> Vector3:
	return Vector3(hero_pos.x + p.x, _floor_y + p.y, hero_pos.z + p.z)


func to_hero(p: Vector3) -> Vector3:
	return Vector3(p.x - hero_pos.x, p.y - _floor_y, p.z - hero_pos.z)


func _move_bottles() -> void:
	var motion := String(logic.layout.get("motion", "static"))
	for i in _bottles.size():
		var b: Node3D = _bottles[i]
		b.position = _bottle_world(i, _ft)
		if motion == "swing":
			var p := logic.position(i, _ft)
			var base: Dictionary = logic.layout["bottles"][i]
			b.rotation.z = (p.x - float(base["x"])) * -0.5
	if motion == "slide" or motion == "drive":
		_rack.position.x = hero_pos.x + logic.position(0, _ft).x - float(logic.layout["bottles"][0]["x"])
	for k in _plates.size():
		var pp := logic.plate_position(k, _ft)
		(_plates[k] as Node3D).position = Vector3(hero_pos.x + pp.x, _floor_y + pp.y, _wall_z + 0.22)


# ---------------------------------------------------------------- build

func _build_wall() -> void:
	_build_stage()
	_build_bottles()


## The stash set and the rack (shelves, or the bar the bottles swing from). Needs no world, so
## the tests build it to check no part of it hides a bottle.
func _build_stage() -> void:
	var motion := String(logic.layout.get("motion", "static"))
	FinaleStash.build(self, theme)
	_rack = Node3D.new()
	add_child(_rack)
	_rack.position = Vector3(hero_pos.x, 0, 0)
	var heights := {}
	var extent := 0.0
	for b in logic.layout["bottles"]:
		heights[snappedf(float(b["y"]) - _half_h(), 0.01)] = true  # shelf top = the bottle base
		extent = maxf(extent, absf(float(b["x"])))
	if motion == "swing":
		var bar := World._box(Vector3(extent * 2.0 + 1.4, 0.12, 0.12), Color("2b2b2b"))
		var top := 0.0
		for h in heights:
			top = maxf(top, float(h))
		bar.position = Vector3(hero_pos.x, _floor_y + top + 1.45, _wall_z + 0.25)
		add_child(bar)
	else:
		var width := extent * 2.0 + (1.0 if motion == "static" else 0.7) * _bscale
		if theme == "factory" and motion != "static":
			width = extent * 2.0 + 1.4
		var tops: Array = heights.keys()
		tops.sort()
		for k in tops.size():
			var h := float(tops[k])
			var shelf := FinaleStash.shelf(theme, width, 0.5, h - float(tops[k - 1]) if k > 0 else 0.0)
			shelf.position = Vector3(0, _floor_y + float(h), _wall_z + 0.22)
			_rack.add_child(shelf)
		if theme == "carnival":
			# A plain dark board behind the shelves: red/white bottles vanish on red/white stripes.
			var top := 0.0
			var low := INF
			for h in heights:
				top = maxf(top, float(h))
				low = minf(low, float(h))
			var bh := top - low + 1.25 * _bscale / BOTTLE_SCALE + 0.3
			var board := World._box(Vector3(width + 0.5, bh, 0.06), Color("1d1a2e"))
			board.position = Vector3(0, _floor_y + low - 0.3 + bh * 0.5, _wall_z + 0.05)
			_rack.add_child(board)


## No stash sign may stand between an eye (the weapon's and the aim camera's) and any bottle,
## over one whole cycle of the set's motion. Works before the bottles exist (the tests).
func _clear_sightlines() -> void:
	var period := TAU / maxf(float(logic.layout.get("speed", 1.0)), 0.1)
	var targets: Array = []
	for i in logic.count():
		for k in 16:
			var t := period * k / 16.0
			targets.append(_bottle_center(i, t) if i < _bottles.size() else _bottle_world(i, t) + Vector3(0, _half_h(), 0))
	var moved := 0
	for eye in [FinaleWeapon.eye_point(logic.wcfg), (aim_camera(logic)[0] as Transform3D).origin]:
		moved += FinaleStash.clear_sightlines(self, to_world(eye), targets, logic.hit_radius())
	if moved > 0:
		push_warning("Bottle Shot %s: %d stash sign(s) lifted out of the line of sight" % [theme, moved])


func _build_bottles() -> void:
	var motion := String(logic.layout.get("motion", "static"))
	var level_seed := int(logic.layout.get("seed", 0))
	for i in logic.count():
		var gold := logic.is_gold(i)
		var bottle: Node3D
		if logic.is_decoy(i):
			bottle = _jug()
		else:
			var hue := fmod(0.31 + i * 0.17, 1.0)
			bottle = BottleMesh.make(gold, hue, (i * 3 + level_seed + logic.count()) % 4)
		bottle.scale = Vector3.ONE * _bscale
		add_child(bottle)
		_bottles.append(bottle)
		var glows: Array = []
		if not logic.is_decoy(i):
			# Caustic: light through the drink pools as a coloured glow on the wall behind.
			var drink := BottleMesh.drink_color(bottle)
			var c := _glow_quad(Vector2(0.34, 0.5), drink.lerp(Color.WHITE, 0.3), 0.28, 0.0)
			c.position = Vector3(0.0, 0.2, -0.17)
			bottle.add_child(c)
			glows.append(c)
		if gold:
			var halo := _glow_quad(Vector2(0.95, 1.1), Color(1.0, 0.78, 0.3), 0.55, 0.35)
			halo.position = Vector3(0.0, 0.32, -0.18)
			bottle.add_child(halo)
			glows.append(halo)
		_glows.append(glows)
		if motion == "swing":
			var string := World._box(Vector3(0.012, 1.0, 0.012), Color("dddddd"))
			string.position = Vector3(0, 0.62 + 0.5, 0)
			bottle.add_child(string)
	# Steel plates for the throwing stars: angled so a star skims off along the row.
	var steel := WeaponModels.mat(Color("aeb6bf"), 0.9, 0.22)
	for p in logic.layout.get("plates", []):
		var plate := Node3D.new()
		add_child(plate)
		var w := float(logic.wcfg.get("plate_w", 0.4)) * logic.size
		var h := float(logic.wcfg.get("plate_h", 0.6)) * logic.size
		var face := WeaponModels.box(plate, Vector3(w, h, 0.03), Vector3.ZERO, steel)
		face.rotation.y = float(p["dir"]) * 0.5
		for s in [-1.0, 1.0]:
			WeaponModels.box(plate, Vector3(0.025, 0.025, 0.04), Vector3(s * w * 0.35, h * 0.38, 0.02), WeaponModels.mat(Color("3a3f46"), 0.8, 0.4))
		WeaponModels.box(plate, Vector3(0.06, 0.4, 0.06), Vector3(0, -h * 0.5 - 0.2, -0.05), WeaponModels.mat(Color("3a3f46"), 0.8, 0.4))
		_plates.append(plate)
	_move_bottles()
	_clear_sightlines()
	_reticle = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.13
	tm.outer_radius = 0.17
	_reticle.mesh = tm
	_reticle.rotation.x = PI * 0.5
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color("ff3b3b")
	rm.no_depth_test = true
	_reticle.material_override = rm
	_reticle.visible = false
	add_child(_reticle)


## Decoy: a clay jug (breaking it resets the combo). Same metas as a bottle for Shatter.
func _jug() -> Node3D:
	var root := Node3D.new()
	root.set_meta("shape", 0)
	root.set_meta("glass", Color("b0603a"))
	root.set_meta("drink", Color(0.45, 0.3, 0.2, 0.6))
	var clay := WeaponModels.mat(Color("b0603a"), 0.0, 0.85)
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.36
	body.mesh = sm
	body.material_override = clay
	body.position.y = 0.19
	root.add_child(body)
	var neck := WeaponModels.tube(root, 0.055, 0.14, Vector3(0, 0.4, 0), clay)
	neck.rotation.x = PI * 0.5
	var band := WeaponModels.tube(root, 0.152, 0.03, Vector3(0, 0.22, 0), WeaponModels.mat(Color("e9d7b0"), 0.0, 0.8))
	band.rotation.x = PI * 0.5
	var handle := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.045
	tm.outer_radius = 0.07
	handle.mesh = tm
	handle.material_override = clay
	handle.position = Vector3(0.14, 0.3, 0)
	handle.rotation.x = PI * 0.5
	root.add_child(handle)
	return root



func _glow_quad(size: Vector2, color: Color, strength: float, pulse: float) -> MeshInstance3D:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	q.mesh = qm
	var m := ShaderMaterial.new()
	m.shader = load("res://src/finale/glow.gdshader")
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("pulse", pulse)
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return q


## A faint visible beam from a spotlight to (just short of) the wall.
func _add_beam(from: Vector3, to: Vector3, angle_deg: float) -> void:
	var length := from.distance_to(to) - 0.15
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = tan(deg_to_rad(angle_deg)) * length * 0.85
	cm.height = length
	cm.radial_segments = 24
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	cone.mesh = cm
	var m := ShaderMaterial.new()
	m.shader = load("res://src/finale/light_cone.gdshader")
	m.set_shader_parameter("strength", 0.07)
	m.set_shader_parameter("height", length)
	cone.material_override = m
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cone)
	var dir := (to - from).normalized()
	# The cylinder runs along +Y: point its -Y end at the wall.
	var y := -dir
	var x := y.cross(Vector3.FORWARD).normalized()
	if x.length_squared() < 0.001:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	# In this node's frame, like the rest of the set (it is built out of sight at level load).
	cone.transform = Transform3D(Basis(x, y, z), from + dir * length * 0.5)


## Dust motes drifting through the two beams (only the ones inside a beam show).
func _add_dust(spots: Array, angle_deg: float) -> void:
	var n := 180
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	mm.mesh = qm
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in n:
		var p := Vector3(hero_pos.x + rng.randf_range(-2.7, 2.7), rng.randf_range(0.7, 4.3), _wall_z + rng.randf_range(0.3, 3.6))
		mm.set_instance_transform(i, Transform3D(Basis(), p))
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), 0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(hero_pos.x - 3.5, 0.0, _wall_z - 0.5), Vector3(7.0, 5.0, 5.0))
	_dust_mat = ShaderMaterial.new()
	_dust_mat.shader = load("res://src/finale/dust.gdshader")
	_dust_mat.set_shader_parameter("spot_a", spots[0]["pos"])
	_dust_mat.set_shader_parameter("dir_a", spots[0]["dir"])
	_dust_mat.set_shader_parameter("spot_b", spots[1]["pos"])
	_dust_mat.set_shader_parameter("dir_b", spots[1]["dir"])
	_dust_mat.set_shader_parameter("cos_angle", cos(deg_to_rad(angle_deg * 0.85)))
	mi.material_override = _dust_mat
	add_child(mi)


func _build_trail() -> void:
	_trail_mesh = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.mesh = _trail_mesh
	_trail.top_level = true
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(_trail)


## Air streak behind the flying knife: the last few positions (in finale time).
func _push_trail(p: Vector3) -> void:
	_trail_pts.append({"p": p, "t": _ft})
	while _trail_pts.size() > 2 and _ft - float(_trail_pts[0]["t"]) > 0.045:
		_trail_pts.pop_front()
	_draw_trail()


func _draw_trail() -> void:
	_trail_mesh.clear_surfaces()
	var n := _trail_pts.size()
	if n < 2:
		return
	var cam_pos := world.camera.global_position
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _trail_mat)
	for i in n:
		var p: Vector3 = _trail_pts[i]["p"]
		var a: Vector3 = _trail_pts[maxi(i - 1, 0)]["p"]
		var b: Vector3 = _trail_pts[mini(i + 1, n - 1)]["p"]
		var tangent := (b - a).normalized()
		var side := tangent.cross((cam_pos - p).normalized())
		if side.length_squared() < 0.000001:
			continue
		var f := float(i) / float(n - 1)
		side = side.normalized() * 0.018 * f
		var c := Color(_trail_color, 0.4 * f * f)
		_trail_mesh.surface_set_color(c)
		_trail_mesh.surface_add_vertex(p - side)
		_trail_mesh.surface_set_color(c)
		_trail_mesh.surface_add_vertex(p + side)
	_trail_mesh.surface_end()


## Kept for other screens that format multipliers this way.
static func _fmt(m: float) -> String:
	return FinaleHud.fmt(m)
