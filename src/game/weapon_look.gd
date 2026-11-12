class_name WeaponLook
extends RefCounted
## The Armory tier made visible (spec v2 section 6, "In the level"): the same low-poly weapons,
## recoloured per tier so performance stays light. Squad weapons are baked into the VAT crowds
## as rigid boxes with fixed vertex colours (tools/bake_vat.gd _weapon_on), so a tier swaps
## those colours on the owner's crowd (Crowd.recolor) once at level start. Bottle Shot view
## models (WeaponModels) get the same tier colours on their metal parts and a trim tint.
## Tier 1 keeps the bake's look; 2 = blued steel, 3 = chrome and gold, 4 = gold and navy.

## The bake's weapon colours (tools/bake_vat.gd): dark body, metal blade, wood, revolver grey,
## sniper scope and stock, launcher olive.
const DARK := Color(0.12, 0.12, 0.14)
const METAL := Color(0.82, 0.85, 0.9)
const WOOD := Color(0.5, 0.33, 0.18)
const REVOLVER := Color(0.35, 0.35, 0.38)
const SCOPE := Color(0.05, 0.05, 0.06)
const STOCK := Color(0.25, 0.27, 0.22)
const OLIVE := Color(0.33, 0.38, 0.22)

## Per tier (index 0 = tier 1): main body colour and trim colour.
const BODY := [Color(), Color(0.2, 0.34, 0.68), Color(0.8, 0.82, 0.88), Color(0.96, 0.76, 0.22)]
const TRIM := [Color(), Color(0.55, 0.75, 1.0), Color(0.9, 0.68, 0.2), Color(0.12, 0.18, 0.42)]
const BLADE := [Color(), Color(0.6, 0.8, 1.0), Color(0.95, 0.82, 0.4), Color(1.0, 0.92, 0.6)]


## Colour swaps for a weapon owner's crowd at `tier` ({} at tier 1).
static func crowd_map(owner: String, tier: int) -> Dictionary:
	if tier <= 1:
		return {}
	var t := clampi(tier, 1, BODY.size()) - 1
	match owner:
		"hero":
			return {METAL: BLADE[t], DARK: TRIM[t]}
		"sergeant":
			return {DARK: BODY[t], WOOD: TRIM[t]}
		"inspector":
			return {REVOLVER: BODY[t]}
		"sniper":
			return {DARK: BODY[t], SCOPE: TRIM[t], STOCK: TRIM[t]}
		"commando":
			return {OLIVE: BODY[t], DARK: TRIM[t]}
		_:
			return {DARK: BODY[t]}


## Recolours every squad crowd whose weapon track is past tier 1 (LevelView, at level start).
static func apply_to_crowds(crowds: Dictionary, save: Dictionary) -> void:
	for id in Armory.ids():
		if Armory.is_finale(String(id)):
			continue
		var owner := String(Armory.track(String(id)).get("owner", ""))
		var map := crowd_map(owner, Armory.level(save, String(id)).x)
		if not map.is_empty() and crowds.get(owner) is Crowd:
			(crowds[owner] as Crowd).recolor(map)


## Tints a Bottle Shot view model (WeaponModels.pistol / rifle / bow / star) for the tier of
## its Armory track: metal parts take the tier's body colour, the rest a light trim tint.
static func tint_view_model(root: Node3D, track_id: String) -> Node3D:
	var save := _save()
	if root == null or save.is_empty() or Armory.track(track_id).is_empty():
		return root
	var tier := Armory.level(save, track_id).x
	if tier <= 1:
		return root
	var t := clampi(tier, 1, BODY.size()) - 1
	var hands := [WeaponModels.skin().albedo_color, WeaponModels.sleeve().albedo_color, WeaponModels.glove().albedo_color]
	_tint(root, BODY[t], TRIM[t], hands)
	return root


static func _tint(n: Node, body: Color, trim: Color, hands: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var m := mi.material_override as StandardMaterial3D
		if m != null and m.albedo_color.a > 0.99 and not hands.has(m.albedo_color):
			var nm := m.duplicate() as StandardMaterial3D
			if m.metallic >= 0.5:
				nm.albedo_color = body
			else:
				nm.albedo_color = m.albedo_color.lerp(trim, 0.35)
			mi.material_override = nm
	for c in n.get_children():
		_tint(c, body, trim, hands)


static func _save() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node_or_null("Game") if tree else null
	if game == null:
		return {}
	var s: Variant = game.get("save")
	return s if s is Dictionary else {}
