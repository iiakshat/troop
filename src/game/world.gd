class_name World
extends Node3D
## The neutral city street: road, sidewalks, buildings, props, light, sky and camera.
## Everything scrolls towards the camera with scroll(); the squad never moves forward.

const ROAD_HALF := 4.9
const FAR_Z := -150.0
const NEAR_Z := 24.0

const BUILDING_COLORS := ["e8d9c4", "c9d6df", "d9c2b0", "b8c7a9", "e3c9c9", "c4c0d9", "d6d0b8", "aebfcf"]

var camera: Camera3D
var _road_mat: ShaderMaterial
var _scroll := 0.0
var _movers: Array[Node3D] = []   # buildings and props that recycle
var _shake := 0.0
var _cam_base := Transform3D()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	_environment()
	_camera()
	_ground()
	_buildings()
	_props()


func scroll(dist: float) -> void:
	_scroll += dist
	_road_mat.set_shader_parameter("offset", _scroll)
	for m in _movers:
		m.position.z += dist
		if m.position.z > NEAR_Z:
			m.position.z -= (NEAR_Z - FAR_Z)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	if _shake > 0.001:
		_shake = move_toward(_shake, 0.0, delta * 2.5)
		var o := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0) * _shake * 0.35
		camera.transform = _cam_base.translated(o)
	else:
		camera.transform = _cam_base


# ---------------------------------------------------------------- build

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("4f8fd6")
	sm.sky_horizon_color = Color("cfe3f2")
	sm.ground_horizon_color = Color("cfe3f2")
	sm.ground_bottom_color = Color("8aa0b0")
	sm.sun_angle_max = 30.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c8d4e6")
	env.ambient_light_energy = 0.75
	env.fog_enabled = true
	env.fog_light_color = Color("cfe3f2")
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.05
	sun.light_color = Color("fff6e8")
	sun.shadow_enabled = false
	add_child(sun)


func _camera() -> void:
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 58.0
	camera.near = 0.5
	camera.far = 220.0
	camera.position = Vector3(0, 8.8, 8.6)
	add_child(camera)
	camera.look_at(Vector3(0, 0, -11.0), Vector3.UP)
	_cam_base = camera.transform
	camera.current = true


func _ground() -> void:
	# Road with scrolling lane markings.
	var road := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(ROAD_HALF * 2.0, NEAR_Z - FAR_Z)
	road.mesh = pm
	road.position = Vector3(0, 0, (NEAR_Z + FAR_Z) * 0.5)
	_road_mat = ShaderMaterial.new()
	_road_mat.shader = load("res://src/game/road.gdshader")
	_road_mat.set_shader_parameter("half_width", ROAD_HALF)
	road.material_override = _road_mat
	add_child(road)

	for side in [-1, 1]:
		var curb := _box(Vector3(0.3, 0.25, NEAR_Z - FAR_Z), Color("9a9a9a"))
		curb.position = Vector3(side * (ROAD_HALF + 0.15), 0.12, (NEAR_Z + FAR_Z) * 0.5)
		add_child(curb)
		var walk := _box(Vector3(3.2, 0.2, NEAR_Z - FAR_Z), Color("c9c4bb"))
		walk.position = Vector3(side * (ROAD_HALF + 1.9), 0.1, (NEAR_Z + FAR_Z) * 0.5)
		add_child(walk)
		var lot := _box(Vector3(30, 0.1, NEAR_Z - FAR_Z), Color("7d8a6e"))
		lot.position = Vector3(side * (ROAD_HALF + 3.5 + 15), 0.0, (NEAR_Z + FAR_Z) * 0.5)
		add_child(lot)


func _buildings() -> void:
	var bmat := ShaderMaterial.new()
	bmat.shader = load("res://src/game/building.gdshader")
	for side in [-1, 1]:
		var z := NEAR_Z
		while z > FAR_Z:
			var w := _rng.randf_range(7.0, 12.0)
			var h := _rng.randf_range(7.0, 24.0)
			var d := _rng.randf_range(7.0, 10.0)
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(d, h, w - 0.8)
			b.mesh = bm
			var mat := bmat.duplicate() as ShaderMaterial
			mat.set_shader_parameter("base", Color(BUILDING_COLORS[_rng.randi() % BUILDING_COLORS.size()]))
			mat.set_shader_parameter("size", bm.size)
			b.material_override = mat
			b.position = Vector3(side * (ROAD_HALF + 3.6 + d * 0.5), h * 0.5, z - w * 0.5)
			add_child(b)
			_movers.append(b)
			# Roof trim
			var trim := _box(Vector3(d + 0.3, 0.4, w - 0.5), Color(BUILDING_COLORS[_rng.randi() % BUILDING_COLORS.size()]).darkened(0.25))
			trim.position = Vector3(0, h * 0.5 + 0.2, 0)
			b.add_child(trim)
			z -= w


func _props() -> void:
	for side in [-1, 1]:
		var z := NEAR_Z - 4.0
		var i := 0
		while z > FAR_Z:
			var prop: Node3D
			if i % 2 == 0:
				prop = _lamp(side)
			else:
				prop = _tree()
			prop.position = Vector3(side * (ROAD_HALF + 2.6), 0.2, z)
			add_child(prop)
			_movers.append(prop)
			z -= 9.0
			i += 1


func _lamp(side: int) -> Node3D:
	var n := Node3D.new()
	var pole := _box(Vector3(0.16, 4.6, 0.16), Color("4a4f57"))
	pole.position = Vector3(0, 2.3, 0)
	n.add_child(pole)
	var arm := _box(Vector3(1.3, 0.12, 0.14), Color("4a4f57"))
	arm.position = Vector3(-side * 0.6, 4.55, 0)
	n.add_child(arm)
	var head := _box(Vector3(0.5, 0.18, 0.3), Color("fff3c4"))
	head.position = Vector3(-side * 1.2, 4.45, 0)
	n.add_child(head)
	return n


func _tree() -> Node3D:
	var n := Node3D.new()
	var trunk := _box(Vector3(0.28, 1.6, 0.28), Color("6b4a2b"))
	trunk.position = Vector3(0, 0.8, 0)
	n.add_child(trunk)
	var g := Color("4f9a4a").lerp(Color("2f7a3c"), _rng.randf())
	var c1 := _box(Vector3(1.6, 1.4, 1.6), g)
	c1.position = Vector3(0, 2.2, 0)
	n.add_child(c1)
	var c2 := _box(Vector3(1.0, 0.9, 1.0), g.lightened(0.12))
	c2.position = Vector3(0.1, 3.1, 0.1)
	n.add_child(c2)
	return n


static func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mi.material_override = mat
	return mi
