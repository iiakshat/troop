class_name BottleMesh
extends RefCounted
## Bottles for the Bottle Shot gallery, built by spinning a profile (lathe): beer, wine, soda,
## a round potion jug and the gold champagne bottle. Each has its own glass tint, drink,
## printed label (pictures, never words) and cap. A bottle node's origin is its base centre.
## The broken pieces (jagged stump left standing, flying neck) come from the same profiles.

const GLASS := preload("res://src/finale/glass.gdshader")
const GLASS_OPEN := preload("res://src/finale/glass_open.gdshader")
const LIQUID := preload("res://src/finale/liquid.gdshader")
const LABEL := preload("res://src/finale/label.gdshader")
const SEGMENTS := 32

enum { BEER, SODA, WINE, JUG, CHAMPAGNE }

# Profiles are (radius, height) from the base up, in metres (before the gallery's scale).
# label = [radius, y0, y1, wrap fraction]; cap = [kind, radius, y0, y1]; fill = drink height;
# body = where the shoulder starts; neck = where a broken neck snaps off; stump = stump height.
const SHAPES := [
	{"profile": [Vector2(0.0, 0.0), Vector2(0.078, 0.0), Vector2(0.085, 0.01), Vector2(0.086, 0.03),
		Vector2(0.086, 0.3), Vector2(0.082, 0.34), Vector2(0.066, 0.385), Vector2(0.045, 0.42),
		Vector2(0.032, 0.45), Vector2(0.029, 0.5), Vector2(0.029, 0.565), Vector2(0.033, 0.57),
		Vector2(0.033, 0.585), Vector2(0.0, 0.585)],
		"label": [0.0875, 0.1, 0.25, 0.7], "neck_label": [0.0305, 0.47, 0.53],
		"cap": ["crown", 0.035, 0.565, 0.602], "fill": 0.48, "body": 0.3, "neck": 0.4, "stump": 0.07},
	{"profile": [Vector2(0.0, 0.0), Vector2(0.07, 0.0), Vector2(0.078, 0.012), Vector2(0.08, 0.04),
		Vector2(0.074, 0.09), Vector2(0.068, 0.13), Vector2(0.072, 0.17), Vector2(0.08, 0.22),
		Vector2(0.082, 0.26), Vector2(0.078, 0.3), Vector2(0.068, 0.34), Vector2(0.052, 0.39),
		Vector2(0.036, 0.44), Vector2(0.027, 0.48), Vector2(0.026, 0.53), Vector2(0.03, 0.535),
		Vector2(0.03, 0.55), Vector2(0.0, 0.55)],
		"label": [0.0835, 0.19, 0.265, 1.0], "cap": ["screw", 0.032, 0.528, 0.578],
		"fill": 0.44, "body": 0.3, "neck": 0.38, "stump": 0.06},
	{"profile": [Vector2(0.0, 0.0), Vector2(0.08, 0.0), Vector2(0.088, 0.012), Vector2(0.09, 0.03),
		Vector2(0.09, 0.34), Vector2(0.087, 0.37), Vector2(0.075, 0.4), Vector2(0.052, 0.425),
		Vector2(0.036, 0.445), Vector2(0.031, 0.47), Vector2(0.03, 0.58), Vector2(0.033, 0.585),
		Vector2(0.033, 0.6), Vector2(0.0, 0.6)],
		"label": [0.0915, 0.09, 0.24, 0.62], "cap": ["foil", 0.0345, 0.52, 0.606],
		"fill": 0.4, "body": 0.34, "neck": 0.41, "stump": 0.08},
	{"profile": [Vector2(0.0, 0.0), Vector2(0.09, 0.0), Vector2(0.1, 0.015), Vector2(0.108, 0.05),
		Vector2(0.11, 0.12), Vector2(0.106, 0.2), Vector2(0.092, 0.26), Vector2(0.07, 0.31),
		Vector2(0.045, 0.345), Vector2(0.034, 0.37), Vector2(0.032, 0.5), Vector2(0.036, 0.505),
		Vector2(0.036, 0.52), Vector2(0.0, 0.52)],
		"label": [0.1115, 0.05, 0.16, 0.55], "cap": ["cork", 0.029, 0.49, 0.585],
		"fill": 0.27, "body": 0.2, "neck": 0.33, "stump": 0.06},
	{"profile": [Vector2(0.0, 0.0), Vector2(0.085, 0.0), Vector2(0.092, 0.015), Vector2(0.093, 0.04),
		Vector2(0.093, 0.3), Vector2(0.09, 0.34), Vector2(0.08, 0.38), Vector2(0.062, 0.42),
		Vector2(0.045, 0.46), Vector2(0.036, 0.5), Vector2(0.033, 0.58), Vector2(0.036, 0.6),
		Vector2(0.036, 0.615), Vector2(0.0, 0.615)],
		"label": [0.0945, 0.11, 0.25, 0.66], "cap": ["foil", 0.0385, 0.46, 0.64],
		"fill": 0.45, "body": 0.3, "neck": 0.43, "stump": 0.07},
]

static var _meshes: Dictionary = {}   # "shape:part" -> Mesh


## A whole bottle. `shape` < 0 picks one from the hue. Children: Glass, Liquid, Label, Cap
## (+ NeckLabel), and a hidden Stump shown when it breaks. Meta: shape, glass, drink.
static func make(gold: bool, hue: float, shape := -1) -> Node3D:
	if gold:
		shape = CHAMPAGNE
	elif shape < 0 or shape >= CHAMPAGNE:
		shape = int(hue * 4.0) % 4
	var sh: Dictionary = SHAPES[shape]
	var look := _look(shape, hue)
	var root := Node3D.new()
	root.set_meta("shape", shape)
	root.set_meta("glass", look["glass"])
	root.set_meta("drink", look["drink"])
	var liquid := _mi("Liquid", _mesh(shape, "liquid"))
	var lm := ShaderMaterial.new()
	lm.shader = LIQUID
	lm.set_shader_parameter("color", look["drink"])
	lm.set_shader_parameter("fill_top", float(sh["fill"]))
	lm.set_shader_parameter("bubbles", look["bubbles"])
	liquid.material_override = lm
	root.add_child(liquid)
	var lab: Array = sh["label"]
	var label := _mi("Label", _mesh(shape, "label"))
	label.material_override = _label_material(look, float(lab[3]), float(lab[0]), float(lab[2]) - float(lab[1]))
	root.add_child(label)
	if sh.has("neck_label"):
		var nl := _mi("NeckLabel", _mesh(shape, "neck_label"))
		var nm := StandardMaterial3D.new()
		nm.albedo_color = look["ink"]
		nm.metallic = 0.6
		nm.roughness = 0.3
		nl.material_override = nm
		root.add_child(nl)
	var cap := _mi("Cap", _mesh(shape, "cap"))
	cap.material_override = _cap_material(String((sh["cap"] as Array)[0]), look["cap"])
	root.add_child(cap)
	var glass := _mi("Glass", _mesh(shape, "glass"))
	glass.material_override = _glass_material(GLASS, look, sh)
	root.add_child(glass)
	var stump := _mi("Stump", _mesh(shape, "stump"))
	stump.material_override = _glass_material(GLASS_OPEN, look, sh)
	stump.visible = false
	root.add_child(stump)
	return root


## Hides the whole bottle except the jagged stump (`keep_stump`), and returns a new flying
## neck piece (glass + cap) positioned where the neck was, or null.
static func break_apart(bottle: Node3D, keep_stump: bool, with_neck: bool) -> Node3D:
	var shape := int(bottle.get_meta("shape", 0))
	var sh: Dictionary = SHAPES[shape]
	for part in ["Glass", "Liquid", "Label", "NeckLabel", "Cap"]:
		var n := bottle.get_node_or_null(part) as Node3D
		if n:
			n.visible = false
	(bottle.get_node("Stump") as Node3D).visible = keep_stump
	if not with_neck:
		return null
	var look := {"glass": bottle.get_meta("glass"), "drink": bottle.get_meta("drink")}
	var neck := Node3D.new()
	var glass := _mi("NeckGlass", _mesh(shape, "neck"))
	glass.material_override = _glass_material(GLASS_OPEN, look, sh)
	neck.add_child(glass)
	var cap := bottle.get_node_or_null("Cap") as MeshInstance3D
	if cap:
		var c2 := _mi("Cap", cap.mesh)
		c2.material_override = cap.material_override
		neck.add_child(c2)
	# Pivot near the neck's centre so it spins naturally; children shift down to match.
	var ny := float(sh["neck"])
	var top := (sh["profile"] as Array).back().y as float
	var mid := (ny + top) * 0.5
	for c in neck.get_children():
		(c as Node3D).position.y = -mid
	neck.set_meta("pivot", mid)
	return neck


## The drink colour of a bottle node (for spray and stains).
static func drink_color(bottle: Node3D) -> Color:
	return bottle.get_meta("drink", Color(0.8, 0.3, 0.3))


static func glass_color(bottle: Node3D) -> Color:
	return bottle.get_meta("glass", Color(0.8, 0.9, 0.9, 0.2))


## Height of a shape's top in metres (before scale).
static func height(shape: int) -> float:
	return (SHAPES[shape]["profile"] as Array).back().y


# ---------------------------------------------------------------- looks

static func _look(shape: int, hue: float) -> Dictionary:
	var vivid := Color.from_hsv(hue, 0.82, 0.92)
	var ink := Color.from_hsv(fmod(hue + 0.55, 1.0), 0.75, 0.6)
	match shape:
		BEER:
			var amber := hue > 0.5
			return {"glass": Color(0.62, 0.38, 0.12, 0.42) if amber else Color(0.36, 0.66, 0.3, 0.32),
				"drink": Color(1.0, 0.66, 0.12), "bubbles": 0.55, "paper": Color(0.97, 0.93, 0.8),
				"ink": ink, "trim": Color(0.86, 0.66, 0.22), "pattern": 0 if hue < 0.33 or hue > 0.75 else 1,
				"cap": Color.from_hsv(fmod(hue + 0.55, 1.0), 0.8, 0.75), "metal": 0.0}
		WINE:
			var drinks := [Color(0.82, 0.07, 0.16), Color(1.0, 0.5, 0.56), Color(1.0, 0.86, 0.42)]
			var d: Color = drinks[int(hue * 3.0) % 3]
			return {"glass": Color(0.42, 0.62, 0.4, 0.36), "drink": d, "bubbles": 0.0,
				"paper": Color(0.98, 0.97, 0.93), "ink": Color(0.45, 0.06, 0.12), "trim": Color(0.8, 0.64, 0.25),
				"pattern": 3, "cap": Color(0.5, 0.05, 0.1) if d.r < 0.8 else Color(0.12, 0.12, 0.14), "metal": 0.0}
		SODA:
			return {"glass": Color(0.78, 0.96, 0.92, 0.14), "drink": vivid, "bubbles": 0.9,
				"paper": Color.from_hsv(fmod(hue + 0.5, 1.0), 0.75, 0.95), "ink": Color(1, 1, 1),
				"trim": Color(1.0, 0.85, 0.3), "pattern": 2, "cap": vivid.darkened(0.25), "metal": 0.0}
		JUG:
			return {"glass": Color(0.92, 0.96, 1.0, 0.1), "drink": vivid, "bubbles": 0.0,
				"paper": Color(0.86, 0.74, 0.52), "ink": Color(0.36, 0.2, 0.1), "trim": Color(0.55, 0.32, 0.16),
				"pattern": 1 if hue < 0.5 else 0, "cap": Color(0.72, 0.52, 0.32), "metal": 0.0}
	return {"glass": Color(1.0, 0.8, 0.32, 0.4), "drink": Color(1.0, 0.76, 0.2), "bubbles": 1.0,
		"paper": Color(0.1, 0.08, 0.07), "ink": Color(0.95, 0.76, 0.28), "trim": Color(1.0, 0.85, 0.4),
		"pattern": 4, "cap": Color(0.95, 0.75, 0.25), "metal": 1.0, "sparkle": 1.4}


static func _glass_material(shader: Shader, look: Dictionary, sh: Dictionary) -> ShaderMaterial:
	var gm := ShaderMaterial.new()
	gm.shader = shader
	gm.set_shader_parameter("tint", look["glass"])
	var drink: Color = look["drink"]
	gm.set_shader_parameter("caustic_color", drink.lerp(Color.WHITE, 0.25))
	gm.set_shader_parameter("body_top", float(sh["body"]))
	gm.set_shader_parameter("sparkle", float(look.get("sparkle", 0.0)))
	return gm


static func _label_material(look: Dictionary, wrap: float, r: float, h: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LABEL
	m.set_shader_parameter("paper", look["paper"])
	m.set_shader_parameter("ink", look["ink"])
	m.set_shader_parameter("trim", look["trim"])
	m.set_shader_parameter("pattern", int(look["pattern"]))
	m.set_shader_parameter("wrap", wrap)
	m.set_shader_parameter("aspect", wrap * TAU * r / h)
	m.set_shader_parameter("metal", float(look["metal"]))
	return m


static func _cap_material(kind: String, color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	match kind:
		"crown":
			m.metallic = 0.8
			m.roughness = 0.3
		"foil":
			m.metallic = 0.9
			m.roughness = 0.25
		"screw":
			m.roughness = 0.45
		"cork":
			m.roughness = 0.95
	return m


# ---------------------------------------------------------------- meshes

static func _mi(n: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	return mi


static func _mesh(shape: int, part: String) -> Mesh:
	var key := "%d:%s" % [shape, part]
	if _meshes.has(key):
		return _meshes[key]
	var sh: Dictionary = SHAPES[shape]
	var prof: Array = sh["profile"]
	var top: float = prof.back().y
	var m: Mesh
	match part:
		"glass":
			var rings := _rings(prof, 1.0, 0.0, top)
			rings.append({"r": 0.0, "y": top})
			m = _lathe(rings, top)
		"liquid":
			var rings := _rings(prof, 0.88, 0.006, float(sh["fill"]))
			rings.insert(0, {"r": 0.0, "y": 0.006})
			rings.append({"r": 0.0, "y": float(sh["fill"])})
			m = _lathe(rings, top)
		"label":
			var lab: Array = sh["label"]
			m = _lathe([{"r": float(lab[0]), "y": float(lab[1])}, {"r": float(lab[0]), "y": float(lab[2])}], 0.0)
		"neck_label":
			var nl: Array = sh["neck_label"]
			m = _lathe([{"r": float(nl[0]), "y": float(nl[1])}, {"r": float(nl[0]), "y": float(nl[2])}], 0.0)
		"cap":
			m = _cap(sh["cap"])
		"stump":
			var rings := _rings(prof, 1.0, 0.0, float(sh["stump"]))
			(rings.back() as Dictionary)["jag"] = 0.035
			m = _lathe(rings, top, 11)
		"neck":
			var rings := _rings(prof, 1.0, float(sh["neck"]), top)
			(rings.front() as Dictionary)["jag"] = -0.04
			m = _lathe(rings, top, 29)
	_meshes[key] = m
	return m


## Profile rings between heights y0 and y1 (cut exactly at both), radius scaled.
static func _rings(prof: Array, scale_r: float, y0: float, y1: float) -> Array:
	var out: Array = []
	out.append({"r": _radius_at(prof, y0) * scale_r, "y": y0})
	for p in prof:
		var v: Vector2 = p
		if v.y > y0 + 0.0001 and v.y < y1 - 0.0001:
			out.append({"r": v.x * scale_r, "y": v.y})
	out.append({"r": _radius_at(prof, y1) * scale_r, "y": y1})
	if y0 <= 0.0001:
		out.insert(0, {"r": 0.0, "y": 0.0})   # close the base
	return out


static func _radius_at(prof: Array, y: float) -> float:
	for i in prof.size() - 1:
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[i + 1]
		if a.y <= y and b.y >= y and b.y > a.y:
			return lerpf(a.x, b.x, (y - a.y) / (b.y - a.y))
	if y <= 0.0001:
		return (prof[1] as Vector2).x
	return 0.0


## Spins rings {r, y, jag?} round the y axis. A ring with `jag` gets a broken, uneven edge
## (random heights up to `jag`, seeded so every stump/neck of a shape matches its mesh).
static func _lathe(rings: Array, height: float, seed := 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var jag_y: Array = []
	for r in rings:
		var row := PackedFloat32Array()
		row.resize(SEGMENTS + 1)
		var j := float((r as Dictionary).get("jag", 0.0))
		for s in SEGMENTS:
			row[s] = (rng.randf_range(0.15, 1.0) * j) if j != 0.0 and (s % 2 == 0 or rng.randf() < 0.4) else j * 0.1
		row[SEGMENTS] = row[0]
		jag_y.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for i in rings.size() - 1:
		var a: Dictionary = rings[i]
		var b: Dictionary = rings[i + 1]
		for s in SEGMENTS:
			var t0 := TAU * s / SEGMENTS
			var t1 := TAU * (s + 1) / SEGMENTS
			var ya0 := float(a["y"]) + float(jag_y[i][s])
			var ya1 := float(a["y"]) + float(jag_y[i][s + 1])
			var yb0 := float(b["y"]) + float(jag_y[i + 1][s])
			var yb1 := float(b["y"]) + float(jag_y[i + 1][s + 1])
			var ra := float(a["r"])
			var rb := float(b["r"])
			var a0 := Vector3(cos(t0) * ra, ya0, sin(t0) * ra)
			var a1 := Vector3(cos(t1) * ra, ya1, sin(t1) * ra)
			var b0 := Vector3(cos(t0) * rb, yb0, sin(t0) * rb)
			var b1 := Vector3(cos(t1) * rb, yb1, sin(t1) * rb)
			var u0 := float(s) / SEGMENTS
			var u1 := float(s + 1) / SEGMENTS
			# v runs up the bottle (0..1 of `height`); bands (height 0) get 0 at the bottom ring.
			var va0 := ya0 / height if height > 0.0 else 0.0
			var va1 := ya1 / height if height > 0.0 else 0.0
			var vb0 := yb0 / height if height > 0.0 else 1.0
			var vb1 := yb1 / height if height > 0.0 else 1.0
			# Godot's front faces wind clockwise seen from outside.
			var quad := [[a0, Vector2(u0, va0)], [b1, Vector2(u1, vb1)], [b0, Vector2(u0, vb0)],
				[a0, Vector2(u0, va0)], [a1, Vector2(u1, va1)], [b1, Vector2(u1, vb1)]]
			for q in quad:
				st.set_uv(q[1])
				st.add_vertex(q[0])
	st.generate_normals()
	return st.commit()


static func _cap(c: Array) -> ArrayMesh:
	var kind := String(c[0])
	var r := float(c[1])
	var y0 := float(c[2])
	var y1 := float(c[3])
	var rings: Array = [{"r": 0.0, "y": y0}, {"r": r, "y": y0}]
	match kind:
		"crown":
			rings.append({"r": r * 1.04, "y": y0 + (y1 - y0) * 0.45})
			rings.append({"r": r * 0.96, "y": y1 - 0.004})
			rings.append({"r": r * 0.85, "y": y1})
		"foil":
			rings.append({"r": r, "y": y1 - 0.01})
			rings.append({"r": r * 0.8, "y": y1})
		"screw":
			for k in 5:
				var y := lerpf(y0, y1 - 0.004, (k + 1) / 5.0)
				rings.append({"r": r * (1.0 if k % 2 == 0 else 1.05), "y": y})
			rings.append({"r": r * 0.9, "y": y1})
		"cork":
			rings.append({"r": r * 1.06, "y": y1 - 0.012})
			rings.append({"r": r * 0.92, "y": y1})
	rings.append({"r": 0.0, "y": y1})
	return _lathe(rings, 0.0)
