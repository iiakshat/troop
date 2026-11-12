class_name CageView
extends Node3D
## Rescue (spec v2.1 §4.1): a hostage cage riding the road behind its guards. Steel bars, a
## padlocked door facing the squad and a blue "+N" tag (the people inside; LevelView draws them
## as police figures). The tag is a number with a rank icon, never words.
## open(): the guards fell; the lock drops, the door swings open, the tag turns green.
## lost(): the guards reached the squad; the tag greys out and the cage is dragged away.

const W := 2.3          # footprint across (m)
const D := 2.0          # depth (m)
const H := 2.15         # bar height (m)
const BAR := 0.07
const STEEL := Color("3c434d")
const STEEL_LIGHT := Color("6d7784")
const LOCK := Color("ffc93a")
const TAG_BLUE := Color("8fd0ff")
const TAG_GREEN := Color("5df07a")
const TAG_GREY := Color(0.62, 0.64, 0.68, 0.85)

var cage: Dictionary = {}
var state := "locked"      # locked | open | lost | free
var _door: Node3D
var _lock: Node3D
var _tag: Label3D
var _icon: Sprite3D
var _t := 0.0              # seconds since the last state change
var _pop := 0.0


func setup(c: Dictionary, font: Font) -> CageView:
	cage = c
	var steel := _mat(STEEL, 0.35, 0.55)
	var light := _mat(STEEL_LIGHT, 0.5, 0.45)
	# Floor plate and roof.
	_add_box(Vector3(W + 0.2, 0.14, D + 0.2), Vector3(0, 0.07, 0), steel)
	_add_box(Vector3(W + 0.1, 0.1, D + 0.1), Vector3(0, H, 0), steel)
	# Corner posts.
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_add_box(Vector3(0.14, H, 0.14), Vector3(sx * W * 0.5, H * 0.5, sz * D * 0.5), light)
	# Bars on the back and the two sides; the front is the door.
	for i in 6:
		var x := -W * 0.5 + W * (i + 0.5) / 6.0
		_add_bar(Vector3(x, H * 0.5, -D * 0.5), light)
	for sx in [-1, 1]:
		for i in 4:
			var z := -D * 0.5 + D * (i + 0.5) / 4.0
			_add_bar(Vector3(sx * W * 0.5, H * 0.5, z), light)
	# The door: hinged on its left post, bars and a cross brace, a padlock on the right edge.
	_door = Node3D.new()
	_door.position = Vector3(-W * 0.5, 0, D * 0.5)
	add_child(_door)
	for i in 6:
		var b := _bar_mesh(light)
		b.position = Vector3(W * (i + 0.5) / 6.0, H * 0.5, 0)
		_door.add_child(b)
	var brace := _box_mesh(Vector3(W, 0.1, 0.08), steel)
	brace.position = Vector3(W * 0.5, H * 0.55, 0)
	_door.add_child(brace)
	_lock = Node3D.new()
	_lock.position = Vector3(W - 0.12, H * 0.5, 0.1)
	_door.add_child(_lock)
	var body := _box_mesh(Vector3(0.3, 0.26, 0.12), _mat(LOCK, 0.6, 0.3, 0.35))
	_lock.add_child(body)
	var shackle := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.06
	tm.outer_radius = 0.1
	shackle.mesh = tm
	shackle.material_override = _mat(STEEL_LIGHT, 0.8, 0.3)
	shackle.rotation_degrees = Vector3(90, 0, 0)
	shackle.position = Vector3(0, 0.16, 0)
	_lock.add_child(shackle)
	# The tag: "+N" with a police icon, floating above the roof.
	_tag = GateRowView._label(font, 110, 0.011)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.render_priority = 9
	_tag.outline_render_priority = 8
	_tag.modulate = TAG_BLUE
	_tag.text = "+" + NumFormat.fmt(int(c.get("hostages", 0)))
	_tag.position = Vector3(0.25, H + 0.95, 0)
	add_child(_tag)
	_icon = Sprite3D.new()
	_icon.texture = UiKit.icon_texture("rank_constable")
	_icon.pixel_size = 0.75 / 320.0
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.no_depth_test = true
	_icon.render_priority = 9
	_icon.shaded = false
	_icon.position = Vector3(-0.2 - 0.09 * _tag.text.length(), H + 0.95, 0)
	add_child(_icon)
	return self


## Where the people inside stand (cage-local), for LevelView's police figures.
static func spots(n: int) -> Array:
	var out: Array = []
	for i in mini(n, 6):
		out.append(Vector3(-0.65 + 0.65 * (i % 3), 0.14, -0.4 + 0.75 * (i / 3)))
	return out


func open() -> void:
	if state != "locked":
		return
	state = "open"
	_t = 0.0
	_pop = 1.0
	_tag.modulate = TAG_GREEN


func lost() -> void:
	state = "lost"
	_t = 0.0
	_tag.modulate = TAG_GREY
	_icon.modulate = TAG_GREY


func free_people() -> void:
	state = "free"
	_t = 0.0
	_pop = 1.0


func _process(delta: float) -> void:
	_t += delta
	_pop = maxf(_pop - delta * 3.0, 0.0)
	_tag.scale = Vector3.ONE * (1.0 + 0.35 * _pop)
	match state:
		"locked":
			_lock.rotation.z = 0.12 * sin(_t * 9.0)   # it rattles: someone wants out
		"open", "free":
			_door.rotation.y = lerp_angle(_door.rotation.y, deg_to_rad(105.0), minf(delta * 8.0, 1.0))
			if _lock.visible:
				_lock.position.y -= delta * 6.0
				_lock.visible = _lock.position.y > 0.1
		"lost":
			_tag.modulate.a = maxf(0.85 - _t, 0.0)


func _add_bar(pos: Vector3, m: Material) -> void:
	var b := _bar_mesh(m)
	b.position = pos
	add_child(b)


func _bar_mesh(m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = BAR * 0.5
	cm.bottom_radius = BAR * 0.5
	cm.height = H
	cm.radial_segments = 6
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	return mi


func _add_box(size: Vector3, pos: Vector3, m: Material) -> void:
	var b := _box_mesh(size, m)
	b.position = pos
	add_child(b)


func _box_mesh(size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	return mi


static func _mat(c: Color, metal: float, rough: float, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m
