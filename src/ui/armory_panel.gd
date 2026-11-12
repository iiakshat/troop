class_name ArmoryPanel
extends Control
## The Armory (spec v2 section 6): one card per weapon track (config/armory.json order), the
## squad's weapons first, then the Bottle Shot weapons under a bottle header. Each card: the
## tier's art, its name and calibre, stat bars with the real in-game numbers before ▸ after the
## next buy, the 5-pip step bar, the tier diamonds and the price. The buy that fills the bar
## evolves the weapon: the evolve celebration flashes, swaps in the new tier's art with sparks
## and pops the new name. A locked card is greyed with a lock and level pin + unlock level.
## Squad Power pill counts up after a buy (weapons add power; Bottle Shot handling does not).
## Frees itself on close and emits `closed`. focus_id (set before adding) scrolls to and
## flashes that card (the loss tip). Icons and numbers only; weapon names and calibres are
## the spec's exception.

signal closed

var focus_id := ""

var _cards: Dictionary = {}     # id -> {card, art, name, calibre, stats: [...], pips, tiers, buy, lock, lock_label, lock_row}
var _coins: HBoxContainer
var _power: HBoxContainer
var _scroll: ScrollContainer

const ART_DIR := "res://assets/armory/"
## Fallback icons when a tier has no art file.
const FALLBACK := {
	"knives": "knife", "service_pistol": "pistol", "shotgun": "weapon_shotgun", "revolver": "weapon_revolver",
	"rifle": "smg", "sniper_rifle": "sniper", "launcher": "weapon_launcher", "finale_pistol": "pistol",
	"finale_bow": "aim", "finale_stars": "star_icon", "finale_sniper": "sniper",
}
## Stat rows: icon, and whether a smaller number is better. Squad weapons show dmg and rate;
## Bottle Shot weapons their handling keys from finale.json (key without _add / _mult).
const STATS := {
	"dmg": ["fist", false], "rate": ["fire_rate", false], "mag": ["pistol", false],
	"reload_s": ["clock", true], "draw_s": ["clock", true], "cycle_s": ["clock", true],
	"kick_deg": ["aim", true], "shake_deg": ["aim", true], "sway_deg": ["aim", true],
	"steady_s": ["shield", false], "swipe_fast": ["swipe", true], "ricochet_len": ["broken_bottle", false],
}
const TIER_TINT := [Color("8a94a6"), Color("4f8de0"), Color("f2b73a"), Color("ffd75a")]
const BAR_W := 104.0


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	UiKit.full_rect(dim)
	add_child(dim)
	var p := UiKit.panel()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.offset_left = -340
	p.offset_right = 340
	p.offset_top = -600
	p.offset_bottom = 600
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	p.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var rib := UiKit.ribbon("pistol")
	rib.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(rib)
	var close := UiKit.icon_button("close", "red", 96)
	close.pressed.connect(_close)
	head.add_child(close)
	var pills := HBoxContainer.new()
	pills.alignment = BoxContainer.ALIGNMENT_CENTER
	pills.add_theme_constant_override("separation", 18)
	col.add_child(pills)
	_power = UiKit.pill("power", str(Game.squad_power()), Color.WHITE)
	pills.add_child(_power)
	_coins = UiKit.pill("coin", str(int(Game.save["coins"])))
	pills.add_child(_coins)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	_scroll.add_child(list)
	var finale_head := false
	for id in Armory.ids():
		if Armory.is_finale(String(id)) and not finale_head:
			finale_head = true
			list.add_child(_section("bottle"))
		list.add_child(_card(String(id)))
	refresh()
	UiKit.pop(p, 0.7)
	if _cards.has(focus_id):
		_focus.call_deferred(focus_id)


func _section(icon_name: String) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var line_l := ColorRect.new()
	line_l.color = Color(UiKit.INK, 0.35)
	line_l.custom_minimum_size = Vector2(200, 5)
	line_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line_l)
	row.add_child(RetentionPanel.icon_safe(icon_name, 64))
	var line_r := line_l.duplicate() as ColorRect
	row.add_child(line_r)
	return row


func _card(id: String) -> Control:
	var card := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)

	# Art with the tier diamonds under it; a locked card covers it with a lock.
	var art_box := Control.new()
	art_box.custom_minimum_size = Vector2(130, 150)
	art_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(art_box)
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size = Vector2(126, 126)
	art.position = Vector2(2, 2)
	art.pivot_offset = art.size * 0.5
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_box.add_child(art)
	var tiers := HBoxContainer.new()
	tiers.alignment = BoxContainer.ALIGNMENT_CENTER
	tiers.add_theme_constant_override("separation", 6)
	tiers.position = Vector2(0, 128)
	tiers.size = Vector2(130, 22)
	tiers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_box.add_child(tiers)
	for t in Armory.tier_count(id):
		var d := Panel.new()
		d.custom_minimum_size = Vector2(18, 18)
		d.rotation = PI / 4.0
		d.pivot_offset = Vector2(9, 9)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tiers.add_child(d)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 4)
	row.add_child(mid)
	var nm := UiKit.label("", 32, Color.WHITE, 9)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mid.add_child(nm)
	var cal := UiKit.label("", 24, UiKit.YELLOW, 7)
	cal.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mid.add_child(cal)
	var stats: Array = []
	for key in stat_keys(id):
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 6)
		mid.add_child(srow)
		srow.add_child(RetentionPanel.icon_safe(String(STATS.get(key, ["star_icon"])[0]), 34))
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(BAR_W, 20)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := Panel.new()
		bg.size = Vector2(BAR_W, 20)
		bg.add_theme_stylebox_override("panel", UiKit.flat_box(Color(0, 0, 0, 0.4), 8, 3))
		bar.add_child(bg)
		var ghost := Panel.new()
		ghost.size = Vector2(0, 20)
		ghost.add_theme_stylebox_override("panel", UiKit.flat_box(Color(UiKit.YELLOW, 0.75), 8, 3))
		bar.add_child(ghost)
		var fill := Panel.new()
		fill.size = Vector2(0, 20)
		fill.add_theme_stylebox_override("panel", UiKit.flat_box(UiKit.GREEN, 8, 3))
		bar.add_child(fill)
		srow.add_child(bar)
		var txt := UiKit.label("", 24, Color.WHITE, 7)
		srow.add_child(txt)
		var arrow := RetentionPanel.icon_safe("play", 20, UiKit.YELLOW)
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		srow.add_child(arrow)
		var nxt := UiKit.label("", 24, UiKit.YELLOW, 7)
		srow.add_child(nxt)
		stats.append({"key": key, "fill": fill, "ghost": ghost, "text": txt, "arrow": arrow, "next": nxt})
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 6)
	mid.add_child(pips)
	for i in Armory.steps_per_tier(id):
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(34, 16)
		pips.add_child(pip)

	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(right)
	var buy := UiKit.button("", "green", 34, Vector2(136, 92))
	buy.pressed.connect(func(): buy(id))
	right.add_child(buy)
	var gain_row := HBoxContainer.new()
	gain_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gain_row.add_theme_constant_override("separation", 4)
	gain_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gain_row.add_child(RetentionPanel.icon_safe("power", 30))
	var gain := UiKit.label("", 26, UiKit.YELLOW, 7)
	gain_row.add_child(gain)
	right.add_child(gain_row)

	# Lock overlay: dark cover over the art, the lock, then a level pin and the unlock level.
	var lock := Control.new()
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.size = Vector2(130, 150)
	art_box.add_child(lock)
	var lock_ic := RetentionPanel.icon_safe("lock", 84)
	lock_ic.position = Vector2(23, 8)
	lock_ic.size = Vector2(84, 84)
	lock.add_child(lock_ic)
	var lock_row := HBoxContainer.new()
	lock_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lock_row.add_theme_constant_override("separation", 2)
	lock_row.position = Vector2(0, 88)
	lock_row.size = Vector2(130, 50)
	lock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock_row.add_child(RetentionPanel.icon_safe("play", 26, UiKit.YELLOW))
	lock_row.add_child(RetentionPanel.icon_safe("map_pin", 44))
	var lock_label := UiKit.label("", 40, Color.WHITE, 9)
	lock_row.add_child(lock_label)
	lock.add_child(lock_row)

	_cards[id] = {"card": card, "art": art, "name": nm, "calibre": cal, "stats": stats, "pips": pips,
		"tiers": tiers, "buy": buy, "gain": gain, "gain_row": gain_row, "lock": lock, "lock_ic": lock_ic,
		"lock_label": lock_label, "art_path": ""}
	return card


## Stat rows a track shows: dmg and rate for squad weapons, else its handling keys (up to 3).
static func stat_keys(id: String) -> Array:
	if not Armory.is_finale(id):
		return ["dmg", "rate"]
	var out := []
	for k in Armory.tier_info(id, Armory.tier_count(id)).get("extra", {}):
		var key := String(k).trim_suffix("_add").trim_suffix("_mult")
		if not out.has(key):
			out.append(key)
	return out.slice(0, 3)


## The real number of `key` for track `id` with stats `s` (Armory.stats_at): the owner's dmg /
## rate per troop (units.json x the multipliers), or the Bottle Shot weapon's handling value
## (finale.json base, plus _add or times _mult).
static func stat_value(id: String, key: String, s: Dictionary) -> float:
	var owner := String(Armory.track(id).get("owner", ""))
	if key == "dmg" or key == "rate":
		var u: Dictionary = Config.units()["allies"].get(owner, {})
		return float(u.get(key, 1.0)) * float(s.get(key + "_mult", 1.0))
	var w: Dictionary = _finale_cfg().get("weapons", {}).get(owner.trim_prefix("finale_"), {})
	var base := float(w.get(key, 0.0))
	var x: Dictionary = s.get("extra", {})
	if x.has(key + "_add"):
		return base + float(x[key + "_add"])
	if x.has(key + "_mult"):
		return base * float(x[key + "_mult"])
	return base


static var _finale: Dictionary = {}


static func _finale_cfg() -> Dictionary:
	if _finale.is_empty():
		_finale = Config.load_json("res://config/finale.json")
	return _finale


static func fmt(v: float) -> String:
	if absf(v - roundf(v)) < 0.005:
		return str(int(roundf(v)))
	if absf(v) >= 10.0:
		return "%.1f" % v
	return "%.2f" % v


## 0..1: how far a stat is from tier 1 step 0 towards the maxed track.
static func stat_fill(id: String, key: String, s: Dictionary) -> float:
	var lo := stat_value(id, key, Armory.stats_at(id, 1, 0))
	var top := Armory.at_index(id, Armory.total_buys(id))
	var hi := stat_value(id, key, Armory.stats_at(id, top.x, top.y))
	var v := stat_value(id, key, s)
	if is_equal_approx(hi, lo):
		return 1.0
	return clampf(0.15 + 0.85 * (v - lo) / (hi - lo), 0.0, 1.0)


static func art_path_for(id: String, tier: int) -> String:
	var a := String(Armory.tier_info(id, tier).get("art", ""))
	return ART_DIR + a.trim_prefix("armory/") + ".png" if a != "" else ""


## The art of a track's current tier (save) as an icon-sized TextureRect.
static func art_icon(id: String, size := 84) -> TextureRect:
	var t := TextureRect.new()
	var path := art_path_for(id, Armory.level(Game.save, id).x)
	t.texture = load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else UiKit.icon_texture(String(FALLBACK.get(id, "star_icon")))
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## A track's headline number after `i` purchases: a squad weapon's dps per troop as a percent of
## tier 1 (100%, 106%...), a Bottle Shot weapon's first handling value.
static func index_text(id: String, i: int) -> String:
	if Armory.track(id).is_empty():
		return str(i)
	var l := Armory.at_index(id, i)
	var s := Armory.stats_at(id, l.x, l.y)
	if not Armory.is_finale(id):
		return "%d%%" % int(round(float(s["dmg_mult"]) * float(s["rate_mult"]) * 100.0))
	return fmt(stat_value(id, String(stat_keys(id)[0]), s))


func _set_art(id: String, tier: int) -> void:
	var c: Dictionary = _cards[id]
	var path := art_path_for(id, tier)
	var tex: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		tex = UiKit.icon_texture(String(FALLBACK.get(id, "star_icon")))
		path = ""
	(c["art"] as TextureRect).texture = tex
	c["art_path"] = path


func refresh() -> void:
	UiKit.pill_set(_coins, str(int(Game.save["coins"])))
	var coins := int(Game.save["coins"])
	for id in _cards:
		var c: Dictionary = _cards[id]
		var l: Vector2i = Game.weapon_level(id)
		var locked: bool = Game.weapon_locked(id)
		var info := Armory.tier_info(id, l.x)
		_set_art(id, l.x)
		(c["name"] as Label).text = String(info.get("name", ""))
		(c["calibre"] as Label).text = String(info.get("calibre", ""))
		var s := Armory.stats(Game.save, id)
		var nx := Armory.next_stats(Game.save, id)
		for st in c["stats"]:
			var key := String(st["key"])
			var f := stat_fill(id, key, s) * BAR_W
			(st["fill"] as Control).size.x = f
			var g := f if nx.is_empty() else stat_fill(id, key, nx) * BAR_W
			(st["ghost"] as Control).size.x = g
			(st["text"] as Label).text = fmt(stat_value(id, key, s))
			(st["next"] as Label).text = "" if nx.is_empty() else fmt(stat_value(id, key, nx))
			(st["arrow"] as Control).visible = not nx.is_empty()
		var maxed := Armory.is_maxed(Game.save, id)
		var per := Armory.steps_per_tier(id)
		var pips: HBoxContainer = c["pips"]
		var filled := l.y
		for i in pips.get_child_count():
			var sb := StyleBoxFlat.new()
			sb.bg_color = UiKit.YELLOW if i < filled else Color(0, 0, 0, 0.35)
			sb.set_corner_radius_all(7)
			sb.set_border_width_all(3)
			sb.border_color = UiKit.INK
			(pips.get_child(i) as Panel).add_theme_stylebox_override("panel", sb)
		var tiers: HBoxContainer = c["tiers"]
		for t in tiers.get_child_count():
			var sb2 := StyleBoxFlat.new()
			sb2.bg_color = TIER_TINT[mini(t, TIER_TINT.size() - 1)] if t < l.x else Color(0, 0, 0, 0.35)
			sb2.set_corner_radius_all(3)
			sb2.set_border_width_all(3)
			sb2.border_color = UiKit.INK
			(tiers.get_child(t) as Panel).add_theme_stylebox_override("panel", sb2)
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color("6b7280") if locked else (Color("2e8b3e") if maxed else Color("3b6fd1"))
		cs.set_corner_radius_all(22)
		cs.set_border_width_all(5)
		cs.border_color = UiKit.INK
		cs.content_margin_left = 10
		cs.content_margin_right = 10
		cs.content_margin_top = 8
		cs.content_margin_bottom = 8
		(c["card"] as PanelContainer).add_theme_stylebox_override("panel", cs)
		(c["lock"] as Control).visible = locked
		(c["lock_label"] as Label).text = str(Armory.unlock_level(id))
		(c["art"] as Control).modulate = Color(0.25, 0.25, 0.3, 0.9) if locked else Color.WHITE
		var buy: Button = c["buy"]
		var cost: int = Game.weapon_cost(id)
		var gain: int = 0 if maxed or locked else Game.weapon_power_gain(id)
		(c["gain"] as Label).text = "+%d" % gain
		(c["gain_row"] as Control).modulate.a = 1.0 if gain > 0 else 0.0
		if maxed:
			buy.disabled = true
			UiKit.button_row(buy, ["star_icon"], "", 34)
		elif locked:
			buy.disabled = true
			UiKit.button_row(buy, ["lock"], "", 34)
		else:
			buy.disabled = coins < cost
			# The buy that fills the bar evolves the weapon: the upgrade arrow joins the price.
			var icons := ["upgrade", "coin"] if l.y == per - 1 and l.x < Armory.tier_count(id) else ["coin"]
			UiKit.button_row(buy, icons, UiKit.fmt_coins(cost), 34)


## Buys the next step of track `id`; an evolution plays the new-art reveal.
func buy(id: String) -> void:
	if not _cards.has(id):
		return
	var before: int = Game.squad_power()
	var r: Dictionary = Game.buy_weapon(id)
	if not bool(r.get("ok", false)):
		Sfx.play("error")
		UiKit.shake(_cards[id]["buy"])
		return
	Sfx.play("upgrade")
	Game.vibrate(40 if not bool(r["evolved"]) else 90)
	refresh()
	var after: int = Game.squad_power()
	if bool(r["evolved"]):
		_evolve(id)
	else:
		UiKit.pop(_cards[id]["card"], 0.9)
	if after > before:
		UiKit.pill_count(_power, before, after, 0.6)
		UiKit.bump(_power, 1.3)
		_float_gain(id, after - before)


## Evolve celebration: a white flash, the old art shrinks away, the new tier's art pops in big
## with a ring of sparks and rays, and the new name pops.
func _evolve(id: String) -> void:
	var c: Dictionary = _cards[id]
	RetentionPanel.sfx(["rank_up", "upgrade"], 0.0, 1.0)
	var art: TextureRect = c["art"]
	var card: Control = c["card"]
	card.modulate = Color(2.2, 2.2, 2.0)
	card.create_tween().tween_property(card, "modulate", Color.WHITE, 0.5)
	art.scale = Vector2.ONE * 0.2
	art.rotation = -0.6
	var tw := art.create_tween().set_parallel()
	tw.tween_property(art, "scale", Vector2.ONE * 1.25, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(art, "rotation", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(art, "scale", Vector2.ONE, 0.2)
	UiKit.pop(c["name"], 0.4)
	var at := art.get_global_rect().get_center()
	for i in 16:
		var sp := RetentionPanel.icon_safe("star_icon", 36)
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sp.size = Vector2(36, 36)
		sp.z_index = 30
		add_child(sp)
		sp.global_position = at - Vector2(18, 18)
		var dir := Vector2.from_angle(TAU * i / 16.0)
		var t2 := sp.create_tween().set_parallel()
		t2.tween_property(sp, "global_position", sp.global_position + dir * randf_range(110.0, 190.0), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t2.tween_property(sp, "modulate:a", 0.0, 0.4).set_delay(0.2)
		t2.chain().tween_callback(sp.queue_free)
	# Rays: a few thin bars spinning out behind the art.
	for i in 8:
		var ray := ColorRect.new()
		ray.color = Color(1.0, 0.92, 0.5, 0.8)
		ray.size = Vector2(8, 110)
		ray.pivot_offset = Vector2(4, 110)
		ray.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ray.z_index = 29
		add_child(ray)
		ray.global_position = at - Vector2(4, 110)
		ray.rotation = TAU * i / 8.0
		var t3 := ray.create_tween().set_parallel()
		t3.tween_property(ray, "rotation", ray.rotation + 0.8, 0.7)
		t3.tween_property(ray, "modulate:a", 0.0, 0.7)
		t3.chain().tween_callback(ray.queue_free)


func _float_gain(id: String, n: int) -> void:
	var card: Control = _cards[id]["card"]
	var float_row := HBoxContainer.new()
	float_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	float_row.z_index = 31
	float_row.add_child(RetentionPanel.icon_safe("power", 52))
	float_row.add_child(UiKit.label("+%d" % n, 50, UiKit.YELLOW, 12))
	add_child(float_row)
	var r := card.get_global_rect()
	float_row.global_position = r.position + Vector2(r.size.x * 0.4, 0)
	var tw := float_row.create_tween().set_parallel()
	tw.tween_property(float_row, "global_position:y", r.position.y - 100.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(float_row, "modulate:a", 0.0, 0.4).set_delay(0.5)
	tw.chain().tween_callback(float_row.queue_free)


func _focus(id: String) -> void:
	if not is_inside_tree() or not _cards.has(id):
		return
	var card: Control = _cards[id]["card"]
	_scroll.ensure_control_visible(card)
	var tw := card.create_tween().set_loops(4)
	tw.tween_property(card, "modulate", Color(1.5, 1.5, 0.8), 0.25)
	tw.tween_property(card, "modulate", Color.WHITE, 0.25)


func _close() -> void:
	closed.emit()
	queue_free()


# ---------------------------------------------------------------- for tests and previews

func card_ids() -> Array:
	return _cards.keys()


func is_card_locked(id: String) -> bool:
	return Game.weapon_locked(id)


func lock_icon_visible(id: String) -> bool:
	return (_cards[id]["lock"] as Control).visible and (_cards[id]["lock_ic"] as Control).visible


func lock_text(id: String) -> String:
	return (_cards[id]["lock_label"] as Label).text


func pips_filled(id: String) -> int:
	var n := 0
	for p in (_cards[id]["pips"] as HBoxContainer).get_children():
		var sb := (p as Panel).get_theme_stylebox("panel") as StyleBoxFlat
		if sb and sb.bg_color == UiKit.YELLOW:
			n += 1
	return n


func name_text(id: String) -> String:
	return (_cards[id]["name"] as Label).text


func calibre_text(id: String) -> String:
	return (_cards[id]["calibre"] as Label).text


func art_path(id: String) -> String:
	return String(_cards[id]["art_path"])


## True when the player can afford at least one open weapon step (the lobby's "!" badge).
static func anything_affordable() -> bool:
	var coins := int(Game.save["coins"])
	for id in Armory.ids():
		if Game.weapon_locked(String(id)):
			continue
		var c: int = Game.weapon_cost(String(id))
		if c >= 0 and c <= coins:
			return true
	return false
