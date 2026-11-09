extends Node
## App flow (spec §1, §5.7):
##   boot -> [welcome back (offline city coins)] -> [daily calendar, once a day] -> city map
##   map Play -> boosters -> level -> Bottle Shot -> win: stars + coins (x2 ad) -> [star chest]
##     -> [interstitial, Ads rules] -> map (pin hops to the new level; Next also opens the
##     next level's boosters) -> after a district boss: liberation celebration
##   loss -> revive offer (once per level, rewarded ad) -> "so close" result -> Retry / Home
## A brand-new player skips the menu and lands in level 1 (fast first win), then the map.
##
## Debug args (after `--`, key=value):
##   level=N        start level N at once (no boosters)    autoplay=1  lanes=2,1,1  strike=1
##   boosters=headstart,bomb   tokens to take into a level= run (free, for tests)
##   stop_at=win|loss|revive (screenshot 3 s into that screen, then quit)
##   frames=N screenshot=path shots=100,200 out=prefix  report=1 (print the result)
##   chain=N (autoplay: after a win go result -> map -> next level, until level N)
##   revive=1 (offer the revive under autoplay too; revive=auto also takes it after 1 s)
##   reset=1 (fresh save)  coins=N (and unlock every level)  save=path (play on a copy of that
##   JSON save, never written)  lobby=1 (menu even for a new player)  ads=1 (show the ad
##   popup even under autoplay)
##   panel=station|style|settings|daily|missions|spin|codex|booster|chest|welcome|revive|
##         liberation|map   (open that screen over the map; map = the map alone)
## Autoplay skips boosters, the revive offer and the ad popups.

var world: World
var fx: Fx
var ui: CanvasLayer
var view: LevelView
var hud: Hud
var lobby: Lobby
var result: ResultPanel
var pause_panel: Control
var current_level := 1

var _args := {}
var _frame := 0
var _pilot: Autopilot
var _boosters := {}          # tokens taken into the current level
var _powers_used := {}       # shield / bomb charges used this level (mission stats)
var _charges := {}
var _revive_offered := false
var _last_win := {}          # Game.win_level() result of the level just won ({} after a loss)
var _boot_popups_done := false
var _daily_shown := ""       # date the daily popup last opened by itself
var _flow_busy := false      # a result -> map sequence is running (ignore double taps)
var _back_armed := 0         # msec of the last Back on the bare map (twice in 2 s quits)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _args.has("save") and FileAccess.file_exists(String(_args["save"])):
		Game.save_path = ""
		Game.boot(Config.load_json(String(_args["save"])))
		Game.set_meta("debug_save", true)
	if _args.has("reset"):
		Game.reset_progress()
	if _args.has("coins"):
		Game.save["coins"] = int(_args["coins"])
		Game.save["unlocked"] = Config.LEVEL_COUNT
	if _autoplay() and not _args.has("ads"):
		Ads.skip_ads = true
	if _autoplay() or Game.has_meta("debug_save"):
		# Test runs keep the player's real analytics log clean.
		Analytics.log_path = "user://events_debug.log"
		Analytics.old_path = "user://events_debug.old.log"
	get_tree().process_frame.connect(_on_frame)
	world = World.new()
	add_child(world)
	fx = Fx.new()
	fx.font = UiKit.FONT
	add_child(fx)
	ui = CanvasLayer.new()
	add_child(ui)
	result = ResultPanel.new()
	result.next_pressed.connect(func(): _leave_result(true))
	result.lobby_pressed.connect(func(): _leave_result(false))
	result.retry_pressed.connect(func(): _open_boosters(current_level, true))
	result.station_pressed.connect(_open_station_from_result)
	ui.add_child(result)
	result.visible = false
	if _args.has("level"):
		_start_level(int(_args["level"]), _debug_boosters())
	elif _is_new_player() and not _args.has("lobby") and not _args.has("panel"):
		_start_level(1)  # brand-new player: straight into the action, no menu
	else:
		_show_lobby()


func _autoplay() -> bool:
	return _args.has("autoplay") and String(_args["autoplay"]) != "0"


func _is_new_player() -> bool:
	return int(Game.save["unlocked"]) <= 1 and not Game.level_beaten(1)


## boosters=headstart,bomb: free tokens for a level= test run (not taken from the save).
func _debug_boosters() -> Dictionary:
	var out := {}
	for id in String(_args.get("boosters", "")).split(",", false):
		out[id] = int(out.get(id, 0)) + 1
	return out


# ---------------------------------------------------------------- lobby (city map)

## Shows the map. `advance` = level just beaten (the pin hops from it), `liberated` = district
## freed by that win (celebration), `then_level` > 0 opens that level's boosters afterwards.
func _show_lobby(advance := 0, liberated := 0, then_level := 0) -> void:
	_clear_level()
	result.visible = false
	world.visible = false  # the map covers the screen: no 3D street behind it
	if world.has_method("set_theme"):
		world.set_theme(Game.current_district())
	lobby = Lobby.new()
	lobby.play_pressed.connect(func(n: int): _open_boosters(n))
	lobby.daily_pressed.connect(func(): lobby.open_panel(DailyPanel.new()))
	lobby.spin_pressed.connect(func(): lobby.open_panel(SpinPanel.new()))
	lobby.missions_pressed.connect(func(): lobby.open_panel(MissionsPanel.new()))
	lobby.codex_pressed.connect(func(): lobby.open_panel(CodexPanel.new()))
	lobby.star_chest_pressed.connect(func(): lobby.open_panel(StarChestPanel.new()))
	ui.add_child(lobby)
	ui.move_child(lobby, 0)
	Sfx.play_music("menu")
	if advance > 0:
		lobby.map.advance_from(advance)
	if _args.has("panel"):
		_boot_popups_done = true
		_debug_panel(String(_args["panel"]))
		return
	var steps: Array = []
	if _autoplay():
		# Autoplay chain (chain=N): no popups, straight on to the next level.
		_boot_popups_done = true
		if liberated > 0 and _args.has("report"):
			print("LIBERATED ", liberated)
		liberated = 0
	if liberated > 0:
		steps.append(func(next: Callable): _celebrate(liberated, next))
	if not _boot_popups_done:
		_boot_popups_done = true
		steps.append(_welcome_back_step)
		steps.append(_daily_step)
	if then_level > 0 and liberated == 0:
		steps.append(func(next: Callable):
			_after(1.3, func():
				if is_instance_valid(lobby):
					_open_boosters(then_level)
				next.call()))
	_run_steps(steps, 0.9 if advance > 0 else 0.35)


## Runs popup steps one after another; each is func(next: Callable) and calls next when done.
func _run_steps(steps: Array, delay := 0.35) -> void:
	if steps.is_empty():
		return
	var lob := lobby
	var go := func(): _step(steps, 0, lob)
	_after(delay, go)


func _step(steps: Array, i: int, lob: Lobby) -> void:
	if i >= steps.size() or not is_instance_valid(lob) or lob != lobby:
		return
	(steps[i] as Callable).call(func(): _step(steps, i + 1, lob))


## Opens `p` over the map and calls next() once it closes.
func _panel_step(p: Control, next: Callable) -> void:
	if not is_instance_valid(lobby):
		return
	if p.has_signal("closed"):
		p.connect("closed", func(): _after(0.25, next), CONNECT_ONE_SHOT)
	lobby.open_panel(p)


func _welcome_back_step(next: Callable) -> void:
	var coins := Game.welcome_back()
	if coins > 0:
		_panel_step(WelcomeBackPanel.new(coins), next)
	else:
		next.call()


func _daily_step(next: Callable) -> void:
	if bool(Game.daily_state().get("can_claim", false)) and _daily_shown != Game.today():
		_daily_shown = Game.today()
		_panel_step(DailyPanel.new(), next)
	else:
		next.call()


## District boss beaten: the celebration, then the map glides to the district's buildings.
func _celebrate(district: int, next: Callable) -> void:
	var p := LiberationPanel.new(district)
	p.closed.connect(func():
		if is_instance_valid(lobby):
			lobby.map.focus_level(district * 10 - 5, true)
		_after(0.3, next), CONNECT_ONE_SHOT)
	lobby.open_panel(p)


func _debug_panel(name: String) -> void:
	var lv := lobby.map.selected if lobby.map else 1
	match name:
		"station":
			lobby.open_panel(StationPanel.new())
		"style":
			lobby.open_panel(StylePanel.new())
		"settings":
			lobby.open_panel(SettingsPanel.new())
		"daily":
			lobby.open_panel(DailyPanel.new())
		"missions":
			lobby.open_panel(MissionsPanel.new())
		"spin":
			lobby.open_panel(SpinPanel.new())
		"codex":
			lobby.open_panel(CodexPanel.new())
		"booster":
			_open_boosters(lv)
		"chest":
			lobby.open_panel(StarChestPanel.new())
		"welcome":
			lobby.open_panel(WelcomeBackPanel.new(maxi(Game.city_pending(), 840)))
		"revive":
			lobby.open_panel(RevivePanel.new(0.82, 64))
		"liberation":
			lobby.open_panel(LiberationPanel.new(int(_args.get("district", "1"))))
		"ad":
			Ads.skip_ads = false
			Ads.show_rewarded("x2_coins", func(_ok: bool): pass)
		"interstitial":
			Ads.skip_ads = false
			Ads.show_interstitial("between_levels")
		"map", _:
			pass


## Boosters before a level (skipped under autoplay). Over the result screen for Retry.
func _open_boosters(n: int, over_result := false) -> void:
	if _autoplay():
		_start_level(n)
		return
	var p := BoosterPanel.new(n)
	p.start.connect(func(used: Dictionary): _start_level.call_deferred(n, used), CONNECT_ONE_SHOT)
	if is_instance_valid(lobby) and not over_result:
		lobby.open_panel(p)
	else:
		ui.add_child(p)


## Station over the result screen; closing it returns to the result (badges refresh).
func _open_station_from_result() -> void:
	var p := StationPanel.new()
	ui.add_child(p)
	p.tree_exited.connect(func():
		if is_instance_valid(result):
			result.refresh_alerts())


# ---------------------------------------------------------------- level

func _start_level(n: int, boosters: Dictionary = {}) -> void:
	_clear_level()
	result.visible = false
	world.visible = true
	current_level = n
	_boosters = boosters
	_powers_used = {}
	_revive_offered = false
	_last_win = {}
	_flow_busy = false
	var level := Config.level(n)
	view = LevelView.new().setup(level, Game.level_upgrades(boosters), world, fx, UiKit.FONT)
	add_child(view)
	if world.has_method("set_theme"):
		world.set_theme(ceili(n / 10.0))
	hud = Hud.new()
	ui.add_child(hud)
	ui.move_child(hud, 0)
	hud.set_level(n, String(level.get("name", "")))
	view.hint.connect(hud.show_hint)
	view.banner.connect(hud.show_banner)
	view.charges_changed.connect(_on_charges)
	view.squad_changed.connect(hud.set_troops)
	hud.set_capacity(view.sim.squad.cap)
	hud.set_troops(view.sim.squad.total())
	view.tutorial.connect(hud.set_tutorial)
	view.strike_ready.connect(hud.enter_finale)
	view.finished.connect(_on_finished)
	if view.has_signal("rank_joined"):
		view.connect("rank_joined", _on_rank_joined)
	hud.power_pressed.connect(func(id): view.use_power(id))
	hud.pause_pressed.connect(_toggle_pause)
	_charges = view.sim.charges.duplicate()
	hud.set_charges(view.sim.charges)
	Sfx.play_music("boss" if Economy.is_boss(n, Game.economy) else "level")
	Game.level_started(n, boosters)
	if _autoplay():
		var lanes: Array = []
		for s in String(_args.get("lanes", "2,1,1,0,0")).split(","):
			lanes.append(int(s))
		_pilot = Autopilot.new(lanes, true)
		view.input_enabled = false
		hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.power_pressed.disconnect(hud.power_pressed.get_connections()[0]["callable"])


## Charges only ever drop when a power is used: count them for the missions.
func _on_charges(c: Dictionary) -> void:
	for id in c:
		var drop := int(_charges.get(id, 0)) - int(c[id])
		if drop > 0:
			_powers_used[id] = int(_powers_used.get(id, 0)) + drop
	_charges = c.duplicate()
	if hud:
		hud.set_charges(c)


## A rank joins the squad: its card shows once ever (Codex-style stats).
func _on_rank_joined(unit: String, _first_time: Variant = true) -> void:
	if hud and Game.mark_rank_seen(unit):
		hud.show_rank(unit)


func _clear_level() -> void:
	for n in [view, hud, lobby, pause_panel]:
		if is_instance_valid(n):
			n.queue_free()
	view = null
	hud = null
	lobby = null
	pause_panel = null
	_pilot = null
	fx.clear()


## Mission counters from this run: kills (all and per enemy kind), bottles, powers used.
func _run_stats(r: Dictionary) -> Dictionary:
	var s := {"kill": int(view.sim.kills)}
	var by: Variant = view.sim.get("kills_by")
	if by is Dictionary:
		for kind in by:
			s["kill_" + String(kind)] = int(by[kind])
	if r.get("won", false):
		s["bottle"] = int(r.get("broken", 0)) + int(r.get("gold", 0))
		s["gold_bottle"] = int(r.get("gold", 0))
	for id in _powers_used:
		s[id] = int(_powers_used[id])
	return s


func _run_info(r: Dictionary) -> Dictionary:
	return {"troops": view.sim.squad.total(), "peak": view.sim.peak_squad,
		"time": snappedf(view.sim.time, 0.1), "boosters": _boosters, "revived": view.sim.revived,
		"cause": String(r.get("cause", ""))}


func _on_finished(r: Dictionary) -> void:
	if _args.has("report"):
		print("RESULT ", r, " troops_now=", view.sim.squad.total(), " stars=", view.sim.stars())
	if r["won"]:
		var stars := view.sim.stars()
		_last_win = Game.win_level(current_level, int(r.get("coins", 0)), stars, _run_stats(r), _run_info(r))
		var shown := {"coins": int(_last_win["coins"]), "stars": stars, "broken": r.get("broken", 0),
			"gold": r.get("gold", 0), "star_chest_ready": _last_win["star_chest_ready"]}
		if r.has("mult"):
			shown["mult"] = r["mult"]
		result.show_win(current_level, shown, current_level < Config.LEVEL_COUNT)
		_stop_at("win")
		if _args.has("report"):
			print("WIN ", _last_win)
		if _autoplay() and current_level < int(_args.get("chain", "0")):
			_after(2.0, func(): _leave_result(true))
	elif not view.sim.revived and not _revive_offered and (not _autoplay() or _args.has("revive")):
		_offer_revive(r)
		return
	else:
		_show_loss(r)
	if hud:
		hud.visible = false


## Near miss: one revive per level for a rewarded ad (no countdown, X = give up).
func _offer_revive(r: Dictionary) -> void:
	_revive_offered = true
	var p := RevivePanel.new(view.sim.progress(), view.sim.peak_squad, view.sim.revive_troops())
	p.revive.connect(_do_revive, CONNECT_ONE_SHOT)
	p.give_up.connect(func(): _show_loss(r), CONNECT_ONE_SHOT)
	ui.add_child(p)
	_stop_at("revive")
	if String(_args.get("revive", "")) == "auto":
		_after(1.0, func():
			if is_instance_valid(p):
				p.emit_signal("revive")
				p.queue_free())


func _do_revive() -> void:
	if view == null:
		return
	var troops := view.sim.revive_troops()
	if _args.has("report"):
		print("REVIVE troops=", troops, " peak=", view.sim.peak_squad)
	if view.has_method("revive"):
		view.call("revive", troops)
	elif view.sim.revive(troops):
		# LevelView without its own revive(): back to play and bring the troops back on screen.
		view.set("_state", "play")
		if view.has_method("_handle_events"):
			view.call("_handle_events", view.sim.drain())
		if view.has_method("_sync_allies"):
			view.call("_sync_allies", Vector3(float(view.get("_squad_x")), 0, 0))
		view.squad_changed.emit(view.sim.squad.total())
	if hud:
		hud.visible = true
	Sfx.play_music("boss" if Economy.is_boss(current_level, Game.economy) else "level")


func _show_loss(r: Dictionary) -> void:
	if view == null:
		return
	Game.lose_level(current_level, _run_stats(r), _run_info(r))
	result.show_loss(current_level, String(r.get("cause", "")), view.sim.progress(), view.sim.peak_squad)
	_stop_at("loss")
	if hud:
		hud.visible = false


## Result -> [star chest] -> [interstitial] -> map. Next also opens the next level's boosters.
func _leave_result(go_next: bool) -> void:
	if _flow_busy:
		return
	_flow_busy = true
	var won := not _last_win.is_empty()
	var beaten := current_level if won else 0
	var liberated := int(_last_win.get("liberated", 0)) if won else 0
	var next_level := mini(current_level + 1, Config.LEVEL_COUNT) if go_next and won else 0
	var to_map := func(): _show_lobby(beaten, liberated, next_level)
	var after_chest := func():
		if won and Ads.can_show_interstitial(current_level):
			Ads.show_interstitial("between_levels", to_map)
		else:
			to_map.call()
	if won and bool(Game.star_chest_progress().get("ready", false)):
		var p := StarChestPanel.new()
		p.closed.connect(after_chest, CONNECT_ONE_SHOT)
		ui.add_child(p)
	else:
		after_chest.call()


## stop_at=win|loss|revive with screenshot=path: save the screen 3 s into that screen, then quit.
func _stop_at(what: String) -> void:
	if String(_args.get("stop_at", "")) != what:
		return
	_after(3.0, func():
		if _args.has("screenshot"):
			get_viewport().get_texture().get_image().save_png(String(_args["screenshot"]))
		get_tree().quit())


func _after(seconds: float, cb: Callable) -> void:
	get_tree().create_timer(seconds).timeout.connect(cb)


# ---------------------------------------------------------------- pause, back, frame

func _toggle_pause() -> void:
	if view == null:
		return
	if is_instance_valid(pause_panel):
		pause_panel.queue_free()
		pause_panel = null
		view.paused = false
		return
	view.paused = true
	pause_panel = Control.new()
	UiKit.full_rect(pause_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	UiKit.full_rect(dim)
	pause_panel.add_child(dim)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.offset_left = -240
	col.offset_right = 240
	col.offset_top = -200
	col.offset_bottom = 200
	col.add_theme_constant_override("separation", 20)
	pause_panel.add_child(col)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var resume := UiKit.icon_button("play", "green", 200)
	resume.pressed.connect(_toggle_pause)
	col.add_child(resume)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)
	var restart := UiKit.icon_button("retry", "yellow", 130)
	restart.pressed.connect(func(): _start_level(current_level, {}))
	row.add_child(restart)
	var quit := UiKit.icon_button("home", "blue", 130)
	quit.pressed.connect(func(): _show_lobby())
	row.add_child(quit)
	ui.add_child(pause_panel)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if Ads.is_showing():
			return  # the ad popup handles back itself
		for c in ui.get_children():
			if c is RetentionPanel:
				return  # revive / boosters / chest over the level or result close themselves
		if hud != null and hud.visible:
			if view and view.sim.state == "run":
				_toggle_pause()
		elif lobby != null:
			# A panel may already have closed itself on this Back: quitting needs a second Back.
			if not lobby.close_overlay():
				if Time.get_ticks_msec() - _back_armed < 2000:
					get_tree().quit()
				_back_armed = Time.get_ticks_msec()
		elif result.visible:
			_leave_result(false)
		else:
			_show_lobby()
	elif what == NOTIFICATION_APPLICATION_PAUSED and hud != null and hud.visible and view and view.sim.state == "run" and not is_instance_valid(pause_panel):
		_toggle_pause()
	elif what == NOTIFICATION_APPLICATION_RESUMED and lobby != null and is_instance_valid(lobby):
		# Back from the background: offer the city coins earned meanwhile.
		if not is_instance_valid(lobby.get("_overlay")) and Game.welcome_back() > 0:
			_welcome_back_step(func(): pass)


func _process(_delta: float) -> void:
	if _pilot and view and view.sim.state == "run":
		_pilot.drive(view.sim)
	if _args.has("strike") and view and view.finale and view.finale._state == "aim" and _frame % 40 == 0:
		# Autoplay the finale: aim where the next unbroken bottle will be when the knife lands.
		var lg: BottleLogic = view.finale.logic
		for i in lg.count():
			if not lg.broken[i]:
				view.finale.throw_at(lg.position(i, view.finale._ft + 0.55))
				break


## Frame counter for screenshots: a SceneTree signal, so it keeps counting while an ad popup
## pauses the game.
func _on_frame() -> void:
	_frame += 1
	if _args.has("shots") and String(_args["shots"]).split(",").has(str(_frame)):
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [_args.get("out", "shot"), _frame])
	if _args.has("frames") and _frame == int(_args["frames"]):
		if _args.has("screenshot"):
			var img := get_viewport().get_texture().get_image()
			img.save_png(String(_args["screenshot"]))
		get_tree().quit()
