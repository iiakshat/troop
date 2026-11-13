class_name SettingsPanel
extends Control
## Sound (speaker), music (note) and vibration toggles (icons; each has an "off" look) plus the credits that CC-BY assets require
## (every CC BY row in ASSETS.md: game-icons.net icons and the app icon, Vincent Sevedge's
## gunshots).

const CREDITS := """3D characters: Quaternius (CC0)
City, cars, food, UI: Kenney (CC0)
Street props: Kay Lousberg / KayKit (CC0)
Icons: game-icons.net by Lorc, Delapouite, Skoll,
Sbed, Andy Meneely, Guard13007 (CC BY 3.0)
Sounds: Kenney, rubberduck, qubodup and OpenGameArt artists (CC0)
Glass: Gravity Sound (CC BY 4.0), spookymodem (CC BY 3.0)
Gunshots: Vincent Sevedge (CC BY 3.0)
Music: made with Google Lyria
Painted art: made with Google Gemini
Fonts: Luckiest Guy (Apache 2.0), Lilita One (OFL)
Ads: Godot AdMob plugin by Cengiz and the Godot SDK
Integrations community (MIT), Google Mobile Ads SDK
Analytics: Godotx Firebase by Paulo Coutinho (MIT),
Google Firebase"""


const PRIVACY_URL := "https://github.com/iiakshat/troop/blob/main/docs/PRIVACY.md"   # public without a Pages build (Actions is billing-locked); docs/privacy/index.html once Pages works

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
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	row.add_child(toggle_button("sound", "sound", "sound_off", 124))
	row.add_child(toggle_button("music", "music", "music_off", 124))
	row.add_child(toggle_button("vibration", "vibrate", "vibrate_off", 124))
	# The privacy policy (Play asks for it in the app as well as on the store page).
	var privacy := UiKit.icon_button("privacy", "blue", 124)
	privacy.pressed.connect(func(): OS.shell_open(PRIVACY_URL))
	row.add_child(privacy)
	# Credits scroll inside the panel, so the panel always fits the screen.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	UiKit.touch_scroll(scroll)
	var credits := UiKit.label(CREDITS, 24, UiKit.INK, 0, true)
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits.custom_minimum_size = Vector2(560, 0)
	scroll.add_child(credits)
	UiKit.pop(p, 0.7)


## A sound / music / vibration toggle (also used by the in-level pause panel).
static func toggle_button(key: String, on_icon: String, off_icon: String, px := 150) -> Button:
	var b := UiKit.icon_button(on_icon, "green", px)
	_paint(b, bool(Game.save.get(key, true)), on_icon, off_icon)
	b.pressed.connect(func():
		var now := Game.toggle(key)
		_paint(b, now, on_icon, off_icon)
		if key == "music":
			Sfx.music_changed()
		elif key == "sound":
			Sfx.sound_changed()
		if now:
			Sfx.play("tap")
		UiKit.bump(b, 1.08))
	b.set_meta("key", key)
	return b


## On = green button with the icon; off = grey button with the "off" icon (slashed).
static func _paint(b: Button, on: bool, on_icon: String, off_icon: String) -> void:
	var ic: TextureRect = b.get_meta("icon")
	ic.texture = UiKit.icon_texture(on_icon if on else off_icon)
	# Off: the glossy icons carry their own slash; a plain glyph turns dark so it reads as off.
	ic.modulate = Color.WHITE if on or UiKit.is_gloss(off_icon) else Color(0.25, 0.25, 0.3, 1.0)
	var colr := "green" if on else "grey"
	for st in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(st, UiKit._tex_box(colr, "square"))
	b.add_theme_stylebox_override("pressed", UiKit._tex_box(colr, "square", true))
