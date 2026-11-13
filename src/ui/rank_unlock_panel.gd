class_name RankUnlockPanel
extends RetentionPanel
## New Rank card (v1.1 item 1): full screen, once per rank, before the level that unlocks it
## (main.gd asks Game.rank_card_due(level)). A big glossy rank icon on turning rays, the
## rank's one-word name (allowed here, spec v1.1), damage per hit, rate /s, special icons, the
## lightning firepower of one troop (the Codex's numbers, with the player's Armory upgrades;
## owner play-test 2026-11-13 replaced the "= N constables" box), and the recruit gate it comes
## from (a green gate with "+1" and the rank's icon). Every stat explains itself on a tap. One green button closes; main.gd then opens the
## level's boosters. No other words.
##   RankUnlockPanel.new("sergeant")

var unit := "sergeant"


func _init(u := "sergeant") -> void:
	unit = u


func _ready() -> void:
	var allies: Dictionary = Game.upgraded_allies()
	var u: Dictionary = allies.get(unit, {})
	var col := _frame(first_icon(["badge", "station"]), 0, "", false, Color("23407f"))
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	# Big icon on slowly turning rays.
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(560, 360)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.clip_contents = true
	col.add_child(stage)
	var rays := _rays(300.0)
	rays.position = Vector2(280, 180)
	stage.add_child(rays)
	var spin := rays.create_tween().set_loops()
	spin.tween_property(rays, "rotation", TAU, 12.0).from(0.0)
	var big := icon_safe(CodexPanel.rank_icon(unit), 320)
	big.size = Vector2(320, 320)
	big.position = Vector2(120, 20)
	big.pivot_offset = Vector2(160, 160)
	stage.add_child(big)
	big.scale = Vector2.ZERO
	var tw := big.create_tween()
	tw.tween_interval(0.15)
	tw.tween_property(big, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# The rank's weapon, big, in front of its icon: what actually makes this rank different.
	var wid := CodexPanel.weapon_icon(unit)
	if wid != "":
		var wpn := CodexPanel.weapon_art(unit, 200)
		wpn.size = Vector2(200, 200)
		wpn.position = Vector2(330, 150)
		wpn.pivot_offset = Vector2(100, 100)
		wpn.rotation = -0.25
		stage.add_child(wpn)
		wpn.scale = Vector2.ZERO
		var tw2 := wpn.create_tween()
		tw2.tween_interval(0.4)
		tw2.tween_property(wpn, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		big.position.x = 70

	var name_label := UiKit.label(String(u.get("name", unit.capitalize())).to_upper(), 76, UiKit.YELLOW, 16)
	col.add_child(name_label)

	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 12)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stats)
	var ctx := CodexPanel.tip_ctx(allies, unit)
	for s in [[CodexPanel.DMG_ICON, CodexPanel.number(float(u.get("dmg", 1))), "damage"],
			[CodexPanel.RATE_ICON, CodexPanel.number(float(u.get("rate", 1.0))) + "/s", "rate"]]:
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 4)
		pair.add_child(icon_safe(String(s[0]), 64))
		pair.add_child(UiKit.label(String(s[1]), 56, Color.WHITE, 10))
		StatTip.attach(pair, String(s[2]), ctx)
		stats.add_child(pair)
	for sp in CodexPanel.specials(u):
		var spair := HBoxContainer.new()
		spair.add_theme_constant_override("separation", 2)
		spair.add_child(icon_safe(sp, 64))
		var t := CodexPanel.special_text(sp, u)
		if t != "":
			spair.add_child(UiKit.label(t, 48, Color.WHITE, 10))
		StatTip.attach(spair, String(CodexPanel.SPECIAL_TIPS.get(sp, sp)), ctx)
		stats.add_child(spair)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 26)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bottom)
	var vb := CodexPanel.dps_box(float(ctx["dps"]), -1.0, 64)
	StatTip.attach(vb, "power", ctx)
	bottom.add_child(vb)
	bottom.add_child(gate_icon(unit))

	var go := UiKit.icon_button("play", "green", 140)
	go.custom_minimum_size.x = 260
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(close)
	col.add_child(go)
	pulse(go, 0.05)
	sfx(["rank_up", "banner", "win"])
	after(0.45, func(): burst(centre(big), 18))
	log_event("rank_card", {"unit": unit})


## The recruit gate the rank comes from, as it looks in the level: a green gate panel with
## "+1" and the rank's icon.
static func gate_icon(u: String) -> Control:
	var g := card_box(Color(0.2, 0.75, 0.3), 8, 18, 5)
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 4)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(r)
	r.add_child(UiKit.label("+1", 52, Color.WHITE, 10))
	r.add_child(icon_safe(CodexPanel.rank_icon(u), 64))
	return g


## A ring of soft rays (a Polygon2D fan) centred on its position.
static func _rays(radius: float) -> Node2D:
	var n := Node2D.new()
	var count := 12
	for i in count:
		var a := TAU * i / count
		var w := TAU / count * 0.35
		var p := Polygon2D.new()
		p.polygon = PackedVector2Array([Vector2.ZERO, Vector2.from_angle(a - w) * radius, Vector2.from_angle(a + w) * radius])
		p.color = Color(1.0, 0.85, 0.3, 0.22)
		n.add_child(p)
	return n
