class_name LiberationPanel
extends RetentionPanel
## After a district boss falls: the district is liberated. Trophy ribbon, the district number
## next to a crown, its 5 buildings (ruined or rebuilt) popping in one by one with a hammer
## badge (liberated = they can be upgraded; the next district's ruins can now be rebuilt),
## star bursts, and one hammer button that closes (main.gd then scrolls the map to the
## district). Icons and numbers only.

var district := 1


func _init(d := 1) -> void:
	district = d


func _ready() -> void:
	var col := _frame(first_icon(["trophy_gold", "trophy"]), 0, "", false)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 16)
	col.add_child(top)
	top.add_child(icon_safe(first_icon(["crown", "boss_crown", "star_icon"]), 120))
	var num_label := UiKit.label(str(district), 120, UiKit.YELLOW, 18)
	top.add_child(num_label)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	var wrap := CenterContainer.new()
	wrap.add_child(grid)
	col.add_child(wrap)
	var ids := City.buildings_in(district, Game.economy)
	var i := 0
	for b in ids:
		var id := String(b.get("id", "")) if b is Dictionary else String(b)
		var tile := _tile(id)
		grid.add_child(tile)
		tile.scale = Vector2.ZERO
		tile.pivot_offset = Vector2(90, 90)
		var tw := tile.create_tween()
		tw.tween_interval(0.35 + 0.18 * i)
		tw.tween_property(tile, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func(): sfx(["build", "tap"], -4.0))
		i += 1
	var go := UiKit.icon_button(first_icon(["hammer", "station"]), "green", 140)
	go.custom_minimum_size.x = 260
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(close)
	col.add_child(go)
	pulse(go, 0.05)
	sfx(["win", "banner"])
	after(0.2, func(): burst(centre(num_label), 18))
	after(0.9, func(): burst(centre(num_label), 12, first_icon(["crown", "star_icon"])))


## One building as it stands (ruin or rebuilt) with a small hammer badge.
func _tile(id: String) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(180, 180)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.full_rect(tr)
	var built := int(Game.building_state(id).get("earning_lv", 0)) >= 1
	var path := "res://assets/city/%s%s.png" % [id, "" if built else "_ruin"]
	tr.texture = load(path) as Texture2D if ResourceLoader.exists(path) else UiKit.icon_texture("star_icon")
	box.add_child(tr)
	var badge := icon_safe(first_icon(["hammer", "station"]), 60)
	badge.position = Vector2(118, 116)
	box.add_child(badge)
	return box
