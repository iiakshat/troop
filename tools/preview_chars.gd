extends Node3D
## Debug lineup of every baked role. Run windowed:
##   godot --path . res://tools/preview_chars.tscn -- shot=path.png clip=run
## Facing -z = away from camera (squad view); enemies are turned to face the camera.

var _crowds: Array = []
var _t := 0.0
var _frame := 0
var _clip := "run"
var _shot := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("clip="):
			_clip = a.substr(5)
		if a.begins_with("shot="):
			_shot = a.substr(5)
	var roles: Array = Config.load_json("res://config/characters.json")["roles"].keys()
	for i in roles.size():
		var c := Crowd.new().setup(String(roles[i]), 2)
		add_child(c)
		_crowds.append({"c": c, "x": (i % 6) * 1.6 - 4.0, "z": -(i / 6) * 2.6, "name": roles[i]})
		var l := Label3D.new()
		l.text = String(roles[i])
		l.pixel_size = 0.005
		l.position = Vector3((i % 6) * 1.6 - 4.0, 2.3, -(i / 6) * 2.6)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 2.6, 6.5)
	cam.look_at(Vector3(0, 0.9, -1.3))
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.7
	we.environment = env
	add_child(we)


func _process(delta: float) -> void:
	_t += delta
	_frame += 1
	for e in _crowds:
		var c: Crowd = e["c"]
		c.begin()
		var basis := Basis(Vector3.UP, PI)  # face the camera
		c.push(Transform3D(basis, Vector3(e["x"], 0, e["z"])), _clip, _t)
		c.finish()
	if _shot != "" and _frame == 45:
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()
