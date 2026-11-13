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
##   powers=0 (autoplay never uses the shield or bomb: incoming fire lands, for screenshots)
##   reset=1 (fresh save)  coins=N (and unlock every level)  save=path (play on a copy of that
##   JSON save, never written)  lobby=1 (menu even for a new player)  ads=1 (show the ad
##   popup even under autoplay)
##   tutor=auto (the first-run tutorials run even under autoplay and act themselves out
##   after 1.6 s, for screenshots)
##   perf=1 (frame-time log: _local/perf.log, one line per frame: frame, ms, pipelines
##   compiled, events; the worst level frames are printed when the level ends; perf=path)
##   boot=1 (play the brand boot screens even with debug args; boot=0 skips them)
##   shield_at=N (press the shield at frame N, with a charge if the squad has none: screenshots)
##   safe_top=N safe_bottom=N (pretend the phone has a notch / gesture bar N UI px high: the
##         layout under a cut-out, on a PC)
##   panel=station|armory|style|settings|daily|missions|spin|codex|booster|chest|welcome|revive|
##         liberation|map   (open that screen over the map; map = the map alone)
##   panel=rank unit=sergeant (the New Rank card)  tab=enemies (panel=codex: that tab)  tip=<stat key> tip_n=N (tap the N-th stat icon with that
##         StatTip key after 0.8 s: damage, rate, power, pierce, splash, melee...)
## Autoplay skips boosters, the revive offer, the ad popups and the tutorials.

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
var _boot: BootSequence      # the brand boot screens while they run
var _boot_held: Array = []   # their warmed resources, kept alive behind the age screen
var _daily_shown := ""       # date the daily popup last opened by itself
var _flow_busy := false      # a result -> map sequence is running (ignore double taps)
var _back_armed := 0         # msec of the last Back on the bare map (twice in 2 s quits)
var _perf: FileAccess = null # perf=1 frame-time log
var _perf_last := 0          # usec of the previous frame
var _perf_level_t := 0.0     # seconds since the level started (the first 2 s are loading)
var _perf_worst: Array = []  # [ms, frame, pipelines, marks]: slow or compiling level frames after 2 s
var _perf_pipes: Array = []   # pipeline compilations so far per kind (Performance monitors)
var _perf_max := 0.0         # the slowest level frame after the first 2 s
var _perf_done := false      # the level's PERF report is printed
var _perf_finale_t := 0.0    # seconds into the finale (its first 2 s count in the report)
var _perf_shatters := 0      # bottles shattered so far in the finale (perf marks)
var _perf_shatter_t := 0.0   # seconds since the first shatter (1 s of it counts in the report)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _args.has("save"):
		# Never fall back to the player's real save: a missing file means a blank new player.
		Game.save_path = ""
		var path := String(_args["save"])
		Game.boot(Config.load_json(path) if FileAccess.file_exists(path) else {})
		Game.set_meta("debug_save", true)
	elif _debug_run() and not _args.has("write"):
		# Debug and review runs (autoplay, level=, coins=, reset=, screenshots...) play on a
		# throwaway copy of the save and never write the player's real save.json.
		# write=1 persists on purpose; real_reset=1 wipes the real save.
		Game.save_path = ""
		Game.set_meta("debug_save", true)
	if _args.has("reset") or _args.has("real_reset"):
		Game.reset_progress()
	if _args.has("safe_top") or _args.has("safe_bottom"):
		UiKit.debug_safe = Vector2(float(_args.get("safe_top", "0")), float(_args.get("safe_bottom", "0")))
		_fake_cutout(UiKit.debug_safe.x)
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
	if _args.has("perf"):
		var pp := String(_args["perf"])
		_perf = FileAccess.open(ProjectSettings.globalize_path("res://_local/perf.log") if pp == "1" else pp, FileAccess.WRITE)
		_perf_last = Time.get_ticks_usec()
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
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
	if result.has_signal("tip_pressed"):
		result.tip_pressed.connect(_open_tip_from_result)
	ui.add_child(result)
	result.visible = false
	if _boot_screens():
		# Brand (owner 2026-11-12): axnex intro -> key-art loading screen; the flow builds once its loads are in.
		_boot = BootSequence.new(BootSequence.is_first_launch(), _begin_flow)
		add_child(_boot)
	else:
		_begin_flow()


## The boot screens play on a normal launch (no debug args) or with boot=1; never headless.
func _boot_screens() -> bool:
	if _args.has("boot"):
		return String(_args["boot"]) != "0"
	return _args.is_empty() and DisplayServer.get_name() != "headless"


## The start of the app flow, after the boot screens.
func _begin_flow() -> void:
	if AgeScreen.needed(_args):
		# v2 §8: the neutral age screen comes first, once, before any ad or analytics SDK starts.
		# The boot's warmed crowds (or map) stay alive behind it until the first screen holds
		# its own; dropped, they would leave the cache and level 1 would load them all again.
		if is_instance_valid(_boot):
			_boot_held = _boot.held
		var age := AgeScreen.new()
		age.done.connect(_begin, CONNECT_ONE_SHOT)
		ui.add_child(age)
		return
	_begin()


## The first screen after boot (and after the age screen on a first launch): a level= run, a
## brand-new player's level 1, or the map.
func _begin() -> void:
	if _args.has("level"):
		_start_level(int(_args["level"]), _debug_boosters())
	elif _is_new_player() and not _args.has("lobby") and not _args.has("panel"):
		_start_level(1)  # brand-new player: straight into the action, no menu
	else:
		_show_lobby()
	_boot_held = []  # the first screen holds its own references now


## True for runs started with a debug arg that would otherwise change the real save.
func _debug_run() -> bool:
	for k in ["autoplay", "level", "coins", "reset", "stop_at", "frames", "shots", "screenshot", "chain", "boosters", "district", "perf"]:
		if _args.has(k):
			return true
	return false


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
	if bool(Game.daily_state().get("can_claim", false)) and _daily_shown != Game.today() and not Game.first_build_pending():
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
		"armory":
			lobby.open_panel(ArmoryPanel.new())
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
			var cp := CodexPanel.new()
			cp.start_tab = String(_args.get("tab", "ranks"))
			lobby.open_panel(cp)
		"rank":
			lobby.open_panel(RankUnlockPanel.new(String(_args.get("unit", "sergeant"))))
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
	if _args.has("tip"):
		_after(0.8, _debug_tip.bind(String(_args["tip"]), int(_args.get("tip_n", "0"))))


## tip=<stat key> [tip_n=N]: taps the N-th stat icon with that StatTip key on the open panel.
func _debug_tip(key: String, nth: int) -> void:
	var found: Array = []
	for c in lobby.find_children("*", "Control", true, false):
		if String((c as Control).get_meta("stat_tip", "")) == key:
			found.append(c)
	if nth >= found.size():
		return
	var c: Control = found[nth]
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = c.size * 0.5
		c.gui_input.emit(ev)


## Boosters before a level (skipped under autoplay). Over the result screen for Retry.
func _open_boosters(n: int, over_result := false) -> void:
	if _autoplay():
		_start_level(n)
		return
	# v1.1: a rank unlocking at this level gets its New Rank card first (once ever).
	var due := Game.rank_card_due(n)
	if due != "":
		Game.mark_rank_card(due)
		var card := RankUnlockPanel.new(due)
		card.closed.connect(func(): _open_boosters.call_deferred(n, over_result), CONNECT_ONE_SHOT)
		if is_instance_valid(lobby) and not over_result:
			lobby.open_panel(card)
		else:
			ui.add_child(card)
		return
	var p := BoosterPanel.new(n)
	p.start.connect(func(used: Dictionary): _start_level.call_deferred(n, used), CONNECT_ONE_SHOT)
	if is_instance_valid(lobby) and not over_result:
		lobby.open_panel(p)
	else:
		ui.add_child(p)


## The loss tip's item over the result screen (v2): the Armory on a weapon, else the Station.
func _open_tip_from_result() -> void:
	if result.visible and not Armory.track(result.tip_room).is_empty():
		var a := ArmoryPanel.new()
		a.focus_id = result.tip_room
		ui.add_child(a)
		result.cover(true)
		a.tree_exited.connect(func():
			if is_instance_valid(result):
				result.refresh_alerts())
		return
	_open_station_from_result()


## Station over the result screen; closing it returns to the result (badges refresh).
func _open_station_from_result() -> void:
	var p := StationPanel.new()
	p.focus_room = result.tip_room if result.visible and Game.economy["station"].has(result.tip_room) else ""
	ui.add_child(p)
	result.cover(true)
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
	view = LevelView.new().setup(level, Game.level_upgrades(boosters, n), world, fx, UiKit.FONT)
	view.perf_on = _perf != null
	_perf_level_t = 0.0
	_perf_finale_t = 0.0
	_perf_shatters = 0
	_perf_shatter_t = 0.0
	_perf_done = false
	_perf_max = 0.0
	_perf_worst.clear()
	add_child(view)
	if world.has_method("set_theme"):
		world.set_theme(ceili(n / 10.0), String(level.get("look", "")))   # v2.1: the level's own look
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
	hud.power_pressed.connect(func(id): view.use_power(id, hud.power_rect(id)))
	hud.pause_pressed.connect(_toggle_pause)
	_charges = view.sim.charges.duplicate()
	hud.set_charges(view.sim.charges)
	Sfx.play_music("level")  # LevelView switches to "boss" when the Kingpin walks in, and back when he dies
	Game.level_started(n, boosters)
	var improved := Game.take_improvements()
	if not _autoplay():
		RankToast.show_upgrades(hud, improved)  # v1.1: what the last Station visit improved
	if not _autoplay() or String(_args.get("tutor", "")) == "auto":
		# v1.1: first-run freeze-frame tutorials, each once ever. Never under autoplay, except
		# tutor=auto (debug: each step acts itself out, for screenshots).
		hud.tutor = true
		view.add_child(Tutorial.new().setup(view, hud, String(_args.get("tutor", "")) == "auto"))
	if _autoplay():
		# lanes=… wins; otherwise the level's stored winning route (tune.gd), then a fixed default.
		var lanes: Array = []
		if _args.has("lanes") or (level.get("route", []) as Array).is_empty():
			for s in String(_args.get("lanes", "2,1,1,0,0")).split(","):
				lanes.append(int(s))
		else:
			lanes = (level["route"] as Array).duplicate()
		# powers=0 keeps the shield and bomb unused; the pilot dodges telegraphs (spec v2.1: bosses are calibrated so).
		_pilot = Autopilot.new(lanes, String(_args.get("powers", "1")) != "0", true)
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
	# v2 powers: a level left before its end (restart, home) still spends the charges it used.
	if is_instance_valid(view) and view.sim != null:
		Game.settle_powers(view.sim.charges)
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


## level_end's params. Spec v2 §2 analytics: taps per minute of the level, so wins and losses
## split by tap-rate band (the last 10 s tap_rate bucket is closed here too).
func _run_info(r: Dictionary) -> Dictionary:
	Analytics.end_taps()
	return {"troops": view.sim.squad.total(), "peak": view.sim.peak_squad,
		"time": snappedf(view.sim.time, 0.1), "boosters": _boosters, "revived": view.sim.revived,
		"cause": String(r.get("cause", "")), "charges": view.sim.charges.duplicate(),
		"taps_per_min": int(round(view.taps * 60.0 / maxf(view.sim.time, 1.0)))}


func _on_finished(r: Dictionary) -> void:
	if _args.has("report"):
		print("RESULT ", r, " troops_now=", view.sim.squad.total(), " stars=", view.sim.stars())
	if r["won"]:
		var stars := view.sim.stars()
		_last_win = Game.win_level(current_level, int(r.get("coins", 0)), stars, _run_stats(r), _run_info(r))
		var shown := {"coins": int(_last_win["coins"]), "stars": stars, "broken": r.get("broken", 0),
			"gold": r.get("gold", 0), "tap_pct": r.get("tap_pct", 0), "star_chest_ready": _last_win["star_chest_ready"]}
		if r.has("mult"):
			shown["mult"] = r["mult"]
		result.show_win(current_level, shown, current_level < Config.LEVEL_COUNT)
		_stop_at("win")
		if _args.has("report"):
			print("WIN ", _last_win)
		if _autoplay() and current_level < int(_args.get("chain", "0")):
			_after(2.0, func(): _leave_result(true))
	elif not view.sim.revived and not _revive_offered and (not _autoplay() or _args.has("revive")) 			and revive_can_win(view.sim, (view.get("_level") as Dictionary).get("route", []) if view.get("_level") is Dictionary else []):
		_offer_revive(r)
		return
	else:
		_show_loss(r)
	if hud:
		hud.visible = false


## Review v2.1 (ux): the revive is offered only when it can win. A headless copy of the lost
## street is revived (LevelSim.revive) and played on by a pilot (the stored route's lanes for
## the rows left, the free shield and bomb, stepping out of most marks, tapping 2/s) for at most
## REVIVE_FORK_S sim seconds; it has to reach the stash. An ad that buys a dead end is never sold.
const REVIVE_FORK_S := 90.0
static func revive_can_win(sim: LevelSim, route: Array) -> bool:
	var c := sim.clone()
	if not c.revive(c.revive_troops()):
		return false
	c.drain()
	var lanes: Array = route.duplicate()
	while lanes.size() < c.rows_passed:
		lanes.append(c.lane)
	var pilot := Autopilot.new(lanes, true, true, 2.0, 0.7)
	var t0 := c.time
	while c.state == "run" and c.time - t0 < REVIVE_FORK_S:
		pilot.drive(c)
		c.step(1.0 / 30.0)
		c.drain()
	return c.state != "lost"


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
	Sfx.play_music("boss" if bool(view.get("_boss_music")) else "level")


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
		if _autoplay():  # nobody taps under autoplay (chain=N would stall here)
			_after(2.5, func(): if is_instance_valid(p) and p.is_inside_tree(): p.close())
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
	col.offset_top = -270
	col.offset_bottom = 270
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
	restart.pressed.connect(func(): _start_level(current_level, _boosters))  # same attempt: keep the boosters
	row.add_child(restart)
	var quit := UiKit.icon_button("home", "blue", 130)
	quit.pressed.connect(func(): _show_lobby())
	row.add_child(quit)
	# Sound and music, right where players notice them (same toggles as the lobby settings).
	var audio := HBoxContainer.new()
	audio.alignment = BoxContainer.ALIGNMENT_CENTER
	audio.add_theme_constant_override("separation", 20)
	col.add_child(audio)
	audio.add_child(SettingsPanel.toggle_button("sound", "sound", "sound_off", 110))
	audio.add_child(SettingsPanel.toggle_button("music", "music", "music_off", 110))
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
	if is_instance_valid(hud) and is_instance_valid(view):
		hud.set_progress(view.sim.progress())  # goal gradient: the bar fills towards the Gang HQ
		hud.set_firepower(view.sim.live_power(), Hud.steady_power(view.sim))  # spec v2 §12.4: live firepower next to the troops; its +N / -N hint
		hud.set_shield(view.sim.shield_t if view.sim.state == "run" else 0.0)  # drains round the button
	if _pilot and view and view.sim.state == "run" and not view.hold:  # a tutorial step steers
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
	if _perf:
		_perf_frame()
	if _args.has("shield_at") and _frame == int(_args["shield_at"]) and is_instance_valid(view):
		view.sim.charges["shield"] = maxi(int(view.sim.charges.get("shield", 0)), 1)
		view.use_power("shield")
	if _args.has("shots") and String(_args["shots"]).split(",").has(str(_frame)):
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [_args.get("out", "shot"), _frame])
	if _args.has("frames") and _frame == int(_args["frames"]):
		if _args.has("screenshot"):
			var img := get_viewport().get_texture().get_image()
			img.save_png(String(_args["screenshot"]))
		get_tree().quit()


## perf=1: one line per frame: frame, wall ms, process ms, gpu ms, pipelines compiled this
## frame (shader/material first use: the classic join hitch), level state:squad, sim events.
## Frames over 33 ms or with a pipeline compile after a level's first 2 s are listed, worst
## first, when the level ends (PERF lines on stdout) and at quit.
func _perf_frame() -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _perf_last) / 1000.0
	_perf_last = now
	var marks := ""
	var st := "menu"
	var playing := false
	if is_instance_valid(view):
		_perf_level_t += 1.0 / 60.0  # by frames: the loading frame itself must not count as 2 s
		st = "%s:%d" % [view._state, view.sim.squad.total()]
		playing = view._state == "play"
		# Spec v2 §3: the burst into the stash counts too (the finale's first 2 s), and the
		# finale on to 1 s after its first bottle shatters (marked "shatter:N").
		if view._state == "finale":
			_perf_finale_t += 1.0 / 60.0
			var sh: int = view.finale._shatters.size() if is_instance_valid(view.finale) else 0
			if sh != _perf_shatters:
				view.perf_marks.append("shatter:%d" % sh)
				_perf_shatters = sh
			if sh > 0:
				_perf_shatter_t += 1.0 / 60.0
			playing = _perf_finale_t <= 2.0 or _perf_shatter_t <= 1.0
		marks = " ".join(view.perf_marks)
		view.perf_marks.clear()
	var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	var compiled := 0
	var mons := [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH,
			Performance.PIPELINE_COMPILATIONS_SURFACE, Performance.PIPELINE_COMPILATIONS_DRAW,
			Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]
	for i in mons.size():
		var c := int(Performance.get_monitor(mons[i]))
		if _perf_pipes.size() > i and c > int(_perf_pipes[i]):
			compiled += c - int(_perf_pipes[i])
			marks += " pipe:%s+%d" % [["canvas", "mesh", "surface", "draw", "spec"][i], c - int(_perf_pipes[i])]
		if _perf_pipes.size() <= i:
			_perf_pipes.append(c)
		_perf_pipes[i] = c
	_perf.store_line("%d %.1f %.1f %.1f %d %s %s" % [_frame, ms, proc, gpu, compiled, st, marks])
	if playing and _perf_level_t > 2.0:
		_perf_max = maxf(_perf_max, ms)
		if ms > 33.0 or compiled > 0:
			_perf_worst.append([ms, _frame, compiled, st + " " + marks])
	if _perf_level_t > 2.0 and not playing and not _perf_done and is_instance_valid(view):
		_perf_done = true
		_perf_report()
	if _frame % 120 == 0:
		_perf.flush()


func _perf_report() -> void:
	_perf_worst.sort_custom(func(a, b): return a[0] > b[0])
	print("PERF level max frame %.1f ms after 2 s (and the finale's first 2 s); %d frames over 33 ms or compiling" % [_perf_max, _perf_worst.size()])
	for w in _perf_worst.slice(0, 12):
		print("PERF %.1f ms frame %d pipelines %d %s" % w)
	_perf.store_line("# max %.1f worst: %s" % [_perf_max, str(_perf_worst.slice(0, 12))])
	_perf.flush()


func _exit_tree() -> void:
	if _perf:
		if not _perf_done:
			_perf_report()
		_perf.close()


## safe_top=N: a punch-hole camera drawn over everything in the middle of the fake cut-out, so a
## PC screenshot shows what sits under it.
func _fake_cutout(inset: float) -> void:
	if inset <= 0.0:
		return
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	var hole := Control.new()
	hole.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(hole)
	hole.draw.connect(func():
		var w := hole.get_viewport_rect().size.x
		hole.draw_circle(Vector2(w * 0.5, inset * 0.5), minf(inset * 0.28, 22.0), Color.BLACK))
	layer.add_child(hole)
