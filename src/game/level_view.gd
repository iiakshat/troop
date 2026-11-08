class_name LevelView
extends Node3D
## Plays one level: steps LevelSim at a fixed rate and turns its state and events into
## people, gates, bullets, numbers and sound. Also handles lane input.
## `demo` mode (lobby backdrop): the squad just jogs down an empty street.

signal hint(ev: Dictionary)
signal banner(text: String, color: Color)
signal squad_changed(total: int)
signal charges_changed(charges: Dictionary)
signal strike_ready
signal tutorial(active: bool)
signal finished(result: Dictionary)

const LANE_X := [-3.2, 0.0, 3.2]
const ALLY_CAP := 72
const HORDE_CAP := 180
const DT := 1.0 / 60.0
const ENEMY_KINDS := ["thug", "knifer", "gunman", "brute", "riot", "biker", "boss"]
const ALLY_KINDS := ["hero", "constable", "inspector", "swat"]
const SWIPE_PX := 36.0

var sim: LevelSim
var world: World
var fx: Fx
var font: Font
var level_id := 1
var demo := false
var paused := false
var input_enabled := true      # false under --autoplay so stray clicks can't interfere

var _crowds: Dictionary = {}
var _allies: Array = []        # {kind, pos, slot, phase, flash, fire_t}
var _dying: Array = []         # {kind, pos, t, basis}
var _charging: Array = []      # {kind, pos, target, flip}
var _hordes: Dictionary = {}   # id -> {h, kind, offs, per, label, sub, flash}
var _rows: Dictionary = {}     # id -> GateRowView
var _squad_x := 0.0
var _acc := 0.0
var _last_traveled := 0.0
var _time_scale := 1.0
var _tut_row := -1
var _tut_done: Dictionary = {}
var _state := "play"           # play | strike | striking | done
var _end_t := 0.0
var _squad_label: Label3D
var _label_pop := 0.0
var _shield: MeshInstance3D
var _shield_mat: StandardMaterial3D
var _finish: Node3D
var _hq: Node3D
var _hq_fill: MeshInstance3D
var _strike_mult := 1
var _strike_t := 0.0
var _touch_start := Vector2.ZERO
var _touching := false
var _swiped := false
var _last_total := 1
var _shown_banner: Dictionary = {}
var _obstacles: Dictionary = {}  # id -> {ob, node}


func setup(level: Dictionary, upgrades: Dictionary, w: World, f: Fx, fnt: Font, is_demo := false) -> LevelView:
	world = w
	fx = f
	font = fnt
	demo = is_demo
	level_id = int(level.get("id", 1))
	sim = LevelSim.new(level, Game.units, upgrades)
	fx.scroll_speed = 0.0
	return self


func _ready() -> void:
	for k in ALLY_KINDS + ENEMY_KINDS:
		var cap := ALLY_CAP + 40 if k in ALLY_KINDS else HORDE_CAP * 3
		var c := Crowd.new().setup(k, cap)
		add_child(c)
		_crowds[k] = c
	_squad_label = GateRowView._label(font, 120, 0.011)
	_squad_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_squad_label.no_depth_test = true
	_squad_label.render_priority = 8
	_squad_label.outline_render_priority = 7
	_squad_label.modulate = Color("8fd0ff")
	add_child(_squad_label)
	_build_shield()
	_sync_allies(Vector3(0, 0, 2))
	_squad_label.visible = false
	charges_changed.emit(sim.charges)
	squad_changed.emit(sim.squad.total())


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if demo or paused or _state != "play" or not input_enabled:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touching = true
			_swiped = false
			_touch_start = t.position
		else:
			if _touching and not _swiped and t.position.distance_to(_touch_start) < 12.0:
				# A tap on the left or right third also steps one lane.
				var w := get_viewport().get_visible_rect().size.x
				if t.position.x < w * 0.33:
					_move(-1)
				elif t.position.x > w * 0.67:
					_move(1)
			_touching = false
	elif event is InputEventScreenDrag and _touching:
		var d := event as InputEventScreenDrag
		var dx := d.position.x - _touch_start.x
		if absf(dx) > SWIPE_PX:
			_move(1 if dx > 0 else -1)
			_touch_start = d.position
			_swiped = true
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_LEFT or k == KEY_A:
			_move(-1)
		elif k == KEY_RIGHT or k == KEY_D:
			_move(1)
		elif k == KEY_S:
			use_power("shield")
		elif k == KEY_B:
			use_power("bomb")


func _move(dir: int) -> void:
	var before := sim.lane
	sim.set_lane(sim.lane + dir)
	if sim.lane != before:
		Sfx.play("swoosh", -6.0)
		if _tut_row >= 0:
			_tut_done[_tut_row] = true
			_tut_row = -1
			tutorial.emit(false)


func use_power(id: String) -> bool:
	if paused or _state != "play":
		return false
	var ok := sim.use_power(id)
	if ok:
		charges_changed.emit(sim.charges)
		_handle_events(sim.drain())
	return ok


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if paused:
		return
	if demo:
		world.scroll(4.0 * delta)
		_update_visuals(delta)
		return
	match _state:
		"play":
			_update_time_scale()
			var d := delta * _time_scale
			_acc += d
			var steps := 0
			while _acc >= DT and steps < 8:
				sim.step(DT)
				_acc -= DT
				steps += 1
				_handle_events(sim.drain())
				if _state != "play":
					break
			world.scroll(sim.traveled - _last_traveled)
			_last_traveled = sim.traveled
			fx.scroll_speed = sim.S * _time_scale
			_update_visuals(d)
		"strike", "done_win":
			fx.scroll_speed = 0.0
			_update_visuals(delta)
		"striking":
			_update_strike(delta)
			_update_visuals(delta)
		"done":
			_end_t += delta
			var d := delta * 0.3
			world.scroll(sim.S * d)
			fx.scroll_speed = sim.S * 0.3
			_update_visuals(d)
			if _end_t > 1.2 and _end_t - delta <= 1.2:
				finished.emit({"won": false, "cause": sim.lose_cause, "kills": sim.kills, "level": level_id})


func _update_time_scale() -> void:
	var target := 1.0
	for id in _rows:
		var row: Dictionary = (_rows[id] as GateRowView).row
		var z := float(row["z"])
		if String(row.get("tutorial", "")) == "swipe" and not _tut_done.has(id) and z > -17.0:
			# Freeze only while the squad sits in a lane with no gate: "swipe to grab one".
			var empty := true
			for g in row["gates"]:
				if int(g["lane"]) == sim.lane:
					empty = false
			if empty:
				if _tut_row != id:
					_tut_row = id
					tutorial.emit(true)
				target = 0.0
			else:
				_tut_done[id] = true
				if _tut_row == id:
					_tut_row = -1
					tutorial.emit(false)
	_time_scale = target if target == 0.0 else move_toward(_time_scale, target, 0.08)


# ---------------------------------------------------------------- events

func _handle_events(events: Array) -> void:
	for e in events:
		match String(e["type"]):
			"row_spawn":
				var v := GateRowView.new().setup(e["row"], font, LANE_X)
				add_child(v)
				_rows[e["row"]["id"]] = v
				v.position.z = float(e["row"]["z"])
			"gate_tick":
				_on_gate_tick(e)
			"row_pass":
				_on_row_pass(e)
			"horde_spawn":
				_on_horde_spawn(e["horde"])
			"kill":
				Sfx.play("die", -4.0)
			"horde_cleared":
				pass
			"melee_start":
				Sfx.play("swoosh", -2.0, 0.7)
			"melee":
				_on_melee(e)
			"turncoat":
				_on_turncoat(e)
			"shield_broken":
				var hb: Dictionary = _hordes.get(e["horde"], {})
				if not hb.is_empty():
					fx.burst(_horde_front(hb) + Vector3(0, 1.2, 0), Color("9fc6ff"), 30, 7.0, 0.22, 0.6)
					Sfx.play("clink")
			"barrel_armed":
				var bo: Dictionary = _obstacles.get(e["ob"]["id"], {})
				if not bo.is_empty():
					Sfx.play("tick", 0.0, 1.6)
			"barrel_boom":
				_on_barrel_boom(e)
			"hurt":
				_on_hurt(e)
			"blocked":
				_gun_tracers(int(e["horde"]), true)
				Sfx.play("blocked")
			"armour_block":
				var hv: Dictionary = _hordes.get(e["horde"], {})
				if not hv.is_empty():
					var p := _horde_front(hv)
					fx.burst(p + Vector3(0, 1.2, 0), Color(1, 1, 0.8), 8, 5.0, 0.12, 0.3)
					Sfx.play("clink")
			"foe_mod":
				var hv: Dictionary = _hordes.get(e["horde"], {})
				if not hv.is_empty():
					var p := _horde_front(hv)
					fx.burst(p + Vector3(0, 1.0, 0), Color("6fa8ff"), 24, 6.0, 0.2, 0.6)
					Sfx.play("flip")
			"bomb":
				_on_bomb(e)
			"shield_on":
				Sfx.play("shield")
			"hint":
				hint.emit(e["ev"])
			"finish_spawn":
				_spawn_finish(float(e["at"]))
			"finish":
				_begin_strike()
			"lost":
				_state = "done"
				_end_t = 0.0
				Sfx.play("lose")
				Game.vibrate(200)
			"obstacle_spawn":
				_spawn_obstacle(e["ob"])
			"obstacle_broken":
				var ob: Dictionary = e["ob"]
				fx.burst(_obstacle_pos(ob) + Vector3(0, 1.0, 0), Color(0.55, 0.45, 0.35), 24, 6.0, 0.3, 0.7)
				Sfx.play("boom", -8.0, 1.4)
				_free_obstacle(int(ob["id"]))
			"obstacle_hit":
				world.shake(0.5)
				Sfx.play("hurt")
				_free_obstacle(int(e["ob"]["id"]))
				_sync_allies(Vector3(_squad_x, 0, 0))
			"obstacle_pass":
				_free_obstacle(int(e["ob"]["id"]))
	if sim.squad.total() != _last_total:
		_last_total = sim.squad.total()
		squad_changed.emit(_last_total)
		_label_pop = 1.0


func _on_gate_tick(e: Dictionary) -> void:
	for id in _rows:
		var v: GateRowView = _rows[id]
		for g in v.row["gates"]:
			if g == e["gate"]:
				v.refresh(g, true)
				var root := v.lane_root(int(g["lane"]))
				if root:
					var p := root.global_position + Vector3(0, 2.0, 0.1)
					if e["flipped"]:
						fx.confetti(p, 30)
						Sfx.play("flip")
						Game.vibrate(40)
					else:
						fx.burst(p, Color(1, 1, 1), 3, 3.0, 0.12, 0.25)
						Sfx.play("tick", -3.0, 1.0 + clampf(float(e["to"]) / 30.0, -0.3, 0.6))


func _on_row_pass(e: Dictionary) -> void:
	var row: Dictionary = e["row"]
	var v: GateRowView = _rows.get(row["id"])
	_rows.erase(row["id"])
	var g = e["gate"]
	var src := Vector3(LANE_X[sim.lane], 0, -1.5)
	if v:
		v.passed(int(g["lane"]) if g != null else -1)
	if g == null:
		return
	var delta := int(e["delta"])
	var col: Color = GateRowView.describe(g)["color"]
	fx.burst(src + Vector3(0, 1.6, 0), col.lightened(0.3), 26, 7.0, 0.22, 0.6)
	match String(g["op"]):
		"num", "pct", "div", "mul", "recruit":
			var txt := ("+%d" % delta) if delta >= 0 else ("%d" % delta)
			if g["op"] == "mul":
				txt = "×%d  →  %d" % [int(g["k"]), int(e["after"])]
			elif g["op"] == "recruit":
				txt = "+%d %s" % [delta, String(g["unit"]).to_upper()]
			if delta >= 0:
				Sfx.play("gate_good")
				Sfx.play("recruit", -4.0)
				Game.vibrate(35)
			else:
				Sfx.play("gate_bad")
				Game.vibrate(90)
		"weapon":
			Sfx.play("gate_good")
			Game.vibrate(35)
		"power":
			charges_changed.emit(sim.charges)
			Sfx.play("gate_good")
		"foe_div", "foe_strip":
			Sfx.play("gate_good")
	_sync_allies(src)


func _on_horde_spawn(h: Dictionary) -> void:
	var kind := String(h["enemy"])
	var n := int(h["count"])
	var per := maxi(1, int(ceil(n / float(HORDE_CAP))))
	var vis := int(ceil(n / float(per)))
	var cols := int(h["cols"])
	var dx := 9.0 / maxf(cols, 1)
	var dz := float(h["row_gap"]) * per
	var offs: Array = []
	for i in vis:
		var r := i / cols
		var c := i % cols
		var row_n := mini(cols, vis - r * cols)
		var x := (c - (row_n - 1) * 0.5) * dx + randf_range(-0.15, 0.15)
		offs.append(Vector3(x if cols > 1 else 0.0, randf(), r * dz + randf_range(-0.12, 0.12)))  # y holds a phase
	var label := GateRowView._label(font, 90, 0.011)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("ff6b6b") if int(h["armour"]) == 0 else Color("b8c7d9")
	add_child(label)
	var sub := Node3D.new()
	add_child(sub)
	_hordes[h["id"]] = {"h": h, "kind": kind, "offs": offs, "per": per, "label": label, "sub": sub, "shoot_flash": 0.0}
	var label_text := String(h.get("label", ""))
	if label_text != "" and not _shown_banner.has(label_text):
		_shown_banner[label_text] = true
		banner.emit(label_text, Color("ff5a5f"))


func _on_melee(e: Dictionary) -> void:
	var hv: Dictionary = _hordes.get(e["horde"], {})
	if hv.is_empty():
		return
	# The striking row charges into the squad (the sim already removed them).
	var n := mini(int(ceil(int(e["enemies"]) / float(hv["per"]))), (hv["offs"] as Array).size())
	for i in n:
		var o: Vector3 = hv["offs"].pop_front()
		_charging.append({"kind": hv["kind"], "pos": _fig_pos(hv, o), "phase": o.y, "shielded": e["shielded"]})
	var lost := int(e["lost"])
	world.shake(clampf(0.2 + lost * 0.02, 0.2, 0.9))
	if e["shielded"]:
		Sfx.play("blocked")
	elif lost > 0:
		Sfx.play("hurt", -2.0)
		Game.vibrate(60)
	_sync_allies(Vector3(_squad_x, 0, -1.0))


func _on_turncoat(e: Dictionary) -> void:
	var hv: Dictionary = _hordes.get(e["horde"], {})
	var src := Vector3(_squad_x, 0, -6.0)
	if not hv.is_empty():
		src = _horde_front(hv)
		var n := mini(int(ceil(int(e["n"]) / float(hv["per"]))), (hv["offs"] as Array).size())
		for i in n:
			var o: Vector3 = hv["offs"].pop_front()
			fx.burst(_fig_pos(hv, o) + Vector3(0, 1.0, 0), Color("6fa8ff"), 4, 3.0, 0.18, 0.4)
	Sfx.play("recruit")
	_sync_allies(src)


func _on_barrel_boom(e: Dictionary) -> void:
	var ob: Dictionary = e["ob"]
	var p := _obstacle_pos(ob)
	_free_obstacle(int(ob["id"]))
	fx.explosion(p + Vector3(0, 0.8, 0), 2.2)
	world.shake(1.1)
	Sfx.play("boom")
	Game.vibrate(150)


func _on_hurt(e: Dictionary) -> void:
	Sfx.play("hurt", -3.0)
	if e["cause"] == "gunman" or e["cause"] == "boss":
		_gun_tracers(int(e["source"]), false)
	world.shake(0.25)
	_sync_allies(Vector3(_squad_x, 0, 0))


func _gun_tracers(horde_id: int, blocked: bool) -> void:
	var hv: Dictionary = _hordes.get(horde_id, {})
	if hv.is_empty():
		return
	hv["shoot_flash"] = 0.15
	Sfx.play("shot", -2.0, 0.7)
	var n := mini((hv["offs"] as Array).size(), 8)
	for i in n:
		var from := _fig_pos(hv, hv["offs"][i]) + Vector3(0, 1.2, 0.5)
		var to := Vector3(_squad_x + randf_range(-1.5, 1.5), 1.0, randf_range(0.0, 2.0))
		if blocked:
			to = Vector3(_squad_x, 1.4, -2.2) + Vector3(randf_range(-1.5, 1.5), randf_range(0, 1), 0)
		fx.shoot("tracer", from, to, 60.0)


func _on_bomb(e: Dictionary) -> void:
	var hv: Dictionary = _hordes.get(e["horde"], {})
	var p := Vector3(0, 0.5, float(e["z"]) - 2.0)
	if not hv.is_empty():
		p = _horde_front(hv) + Vector3(0, 0.5, -2.0)
	fx.shoot("bullet_big", Vector3(_squad_x, 2.0, -1.0), p, 30.0)
	fx.explosion(p, 1.6)
	world.shake(1.0)
	Sfx.play("boom")
	Game.vibrate(150)


# ---------------------------------------------------------------- allies

func _desired_allies() -> Dictionary:
	var counts := sim.squad.counts
	var total := sim.squad.total()
	var out := {}
	for k in ALLY_KINDS:
		out[k] = int(counts.get(k, 0))
	if total > ALLY_CAP:
		var per := float(total) / ALLY_CAP
		for k in ["inspector", "swat"]:
			out[k] = maxi(int(round(int(counts[k]) / per)), 1 if int(counts[k]) > 0 else 0)
		out["constable"] = maxi(ALLY_CAP - out["hero"] - out["inspector"] - out["swat"], 0)
	return out


func _sync_allies(source: Vector3) -> void:
	var want := _desired_allies()
	for kind in ALLY_KINDS:
		var have: Array = _allies.filter(func(a): return a["kind"] == kind)
		var diff := int(want[kind]) - have.size()
		if diff > 0:
			for i in diff:
				var jitter := Vector3(randf_range(-1.2, 1.2), 0, randf_range(-0.5, 0.5))
				_allies.append({"kind": kind, "pos": source + jitter, "slot": 0, "phase": randf(), "flash": 0.6,
					"fire_t": randf() * 0.5})
		elif diff < 0:
			# Remove from the back of the blob first.
			have.sort_custom(func(a, b): return (a["pos"] as Vector3).z > (b["pos"] as Vector3).z)
			for i in -diff:
				var a: Dictionary = have[i]
				_allies.erase(a)
				_dying.append({"kind": kind, "pos": a["pos"], "t": 0.0, "basis": Basis()})
				fx.puff(a["pos"])
	# Slots: hero in front, inspectors next, constables behind.
	var order := {"hero": 0, "swat": 1, "inspector": 2, "constable": 3}
	_allies.sort_custom(func(a, b): return order[a["kind"]] < order[b["kind"]])
	for i in _allies.size():
		_allies[i]["slot"] = i


func _slot_pos(slot: int, n: int) -> Vector3:
	var lift := -7.0 if demo else 0.0  # lobby: squad further up the street, above the menu
	if slot == 0:
		return Vector3(_squad_x, 0, -0.5 + lift)
	var i := slot - 1
	var r := 0.4 * sqrt(i + 0.7)
	var a := i * 2.39996
	var radius := 0.4 * sqrt(maxf(n, 1))
	return Vector3(_squad_x + cos(a) * r * 1.25, 0, 0.5 + radius * 0.6 + sin(a) * r * 0.65 + lift)


# ---------------------------------------------------------------- visuals

func _update_visuals(d: float) -> void:
	var lane_target: float = LANE_X[sim.lane]
	_squad_x = move_toward(_squad_x, lane_target, d * 24.0 if not demo else 1.0)
	var target_pos = _target_point()
	var running := 1.0 if (_state == "play" or _state == "done") else 0.0
	if demo:
		running = 1.0

	for k in _crowds:
		(_crowds[k] as Crowd).begin()

	# Allies
	var n := _allies.size()
	for a in _allies:
		var target := _slot_pos(int(a["slot"]), n)
		var pos: Vector3 = a["pos"]
		pos = pos.move_toward(target, d * 14.0)
		a["pos"] = pos
		a["flash"] = maxf(float(a["flash"]) - d * 3.0, 0.0)
		var aim := 0.0
		if not demo and (_state == "play" or _state == "strike" or _state == "striking"):
			aim = 1.0
			a["fire_t"] = float(a["fire_t"]) - d
			if float(a["fire_t"]) <= 0.0:
				var aim_at: Vector3 = target_pos if target_pos != null else Vector3(pos.x, 1.1, pos.z - sim.fire_range)
				_fire(a, aim_at)
		var basis := Basis()
		if target_pos != null and not demo:
			var dir: Vector3 = (target_pos as Vector3) - pos
			dir.y = 0
			if dir.length() > 0.5:
				basis = Basis.looking_at(dir.normalized(), Vector3.UP)
		(_crowds[a["kind"]] as Crowd).push(Transform3D(basis, pos), Color(float(a["phase"]), float(a["flash"]), running, aim))

	# Enemies
	for id in _hordes:
		var hv: Dictionary = _hordes[id]
		var h: Dictionary = hv["h"]
		var want := int(ceil(int(h["count"]) / float(hv["per"])))
		var offs: Array = hv["offs"]
		while offs.size() > want:
			var o: Vector3 = offs.pop_front()
			var p := _fig_pos(hv, o)
			_dying.append({"kind": hv["kind"], "pos": p, "t": 0.0, "basis": Basis(Vector3.UP, PI)})
			fx.puff(p)
		var crowd: Crowd = _crowds[hv["kind"]]
		var run := 0.0 if h["stopped"] else 1.0
		var aim := 1.0 if h["stopped"] else 0.0
		var flash := float(hv["shoot_flash"])
		hv["shoot_flash"] = maxf(flash - d, 0.0)
		var face := Basis(Vector3.UP, PI)
		if hv["kind"] == "boss":
			face = face.scaled(Vector3.ONE * 2.2)
		for o in offs:
			crowd.push(Transform3D(face, _fig_pos(hv, o)), Color(o.y, flash * 2.0, run, aim))
		var lab: Label3D = hv["label"]
		var depth := (offs.back().z if not offs.is_empty() else 0.0) as float
		lab.position = Vector3(0, 3.6 if hv["kind"] != "brute" else 4.6, float(h["z"]) - depth * 0.5)
		lab.text = str(int(h["count"])) if hv["kind"] != "boss" else str(int(ceil(float(h["hp"]) - float(h["acc"]))))
		if int(h["armour"]) == 0:
			lab.modulate = Color("ff6b6b")

	# People waiting at troop pickups, facing the squad.
	for id in _rows:
		var rv: GateRowView = _rows[id]
		var rz := float(rv.row["z"])
		for g in rv.row["gates"]:
			if not GateRowView.is_troops(g):
				continue
			var cnt := mini(GateRowView.troop_count(g), 12)
			var cx: float = LANE_X[int(g["lane"])]
			var crowd: Crowd = _crowds[GateRowView.troop_kind(g)]
			for j in cnt:
				var a := j * 2.39996
				var r := 0.42 * sqrt(j + 0.3) if cnt > 1 else 0.0
				var p := Vector3(cx + cos(a) * r * 1.2, 0, rz + sin(a) * r * 0.8)
				crowd.push(Transform3D(Basis(Vector3.UP, PI), p), Color(fmod(j * 0.37, 1.0), 0.0, 0.0, 0.0))

	# Charging (contact) and dying figures
	var i := 0
	while i < _charging.size():
		var c: Dictionary = _charging[i]
		var goal := Vector3(_squad_x, 0, -0.5 if c["shielded"] else 0.8)
		var p: Vector3 = (c["pos"] as Vector3).move_toward(goal, d * 16.0)
		c["pos"] = p
		if p.distance_to(goal) < (2.6 if c["shielded"] else 0.6):
			fx.puff(p)
			_charging.remove_at(i)
			continue
		(_crowds[c["kind"]] as Crowd).push(Transform3D(Basis(Vector3.UP, PI), p), Color(float(c["phase"]), 0.0, 1.0, 0.0))
		i += 1
	i = 0
	while i < _dying.size():
		var dd: Dictionary = _dying[i]
		dd["t"] = float(dd["t"]) + d
		var t := float(dd["t"])
		if t > 0.9:
			_dying.remove_at(i)
			continue
		var p: Vector3 = dd["pos"]
		p.z += sim.S * d * (1.0 if _state == "play" or _state == "done" else 0.0)
		dd["pos"] = p
		var ang := minf(t / 0.3, 1.0) * 1.45
		var basis: Basis = (dd["basis"] as Basis) * Basis(Vector3.RIGHT, ang)
		var sink := maxf(t - 0.55, 0.0) * 2.0
		var flash := maxf(0.0, 1.0 - t * 4.0)
		(_crowds[dd["kind"]] as Crowd).push(Transform3D(basis, p - Vector3(0, sink, 0)), Color(0.0, flash, 0.0, 0.0))
		i += 1

	for k in _crowds:
		(_crowds[k] as Crowd).finish()

	# Gates ride the road.
	for id in _rows:
		var v: GateRowView = _rows[id]
		v.position.z = float(v.row["z"])
	if _finish:
		_finish.position.z = -(sim.finish_at - sim.traveled)
	for oid in _obstacles:
		var od: Dictionary = _obstacles[oid]
		var on: Node3D = od["node"]
		on.position = _obstacle_pos(od["ob"])
		if od["ob"].get("armed", false):
			on.scale = Vector3.ONE * (1.0 + 0.12 * absf(sin(Time.get_ticks_msec() / 60.0)))

	# Squad label and shield.
	_label_pop = maxf(_label_pop - d * 4.0, 0.0)
	_squad_label.text = str(sim.squad.total())
	_squad_label.position = Vector3(_squad_x, 3.9, -0.8)
	_squad_label.scale = Vector3.ONE * (1.0 + 0.5 * _label_pop)
	_shield.visible = sim.shield_t > 0.0
	if _shield.visible:
		_shield.position = Vector3(_squad_x, 0, 0.6)
		var a := 0.22 + 0.08 * sin(Time.get_ticks_msec() / 90.0)
		if sim.shield_t < 1.0:
			a *= 0.5 + 0.5 * sin(Time.get_ticks_msec() / 40.0)
		_shield_mat.albedo_color = Color(0.45, 0.75, 1.0, a)


func _fig_pos(hv: Dictionary, o: Vector3) -> Vector3:
	var h: Dictionary = hv["h"]
	var z := float(h["z"]) - o.z
	var k := clampf((z + 16.0) / 14.0, 0.0, 1.0)
	var x := lerpf(o.x, _squad_x + o.x * 0.45, k)
	return Vector3(x, 0, z)


func _horde_front(hv: Dictionary) -> Vector3:
	var offs: Array = hv["offs"]
	if offs.is_empty():
		return Vector3(0, 0, float(hv["h"]["z"]))
	return _fig_pos(hv, offs[0])


func _target_point():
	if _state == "strike" or _state == "striking":
		return _hq.global_position + Vector3(0, 2.5, 0) if _hq else null
	match sim.target_kind:
		"horde":
			var hv: Dictionary = _hordes.get(sim.target_ref["id"], {})
			if hv.is_empty():
				return null
			var offs: Array = hv["offs"]
			if offs.is_empty():
				return null
			return _fig_pos(hv, offs[randi() % mini(offs.size(), 9)]) + Vector3(0, 1.0, 0)
		"gate":
			return Vector3(LANE_X[int(sim.target_ref["lane"])], 1.9, float(sim.target_ref.get("z", -10.0)))
		"obstacle":
			return _obstacle_pos(sim.target_ref) + Vector3(0, 0.8, 0)
	return null


func _fire(a: Dictionary, target: Vector3) -> void:
	var kind := String(a["kind"])
	var unit: Dictionary = sim.stats[kind]
	var rate := float(unit["rate"])
	if kind == "constable":
		var per := maxf(float(sim.squad.count("constable")) / maxf(float(_count_kind("constable")), 1.0), 1.0)
		rate *= minf(per, 2.5)
	a["fire_t"] = 1.0 / rate * randf_range(0.85, 1.15)
	var from: Vector3 = (a["pos"] as Vector3) + Vector3(0, 1.15, -0.4)
	var spread := Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), 0)
	fx.shoot(String(unit["proj"]), from, target + spread, 34.0 if unit["proj"] == "knife" else 55.0)
	if kind == "hero":
		Sfx.play("knife", -6.0)
		if sim.squad.hero_weapon != "":
			fx.shoot("bullet", from + Vector3(0.2, 0, 0), target + spread * 0.5, 55.0)
			Sfx.play("shot", -8.0)
	else:
		Sfx.play("shot", -10.0, 1.3 if kind == "constable" else 0.9)


func _count_kind(kind: String) -> int:
	var c := 0
	for a in _allies:
		if a["kind"] == kind:
			c += 1
	return c


func _free_horde(id: int) -> void:
	var hv: Dictionary = _hordes.get(id, {})
	if hv.is_empty():
		return
	(hv["label"] as Node).queue_free()
	(hv["sub"] as Node).queue_free()
	_hordes.erase(id)


func _physics_process(_delta: float) -> void:
	# Hordes that the sim removed (cleared or contact) and have no figures left.
	for id in _hordes.keys():
		var hv: Dictionary = _hordes[id]
		if int(hv["h"]["count"]) <= 0 and (hv["offs"] as Array).is_empty():
			_free_horde(id)


# ---------------------------------------------------------------- obstacles

func _obstacle_pos(ob: Dictionary) -> Vector3:
	return Vector3(LANE_X[int(ob["lane"])], 0, float(ob["z"]))


func _spawn_obstacle(ob: Dictionary) -> void:
	var n := Node3D.new()
	match String(ob.get("kind", "barricade")):
		"barrel":
			var body := World._box(Vector3(1.0, 1.3, 1.0), Color("c8352b"))
			body.position.y = 0.65
			n.add_child(body)
			var band := World._box(Vector3(1.06, 0.18, 1.06), Color("f2c14e"))
			band.position.y = 0.95
			n.add_child(band)
		"car":
			var body := World._box(Vector3(2.2, 0.9, 4.0), Color("3a6fd6"))
			body.position.y = 0.65
			n.add_child(body)
			var cab := World._box(Vector3(1.9, 0.7, 2.0), Color("9ec4ff"))
			cab.position = Vector3(0, 1.4, 0.2)
			n.add_child(cab)
		_:
			var bar := World._box(Vector3(2.8, 0.9, 0.4), Color("8a6a3f"))
			bar.position.y = 0.6
			n.add_child(bar)
	add_child(n)
	n.position = _obstacle_pos(ob)
	_obstacles[int(ob["id"])] = {"ob": ob, "node": n}


func _free_obstacle(id: int) -> void:
	var od: Dictionary = _obstacles.get(id, {})
	if od.is_empty():
		return
	(od["node"] as Node).queue_free()
	_obstacles.erase(id)


# ---------------------------------------------------------------- shield, finish, strike

func _build_shield() -> void:
	_shield = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 3.4
	sm.height = 4.4
	sm.is_hemisphere = true
	_shield.mesh = sm
	_shield_mat = StandardMaterial3D.new()
	_shield_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield_mat.albedo_color = Color(0.45, 0.75, 1.0, 0.25)
	_shield.material_override = _shield_mat
	_shield.visible = false
	add_child(_shield)


func _spawn_finish(at: float) -> void:
	_finish = Node3D.new()
	add_child(_finish)
	_finish.position.z = -(at - sim.traveled)
	# Chequered line
	for i in 20:
		for j in 2:
			var tile := World._box(Vector3(0.49, 0.03, 0.5), Color.WHITE if (i + j) % 2 == 0 else Color(0.1, 0.1, 0.1))
			tile.position = Vector3(-4.75 + i * 0.5, 0.02, j * 0.5)
			_finish.add_child(tile)
	# Gang hideout: the strike target.
	_hq = Node3D.new()
	_hq.position = Vector3(0, 0, -16)
	_finish.add_child(_hq)
	var body := World._box(Vector3(9, 6, 4), Color("4a3b3b"))
	body.position = Vector3(0, 3, 0)
	_hq.add_child(body)
	var roof := World._box(Vector3(9.6, 0.6, 4.6), Color("2b2222"))
	roof.position = Vector3(0, 6.3, 0)
	_hq.add_child(roof)
	var door := World._box(Vector3(2.4, 3.2, 0.2), Color("8c2a2a"))
	door.position = Vector3(0, 1.6, 2.05)
	_hq.add_child(door)
	for x in [-3.0, 3.0]:
		var win := World._box(Vector3(1.6, 1.0, 0.2), Color("1b1b1b"))
		win.position = Vector3(x, 3.8, 2.05)
		_hq.add_child(win)
	var sign := GateRowView._label(font, 110, 0.014)
	sign.text = "GANG HQ"
	sign.modulate = Color("ff6b6b")
	sign.position = Vector3(0, 5.2, 2.2)
	_hq.add_child(sign)
	var bar_bg := World._box(Vector3(6.2, 0.5, 0.2), Color(0.1, 0.1, 0.1))
	bar_bg.position = Vector3(0, 7.3, 0)
	_hq.add_child(bar_bg)
	_hq_fill = World._box(Vector3(6.0, 0.36, 0.22), Color("e0484f"))
	_hq_fill.position = Vector3(0, 7.3, 0.02)
	_hq.add_child(_hq_fill)


func _begin_strike() -> void:
	_state = "strike"
	_time_scale = 1.0
	Sfx.play("swoosh")
	strike_ready.emit()


## Called by the HUD when the player stops the needle.
func do_strike(mult: int) -> void:
	if _state != "strike":
		return
	_strike_mult = mult
	_strike_t = 0.0
	_state = "striking"
	Sfx.play("strike")


func _update_strike(delta: float) -> void:
	_strike_t += delta
	var dur := 1.6
	var k := clampf(_strike_t / dur, 0.0, 1.0)
	# Extra volleys so the strike feels like the whole squad unloading.
	if _strike_t < dur:
		for a in _allies:
			if randf() < delta * 6.0:
				_fire(a, _hq.global_position + Vector3(randf_range(-3, 3), randf_range(1, 5), 2.0))
		if randf() < delta * 10.0:
			fx.burst(_hq.global_position + Vector3(randf_range(-4, 4), randf_range(1, 5), 2.2), Color(1, 0.8, 0.4), 6, 4.0, 0.2, 0.4)
	_hq_fill.scale.x = maxf(1.0 - k, 0.001)
	if _strike_t >= dur and _strike_t - delta < dur:
		fx.explosion(_hq.global_position + Vector3(0, 3, 0), 2.5)
		fx.confetti(_hq.global_position + Vector3(0, 5, 0), 60)
		world.shake(1.2)
		Sfx.play("boom")
		Sfx.play("win")
		Game.vibrate(200)
		_hq.visible = false
	if _strike_t >= dur + 0.9:
		_state = "done_win"
		finished.emit({"won": true, "troops": sim.squad.total(), "mult": _strike_mult, "kills": sim.kills, "level": level_id})
