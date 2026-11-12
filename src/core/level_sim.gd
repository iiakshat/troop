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
## frontmost *living* row. Its body only hurts the squad once that front physically reaches
## it; then the gang fights row by row (melee), each enemy taking `power` troops and dying.
##
## Enemies fight back before they die (spec v2.1 §1), and every attack is a capped share of
## the squad, so nothing wipes a decent squad in one go:
## - Return fire (_return_fire): gangs with guns (gunmen always, thugs and bikers from
##   district 2) outrange the squad, open with a volley on entering range, and each hit takes
##   one visible figure's worth of troops; one volley never takes more than a few percent.
## - Specials (_gunfire): snipers, grenadiers and molotovs mark the squad's lane from beyond
##   its reach (`telegraph`) and the attack lands warn_s later (`attack_land`, _land_attacks):
##   only if the squad still stands in that lane then, and the shield blocks it.
## - Bosses and lieutenants (_boss_fire): a squad-relative gun (`boss_shot`) and, from the
##   halt, a telegraphed lane barrage every few seconds.
## A telegraph lands only in live play: the clock stops with the street (pause, lessons), and
## one still in the air when the squad falls or bursts into the stash is called off.
## The player's bomb is thrown and lands later (_throw_bomb, _land_bombs). Counts are exact
## ints; a huge gang fights in capped rows.

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
var coin_ref := 0          # the level's stored route's finishing squad (coin_troops), 0 = none

## Tap-to-fire: the hero fires at lerp(tap_auto, 1, tap_heat) of his rate (units.hero.tap).
var tap_heat := 0.0        # 0..1; each tap() adds tap_per, held tap_hold_s, then drains over tap_decay_s
var tap_auto := 1.0
var tap_per := 1.0
var tap_hold_s := 0.0
var tap_decay_s := 1.0
var _tap_hold := 0.0       # seconds left before the heat starts to drain
var tap_coin_pct := 0.0    # hero.tap.coin_pct: Bottle Shot coins + this % x the level's mean heat
var heat_sum := 0.0        # tap heat integrated over the run (heat x seconds)
var heat_t := 0.0          # seconds of run the mean heat is taken over

var stats: Dictionary   # effective ally stats after upgrades
var weapons: Dictionary
var enemy_defs: Dictionary
var obstacle_defs: Dictionary
var powers: Dictionary
var rf_cfg: Dictionary     # units.return_fire: from_district, range, open, caps
var boss_cfg: Dictionary   # units.boss: the district boss's barrage and gun
var lt_cfg: Dictionary     # units.lieutenant: the same for the mini-boss
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
var attacks: Array = []     # telegraphed enemy attacks in the air: {id, kind, lane, src, land, base, pct, cause, x, z}
var bombs: Array = []       # the squad's bombs in the air: {id, lane, x, land, target, ref, z}
var cages: Array = []       # hostage cages on the road: {id, at, lane, hostages, unit, z, guard, open}
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
var _enemy_hints: Array = []     # enemy "new" hints waiting for their gang to come in range
var _hints_done: Dictionary = {} # hint id -> true once reported


func _init(level: Dictionary = {}, units_cfg: Dictionary = {}, upgrades: Dictionary = {}) -> void:
	if units_cfg.is_empty():
		return  # clone() fills the fields
	var w: Dictionary = units_cfg["world"]
	# Spec v2.1 §4.1: a level may run at its own pace (Rush: 1.2x), else the world's.
	S_base = float(level.get("scroll_speed", w["scroll_speed"]))
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
	coin_ref = maxi(int(level.get("coin_ref", 0)), 0)
	var tap: Dictionary = units_cfg.get("hero", {}).get("tap", {})
	tap_auto = float(tap.get("auto_rate", tap_auto))
	tap_per = float(tap.get("per_tap", tap_per))
	tap_hold_s = float(tap.get("hold_s", tap_hold_s))
	tap_decay_s = maxf(float(tap.get("decay_s", tap_decay_s)), 0.001)
	tap_coin_pct = maxf(float(tap.get("coin_pct", 0.0)), 0.0)
	stats = units_cfg["allies"].duplicate(true)
	weapons = units_cfg["hero_weapons"]
	enemy_defs = units_cfg["enemies"]
	obstacle_defs = units_cfg.get("obstacles", {})
	powers = units_cfg["powers"]
	rf_cfg = units_cfg.get("return_fire", {})
	boss_cfg = units_cfg.get("boss", {})
	lt_cfg = units_cfg.get("lieutenant", {})
	revive_cfg = units_cfg.get("revive", {})
	star_cfg = level.get("stars", units_cfg.get("stars", {}))

	var hero: Dictionary = stats["hero"]
	hero["dmg"] = float(hero["dmg"]) + float(upgrades.get("knife", 0))
	hero["rate"] = float(hero["rate"]) + 0.5 * float(upgrades.get("speed", 0))
	# Armory (v2): each owner's weapon multiplies its dmg and rate (Armory.sim_upgrades);
	# troop counts never change. The hero's PISTOL pickup (hero_weapons) is not on a track.
	var wup: Dictionary = upgrades.get("weapons", {})
	for owner in wup:
		if stats.has(owner) and wup[owner] is Dictionary:
			var u: Dictionary = stats[owner]
			u["dmg"] = float(u["dmg"]) * float(wup[owner].get("dmg_mult", 1.0))
			u["rate"] = float(u["rate"]) * float(wup[owner].get("rate_mult", 1.0))
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
	# A hero-alone opening (levels 2-3) starts half warm (gen_levels.py START_HEAT).
	tap_heat = clampf(float(level.get("start_heat", 0.0)), 0.0, 1.0)
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
## A calibrated level carries `coin_ref` (its stored route's finishing squad): finishing with
## that many pays like a full district-1 squad, because most levels end far below the cap
## (never more than the cap rule's most, a full squad with the barracks' extra).
func coin_troops() -> int:
	if caps.size() < district:
		return squad.total()
	var dcap := maxi(int(caps[district - 1]), 1)
	if coin_ref <= 0:
		return squad.total() * int(caps[0]) / dcap
	return mini(squad.total() * int(caps[0]) / coin_ref, int(caps[0]) * squad.cap / dcap)


# ---------------------------------------------------------------- tap heat

## One tap on the fire zone: the hero heats up (spec v2 section 2).
func tap() -> void:
	tap_heat = minf(tap_heat + tap_per, 1.0)
	_tap_hold = tap_hold_s
	squad.hero_rate = hero_rate_mult()


## The squad's live firepower (Squad.firepower with the current upgrades and tap heat), as
## the whole number the HUD shows next to the troop count.
func firepower() -> int:
	return int(round(live_power()))


## The same number unrounded: the HUD shows it with Economy.fmt_power, the lobby's format.
func live_power() -> float:
	return squad.firepower(stats, weapons)


## Firepower at the start of a level with these upgrades and the hero at full tap rate: the
## same unit as the HUD's lightning number and the lobby's Squad Power (Economy.squad_power,
## the same Squad.firepower; spec v2 §12.4, "same unit everywhere").
static func start_firepower(units_cfg: Dictionary, upgrades: Dictionary = {}, level: Dictionary = {}) -> float:
	var lv := level.duplicate()
	lv["events"] = []
	var sim := LevelSim.new(lv, units_cfg, upgrades)
	sim.squad.hero_rate = 1.0
	return sim.live_power()


## Share of the hero's base rate he fires at now: tap_auto when cold, 1.0 when hot.
func hero_rate_mult() -> float:
	return lerpf(tap_auto, 1.0, tap_heat)


## The level's mean tap heat (0..1) so far: how hard the player tapped, start to finish.
func mean_heat() -> float:
	return clampf(heat_sum / heat_t, 0.0, 1.0) if heat_t > 0.0 else 0.0


## Spec v2 §2, "tapping adds finale coins": the whole-percent coin bonus this run earned
## (hero.tap.coin_pct x the mean heat). Bottle Shot adds it to the station's coin bonus.
func tap_coin_bonus_pct() -> int:
	return int(round(tap_coin_pct * mean_heat()))


func _cool(dt: float) -> void:
	heat_sum += tap_heat * dt
	heat_t += dt
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
			"cage":
				# A hostage cage rides the road with its guards standing in front of it (_spawn_cage).
				_spawns.append({"kind": "cage", "ev": e, "at": at, "spawn_at": at - spawn_dist})
				_pending_hordes += 1
			"finish":
				finish_at = at
				_spawns.append({"kind": "finish", "ev": e, "at": at, "spawn_at": at - spawn_dist})
			"hint":
				_spawns.append({"kind": "hint", "ev": e, "at": at, "spawn_at": at})
				if e.has("enemy"):
					_enemy_hints.append({"ev": e, "enemy": String(e["enemy"])})
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


## The lane the squad really stands in now: the lane nearest its x (the view's steering in
## play; the lane centre in autoplay). Telegraphs aim at it and land on it (spec v2.1 §1.2).
func squad_lane() -> int:
	return clampi(int(round(squad_x / lane_w)) + 1, 0, 2)


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
			if not can_throw_bomb():
				return false
			_throw_bomb()
		_:
			return false
	charges[id] = int(charges[id]) - 1
	return true


## Seconds from the tap to the blast: the hero's wind-up (the throw clip until the bomb
## leaves his hand) plus the flight.
func bomb_time() -> float:
	var cfg: Dictionary = powers["bomb"]
	return float(cfg.get("windup", 0.0)) + float(cfg.get("flight", 0.8))


## One bomb at a time (a second tap while one is in the air is ignored and spends nothing),
## and none that would still be in the air when the squad bursts into the stash: with no gang
## left the street runs on to the finish (Bottle Shot never sees a bomb).
func can_throw_bomb() -> bool:
	if state != "run" or not bombs.is_empty():
		return false
	if finish_at > 0.0 and hordes.is_empty() and _pending_hordes <= 0:
		return traveled + S_base * bomb_time() < finish_at
	return true


## Spec v2 §12.5: the hero throws a bomb down the squad's lane. It aims at the nearest thing
## in that lane that is within reach when it lands (a gang's front, or a barricade, car or
## barrel the squad will not have reached by then), else the road at max reach. It lands
## windup + flight s after the tap (_land_bombs applies the blast then).
func _throw_bomb() -> void:
	var cfg: Dictionary = powers["bomb"]
	var reach := float(cfg.get("reach", 50.0))
	var total := bomb_time()
	var kind := "road"
	var ref := 0
	var z := -reach - S * total   # the road point that is at max reach when the bomb lands
	var land_z := -reach
	var best = null
	for h in hordes:
		if int(h["count"]) <= 0 or front_z(h) >= 0.0:
			continue
		var hz := front_z(h)
		var lz := hz if (h["stopped"] or h["melee"]) else minf(hz + float(h["vrel"]) * total, contact_z)
		if lz >= -reach and (best == null or hz > front_z(best)):
			best = h
			land_z = lz
	if best != null:
		kind = "horde"
		ref = best["id"]
		z = front_z(best)
	for ob in obstacles:
		var oz := float(ob["z"])
		if int(ob["lane"]) != lane or oz >= 0.0 or not _bombable(ob):
			continue
		var lz := oz + S * total
		# Out of reach at landing, or the squad gets there before the bomb does.
		if lz < -reach or lz >= contact_z or oz <= z:
			continue
		kind = "obstacle"
		ref = ob["id"]
		z = oz
		land_z = lz
	var b := {"id": _new_id(), "lane": lane, "x": lane_x(lane), "land": time + total,
		"target": kind, "ref": ref, "z": z}
	bombs.append(b)
	out.append({"type": "bomb_throw", "id": b["id"], "lane": lane, "x": b["x"], "t": total,
		"windup": float(cfg.get("windup", 0.0)), "target": kind, "ref": ref,
		"z": minf(land_z, contact_z), "radius": float(cfg.get("radius", 4.0))})


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
	var boss_dmg := 0
	var hit_ids: Array = []
	for h in hordes.duplicate():
		if int(h["count"]) <= 0 or (not is_same(h, target) and absf(front_z(h) - bz) > radius):
			continue
		hit_ids.append(h["id"])
		var n: int = h["count"]
		var k := 0
		if float(h["hp"]) >= float(cfg.get("big_hp", 50)):
			# Big single targets take flat damage instead of dying outright; a boss loses
			# big_pct % of its full health (at least big_dmg), so a late boss feels it too.
			var dmg := int(cfg.get("big_dmg", 120))
			if h["boss"]:
				dmg = maxi(dmg, int(h.get("max_hp", h["hp"])) * int(cfg.get("big_pct", 0)) / 100)
				boss_dmg += dmg
			h["acc"] = float(h["acc"]) + float(dmg)
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
		"horde": hit_ids[0] if not hit_ids.is_empty() else -1, "target": b["target"], "boss_dmg": boss_dmg,
		"radius": radius})
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
	_end_attacks()  # (already called off when the squad fell; a safety net)
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
	_land_attacks()
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
	_pass_cages()
	peak_squad = maxi(peak_squad, squad.total())
	_enemy_hints_due()
	if finish_at > 0.0 and traveled >= finish_at and hordes.is_empty() and _pending_hordes <= 0:
		# Safety net (can_throw_bomb keeps this rare): a bomb still in the air goes off now,
		# before the squad bursts into the stash, so Bottle Shot never sees it.
		for b in bombs.duplicate():
			bombs.erase(b)
			_blast(b, float(b["z"]), null)
		_end_attacks()  # nothing lands after the finish
		state = "strike"
		out.append({"type": "finish"})


## Enemy "new" hints show when the first gang of that kind comes within fire_range + 10 m
## (its numbers are on the street then), not by distance travelled: a boss halts the street
## before its wave's `at`, and a strong squad kills a gang at range before it. The reported
## event carries that gang's id (`horde`): its marker stays on it (spec v2.1 §6.1).
func _enemy_hints_due() -> void:
	for eh in _enemy_hints.duplicate():
		for h in hordes:
			# A lieutenant is a boss group with his own hint ("lieutenant"), never the boss's.
			var kind := "lieutenant" if h.get("lieutenant", false) else String(h["enemy"])
			if kind == String(eh["enemy"]) and int(h["count"]) > 0 and front_z(h) >= -(fire_range + 10.0):
				_enemy_hints.erase(eh)
				var ev: Dictionary = (eh["ev"] as Dictionary).duplicate()
				ev["horde"] = h["id"]
				_report_hint(ev)
				break


func _report_hint(ev: Dictionary) -> void:
	var id := String(ev.get("id", ""))
	if id != "" and _hints_done.has(id):
		return
	_hints_done[id] = true
	out.append({"type": "hint", "ev": ev})


## True while the squad must plant its feet and fight: a boss within boss_halt metres, or a
## gang that stops to shoot has stopped within the squad's reach (the street does not scroll
## past a standoff). A gang stopped beyond fire_range never halts it: the street carries the
## squad to it (_move), so it cannot hold the level forever (spec v2.1 §1.2).
func standoff() -> bool:
	for h in hordes:
		if int(h["count"]) <= 0:
			continue
		if h["boss"] and front_z(h) >= -boss_halt:
			return true
		if h["stopped"] and front_z(h) >= -fire_range:
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
			# The distance is the fallback; an enemy hint usually went out when its gang came in.
			_enemy_hints = _enemy_hints.filter(func(x): return not is_same(x["ev"], ev))
			_report_hint(ev)
		"horde":
			_pending_hordes -= 1
			_spawn_horde(sp, early)
		"cage":
			_pending_hordes -= 1
			_spawn_cage(sp)


func _spawn_horde(sp: Dictionary, early := false) -> void:
	var grp: Dictionary = sp["ev"]
	var def := enemy_def(grp)
	var speed := float(def["speed"])
	var vrel := S + speed
	var stop := float(def.get("stop_at", 0.0))
	var z := -stop - (float(sp["at"]) - traveled) * (S_base + speed) / S_base
	if early:
		z = maxf(z, -spawn_dist)
	# Spec v2.1 §1.2: a special (an `attack` in units.json) telegraphs from attack.start_m on;
	# a boss shoots his gun within shoot_range and barrages from the halt (_boss_fire).
	var atk: Dictionary = def.get("attack", {})
	var boss := bool(def.get("boss", false))
	var attack := ""
	var shoot_range := float(def.get("shoot_range", 0.0))
	if not atk.is_empty():
		attack = String(atk.get("kind", ""))
		shoot_range = float(atk.get("start_m", shoot_range))
	elif boss:
		attack = "gun"
	var every := float(def.get("throw_every", def.get("shoot_every", 0.0)))
	var first := float(def.get("first_shot", every))
	var h := {
		"id": _new_id(), "wave": sp["wave"], "enemy": grp["enemy"], "label": sp["label"],
		"count": int(grp["n"]), "start": int(grp["n"]),
		"hp": float(def["hp"]), "armour": int(def["armour"]), "power": int(def["power"]),
		"speed": speed, "vrel": vrel, "stop": stop,
		"attack": attack, "shoot_every": every, "shoot_range": shoot_range,
		"shot_dmg": int(def.get("shot_dmg", 1)), "burn": int(def.get("burn", 1)),
		# per member: what one landed attack costs before the cap (count x hit), the cap, the warning
		"hit": int(def.get("burn", def.get("shot_dmg", 1))), "cap_pct": int(atk.get("cap_pct", 0)),
		"warn": float(atk.get("warn_s", 1.0)),
		"first_shot": first,
		"boss": boss, "lieutenant": boss and bool(grp.get("lieutenant", false)), "bt": -1.0,
		"cols": int(def.get("cols", 9)), "row_gap": float(def.get("row_gap", 0.95)),
		"shield": 0.0, "z": z,
		# the first attack comes first_shot s after it starts attacking (in range or stopped)
		"acc": 0.0, "shoot_t": maxf(every - first, 0.0), "stopped": false, "melee": false, "melee_t": 0.0,
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
	# Return fire (spec v2.1 §1.1): rate per shooter, share with guns (at most the district's
	# max_shooters), range; 0 = never. The opening volley goes out on first entering range.
	var rf: Dictionary = def.get("return_fire", {})
	var on := district >= int(rf.get("from_district", rf_cfg.get("from_district", 2)))
	h["rf_rate"] = float(rf.get("rate", 0.0)) if on else 0.0
	h["rf_share"] = int(rf.get("share", 0))
	h["rf_range"] = float(rf.get("range", rf_cfg.get("range", 50.0)))
	h["rf_max"] = int(_by_district(rf_cfg.get("max_shooters", 1 << 30)))
	h["rf_open"] = false
	h["rf_acc"] = 0.0
	if h["boss"]:
		h["max_hp"] = float(h["hp"]) * int(h["count"])
	if h["count"] <= 0:
		return
	hordes.append(h)
	out.append({"type": "horde_spawn", "horde": h, "lieutenant": h["lieutenant"]})


## A per-district config number: v[district - 1] of an array (its last entry past the end),
## or v itself.
func _by_district(v) -> Variant:
	if v is Array:
		var a: Array = v
		return a[clampi(district, 1, a.size()) - 1] if not a.is_empty() else 0
	return v


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
			if front_z(h) < -fire_range:
				# Stopped beyond the squad's reach: it stands on the street, which carries the
				# squad to it (no standoff out there, spec v2.1 §1.2).
				h["z"] = float(h["z"]) + S * dt
			continue
		h["z"] = float(h["z"]) + float(h["vrel"]) * dt
		if float(h["stop"]) > 0.0 and front_z(h) >= -float(h["stop"]):
			h["z"] = -float(h["stop"]) + killed_rows(h) * float(h["row_gap"])
			h["stopped"] = true
			# (Its attack clock started at spawn and runs while it attacks: the first one comes
			# first_shot s after it starts, in range or stopped.)


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
	# within gang_priority metres comes first, so the squad never shoots a gate while it walks in;
	# so does any gang while one is firing at the squad (stopped gunmen stand outside that reach
	# and halt the street, so a nearer red gate would otherwise soak the fire forever).
	var gang_first: bool = h != null and (front_z(h) >= -gang_priority or _under_fire())
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
func _explode(b: Dictionary, extra: Dictionary = {}) -> void:
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
	var ev := {"type": "barrel_boom", "ob": b, "killed": total}
	ev.merge(extra)
	out.append(ev)


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


## True while a gang's guns reach the squad (spec v2 §12.2 return fire: carries guns, front
## within its range, not in melee).
static func fires_back(h: Dictionary) -> bool:
	return float(h.get("rf_rate", 0.0)) > 0.0 and not h["melee"] and int(h["count"]) > 0 \
		and shooters(h) > 0 and front_z(h) >= -float(h.get("rf_range", 0.0))


## True while any gang is shooting at the squad (return fire or a ranged attack).
func _under_fire() -> bool:
	for h in hordes:
		if int(h["count"]) > 0 and (fires_back(h) or is_attacking(h)):
			return true
	return false


## True while a gang is attacking from range: stopped, or its front inside its shoot_range (a
## special's attack.start_m, a boss's gun range).
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


## Ranged attacks (spec v2.1 §1.2-1.3). A special gang that is attacking (front within
## attack.start_m, or stopped) marks the squad's lane every shoot_every s: a `telegraph` that
## lands warn_s later (_land_attacks), costing count x hit troops capped at cap_pct % of the
## squad. Bosses and lieutenants: _boss_fire.
func _gunfire(dt: float) -> void:
	for h in hordes.duplicate():
		if int(h["count"]) <= 0 or h["melee"]:
			continue
		if h["boss"]:
			_boss_fire(h, dt)
		elif is_attacking(h) and float(h["shoot_every"]) > 0.0:
			h["shoot_t"] = float(h["shoot_t"]) + dt
			var every := float(h["shoot_every"])
			while float(h["shoot_t"]) >= every:
				h["shoot_t"] = float(h["shoot_t"]) - every
				_telegraph(String(h["attack"]), int(h["id"]), float(h["warn"]),
					int(h["count"]) * int(h["hit"]), int(h["cap_pct"]), String(h["enemy"]))
		if state != "run":
			return


## The boss's (or lieutenant's) numbers: units.boss, or units.lieutenant for a lieutenant.
func boss_numbers(h: Dictionary) -> Dictionary:
	return lt_cfg if h.get("lieutenant", false) else boss_cfg


## A boss or lieutenant (spec v2.1 §1.3). His gun, every shoot_every s within shoot_range,
## takes gun_pct % of the squad (`boss_shot`, shield blocks it). From the halt (front within
## boss_halt) he marks the squad's lane barrage_first s later and then every barrage_every s;
## the barrage lands warn_s later and takes barrage_pct % of the squad if it is still there.
func _boss_fire(h: Dictionary, dt: float) -> void:
	var cfg := boss_numbers(h)
	if is_attacking(h) and float(h["shoot_every"]) > 0.0:
		h["shoot_t"] = float(h["shoot_t"]) + dt
		var every := float(h["shoot_every"])
		while float(h["shoot_t"]) >= every:
			h["shoot_t"] = float(h["shoot_t"]) - every
			var blocked := shield_t > 0.0
			var lost := 0
			if not blocked:
				var n := _spare_hero(share_loss(squad.total(), int(cfg.get("gun_pct", 0))))
				if n > 0:
					lost = _hurt(n, "boss", h["id"], false)
			out.append({"type": "boss_shot", "horde": h["id"], "lost": lost, "blocked": blocked})
			if state != "run":
				return
	var bevery := float(cfg.get("barrage_every", 0.0))
	if bevery <= 0.0 or front_z(h) < -boss_halt:
		return
	if float(h["bt"]) < 0.0:
		h["bt"] = maxf(bevery - float(cfg.get("barrage_first", 1.0)), 0.0)
	h["bt"] = float(h["bt"]) + dt
	while float(h["bt"]) >= bevery:
		h["bt"] = float(h["bt"]) - bevery
		_telegraph("lt_barrage" if h["lieutenant"] else "barrage", int(h["id"]), float(cfg.get("warn_s", 1.0)),
			-1, int(_by_district(cfg.get("barrage_pct", 0))), "boss")


## Marks the squad's lane (where it stands now) for an attack landing `warn` s later:
## `base` troops (-1 = none) capped at `pct` % of the squad then, `cause` for the loss.
## Event `telegraph` {kind, lane, src (horde id), x, z (where it lands), land_t (sim time),
## id, t (warn s)}.
func _telegraph(kind: String, src: int, warn: float, base: int, pct: int, cause: String) -> void:
	var l := squad_lane()
	var a := {"id": _new_id(), "kind": kind, "lane": l, "src": src, "land": time + warn,
		"base": base, "pct": pct, "cause": cause, "x": lane_x(l), "z": 0.0}
	attacks.append(a)
	out.append({"type": "telegraph", "id": a["id"], "kind": kind, "lane": l, "src": src,
		"x": a["x"], "z": a["z"], "land_t": a["land"], "t": warn})


## Telegraphed attacks whose time has come land on the lane they marked. The hit is decided
## now, by where the squad really stands (squad_lane): changing lane in time dodges it, the
## shield blocks it. Event `attack_land` {kind, lane, lost, blocked, hit, id, src, x, z}.
func _land_attacks() -> void:
	for a in attacks.duplicate():
		if time < float(a["land"]):
			continue
		attacks.erase(a)
		var hit := squad_lane() == int(a["lane"])
		var blocked := hit and shield_t > 0.0
		var lost := 0
		if hit and not blocked:
			var n := share_loss(squad.total(), int(a["pct"]), int(a["base"]))
			if n > 0:
				lost = _hurt(n, String(a["cause"]), int(a["src"]), false)
		out.append(_land_event(a, hit, blocked, lost))
		if state != "run":
			return


func _land_event(a: Dictionary, hit: bool, blocked: bool, lost: int) -> Dictionary:
	return {"type": "attack_land", "id": a["id"], "kind": a["kind"], "lane": a["lane"], "src": a["src"],
		"x": a["x"], "z": a["z"], "lost": lost, "blocked": blocked, "hit": hit}


## Calls off every attack still in the air (the squad fell, revived or reached the stash): an
## `attack_land` with cancelled = true, hit = false, lost = 0 for each, so the view clears its
## marks. A telegraph only ever lands in live play time.
func _end_attacks() -> void:
	for a in attacks:
		var ev := _land_event(a, false, false, 0)
		ev["cancelled"] = true
		out.append(ev)
	attacks.clear()


## Gangs with guns fire back while their front is within rf_range (spec v2.1 §1.1): an
## opening volley on first entering range, then every shooter (shooters()) fires rf_rate
## shots/s. Each hit takes one visible figure's troops and one volley at most
## volley_cap_pct % of the squad (volley_loss), lowest rank first. The shield blocks it. One
## event per gang and tick {horde, x, z (its front), shots, lost, blocked, opening}, so the
## view draws the muzzle flashes and tracers.
func _return_fire(dt: float) -> void:
	var figs := maxi(int(rf_cfg.get("figures_shown", fig_cap)), 1)
	var cap_pct := int(rf_cfg.get("volley_cap_pct", 0))
	for h in hordes:
		if float(h.get("rf_rate", 0.0)) <= 0.0 or h["melee"] or int(h["count"]) <= 0:
			continue
		if front_z(h) < -float(h["rf_range"]):
			continue
		var opening := false
		if not h["rf_open"]:
			h["rf_open"] = true
			opening = true
			h["rf_acc"] = float(h["rf_acc"]) + float(rf_cfg.get("open", 0))
		h["rf_acc"] = float(h["rf_acc"]) + float(shooters(h)) * float(h["rf_rate"]) * dt
		var shots := int(floor(float(h["rf_acc"])))
		if shots <= 0:
			continue
		h["rf_acc"] = float(h["rf_acc"]) - shots
		var blocked := shield_t > 0.0
		var lost := 0
		if not blocked:
			var n := _spare_hero(volley_loss(squad.total(), shots, figs, cap_pct))
			if n > 0:
				lost = _hurt(n, String(h["enemy"]), h["id"], false)
		out.append({"type": "return_fire", "horde": h["id"], "x": 0.0, "z": front_z(h), "shots": shots,
			"lost": lost, "blocked": blocked, "opening": opening})
		if state != "run":
			return


## How many of a gang carry guns: its rf_share percent, rounded up (0 when it has none), at
## most the district's max_shooters.
static func shooters(h: Dictionary) -> int:
	return mini((int(h["count"]) * int(h.get("rf_share", 0)) + 99) / 100, int(h.get("rf_max", 1 << 30)))


## Troops one return-fire volley of `shots` hits takes from a squad of `total`: each hit one
## visible figure (ceil(total / figs), at least 1), the volley at most cap_pct % of the squad
## (but never less than one hit). Exact integers, never more than the squad.
static func volley_loss(total: int, shots: int, figs: int, cap_pct: int) -> int:
	if total <= 0 or shots <= 0:
		return 0
	var f := maxi(figs, 1)
	var per := (total + f - 1) / f
	var n := shots * per
	if cap_pct > 0:
		n = mini(n, maxi(per, total * cap_pct / 100))
	return mini(n, total)


## A share-of-squad hit: `pct` % of `total` (rounded down, at least 1), but never more than
## `base` (the attack's own count x damage; -1 = none) and never more than the squad.
static func share_loss(total: int, pct: int, base := -1) -> int:
	if total <= 0 or pct <= 0:
		return 0
	var n := maxi(total * pct / 100, 1)
	if base >= 0:
		n = mini(n, base)
	return mini(n, total)


## Return fire and the boss's gun never take the hero while the squad never had a follower
## this level (a hero-alone opening, spec v2.1 §1.1); once followers joined he falls last.
func _spare_hero(n: int) -> int:
	if peak_squad <= 1:
		return mini(n, squad.total() - 1)
	return n


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
		_end_attacks()
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
			_end_attacks()
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
		if kind == "barrel" and ob.get("armed", false):
			_barrel_on_squad(ob)
			if state != "run":
				return
			continue
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


## Spec v2 §5: a lit barrel that reaches the squad (its gang died first) goes off on it, never
## rolls by as "rubber": the troops on its footprint fall, up to armed_pct % of its number
## (units.obstacles.barrel), and any gang near it is caught too.
func _barrel_on_squad(ob: Dictionary) -> void:
	var cost := obstacle_cost(ob) * int(ob.get("armed_pct", 100)) / 100
	var hit := obstacle_hits(ob, cost) if cost > 0 else {}
	var lost := 0
	if not hit.is_empty() and int(hit["lost"]) > 0:
		lost = _hurt(int(hit["lost"]), "barrel", ob["id"], false)
	_explode(ob, {"on_squad": true, "lost": lost})
	if lost > 0:
		out.append({"type": "obstacle_hit", "ob": ob, "lost": lost, "slots": hit["slots"],
			"figures": hit["figures"], "x": squad_x})


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


# ---------------------------------------------------------------- hostage cages (spec v2.1 §4.1)

const CAGE_GAP := 2.0     # metres between the guards' back row and the cage behind them
const CAGE_REACH := 2.0   # the cage reaches the squad (opens to it or is lost) this short of it


## Rescue: a cage rides the road in its lane with a gang standing guard in front of it. The
## guards ride with the road (speed 0, never a standoff), so they cannot outrun the cage. Kill
## every guard before the cage reaches the squad and its people join (`unit`, constables by
## default, up to the cap); otherwise they are lost. The guards are a gang like any other: the
## squad's fire takes their front row first, armed ones fire back, and any that reach the squad
## fight it.
func _spawn_cage(sp: Dictionary) -> void:
	var ev: Dictionary = sp["ev"]
	var at := float(sp["at"])
	var cage := {"id": _new_id(), "at": at, "lane": clampi(int(ev.get("lane", 1)), 0, 2),
		"hostages": maxi(int(ev.get("hostages", 0)), 0), "unit": String(ev.get("unit", "constable")),
		"z": -(at - traveled), "guard": -1, "open": false}
	var grp: Dictionary = (ev.get("guards", {}) as Dictionary).duplicate(true)
	if grp.has("enemy") and int(grp.get("n", 0)) > 0:
		grp["speed"] = 0.0
		grp["stop_at"] = 0.0
		grp.erase("gap")
		var def := enemy_def(grp)
		var per := maxi((int(grp["n"]) + gang_figs - 1) / gang_figs, 1)
		var rows_n := ceili(int(grp["n"]) / float(maxi(int(def.get("cols", 9)), 1) * per))
		var depth := maxf(rows_n - 1, 0) * float(def.get("row_gap", 0.95))
		var before := hordes.size()
		_spawn_horde({"ev": grp, "at": at - depth - CAGE_GAP, "wave": -1, "label": ""})
		if hordes.size() > before:
			var h: Dictionary = hordes.back()
			h["cage"] = cage["id"]
			cage["guard"] = int(h["id"])
	cages.append(cage)
	out.append({"type": "cage_spawn", "cage": cage})


## The cage's guard gang while any of it still stands, else {}.
func cage_guard(cage: Dictionary) -> Dictionary:
	var gid := int(cage["guard"])
	if gid < 0:
		return {}
	for h in hordes:
		if int(h["id"]) == gid and int(h["count"]) > 0:
			return h
	return {}


## Cages ride the road. One opens the moment its last guard falls and its people join when it
## reaches the squad (cage_free). Guards that reach the squad first drag the cage off: its
## people are lost (cage_lost) and the guards still fight.
func _pass_cages() -> void:
	for cage in cages.duplicate():
		cage["z"] = -(float(cage["at"]) - traveled)
		var guard := cage_guard(cage)
		# A guard row that reached the squad this very step may already have fallen striking it
		# (_contacts): its melee event is still in `out`.
		var fought := not guard.is_empty() and bool(guard["melee"])
		if not fought and int(cage["guard"]) >= 0 and not cage["open"]:
			for e in out:
				if String(e["type"]) == "melee_start" and int(e["horde"]) == int(cage["guard"]):
					fought = true
					break
		if fought or (not guard.is_empty() and float(cage["z"]) >= -CAGE_REACH):
			cages.erase(cage)
			out.append({"type": "cage_lost", "cage": cage})
			continue
		if guard.is_empty() and not cage["open"]:
			cage["open"] = true
			out.append({"type": "cage_open", "cage": cage})
		if float(cage["z"]) < -CAGE_REACH:
			continue
		cages.erase(cage)
		var unit := String(cage["unit"])
		var added := squad.add(unit, int(cage["hostages"]))
		peak_squad = maxi(peak_squad, squad.total())
		out.append({"type": "cage_free", "cage": cage, "unit": unit, "n": added})
		if unit != "constable" and added > 0:
			out.append({"type": "rank_join", "unit": unit, "n": added, "first_time": not _joined.has(unit)})
			_joined[unit] = true


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
			"powers", "rf_cfg", "boss_cfg", "lt_cfg", "revive_cfg", "star_cfg", "lane", "squad_x", "_x_driven", "lane_w", "form_half",
			"fig_cap", "fig_r", "gate_clear_s", "gang_priority", "gang_figs", "district", "caps",
			"coin_ref", "tap_heat", "tap_auto", "tap_per", "tap_coin_pct", "heat_sum", "heat_t",
			"tap_hold_s", "tap_decay_s", "_tap_hold", "traveled", "time", "state", "lose_cause",
			"finish_at", "halted", "peak_squad", "revived", "shield_t", "kills", "rows_passed",
			"_spawns", "_next_spawn", "_pending_hordes", "_wave_ats", "_next_id", "_armour_note_t"]:
		c.set(p, get(p))
	c.stats = stats
	c.squad = squad.duplicate_squad()
	c.rows = rows.duplicate(true)
	c.obstacles = obstacles.duplicate(true)
	c.hordes = hordes.duplicate(true)
	c.attacks = attacks.duplicate(true)
	c.bombs = bombs.duplicate(true)
	c.cages = cages.duplicate(true)
	c.charges = charges.duplicate()
	c._wave_mods = _wave_mods.duplicate(true)
	c._joined = _joined.duplicate()
	c._enemy_hints = _enemy_hints.duplicate()
	c._hints_done = _hints_done.duplicate()
	return c


static func strike_coins(economy: Dictionary, troops: int, mult: int) -> int:
	return int(economy["clear_bonus"]) + troops * mult
