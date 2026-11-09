class_name GateRowView
extends Node3D
## One row of pickups across the road, one per lane.
## - Troop pickups (+N constables, +N inspectors) are drawn as the actual people waiting
##   in the lane (LevelView pushes them into the crowds) with a small "+N" tag over them.
## - Everything else is a compact floating sign: maths as numbers (x2, -8, -40%), effects as
##   glossy icons (gang split, broken armour, pistol, SMG, bomb, turncoat), never words.
## A red sign shot past zero turns into a troop group: the negative becomes an advantage.
## Recruits show the rank's icon beside "+N" so a sergeant offer reads apart from constables.
## A gate a crashed barricade blocked is boarded up with crossed planks and greys out.

const GREEN := Color(0.18, 0.78, 0.42)
const RED := Color(0.9, 0.24, 0.27)
const BLUE := Color(0.25, 0.52, 0.95)
const GOLD := Color(0.95, 0.72, 0.2)
const GREY := Color(0.42, 0.42, 0.45)

static var _plank_mesh: BoxMesh
static var _plank_mat: StandardMaterial3D

var row: Dictionary
var _panels: Dictionary = {}   # lane -> {gate, root, sign, mat, label, tag, pad_mat, flash, pop}
var _fade := -1.0


func setup(r: Dictionary, font: Font, lane_x: Array) -> GateRowView:
	row = r
	for g in row["gates"]:
		var gate: Dictionary = g
		var lane := int(gate["lane"])
		var root := Node3D.new()
		root.position = Vector3(lane_x[lane], 0, 0)
		add_child(root)

		# Coloured pad on the road marks the lane's offer.
		var pad := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(2.6, 2.6)
		pad.mesh = pm
		pad.position = Vector3(0, 0.03, 0)
		var pad_mat := StandardMaterial3D.new()
		pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pad.material_override = pad_mat
		root.add_child(pad)

		var sign := Node3D.new()
		sign.position = Vector3(0, 1.7, 0)
		root.add_child(sign)
		var panel := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(2.3, 1.5)
		panel.mesh = qm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		panel.material_override = mat
		sign.add_child(panel)
		var label := _label(font, 150, 0.011)
		label.position = Vector3(0, 0, 0.05)
		sign.add_child(label)
		var icon := Sprite3D.new()
		icon.pixel_size = 1.25 / 320.0
		icon.shaded = false
		icon.render_priority = 3
		icon.position = Vector3(0, 0, 0.06)
		sign.add_child(icon)

		var tag := _label(font, 120, 0.011)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 2.9, 0)
		tag.modulate = Color("7dffb0")
		root.add_child(tag)
		var tag_icon := Sprite3D.new()
		tag_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag_icon.shaded = false
		tag_icon.render_priority = 3
		tag_icon.pixel_size = 0.85 / 320.0
		tag_icon.position = Vector3(-0.62, 2.9, 0)
		tag_icon.visible = false
		root.add_child(tag_icon)

		_panels[lane] = {"gate": gate, "root": root, "sign": sign, "mat": mat, "label": label,
			"icon": icon, "tag": tag, "tag_icon": tag_icon, "pad_mat": pad_mat, "flash": 0.0, "pop": 0.0,
			"boards": null}
		refresh(gate)
	return self


## True when this pickup is shown as people waiting to join.
static func is_troops(g: Dictionary) -> bool:
	return (g["op"] == "num" and int(g["v"]) > 0) or g["op"] == "recruit"


static func troop_kind(g: Dictionary) -> String:
	return String(g["unit"]) if g["op"] == "recruit" else "constable"


static func troop_count(g: Dictionary) -> int:
	return int(g.get("n", 1)) if g["op"] == "recruit" else int(g["v"])


func refresh(gate: Dictionary, ticked := false) -> void:
	var p: Dictionary = _panels.get(int(gate["lane"]), {})
	if p.is_empty():
		return
	var info := describe(gate)
	var troops := is_troops(gate)
	var blocked := is_blocked(gate)
	(p["sign"] as Node3D).visible = not troops or blocked
	(p["tag"] as Label3D).visible = troops and not blocked
	(p["tag"] as Label3D).text = info["text"]
	var tag_icon: Sprite3D = p["tag_icon"]
	tag_icon.visible = troops and not blocked and gate["op"] == "recruit"
	if tag_icon.visible:
		tag_icon.texture = UiKit.icon_texture(String(gate["unit"]))
	(p["tag"] as Label3D).position.x = 0.38 if tag_icon.visible else 0.0
	if blocked:
		_board_up(p)
	var label: Label3D = p["label"]
	var icon: Sprite3D = p["icon"]
	label.text = info["text"]
	var chars := String(info["text"]).length()
	# Fit the lane: long numbers ("+40%", "-120") shrink so neighbours never touch.
	label.font_size = 150 if chars <= 2 else (130 if chars == 3 else (108 if chars == 4 else 84))
	var icon_name := String(info.get("icon", ""))
	icon.visible = icon_name != ""
	if icon.visible:
		icon.texture = UiKit.icon_texture(icon_name)
		# Icon alone sits in the middle; with a number they share the sign.
		var solo := String(info["text"]) == ""
		icon.position.x = 0.0 if solo else -0.6
		icon.pixel_size = (1.35 if solo else 1.05) / 320.0
		label.position.x = 0.0 if solo else 0.55
		label.font_size = 130 if chars <= 2 else 100
	else:
		label.position.x = 0.0
	var c: Color = GREY if blocked else info["color"]
	(p["mat"] as StandardMaterial3D).albedo_color = Color(c, 0.85)
	(p["pad_mat"] as StandardMaterial3D).albedo_color = Color(c, 0.35)
	if ticked:
		p["flash"] = 1.0
		p["pop"] = 1.0


## Crossed planks nailed over a blocked gate (mesh and material shared by every row).
func _board_up(p: Dictionary) -> void:
	if p["boards"] != null:
		return
	if _plank_mesh == null:
		_plank_mesh = BoxMesh.new()
		_plank_mesh.size = Vector3(2.7, 0.32, 0.12)
		_plank_mat = StandardMaterial3D.new()
		_plank_mat.albedo_color = Color("8a5a2e")
		_plank_mat.roughness = 1.0
	var boards := Node3D.new()
	boards.position = Vector3(0, 1.7, 0.25)
	for a in [0.5, -0.5]:
		var mi := MeshInstance3D.new()
		mi.mesh = _plank_mesh
		mi.material_override = _plank_mat
		mi.rotation.z = a
		boards.add_child(mi)
	(p["root"] as Node3D).add_child(boards)
	p["boards"] = boards


## True when a crashed barricade boarded this gate up (nothing to pick up any more).
static func is_blocked(g: Dictionary) -> bool:
	return bool(g.get("blocked", false))


func lane_root(lane: int) -> Node3D:
	return _panels[lane]["root"] if _panels.has(lane) else null


## Picked pickup vanishes (its people run into the squad), the rest shrink away.
func passed(picked_lane: int) -> void:
	_fade = 0.0
	for lane in _panels:
		if lane == picked_lane:
			(_panels[lane]["root"] as Node3D).visible = false


func _process(delta: float) -> void:
	for lane in _panels:
		var p: Dictionary = _panels[lane]
		if float(p["flash"]) > 0.0 or float(p["pop"]) > 0.0:
			p["flash"] = maxf(float(p["flash"]) - delta * 6.0, 0.0)
			p["pop"] = maxf(float(p["pop"]) - delta * 5.0, 0.0)
			var info := describe(p["gate"])
			var base: Color = GREY if is_blocked(p["gate"]) else info["color"]
			var c: Color = base.lerp(Color.WHITE, float(p["flash"]))
			(p["mat"] as StandardMaterial3D).albedo_color = Color(c, 0.85 + 0.15 * float(p["flash"]))
			var s := Vector3.ONE * (1.0 + 0.3 * float(p["pop"]))
			(p["sign"] as Node3D).scale = s
			(p["tag"] as Label3D).scale = s
			(p["tag_icon"] as Sprite3D).scale = s
	if _fade >= 0.0:
		_fade += delta
		for lane in _panels:
			var root: Node3D = _panels[lane]["root"]
			root.scale = Vector3.ONE * maxf(1.0 - _fade * 3.0, 0.01)
		if _fade > 0.4:
			queue_free()


static func describe(g: Dictionary) -> Dictionary:
	match String(g["op"]):
		"num":
			var v := int(g["v"])
			return {"text": ("+%d" % v) if v >= 0 else ("-%d" % -v), "color": GREEN if v > 0 else RED}
		"recruit":
			return {"text": "+%d" % int(g.get("n", 1)), "color": GREEN}
		"mul":
			return {"text": "×%d" % int(g["k"]), "color": GREEN}
		"div":
			return {"text": "÷%d" % int(g["k"]), "color": RED}
		"pct":
			var v := int(g["v"])
			return {"text": ("+%d%%" % v) if v >= 0 else ("-%d%%" % -v), "color": GREEN if v >= 0 else RED}
		"foe_div":
			return {"text": "÷%d" % int(g["k"]), "icon": "gang_split", "color": BLUE}
		"foe_strip":
			return {"text": "", "icon": "armour_break", "color": BLUE}
		"turncoat":
			return {"text": "%d" % int(g.get("n", 1)), "icon": "turncoat", "color": BLUE}
		"weapon":
			return {"text": "", "icon": String(g["id"]), "color": GOLD}
		"power":
			return {"text": "+%d" % int(g.get("n", 1)), "icon": String(g["id"]), "color": GOLD}
	return {"text": "?", "color": Color.GRAY}


static func _label(font: Font, size: int, px: float) -> Label3D:
	var l := Label3D.new()
	l.font = font
	l.font_size = size
	l.pixel_size = px
	l.outline_size = int(size * 0.18)
	l.outline_modulate = Color(0.05, 0.05, 0.08)
	l.modulate = Color.WHITE
	l.render_priority = 2
	l.outline_render_priority = 1
	return l
