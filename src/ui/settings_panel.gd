class_name SettingsPanel
extends Control
## Sound, music and vibration toggles (icons) plus the credits that CC-BY assets require.

const CREDITS := """3D characters: Quaternius (CC0)
City, cars, food, UI: Kenney (CC0)
Street props: Kay Lousberg / KayKit (CC0)
Icons: game-icons.net by Lorc, Delapouite, Skoll,
Sbed, Andy Meneely, Guard13007 (CC BY 3.0)
Sounds: Kenney, rubberduck (CC0)
Gunshots: Vincent Sevedge (CC BY 3.0)
Music: XCVG (CC0)
Fonts: Luckiest Guy (Apache 2.0), Lilita One (OFL)"""


func _ready() -> void:
	UiKit.full_rect(self)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	UiKit.full_rect(dim)
	add_child(dim)
	var p := UiKit.panel()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.offset_left = -320
	p.offset_right = 320
	p.offset_top = -420
	p.offset_bottom = 420
	add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	p.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var rib := UiKit.ribbon("settings")
	rib.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(rib)
	var close := UiKit.icon_button("close", "red", 96)
	close.pressed.connect(queue_free)
	head.add_child(close)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	col.add_child(row)
	row.add_child(_toggle("sound", "sound", "sound_off"))
	row.add_child(_toggle("music", "sound", "sound_off", Color("ffd23f")))
	row.add_child(_toggle("vibration", "vibrate", "vibrate"))
	var credits := UiKit.label(CREDITS, 26, UiKit.INK, 0, true)
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits.custom_minimum_size = Vector2(560, 0)
	col.add_child(credits)
	UiKit.pop(p, 0.7)


func _toggle(key: String, on_icon: String, off_icon: String, tint := Color.WHITE) -> Button:
	var on := bool(Game.save.get(key, true))
	var b := UiKit.icon_button(on_icon if on else off_icon, "green" if on else "grey", 150)
	(b.get_meta("icon") as TextureRect).modulate = tint
	b.pressed.connect(func():
		var now := Game.toggle(key)
		var ic: TextureRect = b.get_meta("icon")
		ic.texture = UiKit.icon_texture(on_icon if now else off_icon)
		b.add_theme_stylebox_override("normal", UiKit._tex_box("green" if now else "grey", "square"))
		b.add_theme_stylebox_override("hover", UiKit._tex_box("green" if now else "grey", "square"))
		if key == "music":
			Sfx.music_changed())
	return b
