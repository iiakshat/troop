extends SceneTree
## Opens one retention panel on a plain background and screenshots it (never writes the save).
##   $G --path . --script res://tools/preview_ui.gd --always-on-top --position 0,0 \
##      --fixed-fps 60 --resolution 540x960 -- panel=daily out=_local/shots/daily.png
## panel = daily | missions | spin | booster | revive | codex | chest | welcome | result_win |
##         result_loss | toast | ad (the blank placeholder ad)
## Extra args: frames=N (when to shoot, default 90), shots=a,b,c (several frames -> out_a.png..),
## tab=enemies (codex), spin=1 (press the spin button), claim=1 (press claim / collect),
## state=fresh (a new player's save instead of the demo state), ad=1 (press the first ad button:
## the placeholder ad shows its countdown, then the reward lands).

var _args := {}
var _frame := 0
var _shots: Array[int] = []
var _out := "_local/shots/ui.png"
var _panel: Control
var _queue: Array = []
var _holder: Control


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := String(a).trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_out = String(_args.get("out", _out))
	_queue = Array(String(_args.get("panel", "daily")).split(","))
	for s in String(_args.get("shots", _args.get("frames", "90"))).split(","):
		_shots.append(int(s))
	process_frame.connect(_on_frame)
	_setup.call_deferred()


func _setup() -> void:
	var game: Node = root.get_node("Game")
	game.save_path = ""
	if String(_args.get("state", "demo")) != "fresh":
		_demo_state(game)
	var bg := ColorRect.new()
	bg.color = Color("1c4fb8")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ui := CanvasLayer.new()
	root.add_child(ui)
	ui.add_child(bg)
	_next_panel(ui)


func _next_panel(ui: Node) -> void:
	if is_instance_valid(_holder):
		_holder.queue_free()
	_holder = Control.new()
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(_holder)
	var name := String(_queue.pop_front())
	if _args.has("dir"):
		_out = String(_args["dir"]).path_join(name + ".png")
	_frame = 0
	_panel = _make(name, _holder)
	if _panel and _panel.get_parent() == null:
		_holder.add_child(_panel)


## A mid-game player: some coins, stars, a streak, missions half done.
func _demo_state(g: Node) -> void:
	var s: Dictionary = g.save
	s["coins"] = 2350
	s["unlocked"] = 14
	for lv in range(1, 14):
		s["stars"][str(lv)] = 3 if lv % 3 else 2
	var today: String = g.today()
	var yesterday := Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(today + "T12:00:00") - 86400)
	s["daily"] = {"day": 3, "last_claim_date": yesterday, "streak": 3}
	s["boosters"] = {"headstart": 2, "shield": 0, "bomb": 1}
	g.refresh_day()
	var l: Array = s["missions"]["list"]
	if l.size() >= 3:
		l[0]["progress"] = l[0]["goal"]
		l[0]["done"] = true
		l[1]["progress"] = int(l[1]["goal"]) / 2
		l[2]["progress"] = l[2]["goal"]
		l[2]["done"] = true
		l[2]["claimed"] = true
	s["rank_seen"] = ["hero", "constable", "sergeant", "inspector", "swat"]


## Panel scripts load at run time: autoload names (Game) only resolve once the tree is up.
func _ui(file: String) -> GDScript:
	return load("res://src/ui/%s.gd" % file)


func _make(name: String, holder: Control) -> Control:
	match name:
		"daily":
			return _ui("daily_panel").new()
		"missions":
			return _ui("missions_panel").new()
		"spin":
			return _ui("spin_panel").new()
		"booster":
			return _ui("booster_panel").new(int(_args.get("level", "10")))
		"revive":
			return _ui("revive_panel").new(float(_args.get("progress", "0.82")), int(_args.get("peak", "64")))
		"codex":
			var c: Control = _ui("codex_panel").new()
			c.start_tab = String(_args.get("tab", "ranks"))
			return c
		"chest":
			var g: Node = root.get_node("Game")
			g.save["stars"]["14"] = 3
			g.save["stars"]["15"] = 3
			return _ui("star_chest_panel").new()
		"welcome":
			return _ui("welcome_back_panel").new(int(_args.get("coins", "840")))
		"result_win", "result_loss":
			var r: Control = _ui("result_panel").new()
			holder.add_child(r)
			if name == "result_win":
				r.show_win(int(_args.get("level", "7")), {"coins": 360, "stars": int(_args.get("stars", "2")), "broken": 3, "gold": 1, "mult": 3.0, "star_chest_ready": false}, true)
			else:
				r.show_loss(int(_args.get("level", "7")), String(_args.get("cause", "brute")), float(_args.get("progress", "0.82")), 64)
			return r
		"toast":
			_ui("rank_toast").show(holder, String(_args.get("unit", "inspector")))
			return null
		"ad":
			root.get_node("Ads").skip_ads = false
			root.get_node("Ads").show_rewarded("x2_coins", func(ok): print("AD ", ok))
			return null
	push_error("unknown panel " + name)
	return null


func _on_frame() -> void:
	_frame += 1
	if _frame == 20 and _panel:
		if _args.has("spin"):
			var b: Variant = _panel.get("_spin_btn")
			if b is Button:
				(b as Button).pressed.emit()
		if _args.has("ad"):
			# Press the first rewarded-ad button (the blank placeholder ad opens; ads are not
			# skipped here, so the real countdown runs).
			root.get_node("Ads").skip_ads = false
			for btn in _panel.find_children("*", "Button", true, false):
				if btn.has_meta("row") and btn.visible:
					(btn as Button).pressed.emit()
					break
		if _args.has("claim"):
			for m in ["_on_claim", "_on_collect"]:
				if _panel.has_method(m):
					_panel.call(m)
					break
	if _shots.has(_frame):
		var path := _out
		if _shots.size() > 1:
			path = _out.get_basename() + "_%d.png" % _frame
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + path.get_base_dir()))
		var img := root.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://" + path))
		print("saved ", path)
	if _frame >= _shots.max():
		if _queue.is_empty():
			quit()
		else:
			_next_panel(_holder.get_parent())
