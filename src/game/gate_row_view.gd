class_name GateRowView
extends Node3D
## One row of pickups across the road, one per lane.
## - Troop pickups (+N constables, +N inspectors) are drawn as the actual people waiting
##   in the lane (LevelView pushes them into the crowds) with a small "+N" tag over them.
## - Everything else (x2, -8, -40%, ÷2 gang, pistol, bomb) is a compact floating sign.
## A red sign shot past zero turns into a troop group: the negative becomes an advantage.

const GREEN := Color(0.18, 0.78, 0.42)
const RED := Color(0.9, 0.24, 0.27)
const BLUE := Color(0.25, 0.52, 0.95)
const GOLD := Color(0.95, 0.72, 0.2)

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
		pm.size = Vector2(2.9, 2.6)
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
		qm.size = Vector2(2.5, 1.6)
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

		var tag := _label(font, 120, 0.011)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 2.9, 0)
		tag.modulate = Color("7dffb0")
		root.add_child(tag)

		_panels[lane] = {"gate": gate, "root": root, "sign": sign, "mat": mat, "label": label,
			"tag": tag, "pad_mat": pad_mat, "flash": 0.0, "pop": 0.0}
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
	(p["sign"] as Node3D).visible = not troops
	(p["tag"] as Label3D).visible = troops
	(p["tag"] as Label3D).text = info["text"]
	(p["label"] as Label3D).text = info["text"]
	(p["label"] as Label3D).font_size = 150 if String(info["text"]).length() <= 4 else 84
	var c: Color = info["color"]
	(p["mat"] as StandardMaterial3D).albedo_color = Color(c, 0.85)
	(p["pad_mat"] as StandardMaterial3D).albedo_color = Color(c, 0.35)
	if ticked:
		p["flash"] = 1.0
		p["pop"] = 1.0


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
			var c: Color = (info["color"] as Color).lerp(Color.WHITE, float(p["flash"]))
			(p["mat"] as StandardMaterial3D).albedo_color = Color(c, 0.85 + 0.15 * float(p["flash"]))
			var s := Vector3.ONE * (1.0 + 0.3 * float(p["pop"]))
			(p["sign"] as Node3D).scale = s
			(p["tag"] as Label3D).scale = s
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
			return {"text": "GANG ÷%d" % int(g["k"]), "color": BLUE}
		"foe_strip":
			return {"text": "NO ARMOUR", "color": BLUE}
		"weapon":
			return {"text": String(g["id"]).to_upper(), "color": GOLD}
		"power":
			return {"text": "+%d %s" % [int(g.get("n", 1)), String(g["id"]).to_upper()], "color": GOLD}
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
