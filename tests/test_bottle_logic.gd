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
	var late := BottleLogic.new(cfg, 19)
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
	var base := float(cfg["clear_bonus"]) + 10 * float(cfg["per_troop"])
	var per := float(cfg["bonus_per_bottle"])
	var step := float(cfg["combo_step"])
	eq(b.coins(10), int(round(base)), "no bottles: clear bonus + troops x per_troop")
	b.throw(_aim(b, 0), 0.0)
	eq(b.combo(), 1.0, "first hit: combo x1")
	b.throw(_aim(b, 1), 0.0)
	eq(b.combo(), 1.0 + step, "second in a row raises the combo")
	eq(b.multiplier(), 1.0 + per + per * (1.0 + step), "bottles x combo")
	b.throw(Vector2(9, 9), 0.0)
	eq(b.combo(), 1.0, "a miss resets the combo")
	eq(b.streak, 0, "streak gone")
	var m := b.multiplier()
	b.throw(_aim(b, b.count() - 1), 0.0)  # gold
	check(b.is_gold(b.count() - 1), "last bottle is gold")
	eq(b.multiplier(), m * float(cfg["gold_mult"]), "gold doubles")
	eq(b.coins(10, 0.1), int(round(base * b.multiplier() * 1.1)), "station +10%")
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
	var b := BottleLogic.new(cfg, 19)  # many bottles: more rounds than one magazine
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
		for lv in range(11, 31):
			var b := BottleLogic.new(cfg, lv)
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
		for lv in range(21, 31):
			var b := BottleLogic.new(cfg, lv)
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
