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
## Shooting rule (easy to explain to players): bullets stream down your lane and hit the
## first thing they meet: a gang (gangs fill the whole road), a red gate, a barrel or a car.
##
## Gangs are blocks of rows. Bullets always kill from the front, so the gang's front is its
## frontmost *living* row. Nothing hurts the squad until that front physically reaches it;
## then the gang fights row by row (melee), each enemy taking `power` troops and dying.

var S: float            # scroll speed, m/s
var fire_range: float
var spawn_dist: float
var contact_z: float
var melee_tick: float

var stats: Dictionary   # effective ally stats after upgrades
var weapons: Dictionary
var enemy_defs: Dictionary
var powers: Dictionary

var squad := Squad.new()
var lane := 1
var traveled := 0.0
var time := 0.0
var state := "run"      # run | strike | lost
var lose_cause := ""
var finish_at := 0.0

var rows: Array = []        # gate rows on screen
var obstacles: Array = []
var hordes: Array = []
var charges: Dictionary = {"shield": 0, "bomb": 0}
var shield_t := 0.0
var kills := 0
var rows_passed := 0
var out: Array = []         # events for the view, drained each frame
var target_kind := ""       # what the squad shot this tick: "horde" | "gate" | "obstacle" | ""
var target_ref = null

var _spawns: Array = []     # pre-computed, sorted by the distance at which they appear
var _next_spawn := 0
var _wave_ats: Array = []   # arrival `at` of each wave event, in order
var _wave_mods: Dictionary = {}  # wave index -> {"div": k, "strip": true}
var _next_id := 1
var _armour_note_t := 0.0


func _init(level: Dictionary, units_cfg: Dictionary, upgrades: Dictionary = {}) -> void:
	var w: Dictionary = units_cfg["world"]
	S = float(w["scroll_speed"])
	fire_range = float(w["fire_range"])
	spawn_dist = float(w["spawn_distance"])
	contact_z = float(w["contact_z"])
	melee_tick = float(w.get("melee_tick", 0.22))
	stats = units_cfg["allies"].duplicate(true)
	weapons = units_cfg["hero_weapons"]
	enemy_defs = units_cfg["enemies"]
	powers = units_cfg["powers"]

	var hero: Dictionary = stats["hero"]
	hero["dmg"] = float(hero["dmg"]) + float(upgrades.get("knife", 0))
	hero["rate"] = float(hero["rate"]) + 0.5 * float(upgrades.get("speed", 0))
	squad.add("constable", int(upgrades.get("squad", 0)))

	var ch: Dictionary = level.get("charges", {})
	for k in ch:
		charges[k] = int(ch[k])
	# Police-station garage: extra powers at the start of every level.
	charges["shield"] = int(charges["shield"]) + int(upgrades.get("shield", 0))
	charges["bomb"] = int(charges["bomb"]) + int(upgrades.get("bomb", 0))
	_build_spawns(level.get("events", []))


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
					var def: Dictionary = enemy_defs[grp["enemy"]]
					var arrive := at + float(grp.get("gap", 0.0))
					var vrel := S + float(def["speed"])
					var stop := float(def.get("stop_at", 0.0))
					_spawns.append({"kind": "horde", "ev": grp, "at": arrive, "wave": wave_index,
						"label": String(e.get("label", "")),
						"spawn_at": arrive - (spawn_dist - stop) * S / vrel})
				wave_index += 1
	_spawns.sort_custom(func(a, b): return float(a["spawn_at"]) < float(b["spawn_at"]))


# ---------------------------------------------------------------- input

func set_lane(l: int) -> void:
	lane = clampi(l, 0, 2)


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
			var h = _front_horde(float(powers["bomb"]["reach"]))
			if h == null:
				return false
			var cfg: Dictionary = powers["bomb"]
			var n: int = h["count"]
			var k := 0
			if float(h["hp"]) >= float(cfg.get("big_hp", 50)):
				# Big single targets (the boss) take flat damage instead of dying outright.
				h["acc"] = float(h["acc"]) + float(cfg.get("big_dmg", 120))
				k = mini(int(floor(float(h["acc"]) / float(h["hp"]))), n)
				h["acc"] = float(h["acc"]) - k * float(h["hp"])
			else:
				k = mini(n, maxi(int(floor(n * float(cfg["kill_pct"]) / 100.0)), int(cfg["min_kill"])))
			h["shield"] = float(h["shield"]) * 0.5
			_kill(h, k)
			out.append({"type": "bomb", "horde": h["id"], "z": front_z(h), "killed": k})
		_:
			return false
	charges[id] = int(charges[id]) - 1
	return true


# ---------------------------------------------------------------- tick

func step(dt: float) -> void:
	if state != "run":
		return
	time += dt
	traveled += S * dt
	shield_t = maxf(shield_t - dt, 0.0)
	_armour_note_t = maxf(_armour_note_t - dt, 0.0)
	_spawn_due()
	_move(dt)
	_check_barrels()
	_shoot(dt)
	_gunfire(dt)
	_contacts(dt)
	_pass_rows()
	_pass_obstacles()
	if state == "run" and finish_at > 0.0 and traveled >= finish_at and hordes.is_empty():
		state = "strike"
		out.append({"type": "finish"})


func _spawn_due() -> void:
	while _next_spawn < _spawns.size() and float(_spawns[_next_spawn]["spawn_at"]) <= traveled:
		var sp: Dictionary = _spawns[_next_spawn]
		_next_spawn += 1
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
				ob["id"] = _new_id()
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
				_spawn_horde(sp)


func _spawn_horde(sp: Dictionary) -> void:
	var grp: Dictionary = sp["ev"]
	var def: Dictionary = enemy_defs[grp["enemy"]]
	var vrel := S + float(def["speed"])
	var stop := float(def.get("stop_at", 0.0))
	var h := {
		"id": _new_id(), "wave": sp["wave"], "enemy": grp["enemy"], "label": sp["label"],
		"count": int(grp["n"]), "start": int(grp["n"]),
		"hp": float(def["hp"]), "armour": int(def["armour"]), "power": int(def["power"]),
		"vrel": vrel, "stop": stop, "shoot_every": float(def.get("shoot_every", 0.0)),
		"shot_dmg": int(def.get("shot_dmg", 1)),
		"cols": int(def.get("cols", 9)), "row_gap": float(def.get("row_gap", 0.95)),
		"shield": 0.0, "z": -stop - (float(sp["at"]) - traveled) * vrel / S,
		"acc": 0.0, "shoot_t": 0.0, "stopped": false, "melee": false, "melee_t": 0.0,
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


func _shoot(dt: float) -> void:
	target_kind = ""
	target_ref = null
	var h = _front_horde(fire_range)
	var t = _lane_target()
	# Bullets hit whichever is nearer in the lane: the gang's front or a lane object.
	if t != null and (h == null or float(t["z"]) > front_z(h)):
		_shoot_lane(t, dt)
		return
	if h == null:
		return
	target_kind = "horde"
	target_ref = h
	var hp := float(h["hp"])
	var d := squad.dps(stats, weapons, int(h["armour"]), hp)
	if d <= 0.0:
		if _armour_note_t <= 0.0 and squad.dps(stats, weapons, 0, hp) > 0.0:
			_armour_note_t = 1.5
			out.append({"type": "armour_block", "horde": h["id"]})
		return
	var dmg := d * dt
	if float(h["shield"]) > 0.0:
		# Riot shields soak non-piercing fire first; piercing rounds go straight through.
		var pierce := squad.pierce_dps(stats, weapons, hp) * dt
		var blocked := minf(float(h["shield"]), maxf(dmg - pierce, 0.0))
		h["shield"] = float(h["shield"]) - blocked
		dmg -= blocked
		if blocked > 0.0 and float(h["shield"]) <= 0.0:
			out.append({"type": "shield_broken", "horde": h["id"]})
	h["acc"] = float(h["acc"]) + dmg
	var k := mini(int(floor(float(h["acc"]) / hp)), int(h["count"]))
	if k > 0:
		h["acc"] = float(h["acc"]) - k * hp
		_kill(h, k)


func _shoot_lane(t: Dictionary, dt: float) -> void:
	var dmg := squad.dps(stats, weapons, 0, 1000.0) * dt
	target_ref = t
	if t.has("op"):  # a gate
		target_kind = "gate"
		t["progress"] = float(t["progress"]) + dmg
		var step_hp := float(t["step"])
		var inc := int(t.get("inc", 1))
		while float(t["progress"]) >= step_hp and int(t["v"]) < int(t["max"]):
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


func _check_barrels() -> void:
	for ob in obstacles.duplicate():
		if not ob.get("armed", false):
			continue
		for h in hordes:
			if front_z(h) >= float(ob["z"]) - 0.5:
				obstacles.erase(ob)
				_explode(ob)
				break


## An armed barrel blows up every gang whose front is within its blast radius.
func _explode(b: Dictionary) -> void:
	var radius := float(b.get("radius", 7.0))
	var max_kill := int(b.get("kill", 30))
	var total := 0
	for h in hordes.duplicate():
		if absf(front_z(h) - float(b["z"])) <= radius:
			var k := mini(max_kill, int(h["count"]))
			total += k
			h["shield"] = 0.0
			_kill(h, k)
	out.append({"type": "barrel_boom", "ob": b, "killed": total})


func _kill(h: Dictionary, k: int) -> void:
	if k <= 0:
		return
	h["count"] = int(h["count"]) - k
	kills += k
	out.append({"type": "kill", "horde": h["id"], "n": k, "left": h["count"]})
	if int(h["count"]) <= 0:
		hordes.erase(h)
		out.append({"type": "horde_cleared", "horde": h["id"]})


func _front_horde(reach: float):
	var best = null
	for h in hordes:
		if int(h["count"]) > 0 and front_z(h) >= -reach:
			if best == null or front_z(h) > front_z(best):
				best = h
	return best


## How many whole rows have been shot away from the front.
static func killed_rows(h: Dictionary) -> int:
	return int((int(h["start"]) - int(h["count"])) / maxi(int(h["cols"]), 1))


## Position of the frontmost living row.
static func front_z(h: Dictionary) -> float:
	return float(h["z"]) - killed_rows(h) * float(h["row_gap"])


func _lane_target():
	var best = null
	var best_z := -INF
	for row in rows:
		var z := float(row["z"])
		if z < -fire_range or z >= 0.0:
			continue
		for g in row["gates"]:
			if int(g["lane"]) == lane and float(g.get("step", 0.0)) > 0.0 and int(g["v"]) < int(g["max"]):
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
		if not h["stopped"] or float(h["shoot_every"]) <= 0.0:
			continue
		h["shoot_t"] = float(h["shoot_t"]) + dt
		while float(h["shoot_t"]) >= float(h["shoot_every"]):
			h["shoot_t"] = float(h["shoot_t"]) - float(h["shoot_every"])
			if shield_t > 0.0:
				out.append({"type": "blocked", "horde": h["id"], "n": h["count"]})
			else:
				_hurt(int(h["count"]) * int(h["shot_dmg"]), String(h["enemy"]), h["id"])
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
		var row := mini(int(h["cols"]), int(h["count"]))
		var power := row * int(h["power"])
		var lost := 0
		if shield_t <= 0.0:
			lost = _hurt(power, String(h["enemy"]), h["id"], false)
		out.append({"type": "melee", "horde": h["id"], "enemies": row, "lost": lost, "shielded": shield_t > 0.0})
		_kill(h, row)
		if state != "run":
			return


func _hurt(n: int, cause: String, source_id: int = 0, announce: bool = true) -> int:
	var lost := squad.lose(n)
	if announce and lost > 0:
		out.append({"type": "hurt", "n": lost, "cause": cause, "source": source_id})
	if not squad.hero_alive():
		state = "lost"
		lose_cause = cause
		out.append({"type": "lost", "cause": cause})
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
		if picked != null:
			delta = _apply_gate(picked)
		out.append({"type": "row_pass", "row": row, "gate": picked, "before": before,
			"after": squad.total(), "delta": delta})
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
			return squad.add(String(g["unit"]), int(g.get("n", 1)))
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
		if int(ob["lane"]) == lane and float(ob["hp"]) > 0.0 and not ob.get("armed", false):
			var lost := _hurt(int(ob.get("dmg", 5)), String(ob.get("kind", "barricade")), ob["id"], false)
			out.append({"type": "obstacle_hit", "ob": ob, "lost": lost})
			if state != "run":
				return
		else:
			out.append({"type": "obstacle_pass", "ob": ob})


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


static func strike_coins(economy: Dictionary, troops: int, mult: int) -> int:
	return int(economy["clear_bonus"]) + troops * mult
