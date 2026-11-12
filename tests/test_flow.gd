extends "res://tests/test_case.gd"
## Flow pieces owned by main.gd (WIRE): the liberation panel and the per-kind kill counter
## that feeds the missions.


func _add(tree: SceneTree, n: Node) -> void:
	tree.root.add_child(n)
	if not n.is_node_ready() and n.has_method("_ready"):
		n._ready()


func test_liberation_panel_builds_and_closes() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node_or_null("Game")
	if game == null:
		check(false, "Game autoload present")
		return
	var keep: Dictionary = game.save.duplicate(true)
	var keep_path: String = game.save_path
	game.save_path = ""
	game.boot({})
	for d in [1, 5]:
		var p := LiberationPanel.new(d)
		var closed := [false]
		p.closed.connect(func(): closed[0] = true)
		_add(tree, p)
		check(p.get_child_count() >= 2, "liberation %d built its frame" % d)
		check(is_instance_valid(p._close_btn) and p._close_btn.visible, "liberation %d has a visible X" % d)
		p._close_btn.pressed.emit()
		check(closed[0], "liberation %d emits closed" % d)
		tree.root.remove_child(p)
		p.free()
	game.save = keep
	game.save_path = keep_path


func test_kills_are_counted_per_enemy_kind() -> void:
	var sim := LevelSim.new(Config.level(1), Config.units(), {})
	var pilot := Autopilot.new([2, 1, 1, 0, 0], true)
	var guard := 0
	while sim.state == "run" and guard < 20000:
		pilot.drive(sim)
		sim.step(1.0 / 30.0)
		sim.drain()
		guard += 1
	var sum := 0
	for kind in sim.kills_by:
		sum += int(sim.kills_by[kind])
	check(sim.kills > 0, "level 1 autoplay kills someone")
	eq(sum, sim.kills, "per-kind kills add up to the total")


## AUDIO: numbered files are takes of an existing id; star1-3 stay separate notes of one chord.
func test_sfx_groups_takes() -> void:
	var g: Dictionary = preload("res://src/autoload/sfx.gd").group_files(
		PackedStringArray(["glass_break", "glass_break2", "glass_break3", "star1", "star2", "star3"]))
	check(g.get("glass_break", []) == ["glass_break", "glass_break2", "glass_break3"], "glass_break2/3 are takes of glass_break")
	check(g.has("star1") and g.has("star2") and g.has("star3"), "star1-3 stay their own ids")


## AUDIO: every spec sound id has a file, and duck runs without errors from a script.
func test_sfx_ids_and_calls() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var sfx: Node = tree.root.get_node_or_null("Sfx")
	if sfx == null:
		check(false, "Sfx autoload present")
		return
	for id in ["knife", "shot", "shot_sniper", "shot_shotgun", "launcher", "glass_break", "glass_tinkle",
			"punch", "hit", "die", "hurt", "coin", "rank_up", "boss_roar", "fire", "pothole", "star1", "star3"]:
		check(ResourceLoader.exists("res://assets/audio/%s.ogg" % id), "sound file for %s" % id)
	# play()/play_music() are exercised by the autoplay runs; here they would leave playbacks
	# the headless dummy audio driver never frees (exit-time "resources still in use").
	sfx.duck_music(true)
	sfx.duck_music(false)
	check(true, "Sfx duck calls ran")


## BRAND: the boot screens (axnex intro -> the cinematic loading screen -> the flow; owner
## 2026-11-12: no wordmark). Driven by advance()/tap() so no frames or tweens are needed;
## tests warm nothing (an empty list) and pin the shot, so no user:// file is written.
func _boot_seq(first_launch: bool, flow: Callable) -> BootSequence:
	var seq := BootSequence.new(first_launch, flow, 0, PackedStringArray())
	seq.write_seen = false  # tests never write the save
	return seq


func test_boot_shows_intro_then_loading_on_first_launch() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node_or_null("Game")
	var keep: Dictionary = game.save.duplicate(true)
	game.save["seen_hints"] = []
	check(BootSequence.is_first_launch(), "a save without the intro hint is a first launch")
	var started := [0]
	var seq := _boot_seq(true, func(): started[0] += 1)
	eq(seq.stage, "intro", "the axnex intro comes first")
	seq.tap()
	eq(seq.stage, "intro", "a tap does not skip the intro on the first launch")
	seq.advance(BootIntro.DURATION * 0.5)
	eq(seq.stage, "intro", "the intro runs its full length")
	seq.advance(BootIntro.DURATION * 0.5 + 0.02)
	eq(seq.stage, "loading", "the loading screen follows the intro (no wordmark screen)")
	check(seq.loading_screen() is LoadingScreen, "the loading screen is up")
	check((game.save["seen_hints"] as Array).has("intro"), "a finished intro is remembered")
	check(not BootSequence.is_first_launch(), "the next launch is not a first launch")
	for i in 120:
		seq.advance(1.0 / 30.0)
	eq(started[0], 1, "the game flow starts once")
	eq(seq.stage, "done", "the boot screens fade out and finish")
	seq.free()
	game.save = keep


func test_intro_skippable_after_first_launch() -> void:
	var started := [0]
	var seq := _boot_seq(false, func(): started[0] += 1)
	eq(seq.stage, "intro", "later launches still open on the intro")
	seq.advance(0.1)
	seq.tap()
	eq(seq.stage, "loading", "a tap skips the intro after the first launch")
	seq.tap()
	eq(seq.stage, "loading", "the loading bar cannot be skipped")
	seq.free()


## The bar follows real loading: it never shows more than is loaded, the flow (the first
## screen's build) waits for the threaded loads, and the bar is full only after the build.
func test_loading_bar_follows_real_loading() -> void:
	var started := [0]
	var seq := _boot_seq(false, func(): started[0] += 1)
	seq.tap()
	var ls := seq.loading_screen()
	var real := [0.0]
	ls.warm_progress = func() -> float: return real[0]
	for i in 60:
		seq.advance(1.0 / 30.0)
	eq(started[0], 0, "nothing loaded: the flow waits")
	eq(ls.progress(), 0.0, "nothing loaded: the bar stays empty")
	real[0] = 0.5
	var ahead := false
	for i in 60:
		seq.advance(1.0 / 30.0)
		ahead = ahead or ls.progress() > ls.real_progress() + 0.0001
	check(not ahead, "the bar never runs ahead of the real progress")
	check(ls.progress() > 0.2 and ls.progress() <= 0.5 * LoadingScreen.WARM_SHARE + 0.0001,
		"half loaded: the bar shows half the loading share (got %.3f)" % ls.progress())
	eq(started[0], 0, "half loaded: the flow still waits")
	real[0] = 1.0
	seq.advance(1.0 / 30.0)
	eq(started[0], 1, "everything loaded: the flow builds the first screen")
	check(ls.progress() < 1.0, "the bar is not full the moment the build starts")
	for i in 90:
		seq.advance(1.0 / 30.0)
	eq(started[0], 1, "the flow runs once")
	eq(seq.stage, "done", "after the build the bar fills and the screens fade out")
	seq.free()


## The threaded warm-up loads real files (a missing one never blocks the boot) and keeps
## them cached until the loading screen goes.
func test_loading_warms_real_files_on_threads() -> void:
	var ls := LoadingScreen.new(0, 0, PackedStringArray(["res://assets/icons/gloss/coin.png", "res://nope/missing.png"]))
	var waited := 0
	while not ls.loaded() and waited < 400:
		OS.delay_msec(5)
		ls.advance(0.005)
		waited += 1
	check(ls.loaded(), "the warm-up finishes")
	eq(ls.held_count(), 1, "the real file is held in the cache, the missing one skipped")
	ls.free()



## The warmed resources are handed to the flow when it starts, so a screen shown before the
## first real one (the age screen on a fresh install) keeps them in the cache.
func test_boot_hands_warmed_resources_to_the_flow() -> void:
	var got := [-1]
	var box := []  # lambdas capture locals by value: the sequence is reached through this
	var seq := BootSequence.new(false, func(): got[0] = (box[0] as BootSequence).held.size(), 0,
		PackedStringArray(["res://assets/icons/gloss/coin.png"]))
	box.append(seq)
	seq.write_seen = false
	seq.tap()
	var waited := 0
	while got[0] < 0 and waited < 400:
		OS.delay_msec(5)
		seq.advance(0.005)
		waited += 1
	eq(got[0], 1, "the flow finds the warmed file held for it")
	check(seq.held[0] is Texture2D, "the real resource, not a path")
	seq.free()


## Shot 4 and shot 5 alternate per launch, kept in a tiny user:// file (never the save).
func test_keyart_alternates_per_launch() -> void:
	var path := "user://_test_boot_art.cfg"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var a := LoadingScreen.pick_shot(path)
	var b := LoadingScreen.pick_shot(path)
	var c := LoadingScreen.pick_shot(path)
	eq(a, 0, "the first launch shows the charge")
	eq(b, 1, "the next launch shows the standoff")
	eq(c, 0, "then the charge again")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for s in LoadingScreen.SHOTS:
		check(ResourceLoader.exists(String(s["path"])), "key art %s exists" % s["path"])
		var tex := load(String(s["path"])) as Texture2D
		check(tex != null and tex.get_height() > tex.get_width() * 1.7, "key art %s is a 9:16 portrait" % s["path"])


## Cover-fit: the shot fills any screen, keeps its aspect and its focal point on screen; the
## push-in grows it about the focal point.
func test_keyart_cover_keeps_focus() -> void:
	var tex := Vector2(1152, 2048)
	for view in [Vector2(720, 1280), Vector2(720, 1600), Vector2(960, 1280), Vector2(720, 1080)]:
		for zoom in [1.0, 1.0 + LoadingScreen.PUSH]:
			var focus := Vector2(0.45, 0.47)
			var r := LoadingScreen.cover_rect(tex, view, focus, zoom)
			check(r.position.x <= 0.01 and r.position.y <= 0.01 and r.end.x >= view.x - 0.01 and r.end.y >= view.y - 0.01,
				"the shot covers %s at zoom %.2f" % [view, zoom])
			check(absf(r.size.x / r.size.y - tex.x / tex.y) < 0.001, "the shot keeps its aspect")
			var f := r.position + r.size * focus
			check(f.x > 0 and f.x < view.x and f.y > 0 and f.y < view.y, "the focal point stays on screen")
	var a := LoadingScreen.cover_rect(tex, Vector2(720, 1280), Vector2(0.5, 0.5), 1.0)
	var b := LoadingScreen.cover_rect(tex, Vector2(720, 1280), Vector2(0.5, 0.5), 1.0 + LoadingScreen.PUSH)
	check(absf(b.size.x / a.size.x - (1.0 + LoadingScreen.PUSH)) < 0.001, "the push-in grows the shot by PUSH")
	check((a.get_center() - b.get_center()).length() < 0.5, "the push-in grows about the focal point")



## The shot lights up out of the intro's navy (eased, with the push), never a one-frame cut
## to full brightness; the push and the fade start together when the shot is up.
func test_keyart_fades_up_from_the_navy() -> void:
	var ls := LoadingScreen.new(0, 0, PackedStringArray())
	check(ls.art_ready(), "no threaded request: the shot loads at once")
	eq(ls.art_alpha(), 0.0, "the first frame is the navy")
	ls.advance(1.0 / 60.0)
	check(ls.art_alpha() < 0.05, "one frame in, the shot is barely lit (got %.3f)" % ls.art_alpha())
	var last := ls.art_alpha()
	var smooth := true
	for i in int(LoadingScreen.ART_IN * 60.0) + 2:
		ls.advance(1.0 / 60.0)
		smooth = smooth and ls.art_alpha() >= last and ls.art_alpha() - last < 0.12
		last = ls.art_alpha()
	check(smooth, "it brightens a little each frame")
	near(ls.art_alpha(), 1.0, "fully lit after ART_IN")
	var r0 := ls.shot_rect(Vector2(540, 960), 0.0)
	var r1 := ls.shot_rect(Vector2(540, 960), LoadingScreen.PUSH_TIME)
	check(r1.size.x > r0.size.x * 1.03, "the push-in runs from the shot's first frame")
	ls.free()


## While the shot is still decoding on its thread the screen never waits for it (a tap on the
## intro's first frame): the navy shows, and the shot is taken, then faded up, once it is in.
func test_keyart_is_never_waited_for() -> void:
	var path := String(LoadingScreen.SHOTS[1]["path"])
	ResourceLoader.load_threaded_request(path)
	var ls := LoadingScreen.new(0, 1, PackedStringArray())
	var waited := 0
	while not ls.art_ready() and waited < 400:
		OS.delay_msec(5)
		ls.advance(0.005)
		waited += 1
	check(ls.art_ready(), "the shot arrives")
	check(ls.art_alpha() < 0.1, "and fades up from the moment it arrives (got %.3f)" % ls.art_alpha())
	ls.free()


## 9:20 phones (1080x2400, the most common size): the charge keeps its five figures (heads at 6%
## and 95% of its width) instead of a cover fit cutting the flanking troops in half. It covers
## the width, hangs from the top, and its bottom edge sits where the scrim is already dark.
## On 9:16 it still covers the whole screen.
func test_keyart_keeps_the_squad_on_tall_phones() -> void:
	var tex := Vector2(1152, 2048)
	var s: Dictionary = LoadingScreen.SHOTS[0]
	var keep := float(s.get("keep", 0.0))
	check(keep > 0.0 and keep <= 0.92, "the charge keeps at least 92% of its width")
	for view in [Vector2(1080, 2400), Vector2(1080, 2340), Vector2(1080, 2520), Vector2(720, 1600)]:
		for zoom in [1.0, 1.0 + LoadingScreen.PUSH]:
			var r := LoadingScreen.cover_rect(tex, view, s["focus"], zoom, keep)
			var shown: float = view.x / r.size.x
			check(shown >= keep - 0.001, "%s zoom %.2f: %.0f%% of the width shown" % [view, zoom, shown * 100.0])
			var left := -r.position.x / r.size.x
			check(left <= 0.05 and left + shown >= 0.95, "%s: both flanking heads in frame" % view)
			check(r.position.x <= 0.01 and r.end.x >= view.x - 0.01, "%s: the width is covered" % view)
			check(absf(r.position.y) < 0.01 or r.end.y >= view.y - 0.01, "%s: it hangs from the top" % view)
			check(r.end.y >= view.y * 0.78, "%s: its bottom edge is where the scrim is over half navy (%.0f%%)" % [view, 100.0 * r.end.y / view.y])
	for view in [Vector2(1080, 1920), Vector2(720, 1280), Vector2(1080, 2160)]:
		var r := LoadingScreen.cover_rect(tex, view, s["focus"], 1.0, keep)
		if view.y / view.x <= 16.0 / 9.0 + 0.001:
			check(r.end.y >= view.y - 0.01 and r.position.y <= 0.01, "%s: a 9:16 screen is still fully covered" % view)
		check(absf(r.size.x / r.size.y - tex.x / tex.y) < 0.001, "%s: the shot keeps its aspect" % view)


## The loading bar warms what the first screen loads: a brand-new player's level 1 builds
## every crowd (their meshes and animation textures); anyone else opens on the map.
func test_boot_warms_the_first_screen() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game: Node = tree.root.get_node_or_null("Game")
	var keep: Dictionary = game.save.duplicate(true)
	game.save["unlocked"] = 1
	game.save["stars"] = {}
	var level := BootSequence.default_warm()
	check(level.size() >= 3, "a new player warms the crowds (got %d paths)" % level.size())
	var all_crowds := true
	for p in level:
		all_crowds = all_crowds and p.begins_with(BootSequence.CROWDS) and p.ends_with(".res") and ResourceLoader.exists(p)
	check(all_crowds, "every warmed path is a crowd resource that exists")
	check(level.has(BootSequence.CROWDS + "hero_vat.res"), "the hero's animation texture is warmed")
	game.save["unlocked"] = 5
	game.save["stars"] = {"1": 3}
	var map := BootSequence.default_warm()
	check(not map.is_empty(), "a returning player warms the map")
	var all_map := true
	for p in map:
		all_map = all_map and p.begins_with("res://assets/city/") and ResourceLoader.exists(p)
	check(all_map, "every warmed map path exists")
	game.save = keep


## No wordmark is left anywhere: the logo screen and its art are gone, the light-bar stays
## (the loading bar's front).
func test_no_wordmark_left() -> void:
	check(not ResourceLoader.exists("res://src/ui/title_logo.gd"), "the wordmark screen is gone")
	check(not ResourceLoader.exists("res://assets/brand/siren_squad_logo.png"), "the wordmark image is gone")
	check(ResourceLoader.exists("res://assets/brand/lightbar.png"), "the loading bar keeps its light-bar")


## The rename to Siren Squad keeps the save where it was (%APPDATA%/Godot/app_userdata/Troop).
func test_user_dir_unchanged() -> void:
	var dir := OS.get_user_data_dir().replace("\\", "/")
	check(dir.ends_with("/Troop"), "user dir still ends with /Troop (got %s)" % dir)
	check(dir.ends_with("app_userdata/Troop"), "user dir is still Godot/app_userdata/Troop (got %s)" % dir)
	eq(String(ProjectSettings.get_setting("application/config/name")), "Siren Squad", "app name")


## BRAND: the backup-joins siren chirp is throttled to once per 3 s.
func test_siren_chirp_throttled() -> void:
	var sfx_script = preload("res://src/autoload/sfx.gd")
	check(float(sfx_script.MIN_GAP.get("siren_chirp", 0.0)) >= 3.0, "siren_chirp at most once per 3 s")
	check(ResourceLoader.exists("res://assets/audio/siren_chirp.ogg"), "siren_chirp.ogg exists")
	check(ResourceLoader.exists("res://assets/audio/siren_whoop.ogg"), "siren_whoop.ogg exists")


## BRAND: every loading tip is pictures only, each a real icon (no star_icon fallback), and
## the tap tip uses the HUD's firepower unit (spec v2 §12.4): a tapping hand -> lightning.
func test_loading_tips_use_real_icons() -> void:
	for tip in LoadingScreen.TIPS:
		for it in tip:
			if it == ">":
				continue
			var name := String(it)
			check(ResourceLoader.exists("res://assets/icons/gloss/%s.png" % name)
				or ResourceLoader.exists("res://assets/icons/%s.svg" % name), "tip icon %s exists" % name)
	var tap_tip: Array = LoadingScreen.TIPS[0]
	eq(String(tap_tip[0]), "hand", "the first tip is the tap")
	eq(String(tap_tip[tap_tip.size() - 1]), "power", "tapping raises firepower (the lightning unit)")
	check(LoadingScreen.TAP_ICONS.has("hand"), "the hand in a tip is drawn as a tap (ripple), not a pointer")


## BRAND: the Android preset carries the Siren Squad package and every launcher icon layer,
## including the monochrome one (Android 13 themed icons; unset, Godot ships its own logo).
func test_android_preset_is_branded() -> void:
	var cfg := ConfigFile.new()
	eq(cfg.load("res://export_presets.cfg"), OK, "export_presets.cfg loads")
	eq(String(cfg.get_value("preset.0.options", "package/unique_name", "")), "com.iiakshat.sirensquad", "package ID")
	eq(String(cfg.get_value("preset.0.options", "package/name", "")), "Siren Squad", "app name")
	var sizes := {"launcher_icons/main_192x192": 192, "launcher_icons/adaptive_foreground_432x432": 432,
		"launcher_icons/adaptive_background_432x432": 432, "launcher_icons/adaptive_monochrome_432x432": 432}
	for key in sizes:
		var path := String(cfg.get_value("preset.0.options", key, ""))
		check(path.begins_with("res://assets/brand/"), "%s is a brand icon (got '%s')" % [key, path])
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			eq(tex.get_width(), int(sizes[key]), "%s is %d px" % [key, sizes[key]])
		else:
			check(false, "%s exists" % path)
	var opts := "preset.0.options"
	var bg := Image.load_from_file(ProjectSettings.globalize_path(String(cfg.get_value(opts, "launcher_icons/adaptive_background_432x432", ""))))
	var fg := Image.load_from_file(ProjectSettings.globalize_path(String(cfg.get_value(opts, "launcher_icons/adaptive_foreground_432x432", ""))))
	var mono := Image.load_from_file(ProjectSettings.globalize_path(String(cfg.get_value(opts, "launcher_icons/adaptive_monochrome_432x432", ""))))
	check(bg.get_pixel(0, 0).a > 0.99 and bg.get_pixel(431, 431).a > 0.99, "the background is the art, full bleed")
	var clear := true
	for y in range(0, 432, 9):
		for x in range(0, 432, 9):
			clear = clear and fg.get_pixel(x, y).a < 0.01
	check(clear, "the foreground layer is clear")
	check(mono.get_pixel(4, 4).a < 0.01 and mono.get_pixel(427, 427).a < 0.01, "the themed icon's corners are clear")
	check(mono.get_pixel(216, 280).a > 0.9, "the themed icon is the hero's head in the middle")
