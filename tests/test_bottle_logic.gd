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
