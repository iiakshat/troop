class_name World
extends Node3D
## The neutral city street: road, sidewalks, buildings, props, light, sky and camera.
## Everything scrolls towards the camera with scroll(); the squad never moves forward.

const ROAD_HALF := 4.9
const FAR_Z := -150.0
const NEAR_Z := 24.0

var camera: Camera3D
var _road_mat: ShaderMaterial
var _scroll_mats: Array[ShaderMaterial] = []
var _scroll := 0.0
var _movers: Array[Node3D] = []   # buildings and props that recycle
var _shake := 0.0
var _cam_base := Transform3D()
var _cam_override: Variant = null
var _base_fov := 56.0
var _lens_attr: CameraAttributesPractical
var _rng := RandomNumberGenerator.new()
const BASE_NEAR := 0.5


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
	for m in _scroll_mats:
		m.set_shader_parameter("offset", _scroll)
	for m in _movers:
		m.position.z += dist
		if m.position.z > NEAR_Z:
			m.position.z -= (NEAR_Z - FAR_Z)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Lens for close-ups: field of view (degrees, < 0 = default), a focus distance beyond which
## things blur (< 0 = no blur), the near clip plane (< 0 = default) and the blur strength.
## Cheap to call every frame (the camera attributes are reused).
func set_lens(fov: float, focus := -1.0, near := -1.0, blur := 0.12) -> void:
	camera.fov = fov if fov > 0.0 else _base_fov
	camera.near = near if near > 0.0 else BASE_NEAR
	if focus > 0.0:
		if _lens_attr == null:
			_lens_attr = CameraAttributesPractical.new()
			_lens_attr.dof_blur_far_enabled = true
			_lens_attr.dof_blur_far_transition = 1.5
		_lens_attr.dof_blur_far_distance = focus
		_lens_attr.dof_blur_amount = blur
		_lens_attr.exposure_multiplier = 1.0
		camera.attributes = _lens_attr
	else:
		camera.attributes = null


## The finale takes the camera: pass a transform each frame, or null to give it back.
## Applied at once, so a cut and a lens change land on the same frame.
func set_camera_override(xf: Variant) -> void:
	_cam_override = xf
	camera.transform = xf if xf != null else _cam_base


func _process(delta: float) -> void:
	var base: Transform3D = _cam_override if _cam_override != null else _cam_base
	if _shake > 0.001:
		_shake = move_toward(_shake, 0.0, delta * 2.5)
		var o := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0) * _shake * 0.35
		camera.transform = base.translated(o)
	else:
		camera.transform = base


# ---------------------------------------------------------------- build

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("2f7fe0")
	sm.sky_horizon_color = Color("bfe4ff")
	sm.ground_horizon_color = Color("bfe4ff")
	sm.ground_bottom_color = Color("6f8aa0")
	sm.sun_angle_max = 20.0
	sm.sky_energy_multiplier = 1.1
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9bcc9")
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color("a9cdee")
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Warm late-morning sun from the front right, so faces and the squad catch light and
	# shadows fall back towards the camera.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 148, 0)
	sun.light_energy = 1.35
	sun.light_color = Color("fff1d9")
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_bias = 0.04
	add_child(sun)
	# Cool fill from the other side keeps shadowed sides from going flat.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, -40, 0)
	fill.light_energy = 0.35
	fill.light_color = Color("d6e2ff")
	add_child(fill)


func _camera() -> void:
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 56.0
	camera.near = 0.5
	camera.far = 220.0
	camera.position = Vector3(0, 7.0, 7.4)
	add_child(camera)
	camera.look_at(Vector3(0, 0.5, -9.0), Vector3.UP)
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
	_road_mat.set_shader_parameter("asphalt", load(TEX + "asphalt.png"))
	road.material_override = _road_mat
	add_child(road)

	var walk_mat := _scroll_mat("sidewalk.png", 3.2)
	for side in [-1, 1]:
		var curb := _box(Vector3(0.35, 0.25, NEAR_Z - FAR_Z), Color("b9b4ab"))
		curb.position = Vector3(side * (ROAD_HALF + 0.17), 0.12, (NEAR_Z + FAR_Z) * 0.5)
		add_child(curb)
		var walk := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(3.6, 0.2, NEAR_Z - FAR_Z)
		walk.mesh = wm
		walk.material_override = walk_mat
		walk.position = Vector3(side * (ROAD_HALF + 2.1), 0.1, (NEAR_Z + FAR_Z) * 0.5)
		add_child(walk)


func _scroll_mat(tex: String, tile: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://src/game/ground_scroll.gdshader")
	m.set_shader_parameter("tex", load(TEX + tex))
	m.set_shader_parameter("tile_m", tile)
	_scroll_mats.append(m)
	return m


const ENV := "res://assets/env/"
static var _scenes: Dictionary = {}


## Instances a Kenney/KayKit model (cached PackedScene), scaled uniformly.
static func model(path: String, scale := 1.0) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load(ENV + path)
	var n: Node3D = (_scenes[path] as PackedScene).instantiate()
	n.scale = Vector3.ONE * scale
	return n


const TEX := "res://assets/env/tex/"
const FACADES := 4
const FACADE_W := 8.0
const FACADE_H := FACADE_W * 2.5   # facade textures are 1024 x 2560
static var _facade_mats: Array = []
static var _side_mats: Array = []


func _buildings() -> void:
	# A continuous row of painted facades on each side; never the same facade twice in a row.
	_facade_materials()
	for side in [-1, 1]:
		var z := NEAR_Z
		var last := -1
		while z > FAR_Z:
			var f := _rng.randi() % FACADES
			if f == last:
				f = (f + 1) % FACADES
			last = f
			var b := _facade_building(f, side)
			b.position = Vector3(side * (ROAD_HALF + 3.9), 0, z - FACADE_W * 0.5)
			add_child(b)
			_movers.append(b)
			z -= FACADE_W + 0.05


func _facade_materials() -> void:
	if not _facade_mats.is_empty():
		return
	for i in FACADES:
		var tex: Texture2D = load(TEX + "facade_%d.png" % (i + 1))
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.roughness = 0.85
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_facade_mats.append(m)
		# Side walls and roof: the facade's average colour, a little darker.
		var img := tex.get_image()
		img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
		var s := StandardMaterial3D.new()
		s.albedo_color = img.get_pixel(0, 0).darkened(0.25)
		s.roughness = 1.0
		_side_mats.append(s)


## One building: a box for the mass, the painted facade on the side facing the road.
func _facade_building(f: int, side: int) -> Node3D:
	var root := Node3D.new()
	var depth := 9.0
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(depth, FACADE_H, FACADE_W)
	body.mesh = bm
	body.material_override = _side_mats[f]
	body.position = Vector3(side * depth * 0.5, FACADE_H * 0.5, 0)
	root.add_child(body)
	var front := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(FACADE_W, FACADE_H)
	front.mesh = q
	front.material_override = _facade_mats[f]
	front.rotation.y = -PI * 0.5 * side   # face the road
	front.position = Vector3(-side * 0.02, FACADE_H * 0.5, 0)
	root.add_child(front)
	return root


func _props() -> void:
	for side in [-1, 1]:
		var z := NEAR_Z - 4.0
		var i := 0
		while z > FAR_Z:
			var prop: Node3D
			match i % 4:
				0:
					prop = model("roads/light-square.glb" if side < 0 else "roads/light-curved.glb", 8.0)
					prop.rotation.y = PI * 0.5 * side
				1:
					prop = model("bits/bush.gltf", 6.5)
				2:
					prop = model("bits/firehydrant.gltf" if (i / 4) % 2 == 0 else "bits/trash_A.gltf", 4.0)
				3:
					prop = model("bits/bench.gltf", 4.0)
					prop.rotation.y = PI * 0.5 * side
			prop.position = Vector3(side * (ROAD_HALF + 1.0 + (0.0 if i % 4 == 0 else 1.2)), 0.2, z)
			add_child(prop)
			_movers.append(prop)
			z -= 6.5
			i += 1


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
