extends Node
## Bottle Shot on its own, for tuning the cameras, glass and shatter without playing a level.
## Run windowed (a covered window stops rendering):
##   godot --path . res://tools/preview_finale.tscn --always-on-top --position 0,0 --fixed-fps 60
##     --resolution 540x960 -- level=2 theme=5 miss=2 shots=60,120 out=_local/shots/fin frames=400
## level = finale layout, theme = district look (1-5), miss = which throw (1-based) misses on
## purpose, shots = frames to save as <out>_<frame>.png (or every=N for every Nth frame),
## frames = quit after this many frames. State and camera changes are printed with frames.

var world: World
var fx: Fx
var shot: BottleShot
var _args := {}
var _frame := 0
var _throws := 0
var _aim_frames := 0
var _hero: Crowd
var _last_state := ""
var _last_cam := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	world = World.new()
	add_child(world)
	if world.has_method("set_theme"):
		world.set_theme(int(_args.get("theme", "1")))
	fx = Fx.new()
	fx.font = UiKit.FONT
	add_child(fx)
	var hero := Vector3(0, 0, -0.5)
	_hero = Crowd.new().setup("hero", 2)
	add_child(_hero)
	shot = BottleShot.new().setup(world, fx, UiKit.FONT, int(_args.get("level", "1")), 40, hero, 0.0)
	shot.done.connect(func(r): print("FINALE ", r))
	add_child(shot)


func _process(_delta: float) -> void:
	_frame += 1
	_hero.begin()
	_hero.push(Transform3D(Basis(), Vector3(0, 0, -0.5)), "idle", _frame / 60.0)
	_hero.finish()
	if is_instance_valid(shot) and (shot._state != _last_state or shot._cam_mode != _last_cam):
		_last_state = shot._state
		_last_cam = shot._cam_mode
		print("frame %d: %s / camera %s" % [_frame, _last_state, _last_cam])
	if is_instance_valid(shot) and shot._state == "aim":
		_aim_frames += 1
		if _aim_frames >= int(_args.get("wait", "40")):
			_aim_frames = 0
			_throws += 1
			var lg := shot.logic
			var aim := Vector2(-2.2, 3.3)   # a deliberate miss: empty top corner of the wall
			if str(_throws) != String(_args.get("miss", "")):
				for i in lg.count():
					if not lg.broken[i]:
						var from := shot.hero_pos + Vector3(0.25, 1.45, -0.4)
						var p := lg.position(i, shot._ft)
						var to := Vector3(shot.hero_pos.x + p.x, p.y, shot._wall_z + 0.12)
						aim = lg.position(i, shot._ft + lg.flight_time(from.distance_to(to)))
						break
			if str(_throws) == String(_args.get("miss", "")) and shot._mode == null:
				shot._throw_knife(aim)   # throw_at always hits the next target; a miss aims by hand
			else:
				shot.throw_at(aim)
	var every := int(_args.get("every", "0"))
	if (_args.has("shots") and String(_args["shots"]).split(",").has(str(_frame))) or (every > 0 and _frame % every == 0):
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [_args.get("out", "_local/shots/fin"), _frame])
	if _frame == int(_args.get("frames", "900")):
		get_tree().quit()
