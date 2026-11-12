class_name BottleLogic
extends RefCounted
## Bottle Shot finale rules. Pure and tested; src/finale/* only draws them.
##
## Space: the hero stands at the origin facing -Z. Bottles stand on the plane z = -distance;
## a bottle's position is (x sideways, y height above the stand's floor).
## The district picks the weapon (knife, pistol, bow, stars, sniper); the level's place in its
## district picks the difficulty row (count, decoys, spare shots, size, distance, motion, wind).
## Knives fly straight (`throw`); everything else is a ballistic shot (`fire`): constant speed
## along the range, gravity down, wind sideways, hitting what is under the crossing point when
## it arrives. A star that crosses a steel plate ricochets along its row and can break more.
## Combo: hits in a row raise a streak factor (the HUD's flame). Coins (spec v2.1 section 3.1)
## count the bottles broken and the gold one through Economy.level_coins, capped at 1.7x.

var cfg: Dictionary
var level := 1
var district := 1
var step := 0                  # 0..9: the level's place inside its district
var weapon := "knife"
var wcfg: Dictionary           # this weapon's config
var layout: Dictionary         # {motion, amp, speed, bottles: [{x, y, gold?, decoy?}], plates: [...]}
var distance := 5.55           # metres from the hero to the bottle plane
var size := 1.0                # bottle and hit-zone scale
var broken: Array = []         # bool per bottle (decoys too)
var shots_left := 3
var mag_size := 0              # 0 = no magazine
var mag_left := 0
var shots_fired := 0
var streak := 0                # hits in a row
var best_streak := 0
var heat := 0.0                # the level's mean tap heat (0..1): the payout's tap term

## Old name, kept for callers that count knives.
var knives_left: int:
	get:
		return shots_left


func _init(finale_cfg: Dictionary, level_id: int) -> void:
	cfg = finale_cfg
	level = maxi(level_id, 1)
	district = clampi(int(ceil(level / 10.0)), 1, 5)
	step = (level - 1) % 10
	weapon = String((cfg.get("district_weapon", {}) as Dictionary).get(str(district), "knife"))
	var weapons: Dictionary = cfg.get("weapons", {})
	wcfg = weapons.get(weapon, weapons.get("knife", {}))
	var diff: Dictionary = cfg.get("difficulty", {})
	size = _row(diff, "size", 1.0)
	distance = float(wcfg.get("distance", 5.55)) * _row(diff, "dist", 1.0)
	layout = _make_layout(diff)
	for b in layout["bottles"]:
		broken.append(false)
	shots_left = targets() + int(_row(diff, "spare", 0.0))
	mag_size = int(wcfg.get("mag", 0))
	mag_left = mini(mag_size, shots_left) if mag_size > 0 else 0


func _row(diff: Dictionary, key: String, fallback: Variant) -> Variant:
	var a: Array = diff.get(key, [])
	if a.is_empty():
		return fallback
	return a[mini(step, a.size() - 1)]


## Rows of up to per_row bottles, centred, bottom row first; the gold bottle stands on top;
## decoys take fixed slots spread through the set (never the gold one).
func _make_layout(diff: Dictionary) -> Dictionary:
	var n := int(_row(diff, "count", 3))
	var decoys := int(_row(diff, "decoys", 0))
	var total := n + 1 + decoys
	var per_row := maxi(int(wcfg.get("per_row", 4)), 1)
	var spacing := float(wcfg.get("spacing", 0.9)) * size
	var row_h := float(wcfg.get("row_h", 0.9)) * size
	var y0 := float(wcfg.get("y0", 1.45))
	var others := total - 1
	var rows := int(ceil(others / float(per_row)))
	var bottles: Array = []
	var plates: Array = []
	for r in rows:
		var k := mini(per_row, others - r * per_row)
		for c in k:
			bottles.append({"x": (c - (k - 1) * 0.5) * spacing, "y": y0 + r * row_h})
		if weapon == "stars":
			var half := (k - 1) * 0.5 * spacing + spacing * 0.75
			for s in [-1.0, 1.0]:
				plates.append({"x": s * half, "y": y0 + r * row_h, "dir": -s})
	# The gold bottle stands alone on top, a little off centre.
	bottles.append({"x": spacing * 0.5, "y": y0 + rows * row_h, "gold": true})
	# Decoys: spread evenly over the non-gold slots, deterministic.
	for j in decoys:
		var idx := int(floor((j + 0.5) * (total - 1) / float(decoys)))
		idx = clampi(idx, 0, total - 2)
		while bottles[idx].get("decoy", false):
			idx = (idx + 1) % (total - 1)
		bottles[idx]["decoy"] = true
	var motion := String(_row(diff, "motion", "static"))
	var amp := float(_row(diff, "amp", 0.0)) * float(wcfg.get("amp_scale", 1.0))
	if amp <= 0.0:
		motion = "static"
	return {"motion": motion, "amp": amp, "speed": float(_row(diff, "speed", 1.0)),
		"bottles": bottles, "plates": plates, "wind": float(_row(diff, "wind", 0.0)) * float(wcfg.get("wind", 0.0)),
		"seed": level}


func count() -> int:
	return (layout["bottles"] as Array).size()


func is_gold(i: int) -> bool:
	return bool(layout["bottles"][i].get("gold", false))


func is_decoy(i: int) -> bool:
	return bool(layout["bottles"][i].get("decoy", false))


## Bottles that count (everything but decoys).
func targets() -> int:
	var n := 0
	for i in count():
		if not is_decoy(i):
			n += 1
	return n


## Target bottles still standing.
func remaining() -> int:
	var n := 0
	for i in count():
		if not is_decoy(i) and not broken[i]:
			n += 1
	return n


func finished() -> bool:
	return remaining() == 0 or shots_left <= 0


## The first target still standing (autoplay), or -1.
func next_target() -> int:
	for i in count():
		if not is_decoy(i) and not broken[i]:
			return i
	return -1


## Where bottle `i` is at time `t` (x sideways, y height).
func position(i: int, t: float) -> Vector2:
	var b: Dictionary = layout["bottles"][i]
	return Vector2(float(b["x"]), float(b["y"])) + _motion_offset(i, t)


func _motion_offset(i: int, t: float) -> Vector2:
	var amp := float(layout.get("amp", 0.0))
	var speed := float(layout.get("speed", 1.0))
	match String(layout.get("motion", "static")):
		"slide", "drive":
			return Vector2(sin(t * speed) * amp, 0.0)
		"swing":
			return Vector2(sin(t * speed + i * 1.3) * amp, 0.0)
	return Vector2.ZERO


## Steel plate `k` (stars) at time `t`: it rides the shelf when the shelf slides.
func plate_position(k: int, t: float) -> Vector2:
	var p: Dictionary = layout["plates"][k]
	var off := Vector2.ZERO
	var motion := String(layout.get("motion", "static"))
	if motion == "slide" or motion == "drive":
		off = _motion_offset(0, t)
	return Vector2(float(p["x"]), float(p["y"])) + off


func hit_radius() -> float:
	return float(wcfg.get("hit_radius", 0.24)) * size


## Inside bottle `i`'s hit zone (an upright ellipse) at time `t`?
func _inside(i: int, p: Vector2, t: float) -> float:
	var d := position(i, t) - p
	var rx := hit_radius()
	var ry := rx * float(wcfg.get("aspect", 1.0))
	return sqrt((d.x / rx) * (d.x / rx) + (d.y / ry) * (d.y / ry))


## Seconds a knife takes to cover `dist` metres.
func flight_time(dist: float) -> float:
	return dist / float(wcfg.get("speed", 14.0))


## Which standing bottle (or -1) is under `aim` at time `t_hit`. Decoys count: they are in the way.
func hit_at(aim: Vector2, t_hit: float) -> int:
	var best := -1
	var best_d := 1.0
	for i in count():
		if broken[i]:
			continue
		var d := _inside(i, aim, t_hit)
		if d <= best_d:
			best = i
			best_d = d
	return best


## Throws one knife; returns the bottle index broken or -1. Uses up a knife either way.
func throw(aim: Vector2, t_hit: float) -> int:
	if not can_fire():
		return -1
	_use_shot()
	var i := hit_at(aim, t_hit)
	_register([i] if i >= 0 else [])
	return i


func can_fire() -> bool:
	return shots_left > 0 and (mag_size <= 0 or mag_left > 0)


## A fresh magazine (as many rounds as are left, up to its size). False if nothing changes.
func reload() -> bool:
	if mag_size <= 0 or mag_left >= mini(mag_size, shots_left):
		return false
	mag_left = mini(mag_size, shots_left)
	return true


func needs_reload() -> bool:
	return mag_size > 0 and mag_left <= 0 and shots_left > 0


func _use_shot() -> void:
	shots_left -= 1
	shots_fired += 1
	if mag_size > 0:
		mag_left -= 1


# ---------------------------------------------------------------- ballistics

func gravity() -> float:
	return float(wcfg.get("gravity", 0.0))


## Sideways wind (m/s^2) for shot number `n` (0-based): steady within a shot, changes between
## shots, the same every time this level is played.
func wind(n: int) -> float:
	var w := float(layout.get("wind", 0.0))
	if w <= 0.0:
		return 0.0
	var h := fposmod(sin(level * 12.9898 + n * 78.233) * 43758.5453, 1.0)
	return w * (h * 2.0 - 1.0)


## Where a shot fired from `o` with velocity `v` is after `t` seconds.
func trajectory(o: Vector3, v: Vector3, t: float, wind_x := 0.0) -> Vector3:
	return o + v * t + Vector3(wind_x, -gravity(), 0.0) * (0.5 * t * t)


## Seconds from `o` to the bottle plane at velocity `v` (INF if it never gets there).
func time_to_plane(o: Vector3, v: Vector3) -> float:
	if v.z >= -0.001:
		return INF
	return (o.z + distance) / -v.z


## Fires one shot from `o` (hero space) at velocity `v`, at finale time `t0`.
## Returns {hits: [i...], point: Vector3 crossing point, t: arrival time, plate: k or -1,
## end: Vector2 where a ricochet stops, times: [arrival per hit]}. Hits are registered.
func fire(o: Vector3, v: Vector3, t0: float, wind_x := 0.0) -> Dictionary:
	var out := {"hits": [], "point": Vector3.ZERO, "t": t0, "plate": -1, "end": Vector2.ZERO, "times": []}
	if not can_fire():
		return out
	_use_shot()
	var dt := time_to_plane(o, v)
	if is_inf(dt):
		_register([])
		return out
	var p := trajectory(o, v, dt, wind_x)
	var t := t0 + dt
	out["point"] = p
	out["t"] = t
	var p2 := Vector2(p.x, p.y)
	var i := hit_at(p2, t)
	if i >= 0:
		out["hits"] = [i]
		out["times"] = [t]
	else:
		var k := plate_hit(p2, t)
		if k >= 0:
			out["plate"] = k
			_ricochet(k, p2, t, out)
	_register(out["hits"])
	return out


## Which steel plate (or -1) is under `p` at time `t`.
func plate_hit(p: Vector2, t: float) -> int:
	var w := float(wcfg.get("plate_w", 0.4)) * size * 0.5
	var h := float(wcfg.get("plate_h", 0.6)) * size * 0.5
	for k in (layout.get("plates", []) as Array).size():
		var c := plate_position(k, t)
		if absf(p.x - c.x) <= w and absf(p.y - c.y) <= h:
			return k
	return -1


## A star off plate `k` skims along its row for ricochet_len metres and breaks every standing
## bottle whose hit zone the line crosses (decoys stop it).
func _ricochet(k: int, p: Vector2, t: float, out: Dictionary) -> void:
	var dir := float(layout["plates"][k]["dir"])
	var length := float(wcfg.get("ricochet_len", 2.0))
	var rs := maxf(float(wcfg.get("ricochet_speed", 10.0)), 0.1)
	var y := plate_position(k, t).y
	out["end"] = Vector2(p.x + dir * length, y)
	var found: Array = []
	for i in count():
		if broken[i]:
			continue
		var b := position(i, t)
		var along := (b.x - p.x) * dir
		if along < 0.0 or along > length:
			continue
		if _inside(i, Vector2(b.x, y), t) <= 1.0:
			found.append({"i": i, "along": along})
	found.sort_custom(func(a, b): return float(a["along"]) < float(b["along"]))
	for f in found:
		out["hits"].append(int(f["i"]))
		out["times"].append(t + float(f["along"]) / rs)
		if is_decoy(int(f["i"])):
			out["end"] = Vector2(p.x + dir * float(f["along"]), y)
			break


## Velocity (forward speed `speed` along the range) that lands on bottle `i`, leading it for
## its motion and the flight time, against gravity and wind. `zero_tilt` is ignored here.
func solve(o: Vector3, i: int, speed: float, t0: float, wind_x := 0.0) -> Vector3:
	var dt := (o.z + distance) / maxf(speed, 0.01)
	var target := position(i, t0 + dt)
	var vx := (target.x - o.x - 0.5 * wind_x * dt * dt) / dt
	var vy := (target.y - o.y + 0.5 * gravity() * dt * dt) / dt
	return Vector3(vx, vy, -speed)


## Pitch (radians) a sight zeroed at `zero_m` adds so the line of sight meets the drop there.
func zero_angle(speed: float, zero_m: float) -> float:
	var t := zero_m / maxf(speed, 0.01)
	return atan(0.5 * gravity() * t * t / maxf(zero_m, 0.01))


# ---------------------------------------------------------------- score

## Hits in a row: each target hit raises the combo; a miss or a decoy resets it.
func _register(hits: Array) -> void:
	if hits.is_empty():
		streak = 0
		return
	for i in hits:
		broken[i] = true
		if is_decoy(i):
			streak = 0
			continue
		streak += 1
		best_streak = maxi(best_streak, streak)


## The combo factor of the `n`-th hit in a row.
func combo_for(n: int) -> float:
	if n <= 0:
		return 1.0
	return minf(1.0 + float(cfg.get("combo_step", 0.0)) * (n - 1), float(cfg.get("combo_max", 1.0)))


## The combo factor the current streak is on.
func combo() -> float:
	return combo_for(streak)


func broken_count(gold := false) -> int:
	var n := 0
	for i in count():
		if broken[i] and not is_decoy(i) and is_gold(i) == gold:
			n += 1
	return n


## Multiplier from broken bottles (spec v2.1 section 3.1): Economy.bottle_factor, 1 + 0.1 per
## bottle (up to 4) + 0.3 for the gold one, so a perfect run pays at most 1.7x a plain win.
func multiplier() -> float:
	return Economy.bottle_factor(broken_count(), broken_count(true) > 0)


## What the win pays (Economy.level_coins, the one payout function): `troops` = the finish as
## district-1 troops (LevelSim.coin_troops, a full squad = the stored route's finish),
## `station_bonus` = the evidence room's coin bonus (0.2 = +20%), `heat` = the level's taps.
func coins(troops: int, station_bonus := 0.0) -> int:
	return Economy.level_coins(level, troops, Economy.full_coin_troops(), broken_count(), broken_count(true) > 0,
		heat, 1.0 + station_bonus)
