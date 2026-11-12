class_name CodexPanel
extends RetentionPanel
## Codex: two tabs (ranks / enemies) of cards built from config/units.json, so the numbers are
## always the real ones. Rank card: icon, name (1-3 words, the Codex allows it), damage, rate,
## a special icon (pierces armour, burst, splash, picks the toughest) and the value line
## "= N" (DPS relative to a constable: Squad.value_vs_constable when the sim has it, else the
## same nominal formula here). Ranks not unlocked yet are dark with a lock, the district and the
## level that unlocks them. Enemy card: icon, name, hp, armour, speed, its threat icon and
## melee power. Enemies you have not reached yet are hidden behind a lock too.
## v1.1: rank cards are sorted by their "= N" value (hero first), and every screen that shows a
## rank (Codex, RankToast, New Rank card, gates) uses rank_icon() so the icons match.

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
const PIERCE_ICON := "armour_pierce"


static func weapon_icon(id: String) -> String:
	return String(RANK_WEAPONS.get(id, ""))


## "= N constables": a plain figure plus a pistol, so it never reads as the rank's own cap.
static func constable_ref(px: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", -int(px * 0.3))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(icon_safe("person", px, Color("1d2b55")))
	var g := icon_safe("pistol", int(px * 0.7))
	g.size_flags_vertical = Control.SIZE_SHRINK_END
	h.add_child(g)
	return h

var start_tab := "ranks"
var _tab := ""
var _list: VBoxContainer
var _tabs := {}


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
	if t == "ranks":
		# v2 rule 6: values and numbers compare the player's upgraded stats (Armory).
		var allies: Dictionary = Game.upgraded_allies()
		for id in ranks_by_value(allies):
			_list.add_child(_rank_card(String(id), allies[id]))
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


## "= 4", "= 2.5" (value line text). Hero has none.
static func value_text(stats: Dictionary, rank: String) -> String:
	if rank == "hero":
		return ""
	var v := value_of(stats, rank)
	if absf(v - round(v)) < 0.05:
		return "= %d" % int(round(v))
	return "= %.1f" % v


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
		out.append("shield")
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


func _rank_card(id: String, u: Dictionary) -> Control:
	var locked := _locked(u, id, true)
	var parts := _base_card(locked)
	var row: HBoxContainer = parts[1]
	var ic := icon_safe(rank_icon(id), 104)
	if locked:
		ic.modulate = Color(0, 0, 0, 0.85)
	row.add_child(ic)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 0)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mid)
	var title := UiKit.label(String(u.get("name", id.capitalize())).to_upper(), 36, UiKit.YELLOW if not locked else Color(1, 1, 1, 0.6), 9)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mid.add_child(title)
	if locked:
		mid.add_child(_lock_row(unlock_level(u)))
		return parts[0]
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(stats)
	_stat(stats, "knife_power" if id == "hero" else "fist", number(float(u.get("dmg", 1))))
	_stat(stats, RATE_ICON, number(float(u.get("rate", 1.0))))
	if weapon_icon(id) != "":
		stats.add_child(icon_safe(weapon_icon(id), 46))
	for s in specials(u):
		stats.add_child(icon_safe(s, 46))
	var v := value_text(Game.units.get("allies", {}), id)
	if v != "":
		var vb := card_box(UiKit.YELLOW, 6, 18, 4)
		vb.custom_minimum_size = Vector2(118, 0)
		var vr := HBoxContainer.new()
		vr.add_theme_constant_override("separation", 2)
		vr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(vr)
		vr.add_child(UiKit.label(v, 40, Color.WHITE, 9))
		vr.add_child(constable_ref(40))
		row.add_child(vb)
	return parts[0]


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
	_stat(stats, "heart", number(float(u.get("hp", 1))))
	_stat(stats, "speed", number(float(u.get("speed", 1.0))))
	var power := int(u.get("power", 1))
	if power < 100:
		_stat(stats, "fist", str(power))
	for s in threats(u):
		stats.add_child(icon_safe(s, 46))
	return parts[0]


func _stat(where: HBoxContainer, icon_name: String, text: String) -> void:
	var c := HBoxContainer.new()
	c.add_theme_constant_override("separation", 2)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(icon_safe(icon_name, 44))
	c.add_child(UiKit.label(text, 36, Color.WHITE, 8))
	where.add_child(c)


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
