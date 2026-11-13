class_name LossCues
extends Node3D
## Owner play-test 2026-11-13 ("why do I suddenly lose 3-4 people every time?"): who shot reads
## at a glance. A gang that fires at the squad wears a bright gun icon over its count while its
## guns reach the squad (the icon kicks with every volley), and every volley draws one bold line
## from the shooters to the squad. The first time a gang ever fires at the player (once per
## save) a pulsing ring circles the shooters and a line ties them to the squad for FOCUS_S s:
## no pause and no slow motion. (The cause icon beside the red -N lives with the -N in LevelView.)
## Pooled: every node is made in setup(); nothing is allocated per frame.

const LINE_POOL := 6
const LINE_S := 0.6            # a volley line's life (s): solid, then fading
const LINE_FAR_W := 0.5        # its width at the shooters' end (m) ...
const LINE_NEAR_W := 0.2       # ... and where it meets the squad
const LINE_CORE := Color(1.0, 0.86, 0.25)
const LINE_HALO := Color(0.55, 0.04, 0.02)
const GUN_POOL := 8
const GUN_W := 1.5             # the gun icon's width at scale 1 (m)
const BADGE_K := 1.3           # an icon's round white badge, this much wider than the icon
const BADGE_FILL := Color(1.0, 0.98, 0.94, 0.95)
const BADGE_RIM := Color(0.93, 0.16, 0.14)
const FOCUS_S := 2.6
const FOCUS_COLOR := Color(1.0, 0.22, 0.1)
const RING_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.22, 0.1, 1.0);
uniform float pulse = 0.0;
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float aa = fwidth(r) * 1.5;
	float band = smoothstep(0.7 - aa, 0.7, r) * (1.0 - smoothstep(0.96, 0.96 + aa, r));
	float core = smoothstep(0.73, 0.76, r) * (1.0 - smoothstep(0.9, 0.93, r));
	vec3 c = mix(vec3(0.35, 0.02, 0.0), color.rgb, core);   // a bright band with dark edges
	ALBEDO = mix(c, vec3(1.0, 0.85, 0.4), 0.25 * pulse);
	ALPHA = band * color.a;
}
"""

## Where the squad's front is (the lines end there); LevelView sets it every frame.
var squad_at := Vector3(0, 1.0, -0.8)

var _lines: Array = []         # {core, halo, cmat, hmat, t, from, dx (x by the squad), y, z}
var _guns: Array[Sprite3D] = []
var _gun_owner := PackedInt32Array()   # per icon: the horde id it shows over (-1: free)
var _gun_used := PackedByteArray()     # per icon: drawn this frame
var _ring: MeshInstance3D
var _ring_mat: ShaderMaterial
var _focus_line: Dictionary = {}
var focus_id := -1             # the gang the first-time highlight is on (-1: none)
var focus_t := 0.0             # seconds of highlight left
var _focus_at := Vector3.ZERO
var _focus_r := 3.0
var _focus_seen := false       # the gang reported its position this frame
var _t := 0.0
static var _badge: Texture2D = null


func setup() -> LossCues:
	name = "LossCues"
	var mesh := tapered_mesh(LINE_FAR_W, LINE_NEAR_W)
	var halo_mesh := tapered_mesh(LINE_FAR_W * 1.9, LINE_NEAR_W * 2.4)
	for i in LINE_POOL + 1:
		var ln := _make_line(mesh, halo_mesh)
		if i < LINE_POOL:
			_lines.append(ln)
		else:
			_focus_line = ln
	var tex := UiKit.icon_texture("pistol")
	for i in GUN_POOL:
		var s := Sprite3D.new()
		s.texture = tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.no_depth_test = true
		s.render_priority = 6
		s.pixel_size = GUN_W / maxf(float(tex.get_width()) if tex else 320.0, 1.0)
		s.visible = false
		s.add_child(badge(GUN_W, 5))
		add_child(s)
		_guns.append(s)
	_gun_owner.resize(GUN_POOL)
	_gun_owner.fill(-1)
	_gun_used.resize(GUN_POOL)
	_gun_used.fill(0)
	_ring = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	_ring.mesh = q
	_ring_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = RING_SHADER
	_ring_mat.shader = sh
	_ring_mat.render_priority = 5
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)
	return self


func _make_line(mesh: Mesh, halo_mesh: Mesh) -> Dictionary:
	var out := {"t": 0.0, "from": Vector3.ZERO, "dx": 0.0, "y": 1.0, "z": -0.8}
	for part in ["halo", "core"]:
		var mi := MeshInstance3D.new()
		mi.mesh = halo_mesh if part == "halo" else mesh
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = true
		m.disable_fog = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.render_priority = 3 if part == "halo" else 4
		m.albedo_color = LINE_HALO if part == "halo" else LINE_CORE
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		out[part] = mi
		out["hmat" if part == "halo" else "cmat"] = m
	return out


## A round white badge with a red rim for an icon `icon_w` m wide (a child of the icon's sprite,
## drawn just under it): a dark icon reads on the asphalt, the sky and the stash alike.
static func badge(icon_w: float, priority: int) -> Sprite3D:
	var b := Sprite3D.new()
	b.texture = badge_texture()
	b.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	b.shaded = false
	b.no_depth_test = true
	b.render_priority = priority
	b.pixel_size = icon_w * BADGE_K / float(b.texture.get_width())
	b.name = "Badge"
	return b


static func badge_texture() -> Texture2D:
	if _badge == null:
		var n := 96
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var c := (n - 1) * 0.5
		for y in n:
			for x in n:
				var r := Vector2(x - c, y - c).length() / c
				var col := BADGE_FILL if r < 0.82 else BADGE_RIM
				col.a *= clampf((1.0 - r) * c, 0.0, 1.0)   # a soft edge one pixel wide
				img.set_pixel(x, y, col)
		_badge = ImageTexture.create_from_image(img)
	return _badge


## A beam one metre long along -z..+z (scaled to its length): `far` m wide at its +z end (the
## shooter's), `near` at the -z end. A flat ribbon and its upright twin, so it reads from above.
static func tapered_mesh(far: float, near: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var f := far * 0.5
	var n := near * 0.5
	for quad in [[Vector3(-n, 0, -0.5), Vector3(n, 0, -0.5), Vector3(f, 0, 0.5), Vector3(-f, 0, 0.5)],
			[Vector3(0, -n, -0.5), Vector3(0, n, -0.5), Vector3(0, f, 0.5), Vector3(0, -f, 0.5)]]:
		for k in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(quad[k])
	return st.commit()


## One volley: a bold line from the shooters (`from`) to the squad's front, LINE_S s.
func volley(from: Vector3) -> void:
	var best: Dictionary = _lines[0]
	for ln in _lines:
		if float(ln["t"]) <= 0.0:
			best = ln
			break
		if float(ln["t"]) < float(best["t"]):
			best = ln
	best["t"] = LINE_S
	best["from"] = from
	best["dx"] = 0.0
	best["y"] = squad_at.y
	best["z"] = squad_at.z


## Lines showing now (tests).
func lines_shown() -> int:
	var n := 0
	for ln in _lines:
		if (ln["core"] as Node3D).visible:
			n += 1
	return n


## The gang `id` fires at the squad: its gun icon over `at` this frame, `size` x GUN_W wide,
## kicked up by `kick` (0..1, a volley just went out).
func gun(id: int, at: Vector3, size: float, kick: float) -> void:
	var i := _gun_owner.find(id)
	if i < 0:
		i = _gun_owner.find(-1)
		if i < 0:
			return   # more firing gangs than icons (never in practice): the rest still flash
		_gun_owner[i] = id
	_gun_used[i] = 1
	var s: Sprite3D = _guns[i]
	s.visible = true
	s.position = at
	s.scale = Vector3.ONE * size * (1.0 + 0.45 * kick)
	s.modulate = Color(1, 1, 1).lerp(Color(1.0, 0.9, 0.55), kick)


## Gun icons showing now (tests).
func guns_shown() -> int:
	var n := 0
	for s in _guns:
		if s.visible:
			n += 1
	return n


## The first-time highlight on gang `id` (LevelView reports where it is with focus_at).
func focus_on(id: int) -> void:
	focus_id = id
	focus_t = FOCUS_S


## Where the highlighted gang stands this frame (`at`: the middle of its front, chest high) and
## how wide it is (`radius`, m).
func focus_at(at: Vector3, radius: float) -> void:
	_focus_at = at
	_focus_r = radius
	_focus_seen = true


func update(d: float, cam: Camera3D) -> void:
	_t += d
	for ln in _lines:
		var t := maxf(float(ln["t"]) - d, 0.0)
		ln["t"] = t
		var on := t > 0.0
		(ln["core"] as Node3D).visible = on
		(ln["halo"] as Node3D).visible = on
		if not on:
			continue
		var a := clampf(t / (LINE_S * 0.5), 0.0, 1.0)   # solid for the first half, then fading
		_place(ln, ln["from"], Vector3(squad_at.x + float(ln["dx"]), float(ln["y"]), float(ln["z"])), a, 1.0)
	# Guns: whatever no gang drew this frame goes away.
	for i in _guns.size():
		if _gun_used[i] == 0:
			_guns[i].visible = false
			_gun_owner[i] = -1
		_gun_used[i] = 0
	# The first-time highlight follows its gang until FOCUS_S runs out or the gang is gone.
	if focus_id >= 0:
		focus_t = maxf(focus_t - d, 0.0)
		if focus_t <= 0.0 or not _focus_seen:
			focus_id = -1
	var shown := focus_id >= 0
	_ring.visible = shown
	(_focus_line["core"] as Node3D).visible = shown
	(_focus_line["halo"] as Node3D).visible = shown
	if shown:
		var pulse := 0.5 + 0.5 * sin(_t * 12.0)
		var fade := clampf(focus_t / 0.4, 0.0, 1.0)
		var face := Basis()
		if cam != null and cam.global_position.distance_to(_focus_at) > 0.1:
			face = Basis.looking_at(cam.global_position - _focus_at, Vector3.UP)
		_ring.transform = Transform3D(face.scaled(Vector3.ONE * _focus_r * (1.0 + 0.08 * pulse)), _focus_at)
		_ring_mat.set_shader_parameter("color", Color(FOCUS_COLOR, fade))
		_ring_mat.set_shader_parameter("pulse", pulse)
		_place(_focus_line, _focus_at + Vector3(0, -_focus_r * 0.6, 0), squad_at, fade * (0.75 + 0.25 * pulse), 1.4)
	_focus_seen = false


func _place(ln: Dictionary, from: Vector3, to: Vector3, alpha: float, width: float) -> void:
	var dir := from - to
	var length := dir.length()
	if length < 0.1:
		(ln["core"] as Node3D).visible = false
		(ln["halo"] as Node3D).visible = false
		return
	var basis := Basis.looking_at(-dir / length, Vector3.UP).scaled_local(Vector3(width, width, length))
	var xf := Transform3D(basis, (from + to) * 0.5)
	(ln["core"] as MeshInstance3D).transform = xf
	(ln["halo"] as MeshInstance3D).transform = xf
	(ln["cmat"] as StandardMaterial3D).albedo_color = Color(LINE_CORE, alpha)
	(ln["hmat"] as StandardMaterial3D).albedo_color = Color(LINE_HALO, 0.55 * alpha)


## Invisible copies of every cue (LevelView's load-time prewarm draws them out of sight for a
## few frames, so their materials compile while loading, not at the first volley).
func warm_nodes(at: Vector3) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for part in ["core", "halo"]:
		var mi := MeshInstance3D.new()
		mi.mesh = (_focus_line[part] as MeshInstance3D).mesh
		var m := ((_focus_line[part] as MeshInstance3D).material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.albedo_color.a = 0.0
		mi.material_override = m
		mi.position = at
		out.append(mi)
	var s := Sprite3D.new()
	s.texture = _guns[0].texture
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.no_depth_test = true
	s.render_priority = 6
	s.pixel_size = _guns[0].pixel_size
	s.modulate = Color(1, 1, 1, 0)
	s.position = at
	out.append(s)
	var ring := MeshInstance3D.new()
	ring.mesh = _ring.mesh
	var rm := _ring_mat.duplicate() as ShaderMaterial
	rm.set_shader_parameter("color", Color(FOCUS_COLOR, 0.0))
	ring.material_override = rm
	ring.position = at
	out.append(ring)
	return out


## Every cue off at once (a revive, the finish, the loss).
func clear() -> void:
	for ln in _lines:
		ln["t"] = 0.0
	focus_id = -1
	focus_t = 0.0
