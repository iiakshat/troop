extends Node
## The street on its own in each district look (World.set_theme), with a small squad and a
## gang for scale, scrolling as in a level. Run windowed (a covered window stops rendering):
##   godot --path . res://tools/preview_world.tscn --always-on-top --position 0,0 --fixed-fps 60
##     --resolution 540x960 -- themes=1,2,3,4,5 hold=40 out=_local/shots/world
## Each theme in `themes` is shown for `hold` frames and saved as <out>_d<theme>.png; then it
## quits. Switching themes on one World also checks that set_theme can go back and forth.

var world: World
var _args := {}
var _frame := 0
var _themes: PackedStringArray
var _i := 0
var _crowds := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_themes = String(_args.get("themes", "1,2,3,4,5")).split(",")
	world = World.new()
	world.set_theme(int(_themes[0]))   # before entering the tree: applied in _ready
	add_child(world)
	for k in ["hero", "constable", "thug"]:
		var c := Crowd.new().setup(k, 24)
		add_child(c)
		_crowds[k] = c


func _process(delta: float) -> void:
	_frame += 1
	world.scroll(8.0 * delta)
	var t := _frame / 60.0
	_draw("hero", [Vector3(0, 0, 1.2)], "run", t)
	var squad: Array = []
	for i in 14:
		squad.append(Vector3((i % 5 - 2) * 0.55, 0, 1.9 + (i / 5) * 0.55))
	_draw("constable", squad, "run", t)
	var gang: Array = []
	for i in 12:
		gang.append(Vector3(2.8 + (i % 4 - 1.5) * 0.6, 0, -16.0 - (i / 4) * 0.7))
	_draw("thug", gang, "run", t, true)
	var hold := int(_args.get("hold", "40"))
	if _frame % hold == 0:
		var out := String(_args.get("out", "_local/shots/world"))
		get_viewport().get_texture().get_image().save_png("%s_d%s.png" % [out, _themes[_i]])
		_i += 1
		if _i >= _themes.size():
			get_tree().quit()
			return
		world.set_theme(int(_themes[_i]))


func _draw(kind: String, at: Array, clip: String, t: float, facing_squad := false) -> void:
	var c: Crowd = _crowds[kind]
	c.begin()
	var b := Basis(Vector3.UP, PI) if facing_squad else Basis()
	for p in at:
		c.push(Transform3D(b, p), clip, t + p.x * 0.3)
	c.finish()
