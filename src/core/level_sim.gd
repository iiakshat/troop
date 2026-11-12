class_name LevelSim
extends RefCounted
## The whole battle as numbers. No nodes, deterministic for a given dt, unit tested.
## The view (src/game/level_view.gd) only reads this state and drains `out` events.
##
## Space: the squad stands at z = 0 and faces -z. Everything else spawns far ahead
## (negative z) and comes towards it. Lanes are 0 (left), 1 (middle), 2 (right).
##
## Every level event has an `at`: the track distance at which it reaches the squad.
## Gates and obstacles ride the road (scroll speed); gangs also run (scroll + their speed),
## so they spawn earlier to arrive on time.
##
## The scroll speed `S` is not constant: the squad stops running and stands its ground
## (`halted`, a standoff) while a boss is within `boss_halt` metres or while any gang that
## stops to shoot has stopped, and it stops `finish_hold` metres short of the Gang HQ while
## any gang is still alive or yet to come. So bosses really walk in (slowly, shooting), a
## gunman line is a real standoff (the street does not scroll past it), and the HQ never
## scrolls past a fight. `traveled` does not advance while halted.
##
## Obstacles hit spatially: the squad is a formation of slots (Squad.slot_offset) around its
## real sideways position `squad_x` (set_squad_x, called by the view every frame; without it
## the squad stands at its lane centre). An obstacle has a footprint `width` and a capacity
## (its shown number); only the troops whose slots overlap the footprint die, up to the
## capacity. Steering half past an obstacle saves half the squad.
##
## Shooting rule (easy to explain to players): bullets stream down your lane and hit the
## first thing they meet: a gang (gangs fill the whole road), a red gate, a barricade, a
## barrel or a car. Snipers are the one exception: they shoot the toughest gang in range.
##
## Gangs are blocks of rows. Bullets always kill from the front, so the gang's front is its
## frontmost *living* row. Nothing hurts the squad until that front physically reaches it;
## then the gang fights row by row (melee), each enemy taking `power` troops and dying.
## Ranged gangs attack from a distance: gunmen/grenadiers shoot, molotovs lob firebombs
## into the squad's lane (dodge by changing lane), sniper foes aim a laser then fire.

var S: float            # current scroll speed, m/s
var S_base: float       # running speed
var accel: float        # how fast the squad stops and starts, m/s²
var fire_range: float
var spawn_dist: float
var contact_z: float
var melee_tick: float
var boss_halt: float
var finish_hold: float
var boss_hit_every: float
var lane_w := 2.8          # metres between lane centres
var form_half := 1.25      # widest a formation gets either side of its centre
var fig_cap := 72          # figures a formation is drawn with (each carries total/figures troops)
var fig_r := 0.2           # figure radius for footprint overlap
var gate_clear_s := 2.5    # a committed squad shoots a red gate up to 0 within this many seconds
var gang_priority := 0.0   # a gang front this close takes the fire before nearer lane objects
var gang_figs := 180       # a gang stands in at most this many figures (per = people per figure)
var district := 1          # 1-5: the squad cap and return fire depend on it
var caps: Array = []       # world.squad_cap, per district

## Tap-to-fire: the hero fires at lerp(tap_auto, 1, tap_heat) of his rate (units.hero.tap).
var tap_heat := 0.0        # 0..1; each tap() adds tap_per, held tap_hold_s, then drains over tap_decay_s
var tap_auto := 1.0
var tap_per := 1.0
var tap_hold_s := 0.0
var tap_decay_s := 1.0
var _tap_hold := 0.0       # seconds left before the heat starts to drain

var stats: Dictionary   # effective ally stats after upgrades
var weapons: Dictionary
var enemy_defs: Dictionary
var obstacle_defs: Dictionary
var powers: Dictionary
var rf_cfg: Dictionary     # units.return_fire: from_district, range
var revive_cfg: Dictionary
var star_cfg: Dictionary

var squad := Squad.new()
var lane := 1
var squad_x := 0.0          # the squad's real sideways position (metres, 0 = middle lane)
var _x_driven := false      # true once the view feeds set_squad_x (else lane centres)
var traveled := 0.0
var time := 0.0
var state := "run"      # run | strike | lost
var lose_cause := ""
var finish_at := 0.0
var halted := false     # the squad is standing its ground (boss fight or waiting at the HQ)
var peak_squad := 0
var revived := false

var rows: Array = []        # gate rows on screen
var obstacles: Array = []
var hordes: Array = []
var firebombs: Array = []   # in the air: {horde, lane, land, burn}
var bombs: Array = []       # the squad's bombs in the air: {id, lane, x, land, target, ref, z}
var charges: Dictionary = {"shield": 0, "bomb": 0}
var shield_t := 0.0
var kills := 0
var kills_by := {}      # enemy kind -> people killed (mission stats)
var rows_passed := 0
var out: Array = []         # events for the view, drained each frame
var target_kind := ""       # what the squad shot this tick: "horde" | "gate" | "obstacle" | ""
var target_ref = null
var snipe_ref = null        # the gang the snipers shot this tick (or null)

var _spawns: Array = []     # pre-computed, sorted by the distance at which they appear
var _next_spawn := 0
var _pending_hordes := 0    # horde spawns not yet on screen
var _wave_ats: Array = []   # arrival `at` of each wave event, in order
var _wave_mods: Dictionary = {}  # wave index -> {"div": k, "strip": true}
var _next_id := 1
var _armour_note_t := 0.0
var _joined: Dictionary = {}     # rank -> true once it arrived this level


func _init(level: Dictionary = {}, units_cfg: Dictionary = {}, upgrades: Dictionary = {}) -> void:
	if units_cfg.is_empty():
		return  # clone() fills the fields
	var w: Dictionary = units_cfg["world"]
	S_base = float(w["scroll_speed"])
	S = S_base
	accel = float(w.get("scroll_accel", 12.0))
	fire_range = float(w["fire_range"])
	spawn_dist = float(w["spawn_distance"])
	contact_z = float(w["contact_z"])
	melee_tick = float(w.get("melee_tick", 0.22))
	boss_halt = float(w.get("boss_halt", 40.0))
	finish_hold = float(w.get("finish_hold", 14.0))
	boss_hit_every = float(w.get("boss_hit_every", 0.1))
	lane_w = float(w.get("lane_width", lane_w))
	form_half = float(w.get("formation_half_width", form_half))
	fig_cap = int(w.get("formation_figures", fig_cap))
	fig_r = float(w.get("figure_radius", fig_r))
	gate_clear_s = float(w.get("red_gate_clear_s", gate_clear_s))
	gang_priority = float(w.get("gang_priority_m", gang_priority))
	gang_figs = maxi(int(w.get("gang_figures", gang_figs)), 1)
	district = clampi(int(level.get("district", 1)), 1, 5)
	caps = w.get("squad_cap", [])
	var tap: Dictionary = units_cfg.get("hero", {}).get("tap", {})
	tap_auto = float(tap.get("auto_rate", tap_auto))
	tap_per = float(tap.get("per_tap", tap_per))
	tap_hold_s = float(tap.get("hold_s", tap_hold_s))
	tap_decay_s = maxf(float(tap.get("decay_s", tap_decay_s)), 0.001)
	stats = units_cfg["allies"].duplicate(true)
	weapons = units_cfg["hero_weapons"]
	enemy_defs = units_cfg["enemies"]
	obstacle_defs = units_cfg.get("obstacles", {})
	powers = units_cfg["powers"]
	rf_cfg = units_cfg.get("return_fire", {})
	revive_cfg = units_cfg.get("revive", {})
	star_cfg = level.get("stars", units_cfg.get("stars", {}))

	var hero: Dictionary = stats["hero"]
	hero["dmg"] = float(hero["dmg"]) + float(upgrades.get("knife", 0))
	hero["rate"] = float(hero["rate"]) + 0.5 * float(upgrades.get("speed", 0))
	squad.cap = squad_cap_for(units_cfg, district, int(upgrades.get("capacity", 0)))
	squad.add("constable", int(upgrades.get("squad", 0)))
	# Pre-level booster: each head-start token brings a few constables.
	var per_token := int(units_cfg.get("boosters", {}).get("headstart", 5))
	squad.add("constable", int(upgrades.get("headstart", 0)) * per_token)

	var ch: Dictionary = level.get("charges", {})
	for k in ch:
		charges[k] = int(ch[k])
	# Police-station garage and booster tokens: extra powers at the start of the level.
	charges["shield"] = int(charges["shield"]) + int(upgrades.get("shield", 0))
	charges["bomb"] = int(charges["bomb"]) + int(upgrades.get("bomb", 0))
	_build_spawns(level.get("events", []))
	peak_squad = squad.total()
	squad.hero_rate = hero_rate_mult()


## The most troops a squad holds in `district` (1-5): world.squad_cap, plus the barracks'
## `capacity_pct` percent of it. Exact integers.
static func squad_cap_for(units_cfg: Dictionary, d: int, capacity_pct := 0) -> int:
	var caps: Array = units_cfg["world"].get("squad_cap", [])
	if caps.is_empty():
		return 0
	var base := int(caps[clampi(d, 1, caps.size()) - 1])
	return base + base * maxi(capacity_pct, 0) / 100


## The squad as district-1 troops (what the finale's coins count): a full district-5 squad
## pays like a full district-1 squad, so rewards stay on the economy's curve as caps grow.
func coin_troops() -> int:
	if caps.size() < district:
		return squad.total()
	return squad.total() * int(caps[0]) / maxi(int(caps[district - 1]), 1)


# ---------------------------------------------------------------- tap heat

## One tap on the fire zone: the hero heats up (spec v2 section 2).
func tap() -> void:
	tap_heat = minf(tap_heat + tap_per, 1.0)
	_tap_hold = tap_hold_s
	squad.hero_rate = hero_rate_mult()


## The squad's live firepower (Squad.firepower with the current upgrades and tap heat), as
## the whole number the HUD shows next to the troop count.
func firepower() -> int:
	return int(round(squad.firepower(stats, weapons)))


## Share of the hero's base rate he fires at now: tap_auto when cold, 1.0 when hot.
func hero_rate_mult() -> float:
	return lerpf(tap_auto, 1.0, tap_heat)


func _cool(dt: float) -> void:
	var held := minf(dt, _tap_hold)
	_tap_hold -= held
	tap_heat = maxf(tap_heat - (dt - held) / tap_decay_s, 0.0)
	squad.hero_rate = hero_rate_mult()


## A gang's numbers: the enemy type, with any per-group overrides (boss variants etc.).
func enemy_def(grp: Dictionary) -> Dictionary:
	var def: Dictionary = enemy_defs[grp["enemy"]]
	var over := false
	for k in grp:
		if k != "enemy" and k != "n" and k != "gap" and def.has(k):
			over = true
	if not over:
		return def
	var d := def.duplicate()
	for k in grp:
		if k != "enemy" and k != "n" and k != "gap" and def.has(k):
			d[k] = grp[k]
	return d


func _build_spawns(events: Array) -> void:
	var wave_index := 0
	for ev in events:
		var e: Dictionary = ev
		var at := float(e.get("at", 0.0))
		match String(e.get("type", "")):
			"gates", "obstacle":
				_spawns.append({"kind": e["type"], "ev": e, "at": at, "spawn_at": at - spawn_dist})
			"finish":
				finish_at = at
				_spawns.append({"kind": "finish", "ev": e, "at": at, "spawn_at": at - spawn_dist})
			"hint":
				_spawns.append({"kind": "hint", "ev": e, "at": at, "spawn_at": at})
			"wave":
				_wave_ats.append(at)
				for g in e.get("groups", []):
					var grp: Dictionary = g
					var def := enemy_def(grp)
					var arrive := at + float(grp.get("gap", 0.0))
					var vrel := S_base + float(def["speed"])
					var stop := float(def.get("stop_at", 0.0))
					_spawns.append({"kind": "horde", "ev": grp, "at": arrive, "wave": wave_index,
						"label": String(e.get("label", "")),
						"spawn_at": arrive - (spawn_dist - stop) * S_base / vrel})
					_pending_hordes += 1
				wave_index += 1
	_spawns.sort_custom(func(a, b): return float(a["spawn_at"]) < float(b["spawn_at"]))


# ---------------------------------------------------------------- input

func set_lane(l: int) -> void:
	lane = clampi(l, 0, 2)
	if not _x_driven:
		squad_x = lane_x(lane)


## The squad's real sideways position (the view's steering, every frame). Obstacles hit the
## troops whose formation slots overlap them at this x.
func set_squad_x(x: float) -> void:
	_x_driven = true
	squad_x = clampf(x, lane_x(0), lane_x(2))


func lane_x(l: int) -> float:
	return (l - 1) * lane_w


## Which troops an obstacle in its lane would hit right now: Squad.footprint_hits for this
## squad at squad_x, with the obstacle's footprint and capacity (`n` troops).
func obstacle_hits(ob: Dictionary, n: int, keep_hero := false) -> Dictionary:
	var total := squad.total()
	var cap := mini(n, total - 1) if keep_hero else n
	return Squad.footprint_hits(total, fig_cap, squad_x, lane_x(int(ob["lane"])),
		float(ob.get("width", 2.4)) * 0.5, fig_r, maxi(cap, 0), form_half)


func use_power(id: String) -> bool:
	if state != "run" or int(charges.get(id, 0)) <= 0:
		return false
	match id:
		"shield":
			if shield_t > 0.0:
				return false
			shield_t = float(powers["shield"]["duration"])
			out.append({"type": "shield_on", "dur": shield_t})
		"bomb":
			_throw_bomb()
		_:
			return false
	charges[id] = int(charges[id]) - 1
	return true


## Spec v2 §12.5: the hero throws a bomb down the squad's lane. It aims at the nearest thing
## in that lane within reach (a gang's front, or a barricade, car or barrel), else the road at
## max reach, and lands `flight` s later (_land_bombs applies the blast then).
func _throw_bomb() -> void:
	var cfg: Dictionary = powers["bomb"]
	var reach := float(cfg.get("reach", 50.0))
	var flight := float(cfg.get("flight", 0.8))
	var kind := "road"
	var ref := 0
	var z := -reach
	var land_z := -reach + S * flight   # where that point of the road will be at landing
	var h = _front_horde(reach)
	if h != null and front_z(h) < 0.0:
		kind = "horde"
		ref = h["id"]
		z = front_z(h)
		land_z = z if (h["stopped"] or h["melee"]) else z + float(h["vrel"]) * flight
	for ob in obstacles:
		var oz := float(ob["z"])
		if int(ob["lane"]) != lane or oz >= 0.0 or oz < -reach or oz <= z or not _bombable(ob):
			continue
		kind = "obstacle"
		ref = ob["id"]
		z = oz
		land_z = oz + S * flight
	var b := {"id": _new_id(), "lane": lane, "x": lane_x(lane), "land": time + flight,
		"target": kind, "ref": ref, "z": z}
	bombs.append(b)
	out.append({"type": "bomb_throw", "id": b["id"], "lane": lane, "x": b["x"], "t": flight,
		"target": kind, "ref": ref, "z": minf(land_z, contact_z)})


## A bomb can hit barricades, cars and barrels (a pothole is a hole, not a target).
static func _bombable(ob: Dictionary) -> bool:
	var kind := String(ob.get("kind", ""))
	return kind != "pothole" and (float(ob["hp"]) > 0.0 or ob.get("armed", false))


## Bombs whose flight is over explode where their target is now (the road point when the
## target is gone): gangs within the radius lose kill_pct % (the boss takes flat damage),
## barricades and cars in it are destroyed, barrels in it go off.
func _land_bombs(dt: float) -> void:
	for b in bombs:
		b["z"] = float(b["z"]) + S * dt   # the road point rides towards the squad
	for b in bombs.duplicate():
		if time < float(b["land"]):
			continue
		bombs.erase(b)
		var bz := float(b["z"])
		var target = null
		match String(b["target"]):
			"horde":
				for h in hordes:
					if int(h["id"]) == int(b["ref"]):
						target = h
						bz = front_z(h)
			"obstacle":
				for ob in obstacles:
					if int(ob["id"]) == int(b["ref"]):
						bz = float(ob["z"])
		_blast(b, bz, target)


func _blast(b: Dictionary, bz: float, target) -> void:
	var cfg: Dictionary = powers["bomb"]
	var radius := float(cfg.get("radius", 4.0))
	var killed := 0
	var hit_ids: Array = []
	for h in hordes.duplicate():
		if int(h["count"]) <= 0 or (not is_same(h, target) and absf(front_z(h) - bz) > radius):
			continue
		hit_ids.append(h["id"])
		var n: int = h["count"]
		var k := 0
		if float(h["hp"]) >= float(cfg.get("big_hp", 50)):
			# Big single targets (the boss) take flat damage instead of dying outright.
			h["acc"] = float(h["acc"]) + float(cfg.get("big_dmg", 120))
			k = mini(int(floor(float(h["acc"]) / float(h["hp"]))), n)
			h["acc"] = float(h["acc"]) - k * float(h["hp"])
		else:
			k = mini(n, maxi(n * int(cfg["kill_pct"]) / 100, int(cfg["min_kill"])))
		h["shield"] = float(h["shield"]) * 0.5
		killed += k
		_kill(h, k)
		if h["boss"] and int(h["count"]) > 0:
			_boss_hit(h, true)
	out.append({"type": "bomb", "id": b["id"], "lane": b["lane"], "x": b["x"], "z": bz, "killed": killed,
		"horde": hit_ids[0] if not hit_ids.is_empty() else -1, "target": b["target"]})
	for ob in obstacles.duplicate():
		if not _bombable(ob) or Vector2(lane_x(int(ob["lane"])) - float(b["x"]), float(ob["z"]) - bz).length() > radius:
			continue
		obstacles.erase(ob)
		if String(ob.get("kind", "")) == "barrel":
			_explode(ob)
		else:
			ob["hp"] = 0.0
			out.append({"type": "obstacle_broken", "ob": ob, "by": "bomb"})


## Brings the squad back after a loss (once per level): `troops` people (the hero plus
## constables), gangs that were on top of the squad are shoved back, and a short shield
## covers the restart. Returns false if the level isn't lost or was already revived.
func revive(troops: int) -> bool:
	if state != "lost" or revived:
		return false
	revived = true
	squad.counts["hero"] = 1
	squad.add("constable", maxi(troops, 1) - 1)
	var push := float(revive_cfg.get("push", 14.0))
	for h in hordes:
		if front_z(h) > -push:
			h["melee"] = false
			h["melee_t"] = 0.0
			h["z"] = -push + killed_rows(h) * float(h["row_gap"])
	firebombs.clear()
	shield_t = maxf(shield_t, float(revive_cfg.get("shield", 2.0)))
	state = "run"
	lose_cause = ""
	out.append({"type": "revive", "troops": squad.total()})
	return true


## How many troops a revive brings back: `pct` % of the peak squad, at least 1.
func revive_troops() -> int:
	var n := (peak_squad * int(revive_cfg.get("pct", 50)) + 99) / 100
	if squad.cap > 0:
		n = mini(n, squad.cap)
	return maxi(n, 1)


## 0 until the level is won; then 1-3 from the share of the peak squad still standing
## (level thresholds `stars: {star2, star3}` in percent, exact integer maths).
func stars() -> int:
	if state != "strike":
		return 0
	var t := squad.total()
	var p := maxi(peak_squad, 1)
	if t * 100 >= p * int(star_cfg.get("star3", 55)):
		return 3
	if t * 100 >= p * int(star_cfg.get("star2", 30)):
		return 2
	return 1


# ---------------------------------------------------------------- tick

func step(dt: float) -> void:
	if state != "run":
		return
	time += dt
	_update_speed(dt)
	traveled += S * dt
	shield_t = maxf(shield_t - dt, 0.0)
	_cool(dt)
	_armour_note_t = maxf(_armour_note_t - dt, 0.0)
	_spawn_due()
	_move(dt)
	_land_bombs(dt)
	_check_barrels()
	_shoot(dt)
	_gunfire(dt)
	if state != "run":
		return
	_return_fire(dt)
	if state != "run":
		return
	_firebombs()
	if state != "run":
		return
	_contacts(dt)
	if state != "run":
		return
	_pass_rows()
	if state != "run":
		return
	_pass_obstacles()
	if state != "run":
		return
	peak_squad = maxi(peak_squad, squad.total())
	if finish_at > 0.0 and traveled >= finish_at and hordes.is_empty() and _pending_hordes <= 0:
		state = "strike"
		out.append({"type": "finish"})


## True while the squad must plant its feet and fight: a boss within boss_halt metres, or a
## gang that stops to shoot has stopped (the street does not scroll past a standoff).
func standoff() -> bool:
	for h in hordes:
		if int(h["count"]) <= 0:
			continue
		if h["boss"] and front_z(h) >= -boss_halt:
			return true
		if h["stopped"]:
			return true
	return false


## Running speed: stop for a standoff, and stop short of the HQ while gangs live.
func _update_speed(dt: float) -> void:
	var target := S_base
	var boss := standoff()
	if boss:
		target = 0.0
	var hold := false
	if finish_at > 0.0 and (not hordes.is_empty() or _pending_hordes > 0):
		# Brake so the squad comes to rest exactly finish_hold metres before the HQ.
		var remaining := finish_at - finish_hold - traveled
		var limit := sqrt(2.0 * accel * maxf(remaining, 0.0))
		if limit < target:
			target = limit
		if S > limit:
			S = limit
		hold = remaining <= 0.05
	if S > target:
		S = maxf(target, S - 2.0 * accel * dt)
	else:
		S = minf(target, S + accel * dt)
	if S < 0.01 and target <= 0.0:
		S = 0.0
	halted = boss or hold
	# Waiting at the HQ with gangs still to come: the next one pours out now (safety net;
	# the level generator times every wave to arrive before this point).
	if hold and S <= 0.0 and _pending_hordes > 0 and hordes.is_empty():
		var pending := _pending_hordes
		while _next_spawn < _spawns.size() and _pending_hordes == pending:
			var sp: Dictionary = _spawns[_next_spawn]
			_next_spawn += 1
			_spawn_one(sp, true)


func _spawn_due() -> void:
	while _next_spawn < _spawns.size() and float(_spawns[_next_spawn]["spawn_at"]) <= traveled:
		var sp: Dictionary = _spawns[_next_spawn]
		_next_spawn += 1
		_spawn_one(sp)


func _spawn_one(sp: Dictionary, early := false) -> void:
	var ev: Dictionary = sp["ev"]
	match String(sp["kind"]):
		"gates":
			var gates: Array = []
			for g in ev.get("gates", []):
				var gate: Dictionary = (g as Dictionary).duplicate(true)
				gate["progress"] = 0.0
				if gate["op"] == "num" or gate["op"] == "pct":
					gate["v"] = int(gate.get("v", 0))
				gates.append(gate)
			var row := {"id": _new_id(), "at": sp["at"], "gates": gates, "z": 0.0,
				"slowmo": bool(ev.get("slowmo", false)), "tutorial": String(ev.get("tutorial", ""))}
			row["z"] = -(float(row["at"]) - traveled)
			rows.append(row)
			out.append({"type": "row_spawn", "row": row})
		"obstacle":
			var ob := ev.duplicate(true)
			var defaults: Dictionary = obstacle_defs.get(String(ob.get("kind", "")), {})
			for k in defaults:
				if not ob.has(k) and not String(k).begins_with("_"):
					ob[k] = defaults[k]
			ob["id"] = _new_id()
			if String(ob.get("kind", "")) == "pothole":
				ob["hp"] = 0  # can't be shot
			ob["hp_max"] = float(ob.get("hp", 10))
			ob["hp"] = ob["hp_max"]
			ob["z"] = -(float(sp["at"]) - traveled)
			obstacles.append(ob)
			out.append({"type": "obstacle_spawn", "ob": ob})
		"finish":
			out.append({"type": "finish_spawn", "at": sp["at"]})
		"hint":
			out.append({"type": "hint", "ev": ev})
		"horde":
			_pending_hordes -= 1
			_spawn_horde(sp, early)


func _spawn_horde(sp: Dictionary, early := false) -> void:
	var grp: Dictionary = sp["ev"]
	var def := enemy_def(grp)
	var speed := float(def["speed"])
	var vrel := S + speed
	var stop := float(def.get("stop_at", 0.0))
	var z := -stop - (float(sp["at"]) - traveled) * (S_base + speed) / S_base
	if early:
		z = maxf(z, -spawn_dist)
	var attack := ""
	if def.has("throw_every"):
		attack = "firebomb"
	elif def.has("aim"):
		attack = "snipe"
	elif float(def.get("shoot_every", 0.0)) > 0.0:
		attack = "gun"
	var h := {
		"id": _new_id(), "wave": sp["wave"], "enemy": grp["enemy"], "label": sp["label"],
		"count": int(grp["n"]), "start": int(grp["n"]),
		"hp": float(def["hp"]), "armour": int(def["armour"]), "power": int(def["power"]),
		"speed": speed, "vrel": vrel, "stop": stop,
		"attack": attack, "shoot_every": float(def.get("throw_every", def.get("shoot_every", 0.0))),
		"shoot_range": float(def.get("shoot_range", 0.0)),
		"shot_dmg": int(def.get("shot_dmg", 1)), "burn": int(def.get("burn", 1)),
		"flight": float(def.get("flight", 1.0)), "aim": float(def.get("aim", 0.0)), "aimed": false,
		"first_shot": float(def.get("first_shot", def.get("throw_every", def.get("shoot_every", 0.0)))),
		"boss": bool(def.get("boss", false)),
		"cols": int(def.get("cols", 9)), "row_gap": float(def.get("row_gap", 0.95)),
		"shield": 0.0, "z": z,
		"acc": 0.0, "shoot_t": 0.0, "stopped": false, "melee": false, "melee_t": 0.0,
		"hit_t": -1.0,
	}
	var mods: Dictionary = _wave_mods.get(sp["wave"], {})
	if mods.has("div"):
		h["count"] = int(floor(h["count"] / float(mods["div"])))
		h["start"] = h["count"]
	if mods.has("strip"):
		h["armour"] = 0
	var take := mini(int(mods.get("turncoat", 0)), int(h["count"]))
	if take > 0:
		mods["turncoat"] = int(mods["turncoat"]) - take
		_turn(h, take)
	h["shield"] = float(def.get("shield", 0.0)) * int(h["count"])
	# A huge gang stands in at most gang_figs figures: each carries `per` people, a row is
	# cols x per of them (killed_rows), and its front row strikes together (_contacts).
	h["per"] = maxi((int(h["start"]) + gang_figs - 1) / gang_figs, 1)
	# Return fire (spec v2 §12.2): rate per shooter, share with guns, range; 0 = never.
	var rf: Dictionary = def.get("return_fire", {})
	var on := district >= int(rf.get("from_district", rf_cfg.get("from_district", 2)))
	h["rf_rate"] = float(rf.get("rate", 0.0)) if on else 0.0
	h["rf_share"] = int(rf.get("share", 0))
	h["rf_range"] = float(rf.get("range", rf_cfg.get("range", 32.0)))
	h["rf_acc"] = 0.0
	if h["boss"]:
		h["max_hp"] = float(h["hp"]) * int(h["count"])
	if h["count"] <= 0:
		return
	hordes.append(h)
	out.append({"type": "horde_spawn", "horde": h})


func _move(dt: float) -> void:
	for row in rows:
		row["z"] = -(float(row["at"]) - traveled)
		for g in row["gates"]:
			g["z"] = row["z"]
	for ob in obstacles:
		ob["z"] = float(ob["z"]) + S * dt
	for h in hordes:
		h["vrel"] = S + float(h["speed"])
		if h["melee"]:
			# Rows behind keep walking up so the living front stays on the squad.
			h["z"] = contact_z + killed_rows(h) * float(h["row_gap"])
			continue
		if h["stopped"]:
			continue
		h["z"] = float(h["z"]) + float(h["vrel"]) * dt
		if float(h["stop"]) > 0.0 and front_z(h) >= -float(h["stop"]):
			h["z"] = -float(h["stop"]) + killed_rows(h) * float(h["row_gap"])
			h["stopped"] = true
			# They come in ready: the first volley follows `first_shot` s after they stop.
			h["shoot_t"] = maxf(float(h["shoot_every"]) - float(h["first_shot"]), 0.0)


func _shoot(dt: float) -> void:
	target_kind = ""
	target_ref = null
	snipe_ref = null
	# Snipers pick the toughest gang in range; everyone else fires down the lane.
	var which := Squad.Fire.ALL
	if squad.has_snipers(stats):
		var tough = _toughest_horde(fire_range)
		if tough != null:
			which = Squad.Fire.MAIN
			snipe_ref = tough
			var hp := float(tough["hp"])
			var n := int(tough["count"])
			var sd := squad.dps(stats, weapons, int(tough["armour"]), hp, n, Squad.Fire.SNIPE) * dt
			var sp := squad.pierce_dps(stats, weapons, hp, n, Squad.Fire.SNIPE) * dt
			_damage_horde(tough, sd, sp)
	var h = _front_horde(fire_range)
	var t = _lane_target()
	# Bullets hit whichever is nearer in the lane: the gang's front or a lane object. A gang
	# within gang_priority metres comes first, so the squad never shoots a gate while it walks in.
	var gang_first: bool = h != null and front_z(h) >= -gang_priority
	if t != null and (h == null or (float(t["z"]) > front_z(h) and not gang_first)):
		_shoot_lane(t, dt, which)
		return
	if h == null:
		return
	target_kind = "horde"
	target_ref = h
	var hp := float(h["hp"])
	var n := int(h["count"])
	var d := squad.dps(stats, weapons, int(h["armour"]), hp, n, which)
	if d <= 0.0:
		if _armour_note_t <= 0.0 and squad.dps(stats, weapons, 0, hp, n, which) > 0.0:
			_armour_note_t = 1.5
			out.append({"type": "armour_block", "horde": h["id"]})
		return
	_damage_horde(h, d * dt, squad.pierce_dps(stats, weapons, hp, n, which) * dt)


## Applies `dmg` (of which `pierce` passes riot shields) to a gang, killing whole enemies.
func _damage_horde(h: Dictionary, dmg: float, pierce: float) -> void:
	if dmg <= 0.0:
		return
	if float(h["shield"]) > 0.0:
		# Riot shields soak non-piercing fire first; piercing rounds go straight through.
		var blocked := minf(float(h["shield"]), maxf(dmg - pierce, 0.0))
		h["shield"] = float(h["shield"]) - blocked
		dmg -= blocked
		if blocked > 0.0 and float(h["shield"]) <= 0.0:
			out.append({"type": "shield_broken", "horde": h["id"]})
	var hp := float(h["hp"])
	h["acc"] = float(h["acc"]) + dmg
	var k := mini(int(floor(float(h["acc"]) / hp)), int(h["count"]))
	if k > 0:
		h["acc"] = float(h["acc"]) - k * hp
		_kill(h, k)
	if h["boss"] and int(h["count"]) > 0:
		_boss_hit(h)  # (a kill already reported the death)


## Boss health for the big bar, at most every boss_hit_every seconds (always on death or
## when forced, e.g. by a bomb).
func _boss_hit(h: Dictionary, force := false) -> void:
	var dead := int(h["count"]) <= 0
	if not force and not dead and float(h["hit_t"]) >= 0.0 and time - float(h["hit_t"]) < boss_hit_every:
		return
	h["hit_t"] = time
	out.append({"type": "boss_hit", "horde": h["id"], "hp": boss_hp(h), "max": int(h.get("max_hp", h["hp"]))})


## Remaining boss health (whole points, what the bar's number shows).
static func boss_hp(h: Dictionary) -> int:
	return maxi(int(ceil(int(h["count"]) * float(h["hp"]) - float(h["acc"]))), 0)


func _shoot_lane(t: Dictionary, dt: float, which: int) -> void:
	# One target, so no bursts or splash: hp is huge and there is a single "enemy".
	var dmg := squad.dps(stats, weapons, 0, 1000.0, 1, which) * dt
	target_ref = t
	if t.has("op"):  # a gate
		target_kind = "gate"
		t["progress"] = float(t["progress"]) + dmg
		if not t.has("step_eff"):
			t["step_eff"] = gate_step(t, dmg / dt)
		var inc := int(t.get("inc", 1))
		while int(t["v"]) < int(t["max"]):
			# The dps-scaled step only covers the climb to 0; past 0 the gate is a troop
			# offer and keeps the level's designed cost per tick.
			var step_hp := float(t["step_eff"]) if int(t["v"]) < 0 else float(t.get("step", 1.0))
			if float(t["progress"]) < step_hp:
				break
			t["progress"] = float(t["progress"]) - step_hp
			var before: int = t["v"]
			t["v"] = mini(before + inc, int(t["max"]))
			out.append({"type": "gate_tick", "gate": t, "from": before, "to": t["v"],
				"flipped": before < 0 and int(t["v"]) >= 0})
	else:  # an obstacle
		target_kind = "obstacle"
		t["hp"] = float(t["hp"]) - dmg
		if float(t["hp"]) <= 0.0:
			t["hp"] = 0.0
			if String(t.get("kind", "")) == "barrel":
				# A shot barrel is armed: it blows when the next gang's front reaches it.
				t["armed"] = true
				out.append({"type": "barrel_armed", "ob": t})
			else:
				obstacles.erase(t)
				out.append({"type": "obstacle_broken", "ob": t})


## Hits per tick of a red gate below 0, fixed when the squad first shoots it: the level's `step`,
## but never so big that this squad (firing `dps`) needs more than gate_clear_s seconds to
## shoot it up to 0. A small squad still sees it tick every few hits.
func gate_step(g: Dictionary, dps: float) -> float:
	var step_hp := float(g.get("step", 1.0))
	var v := int(g.get("v", 0))
	if v >= 0 or dps <= 0.0:
		return step_hp
	var inc := maxi(int(g.get("inc", 1)), 1)
	var ticks := int(ceil(-v / float(inc)))
	return minf(step_hp, maxf(dps * gate_clear_s / ticks, 0.01))


func _check_barrels() -> void:
	for ob in obstacles.duplicate():
		if not ob.get("armed", false):
			continue
		for h in hordes:
			if front_z(h) >= float(ob["z"]) - 0.5:
				obstacles.erase(ob)
				_explode(ob)
				break


## An armed barrel blows up the gangs whose front is within its blast radius, nearest to
## the squad first, killing up to `kill` gang members in total.
func _explode(b: Dictionary) -> void:
	var radius := float(b.get("radius", 7.0))
	var left := int(b.get("kill", 30))
	var total := 0
	var near: Array = hordes.filter(func(x): return absf(front_z(x) - float(b["z"])) <= radius)
	near.sort_custom(func(x, y): return front_z(x) > front_z(y))
	for h in near:
		h["shield"] = 0.0
		if h["boss"]:
			continue  # a barrel only singes the boss
		var k := mini(left, int(h["count"]))
		left -= k
		total += k
		_kill(h, k)
	out.append({"type": "barrel_boom", "ob": b, "killed": total})


func _kill(h: Dictionary, k: int) -> void:
	if k <= 0:
		return
	h["count"] = int(h["count"]) - k
	kills += k
	kills_by[String(h["enemy"])] = int(kills_by.get(String(h["enemy"]), 0)) + k
	out.append({"type": "kill", "horde": h["id"], "n": k, "left": h["count"]})
	if int(h["count"]) <= 0:
		if h["boss"]:
			_boss_hit(h, true)
		hordes.erase(h)
		out.append({"type": "horde_cleared", "horde": h["id"]})


func _front_horde(reach: float):
	var best = null
	for h in hordes:
		if int(h["count"]) > 0 and front_z(h) >= -reach:
			if best == null or front_z(h) > front_z(best):
				best = h
	return best


## The gang a sniper picks: bosses first, then the most hp x armour per enemy; nearest wins ties.
func _toughest_horde(reach: float):
	var best = null
	var best_v := -1.0
	for h in hordes:
		if int(h["count"]) <= 0 or front_z(h) < -reach:
			continue
		var v := INF if h["boss"] else float(h["hp"]) * (1 + int(h["armour"]))
		if best == null or v > best_v or (v == best_v and front_z(h) > front_z(best)):
			best = h
			best_v = v
	return best


## How many whole rows have been shot away from the front (a row = cols figures of `per`).
static func killed_rows(h: Dictionary) -> int:
	return (int(h["start"]) - int(h["count"])) / row_size(h)


## People in one of the gang's rows: cols figures, each carrying `per` people.
static func row_size(h: Dictionary) -> int:
	return maxi(int(h["cols"]), 1) * maxi(int(h.get("per", 1)), 1)


## Position of the frontmost living row.
static func front_z(h: Dictionary) -> float:
	return float(h["z"]) - killed_rows(h) * float(h["row_gap"])


## True while a gang is attacking from range (stopped, or a boss inside its shoot range).
static func is_attacking(h: Dictionary) -> bool:
	if String(h.get("attack", "")) == "" or h["melee"]:
		return false
	return h["stopped"] or (float(h["shoot_range"]) > 0.0 and front_z(h) >= -float(h["shoot_range"]))


func _lane_target():
	var best = null
	var best_z := -INF
	for row in rows:
		var z := float(row["z"])
		if z < -fire_range or z >= 0.0:
			continue
		for g in row["gates"]:
			if int(g["lane"]) == lane and float(g.get("step", 0.0)) > 0.0 and int(g["v"]) < int(g["max"]) and not g.get("blocked", false):
				if z > best_z:
					best = g
					best_z = z
	for ob in obstacles:
		var z := float(ob["z"])
		if int(ob["lane"]) == lane and z >= -fire_range and z < 0.0 and float(ob["hp"]) > 0.0 and z > best_z and not ob.get("armed", false):
			best = ob
			best_z = z
	return best


func _gunfire(dt: float) -> void:
	for h in hordes:
		if not is_attacking(h) or float(h["shoot_every"]) <= 0.0:
			continue
		h["shoot_t"] = float(h["shoot_t"]) + dt
		var every := float(h["shoot_every"])
		match String(h["attack"]):
			"gun":
				while float(h["shoot_t"]) >= every:
					h["shoot_t"] = float(h["shoot_t"]) - every
					if shield_t > 0.0:
						out.append({"type": "blocked", "horde": h["id"], "n": h["count"]})
					else:
						_hurt(int(h["count"]) * int(h["shot_dmg"]), String(h["enemy"]), h["id"])
					if state != "run":
						return
			"firebomb":
				while float(h["shoot_t"]) >= every:
					h["shoot_t"] = float(h["shoot_t"]) - every
					var fb := {"horde": h["id"], "lane": lane, "land": time + float(h["flight"]),
						"burn": int(h["count"]) * int(h["burn"])}
					firebombs.append(fb)
					out.append({"type": "firebomb_throw", "horde": h["id"], "lane": lane, "t": float(h["flight"])})
			"snipe":
				if not h["aimed"] and float(h["shoot_t"]) >= every - float(h["aim"]):
					h["aimed"] = true
					out.append({"type": "snipe_aim", "horde": h["id"]})
				while float(h["shoot_t"]) >= every:
					h["shoot_t"] = float(h["shoot_t"]) - every
					h["aimed"] = false
					var lost := 0
					var blocked := shield_t > 0.0
					if not blocked:
						lost = _hurt(int(h["count"]) * int(h["shot_dmg"]), String(h["enemy"]), h["id"], false)
					out.append({"type": "snipe", "horde": h["id"], "lost": lost, "blocked": blocked})
					if state != "run":
						return


## Gangs with guns fire back while their front is within range (spec v2 §12.2): every
## shooter (share % of the gang, rounded up) fires rf_rate shots/s; each hit kills one troop,
## lowest rank first, so the hero falls last. The shield blocks it. One event per gang and
## tick with the shots fired, so the view draws the muzzle flashes and tracers.
func _return_fire(dt: float) -> void:
	for h in hordes:
		if float(h.get("rf_rate", 0.0)) <= 0.0 or h["melee"] or int(h["count"]) <= 0:
			continue
		if front_z(h) < -float(h["rf_range"]):
			continue
		h["rf_acc"] = float(h["rf_acc"]) + float(shooters(h)) * float(h["rf_rate"]) * dt
		var shots := int(floor(float(h["rf_acc"])))
		if shots <= 0:
			continue
		h["rf_acc"] = float(h["rf_acc"]) - shots
		var blocked := shield_t > 0.0
		var lost := 0
		if not blocked:
			lost = _hurt(shots, String(h["enemy"]), h["id"], false)
		out.append({"type": "return_fire", "horde": h["id"], "shots": shots, "lost": lost, "blocked": blocked})
		if state != "run":
			return


## How many of a gang carry guns: its rf_share percent, rounded up (0 when it has none).
static func shooters(h: Dictionary) -> int:
	return (int(h["count"]) * int(h.get("rf_share", 0)) + 99) / 100


## Firebombs land in the lane they were thrown at; the squad burns only if it is still there.
func _firebombs() -> void:
	for fb in firebombs.duplicate():
		if time < float(fb["land"]):
			continue
		firebombs.erase(fb)
		var blocked := shield_t > 0.0 and int(fb["lane"]) == lane
		var lost := 0
		if int(fb["lane"]) == lane and not blocked:
			lost = _hurt(int(fb["burn"]), "molotov", int(fb["horde"]), false)
		out.append({"type": "firebomb_hit", "horde": fb["horde"], "lane": fb["lane"], "lost": lost, "blocked": blocked})
		if state != "run":
			return


func _contacts(dt: float) -> void:
	for h in hordes.duplicate():
		if not h["melee"]:
			if front_z(h) < contact_z:
				continue
			h["melee"] = true
			h["melee_t"] = 0.0
			out.append({"type": "melee_start", "horde": h["id"]})
		h["melee_t"] = float(h["melee_t"]) - dt
		if float(h["melee_t"]) > 0.0:
			continue
		h["melee_t"] = melee_tick
		# The front row strikes: each enemy takes `power` troops and falls.
		var row := mini(row_size(h), int(h["count"]))
		var power := row * int(h["power"])
		var lost := 0
		if shield_t <= 0.0:
			lost = _hurt(power, String(h["enemy"]), h["id"], false)
		out.append({"type": "melee", "horde": h["id"], "enemies": row, "lost": lost, "shielded": shield_t > 0.0})
		if h["boss"]:
			continue  # the boss keeps swinging: he never falls to his own strike
		_kill(h, row)
		if state != "run":
			return


func _hurt(n: int, cause: String, source_id: int = 0, announce: bool = true) -> int:
	var lost := squad.lose(n)
	if announce and lost > 0:
		out.append({"type": "hurt", "n": lost, "cause": cause, "source": source_id})
	if not squad.hero_alive() and state == "run":
		state = "lost"
		lose_cause = cause
		out.append({"type": "lost", "cause": cause, "source": source_id})
	return lost


func _pass_rows() -> void:
	for row in rows.duplicate():
		if float(row["z"]) < 0.0:
			continue
		rows.erase(row)
		rows_passed += 1
		var picked = null
		for g in row["gates"]:
			if int(g["lane"]) == lane:
				picked = g
		var before := squad.total()
		var delta := 0
		var blocked: bool = picked != null and picked.get("blocked", false)
		if picked != null and not blocked:
			delta = _apply_gate(picked)
		peak_squad = maxi(peak_squad, squad.total())
		out.append({"type": "row_pass", "row": row, "gate": picked, "before": before,
			"after": squad.total(), "delta": delta, "blocked": blocked})
		if picked != null and not squad.hero_alive():
			state = "lost"
			lose_cause = "gate"
			out.append({"type": "lost", "cause": "gate"})
			return


func _apply_gate(g: Dictionary) -> int:
	match String(g["op"]):
		"num":
			var v: int = g["v"]
			return squad.add("constable", v) if v >= 0 else -squad.lose(-v)
		"recruit":
			var unit := String(g["unit"])
			var added := squad.add(unit, int(g.get("n", 1)))
			out.append({"type": "rank_join", "unit": unit, "n": added, "first_time": not _joined.has(unit)})
			_joined[unit] = true
			return added
		"mul":
			return squad.multiply(int(g["k"]))
		"div":
			return squad.divide(int(g["k"]))
		"pct":
			return squad.apply_percent(int(g["v"]))
		"weapon":
			squad.hero_weapon = String(g["id"])
			return 0
		"power":
			var id := String(g["id"])
			charges[id] = int(charges.get(id, 0)) + int(g.get("n", 1))
			return 0
		"foe_div", "foe_strip", "turncoat":
			var before := squad.total()
			_apply_foe_mod(g)
			return squad.total() - before
	return 0


## Moves `k` gang members from the front of `h` into the squad as constables.
func _turn(h: Dictionary, k: int) -> void:
	h["count"] = int(h["count"]) - k
	h["start"] = int(h["start"]) - k
	squad.add("constable", k)
	out.append({"type": "turncoat", "horde": h["id"], "n": k})


func _apply_foe_mod(g: Dictionary) -> void:
	var wave := -1
	for i in _wave_ats.size():
		if float(_wave_ats[i]) > traveled:
			wave = i
			break
	if wave < 0:
		return
	var mods: Dictionary = _wave_mods.get(wave, {})
	var spawned: Array = hordes.filter(func(x): return int(x["wave"]) == wave)
	match String(g["op"]):
		"foe_div":
			mods["div"] = int(g["k"])
		"foe_strip":
			mods["strip"] = true
		"turncoat":
			# Converts from the gangs of that wave already on screen; the rest applies at spawn.
			var left := int(g.get("n", 5))
			for h in spawned:
				if h["boss"]:
					continue  # the Kingpin never switches sides
				var k := mini(left, int(h["count"]))
				if k > 0:
					_turn(h, k)
					left -= k
			if left > 0:
				mods["turncoat"] = int(mods.get("turncoat", 0)) + left
			_wave_mods[wave] = mods
			for h in hordes.duplicate():
				if int(h["count"]) <= 0:
					hordes.erase(h)
					out.append({"type": "horde_cleared", "horde": h["id"]})
			return
	_wave_mods[wave] = mods
	for h in spawned:
		var before: int = h["count"]
		if g["op"] == "foe_div":
			if h["boss"]:
				continue  # bosses are one person; halving is for crowds
			var killed := int(h["start"]) - before
			h["count"] = int(floor(before / float(g["k"])))
			h["start"] = int(h["count"]) + killed  # halved from the back; the front stays put
			h["shield"] = float(h["shield"]) / float(g["k"])
		else:
			h["armour"] = 0
		out.append({"type": "foe_mod", "horde": h["id"], "op": g["op"], "from": before, "to": h["count"]})
	for h in hordes.duplicate():
		if int(h["count"]) <= 0:
			hordes.erase(h)
			out.append({"type": "horde_cleared", "horde": h["id"]})


func _pass_obstacles() -> void:
	for ob in obstacles.duplicate():
		if float(ob["z"]) < 0.0:
			continue
		obstacles.erase(ob)
		var kind := String(ob.get("kind", "barricade"))
		var solid: bool = kind == "pothole" or (float(ob["hp"]) > 0.0 and not ob.get("armed", false))
		var hit := {}
		if solid:
			# Spatial: only the troops standing on its footprint, up to its number. The hero
			# always hops a pothole, so a pothole never ends the level.
			hit = obstacle_hits(ob, obstacle_cost(ob), kind == "pothole")
		if hit.is_empty() or int(hit["lost"]) <= 0:
			out.append({"type": "obstacle_pass", "ob": ob})
			continue
		var lost := _hurt(int(hit["lost"]), kind, ob["id"], false)
		var ev := {"type": "obstacle_hit", "ob": ob, "lost": lost, "slots": hit["slots"],
			"figures": hit["figures"], "x": squad_x}
		if kind == "pothole":
			out.append({"type": "pothole_pass", "id": ob["id"], "lane": ob["lane"], "lost": lost, "ob": ob})
		elif kind == "barricade":
			var g = _block_next_gate(int(ob["lane"]), float(ob.get("block_reach", 12.0)))
			out.append({"type": "barricade_hit", "id": ob["id"], "lane": ob["lane"], "lost": lost,
				"ob": ob, "blocked_gate": g})
		out.append(ev)
		if state != "run":
			return


## The most troops an obstacle can take (the number shown on it): `fall`/`dmg`, or
## `fall_pct`/`dmg_pct` % of the squad right now.
func obstacle_cost(ob: Dictionary) -> int:
	if String(ob.get("kind", "")) == "pothole":
		if ob.has("fall_pct"):
			return squad.total() * int(ob["fall_pct"]) / 100
		return int(ob.get("fall", 0))
	if ob.has("dmg_pct"):
		return squad.total() * int(ob["dmg_pct"]) / 100
	return int(ob.get("dmg", 5))


## A barricade you crash through wrecks the gate right behind it in that lane (within reach).
## Returns that gate (now `blocked`) or null.
func _block_next_gate(l: int, reach: float):
	var best = null
	var best_z := -INF
	for row in rows:
		var z := float(row["z"])
		if z >= 0.0 or z < -reach:
			continue
		for g in row["gates"]:
			if int(g["lane"]) == l and not g.get("blocked", false) and z > best_z:
				best = g
				best_z = z
	if best != null:
		best["blocked"] = true
	return best


func _new_id() -> int:
	_next_id += 1
	return _next_id


# ---------------------------------------------------------------- helpers

func progress() -> float:
	return clampf(traveled / finish_at, 0.0, 1.0) if finish_at > 0.0 else 0.0


func drain() -> Array:
	var e := out
	out = []
	return e


## A deep copy that plays on independently (route search in tests/tune.gd).
func clone() -> LevelSim:
	var c := LevelSim.new()
	for p in ["S", "S_base", "accel", "fire_range", "spawn_dist", "contact_z", "melee_tick",
			"boss_halt", "finish_hold", "boss_hit_every", "weapons", "enemy_defs", "obstacle_defs",
			"powers", "rf_cfg", "revive_cfg", "star_cfg", "lane", "squad_x", "_x_driven", "lane_w", "form_half",
			"fig_cap", "fig_r", "gate_clear_s", "gang_priority", "gang_figs", "district", "caps",
			"tap_heat", "tap_auto", "tap_per",
			"tap_hold_s", "tap_decay_s", "_tap_hold", "traveled", "time", "state", "lose_cause",
			"finish_at", "halted", "peak_squad", "revived", "shield_t", "kills", "rows_passed",
			"_spawns", "_next_spawn", "_pending_hordes", "_wave_ats", "_next_id", "_armour_note_t"]:
		c.set(p, get(p))
	c.stats = stats
	c.squad = squad.duplicate_squad()
	c.rows = rows.duplicate(true)
	c.obstacles = obstacles.duplicate(true)
	c.hordes = hordes.duplicate(true)
	c.firebombs = firebombs.duplicate(true)
	c.bombs = bombs.duplicate(true)
	c.charges = charges.duplicate()
	c._wave_mods = _wave_mods.duplicate(true)
	c._joined = _joined.duplicate()
	return c


static func strike_coins(economy: Dictionary, troops: int, mult: int) -> int:
	return int(economy["clear_bonus"]) + troops * mult
