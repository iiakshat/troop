# Siren Squad v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Troop v1.1 into "Siren Squad":
- a branded, smooth runner where tapping powers the hero
- weapons are the coin sink
- clear hints
- the play-test fixes
- real AdMob and Firebase for a mixed audience

**Architecture:**
- New pure logic goes in small tested classes under `src/core/`:
  - `touch_classifier.gd`
  - `armory.gd`
  - `powers_timer.gd`
  - `audience.gd`
- Those classes feed the existing `LevelSim` through its `upgrades` dictionary and two new inputs: `tap()` and gang priority.
- Visuals, UI, brand and SDK work sit on top in their own files.
- Calibration runs last, on the merged result, against one fixed player profile.

**Tech Stack:**
- Godot 4.7.2 (GDScript, Forward Mobile), the headless test runner, and `tests/tune.gd` + `tools/gen_levels.py` for calibration
- Python tools: Gemini sheets, `make_sfx.py`
- AdMob and Firebase Godot Android plugins (Gradle build)

**Spec:** `docs/superpowers/specs/2026-11-12-siren-squad-v2-design.md`. Read it with this plan; section numbers below (§N) refer to it.

## Global Constraints

- Every number lives in `config/`. The arithmetic stays exact: "+N" adds exactly N.
- No words on buttons or game objects. The exceptions are spec v1 §0, one-word rank names on the New Rank card, and the Siren Squad and axnex logos.
- **No `Engine.time_scale` change and no pause during a level**, except first-run tutorial steps. The Bottle Shot finale keeps its slow motion.
- No real gun brand or model names. Calibres are allowed. Weapon art is premium stylised, never photo-real.
- Package ID `com.iiakshat.sirensquad`. App and window name "Siren Squad".
- Children: under 13, or **under 18 when the device region or locale is India**. For children:
  - child-directed ads
  - max ad content rating G
  - non-personalised ads
  - no advertising ID
  - Firebase is never started
- Secrets and `google-services.json` are never committed. `art_src/mixamo/` stays git-ignored.
- Debug and test runs never touch the owner's real save (`save=_local/x.json`).
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push from a builder.
- Godot: `$G` = `../_tools/godot/Godot_v4.7.2-stable_win64_console.exe`.
  - Import after adding any `class_name`: `$G --headless --path . --import`
  - Tests: `$G --headless --path . --script res://tests/run_tests.gd` must end `0 failed`
- Gemini key is shared: few requests, many assets per sheet.

## Review Focus

1. **A fast tap-tap-swipe on a small phone.** Expected: taps fire, the swipe steers, a tap never moves the lane, and a swipe never fires. Test: `test_touch_classifier.gd::test_rapid_taps_then_swipe` (Task 2).
2. **Setting the phone clock back to refill shield and bomb.** Expected: no free refill. A clock that moved backwards keeps the old ready time. Test: `test_powers_timer.gd::test_clock_moved_back_gives_nothing` (Task 6).
3. **An existing v3 save with station knife 7 and garage 3.** Expected: nothing bought is lost. The knife track holds at least the coins spent; garage charges become stored charges. Test: `test_save_data.gd::test_v3_station_converts_without_loss` (Task 6).
4. **A child in India aged 15.** Expected: treated as a child, so Firebase is never started and ads are child-directed. Test: `test_audience.gd::test_india_under_18_is_child` (Task 11).
5. **A non-upgrading player stuck mid district 1.** Expected: replaying earlier levels earns enough to buy the needed step with no ads. Test: `econ_sim` assertion `no_ad_pace_reaches_every_level` (Task 13).

---

## Phase 1: parallel builders

Tasks 1-12 split into builders by the files they own. Tasks in different builders must not edit the same file, except where a task says "minimal edit, listed in deviations".

### Task 1: Tap heat and gang priority in the sim (builder CORE)

**Files:**
- Modify: `src/core/level_sim.gd` (`_init`, `step`, `_shoot`, `_lane_target`, `clone`)
- Modify: `src/core/squad.gd` (`dps`, `pierce_dps`: hero rate multiplier)
- Modify: `src/core/autopilot.gd` (`_init`, `drive`, `run`)
- Modify: `config/units.json` (add `hero.tap`, `world.gang_priority_m`)
- Test: `tests/test_level_sim.gd`

**Interfaces:**
- Produces:
  - `LevelSim.tap() -> void`
  - `LevelSim.tap_heat: float` (0..1)
  - `LevelSim.hero_rate_mult() -> float`
  - `Autopilot._init(lane_choices: Array, powers := true, dodges := false, tap_rate := 4.0)`
  - `Autopilot.run(..., tap_rate := 4.0)`
  - config `units.hero.tap = {auto_rate: 0.4, per_tap: 0.3, decay_s: 1.0}`
  - config `units.world.gang_priority_m = 15.0`
- Consumes: nothing new.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_hero_rate_rises_with_taps_and_decays() -> void:
	var sim := _sim_l1()                      # existing helper style; level 1, no upgrades
	eq(sim.hero_rate_mult(), 0.4, "idle hero fires at auto_rate")
	for i in 8:
		sim.tap(); sim.step(0.25)            # 4 taps/s
	check(sim.hero_rate_mult() > 0.95, "steady 4/s tapping holds full rate")
	for i in 8: sim.step(0.25)               # 2 s idle
	eq(sim.hero_rate_mult(), 0.4, "back to auto_rate after decay")

func test_followers_ignore_tap_heat() -> void:
	# a constable-only squad deals the same dps with and without taps

func test_gang_within_priority_takes_fire_before_red_gate() -> void:
	# red gate at z=-10 in lane, gang front at z=-14 (inside 15 m): target_kind == "horde"
	# same gang at z=-25 (outside 15 m): the red gate is shot first (old rule)
```

- [ ] **Step 2: Run them to make sure they fail.** Run the tests. Expected: FAIL (`tap` not found).
- [ ] **Step 3: Implement.**
  - Heat: each `tap()` adds `per_tap` (capped at 1). `step` decays it linearly to 0 over `decay_s`.
  - `hero_rate_mult = lerp(auto_rate, 1.0, heat)`, applied only to the `hero` unit's rate inside `Squad.dps`/`pierce_dps`, including when the hero holds the PISTOL or SMG pickup.
  - `_shoot`: if the front gang is within `gang_priority_m`, shoot it even if a lane object is nearer.
  - `clone()` copies the heat.
  - The autopilot calls `sim.tap()` at `tap_rate` per second of sim time (0 = never).
- [ ] **Step 4: Run all tests.** Expected: the new tests pass. Existing level tests may now fail on balance; that is expected until Task 13. List which ones fail in the report, and do not re-tune here.
- [ ] **Step 5: Commit** with the message "Sim: tap heat for the hero, gang priority over lane objects".

### Task 2: Tap vs swipe classifier (builder VIEW)

**Files:**
- Create: `src/core/touch_classifier.gd` (`class_name TouchClassifier`, pure, no nodes)
- Modify: `src/game/level_view.gd` (`_unhandled_input`: route touches through the classifier; the lower half of the screen sends taps to `sim.tap()`; drags steer as today)
- Modify: `config/units.json` (`input = {tap_max_px: 15, tap_max_s: 0.25, zone_top: 0.5}`; `tap_max_px` scales with `DisplayServer.screen_get_scale()`)
- Test: `tests/test_touch_classifier.gd`

**Interfaces:**
- Produces:
  - `TouchClassifier.new(cfg: Dictionary)`
  - `press(id: int, pos: Vector2, t: float) -> void`
  - `move(id: int, pos: Vector2, t: float) -> String`, returns `"steer"` once the touch passes the threshold, else `""`
  - `release(id: int, pos: Vector2, t: float) -> String`, returns `"tap"`, `"steer_end"` or `""`
  - `in_zone(pos: Vector2, screen: Vector2) -> bool`

- [ ] **Step 1: Failing tests:**
  - `test_short_still_touch_is_tap`
  - `test_moving_touch_is_steer_and_never_tap`
  - `test_rapid_taps_then_swipe`: 5 taps 0.1 s apart then a 200 px swipe gives 5 × "tap", then "steer", then "steer_end", and no steer events during the taps
  - `test_slow_hold_is_not_tap`: 0.4 s still gives ""
  - `test_second_finger_tap_while_steering`: id 1 steering, id 2 taps; the tap still counts
  - `test_upper_half_tap_is_ignored`
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement the classifier and wire it into `_unhandled_input`.**
  - A tap calls `sim.tap()` and plays the hero hand-flick (Task 4 visual).
  - Steering keeps today's continuous-x behaviour.
  - Keyboard: Space = tap (PC testing).
- [ ] **Step 4: Run the tests.** PASS.
- [ ] **Step 5: Commit.**

### Task 3: Smoothness: no slow-downs, no join hitch (builder VIEW)

**Files:**
- Modify: `src/game/level_view.gd`
  - `_update_time_scale`: delete the spotlight and red-gate 0.3 branches, and the rank spotlight timer at ~line 803
  - only the tutorial hold remains
- Modify: `src/game/crowd.gd`, `src/game/fx.gd` (pre-warm and buffer sizing)
- Modify: `src/main.gd` (debug arg `perf=1`)
- Test: `tests/test_flow.gd` (or new `tests/test_view_rules.gd`)

- [ ] **Step 1: Failing test** `test_level_view_never_slows_time`:
  - build a `LevelView` headless with level 7, autoplay, `tutor` off
  - step 1200 frames
  - assert `_time_scale == 1.0` every frame (expose `time_scale()`)
- [ ] **Step 2: Profile the join hitch** before fixing it.
  - Run: `$G --path . -- level=4 autoplay=1 perf=1 save=_local/p.json --fixed-fps 60 --resolution 540x960`
  - `perf=1` writes `_local/perf.log` with the frame time per frame plus event markers (`rank_joined`, `recruit`, `boss`, `explode`).
  - Record which frames go over 33 ms and the event next to each.
- [ ] **Step 3: Fix the measured causes.** Suspects:
  - first-use materials or shaders: pre-warm every crowd, rank and effect material at level load by rendering one hidden instance for one frame
  - MultiMesh `instance_count` growth: size once to `formation_figures` and the enemy caps
  - per-join node or tween creation: pool them
- [ ] **Step 4: Re-run perf.** Expected: no frame over 50 ms after the first 2 s, on L4, L13, L31 and L50 (record the max per level in the commit message). Tests pass.
- [ ] **Step 5: Commit.**

### Task 4: Street look: camera, formation, heat arc, barrel, boss, smudge, colour (builder VIEW)

**Files:**
- Modify: `src/game/level_view.gd` (camera rig numbers, formation spread, heat arc, hero flick, boss placement before the stash)
- Modify: `src/game/gate_row_view.gd` (explosive barrel model: red drum, hazard-flame decal, fuse ring fills while shot, blinks when armed, blast shows the kill count)
- Modify: `src/game/world.gd` (colour grade per district: fog colour and density, sun tint, exposure, saturation; all values in `config/world_look.json`, new)
- Modify: `config/units.json` (`world.formation_half_width`, roughly lane-wide; see Task 13)
- Create: `config/world_look.json`

- [ ] **Step 1: Camera.** Hero at ~25% of screen height from the bottom, followers ~18-20%. Check with screenshots at L1 and L31 (`--resolution 540x960`).
- [ ] **Step 2: Formation.** Raise `formation_half_width` so a full squad is about one lane wide. `Squad.slot_offset` already reads it. Keep the slot order stable.
- [ ] **Step 3: Smudge.** Reproduce the grey and purple blob with a 150+ squad (L21 autoplay screenshot). Fix the overlap or headgear z-fight at the formation centre.
- [ ] **Step 4: Boss visibility.** At every boss level (10/20/30/40/50) the boss walks out in front of the stash and is fully visible all fight. Take a screenshot of each with `stop_at` near the boss. Each must show the boss model.
- [ ] **Step 5: Barrel** model and states, as in the files above. Contact cost stays as in config. An unarmed barrel blocks like an obstacle with its cost tag, never "rubber".
- [ ] **Step 6: Colour grade.** No orange haze; street, squad, threats and pickups read clearly. Before and after screenshots for districts 1-5 (`tools/preview_world.tscn`).
- [ ] **Step 7: Heat arc** at the hero's feet (cold → hot, from `sim.tap_heat`), plus the hand flick on each tap.
- [ ] **Step 8:** Tests pass. **Commit** after each step.

### Task 5: Armory core (builder ECON)

**Files:**
- Create: `config/armory.json`
- Create: `src/core/armory.gd` (`class_name Armory`, pure)
- Test: `tests/test_armory.gd`

**Interfaces:**
- Produces:
  - `config/armory.json`:
    - `tracks[weapon_id] = {owner: "hero"|rank|"finale_<weapon>", unlock_level: int, tiers: [{name, calibre, dmg_mult, rate_mult, extra:{...}, art: "armory/<id>_t<n>"}], steps_per_tier: 5, cost: {base, growth}}`
    - start with 4 tiers × 5 steps
    - Bottle Shot tracks only use `extra` (magazine, sway, draw).
  - `Armory.level(save: Dictionary, id: String) -> Vector2i` (tier, step)
  - `Armory.cost(id: String, tier: int, step: int, armory_cfg: Dictionary) -> int`
  - `Armory.is_locked(id: String, unlocked_level: int, cfg: Dictionary) -> bool`
  - `Armory.buy(save: Dictionary, id: String, cfg: Dictionary) -> Dictionary`, returns `{ok, evolved: bool, tier, step}` and spends coins
  - `Armory.sim_upgrades(save: Dictionary, cfg: Dictionary) -> Dictionary`, returns `{"weapons": {owner: {dmg_mult, rate_mult}}}` for `LevelSim._init`
  - `Armory.finale_extra(save, weapon) -> Dictionary`
- Weapon names: our own, realistic-sounding, with real calibres. Web-check each for collisions with real products and list the checks in the commit message.

- [ ] **Step 1: Failing tests:**
  - `test_buy_steps_then_evolve`: 5 buys at tier 1 → `evolved == true`, tier 2 step 0, and `dmg_mult` jumps
  - `test_locked_until_unlock_level`
  - `test_cannot_buy_without_coins` (coins unchanged)
  - `test_costs_rise_monotonically`
  - `test_sim_upgrades_change_damage_not_counts`: run L5 with and without a pistol tier 2; the squad count after the "+N" gates is equal and constable dps is higher
  - `test_no_brand_names`: no tier name contains any of "glock", "desert eagle", "mp5", "ak-47", "colt", "beretta", "remington", "barrett", "uzi"
- [ ] **Step 2: Run.** FAIL.
- [ ] **Step 3: Implement.**
  - `LevelSim._init` reads `upgrades["weapons"]` and multiplies each owner's `dmg`/`rate` in `stats`. Coordinate with CORE: this is a **minimal edit in `level_sim.gd` `_init` only**; list it in deviations.
  - Remove `knife`/`speed` from station effects (Task 6 migrates them).
- [ ] **Step 4: Run.** PASS.
- [ ] **Step 5: Commit.**

### Task 6: Powers timer and save v4 migration (builder ECON)

**Files:**
- Create: `src/core/powers_timer.gd` (`class_name PowersTimer`, pure)
- Modify: `src/core/save_data.gd` (`VERSION := 4`, migration), `src/autoload/game.gd` (power API), `config/economy.json` (`powers = {free: {shield:1, bomb:1}, recharge_s: 18000}`; remove the `garage` room, and the `armory`/`range` rooms from `station`)
- Test: `tests/test_powers_timer.gd`, `tests/test_save_data.gd`

**Interfaces:**
- Produces:
  - `PowersTimer.available(save: Dictionary, id: String, now: int, cfg: Dictionary) -> int` (free ready + stored)
  - `PowersTimer.use(save, id, now, cfg) -> bool`: uses a free charge first and starts its 5 h timer, otherwise a stored one
  - `PowersTimer.refill_free(save, id, now, cfg) -> void` (ad reward)
  - `PowersTimer.seconds_left(save, id, now, cfg) -> int`
  - Save fields: `powers = {shield: {stored: int, ready_at: int}, bomb: {...}}`, `last_seen_time` guard (reuse the daily calendar guard)
  - Level start: charges = `available()`. Level end: report the charges used back via `use()`.

- [ ] **Step 1: Failing tests:**
  - `test_free_charge_recharges_after_5h`
  - `test_clock_moved_back_gives_nothing`: use at t=10000, `now=5000` → 0 free; `ready_at` unchanged
  - `test_ad_refill_makes_free_ready_now`
  - `test_stored_used_after_free`
  - `test_v3_station_converts_without_loss`:
    - a v3 save with armory 7, range 4, garage 3
    - after migration, the hero-knife track's spent-equivalent ≥ the sum of `station_cost` for those levels
    - stored shield == ceil(3/2) and stored bomb == floor(3/2) on top of existing items
    - version == 4
- [ ] **Step 2: Run.** FAIL.
- [ ] **Step 3: Implement.** Convert armory and range levels into knife-track steps by coin value, rounding up.
- [ ] **Step 4: Run.** PASS. Fix `test_economy`/`smoke` tests that reference the removed rooms.
- [ ] **Step 5: Commit.**

### Task 7: Armory screen and economy hooks (builder ECON)

**Files:**
- Create: `src/ui/armory_panel.gd`
- Modify:
  - `src/ui/station_panel.gd` (remove the knife, speed and garage rows; link to the Armory)
  - `src/ui/lobby.gd` (Armory button: icon only)
  - `src/core/economy_math.gd` (`squad_power`, `purchases`, `best_purchase`, `best_upgrade_after_loss` include armory steps)
  - `src/ui/booster_panel.gd` / HUD power buttons: show the recharge countdown (a clock icon with h:mm) and "refill with ad" (ad icon)
- Create: `art_src/gen/armory_*.png` (Gemini sheets), `assets/armory/*.png` (sliced, via `tools/slice_icons.py`)
- Test: `tests/test_economy.gd`, `tests/test_retention_ui.gd`

- [ ] **Step 1: Failing tests:**
  - `test_best_purchase_can_be_a_weapon_step`
  - `test_loss_tip_points_at_weapon_when_it_helps_most`
  - `test_armory_panel_shows_lock_and_level` (headless panel build: a locked track shows the lock icon and its unlock-level number)
- [ ] **Step 2: Run.** FAIL.
- [ ] **Step 3: Art.**
  - At most 2 Gemini requests: one sheet per ~14 weapon tiers, premium stylised (Brawl Stars style), on a magenta key.
  - Slice them, log in `ASSETS.md`.
  - The in-level low-poly weapons get a per-tier colour and trim (`weapon_models.gd`; a minimal edit, listed).
- [ ] **Step 4: Panel.**
  - Each weapon card: art, name, calibre, stat bars before ▸ after, the 5-pip step bar and the price.
  - The evolve celebration plays the new art reveal.
  - A locked card shows a lock and "▸ L{n}" (level icon + number).
- [ ] **Step 5: Hero skins** (spec §6). Cosmetic outfits for the current hero model, sold for coins in the existing `src/ui/style_panel.gd`: recolours plus one accessory per outfit, from config `cosmetics`. Test: `test_style_panel_sells_hero_outfit`.
- [ ] **Step 6:** Tests pass, plus screenshots of the panel (fresh save, `coins=5000`). **Commit.**

### Task 8: One clear hint language (builder UX)

**Files:**
- Modify: `src/ui/tutorial.gd`
  - The gesture hand is used only for: swipe, tap-to-fire (new, L1), the bottle weapons and the pistol reload.
  - `gate_pick` becomes chevrons plus a result preview.
  - Remove the hand from every other step.
- Create: `src/ui/new_item_card.gd` (the top-edge card: icon ▸ effect icons and numbers, auto-hides after ~2 s, no freeze) and the gold-outline and "new" burst on the 3D object (a minimal hook in `level_view.gd`, listed)
- Modify: `src/game/level_view.gd` (minimal: level `hint` events open `NewItemCard` and outline the object, instead of the old hand)
- Modify: menu pointers in `src/ui/city_map.gd` and `src/ui/result_panel.gd`: the hand bounces *on* the button, always next to the item icon and the before ▸ after number
- Create: `assets/ui/hand.png`: new glossy cartoon hand with a soft shadow (Gemini sheet shared with Task 7's request if possible, otherwise one request)
- Test: `tests/test_tutorial.gd`

- [ ] **Step 1: Failing tests:**
  - `test_tap_lesson_runs_first_on_level_1`: fresh save; the `tap` step opens, holds, and ends after 3 taps
  - `test_hint_events_open_card_not_hand`: L4 sergeant hint → `NewItemCard` visible, no hand node, `time_scale` 1.0
  - `test_gate_pick_uses_chevrons`: no hand during `gate_pick`
- [ ] **Step 2: Run.** FAIL.
- [ ] **Step 3: Implement.**
  - Card content per hint id comes from a table in `config/hints.json` (new): icon, effect icons, numbers. Example: barrel → shoot, fuse, blast "N".
  - The barrel gets its one-time first-run gesture lesson (shooting it), which is allowed to pause.
- [ ] **Step 4:** Tests pass, plus a `tutor=auto` screenshot sequence on a fresh save (L1, L3, L4). **Commit.**

### Task 9: Bottle Shot fixes only (builder FINALE)

**Files:**
- Modify:
  - `src/finale/bottle_mesh.gd` / `bottle_shot.gd`: remove the visible rectangles behind bottles on Mobile and GL. Find the quad: glass refraction or backdrop.
  - `src/finale/weapon_bow.gd`: the camera stays still while aiming; at least 3 bottles in view; a real arrow model (head, fletching, shaft); the wind HUD shows an arrow sized to strength and hides when it's 0; every quiver arrow can be shot
  - `src/finale/weapon_models.gd`: premium stylised pistol and bow from primitives plus bevels and materials, positioned so they never cover targets (checked against bottle screen rects)
  - `src/finale/finale_hud.gd`
- Test: `tests/test_bottle_logic.gd`

- [ ] **Step 1: Failing tests:**
  - `test_bow_all_arrows_usable`: `BottleLogic` with the bow and 6 arrows allows 6 shots
  - `test_wind_zero_hides_indicator` (a HUD state function)
- [ ] **Step 2:** Implement. Before and after screenshots for L11 (pistol) and L21 (bow) with `strike=1`, plus one real-input bow screenshot mid-draw.
- [ ] **Step 3:** No other finale changes. Tests pass. **Commit.**

### Task 10: Brand (builder BRAND)

**Files:**
- Modify:
  - `project.godot`: `config/name="Siren Squad"`; **keep the save path**: set `application/config/use_custom_user_dir=true`, `custom_user_dir_name="Troop"`
  - `export_presets.cfg`: `package/unique_name="com.iiakshat.sirensquad"`, `package/name="Siren Squad"`, adaptive icons
- Create:
  - `src/ui/boot_intro.gd`: the axnex intro, ~2 s; a tap skips it after the first launch (`seen_hints` id `intro`)
  - `src/ui/title_logo.gd`
  - `src/ui/loading_screen.gd`: siren light-bar progress and icon-only tips
- Modify:
  - `src/main.gd`: the boot order is intro → logo → loading → the existing flow (minimal edit, listed). Autoplay and headless skip it.
  - `tools/make_sfx.py`: add `siren_whoop` (intro) and `siren_chirp` (backup joins; throttled to once per 3 s in `sfx.gd`)
- Create:
  - `assets/brand/axnex.svg`, `assets/brand/siren_squad_logo.png`
  - `assets/brand/icon_fg.png` / `icon_bg.png`
  - `art_src/brand/feature_graphic.png` (1024×500)
- Test: `tests/test_flow.gd`

- [ ] **Step 1: Failing tests:**
  - `test_boot_shows_intro_then_logo_on_first_launch`
  - `test_intro_skippable_after_first_launch`
  - `test_user_dir_unchanged`: `OS.get_user_data_dir()` ends with `/Troop`
- [ ] **Step 2: Implement.** The logo motif is a police light-bar in blue and red.
  - The axnex mark is a vector wordmark we draw. Animation: a light sweep, then a siren-light flash, with `siren_whoop`.
  - Log the assets in `ASSETS.md`. Add the brand words exception to spec v1 §0.
- [ ] **Step 3:** Tests pass, plus screenshots of the intro, logo and loading screen. **Commit.**

### Task 11: Audience and age screen (builder SDK)

**Files:**
- Create:
  - `src/core/audience.gd` (`class_name Audience`, pure)
  - `src/ui/age_screen.gd`: a birth-year wheel, numbers only, neutral; shown once on first launch, before any SDK starts
- Modify: `src/autoload/game.gd` (stores `birth_year` and `is_child` in the save), `src/main.gd` (minimal: show it before boot popups)
- Test: `tests/test_audience.gd`

**Interfaces:**
- Produces:
  - `Audience.is_child(birth_year: int, now_year: int, region: String, locale: String) -> bool`: under 13, or under 18 when `region == "IN"` or `locale` ends with `_IN`
  - `Game.is_child() -> bool`
  - `Game.audience_ready` signal

- [ ] **Step 1: Failing tests:**
  - `test_under_13_is_child`
  - `test_india_under_18_is_child`
  - `test_adult_outside_india`
  - `test_unknown_age_treated_as_child`
- [ ] **Step 2:** Implement. **Step 3:** Tests pass. **Commit.**

### Task 12: AdMob and Firebase behind the existing interfaces (builder SDK)

**Files:**
- Modify: `src/autoload/ads.gd` (provider switch: `placeholder` | `admob`), `src/autoload/analytics.gd` (provider: `local` | `firebase`)
- Create: `config/ads.json` (Google's official **test** app ID and unit IDs; `child_tags`), `addons/<admob plugin>/`, `addons/<firebase plugin>/`, `android/` (Gradle build template)
- Modify:
  - `export_presets.cfg`: `gradle_build/use_gradle_build=true` and the plugin toggles
  - `build_apk.bat`: install the Android build template if missing
- Create:
  - `docs/PRIVACY.md`
  - `docs/play_data_safety.md`
  - `docs/families_checklist.md`
  - `docs/owner_ads_setup.md`: the owner's 10-minute checklist (create the AdMob app and units, the Firebase Android app with `com.iiakshat.sirensquad`, drop `google-services.json` into `android/build/`, and where to paste the IDs)
- Test: `tests/test_ads.gd`

- [ ] **Step 1: Choose the plugins.** They must support Godot 4.7.2 Android, be maintained, and support child-directed or under-age tags, max content rating, non-personalised requests, UMP consent, and turning off ad-ID collection. Record the choice and its licence in `ASSETS.md`/`DECISIONS.md`.
- [ ] **Step 2: Failing tests:**
  - `test_child_request_config`: `Ads.request_config(is_child=true)` gives `{child_directed: true, max_rating: "G", npa: true}`
  - `test_adult_request_config`
  - `test_firebase_not_started_for_child`: `Analytics.provider_for(is_child=true) == "local"`
  - `test_placeholder_when_plugin_missing`: on PC and headless the provider is `placeholder`, and the existing ad tests still pass
- [ ] **Step 3: Implement.**
  - The adult path shows the UMP consent form before the first ad in GDPR regions.
  - Ad-ID collection is always off in the Firebase config.
  - Tap analytics events (`tap_rate` per level, in 10 s buckets) go only to the local log for children.
- [ ] **Step 4:**
  - Tests pass.
  - The `build_apk.bat noinstall` Gradle build succeeds with the test IDs.
  - `google-services.json` is absent from git (`git check-ignore android/build/google-services.json`).
- [ ] **Step 5: Commit.**

---

## Phase 2: integrate and calibrate (one agent, after Phase 1)

### Task 13: Merge, profile and recalibrate all 50 levels

**Files:**
- Modify: `tests/tune.gd`, `tests/econ_sim.gd`, `tools/gen_levels.py`, `config/levels/*`, `config/levels/calibration.json`, `config/armory.json` (prices), `config/economy.json`

- [ ] **Step 1: Merge the builder branches** in the order CORE, ECON, VIEW, UX, FINALE, BRAND, SDK.
  - Resolve conflicts keeping both intents.
  - Restore each file's original line endings.
  - Import, then run the tests.
- [ ] **Step 2: `econ_sim` no-ad pace.**
  - Simulate a player who wins each level once (with replays when stuck), earns coins with **no ads**, and buys by `best_purchase`.
  - Output per level: the expected armory state.
  - Assert `no_ad_pace_reaches_every_level`: the expected armory state at each level is affordable from no-ad earnings, allowing at most 2 replays of earlier levels.
  - Write `_local/pace.json`: level → upgrades dictionary.
- [ ] **Step 3: Profile in `tune.gd`.** `profile=paced` uses `pace.json` upgrades, `tap_rate=4` and `powers=false`. Calibrate (`calibrate=1`, then `--merge`, then plain, then `--merge`) against the spec v1 §3 win curve with this profile.
  - The gentle need for upgrades starts at about L5-L7: the same profile with **zero** upgrades must lose at least one of L5-L10, and lose more often after that.
- [ ] **Step 4: Extra checks** (add to `test_levels_are_winnable_and_reward_planning`):
  - the stored route wins with the paced profile and **no powers**
  - a non-tapper (`tap_rate=0`) with paced upgrades wins every level from L6
  - a non-tapper loses L2 and L3
  - L1 is won with light tapping (`tap_rate=1.5`)
- [ ] **Step 5: Off-curve levels.** If any level stays more than ±10 points off its target after calibration (watch L12, L22, L23 and L30), change the generator's wave mix or row count for it in `gen_levels.py` and repeat.
- [ ] **Step 6: Wider formation.** Re-check `formation_half_width` (Task 4) and the obstacle-capacity tests together.
- [ ] **Step 7: Finish.**
  - Headless autoplay with `strike=1` of L1, 5, 10, 11, 21, 31, 41 and 50: all reach the result with no `SCRIPT ERROR`.
  - A `perf=1` run of L13 and L50 with no frame over 50 ms after 2 s.
  - Update `CLAUDE.md` (name, status, commands: `perf=1`, age screen, providers), `DECISIONS.md` and `ASSETS.md`.
  - **Commit.**

## Phase 3: review and fix

### Task 14: Three reviews, then fixes

- [ ] **Gameplay and feel review.** Check every spec section is delivered. Screenshots of L1 (fresh save, tutorials), L4, L10, L21 and L50, plus the Armory and the boot sequence. Check tap feel with the classifier tests and a `tap_rate` sweep in tune.
- [ ] **Code review.** Review `git diff dev...HEAD` for crashes, sim/view desync, migration edge cases, clock exploits, the SDK child path (assert Firebase is never initialised for a child), and per-frame allocations.
- [ ] **UX and rules review.**
  - no words beyond the exceptions
  - every hint matches §11's language
  - no mid-level slow-down
  - every panel closable
  - no deceptive patterns: the ad refill is optional and the timer is honest
- [ ] **FIX.** Fix blockers, majors and cheap minors. Tests end `0 failed`. Re-run tune if balance changed. **Commit.**

## Phase 4: ship (main session)

- [ ] Fast-forward `dev`, re-import, run the tests.
- [ ] Run `build_apk.bat noinstall`: the Gradle build with test ad IDs.
- [ ] Fast-forward `main`, then push both with the per-command auth header.
- [ ] Report to the owner per spec section, plus the owner checklist (`docs/owner_ads_setup.md`, the ipindia.gov.in name check).
- [ ] When the owner's Mixamo files arrive, start a separate round per spec §9.
