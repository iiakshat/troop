extends "res://tests/test_case.gd"
## Owner play-test 2026-11-13: menus a first-time player understands, and a notch-safe layout.
## - Safe area: the insets maths, panels kept clear of a cut-out, and the backings (the lobby's
##   top fade, the HUD's scrim) running to the very top of the screen while the buttons sit
##   below the cut-out (UiKit.debug_safe simulates one, as `safe_top=80` does on a PC).
## - Stats: the damage icon is never the fist-bump, every number is the upgraded one, the
##   lightning per troop is damage x rate x enemies hit, and every tip is icons and numbers.


func _add(tree: SceneTree, n: Node) -> void:
	tree.root.add_child(n)
	if not n.is_node_ready() and n.has_method("_ready"):
		n._ready()


func test_insets_maths() -> void:
	# A 1080 x 2400 phone with a 120 px punch-hole band and a 60 px gesture bar, UI 1600 high.
	var ins := UiKit.insets_for(Vector2(1080, 2400), Rect2(0, 120, 1080, 2220), 1600.0)
	near(ins.x, 80.0, "top inset in UI px")
	near(ins.y, 40.0, "bottom inset in UI px")
	ins = UiKit.insets_for(Vector2(1080, 2400), Rect2(0, 0, 1080, 2400), 1600.0)
	eq(ins, Vector2(24, 12), "no cut-out: the status and gesture bar minimum")
	eq(UiKit.insets_for(Vector2(0, 0), Rect2(), 1280.0), Vector2(48, 24), "nothing reported: safe defaults")


func test_center_span_keeps_panels_clear() -> void:
	eq(UiKit.center_span(1600.0, 600.0, Vector2(80, 40)), Vector2(200, 1400), "room enough: stays centred")
	eq(UiKit.center_span(1400.0, 600.0, Vector2(120, 0)), Vector2(132, 1332), "moved down under the cut-out")
	var s := UiKit.center_span(1280.0, 600.0, Vector2(80, 40))
	eq(s, Vector2(92, 1228), "too tall: fits between the insets")
	eq(UiKit.center_span(1280.0, 600.0, Vector2.ZERO), Vector2(40, 1240), "a PC: unchanged")


func test_top_scrim_runs_from_the_screen_edge() -> void:
	var f := UiKit.top_scrim(80.0, 150.0)
	eq(f.offset_top, 0.0, "starts at y = 0")
	eq(f.offset_bottom, 230.0, "covers the cut-out and fades below it")
	var g := (f.texture as GradientTexture2D).gradient
	near(g.sample(0.0).a, 0.92, "dark at the top")
	near(g.sample(80.0 / 230.0 - 0.01).a, 0.92, "solid over the whole cut-out")
	near(g.sample(1.0).a, 0.0, "clear at the bottom")
	f.free()


## The HUD under a cut-out: the bar sits in the safe rect, its scrim starts at the screen's top
## edge (offsets: the runner's tree is not laid out yet). The lobby's live check (fade from y = 0,
## buttons below the cut-out) is in tests/smoke_lobby.gd, which runs frames.
func test_hud_scrim_reaches_the_top_under_a_notch() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	UiKit.debug_safe = Vector2(80, 30)
	var hud := Hud.new()
	_add(tree, hud)
	eq(hud.offset_top, 80.0, "the HUD's buttons live below the cut-out")
	eq(hud.offset_bottom, -30.0, "and above the gesture bar")
	var scrim := hud.find_child("TopScrim", true, false) as Control
	check(scrim != null and scrim.get_parent() == hud, "the HUD has a scrim under a cut-out")
	if scrim:
		eq(hud.offset_top + scrim.offset_top, 0.0, "the scrim starts at the very top of the screen")
		check(hud.offset_top + scrim.offset_bottom > 80.0, "and reaches below the cut-out")
	tree.root.remove_child(hud)
	hud.free()
	UiKit.debug_safe = Vector2(-1, -1)
	var hud2 := Hud.new()
	_add(tree, hud2)
	check(hud2.find_child("TopScrim", true, false) == null, "no scrim without a cut-out (PC)")
	tree.root.remove_child(hud2)
	hud2.free()


## Tip rows: every "@icon" exists, and the rest is numbers and symbols (unit marks s, m, K, M,
## %, /s only): no words (owner rule).
func test_stat_tips_are_icons_and_numbers() -> void:
	var keys := ["damage", "rate", "power", "pierce", "armour", "splash", "burst", "toughest", "tap",
		"heart", "speed", "melee", "fire", "shooter", "riot", "boss_crown"]
	var ctx := {"dmg": 3.0, "rate": 2.0, "hits": 5.0, "dps": 30.0, "v": 4.0, "who": "brute"}
	var re := RegEx.create_from_string("[0-9.,%+\\-×=▸>/ ]")
	for k in keys:
		var rows: Array = StatTip.rows(k, ctx)
		check(not rows.is_empty(), "%s has an example" % k)
		var all: Array = StatTip.header(k, ctx).duplicate()
		for r in rows:
			all.append_array(r)
		for tok in all:
			var t := String(tok)
			if t.begins_with("@"):
				check(RetentionPanel.has_icon(t.substr(1)), "%s: icon %s exists" % [k, t])
			else:
				check(re.sub(t, "", true) in ["", "s", "m", "K", "M"], "%s: '%s' is a number or symbol" % [k, t])
	eq(StatTip.rows("power", ctx)[1], ["=", "@power", "30"], "the lightning is the row's own dps")
	eq(StatTip.rows("power", ctx)[0], ["@damage", "3", "×", "@fire_rate", "2/s", "×", "@thug", "5"], "dmg x rate x hits")
	eq(StatTip.rows("clock", {"lo": "1.2", "hi": "0.8"}), [["@clock", "1.2", "▸", "0.8", "@upgrade"]], "an Armory handling stat: first ▸ last")


func test_damage_icon_and_armory_rows() -> void:
	check(RetentionPanel.has_icon(CodexPanel.DMG_ICON), "the damage icon exists")
	check(CodexPanel.DMG_ICON != "fist", "never the fist-bump")
	eq(String(ArmoryPanel.STATS["dmg"][0]), CodexPanel.DMG_ICON, "the Armory uses the same damage icon")
	eq(String(ArmoryPanel.STATS["dps"][0]), "power", "firepower uses the Squad Power lightning")
	eq(ArmoryPanel.stat_keys("service_pistol"), ["dps", "dmg", "rate"], "squad weapons: firepower first")
	eq(ArmoryPanel.user_icon("knives"), CodexPanel.rank_icon("hero"), "knives: the hero carries them")
	eq(ArmoryPanel.user_icon("shotgun"), CodexPanel.rank_icon("sergeant"), "the shotgun: the sergeant")
	eq(ArmoryPanel.user_icon("finale_bow"), "bottle", "Bottle Shot weapons: the bottle")
	var s := Armory.stats_at("service_pistol", 1, 0)
	check(ArmoryPanel.stat_text("service_pistol", "rate", s).ends_with("/s"), "rate has its /s")
	var u: Dictionary = Config.units()["allies"]["constable"]
	near(ArmoryPanel.stat_value("service_pistol", "dps", s),
		float(u["dmg"]) * float(s["dmg_mult"]) * float(u["rate"]) * float(s["rate_mult"]), "dps = dmg x rate")


## The Codex shows the player's upgraded numbers: a pistol step raises the constable's lightning.
func test_codex_numbers_follow_the_armory() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node_or_null("Game")
	if game == null:
		check(false, "Game autoload present")
		return
	var keep: Dictionary = game.save.duplicate(true)
	var keep_path: String = game.save_path
	game.save_path = ""
	game.boot({"unlocked": 20, "coins": 100000, "birth_year": 1990})
	var cp := CodexPanel.new()
	_add(tree, cp)
	var before := cp.dps_text("constable")
	eq(before, Economy.fmt_power(CodexPanel.troop_dps(game.upgraded_allies(), "constable")), "the constable's lightning")
	check(cp.dps_text("hero") != "", "the hero has one too")
	eq(cp.dps_text("commando"), "", "a locked rank shows none")
	for c in cp.find_children("*", "TextureRect", true, false):
		check((c as TextureRect).texture != UiKit.icon_texture("fist"), "no fist-bump icon on the ranks tab")
	tree.root.remove_child(cp)
	cp.free()
	for i in 3:
		game.buy_weapon("service_pistol")
	var cp2 := CodexPanel.new()
	_add(tree, cp2)
	check(float(cp2.dps_text("constable")) > float(before), "after pistol steps the lightning grew (%s > %s)" % [cp2.dps_text("constable"), before])
	tree.root.remove_child(cp2)
	cp2.free()
	game.save = keep
	game.save_path = keep_path
