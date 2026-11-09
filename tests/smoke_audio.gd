extends SceneTree
## Smoke test of the settings audio toggles (v1.1 item 4) on the real Sfx autoload with a fresh
## save (never written). Needs a running tree, so it is not part of run_tests.gd:
##   godot --headless --path . --script res://tests/smoke_audio.gd
## Prints "SMOKE AUDIO: N checks, 0 failed" and exits 1 on any failure.
## Bug it guards: music off used to leave the track playing (two fades killed each other).

var _f := 0
var _checks := 0
var _fails: Array[String] = []


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)


func _process(_d: float) -> bool:
	_f += 1
	var g: Node = root.get_node("Game")
	var s: Node = root.get_node("Sfx")
	match _f:
		2:
			g.save_path = ""
			g.boot({})
			s.play_music("menu")
		30:
			_check(s.music_playing(), "music plays when on")
			g.toggle("music")
			s.music_changed()
			_check(not s.music_playing(), "music off stops the track at once")
		60:
			_check(not s.music_playing(), "music stays off")
			s.play_music("level")
			_check(not s.music_playing(), "a new mode stays silent while music is off")
			g.toggle("music")
			s.music_changed()
			_check(s.music_playing(), "music on starts it again")
			_check(s.music_mode() == "level", "the mode is kept")
			g.toggle("sound")
			s.sound_changed()
			s.play("tap")
			var any := false
			for p in s._players:
				any = any or p.playing
			_check(not any, "sound off: no effect plays")
			_check(bool(g.save["music"]) and not bool(g.save["sound"]), "flags in the save")
		90:
			print("SMOKE AUDIO: %d checks, %d failed" % [_checks, _fails.size()])
			for m in _fails:
				print("  FAIL " + m)
			quit(1 if not _fails.is_empty() else 0)
	return false
