extends "res://tests/test_case.gd"

var cfg: Dictionary = Config.load_json("res://config/finale.json")


func _aim(b: BottleLogic, i: int) -> Vector2:
	return b.position(i, 0.0)


func test_level_one_is_knives_with_spare() -> void:
	var b := BottleLogic.new(cfg, 1)
	eq(b.weapon, "knife", "district 1 throws knives")
	eq(b.targets(), 4, "three bottles and the gold one")
	eq(b.knives_left, b.targets() + 2, "two spare knives on the first level")
	for i in b.knives_left:
		b.throw(Vector2(9, 9), 0.0)
	eq(b.knives_left, 0, "all used")
	eq(b.throw(_aim(b, 0), 0.0), -1, "no extra knife")
	check(b.finished(), "out of knives = done")


func test_weapon_per_district() -> void:
	var want := {1: "knife", 11: "pistol", 21: "bow", 31: "stars", 41: "sniper", 50: "sniper"}
	for lv in want:
		eq(BottleLogic.new(cfg, lv).weapon, want[lv], "level %d weapon" % lv)


func test_difficulty_grows_inside_a_district() -> void:
	var first := BottleLogic.new(cfg, 11)
	var late := BottleLogic.new(cfg, 18)   # L19 is a guest sniper (v2.1 §4.3)
	check(late.count() > first.count(), "more bottles late in the district")
	check(late.distance > first.distance, "farther away")
	check(late.size < first.size, "smaller")
	check(late.shots_left - late.targets() < first.shots_left - first.targets(), "fewer spare shots")
	var decoys := 0
	for i in late.count():
		if late.is_decoy(i):
			decoys += 1
	check(decoys > 0, "decoys late on")
	eq(String(late.layout["motion"]) != "static", true, "late bottles move")
	eq(late.targets(), late.count() - decoys, "decoys are not targets")


func test_direct_hit_breaks_and_misses_do_not() -> void:
	var b := BottleLogic.new(cfg, 1)
	eq(b.throw(_aim(b, 1), 0.0), 1, "aimed at bottle 1")
	eq(b.throw(_aim(b, 1), 0.0), -1, "already broken")
	eq(b.throw(Vector2(5, 5), 0.0), -1, "miss")
	eq(b.broken_count(), 1, "one broken")


func test_moving_bottles_are_hit_where_they_are_on_arrival() -> void:
	var b := BottleLogic.new(cfg, 4)  # sliding shelf
	eq(String(b.layout["motion"]), "slide", "level 4 slides")
	var t := 1.0
	check(b.position(0, 0.0).distance_to(b.position(0, t)) > 0.3, "the shelf moved")
	eq(b.hit_at(b.position(0, 0.0), t), -1, "aiming where it was misses")
	eq(b.hit_at(b.position(0, t), t), 0, "leading the target hits")


func test_combo_and_reward_multiplier() -> void:
	var b := BottleLogic.new(cfg, 1)
	var step := float(cfg["combo_step"])
	var full := Economy.full_coin_troops()
	# Spec v2.1 section 3.1: the coins are Economy.level_coins (tests/test_economy.gd checks it).
	eq(b.coins(10), Economy.level_coins(1, 10, full, 0, false, 0.0, 1.0), "no bottles: the plain payout")
	b.throw(_aim(b, 0), 0.0)
	eq(b.combo(), 1.0, "first hit: combo x1")
	b.throw(_aim(b, 1), 0.0)
	eq(b.combo(), 1.0 + step, "second in a row raises the combo")
	eq(b.multiplier(), Economy.bottle_factor(2, false), "two bottles: the payout's bottle factor")
	b.throw(Vector2(9, 9), 0.0)
	eq(b.combo(), 1.0, "a miss resets the combo")
	eq(b.streak, 0, "streak gone")
	var m := b.multiplier()
	b.throw(_aim(b, b.count() - 1), 0.0)  # gold
	check(b.is_gold(b.count() - 1), "last bottle is gold")
	eq(b.multiplier(), Economy.bottle_factor(2, true), "the gold bottle adds its share")
	check(b.multiplier() > m, "gold raises the multiplier")
	eq(b.coins(10, 0.1), Economy.level_coins(1, 10, full, 2, true, 0.0, 1.1), "station +10%")
	eq(b.best_streak, 2, "best streak kept")


func test_combo_caps() -> void:
	var b := BottleLogic.new(cfg, 1)
	eq(b.combo_for(50), float(cfg["combo_max"]), "capped")


func test_decoy_resets_combo_and_is_not_counted() -> void:
	var b := BottleLogic.new(cfg, 18)
	var d := -1
	var t := -1
	for i in b.count():
		if b.is_decoy(i) and d < 0:
			d = i
		elif not b.is_decoy(i) and not b.is_gold(i) and t < 0:
			t = i
	check(d >= 0 and t >= 0, "has a decoy and a target")
	var o := Vector3(0, 1.6, 0)
	var sp := float(b.wcfg["speed"])
	b.fire(o, b.solve(o, t, sp, 0.0), 0.0)
	eq(b.streak, 1, "hit")
	var r := b.fire(o, b.solve(o, d, sp, 0.0), 0.0)
	eq(r["hits"], [d], "the decoy breaks")
	eq(b.streak, 0, "the decoy resets the combo")
	eq(b.broken_count(), 1, "the decoy is not a broken bottle")


func test_ballistic_shot_drops_and_solve_leads() -> void:
	var b := BottleLogic.new(cfg, 21)  # bow: slow arrows, real drop
	var o := Vector3(0, 1.6, 0)
	var i := 0
	var tgt := b.position(i, 0.0)
	var flat := Vector3(tgt.x, tgt.y - o.y, -b.distance).normalized() * 20.0
	flat *= 20.0 / -flat.z  # forward speed 20
	var dt := b.time_to_plane(o, flat)
	var p := b.trajectory(o, flat, dt)
	check(p.y < tgt.y - 0.5, "an arrow aimed straight falls well short (%.2f)" % (tgt.y - p.y))
	eq(b.hit_at(Vector2(p.x, p.y), dt), -1, "so it misses")
	var w := b.wind(0)
	var v := b.solve(o, i, 20.0, 0.0, w)
	var r := b.fire(o, v, 0.0, w)
	eq(r["hits"], [i], "the solved arrow hits, wind and drop allowed for")
	check(absf(float(r["t"]) - b.distance / 20.0) < 0.001, "arrival time = range / speed")


func test_wind_is_fixed_per_level() -> void:
	var a := BottleLogic.new(cfg, 25)
	var b := BottleLogic.new(cfg, 25)
	eq(a.wind(2), b.wind(2), "same level, same wind")
	check(absf(a.wind(0)) <= float(a.layout["wind"]), "within the level's wind")
	eq(BottleLogic.new(cfg, 15).wind(0), 0.0, "no wind for the pistol")


func test_pistol_magazine_and_reload() -> void:
	var b := BottleLogic.new(cfg, 18)  # many bottles: more rounds than one magazine
	var o := Vector3(0, 1.62, 0)
	var size := b.mag_size
	check(size > 0 and b.shots_left > size, "magazine smaller than the rounds")
	eq(b.mag_left, size, "full magazine")
	for k in size:
		b.fire(o, Vector3(0, 0, -100), 0.0)
	eq(b.mag_left, 0, "empty")
	check(b.needs_reload(), "needs a reload")
	check(not b.can_fire(), "cannot fire while empty")
	var before := b.shots_left
	b.fire(o, Vector3(0, 0, -100), 0.0)
	eq(b.shots_left, before, "dry fire uses nothing")
	check(b.reload(), "reload")
	eq(b.mag_left, mini(size, b.shots_left), "refilled from what is left")
	check(not b.reload(), "a full magazine does not reload")


func test_sniper_zero_meets_line_of_sight() -> void:
	var b := BottleLogic.new(cfg, 41)
	var sp := float(b.wcfg["speed"])
	var zero := float(b.wcfg["zero"])
	var a := b.zero_angle(sp, zero)
	var v := Vector3(0, tan(a), -1.0) * sp
	var p := b.trajectory(Vector3.ZERO, v, zero / sp)
	check(absf(p.y) < 0.002, "zeroed: the bullet meets the line of sight at the zero range")
	check(b.distance > 90.0, "the sniper range is very far")
	var drop := b.trajectory(Vector3.ZERO, v, b.time_to_plane(Vector3.ZERO, v)).y
	check(drop < 0.0, "past the zero it drops a little (%.3f)" % drop)


func test_star_ricochet_off_a_plate_breaks_along_the_row() -> void:
	var b := BottleLogic.new(cfg, 31)
	check((b.layout["plates"] as Array).size() >= 2, "steel plates")
	var k := 0
	var pp := b.plate_position(k, 0.0)
	eq(b.hit_at(pp, 0.0), -1, "the plate is clear of bottles")
	var o := Vector3(0.25, 1.45, -0.4)
	var dt := (o.z + b.distance) / 12.0
	var v := Vector3((pp.x - o.x) / dt, (pp.y - o.y + 0.5 * b.gravity() * dt * dt) / dt, -12.0)
	var r := b.fire(o, v, 0.0)
	eq(r["plate"], k, "struck the plate")
	check((r["hits"] as Array).size() >= 2, "the ricochet breaks more than one bottle (%d)" % (r["hits"] as Array).size())
	eq(b.streak, (r["hits"] as Array).size(), "each counts toward the combo")

## Autoplay (strike=1) aims like this for every weapon: a perfect solve for the next target,
## reloading when the magazine is empty. Every level's set must be clearable that way.
func test_autoplay_clears_every_level() -> void:
	var origin := {"pistol": Vector3(0, 1.62, -0.35), "bow": Vector3(0, 1.58, -0.35),
		"stars": Vector3(0.25, 1.45, -0.4), "sniper": Vector3(0, 1.6, -0.35)}
	for lv in range(1, 51):
		var b := BottleLogic.new(cfg, lv)
		var t := 0.0
		var guard := 0
		while not b.finished() and guard < 40:
			guard += 1
			if b.needs_reload():
				check(b.reload(), "level %d reloads" % lv)
			var i := b.next_target()
			if b.weapon == "knife":
				var flight := b.flight_time(b.distance - 0.15)
				b.throw(b.position(i, t + flight), t + flight)
			else:
				var spd := float(b.wcfg.get("speed", b.wcfg.get("speed_max", 20.0)))
				var o: Vector3 = origin[b.weapon]
				var w := b.wind(b.shots_fired)
				b.fire(o, b.solve(o, i, spd, t, w), t, w)
			t += 1.3
		eq(b.remaining(), 0, "level %d (%s): autoplay clears the set" % [lv, b.weapon])


func test_weapon_configs_have_their_keys() -> void:
	var need := {"knife": ["distance", "speed", "hit_radius"],
		"pistol": ["distance", "speed", "mag", "reload_s", "kick_deg", "recover_s", "fov", "sens", "slow"],
		"bow": ["distance", "speed_min", "speed_max", "draw_s", "steady_s", "shake_deg", "wind", "fov"],
		"stars": ["distance", "speed_min", "speed_max", "swipe_fast", "ricochet_len", "plate_w", "plate_h"],
		"sniper": ["distance", "speed", "zero", "elevation", "scope_fov", "sway_deg", "tremor_deg", "steady_s", "cycle_s", "bullet_cam"]}
	for wname in need:
		var w: Dictionary = cfg["weapons"][wname]
		for k in need[wname]:
			check(w.has(k), "%s has %s" % [wname, k])
	for d in range(1, 6):
		check(cfg["district_stash"].has(str(d)), "district %d has a stash set" % d)


func test_stash_signs_never_block_a_bottle() -> void:
	check(FinaleStash.segment_hits_box(Vector3(0, 0, 0), Vector3(0, 0, -10), Vector3(-1, -1, -6), Vector3(1, 1, -5)), "a line through a box hits it")
	check(not FinaleStash.segment_hits_box(Vector3(0, 0, 0), Vector3(0, 0, -4), Vector3(-1, -1, -6), Vector3(1, 1, -5)), "a line that stops short does not")
	check(not FinaleStash.segment_hits_box(Vector3(0, 3, 0), Vector3(0, 3, -10), Vector3(-1, -1, -6), Vector3(1, 1, -5)), "a line above it does not")
	var root := Node3D.new()
	var sign := FinaleStash.neon_bottle(root, Vector3(0, 0.5, -9.0), 1.0, Color.MAGENTA, false)
	var eye := Vector3(0, 1.6, 0)
	var bottle := Vector3(0, 1.2, -10.0)
	eq(FinaleStash.clear_sightlines(root, eye, [bottle], 0.15), 1, "a sign in front of a bottle is lifted")
	check(not FinaleStash.segment_hits_box(eye, bottle, sign.position + Vector3(-0.42, -0.05, -0.08), sign.position + Vector3(0.42, 1.17, 0.08)), "and the line is clear")
	eq(FinaleStash.clear_sightlines(root, eye, [bottle], 0.15), 0, "a clean set is left alone")
	root.free()


# ---------------------------------------------------------------- v2 finale fixes (Task 9)

func test_bow_all_arrows_usable() -> void:
	var b := BottleLogic.new(cfg, 21)
	eq(b.weapon, "bow", "level 21 is the bow")
	eq(b.shots_left, 6, "four targets and two spare arrows")
	var o := Vector3(0, 1.6, -0.35)
	var n := 0
	# Every arrow misses (aimed into the floor): the quiver must still empty arrow by arrow.
	while b.can_fire():
		var r := b.fire(o, Vector3(0, -8.0, -20.0), n * 2.0, b.wind(b.shots_fired))
		eq(r["hits"], [], "arrow %d misses" % n)
		n += 1
		if n > 20:
			break
	eq(n, 6, "all six arrows can be shot")
	eq(b.shots_left, 0, "the quiver is empty")
	check(b.finished(), "and the finale is over")
	# A press made while the last arrow was still flying starts the next draw once the bow is ready.
	check(WeaponBow.starts_draw(true, false, true, false), "a finger held through the flight draws when ready")
	check(not WeaponBow.starts_draw(false, false, true, false), "no draw while an arrow is out")
	check(not WeaponBow.starts_draw(true, false, true, true), "already drawing: no new draw")
	check(not WeaponBow.starts_draw(true, true, true, false), "autoplay draws by itself")
	check(not WeaponBow.starts_draw(true, false, false, false), "no finger, no draw")


func test_wind_zero_hides_indicator() -> void:
	var calm := FinaleHud.wind_view(0.0, 2.3)
	check(not bool(calm["visible"]), "no wind: no arrow")
	check(not bool(FinaleHud.wind_view(0.04, 2.3)["visible"]), "a wind that reads 0.0 is hidden too")
	var soft := FinaleHud.wind_view(0.5, 2.3)
	var hard := FinaleHud.wind_view(-2.3, 2.3)
	check(bool(soft["visible"]) and bool(hard["visible"]), "real wind shows")
	eq(String(soft["text"]), "0.5", "strength as a number")
	eq(String(hard["text"]), "2.3", "strength is unsigned")
	check(float(hard["length"]) > float(soft["length"]), "the arrow grows with the strength")
	eq(float(hard["length"]), 1.0, "full arrow only at the strongest wind")
	eq(float(soft["angle"]), 0.0, "blowing right points right")
	eq(float(hard["angle"]), PI, "blowing left points left")
	for w in [0.06, 0.1, 0.7, 1.4, 2.0]:
		var v := FinaleHud.wind_view(w, 2.3)
		check(String(v["text"]) != "0.0" and bool(v["visible"]), "wind %.2f shows a number" % w)


## Screen rects of the standing bottles, the weapon model's parts, and whether they overlap, for
## every pistol and bow level, on a 9:16 and a 9:20 phone, aimed at the set and at each bottle.
func test_finale_weapons_never_cover_bottles() -> void:
	for vp in [Vector2(720, 1280), Vector2(720, 1600)]:
		for lv in range(1, 51):
			var b := BottleLogic.new(cfg, lv)
			if b.weapon != "pistol" and b.weapon != "bow":
				continue   # guests (v2.1 §4.3) count too: every pistol and bow level
			var fov := float(b.wcfg.get("fov", 30.0))
			var eye := FinaleWeapon.eye_point(b.wcfg)
			var rest := FinaleWeapon.rest_aim(b)
			var rest_cam := Transform3D(Basis.from_euler(Vector3(rest.y, rest.x, 0.0)), eye)
			var aims: Array = [rest_cam.basis * Vector3.FORWARD]
			for i in b.count():
				aims.append((Vector3(b.position(i, 0.0).x, b.position(i, 0.0).y, -b.distance) - eye).normalized())
			var model: Node3D
			var arrow: Node3D
			if b.weapon == "pistol":
				model = WeaponModels.pistol()
			else:
				model = WeaponModels.bow()
				arrow = WeaponModels.arrow()
				model.add_child(arrow)
			var worst := ""
			for a in aims:
				var poses: Array = []
				var cam := rest_cam
				if b.weapon == "pistol":
					# The pistol's view follows the aim; the gun rides low right in it.
					cam = Transform3D(Basis.looking_at(a, Vector3.UP), eye)
					poses.append(WeaponPistol.gun_pose())
				else:
					# The bow's view holds still; the bow swings to point at the pin.
					for d in [0.0, 1.0]:
						WeaponBow.place_arrow(model, arrow, d)
						poses.append(WeaponBow.bow_pose(rest_cam.basis.inverse() * a, d))
				var bottles: Array = []
				for t in [0.0, 1.0, 2.0, 3.0, 4.5]:
					bottles.append_array(FinaleWeapon.bottle_rects(b, cam, fov, vp, t))
				for pose in poses:
					var parts := WeaponModels.screen_rects(model, pose, fov, vp)
					check(parts.size() > 3, "level %d: the model has parts on screen" % lv)
					for r in parts:
						for q in bottles:
							if (r as Rect2).intersects(q as Rect2) and worst == "":
								worst = "level %d %s on %s: part %s covers bottle %s" % [lv, b.weapon, vp, r, q]
			check(worst == "", worst if worst != "" else "ok")
			model.free()


func test_bow_view_holds_still_with_bottles_in_frame() -> void:
	for vp in [Vector2(720, 1280), Vector2(720, 1600)]:
		for lv in range(1, 51):
			var b := BottleLogic.new(cfg, lv)
			if b.weapon != "bow":
				continue   # every bow level, guests included
			var rest := FinaleWeapon.rest_aim(b)
			var a := WeaponBow.view_basis_for(rest, Vector2(rest.x + 0.1, rest.y - 0.05))
			var c := WeaponBow.view_basis_for(rest, rest)
			check(a.is_equal_approx(c), "level %d: aiming does not move the camera" % lv)
			var cam := Transform3D(c, FinaleWeapon.eye_point(b.wcfg))
			var screen := Rect2(Vector2.ZERO, vp)
			var inside := 0
			for r in FinaleWeapon.bottle_rects(b, cam, float(b.wcfg["fov"]), vp, 0.0):
				if screen.encloses(r):
					inside += 1
			check(inside >= mini(3, b.count()), "level %d on %s: %d bottles in view" % [lv, vp, inside])
			eq(inside, b.count(), "level %d on %s: the whole set is in view" % [lv, vp])


# ---------------------------------------------------------------- spec 12.1: every bottle visible

const PHONES := [Vector2(720, 1280), Vector2(720, 1600)]


## Finale times over one whole cycle of the level's motion (just 0 for a set that stands still).
func _cycle(b: BottleLogic) -> Array:
	if String(b.layout.get("motion", "static")) == "static":
		return [0.0]
	var period := TAU / maxf(float(b.layout.get("speed", 1.0)), 0.1)
	var out: Array = []
	for k in 16:
		out.append(period * k / 16.0)
	return out


## In every weapon mode the whole set is on screen when aiming starts and while aiming, clear of
## the HUD's top and bottom bands: L1-50, a 9:16 and a 9:20 phone, the set's whole motion. The
## pistol's view follows the aim, so it is also checked aimed at each bottle in turn; the sniper
## counts unscoped (tiny is fine, off screen is not).
func test_every_weapon_shows_the_whole_set() -> void:
	for vp in PHONES:
		var safe := FinaleHud.safe_rect(vp)
		for lv in range(1, 51):
			var b := BottleLogic.new(cfg, lv)
			var view: Array = BottleShot.aim_camera(b)
			var cam: Transform3D = view[0]
			var fov := float(view[1])
			var bad := ""
			for t in _cycle(b):
				var cams: Array = [cam]
				if b.weapon == "pistol":
					for i in b.count():
						var p := b.position(i, t)
						cams.append(Transform3D(Basis.looking_at(Vector3(p.x, p.y, -b.distance) - cam.origin, Vector3.UP), cam.origin))
				for c in cams:
					for r in FinaleWeapon.bottle_rects(b, c, fov, vp, t):
						if not safe.encloses(r) and bad == "":
							bad = "level %d %s on %s at t=%.2f: bottle %s leaves %s" % [lv, b.weapon, vp, t, r, safe]
			check(bad == "", bad if bad != "" else "ok")


## The sniper's rifle (unscoped, at rest) never covers a bottle.
func test_sniper_rifle_never_covers_the_set() -> void:
	for vp in PHONES:
		for lv in range(1, 51):
			var b := BottleLogic.new(cfg, lv)
			if b.weapon != "sniper":
				continue   # every sniper level, guests included
			var view: Array = BottleShot.aim_camera(b)
			var rifle := WeaponModels.rifle()
			var parts := WeaponModels.screen_rects(rifle, Transform3D(Basis(), WeaponSniper.RIFLE_AT), float(view[1]), vp)
			var bad := ""
			for t in _cycle(b):
				for q in FinaleWeapon.bottle_rects(b, view[0], float(view[1]), vp, t):
					for r in parts:
						if (r as Rect2).intersects(q as Rect2) and bad == "":
							bad = "level %d on %s: rifle part %s covers bottle %s" % [lv, vp, r, q]
			check(bad == "", bad if bad != "" else "ok")
			rifle.free()


## Solid boxes of every mesh under `n` (in `xf` space), split into the moving rack and the rest.
func _solid_boxes(n: Node, xf: Transform3D, rack: Node, in_rack: bool, fixed: Array, moving: Array) -> void:
	for c in n.get_children():
		if not (c is Node3D):
			continue
		var cx: Transform3D = xf * (c as Node3D).transform
		var r := in_rack or c == rack
		if c is MeshInstance3D and (c as MeshInstance3D).mesh and not ((c as MeshInstance3D).material_override is ShaderMaterial):
			var box: AABB = cx * (c as MeshInstance3D).mesh.get_aabb()
			(moving if r else fixed).append(box)
		_solid_boxes(c, cx, rack, r, fixed, moving)


## No shelf, crate, board, bar or stash prop stands between the eye and a bottle: the lines to
## its middle, its shoulder and both sides stay clear over the set's whole motion (L1-50).
func test_stash_never_hides_a_bottle() -> void:
	for lv in range(1, 51):
		var s := BottleShot.new().setup(null, null, null, lv, 40, Vector3.ZERO, 0.0)
		var b := s.logic
		s._build_stage()
		var up := Vector3(0, s._floor_y, 0)
		var view: Array = BottleShot.aim_camera(b)
		var eye: Vector3 = (view[0] as Transform3D).origin + up
		s._clear_sightlines()   # what the finale does once the bottles stand
		var fixed: Array = []
		var moving: Array = []
		_solid_boxes(s, Transform3D(), s._rack, false, fixed, moving)
		check(moving.size() > 0 or String(b.layout.get("motion", "")) == "swing", "level %d: the rack has shelves" % lv)
		var x0 := float(b.layout["bottles"][0]["x"])
		var bad := ""
		for t in _cycle(b):
			var shift := Vector3.ZERO
			var motion := String(b.layout.get("motion", "static"))
			if motion == "slide" or motion == "drive":
				shift.x = b.position(0, t).x - x0
			for i in b.count():
				var p := b.position(i, t)
				var c := Vector3(p.x, p.y, -b.distance) + up
				for off in [Vector3.ZERO, Vector3(0, 0.24 * b.size, 0), Vector3(0.07 * b.size, 0, 0), Vector3(-0.07 * b.size, 0, 0)]:
					var q: Vector3 = c + off
					for box in fixed:
						if bad == "" and FinaleStash.segment_hits_box(eye, q, (box as AABB).position, (box as AABB).end):
							bad = "level %d (%s) t=%.2f: a stash box %s hides bottle %d at %s" % [lv, s.theme, t, box, i, q]
					for box in moving:
						var m := (box as AABB)
						if bad == "" and FinaleStash.segment_hits_box(eye, q, m.position + shift, m.end + shift):
							bad = "level %d (%s) t=%.2f: a shelf box %s hides bottle %d at %s" % [lv, s.theme, t, m, i, q]
		check(bad == "", bad if bad != "" else "ok")
		s.free()


# ---------------------------------------------------------------- spec v2.1 §4.3: guest weapons

## The stash set of `weapon`: the one of the district whose own weapon it is.
func _home_stash(weapon: String) -> String:
	for d in cfg["district_weapon"]:
		if String(cfg["district_weapon"][d]) == weapon:
			return String(cfg["district_stash"][d])
	return ""


## finale.json level_weapon gives a level a guest weapon; every other level keeps its district's.
## A guest brings its own stash set (the one built and checked for that weapon: the sniper needs
## its rooftop, the pistol its shooting gallery), keeps its own handling, and gets the gift's
## spare shot. Never on a district's first level (its own weapon's debut) or on its boss.
func test_level_weapon_overrides_district() -> void:
	var lw: Dictionary = cfg.get("level_weapon", {})
	check(lw.size() >= 10, "finale.json level_weapon schedules the guests (%d)" % lw.size())
	var spare := int((cfg.get("gift", {}) as Dictionary).get("spare", -1))
	check(spare >= 0, "finale.json gift.spare is set")
	var per_district := {}
	for k in lw:
		var lv := int(k)
		var b := BottleLogic.new(cfg, lv)
		eq(b.weapon, String(lw[k]), "level %d plays its guest weapon" % lv)
		check(b.guest, "level %d: a guest weapon" % lv)
		check(b.weapon != String(cfg["district_weapon"][str(b.district)]), "level %d: a guest is not the district's own weapon" % lv)
		check(lv % 10 != 0 and lv % 10 != 1, "level %d: never a district's first level or its boss" % lv)
		eq(b.stash, _home_stash(b.weapon), "level %d: the guest brings its own stash set" % lv)
		eq(b.wcfg, cfg["weapons"][b.weapon], "level %d: the guest's own handling" % lv)
		var row_spare := int(cfg["difficulty"]["spare"][b.step])
		eq(b.shots_left, b.targets() + row_spare + spare, "level %d: the row's spare shots plus the gift's" % lv)
		per_district[b.district] = int(per_district.get(b.district, 0)) + 1
	for d in range(1, 6):
		check(int(per_district.get(d, 0)) >= 2, "district %d has at least 2 guests" % d)
	for lv in range(1, 51):
		if lw.has(str(lv)):
			continue
		var b := BottleLogic.new(cfg, lv)
		eq(b.weapon, String(cfg["district_weapon"][str(b.district)]), "level %d keeps the district weapon" % lv)
		check(not b.guest, "level %d: no guest" % lv)
		eq(b.stash, String(cfg["district_stash"][str(b.district)]), "level %d: the district's stash" % lv)
	eq(BottleLogic.new(cfg, 4).weapon, "pistol", "L4: the first gift is the pistol")
	eq(BottleLogic.new(cfg, 13).weapon, "stars", "L13: the stars")
	# Review v2.1: the guests rotate. No guest follows itself, and the same slot of neighbouring
	# districts carries different guests.
	var keys: Array = lw.keys().map(func(k): return int(k))
	keys.sort()
	for i in range(1, keys.size()):
		check(String(lw[str(keys[i])]) != String(lw[str(keys[i - 1])]), "L%d's guest differs from L%d's" % [keys[i], keys[i - 1]])
		if keys[i] - keys[i - 1] == 10 or lw.has(str(keys[i] - 10)):
			var prev := str(keys[i] - 10)
			if lw.has(prev):
				check(String(lw[str(keys[i])]) != String(lw[prev]), "L%d's guest differs from L%s's (same slot)" % [keys[i], prev])
	eq(BottleLogic.new(cfg, 19).stash, "rooftop", "a guest sniper shoots from its roof")
	check(BottleLogic.new(cfg, 19).wcfg.has("elevation"), "with the roof's height")
	# No schedule: the district weapon everywhere. A schedule naming the district's own weapon or
	# an unknown one changes nothing.
	var plain: Dictionary = cfg.duplicate(true)
	plain.erase("level_weapon")
	eq(BottleLogic.new(plain, 4).weapon, "knife", "no schedule: knives on L4")
	plain["level_weapon"] = {"4": "knife", "5": "laser"}
	check(not BottleLogic.new(plain, 4).guest, "the district's own weapon is not a guest")
	eq(BottleLogic.new(plain, 5).weapon, "knife", "an unknown weapon is ignored")
	eq(BottleLogic.new(plain, 5).shots_left, BottleLogic.new(cfg, 5).shots_left, "and gets no gift shot")


## Review focus 4: the guest uses the Armory tier the player owns for it (base tier if none), on
## every attempt, so a purchase between a loss and a replay shows up; the save is never touched.
func test_guest_weapon_uses_current_tier() -> void:
	var tid := Armory.track_of("finale_pistol")
	check(tid != "", "the pistol has an Armory track")
	var save := {"unlocked": 4, "coins": 0, "armory": {}}
	var before: Dictionary = save.duplicate(true)
	var base := BottleLogic.new(Armory.apply_finale(cfg, save), 4)
	eq(base.weapon, "pistol", "L4 is a guest pistol")
	eq(int(base.wcfg["mag"]), int(cfg["weapons"]["pistol"]["mag"]), "nothing owned: the base tier's magazine")
	var info := GiftReveal.info(save, "pistol")
	eq(int(info["tier"]), 1, "nothing owned: tier 1")
	eq(int(info["lock"]), Armory.unlock_level(tid), "a locked track teases its unlock level")
	check(String(info["art"]).ends_with("finale_pistol_t1.png"), "tier 1 art (%s)" % info["art"])
	check(ResourceLoader.exists(String(info["art"])), "the art exists")
	eq(save, before, "the gift leaves the save alone")
	# A replay after buying into tier 2 (L23 is a guest pistol too).
	save["unlocked"] = 23
	Armory.set_index(save, tid, Armory.steps_per_tier(tid) + 1)
	eq(Armory.level(save, tid).x, 2, "bought into tier 2")
	before = save.duplicate(true)
	var owned := BottleLogic.new(Armory.apply_finale(cfg, save), 23)
	eq(owned.weapon, "pistol", "L23 is a guest pistol")
	check(int(owned.wcfg["mag"]) > int(cfg["weapons"]["pistol"]["mag"]), "the owned tier's bigger magazine")
	check(float(owned.wcfg["kick_deg"]) < float(cfg["weapons"]["pistol"]["kick_deg"]), "and its softer kick")
	eq(owned.wcfg, BottleLogic.new(Armory.apply_finale(cfg, save), 11).wcfg, "the same handling as the district's own pistol")
	var info2 := GiftReveal.info(save, "pistol")
	eq(int(info2["tier"]), 2, "the reveal shows tier 2")
	eq(int(info2["lock"]), 0, "an open track shows no lock")
	check(String(info2["art"]).ends_with("finale_pistol_t2.png"), "tier 2 art (%s)" % info2["art"])
	eq(save, before, "still untouched")
	for w in ["bow", "stars", "sniper"]:
		var i := GiftReveal.info({"unlocked": 1}, w)
		check(int(i["lock"]) > 1 and ResourceLoader.exists(String(i["art"])), "%s: art and a lock level" % w)


## The reveal: at most 1.5 s (finale.json gift), the weapon reaches the hand before it ends, and
## a tap ends it at once with the weapon in hand; that tap's release is swallowed (never a shot).
func test_gift_reveal_skippable_and_short() -> void:
	var gc: Dictionary = cfg.get("gift", {})
	check(not gc.is_empty(), "finale.json has the gift block")
	var total := GiftReveal.total(gc)
	check(total >= 0.8 and total <= 1.5, "the reveal lasts %.2f s (0.8 to 1.5)" % total)
	var g := GiftReveal.new().setup(gc, "pistol", 1, 11)
	var seen: Array = []
	g.handed.connect(func(): seen.append(["handed", g.t]))
	g.finished.connect(func(): seen.append(["finished", g.t]))
	check(not g.take_input(_tap(true)), "a tap before it plays is not taken")
	g.play()
	var steps := 0
	while not g.done and steps < 600:
		g.advance(1.0 / 60.0)
		steps += 1
	check(g.done, "it ends by itself")
	check(steps / 60.0 <= 1.5 + 0.02, "within 1.5 s (%.2f)" % (steps / 60.0))
	eq(seen.size(), 2, "handed once, finished once")
	if seen.size() == 2:
		eq(seen[0][0], "handed", "the weapon reaches the hand first")
		check(float(seen[0][1]) > total * 0.5, "after the box has opened (%.2f)" % float(seen[0][1]))
	g.free()
	var s := GiftReveal.new().setup(gc, "sniper", 1, 41)
	var got: Array = []
	s.handed.connect(func(): got.append("handed"))
	s.finished.connect(func(): got.append("finished"))
	s.play()
	s.advance(0.2)
	check(s.take_input(_tap(true)), "a tap is taken by the reveal")
	check(s.done, "a tap ends it at once")
	eq(got, ["handed", "finished"], "the weapon is handed over, then the reveal is over")
	check(s.take_input(_tap(false)), "the skipping tap's release is swallowed")
	check(not s.take_input(_tap(true)), "after that it takes nothing")
	s.free()
	var long: Dictionary = gc.duplicate(true)
	for k in ["drop_s", "wiggle_s", "open_s", "spin_s", "fly_s"]:
		long[k] = 1.0
	check(GiftReveal.total(long) <= 1.5 + 0.0001, "phases past the cap are squeezed into 1.5 s")


func _tap(pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.pressed = pressed
	e.position = Vector2(270, 480)
	return e
