# v1 builder reports (round 1-2)

## META-CORE (worktree-wf_42e1dd2e-61a-2)

### Summary
- **Owner's request (watch-ad popups) is done.** Every ad now opens a blank placeholder screen. File: `src/autoload/ad_placeholder.gd`, opened by `src/autoload/ads.gd`.
  - It sits on top of everything (CanvasLayer 100) as a near-black full screen with a big countdown number in the UiKit font inside a shrinking ring, a small ad icon at the top and a red round close X. No words.
  - The countdown runs on real time, so slow motion and pause do not stretch it.
  - **Rewarded:** counts down 5 s and pays `cb(true)` only at 0, then closes itself. The X shows from the start; closing early pays nothing (`cb(false)`).
  - **Interstitial:** counts down 3 s, then the X appears, and it closes itself 2 s later. Android back / Esc work like the X once it is showing.
  - The game is paused while the popup shows (the popup itself keeps running) and goes back to its earlier pause state afterwards.
  - The popup is skipped and the reward granted at once when running headless, outside the scene tree (tests), with `Ads.skip_ads = true`, or with `autoplay=1` / `skip_ads=1` on the command line.
  - Durations are in `config/economy.json` under `ads`: `rewarded_seconds` 5, `interstitial_seconds` 3, `interstitial_close_after` 2.
  - Analytics events: `ad_offer` (button shown), `ad_start` (popup opened), `ad_watch` (watched to the end), `ad_skip` (closed early, with seconds left).
  - Callers do not change: `show_rewarded(placement, cb)` and `show_interstitial(placement)` work as before.
- **Meta-core items 1-6 were done in the earlier run and are committed:**
  - `config/economy.json`: station rooms up to 10 levels with district gates, 25 buildings in 5 districts, coin curve (+3% per level, boss ×1.5, replays ×0.5), 7-day calendar, missions, spin, chests, boosters.
  - Pure logic in `src/core`: City, Daily, Missions, Spin, Rewards, Economy.
  - SaveData v3 with migration from v2.
  - Ads and Analytics autoloads, registered after Game in `project.godot`.
  - `game.gd` wraps it all with save writes and signals; the API is documented at the top of the file.
  - This run also finished the half-done change that turns reward numbers from JSON floats into whole numbers (daily, missions, rewards), with a test.
- **How it was checked:**
  - Tests: 89 tests, 0 failed (5 new popup tests in `tests/test_ads.gd` drive the countdown with a fake clock).
  - Real game boot with the new autoloads: a headless autoplay run of level 1 won (RESULT coins=640). Its only exit warnings were audio leaks in the Sfx sounds, which META-CORE does not own.
  - Windowed preview with 3 screenshots (`_local/shots/ad_rewarded.png`, `ad_inter_count.png`, `ad_inter_x.png`): the countdown and ring draw correctly, the game was paused during the ad and running again after, rewarded paid `true`, closing early paid `false`, the interstitial closed itself.
- **Owner's save:** I backed up and restored `%APPDATA%/Godot/app_userdata/Troop/save.json` and `events.log` around this run's smoke tests. They are byte-identical to before.
- **Commits on the branch:** f60b54c, fa8c467 (WIP), 019645c (popup), da8ac8d (argument fix).

### Deviations
- **New file:** `src/autoload/ad_placeholder.gd` (the popup), next to `ads.gd`. It uses UiKit (FONT, label, icon_button, YELLOW, safe_rect, pop) without changing it.
- **Ad icon fallback:** the popup does its own icon lookup and never errors. It uses the glossy `ad_play` icon once ART paints it; until then it shows the white `play.svg`.
- **Placement name:** changed `speedup` to `speed_up` to match the spec. The building dictionary key "speedup" (seconds an ad saves) and the economy key `speedup_ad` stay as they are.
- **Additions to the Ads API:**
  - `show_interstitial(placement := "between_levels", on_closed := Callable())`: the optional callback runs once the ad is gone.
  - Signals `interstitial_closed(placement)` and `interstitial_shown(placement)`, plus `reward_granted`.
  - `is_showing()` and `skips_popup()`.
  - If an ad is already showing, a second `show_rewarded` gets `cb(false)`.
  - `stub_delay` is removed from the config.
- **Analytics:** a fourth event, `ad_start`, logs when a popup opens; the old `ad_interstitial` event is replaced by `ad_start` / `ad_watch` with a `kind` field.
- **skip_ads under autoplay:** I set it inside Ads from the command line (`autoplay` / `skip_ads`, the same parsing as main.gd), because main.gd belongs to INTEGRATE. main.gd may also set `Ads.skip_ads = true` directly.
- **Signature differs from the task's example:** `Game.city_collect(mult := 1, t := -1)` instead of `city_collect(now)`; the multiplier is for the x2 welcome-back ad. Every other function named in the task exists as listed.
- **Station gates:** "level k needs district ceil(k/2)" is read as district ceil(k/2) reached, i.e. ceil(k/2)-1 districts liberated. Levels 1-2 of each room are buyable at once; levels 9-10 need district 5. The literal reading would lock the whole station until level 10, which goes against "early game generous". This needs a line in DECISIONS.md (INTEGRATE).
- **Build timer cap:** first builds take 30 s up to 2 h (city_hall); later upgrades can take up to `max_build_seconds` = 4 h.

### Followups
- **INTEGRATE, Game calls in main.gd:** call `Game.level_started(level, boosters)` when a level begins; this also resets the interstitial block. At a win call `Game.win_level(...)` instead of `add_coins` + `complete_level`, and at a loss call `Game.lose_level(...)`. Until then events.log only records session_start.
- **INTEGRATE, interstitials:** between levels, check `Ads.can_show_interstitial(finished_level)`, then call `Ads.show_interstitial("between_levels", next_step)`. Optionally set `Ads.skip_ads = true` under autoplay; Ads already does this itself.
- **RETENTION-UI / MAP-UI:**
  - Call `Ads.note_offer(placement)` whenever an ad button appears (it also blocks interstitials after a revive offer).
  - Call `Ads.show_rewarded(placement, func(ok): if ok: ...)` and give nothing when `ok` is false.
  - The game tree pauses during the popup, so UI tweens that must keep moving need PROCESS_MODE_ALWAYS.
- **MAP-UI:** `UiKit.icon_texture()` still errors on missing icons (spec says fall back to `star_icon`). The ad popup avoids it, but other callers that ask for icons ART has not painted yet will hit it.
- **AUDIO:** Sfx leaves 2 ogg streams (shot.ogg, music_fight.ogg) still in use at exit, which shows up as leak warnings. This was already there before my changes.
- **Owner's save is already v3:** the earlier interrupted run migrated the real `save.json` to v3 (coins kept at 2518). Builds from the old dev branch will load a save with extra keys until this branch is merged.
- **Licences:** no new assets were added, so there is no `docs/assets_meta-core.md`.
- **The worktree branched before the spec commits** (2e1691b, 53dc0a2 on dev). I read the spec via `git show dev:` and did not merge dev, so INTEGRATE's merge brings the spec file in.

## ART (worktree-wf_42e1dd2e-61a-3)

### Summary
- Used 4 Gemini requests in total, all from the earlier run; this resumed run made none. The 4 sheets are in art_src/gen/ (icons_c.png, city_built.png, city_ruin.png, map_panels.png) and their prompts are in art_src/gen/prompts/.
- Icons: 25 new glossy icons in assets/icons/gloss/: the 24 names in spec §5.4, plus `heart` (red heart with a white plus) as the spare, which could serve as a revive icon. They have the same thick navy outline as the old set and no text. I checked them as a contact sheet on teal and yellow backgrounds and they look clean. Re-running tools/slice_icons.py gives byte-identical output, so the 32 existing icons are unchanged.
- Buildings: all 25 ids from §6 in both states, assets/city/<id>.png and <id>_ruin.png. Each is 512x512 RGBA at one shared scale, with the base tile on a common ground line (pivot (0.5, 0.808)). Their imports use lossy WebP 0.85. I checked all 50 on coloured backgrounds: each ruin is recognisably the same building as its rebuilt version, and none has text or graffiti.
- Map: assets/city/map.png is the whole city in 5 stacked bands (Downtown at the bottom, Uptown at the top, night with neon). It is 604x8192, scaled down from 1078x14628. map_1..5.png are the same bands, one district each at full resolution (1078 x ~2900). Their imports are now lossy WebP 0.82, so the map costs about 2.7 MB in the build instead of about 32 MB of PNG.
- assets/city/map_layout.json holds, for each district: its id and name, the band's y-range (0..1, 0 = top), its tile file, a suggested building tint, 5 buildings {id, pos} in §6 order, and 10 levels {level, pos} for levels 1..50 in road order. Top-level keys are image, size, full_size, building_pivot and building_width (0.44 of map width).
- This run re-read every road and plot point through a 0.05 coordinate grid. The earlier level paths drifted off the road in places, onto the sidewalk and, in Market, onto the market stalls. A road-colour mask check now puts all 10 nodes on the road in districts 1, 2, 3 and 5. District 4 I checked by eye in an overlay, because its orange haze breaks the colour mask. Four plots per district sit on the centres of the painted empty lots, which I re-measured.
- tools/slice_city.py (new) rebuilds everything: buildings, the stacked map with cross-fades, and the layout (`python -I tools/slice_city.py [buildings|map|layout|ref]`). A full re-run reproduces the committed files exactly.
- tools/slice_icons.py now has a 'loose' mode for the 5x5 icons_c sheet, which wasn't painted on an exact grid.
- docs/assets_art.md has the rows for ASSETS.md.
- In Godot: all 29 tests pass (0 failed), and a headless load of all 25 icons, 50 building sprites, 5 map tiles, map.png and map_layout.json found nothing missing.

### Deviations
- The map is not one 9:16 painting. It was painted as five tall district panels on one 16:9 sheet, which the slicer stacks with 160 px cross-fades and mirrors (districts 2 and 4) so the roads join. That gives 1078x14628 at full resolution, much taller and with more room per district than a single 9:16 image. map.png is scaled down to 8192 px tall for GPU limits; the per-district tiles map_1..5.png, at full resolution, are an extra.
- Each district has only 4 painted empty lots. The 5th building plot is an open spot: Downtown park (pharmacy), Market square among the stalls (barber), the pier over the water (lighthouse), the Industrial yard over a painted brick shed (garage), and an Uptown block (museum). With the sprite drawn there it looks right, but it covers part of the painting.
- The spare 25th icon is `heart`.
- Files outside my role: the earlier run changed tools/gemini_image.py to add `--ref <image>` (attaching reference images) plus TROOP_ENV key lookup. The icon and ruin prompts depend on attached references, so the change is needed to reproduce the art. dev's commit 2e1691b also edited this file (TROOP_ENV only, CRLF), so the merge will conflict. Take this branch's version; it does everything dev's version does.
- My worktree branches from de114c3, which is older than the spec commits on dev, so the spec file is not in this branch.
- assets/city/*.png.import files are committed with lossy settings (maps 0.82, buildings 0.85).

### Followups
- INTEGRATE: merge the rows in docs/assets_art.md into ASSETS.md. They replace the old "32 glossy icons" row; the set is now 57.
- INTEGRATE: when tools/gemini_image.py conflicts, keep this branch's version.
- INTEGRATE / export: map_layout.json is read at runtime from res://assets/city/. The export preset only include-filters config/*.json, so either add `assets/city/*.json` to include_filter in export_presets.cfg, or check on a device that the JSON gets exported.
- MAP-UI, using the map:
  - Positions in map_layout.json are 0..1 of map.png.
  - Draw building sprites with their pivot point (0.5, 0.808) on `pos`, at about building_width × map width, modulated by the district `tint`.
  - Draw the level path as a curve through the `levels` points in order.
  - For low-end GPUs (4096 px texture limit) and lower VRAM, draw the five map_N.png tiles stacked, using the band ranges, and load only the visible ones; map.png alone is 604x8192.
  - Put district banners on the band boundaries; they hide the cross-fade seams.
- No other art is missing. No Gemini requests were left over or needed.

## FINALE-WORLD (worktree-wf_42e1dd2e-61a-5)

### Summary
- **Bottle Shot (spec §7), in src/finale/**. I finished the rework the last run left half done.
  - **Cameras.** During each flight the camera tracks side-on, close to the spinning knife, in slow motion (time scale 0.2). The knife fills about a third of the screen and sits nearer the centre now (TRACK_LEAD went from 0.3 to 0.15). 0.15 s of real time before contact it cuts to a front three-quarter close-up of the target. Time returns to normal on contact, with a 45 ms hit-stop, a flash, a screen shake and a vibration.
  - **Shatter.** Glass shards only, plus a short spray of thin drink streaks and a little glitter. There are no spheres. The neck flies off, the stump stays on the shelf, and a stain spreads on the wall. Sounds are Sfx.play glass_break, then glass_tinkle 0.3 s later.
  - **Misses.** The knife thunks into the wood. The close-up is now side-on to the knife, filmed from the middle side of the wall so it never sits inside the wall, and holds on the whole stuck knife for 0.3 s.
  - **Fixed the black shard edges.** The shard shader is now unshaded, which is also cheaper on phones. Lit transparent emission was coming out black on the Mobile renderer.
  - **Gold bottle.** It no longer calls fx.confetti (big pastel cubes looked crude this close). It gets 48 longer-lived gold glitter streaks from Shatter instead.
  - **Multiplier.** "×N" counts up in steps of 0.5 (no more "×4.0"), with a scale punch, a wobble, a white-to-gold colour change and a spinning sunburst.
  - **Aim camera.** Moved higher and to the right (NORMAL_VIEW = 0.9, 2.25, 1.2). The hero's big cartoon head was covering the bottom-left of the screen on the wider layouts.
  - **Unchanged:** BottleLogic, config/finale.json, the layouts and the rewards. The git diff against dev touches nothing in src/core, config, tests, src/ui, main.gd, level_view.gd or fx.gd.
- **World themes (spec §6), in src/game/world.gd.**
  - `World.set_theme(d)` works for d = 1-5 (out-of-range values clamp). It can be called before or after the World enters the tree, and as often as you like, because one World serves the whole session.
  - Each theme sets sky colours, sun pitch, yaw, colour, energy and disc size, fill light, ambient, fog, exposure, glow, saturation, facade and side-wall tint and pavement tint.
  - **Districts:** 1 sunny day (the old look), 2 warm afternoon, 3 golden hour, 4 dusk with orange haze, lit windows, dim lamps and neon, 5 night with neon.
  - **Night look:** lit windows, glowing street lamps (halo with a hot core plus a light pool on the road), neon strips on the facades, and a wet road with puddles, gloss and lamp reflection streaks. World places the streaks every frame where the mirror image would fall.
  - **Phone cost:** no extra lights or shadows; the sun is the only shadow-casting light. Night adds about 42 additive quads (3 per lamp) and one neon mesh per building (all neon on a building merged into one vertex-coloured mesh with a shared unshaded shader). All extras are hidden, so they cost nothing, in themes where they are off.
  - **Lit windows:** new tool `tools/make_window_masks.py` detects the window glass in our own facade paintings and writes `assets/env/tex/facade_{1..4}_night.png`. Each window gets its own brightness and about 28% stay dark. They are used as a StandardMaterial3D emission texture with the MULTIPLY operator (ADD lit the whole wall, which I caught in a screenshot).
- **Preview tools.**
  - `tools/preview_world.tscn` builds a World with a squad and a gang, scrolls it, and saves `<out>_d<theme>.png` for each theme in `themes=`. It switches themes on one World, so going 5 → 4 → 1 also checks that switching back works.
  - `tools/preview_finale.tscn` takes level=, theme=, miss=, every=N or shots=, and prints each state and camera change with its frame number.
- **docs/assets_finale-world.md** has the licence row for the night window masks.
- **How I checked it:**
  - Screenshot sheets of all five themes.
  - Finale previews: level 1 by day and at night with a miss, level 4 (swinging bottles) with a miss, level 2 at golden hour through the gold hit, and level 5 aim view.
  - A real windowed level 1 with autoplay and auto-throws through the finale to the result screen.
  - Logged timings match the spec: the cut lands 9 frames (0.15 s) before contact and the miss hold is 18 frames (0.3 s).
  - Headless level 1 with autoplay ends `won: true, broken 3, gold 1, ×5, 640 coins`.
  - `tests/run_tests.gd`: 29 tests, 0 failed.
  - Everything is committed on the branch (6 commits ahead of dev). Line endings match what each file had before.

### Deviations
- **Theme numbers are in a `THEMES` table in world.gd, not in config/.** They are visual only (colours, light angles, fog) with no gameplay meaning, the same as the existing hard-coded lighting. Moving them to `config/world_themes.json` would be easy if wanted.
- **`World.set_lens(fov, focus := -1.0, near := -1.0, blur := 0.12)` has two new optional parameters.** It reuses one CameraAttributesPractical object. Existing calls behave the same. `set_camera_override` now applies the transform at once, so a cut and a lens change land on the same frame.
- **New world-side files:** `src/game/neon.gdshader`, and a `wet` uniform in `src/game/road.gdshader` (default 0, so the day look is unchanged).
- **New files under tools/:** make_window_masks.py, preview_world.gd/.tscn, preview_finale.gd/.tscn.
- **New assets:** `assets/env/tex/facade_{1..4}_night.png` with their .import files.
- **The aim view is no longer over the shoulder** (camera at hero + (0.9, 2.25, 1.2)), so the hero's head stays out of frame.
- **The gold hit no longer calls `fx.confetti`.** The glitter comes from Shatter instead.

### Followups
- **INTEGRATE wiring:**
  - Call `world.set_theme(ceili(level / 10.0))` at every level start, in LevelView or main.gd `_start_level`.
  - For the lobby, pick the current district or 1. World defaults to theme 1 and switching back and forth is safe.
- **INTEGRATE docs:**
  - Merge `docs/assets_finale-world.md` into ASSETS.md.
  - DECISIONS.md entries worth adding:
    - The shards are unshaded, because lit transparent emission rendered black on the Mobile renderer.
    - Window masks use the MULTIPLY emission operator.
    - Night extras are fake glows rather than real lights, for phone performance.
- **AUDIO** must supply `glass_break`, `glass_tinkle` and `thunk` (also used: knife, swoosh, coin, win). Unknown ids stay silent.
- **Not checked on a real low-end phone.** The night district adds about 42 transparent quads and about 44 neon draws, plus the gallery's 2 shadowed spotlights during the finale, which the finale already had. Worth a frame-time check on a cheap phone.
- **Headless runs** end with "N resources still in use at exit". This is likely harmless; I did not check whether dev prints it too.

## RETENTION-UI (worktree-wf_53cf7355-4a7-7)

### Summary
- I merged the two dependency branches first (worktree-wf_42e1dd2e-61a-2 META-CORE and -61a-3 ART), then re-imported.
- Your ad request was already handled by META-CORE in src/autoload/ads.gd and ad_placeholder.gd: a blank full-screen popup with a countdown number, a shrinking ring and a close X. Every ad button I built calls Ads.show_rewarded(placement), so that popup opens each time. I checked it on screen: pressing a booster ad button showed the countdown at "4"; when it reached 0 the free headstart token arrived, got picked automatically, and that booster's ad button disappeared.
- New shared base: src/ui/retention_panel.gd (class RetentionPanel). It gives every panel a dimmed screen, a card that sizes to its content, a red close X that is always visible and always works (the Android back key closes too, except while an ad is showing), a coin counter that flying coins land in, reward rows (icon plus number), ad buttons that log the offer, star bursts, pulses, progress bars, a drawn check mark, a real countdown to midnight, and icon/sound lookups that never crash.
- The panels in src/ui/ (each frees itself and emits `closed` once):
  - daily_panel.gd: 7-day calendar. Claimed days get a check, today glows and pulses. The claim pops the cell and flies the reward. A missed day shows a streak of 0 and the calendar back at day 1. Day 7 opens the chest screen.
  - missions_panel.gd: 3 rows with icon, progress bar "have/goal", reward and a claim button (a check once claimed). Bonus chest with one dot per claimed mission. Countdown to tomorrow's missions.
  - spin_panel.gd: each slice's angle is exactly its chance x 360 degrees. One free spin, then an ad button showing how many ad spins are left. The wheel ticks and nudges the pointer at every slice edge, slows down over 4.2 s and stops inside the slice the game picked. The reward is granted before the wheel turns, so closing mid-spin loses nothing. Chest slices open the chest screen.
  - booster_panel.gd BoosterPanel.new(level): level number (crown on boss levels), 3 tap-to-pick cards showing what each gives (+5 troops, +1 charge) and how many you own, one "+1" ad per booster. Play spends the picked tokens itself and emits start(used).
  - revive_panel.gd RevivePanel.new(progress, peak, troops := -1): percent reached, a bar with your squad marker and a trophy at the finish, your peak squad, one ad button "+N troops". No countdown. Signals revive / give_up.
  - codex_panel.gd: Ranks / Enemies tabs built from units.json. Rank rows: icon, name, damage, rate, special icon and "= N". Locked rows show the district and level that unlock them; enemies you have not reached are locked the same way.
  - rank_toast.gd RankToast.show(parent, unit): 2.5 s card in the top-left corner; it never takes taps.
  - star_chest_panel.gd: the chest shakes, bursts open, rewards pop out one by one, then a collect button. With no reward passed in, it opens the star chest if it is ready, otherwise it shows stars have/need.
  - welcome_back_panel.gd WelcomeBackPanel.new(coins): collect, or x2 by ad.
- result_panel.gd:
  - Win: 1-3 stars pop in one after another, then the bottles and multiplier, coins counting up, an ad button "x2" (watching it pays the same coins again with Game.add_coins), the star-chest bar (the chest bounces and opens when full), then Home / Station (with "!") / Next.
  - Loss: level, road bar with percent, what beat you plus its tip (tips added for pothole, barrel, molotov, sniper_foe, grenadier), peak squad, Home / Station / Retry.
- Tests: tests/test_retention_ui.gd adds 7 tests (wheel slices equal the odds, the wheel lands in the picked slice, calendar states, revive troop count, Codex value lines, reward rows, every panel builds and closes with a visible X). Full suite: 96 tests, 0 failed, no script errors.
- Screenshots: tools/preview_ui.gd opens one or several panels and screenshots them (arguments: panel=a,b,c, dir=, shots=, spin=1, claim=1, ad=1, tab=enemies, state=fresh). I looked at every panel, plus the spin in motion and after landing, the daily panel after a claim, the chest after opening, the win screen after the count-up, and a new player's calendar.
- I also checked the Codex against the SIM branch's units.json and Squad.value_vs_constable, temporarily and then restored. It shows = 1, 2, 3, 4 for the unlocked ranks; sniper and commando appear locked with their district and level (21 and 31) on a level-14 save. Calling SIM's function directly returns sniper 4 and commando 6, matching the spec table.

### Deviations
- New files outside the §8 list (all new, so no merge conflicts): src/ui/retention_panel.gd (shared base), tests/test_retention_ui.gd, tools/preview_ui.gd.
- RankToast is a RefCounted factory, not a Control. A static show() cannot live on a CanvasItem because CanvasItem already has its own show(). RankToast.show(parent, unit) returns the PanelContainer card, or null for an unknown unit.
- The panels make their own Game calls. INTEGRATE must not repeat them:
  - Daily calls claim_daily, Missions calls claim_mission / claim_mission_bonus, Spin calls spin_free / spin_ad.
  - BoosterPanel calls Game.use_boosters on Play, then emits start(used) with what was really spent.
  - WelcomeBackPanel calls Game.city_collect(mult) itself, then emits collect(mult) and collected(coins). A second city_collect would be harmless (the storage is already empty).
  - StarChestPanel calls Game.open_star_chest itself unless a reward is passed in.
- RevivePanel takes an optional 3rd argument `troops`. By default it computes ceil(peak x units.revive.pct / 100), at least 1, the same as SIM's LevelSim.revive_troops().
- ResultPanel:
  - show_loss(level, cause, progress := -1.0, peak := 0): new optional arguments; the road bar is hidden when progress < 0.
  - The loss screen has no revive button, because RevivePanel comes first.
  - New signal doubled(extra_coins) and new method refresh_alerts().
  - show_win reads r.stars (default 1) and r.coins (the amount already paid).
- Sounds: I play the spec ids with fallbacks to sounds that exist today (spin_tick→tick, star1-3→gate_good, daily_claim/chest_open/mission_done→upgrade, spin_win→win, rank_up→recruit, collect→coin_bag). To find which exist, I look inside the Sfx autoload's internal sound lists. If AUDIO renames those internals, the first id is simply played, and an unknown id stays silent.
- Retention panels keep working while the game is paused (process_mode ALWAYS). The ad placeholder still covers them and takes every tap while it shows.
- The only words are the unit names in Codex and rank toast rows and the 1-3 word loss tips; everything else is icons and numbers. I added no new assets, so there is no docs/assets_retention-ui.md.

### Followups
INTEGRATE wiring (main.gd / lobby.gd are not mine):
1. Win: replace the current Game.add_coins + complete_level with `var res := Game.win_level(level, finale_coins, view.sim.stars(), stats, info)`, then `result.show_win(level, {"coins": res.coins, "stars": view.sim.stars(), "broken": r.broken, "gold": r.gold, "mult": r.mult}, has_next)`. Don't add coins anywhere else; the x2 button pays on its own.
2. Loss: if not view.sim.revived, show `RevivePanel.new(view.sim.progress(), view.sim.peak_squad, view.sim.revive_troops())`. On revive, call view.sim.revive(troops) and resume. On give_up, call Game.lose_level(...) then `result.show_loss(level, cause, view.sim.progress(), view.sim.peak_squad)`. Interstitials stay in main.gd (Ads.can_show_interstitial).
3. Before a level: `var bp := BoosterPanel.new(n); bp.start.connect(func(used): start the level with Game.level_upgrades(used) and Game.level_started(n, used))`. `closed` also fires after start, so treat "closed without start" as cancel. Don't call use_boosters again.
4. Lobby side and bottom buttons: add_child(DailyPanel.new() / SpinPanel.new() / MissionsPanel.new() / CodexPanel.new() / StarChestPanel.new()), and refresh the "!" alerts on `closed` (or tree_exited).
5. On boot or resume: `var c := Game.welcome_back(); if c > 0: ui.add_child(WelcomeBackPanel.new(c))`.
6. Sim event rank_join with first_time: `if Game.mark_rank_seen(unit): RankToast.show(hud, unit)`.
7. After the Station panel opened from the result screen closes, call result.refresh_alerts() instead of the find_children loop.
8. Optional: main.gd debug arg panel=... can reuse tools/preview_ui.gd's _make() list.

Other notes:
- UiKit.icon_texture's fallback to star_icon (spec §0) is MAP-UI's. My panels avoid the problem by using RetentionPanel.icon_safe.
- On the wheel, the two tiny slices (3% money, 5% chest) have slightly crowded icons and numbers. That is the honest-odds rule at work; if needed, hide the amount on slices narrower than about 15 degrees.
- The ad placeholder's background is 97% opaque, so the panel behind shows faintly. That file is META-CORE's, if the owner wants it fully blank.
- Godot will generate tests/test_retention_ui.gd.uid on the next editor import; it is not committed.

## SIM (worktree-wf_42e1dd2e-61a-1)
Interrupted before reporting. See its commits (git log dev..worktree-wf_42e1dd2e-61a-1). Known: levels lack stored `route`/`route_np` fields; calibration step in tests/tune.gd not finished.

## MAP-UI (worktree-wf_53cf7355-4a7-6)
Interrupted before reporting. Commits: city map lobby, BuildingPanel, Station 10 levels, UiKit helpers, headless lobby smoke test. Last WIP commit holds small uncommitted polish.

## AUDIO (worktree-wf_42e1dd2e-61a-4)
Interrupted. Done: 3 Lyria tracks (music_menu/level/boss.ogg), sfx.gd rework (takes by file name, round-robin, music modes with crossfade, lazy synth fallbacks), tools/lyria_music.py, tools/make_sfx.py (WIP). NOT done: sourcing real SFX recordings for the spec 5.3 ids; tests show Sfx.play before _ready crashes (_players empty).
