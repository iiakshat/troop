extends Node
## App flow: lobby (squad jogging behind the menu) -> level -> Bottle Shot -> result -> ...
##
## Debug args (after `--`, key=value): level=N  frames=N  screenshot=path  autoplay=1
##   lanes=2,1,1 (autoplay lane per gate row)  strike=1 (autoplay the bottle throws)
##   reset=1 (fresh save)  coins=N  lobby=1  panel=station|style|settings  report=1

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


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _args.has("reset"):
		Game.reset_progress()
	if _args.has("coins"):
		Game.save["coins"] = int(_args["coins"])
		Game.save["unlocked"] = Config.LEVEL_COUNT
	world = World.new()
	add_child(world)
	fx = Fx.new()
	fx.font = UiKit.FONT
	add_child(fx)
	ui = CanvasLayer.new()
	add_child(ui)
	result = ResultPanel.new()
	result.next_pressed.connect(func(): _start_level(mini(current_level + 1, Config.LEVEL_COUNT)))
	result.retry_pressed.connect(func(): _start_level(current_level))
	result.lobby_pressed.connect(_show_lobby)
	result.station_pressed.connect(_open_station_from_result)
	if _args.has("level"):
		_start_level(int(_args["level"]))
	elif int(Game.save["coins"]) == 0 and int(Game.save["unlocked"]) == 1 and not _args.has("lobby"):
		_start_level(1)  # brand-new player: straight into the action, no menu
	else:
		_show_lobby()
	ui.add_child(result)


func _show_lobby() -> void:
	_clear_level()
	result.visible = false
	view = LevelView.new().setup(Config.level(1), Game.upgrades(), world, fx, UiKit.FONT, true)
	add_child(view)
	lobby = Lobby.new()
	lobby.play.connect(_start_level)
	ui.add_child(lobby)
	ui.move_child(lobby, 0)
	Sfx.play_music(false)
	match String(_args.get("panel", "")):
		"station":
			lobby._open(StationPanel.new())
		"style":
			lobby._open(StylePanel.new())
		"settings":
			lobby._open(SettingsPanel.new())


## Station over the result screen; closing it returns to the result (badges refresh).
func _open_station_from_result() -> void:
	var p := StationPanel.new()
	ui.add_child(p)
	p.tree_exited.connect(func():
		for b in result.find_children("*", "Button", true, false):
			if (b as Button).has_meta("badge"):
				UiKit.set_alert(b, StationPanel.anything_affordable()))


func _start_level(n: int) -> void:
	_clear_level()
	result.visible = false
	current_level = n
	var level := Config.level(n)
	view = LevelView.new().setup(level, Game.upgrades(), world, fx, UiKit.FONT)
	add_child(view)
	hud = Hud.new()
	ui.add_child(hud)
	ui.move_child(hud, 0)
	hud.set_level(n, String(level.get("name", "")))
	view.hint.connect(hud.show_hint)
	view.banner.connect(hud.show_banner)
	view.charges_changed.connect(hud.set_charges)
	view.squad_changed.connect(hud.set_troops)
	hud.set_capacity(view.sim.squad.cap)
	hud.set_troops(view.sim.squad.total())
	view.tutorial.connect(hud.set_tutorial)
	view.strike_ready.connect(hud.enter_finale)
	view.finished.connect(_on_finished)
	hud.power_pressed.connect(func(id): view.use_power(id))
	hud.pause_pressed.connect(_toggle_pause)
	hud.set_charges(view.sim.charges)
	Sfx.play_music(true)
	if _args.has("autoplay"):
		var lanes: Array = []
		for s in String(_args.get("lanes", "2,1,1,0,0")).split(","):
			lanes.append(int(s))
		_pilot = Autopilot.new(lanes, true)
		view.input_enabled = false
		hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.power_pressed.disconnect(hud.power_pressed.get_connections()[0]["callable"])


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


func _on_finished(r: Dictionary) -> void:
	if _args.has("report"):
		print("RESULT ", r, " troops_now=", view.sim.squad.total())
	if r["won"]:
		Game.add_coins(int(r["coins"]))
		Game.complete_level(current_level)
		result.show_win(current_level, r, current_level < Config.LEVEL_COUNT)
	else:
		result.show_loss(current_level, String(r["cause"]))
	if hud:
		hud.visible = false


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
	restart.pressed.connect(func(): _start_level(current_level))
	row.add_child(restart)
	var quit := UiKit.icon_button("home", "blue", 130)
	quit.pressed.connect(_show_lobby)
	row.add_child(quit)
	ui.add_child(pause_panel)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if hud != null:
			_toggle_pause()
		elif lobby == null:
			_show_lobby()
		else:
			get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED and hud != null and not is_instance_valid(pause_panel):
		_toggle_pause()


func _process(_delta: float) -> void:
	if _pilot and view and view.sim.state == "run":
		_pilot.drive(view.sim)
	_frame += 1
	if _args.has("strike") and view and view.finale and view.finale._state == "aim" and _frame % 40 == 0:
		# Autoplay the finale: aim where the next unbroken bottle will be when the knife lands.
		var lg: BottleLogic = view.finale.logic
		for i in lg.count():
			if not lg.broken[i]:
				view.finale.throw_at(lg.position(i, view.finale._ft + 0.55))
				break
	if _args.has("shots") and String(_args["shots"]).split(",").has(str(_frame)):
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [_args.get("out", "shot"), _frame])
	if _args.has("frames") and _frame == int(_args["frames"]):
		if _args.has("screenshot"):
			var img := get_viewport().get_texture().get_image()
			img.save_png(String(_args["screenshot"]))
		get_tree().quit()

