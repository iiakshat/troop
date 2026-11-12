class_name HeroAccessory
extends Node3D
## The outfit's accessory on the hero's head (spec v2 section 6, Style panel outfits): a cap,
## a hood, shades or a crown, built from a few primitives (no asset files). The hero is a VAT
## Crowd with no skeleton, so each frame this reads the hero instance's transform and pose
## (MultiMesh custom data: rows A/B + blend) and the baked positions of his head vertices from
## the VAT image, and sits on the head through every clip. Created by LevelView via attach().

const KINDS := ["cap", "hood", "shades", "crown"]
const HEAD_DEPTH := 0.24          # metres below the top of the head that still count as head
const SAMPLES := 24

var _crowd: Crowd
var _img: Image
var _ids: PackedInt32Array = PackedInt32Array()   # sampled head vertices
var _top := -1                                    # the highest head vertex
var _fwd := Vector3(0, 0, 1)                      # face direction in mesh space
var _r := 0.11                                    # head radius (m)


## Adds the accessory of `outfit` (economy.cosmetics.outfits entry) to the hero crowd, or
## nothing when the outfit has none or the bake cannot be read.
static func attach(crowd: Crowd, outfit: Dictionary) -> HeroAccessory:
	var kind := String(outfit.get("accessory", ""))
	if crowd == null or not KINDS.has(kind):
		return null
	var a := HeroAccessory.new()
	if not a._setup(crowd):
		a.free()
		return null
	a.name = "HeroAccessory"
	a._build(kind, Color(String(outfit.get("accessory_color", "ffffff"))))
	crowd.add_child(a)
	return a


func _setup(crowd: Crowd) -> bool:
	_crowd = crowd
	var mat := crowd.material_override as ShaderMaterial
	var mesh := crowd.multimesh.mesh as ArrayMesh if crowd.multimesh else null
	if mat == null or mesh == null:
		return false
	var vat := mat.get_shader_parameter("vat") as Texture2D
	if vat == null:
		return false
	_img = vat.get_image()
	if _img == null or _img.is_empty():
		return false
	if _img.is_compressed():
		_img.decompress()
	var arr := mesh.surface_get_arrays(0)
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var col: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	if pos.is_empty():
		return false
	var top_y := -INF
	for i in pos.size():
		if pos[i].y > top_y:
			top_y = pos[i].y
			_top = i
	var head := PackedInt32Array()
	var skin := Vector3.ZERO
	var hair := Vector3.ZERO
	var ns := 0
	var nh := 0
	var top_x := pos[_top].x
	for i in pos.size():
		if pos[i].y > top_y - HEAD_DEPTH and absf(pos[i].x - top_x) < HEAD_DEPTH:
			head.append(i)
			var c := col[i] if i < col.size() else Color.WHITE
			if c.r > c.b + 0.15 and c.r > 0.6:   # skin tones: the face
				skin += pos[i]
				ns += 1
			else:
				hair += pos[i]
				nh += 1
	if head.size() < 4:
		return false
	var step := maxi(head.size() / SAMPLES, 1)
	for k in range(0, head.size(), step):
		_ids.append(head[k])
	var centre := Vector3.ZERO
	for i in _ids:
		centre += pos[i]
	centre /= float(_ids.size())
	_r = clampf((top_y - centre.y) * 1.15, 0.07, 0.2)
	if ns > 0 and nh > 0:
		var d := skin / ns - hair / nh
		d.y = 0.0
		if d.length() > 0.005:
			_fwd = d.normalized()
	return true


func _vert(i: int, ra: int, rb: int, t: float) -> Vector3:
	var a := _img.get_pixel(i, ra)
	var b := _img.get_pixel(i, rb)
	return Vector3(lerpf(a.r, b.r, t), lerpf(a.g, b.g, t), lerpf(a.b, b.b, t))


func _process(_delta: float) -> void:
	if _crowd == null or _crowd.multimesh == null or _crowd.multimesh.visible_instance_count < 1:
		visible = false
		return
	var cd := _crowd.multimesh.get_instance_custom_data(0)
	if cd.a < -0.5:
		visible = false   # dissolving away
		return
	var rows := _img.get_height()
	var ra := clampi(int(cd.r + 0.5), 0, rows - 1)
	var rb := clampi(int(cd.g + 0.5), 0, rows - 1)
	var c := Vector3.ZERO
	for i in _ids:
		c += _vert(i, ra, rb, cd.b)
	c /= float(_ids.size())
	var up := (_vert(_top, ra, rb, cd.b) - c).normalized()
	if up.length() < 0.5:
		up = Vector3.UP
	var back := -_fwd
	var right := up.cross(back).normalized()
	back = right.cross(up).normalized()
	var xf := _crowd.multimesh.get_instance_transform(0)
	transform = xf * Transform3D(Basis(right, up, back), c)
	visible = true


# ---------------------------------------------------------------- the pieces (-Z = face)

func _mat(color: Color, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = 0.35 if metal > 0.0 else 0.65
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	return m


func _piece(mesh: Mesh, at: Vector3, m: Material, scale_by := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = at
	mi.scale = scale_by
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _dome(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius
	s.is_hemisphere = true
	s.radial_segments = 16
	s.rings = 6
	return s


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _build(kind: String, color: Color) -> void:
	var r := _r
	match kind:
		"cap":
			var m := _mat(color)
			_piece(_dome(r * 1.08), Vector3(0, r * 0.3, 0), m, Vector3(1, 0.85, 1))
			_piece(_box(Vector3(r * 1.5, r * 0.12, r * 0.95)), Vector3(0, r * 0.32, -r * 1.1), _mat(color.darkened(0.25)))
		"hood":
			var m := _mat(color)
			_piece(_dome(r * 1.3), Vector3(0, -r * 0.05, r * 0.12), m, Vector3(1, 1.15, 1))
			_piece(_box(Vector3(r * 1.9, r * 0.9, r * 0.5)), Vector3(0, -r * 0.75, r * 0.75), m)
		"shades":
			var m := _mat(color, 0.6)
			_piece(_box(Vector3(r * 1.9, r * 0.32, r * 0.14)), Vector3(0, r * 0.12, -r * 0.98), m)
			var rim := _mat(Color(0.75, 0.78, 0.82), 0.8)
			_piece(_box(Vector3(r * 2.0, r * 0.07, r * 0.16)), Vector3(0, r * 0.3, -r * 0.98), rim)
		"crown":
			var gold := _mat(color, 0.85, 0.25)
			var ring := CylinderMesh.new()
			ring.top_radius = r * 0.78
			ring.bottom_radius = r * 0.72
			ring.height = r * 0.42
			ring.radial_segments = 14
			_piece(ring, Vector3(0, r * 1.0, 0), gold)
			for k in 5:
				var a := TAU * k / 5.0
				var spike := CylinderMesh.new()
				spike.top_radius = 0.0
				spike.bottom_radius = r * 0.17
				spike.height = r * 0.4
				spike.radial_segments = 6
				_piece(spike, Vector3(sin(a) * r * 0.68, r * 1.4, cos(a) * r * 0.68), gold)
			_piece(_box(Vector3(r * 0.2, r * 0.2, r * 0.08)), Vector3(0, r * 1.0, -r * 0.77), _mat(Color("d43a3a"), 0.3, 0.6))
