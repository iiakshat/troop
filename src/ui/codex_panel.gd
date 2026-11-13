class_name CodexPanel
extends RetentionPanel
## Codex: two tabs (ranks / enemies) of cards built from config/units.json, so the numbers are
## always the real ones. Rank card: see the 2026-11-13 note below (value_of, the old "= N"
## constables, still sorts the cards: it is the same firepower relative to a constable). Ranks
## not unlocked yet are dark with a lock and the level that unlocks them. Enemy card: icon,
## name, hp, speed, troops one takes in a clash (-N and the troop figure), its threat icons.
## Enemies you have not reached yet are hidden behind a lock too.
## v1.1: rank cards are sorted by their "= N" value (hero first), and every screen that shows a
## rank (Codex, RankToast, New Rank card, gates) uses rank_icon() so the icons match.
## Owner play-test 2026-11-13 ("the characters' power is unclear, what weapon, why a join
## symbol and 16?"): a rank card is now portrait + its weapon (the Armory art of its track, drawn
## big) + name, damage per hit (DMG_ICON, a bullet into an impact burst, never the fist-bump)
## and rate "/s", its specials with their "×N", and ONE headline on the right: the lightning
## firepower of one troop (troop_dps: damage × rate × enemies hit, the same unit as Squad
## Power), with a bar against the strongest rank so the order reads at a glance. All numbers are
## the player's upgraded ones (units.json × Armory). Every stat icon explains itself on a tap
## (StatTip). The "= N constables" box is gone (the lightning already ranks them).

## Preferred icons per rank, first that exists wins (the v1.1 headgear set first).
const RANK_ICONS := {
	"hero": ["rank_hero", "knife"], "constable": ["rank_constable", "badge", "pistol"],
	"sergeant": ["sergeant"], "inspector": ["inspector"], "swat": ["swat"],
	"sniper": ["rank_sniper", "sniper"], "commando": ["rank_commando", "commando"],
}
const ENEMY_ICONS := {"knifer": ["knife"], "gunman": ["pistol"], "biker": ["speed"]}
## The weapon each rank carries (what makes it different; shown on the rank card and Codex).
const RANK_WEAPONS := {
	"hero": "knife", "constable": "pistol", "sergeant": "weapon_shotgun", "inspector": "weapon_revolver",
	"swat": "smg", "sniper": "sniper", "commando": "weapon_launcher",
}
const RATE_ICON := "fire_rate"     ## shots per second (the sneaker stays for enemy speed)
const DMG_ICON := "damage"         ## damage per hit: a bullet into an impact burst
const PIERCE_ICON := "armour_pierce"
## StatTip key of each special icon.
const SPECIAL_TIPS := {"aim": "toughest", "armour_pierce": "pierce", "gang_split": "burst", "bomb": "splash"}
## StatTip key of each enemy threat icon.
const THREAT_TIPS := {"boss_crown": "boss_crown", "fire": "fire", "aim": "shooter", "pistol": "shooter",
	"armour": "armour", "riot": "riot"}


static func weapon_icon(id: String) -> String:
	return String(RANK_WEAPONS.get(id, ""))


## Firepower of ONE troop of `rank` with stats `stats` (the lightning unit of Squad Power and the
## HUD): damage × rate × enemies one shot hits (burst, splash), vs a plain crowd.
static func troop_dps(stats: Dictionary, rank: String) -> float:
	if not stats.has(rank):
		return 0.0
	return Squad.hit_value(stats[rank], 0, 1.0, 1 << 30, true)


## Enemies one shot of `u` hits at best (burst × splash), 1 for a plain gun.
static func hits_of(u: Dictionary) -> float:
	return maxf(float(u.get("multi", 1)) * float(u.get("splash", 1)), 1.0)


## The numbers a rank's tips use: {dmg, rate, hits, dps}.
static func tip_ctx(stats: Dictionary, rank: String) -> Dictionary:
	var u: Dictionary = stats.get(rank, {})
	return {"dmg": float(u.get("dmg", 1)), "rate": float(u.get("rate", 1.0)), "hits": hits_of(u),
		"dps": troop_dps(stats, rank)}


## The "×N" a special icon carries (burst and splash), else "".
static func special_text(icon_name: String, u: Dictionary) -> String:
	match icon_name:
		"gang_split":
			return "×" + number(float(u.get("multi", 1)))
		"bomb":
			return "×" + number(float(u.get("splash", 1)))
	return ""


## The weapon a rank carries, drawn big: the current tier's Armory art of its track (so an
## upgrade that evolves it shows here too), else the plain weapon icon.
static func weapon_art(rank: String, px: int) -> TextureRect:
	var track := Armory.track_of(rank)
	if track != "":
		return ArmoryPanel.art_icon(track, px)
	return icon_safe(weapon_icon(rank) if weapon_icon(rank) != "" else "pistol", px)


## The lightning headline: icon + one troop's firepower, a bar against the strongest (0..1).
static func dps_box(dps: float, fill: float, px := 44) -> PanelContainer:
	var vb := card_box(UiKit.YELLOW, 6, 18, 4)
	vb.custom_minimum_size = Vector2(px * 3.3, 0)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(col)
	var r := HBoxContainer.new()
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_theme_constant_override("separation", 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(r)
	r.add_child(icon_safe("power", px))
	var l := UiKit.label(Economy.fmt_power(dps), int(px * 0.95), Color.WHITE, 9)
	l.name = "Dps"
	r.add_child(l)
	if fill >= 0.0:
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(px * 2.6, 14)
		bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := Panel.new()
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_theme_stylebox_override("panel", UiKit.flat_box(Color(0, 0, 0, 0.35), 7, 3))
		UiKit.full_rect(bg)
		bar.add_child(bg)
		var fl := Panel.new()
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fl.add_theme_stylebox_override("panel", UiKit.flat_box(Color("ff8a1f"), 7, 3))
		fl.anchor_bottom = 1.0
		fl.anchor_right = clampf(fill, 0.08, 1.0)
		bar.add_child(fl)
		col.add_child(bar)
	return vb


var start_tab := "ranks"
var _tab := ""
var _list: VBoxContainer
var _tabs := {}
var _dps: Dictionary = {}   # rank -> its lightning label (tests)


func _ready() -> void:
	var col := _frame(first_icon(["badge", "station"]), 1180, "", false)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 16)
	col.add_child(tabs)
	for t in [["ranks", first_icon(["badge", "inspector"])], ["enemies", first_icon(["thug", "fist"])]]:
		var b := UiKit.icon_button(String(t[1]), "blue", 110)
		b.custom_minimum_size.x = 220
		b.pressed.connect(_show_tab.bind(String(t[0])))
		tabs.add_child(b)
		_tabs[String(t[0])] = b
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	UiKit.touch_scroll(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	_show_tab(start_tab if start_tab in ["ranks", "enemies"] else "ranks")


func _show_tab(t: String) -> void:
	if t == _tab:
		return
	_tab = t
	for k in _tabs:
		var colr := "yellow" if k == t else "blue"
		var b: Button = _tabs[k]
		for st in ["normal", "hover"]:
			b.add_theme_stylebox_override(st, UiKit._tex_box(colr, "square"))
	for c in _list.get_children():
		c.queue_free()
	_dps.clear()
	if t == "ranks":
		# v2 rule 6: values and numbers compare the player's upgraded stats (Armory).
		var allies: Dictionary = Game.upgraded_allies()
		var top := 0.0
		for id in allies:
			if not _locked(allies[id], String(id), true):
				top = maxf(top, troop_dps(allies, String(id)))
		for id in ranks_by_value(allies):
			_list.add_child(_rank_card(String(id), allies, top))
	else:
		var enemies: Dictionary = Game.units.get("enemies", {})
		for id in enemies:
			_list.add_child(_enemy_card(String(id), enemies[id]))


# ---------------------------------------------------------------- pure helpers (tested)

## The icon for a rank, the same everywhere.
static func rank_icon(id: String) -> String:
	var names: Array = RANK_ICONS.get(id, []).duplicate()
	var u: Dictionary = Game.units.get("allies", {}).get(id, {})
	if u.has("icon"):
		names.append(String(u["icon"]))
	names.append_array([id, "badge"])
	return first_icon(names)


## Ally ids sorted by value vs a constable, weakest first; the hero (no value line) leads.
static func ranks_by_value(allies: Dictionary) -> Array:
	var ids: Array = allies.keys()
	ids.sort_custom(func(a, b):
		if String(a) == "hero" or String(b) == "hero":
			return String(a) == "hero" and String(b) != "hero"
		var va := value_of(allies, String(a))
		var vb := value_of(allies, String(b))
		if absf(va - vb) > 1e-6:
			return va < vb
		return unlock_level(allies[a]) < unlock_level(allies[b]))
	return ids

## Nominal value of an ally vs a constable (both from the same stats table): dmg x rate x
## (burst x splash hits) relative to the constable. Prefers the sim's own function.
static func value_of(stats: Dictionary, rank: String) -> float:
	var sq: Script = Squad
	for m in sq.get_script_method_list():
		if String(m["name"]) == "value_vs_constable":
			return float(sq.call("value_vs_constable", stats, rank))
	if not stats.has(rank) or not stats.has("constable"):
		return 0.0
	var base := _nominal(stats["constable"])
	return _nominal(stats[rank]) / base if base > 0.0 else 0.0


static func _nominal(u: Dictionary) -> float:
	var hits := maxf(float(u.get("multi", 1)) * float(u.get("splash", 1)), 1.0)
	return float(u.get("dmg", 1)) * float(u.get("rate", 1.0)) * hits


## Level that unlocks a unit (units.json "unlock", default 1).
static func unlock_level(u: Dictionary) -> int:
	return maxi(int(u.get("unlock", u.get("unlock_level", 1))), 1)


## Icon names for an ally's special: pierce, burst (multi), splash, toughest-first.
static func specials(u: Dictionary) -> Array:
	var out := []
	if String(u.get("target", "")) == "toughest":
		out.append("aim")
	if bool(u.get("pierce", false)):
		out.append(PIERCE_ICON)
	if float(u.get("multi", 1)) > 1.0:
		out.append("gang_split")
	if float(u.get("splash", 1)) > 1.0:
		out.append("bomb")
	return out


## Threat icons for an enemy: shooter, firebombs, armour, riot shield, boss.
static func threats(u: Dictionary) -> Array:
	var out := []
	if bool(u.get("boss", false)):
		out.append("boss_crown")
	if u.has("burn") or u.has("throw_every"):
		out.append("fire")
	elif u.has("shoot_every") or int(u.get("return_fire", {}).get("share", 0)) >= 50:
		out.append("aim" if u.has("aim") else "pistol")
	if int(u.get("armour", 0)) > 0:
		out.append("armour")
	if int(u.get("shield", 0)) > 0:
		out.append("riot")  # the gang's riot shield, never the squad's shield power icon
	return out


static func number(x: float) -> String:
	return str(int(round(x))) if absf(x - round(x)) < 0.05 else "%.1f" % x


# ---------------------------------------------------------------- cards

func _locked(u: Dictionary, id: String, rank: bool) -> bool:
	var unlocked := int(Game.save.get("unlocked", 1))
	if rank and Game.rank_seen(id):
		return false
	return unlock_level(u) > unlocked


func _base_card(locked: bool) -> Array:
	var card := card_box(Color("2a3a5e") if locked else Color("3b6fd1"), 10)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	return [card, row]


## A rank card: portrait, its weapon big, name / damage and rate / specials, and the lightning
## firepower of one troop with a bar against the strongest rank (`top`).
func _rank_card(id: String, allies: Dictionary, top: float) -> Control:
	var u: Dictionary = allies[id]
	var locked := _locked(u, id, true)
	var parts := _base_card(locked)
	var row: HBoxContainer = parts[1]
	row.add_theme_constant_override("separation", 6)
	(parts[0] as Control).custom_minimum_size.y = 136   # one even row height, locked or not
	var ic := icon_safe(rank_icon(id), 84)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var wp := weapon_art(id, 96)
	wp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if locked:
		ic.modulate = Color(0, 0, 0, 0.85)
		wp.modulate = Color(0, 0, 0, 0.6)
	row.add_child(ic)
	row.add_child(wp)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 2)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mid)
	var title := UiKit.label(String(u.get("name", id.capitalize())).to_upper(), 32, UiKit.YELLOW if not locked else Color(1, 1, 1, 0.6), 9)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.clip_text = true
	mid.add_child(title)
	if locked:
		mid.add_child(_lock_row(unlock_level(u)))
		return parts[0]
	var ctx := tip_ctx(allies, id)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(stats)
	_stat(stats, DMG_ICON, number(float(u.get("dmg", 1))), "damage", ctx)
	_stat(stats, RATE_ICON, number(float(u.get("rate", 1.0))) + "/s", "rate", ctx)
	var sp := specials(u)
	if id == "hero":
		sp.push_front("hand")   # tapping heats him up: the tip shows idle vs steady tapping
	if not sp.is_empty():
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 10)
		srow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mid.add_child(srow)
		for s in sp:
			var key := "tap" if s == "hand" else String(SPECIAL_TIPS.get(s, s))
			var tctx := ctx.duplicate()
			if s == "hand":
				tctx = hero_tap_ctx()
			_stat(srow, String(s), special_text(String(s), u), key, tctx)
	var box := dps_box(float(ctx["dps"]), float(ctx["dps"]) / top if top > 0.0 else 1.0)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	StatTip.attach(box, "power", ctx)
	row.add_child(box)
	_dps[id] = box.find_child("Dps", true, false)
	return parts[0]


## The lightning number on a rank's card as shown ("" when locked or not on screen; tests).
func dps_text(rank: String) -> String:
	var l: Variant = _dps.get(rank)
	return (l as Label).text if l is Label and is_instance_valid(l) else ""


## The hero's tap numbers for his tip: idle share of his rate and the taps/s that hold it full.
static func hero_tap_ctx() -> Dictionary:
	var tap: Dictionary = Game.units.get("hero", {}).get("tap", {})
	var per := maxf(float(tap.get("per_tap", 0.3)) * float(tap.get("decay_s", 1.0)), 0.01)
	return {"auto": float(tap.get("auto_rate", 0.4)), "taps": ceilf(1.0 / per)}


func _enemy_card(id: String, u: Dictionary) -> Control:
	var locked := _locked(u, id, false)
	var parts := _base_card(locked)
	var row: HBoxContainer = parts[1]
	var names: Array = ENEMY_ICONS.get(id, []).duplicate()
	names.push_front(String(u.get("icon", id)))
	var ic := icon_safe(first_icon(names), 104)
	if locked:
		ic.modulate = Color(0, 0, 0, 0.85)
	row.add_child(ic)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 0)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mid)
	var title := UiKit.label(String(u.get("name", id.capitalize())).to_upper(), 36, UiKit.RED if not locked else Color(1, 1, 1, 0.6), 9)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mid.add_child(title)
	if locked:
		mid.add_child(_lock_row(unlock_level(u)))
		return parts[0]
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(stats)
	_stat(stats, "heart", number(float(u.get("hp", 1))), "heart", {"v": float(u.get("hp", 1))})
	_stat(stats, "speed", number(float(u.get("speed", 1.0))), "speed", {"v": float(u.get("speed", 1.0))})
	var power := int(u.get("power", 1))
	if power < 100:
		# Troops one of them takes in a clash: the HUD's troop figure with a red minus.
		_stat(stats, "person", "-%d" % power, "melee", {"v": power, "who": first_icon(names)}, UiKit.RED)
	var tstats := HBoxContainer.new()
	tstats.add_theme_constant_override("separation", 10)
	tstats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in threats(u):
		_stat(tstats, String(s), "", String(THREAT_TIPS.get(s, s)), threat_ctx(String(s), u))
	if tstats.get_child_count() > 0:
		mid.add_child(tstats)
	else:
		tstats.free()
	return parts[0]


## The number a threat's tip shows: troops a firebomb burns, a shot takes, riot-shield hp, boss hp.
static func threat_ctx(icon_name: String, u: Dictionary) -> Dictionary:
	match icon_name:
		"fire":
			return {"v": float(u.get("burn", 2))}
		"aim", "pistol":
			return {"v": float(u.get("shot_dmg", 1))}
		"riot":
			return {"v": float(u.get("shield", 4))}
		"boss_crown":
			return {"v": float(u.get("hp", 360))}
		"armour":
			return {"dmg": 4.0}
	return {}


## An icon + number pair; a tap on it explains it (StatTip `tip` with `ctx`).
func _stat(where: HBoxContainer, icon_name: String, text: String, tip := "", ctx := {}, color := Color.WHITE) -> void:
	var c := HBoxContainer.new()
	c.add_theme_constant_override("separation", 2)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(icon_safe(icon_name, 42))
	if text != "":
		c.add_child(UiKit.label(text, 32, color, 8))
	where.add_child(c)
	if tip != "":
		var tctx := ctx.duplicate()
		tctx["icon"] = icon_name
		StatTip.attach(c, tip, tctx)


## Lock + the level that unlocks it (no district number: on the Station, lock + N means
## "liberate district N", a different condition).
func _lock_row(lv: int) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(icon_safe("lock", 48))
	r.add_child(icon_safe(first_icon(["map_pin", "lock"]), 44))
	r.add_child(UiKit.label(str(lv), 36, Color.WHITE, 8))
	return r
