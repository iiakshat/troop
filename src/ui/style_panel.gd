class_name StylePanel
extends Control
## Cosmetics: hero outfits (shirt icon in the outfit's colour, with the outfit's head
## accessory as a badge: cap, hood, shades or crown, which the hero wears in the level) and
## knife skins (knife icon in the blade colour). Tap to buy (coin + price) or equip (tick).
## Looks only, never power.

var _items: Array = []   # {kind, id, button, price_label, accessory}

## Badge icon of each outfit accessory (HeroAccessory.KINDS).
const ACCESSORY_ICONS := {"cap": "cap", "hood": "hood", "shades": "sunglasses", "crown": "crown"}


func _ready() -> void:
	UiKit.full_rect(self)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	UiKit.full_rect(dim)
	add_child(dim)
	var p := UiKit.panel()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.offset_left = -330
	p.offset_right = 330
	p.offset_top = -470
	p.offset_bottom = 470
	add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	p.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var rib := UiKit.ribbon("shirt")
	rib.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(rib)
	var close := UiKit.icon_button("close", "red", 96)
	close.pressed.connect(queue_free)
	head.add_child(close)
	for kind in ["outfits", "knives"]:
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 14)
		col.add_child(grid)
		for c in Game.economy["cosmetics"][kind]:
			grid.add_child(_item(kind, c))
	refresh()
	UiKit.pop(p, 0.7)


func _item(kind: String, c: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var tint := Color(String(c["shirt"] if kind == "outfits" else c["blade"]))
	var b := UiKit.icon_button("shirt" if kind == "outfits" else "knife", "blue", 180)
	(b.get_meta("icon") as TextureRect).modulate = tint
	b.pressed.connect(func(): _pick(kind, String(c["id"])))
	box.add_child(b)
	var acc: Control = null
	var acc_kind := String(c.get("accessory", ""))
	if kind == "outfits" and ACCESSORY_ICONS.has(acc_kind):
		var name := String(ACCESSORY_ICONS[acc_kind])
		acc = UiKit.icon(name, 78, Color(String(c.get("accessory_color", "ffffff"))))
		if not UiKit.is_gloss(name) and Color(String(c.get("accessory_color", "ffffff"))).get_luminance() < 0.2:
			acc.modulate = Color("e8ecf2")   # a black glyph would vanish on the button
		acc.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		acc.offset_left = -84
		acc.offset_right = -6
		acc.offset_top = 6
		acc.offset_bottom = 84
		b.add_child(acc)
	var price := UiKit.label("", 34, UiKit.YELLOW, 8)
	box.add_child(price)
	_items.append({"kind": kind, "id": String(c["id"]), "button": b, "price": price, "cost": int(c["price"]), "accessory": acc})
	return box


func _pick(kind: String, id: String) -> void:
	if Game.pick_cosmetic(kind, id):
		Sfx.play("upgrade")
		refresh()
	else:
		Sfx.play("error")


func refresh() -> void:
	for it in _items:
		var equipped := String(Game.save["outfit" if it["kind"] == "outfits" else "knife"]) == String(it["id"])
		var b: Button = it["button"]
		var colr := "green" if equipped else ("blue" if Game.owns(it["id"]) else "grey")
		b.add_theme_stylebox_override("normal", UiKit._tex_box(colr, "square"))
		b.add_theme_stylebox_override("hover", UiKit._tex_box(colr, "square"))
		var price: Label = it["price"]
		price.text = "" if Game.owns(it["id"]) else str(it["cost"])


## For tests: the outfit card shows its accessory badge.
func accessory_icon_visible(id: String) -> bool:
	for it in _items:
		if String(it["id"]) == id:
			return it["accessory"] != null and (it["accessory"] as Control).visible
	return false
