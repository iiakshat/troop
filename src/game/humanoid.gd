class_name Humanoid
extends RefCounted
## Builds low-poly people out of boxes, coloured per role. No art files.
## Each vertex carries UV = (part, pivot_y) so the crowd shader can swing legs and
## arms on the GPU; that is what lets hundreds of them run on a cheap phone.
## Parts: -1 shadow, 0 body, 1 left leg, 2 right leg, 3 left arm, 4 right (weapon) arm.
## Characters face -z.

const HIP := 0.78
const SHOULDER := 1.36

const LOOKS := {
	"hero": {"skin": "e2b48f", "hair": "3b2a20", "shirt": "21c7b5", "pants": "3d6fb6", "shoes": "f2f2f2",
		"hat": "", "weapon": "knife", "scale": 1.05},
	"constable": {"skin": "c99772", "hair": "1d1d1d", "shirt": "2b4c8c", "pants": "1d2f57", "shoes": "111111",
		"hat": "cap", "hat_color": "1d2f57", "badge": "f2c14e", "weapon": "pistol", "scale": 1.0},
	"inspector": {"skin": "b9875f", "hair": "1d1d1d", "shirt": "8fb3e8", "pants": "1d2f57", "shoes": "3b2a20",
		"hat": "peaked", "hat_color": "1d2f57", "badge": "f2c14e", "belt": "6b4a2b", "weapon": "revolver", "scale": 1.12},
	"thug": {"skin": "d8a987", "hair": "222222", "shirt": "b3282d", "pants": "2a2a2a", "shoes": "111111",
		"hat": "bandana", "hat_color": "222222", "weapon": "bat", "scale": 1.0},
	"knifer": {"skin": "c48e6a", "hair": "222222", "shirt": "6b2d8f", "pants": "262626", "shoes": "111111",
		"hat": "beanie", "hat_color": "141414", "weapon": "knife", "scale": 0.96},
	"gunman": {"skin": "d0a080", "hair": "111111", "shirt": "1e1e1e", "pants": "3a3a3a", "shoes": "111111",
		"hat": "shades", "hat_color": "111111", "weapon": "gun", "scale": 1.0},
	"brute": {"skin": "b07a58", "hair": "111111", "shirt": "5a5f3a", "pants": "2b2b2b", "shoes": "111111",
		"hat": "helmet", "hat_color": "3d4030", "vest": "7d8466", "weapon": "club", "scale": 1.45, "bulk": 1.3},
}

static var _cache: Dictionary = {}


static func mesh(kind: String) -> ArrayMesh:
	if not _cache.has(kind):
		_cache[kind] = _build(LOOKS[kind])
	return _cache[kind]


static func _build(look: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sc := float(look.get("scale", 1.0)) * 1.12
	var bulk := float(look.get("bulk", 1.0))
	var skin := Color(look["skin"])
	var shirt := Color(look["shirt"])
	var pants := Color(look["pants"])
	var shoes := Color(look["shoes"])
	var hair := Color(look["hair"])

	# Soft round shadow (an opaque dark disc; the road is one colour, so it reads as shadow).
	_disc(st, Vector3(0, 0.02, 0), 0.42 * bulk * sc, Color(0.16, 0.17, 0.2))

	var leg_w := 0.2 * bulk
	for side in [-1, 1]:
		var part := 1.0 if side < 0 else 2.0
		_box(st, Vector3(0.12 * side * bulk, 0.42, 0), Vector3(leg_w, 0.72, 0.24), pants, part, HIP, sc)
		_box(st, Vector3(0.12 * side * bulk, 0.06, -0.04), Vector3(leg_w + 0.02, 0.12, 0.32), shoes, part, HIP, sc)
	# Torso and head.
	_box(st, Vector3(0, 1.08, 0), Vector3(0.56 * bulk, 0.66, 0.32 * bulk), shirt, 0.0, 0.0, sc)
	if look.has("vest"):
		_box(st, Vector3(0, 1.1, 0), Vector3(0.62 * bulk, 0.5, 0.38 * bulk), Color(look["vest"]), 0.0, 0.0, sc)
	if look.has("belt"):
		_box(st, Vector3(0, 0.8, 0), Vector3(0.58 * bulk, 0.08, 0.34 * bulk), Color(look["belt"]), 0.0, 0.0, sc)
	if look.has("badge"):
		_box(st, Vector3(-0.13 * bulk, 1.22, -0.17 * bulk), Vector3(0.09, 0.09, 0.03), Color(look["badge"]), 0.0, 0.0, sc)
	_box(st, Vector3(0, 1.58, 0), Vector3(0.36, 0.36, 0.34), skin, 0.0, 0.0, sc)
	_box(st, Vector3(0, 1.79, 0.02), Vector3(0.38, 0.08, 0.36), hair, 0.0, 0.0, sc)
	# Eyes: two dark dots so faces read at a glance.
	for side in [-1, 1]:
		_box(st, Vector3(0.08 * side, 1.62, -0.175), Vector3(0.05, 0.06, 0.02), Color(0.1, 0.1, 0.12), 0.0, 0.0, sc)
	_hat(st, look, sc)

	# Arms (left swings freely, right carries the weapon).
	var arm_w := 0.16 * bulk
	for side in [-1, 1]:
		var part := 3.0 if side < 0 else 4.0
		var ax: float = (0.28 * bulk + arm_w * 0.5) * side
		_box(st, Vector3(ax, 1.12, 0), Vector3(arm_w, 0.56, 0.18), shirt, part, SHOULDER, sc)
		_box(st, Vector3(ax, 0.8, 0), Vector3(arm_w * 0.9, 0.12, 0.16), skin, part, SHOULDER, sc)
	_weapon(st, String(look.get("weapon", "")), (0.28 * bulk + arm_w * 0.5), sc)

	st.generate_normals()
	return st.commit()


static func _hat(st: SurfaceTool, look: Dictionary, sc: float) -> void:
	var c := Color(look.get("hat_color", "222222"))
	match String(look.get("hat", "")):
		"cap":
			_box(st, Vector3(0, 1.86, 0), Vector3(0.4, 0.12, 0.38), c, 0.0, 0.0, sc)
			_box(st, Vector3(0, 1.81, -0.24), Vector3(0.36, 0.04, 0.14), c, 0.0, 0.0, sc)
		"peaked":
			_box(st, Vector3(0, 1.9, 0), Vector3(0.44, 0.16, 0.42), c, 0.0, 0.0, sc)
			_box(st, Vector3(0, 1.84, 0), Vector3(0.45, 0.05, 0.43), Color(look.get("badge", "f2c14e")), 0.0, 0.0, sc)
			_box(st, Vector3(0, 1.8, -0.27), Vector3(0.38, 0.04, 0.16), Color(0.08, 0.08, 0.1), 0.0, 0.0, sc)
		"bandana":
			_box(st, Vector3(0, 1.52, -0.02), Vector3(0.38, 0.14, 0.36), c, 0.0, 0.0, sc)
		"beanie":
			_box(st, Vector3(0, 1.84, 0.01), Vector3(0.4, 0.16, 0.38), c, 0.0, 0.0, sc)
		"shades":
			_box(st, Vector3(0, 1.63, -0.18), Vector3(0.34, 0.07, 0.03), c, 0.0, 0.0, sc)
		"helmet":
			_box(st, Vector3(0, 1.85, 0), Vector3(0.44, 0.2, 0.42), c, 0.0, 0.0, sc)
			_box(st, Vector3(0, 1.62, -0.19), Vector3(0.36, 0.05, 0.03), Color(0.1, 0.1, 0.1), 0.0, 0.0, sc)


static func _weapon(st: SurfaceTool, kind: String, hand_x: float, sc: float) -> void:
	var p := 4.0
	var metal := Color(0.82, 0.85, 0.9)
	var dark := Color(0.12, 0.12, 0.14)
	var wood := Color(0.45, 0.3, 0.17)
	match kind:
		"knife":
			_box(st, Vector3(hand_x, 0.78, -0.06), Vector3(0.05, 0.1, 0.1), dark, p, SHOULDER, sc)
			_box(st, Vector3(hand_x, 0.78, -0.24), Vector3(0.03, 0.06, 0.26), metal, p, SHOULDER, sc)
		"pistol":
			_box(st, Vector3(hand_x, 0.76, -0.12), Vector3(0.07, 0.1, 0.26), dark, p, SHOULDER, sc)
		"revolver":
			_box(st, Vector3(hand_x, 0.76, -0.14), Vector3(0.08, 0.12, 0.32), Color(0.3, 0.3, 0.33), p, SHOULDER, sc)
		"gun":
			_box(st, Vector3(hand_x, 0.76, -0.2), Vector3(0.08, 0.12, 0.5), dark, p, SHOULDER, sc)
		"bat":
			_box(st, Vector3(hand_x, 0.78, -0.3), Vector3(0.08, 0.08, 0.62), wood, p, SHOULDER, sc)
		"club":
			_box(st, Vector3(hand_x, 0.78, -0.32), Vector3(0.14, 0.14, 0.7), Color(0.35, 0.35, 0.38), p, SHOULDER, sc)


## Axis-aligned box. UV carries (part, pivot) for the shader; positions are pre-scaled.
static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color, part: float, pivot: float, sc: float) -> void:
	var h := s * 0.5
	var corners := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	# Corner order is counter-clockwise from outside; triangles are emitted reversed
	# (clockwise), which is Godot's front-face convention.
	var faces := [[0, 3, 2, 1], [5, 6, 7, 4], [4, 7, 3, 0], [1, 2, 6, 5], [3, 7, 6, 2], [4, 0, 1, 5]]
	for f in faces:
		var q: Array = []
		for idx in f:
			q.append((c + corners[idx]) * sc)
		for tri in [[0, 2, 1], [0, 3, 2]]:
			for k in tri:
				st.set_color(col)
				st.set_uv(Vector2(part, pivot * sc))
				st.add_vertex(q[k])


static func _disc(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	var n := 10
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		for v in [c, c + Vector3(cos(a0) * r, 0, sin(a0) * r), c + Vector3(cos(a1) * r, 0, sin(a1) * r)]:
			st.set_color(col)
			st.set_uv(Vector2(-1.0, 0.0))
			st.add_vertex(v)
