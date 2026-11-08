class_name BottleShot
extends Node3D
## End-of-level Bottle Shot. The hero gets 3 knives; drag to aim at the bottle wall,
## release to throw. Each knife flies in slow motion with the camera chasing it; time snaps
## back to full speed at impact and the bottle shatters. Rules live in BottleLogic.

signal done(result: Dictionary)

const SLOW := 0.22
const NORMAL_VIEW := Vector3(0.35, 1.85, 1.5)  # just over the hero's shoulder
const AIM_FOV := 34.0                          # telephoto: the bottle wall fills the screen
const CHASE_FOV := 44.0
const BOTTLE_SCALE := 1.3

var logic: BottleLogic
var world: World
var fx: Fx
var font: Font
var troops := 0
var station_bonus := 0.0
var hero_pos := Vector3.ZERO
var on_throw: Callable        # LevelView plays the hero's throw animation

var _wall_z := -7.5
var _ft := 0.0                # finale clock (game time)
var _scale := 1.0
var _bottles: Array = []      # Node3D per bottle
var _rack: Node3D
var _reticle: MeshInstance3D
var _aim := Vector2(0, 1.8)
var _aiming := false
var _knife: Node3D = null
var _knife_from := Vector3.ZERO
var _knife_to := Vector3.ZERO
var _knife_t0 := 0.0
var _knife_t1 := 0.0
var _knife_hit := -1
var _cam := Transform3D()
var _state := "aim"           # aim | flying | impact | tally | finished
var _wait := 0.0
var _shards: Array = []       # {node, vel, spin}
var _stuck: Array = []
var _ui: CanvasLayer
var _knife_icons: Array = []
var _mult_label: Label


func setup(w: World, f: Fx, fnt: Font, level_id: int, troop_count: int, hero: Vector3, bonus: float) -> BottleShot:
	world = w
	fx = f
	font = fnt
	troops = troop_count
	hero_pos = hero
	station_bonus = bonus
	var cfg: Dictionary = Config.load_json("res://config/finale.json")
	logic = BottleLogic.new(cfg, level_id)
	_wall_z = hero.z + float(cfg["wall_z"])
	return self


func _ready() -> void:
	_build_wall()
	_build_ui()
	_cam = _aim_view()
	world.set_camera_override(_cam)
	_aim_lens()
	Sfx.play("swoosh")


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if _state != "aim":
		return
	var pos := Vector2.ZERO
	var pressed := false
	var released := false
	if event is InputEventScreenTouch:
		pos = (event as InputEventScreenTouch).position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenDrag:
		pos = (event as InputEventScreenDrag).position
		pressed = true
	else:
		return
	if pressed:
		_aiming = true
		_aim = _screen_to_wall(pos)
	elif released and _aiming:
		_aiming = false
		_aim = _screen_to_wall(pos)
		throw_at(_aim)


func _screen_to_wall(p: Vector2) -> Vector2:
	var cam := world.camera
	var from := cam.project_ray_origin(p)
	var dir := cam.project_ray_normal(p)
	if absf(dir.z) < 0.001:
		return _aim
	var t := (_wall_z - from.z) / dir.z
	var hit := from + dir * t
	return Vector2(clampf(hit.x - hero_pos.x, -2.4, 2.4), clampf(hit.y, 0.6, 3.6))


## Throws a knife at a wall point (x relative to the hero, y = height). Also used by autoplay.
func throw_at(aim: Vector2) -> void:
	if _state != "aim" or logic.knives_left <= 0:
		return
	_knife_from = hero_pos + Vector3(0.25, 1.45, -0.4)
	_knife_to = Vector3(hero_pos.x + aim.x, aim.y, _wall_z + 0.12)
	var flight := logic.flight_time(_knife_from.distance_to(_knife_to))
	_knife_t0 = _ft
	_knife_t1 = _ft + flight
	_knife_hit = logic.throw(aim, _knife_t1)
	_knife = Node3D.new()
	var blade := World.model("food/cooking-knife.glb", 0.38)
	blade.rotation.y = PI * 0.5  # the model lies along +x; point it down -z (flight direction)
	_knife.add_child(blade)
	add_child(_knife)
	_knife.position = _knife_from
	_state = "flying"
	_scale = SLOW
	world.set_lens(CHASE_FOV, _knife_from.distance_to(_knife_to) + 1.2)
	_update_icons()
	Sfx.play("knife", 2.0)
	if on_throw.is_valid():
		on_throw.call()


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if _state == "finished":
		return
	var d := delta * _scale
	_ft += d
	_move_bottles()
	_tick_shards(d)
	match _state:
		"aim":
			_reticle.visible = true
			_reticle.position = Vector3(hero_pos.x + _aim.x, _aim.y, _wall_z + 0.3)
			_reticle.rotation.z += delta * 2.0
			_cam = _cam.interpolate_with(_aim_view(), minf(delta * 4.0, 1.0))
		"flying":
			_reticle.visible = false
			var k := clampf((_ft - _knife_t0) / maxf(_knife_t1 - _knife_t0, 0.001), 0.0, 1.0)
			var p := _knife_from.lerp(_knife_to, k) + Vector3(0, sin(k * PI) * 0.25, 0)
			_knife.position = p
			_knife.basis = Basis.looking_at((_knife_to - _knife_from).normalized(), Vector3.UP) * Basis(Vector3.RIGHT, -_ft * 28.0)
			# Chase cam: close behind the knife, looking at where it will land.
			var target := _knife_to
			if _knife_hit >= 0:
				target = _bottle_world(_knife_hit, _knife_t1) + Vector3(0, 0.3, 0)
			var cam_pos := p + Vector3(0.18, 0.22, 0.9)
			_cam = _cam.interpolate_with(Transform3D(Basis.looking_at(target - cam_pos, Vector3.UP), cam_pos), minf(delta * 8.0, 1.0))
			# Snap back to full speed just before the strike.
			if _knife_t1 - _ft < 0.06:
				_scale = 1.0
			if k >= 1.0:
				_impact()
		"impact":
			_wait -= delta
			if _wait <= 0.0:
				if logic.knives_left > 0 and logic.broken_count() + logic.broken_count(true) < logic.count():
					_state = "aim"
					_aim_lens()
				else:
					_state = "tally"
					_wait = 1.0
					Sfx.play("win")
		"tally":
			_wait -= delta
			_cam = _cam.interpolate_with(_aim_view(), minf(delta * 3.0, 1.0))
			if _wait <= 0.0:
				_state = "finished"
				world.set_camera_override(null)
				world.set_lens(-1.0)
				_ui.queue_free()
				done.emit({"broken": logic.broken_count(), "gold": logic.broken_count(true),
					"mult": logic.multiplier(), "coins": logic.coins(troops, station_bonus)})
				return  # the camera is handed back; don't take it again below
	world.set_camera_override(_cam)


func _impact() -> void:
	_state = "impact"
	_scale = 1.0
	_wait = 0.9
	if _knife_hit >= 0:
		var b: Node3D = _bottles[_knife_hit]
		var at := b.global_position + Vector3(0, 0.4, 0)
		_shatter(at, logic.is_gold(_knife_hit), fmod(0.31 + _knife_hit * 0.17, 1.0))
		b.visible = false
		_knife.queue_free()
		world.shake(0.5)
		Sfx.play("glass", 3.0)
		Sfx.play("coin", -2.0, 1.2)
		Game.vibrate(60)
		_mult_label.text = "×%s" % _fmt(logic.multiplier())
		UiKit.pop(_mult_label, 1.8)
	else:
		_stuck.append(_knife)
		# Stuck knife: blade buried in the wall, handle towards the thrower, a little tilt.
		# (the blade runs along the pivot's +Y, so tip it forward a quarter turn)
		_knife.basis = Basis.looking_at((_knife_to - _knife_from).normalized(), Vector3.UP) * Basis(Vector3.FORWARD, randf_range(-0.4, 0.4)) * Basis(Vector3.RIGHT, -PI * 0.5)
		Sfx.play("thunk", 2.0)
		fx.burst(_knife.global_position, Color(0.6, 0.45, 0.3), 8, 3.0, 0.08, 0.4)
	_knife = null


func _shatter(at: Vector3, gold: bool, hue: float) -> void:
	var tint := Color(1.0, 0.85, 0.35) if gold else Color.from_hsv(hue, 0.45, 0.95)
	var shard_mat := StandardMaterial3D.new()
	shard_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shard_mat.albedo_color = Color(tint, 0.55)
	shard_mat.roughness = 0.05
	shard_mat.metallic_specular = 1.0
	shard_mat.rim_enabled = true
	shard_mat.rim = 1.0
	shard_mat.emission_enabled = true
	shard_mat.emission = tint * 0.35
	shard_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var drop_mat := StandardMaterial3D.new()
	drop_mat.albedo_color = Color("e3a51f") if gold else Color.from_hsv(hue, 0.75, 0.6)
	drop_mat.roughness = 0.15
	drop_mat.metallic_specular = 0.9
	for i in 54:
		var shard := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(randf_range(0.03, 0.1), randf_range(0.05, 0.14), 0.008)
		shard.mesh = pm
		shard.material_override = shard_mat
		add_child(shard)
		shard.global_position = at + Vector3(randf_range(-0.08, 0.08), randf_range(-0.3, 0.3), randf_range(-0.06, 0.06))
		var vel := Vector3(randf_range(-3.0, 3.0), randf_range(0.5, 4.0), randf_range(0.5, 3.5))
		_shards.append({"node": shard, "vel": vel, "spin": Vector3(randf(), randf(), randf()) * 20.0, "life": 2.2})
	# The liquid splashes out as droplets.
	for i in 30:
		var drop := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r := randf_range(0.012, 0.035)
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 8
		sm.rings = 4
		drop.mesh = sm
		drop.material_override = drop_mat
		add_child(drop)
		drop.global_position = at + Vector3(randf_range(-0.05, 0.05), randf_range(-0.25, 0.05), 0.05)
		var vel := Vector3(randf_range(-2.0, 2.0), randf_range(1.0, 3.5), randf_range(0.8, 2.5))
		_shards.append({"node": drop, "vel": vel, "spin": Vector3.ZERO, "life": 1.4})
	fx.burst(at, Color(1, 1, 1), 12, 5.0, 0.03, 0.25)   # white glints
	if gold:
		fx.confetti(at, 40)


func _tick_shards(d: float) -> void:
	var i := 0
	while i < _shards.size():
		var s: Dictionary = _shards[i]
		s["life"] = float(s["life"]) - d
		var node: MeshInstance3D = s["node"]
		if float(s["life"]) <= 0.0:
			node.queue_free()
			_shards.remove_at(i)
			continue
		var v: Vector3 = s["vel"]
		v.y -= 9.8 * d
		if node.position.y < 0.02 and v.y < 0.0:
			v = Vector3(v.x * 0.4, -v.y * 0.25, v.z * 0.4)
		s["vel"] = v
		node.position += v * d
		node.rotation += (s["spin"] as Vector3) * d
		i += 1


# ---------------------------------------------------------------- build

## Telephoto lens framing this level's bottles (plus their motion) edge to edge.
func _aim_lens() -> void:
	var extent := 0.0
	for b in logic.layout["bottles"]:
		extent = maxf(extent, absf(float(b["x"])))
	extent += float(logic.layout.get("amp", 0.0)) + 0.55
	var d := _aim_view().origin.distance_to(Vector3(hero_pos.x, 1.8, _wall_z))
	var fov := clampf(rad_to_deg(2.0 * atan(extent / d)), 22.0, AIM_FOV)
	world.set_lens(fov, d + 0.4)


func _aim_view() -> Transform3D:
	var eye := hero_pos + NORMAL_VIEW
	var look := Vector3(hero_pos.x, 1.75, _wall_z)
	return Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)


func _bottle_world(i: int, t: float) -> Vector3:
	var p := logic.position(i, t)
	return Vector3(hero_pos.x + p.x, p.y - 0.4, _wall_z + 0.25)


func _move_bottles() -> void:
	var motion := String(logic.layout.get("motion", "static"))
	for i in _bottles.size():
		var b: Node3D = _bottles[i]
		b.position = _bottle_world(i, _ft)
		if motion == "swing":
			var p := logic.position(i, _ft)
			var base: Dictionary = logic.layout["bottles"][i]
			b.rotation.z = (p.x - float(base["x"])) * -0.5
	if motion == "slide" or motion == "drive":
		_rack.position.x = hero_pos.x + logic.position(0, _ft).x - float(logic.layout["bottles"][0]["x"])


func _build_wall() -> void:
	var motion := String(logic.layout.get("motion", "static"))
	# Gallery: a warm plank wall with a frame, lit by two spotlights so every bottle throws
	# a shadow on it, and a string of glowing bulbs across the top.
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(6.4, 4.4, 0.25)
	wall.mesh = wm
	var pm := ShaderMaterial.new()
	pm.shader = load("res://src/finale/planks.gdshader")
	wall.material_override = pm
	wall.position = Vector3(hero_pos.x, 2.0, _wall_z - 0.1)
	add_child(wall)
	for side in [-1, 1]:
		var post := World._box(Vector3(0.3, 4.6, 0.4), Color("3b2414"))
		post.position = Vector3(hero_pos.x + side * 3.25, 2.1, _wall_z)
		add_child(post)
	var beam := World._box(Vector3(6.9, 0.32, 0.45), Color("3b2414"))
	beam.position = Vector3(hero_pos.x, 4.3, _wall_z)
	add_child(beam)
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color("ffd98a")
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color("ffc65a")
	bulb_mat.emission_energy_multiplier = 4.0
	for i in 13:
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		bulb.mesh = sm
		bulb.material_override = bulb_mat
		var x := -3.0 + i * 0.5
		bulb.position = Vector3(hero_pos.x + x, 4.05 - 0.12 * sin(fposmod(x, 1.0) * PI), _wall_z + 0.3)
		add_child(bulb)
	for side in [-1, 1]:
		var spot := SpotLight3D.new()
		spot.light_color = Color("ffe2b0")
		spot.light_energy = 3.2
		spot.spot_range = 14.0
		spot.spot_angle = 32.0
		spot.shadow_enabled = true
		spot.position = Vector3(hero_pos.x + side * 2.4, 4.6, _wall_z + 4.0)
		add_child(spot)
		spot.look_at(Vector3(hero_pos.x + side * 0.4, 1.8, _wall_z), Vector3.UP)
	_rack = Node3D.new()
	add_child(_rack)
	_rack.position = Vector3(hero_pos.x, 0, 0)
	var heights := {}
	for b in logic.layout["bottles"]:
		heights[snappedf(float(b["y"]) - 0.3, 0.01)] = true  # shelf top sits under the bottle base
	if motion == "swing":
		var bar := World._box(Vector3(4.2, 0.12, 0.12), Color("2b2b2b"))
		bar.position = Vector3(hero_pos.x, 3.2, _wall_z + 0.25)
		add_child(bar)
	else:
		for h in heights:
			var shelf := World._box(Vector3(4.0 if motion == "static" else 2.8, 0.08, 0.5), Color("8a5a32"))
			shelf.position = Vector3(0, float(h) - 0.04, _wall_z + 0.22)
			_rack.add_child(shelf)
	for i in logic.count():
		var bottle := BottleMesh.make(logic.is_gold(i), fmod(0.31 + i * 0.17, 1.0))
		bottle.scale = Vector3.ONE * BOTTLE_SCALE
		add_child(bottle)
		_bottles.append(bottle)
		if motion == "swing":
			var string := World._box(Vector3(0.015, 1.0, 0.015), Color("dddddd"))
			string.position = Vector3(0, 1.1, 0)
			bottle.add_child(string)
	_move_bottles()
	_reticle = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.13
	tm.outer_radius = 0.17
	_reticle.mesh = tm
	_reticle.rotation.x = PI * 0.5
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color("ff3b3b")
	rm.no_depth_test = true
	_reticle.material_override = rm
	add_child(_reticle)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	row.offset_top = -170
	row.offset_bottom = -70
	row.offset_left = -180
	row.offset_right = 180
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(row)
	for i in logic.knives_left:
		var icon := UiKit.icon("knife", 84)
		row.add_child(icon)
		_knife_icons.append(icon)
	_mult_label = UiKit.label("×1", 96, UiKit.GOLD, 18)
	_mult_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_mult_label.offset_top = 150
	_mult_label.offset_left = -200
	_mult_label.offset_right = 200
	_mult_label.offset_bottom = 270
	_ui.add_child(_mult_label)


func _update_icons() -> void:
	for i in _knife_icons.size():
		(_knife_icons[i] as Control).modulate.a = 1.0 if i < logic.knives_left else 0.2


static func _fmt(m: float) -> String:
	return str(int(m)) if is_equal_approx(m, round(m)) else "%.1f" % m
