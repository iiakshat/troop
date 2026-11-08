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

## Look of each district (spec section 6): sky, sun (pitch and yaw in degrees; the low sun
## of the later districts swings towards the end of the street), fill light, ambient, fog,
## exposure, facade tint and the night extras (windows = lit-window emission, lamps = street-
## lamp glow, neon = neon strips, wet = rain-slick road with lamp reflections). Visual only:
## no gameplay number lives here.
const THEMES := {
	1: {"sky_top": "2f7fe0", "sky_hor": "bfe4ff", "ground_hor": "bfe4ff", "ground_bot": "6f8aa0", "sky_energy": 1.1,
		"sun_pitch": -48.0, "sun_yaw": 148.0, "sun_color": "fff1d9", "sun_energy": 1.35, "sun_size": 20.0,
		"fill_color": "d6e2ff", "fill_energy": 0.35, "ambient": "b9bcc9", "ambient_energy": 0.7,
		"fog": "a9cdee", "fog_density": 0.0045, "exposure": 0.95, "glow": 0.3, "saturation": 1.18,
		"tint": "ffffff", "walk": "ffffff", "windows": 0.0, "lamps": 0.0, "neon": 0.0, "wet": 0.0},
	2: {"sky_top": "3f86d6", "sky_hor": "f6dcb6", "ground_hor": "f0d2a8", "ground_bot": "8a7a6a", "sky_energy": 1.1,
		"sun_pitch": -36.0, "sun_yaw": 150.0, "sun_color": "ffdcaa", "sun_energy": 1.35, "sun_size": 18.0,
		"fill_color": "d9d2ff", "fill_energy": 0.3, "ambient": "c7b9a6", "ambient_energy": 0.68,
		"fog": "ecd2ad", "fog_density": 0.005, "exposure": 0.97, "glow": 0.32, "saturation": 1.2,
		"tint": "fff3e2", "walk": "fff4e6", "windows": 0.0, "lamps": 0.0, "neon": 0.0, "wet": 0.0},
	3: {"sky_top": "4d6fb8", "sky_hor": "ffbe76", "ground_hor": "ffb470", "ground_bot": "7a5a4a", "sky_energy": 1.15,
		"sun_pitch": -20.0, "sun_yaw": 158.0, "sun_color": "ffb25e", "sun_energy": 1.45, "sun_size": 14.0,
		"fill_color": "b9b2ff", "fill_energy": 0.32, "ambient": "b49a88", "ambient_energy": 0.62,
		"fog": "f4b77a", "fog_density": 0.0065, "exposure": 1.0, "glow": 0.38, "saturation": 1.22,
		"tint": "ffe4c2", "walk": "ffe9cf", "windows": 0.0, "lamps": 0.15, "neon": 0.0, "wet": 0.0},
	4: {"sky_top": "2e3570", "sky_hor": "ff8a4a", "ground_hor": "e07a4c", "ground_bot": "4a3040", "sky_energy": 1.0,
		"sun_pitch": -9.0, "sun_yaw": 162.0, "sun_color": "ff7a3a", "sun_energy": 1.0, "sun_size": 10.0,
		"fill_color": "8e86ff", "fill_energy": 0.38, "ambient": "8d7592", "ambient_energy": 0.72,
		"fog": "d9805a", "fog_density": 0.011, "exposure": 1.06, "glow": 0.45, "saturation": 1.18,
		"tint": "e9c6b8", "walk": "e6c4b8", "windows": 0.55, "lamps": 0.7, "neon": 0.35, "wet": 0.0},
	5: {"sky_top": "060a1f", "sky_hor": "262a63", "ground_hor": "1d2150", "ground_bot": "06070f", "sky_energy": 1.0,
		"sun_pitch": -52.0, "sun_yaw": 140.0, "sun_color": "9fb0ff", "sun_energy": 0.42, "sun_size": 3.0,
		"fill_color": "b06cff", "fill_energy": 0.28, "ambient": "5c66a8", "ambient_energy": 0.95,
		"fog": "1b2350", "fog_density": 0.012, "exposure": 1.2, "glow": 0.65, "saturation": 1.15,
		"tint": "a3a9d4", "walk": "8e93b8", "windows": 1.0, "lamps": 1.0, "neon": 1.0, "wet": 1.0},
}
const NEON_COLORS := ["ff3fa8", "38f0ff", "b25cff", "ffd23f", "48ff8a"]
const WINDOW_LIGHT := "ffc678"
const LAMP_LIGHT := "ffcf86"

var district := 1
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _walk_mat: ShaderMaterial
var _lamps: Array = []            # {prop, head (prop-local), parts: [Node3D], refl: MeshInstance3D}
var _neon: Array[Node3D] = []
var _lamp_mat: StandardMaterial3D
var _pool_mat: StandardMaterial3D
var _refl_mat: StandardMaterial3D
var _bulb_mat: StandardMaterial3D
var _neon_mats: Array = []
var _wet := 0.0


func _ready() -> void:
	_rng.seed = 7
	_environment()
	_camera()
	_ground()
	_buildings()
	_props()
	_apply_theme()


## Switches the whole look to a district (1-5; out-of-range values clamp). Safe to call
## before or after the World enters the tree, and as often as needed (one World serves the
## whole session).
func set_theme(d: int) -> void:
	district = clampi(d, 1, THEMES.size())
	if is_node_ready():
		_apply_theme()


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
	if _wet > 0.0:
		_place_reflections()


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
	_sky_mat = sm
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
	_env = env

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
	_sun = sun
	# Cool fill from the other side keeps shadowed sides from going flat.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, -40, 0)
	fill.light_energy = 0.35
	fill.light_color = Color("d6e2ff")
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY   # one sun disc in the sky
	add_child(fill)
	_fill = fill


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
	_walk_mat = walk_mat
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
		# Lit windows for dusk and night (tools/make_window_masks.py); off by day.
		var night := TEX + "facade_%d_night.png" % (i + 1)
		if ResourceLoader.exists(night):
			m.emission_enabled = true
			m.emission_texture = load(night)
			m.emission = Color(WINDOW_LIGHT)
			m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY   # colour x mask (ADD would light the whole wall)
			m.emission_energy_multiplier = 0.0
		_facade_mats.append(m)
		# Side walls and roof: the facade's average colour, a little darker.
		var img := tex.get_image()
		img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
		var s := StandardMaterial3D.new()
		s.albedo_color = img.get_pixel(0, 0).darkened(0.25)
		s.set_meta("base", s.albedo_color)
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
	_add_neon(root, side)
	return root


## Neon for the night districts: a vertical bar by one edge, a strip over the shopfront, or
## both. Plain glowing shapes (no lettering). Hidden by day.
func _add_neon(root: Node3D, side: int) -> void:
	var kind := _rng.randi() % 3
	var c := _rng.randi() % NEON_COLORS.size()
	var x := -side * 0.09
	var parts: Array = []
	if kind != 1:
		var edge := (FACADE_W * 0.5 - 0.45) * (1.0 if _rng.randf() < 0.5 else -1.0)
		var bar := _neon_box(Vector3(0.1, 4.6, 0.16), c)
		bar.position = Vector3(x, 7.6, edge)
		parts.append(bar)
		var cap := _neon_box(Vector3(0.1, 0.16, 1.0), (c + 1) % NEON_COLORS.size())
		cap.position = Vector3(x, 10.0, edge - signf(edge) * 0.42)
		parts.append(cap)
	if kind != 0:
		var strip := _neon_box(Vector3(0.1, 0.13, FACADE_W - 1.6), (c + 2) % NEON_COLORS.size())
		strip.position = Vector3(x, 4.55, 0)
		parts.append(strip)
	for n in parts:
		root.add_child(n)
		_neon.append(n)


func _neon_box(size: Vector3, color_i: int) -> MeshInstance3D:
	if _neon_mats.is_empty():
		for h in NEON_COLORS:
			var m := StandardMaterial3D.new()
			m.albedo_color = Color.BLACK
			m.emission_enabled = true
			m.emission = Color(h)
			m.emission_energy_multiplier = 3.0
			_neon_mats.append(m)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _neon_mats[color_i]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


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
					_add_lamp_glow(prop, LAMP_SQUARE_HEAD if side < 0 else LAMP_CURVED_HEAD)
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


## Lamp-head bulb positions in the Kenney models' own units (read from their meshes).
const LAMP_SQUARE_HEAD := Vector3(0, 0.575, -0.19)
const LAMP_CURVED_HEAD := Vector3(0, 0.652, -0.175)
const LAMP_SCALE := 8.0
const PROP_Y := 0.2


## Night glow for one street lamp, all unlit and unshadowed (no real lights, phone-friendly):
## a hot bulb, a soft halo, a pool of light on the road under it and a smaller one on the
## pavement, plus a reflection streak on the wet road that World moves every frame.
func _add_lamp_glow(prop: Node3D, head: Vector3) -> void:
	if _lamp_mat == null:
		_make_glow_materials()
	var parts: Array = []
	var inv := Vector3.ONE / LAMP_SCALE
	var bulb := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.32, 0.05, 0.36)
	bulb.mesh = bm
	bulb.material_override = _bulb_mat
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bulb.scale = inv
	bulb.position = head - Vector3(0, 0.002, 0)
	parts.append(bulb)
	var halo := _glow_quad(Vector2(2.4, 2.4), _lamp_mat)
	halo.scale = inv
	halo.position = head - Vector3(0, 0.01, 0)
	parts.append(halo)
	var pool := _glow_quad(Vector2(5.5, 5.5), _pool_mat)
	pool.rotation.x = -PI * 0.5
	pool.scale = inv
	pool.position = Vector3(head.x, (0.015 - PROP_Y) / LAMP_SCALE, head.z)
	parts.append(pool)
	var walk := _glow_quad(Vector2(2.2, 2.2), _pool_mat)
	walk.rotation.x = -PI * 0.5
	walk.scale = inv
	walk.position = Vector3(0, (0.207 - PROP_Y) / LAMP_SCALE, 0.04)
	parts.append(walk)
	for n in parts:
		(n as Node3D).visible = false
		prop.add_child(n)
	var refl := _glow_quad(Vector2(0.75, 7.5), _refl_mat)
	refl.top_level = true
	refl.visible = false
	add_child(refl)
	_lamps.append({"prop": prop, "head": head, "parts": parts, "refl": refl})


func _make_glow_materials() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.14), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_lamp_mat = _additive(tex, true)
	_pool_mat = _additive(tex, false)
	_refl_mat = _additive(tex, false)
	_bulb_mat = StandardMaterial3D.new()
	_bulb_mat.albedo_color = Color(LAMP_LIGHT)
	_bulb_mat.emission_enabled = true
	_bulb_mat.emission = Color(LAMP_LIGHT)
	_bulb_mat.emission_energy_multiplier = 0.0


func _additive(tex: Texture2D, billboard: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.albedo_texture = tex
	m.albedo_color = Color(LAMP_LIGHT)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return m


func _glow_quad(size: Vector2, mat: Material) -> MeshInstance3D:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	q.mesh = qm
	q.material_override = mat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return q


## Each lamp's reflection on the wet road lies where the camera would see it mirrored, and
## is smeared along the line from the camera to the lamp, as on real wet asphalt.
func _place_reflections() -> void:
	var c := camera.global_position
	var cg := Vector3(c.x, 0.0, c.z)
	for l in _lamps:
		var prop: Node3D = l["prop"]
		var refl: MeshInstance3D = l["refl"]
		var head := prop.to_global(l["head"])
		var hg := Vector3(head.x, 0.0, head.z)
		var dir := hg - cg
		if dir.z > -2.0 or c.y <= 0.0:
			refl.visible = false   # beside or behind the camera: nothing to see
			continue
		refl.visible = true
		dir = dir.normalized()
		var at := cg.lerp(hg, c.y / (c.y + head.y))
		var x := dir.cross(Vector3.UP).normalized()
		refl.global_transform = Transform3D(Basis(x, dir, Vector3.UP), at - dir * 1.2 + Vector3(0, 0.02, 0))


## Applies THEMES[district] to the sky, lights, environment, materials and night extras.
func _apply_theme() -> void:
	var t: Dictionary = THEMES[district]
	_sky_mat.sky_top_color = Color(t["sky_top"])
	_sky_mat.sky_horizon_color = Color(t["sky_hor"])
	_sky_mat.ground_horizon_color = Color(t["ground_hor"])
	_sky_mat.ground_bottom_color = Color(t["ground_bot"])
	_sky_mat.sky_energy_multiplier = float(t["sky_energy"])
	_sky_mat.sun_angle_max = float(t["sun_size"])
	_sun.rotation_degrees = Vector3(float(t["sun_pitch"]), float(t["sun_yaw"]), 0.0)
	_sun.light_color = Color(t["sun_color"])
	_sun.light_energy = float(t["sun_energy"])
	_fill.light_color = Color(t["fill_color"])
	_fill.light_energy = float(t["fill_energy"])
	_env.ambient_light_color = Color(t["ambient"])
	_env.ambient_light_energy = float(t["ambient_energy"])
	_env.fog_light_color = Color(t["fog"])
	_env.fog_density = float(t["fog_density"])
	_env.tonemap_exposure = float(t["exposure"])
	_env.glow_intensity = float(t["glow"])
	_env.adjustment_saturation = float(t["saturation"])
	var tint := Color(t["tint"])
	var windows := float(t["windows"])
	for m in _facade_mats:
		(m as StandardMaterial3D).albedo_color = tint
		(m as StandardMaterial3D).emission_energy_multiplier = windows * 1.5
	for m in _side_mats:
		(m as StandardMaterial3D).albedo_color = (m.get_meta("base") as Color) * tint
	_walk_mat.set_shader_parameter("tint", Color(t["walk"]))
	_wet = float(t["wet"])
	_road_mat.set_shader_parameter("wet", _wet)
	var lamps := float(t["lamps"])
	var lamp_col := Color(LAMP_LIGHT)
	if _bulb_mat:
		_bulb_mat.emission_energy_multiplier = lamps * 5.0
		_lamp_mat.albedo_color = Color(lamp_col, 0.75 * lamps)
		_pool_mat.albedo_color = Color(lamp_col, 0.5 * lamps)
		_refl_mat.albedo_color = Color(lamp_col, 0.3 * _wet)
	for l in _lamps:
		for n in l["parts"]:
			(n as Node3D).visible = lamps > 0.0
		if _wet <= 0.0:
			(l["refl"] as Node3D).visible = false
	var neon := float(t["neon"])
	for m in _neon_mats:
		(m as StandardMaterial3D).emission_energy_multiplier = 3.2 * neon
	for n in _neon:
		n.visible = neon > 0.0
	if _wet > 0.0:
		_place_reflections()


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
