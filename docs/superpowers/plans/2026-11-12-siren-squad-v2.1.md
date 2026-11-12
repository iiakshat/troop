# Siren Squad v2.1 Implementation Plan

> **For agentic workers:** this plan is executed by a multi-agent workflow. There are 7 parallel builders in worktrees off `dev`, then an integrator, reviewers and a fixer. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Real fights (enemies and bosses act before they die, capped and telegraphed), Harder difficulty measured on a player who steers well, a payout that keeps power near the challenge, level archetypes and guest-weapon gifts for variety, and honest hint markers.

**Architecture:** Pure-logic changes in `src/core/` (LevelSim, Autopilot, EconomyMath, BottleLogic, Armory) with tests. A generator mirror and archetype table in `tools/gen_levels.py`. View work in `src/game/` and `src/ui/`. New calibration profiles in `tests/tune.gd`. Every number in `config/`.

**Tech Stack:** Godot 4.7.2 GDScript (Forward Mobile), Python 3 generator, the headless test runner `tests/run_tests.gd`.

**Spec:** `docs/superpowers/specs/2026-11-12-siren-squad-v2.1-tension.md`. The v2 spec still holds except where v2.1 changes it.

## Global Constraints

- Every number lives in `config/`. The arithmetic stays exact. Squads are 64-bit ints, and percentage losses round to whole troops: never negative, never more than the squad.
- Icons and numbers only, no words. Allowed text: rank names on the New Rank card, the axnex logo, gang wave banners.
- No slow motion and no pause mid-level, except first-run tutorials. The gift reveal is inside the finale.
- Every enemy attack is capped as a share of the current squad. No undodgeable one-shot of a hero alone.
- Harder levels never require ads: the stored route at the no-ad pace wins every level.
- No deceptive patterns: honest telegraphs, honest timers, ads optional.
- Original assets only, logged in `ASSETS.md`. Gemini at most what each task allows (shared key).
- Keep each file's line endings. Debug runs use `save=_local/x.json` and never touch the owner's save.
- Tests end "0 failed", except level-balance tests that only calibration (Task 8) can fix: list them.

## Review Focus

1. **A telegraph that is pending during a revive, pause, first-run lesson freeze or the finish.** It must land only in live play time, never through a revive shield's start frame, and never after the finish. Owner: Task 1 (test `test_telegraph_respects_freeze_revive_finish`).
2. **Lane change exactly at landing.** The sim decides the hit by the squad's lane at land time, using the view's real x (`set_squad_x`) in play and lane centres in autoplay. Owner: Task 1 (test `test_dodge_decided_at_land_time`).
3. **100K+ squads.** Percentage caps on huge squads stay exact ints, and one hit is still at least 1 troop. Owner: Task 1 (test `test_caps_exact_on_huge_squads`).
4. **Guest weapon on a replay or restart, and after an Armory purchase.** The gift shows on each attempt (≤1.5 s, skippable) and uses the current Armory tier. The save is unaffected. Owner: Task 5 (test `test_guest_weapon_uses_current_tier`).
5. **A hint whose object dies in the same frame the hint fires.** The marker must never appear, and never re-attach to another object. Owner: Task 6 (test `test_hint_bound_object_dies_immediately`).

---

### Task 1: FIGHT (sim: return fire, specials, bosses, lieutenant, autopilot, generator mirror)

**Files:** `src/core/level_sim.gd` (combat functions only), `config/units.json` (return_fire, enemy attack fields, boss/lieutenant), `src/core/autopilot.gd`, `tools/gen_levels.py` (combat mirror, boss HP rule, `lieutenant_wave`), `tests/test_level_sim.gd`.

**Interfaces (produces):**
- `return_fire` event: `{type, horde, x, z, shots:int, lost:int, blocked:bool, opening:bool}`.
- `telegraph` event: `{type, kind:"snipe"|"grenade"|"firebomb"|"barrage"|"lt_barrage", lane:int, src:horde_id, x, z, land_t:float}`. It replaces `snipe_aim` and `firebomb_throw`.
- `attack_land` event: `{type, kind, lane, lost:int, blocked:bool, hit:bool}`. It replaces `snipe` and `firebomb_hit`.
- `boss_shot` event: `{type, horde, lost:int, blocked:bool}`.
- `horde_spawn` gains `lieutenant:bool`.
- `units.json`:
  - `return_fire {range 50, open 1, max_shooters [3,3,4,5,6], volley_cap_pct 5, figures_shown 72}`
  - per enemy `attack {start_m, warn_s, cap_pct}`
  - `boss {hp_secs [12..15], barrage_every 2.5, warn_s 1.0, barrage_pct, gun_pct, halt_min_s 6}`
  - `lieutenant {...}`
- `gen_levels.lieutenant_wave(level:int, d:int) -> dict` (used by Task 4 at slot 5).
- `Autopilot` gains `dodge_p:float` (constructor kwarg after `taps`) and shield-on-threat logic.

- [ ] Step 1: Write failing tests in `tests/test_level_sim.gd`:
  - `test_return_fire_outranges_squad`: an armed gang on L11-like data fires an opening shot before it dies on the stored route.
  - `test_return_fire_caps_and_figures`: one volley ≤ 5% of the squad; one hit ≥ 1 troop = `ceil(squad/72)`.
  - `test_hero_falls_last_and_not_in_hero_alone_opening`: a do-nothing squad loses followers lowest rank first, then the hero; a hero-alone opening is never one-shot.
  - `test_specials_attack_beyond_range_and_cap`: sniper, grenadier and molotov telegraph from beyond 45 m; a landed attack is ≤ its cap_pct; there is no standoff deadlock beyond 45 m.
  - `test_dodge_decided_at_land_time`
  - `test_telegraph_respects_freeze_revive_finish`
  - `test_caps_exact_on_huge_squads`: a 150,000 squad.
  - `test_boss_hp_not_scaled_and_barrage`: the boss halts ≥ 6 s and fires ≥ 2 barrages on the stored route; a dodger takes 0 from barrages.
  - `test_lieutenant_wave`
- [ ] Step 2: Run them: `"$G" --headless --path . --script res://tests/run_tests.gd -- only=test_level_sim`. They fail.
- [ ] Step 3: Implement in `level_sim.gd`:
  - `_return_fire`: opening, cap, figures, hero-last, grace
  - special attacks as `telegraph` → `attack_land` with caps
  - standoff fix
  - boss/lieutenant barrage and squad-relative gun
- [ ] Step 4: Mirror the rules in `gen_levels.py`: boss HP = `hp_secs` × expected dps, excluded from k×kf. Add `lieutenant_wave`.
- [ ] Step 5: In `autopilot.gd`, add `dodge_p` and the shield on an armed gang in range or a telegraph on its lane.
- [ ] Step 6: Tests pass (list the level-balance failures for Task 8). Commit.

### Task 2: FIGHTVIEW (readable incoming fire, telegraphs, lieutenant look)

**Files:** `src/game/level_view.gd` (combat handlers only), `src/game/fx.gd`, `src/ui/hud.gd` (troop pill pulse), `src/game/crowd.gd` or the boss view (lieutenant tint), `tests/test_view_rules.gd`.

**Interfaces (consumes):** the Task 1 events. Until they exist in your worktree, drive them from a scratch emitter in the tests.

- [ ] Step 1: Failing tests:
  - `test_enemy_tracers_have_own_pool`: enemy tracers never count against the squad's 320 cap; at most 8 per event.
  - `test_minus_n_sums_window`: −N is summed over 0.3 s.
- [ ] Step 2: Implement the visuals:
  - enemy tracers: an orange-red pool, scale ~1.0, about 1 s on screen
  - a bigger muzzle flash
  - a red −N over the squad (also for `boss_shot`)
  - a troop pill pulse
  - a 30 ms vibrate through the existing setting
  - telegraphs: sniper laser on the lane, grenade and firebomb lane marks, boss and lieutenant barrage marks, then the impacts
  - the lieutenant drawn at 2.4× a thug with a distinct tint and a smaller boss bar
  - no slow-down
- [ ] Step 3: Screenshots under `_local/fightview/`: return fire with −N on L11 and L15, each telegraph, the boss barrage on L10, the lieutenant on L15. Use a debug arg that turns powers off under autoplay (add `powers=0` to main.gd if missing; listed).
- [ ] Step 4: Tests pass. Commit.

### Task 3: ECON (payout, gates, idle, model)

**Files:** `src/core/economy_math.gd`, `config/economy.json`, `src/core/bottle_logic.gd` (coins only), `src/ui/result_panel.gd`, `src/core/armory.gd`, `config/armory.json`, `src/ui/armory_panel.gd` (tier lock), `src/ui/station_panel.gd` (training lock), `src/core/city.gd`, `src/autoload/game.gd` (welcome-back away time), `tests/econ_model.gd`, `tests/econ_sim.gd`, `tests/test_economy.gd`.

**Interfaces (produces):**
- `Economy.level_coins(level:int, troops:int, coin_ref:int, hits:int, gold:bool, heat:float, station:float) -> int`. It is the only payout function, used by BottleLogic, the result panel and the model.
- `Armory.tier_unlocked(tier:int, level:int) -> bool`.
- `_local/pace.json` keeps its format, now rebased (§3.5), plus `pace_ads.json`.

- [ ] Step 1: Failing tests:
  - `test_perfect_run_at_most_1_7x`
  - `test_tier_unlock_levels` (tier 2 L9, tier 3 L15, tier 4 L31)
  - `test_training_gated_l2_l3_tap_check`: the L2/L3 stored routes at tap 0 with squad 1-3 lose
  - `test_build_timers_by_district`
  - `test_welcome_back_from_background_time`
  - `test_engaged_power_ceiling`: the engaged no-ad power is ≤ 1.6× recommended
- [ ] Step 2: Implement §3.1-3.4. Fit `base` so the no-ad pace makes 1-3 meaningful buys per win. Refit `recommended` power.
- [ ] Step 3: Rebase `econ_model` per §3.5 and write `_local/pace.json` and `_local/pace_ads.json`.
- [ ] Step 4: Tests pass. Commit.

### Task 4: LEVELS (archetypes, names, unlocks, L1-L3, per-level look and speed, rescue)

**Files:**
- `tools/gen_levels.py` (layout, `ARCHETYPES`, names, L1-L3)
- `config/units.json` (unlock levels only)
- `config/armory.json` (rank track unlocks only, coordinate with ECON's tier field)
- `src/core/level_sim.gd` (per-level `scroll_speed` override and the hostage-cage object only)
- `src/game/world.gd` + `config/world_look.json` (per-level `look`: night, storm)
- the hostage cage view in `src/game/level_view.gd` (contained) or a new `src/game/cage_view.gd`
- `src/ui/city_map.gd` (archetype node icons)
- `tests/test_levels.gd`

**Interfaces:**
- Level JSON gains `archetype:String`, `look:String` (optional), `scroll_speed:float` (optional) and `cage` rows: `{at, lane, hostages:int, guards:horde}`.
- Consumes `gen_levels.lieutenant_wave` (Task 1). Stub it if absent.

- [ ] Step 1: Failing tests:
  - `test_archetype_by_slot`
  - `test_unique_names`
  - `test_new_thing_every_3_levels`: every window of 3 levels from L1-L50 has a first appearance, a new archetype in that district, or a guest weapon (read `finale.json level_weapon` if present)
  - `test_rescue_cage_frees_or_loses`
  - `test_l1_trap_row_and_beats`
- [ ] Step 2: Implement the archetype table, layouts, names, earlier unlocks with hint cards (sniper_foe 15, sniper rank 19, grenadier 22, commando 26), the L1 redesign, the per-level speed and look, the rescue cage (sim + view), and the map icons. Gemini: at most 1 request for archetype icons; vector is fine.
- [ ] Step 3: Screenshots under `_local/levels/`: one per archetype look (night, storm, rush, rescue cage), the L1 trap row, the map with icons.
- [ ] Step 4: Regenerate the levels (uncalibrated is fine), run the tests, commit.

### Task 5: GIFT (guest Bottle Shot weapons as a gift)

**Files:** `config/finale.json` (`level_weapon`, gift timings), `src/core/bottle_logic.gd` (weapon lookup), new `src/finale/gift_reveal.gd`, `src/finale/bottle_shot.gd` (hook), `tests/test_bottle_logic.gd`.

- [ ] Step 1: Failing tests:
  - `test_level_weapon_overrides_district`
  - `test_guest_weapon_uses_current_tier`
  - `test_gift_reveal_skippable_and_short` (≤ 1.5 s)
- [ ] Step 2: Implement the §4.3 schedule and the gift reveal: box drop, wiggle, sparkle open, weapon into the hand, lock + level tease when its Armory track is locked, a tap to skip. Gemini: at most 1 request for the gift box; vector is fine.
- [ ] Step 3: Screenshots under `_local/gift/`: the reveal on L4 and L13, and each guest weapon at its level with every bottle visible (§12.1).
- [ ] Step 4: Tests pass. Commit.

### Task 6: HINTS (bound markers, tones, no lane singled out)

**Files:** `src/ui/new_item_card.gd`, `config/hints.json` (tones, riot icon, `return_fire` and `car` items), `src/ui/tutorial.gd` (ring tones only), `src/core/level_sim.gd` (`_enemy_hints_due` adds the object id only), `tools/gen_levels.py` (HINTS `car` and `return_fire` entries only), `src/autoload/analytics.gd` (`hint_shown`), `tests/test_view_rules.gd`.

- [ ] Step 1: Failing tests:
  - `test_hint_bound_object_dies_immediately`
  - `test_marker_never_reattaches`
  - `test_marker_and_card_same_duration`
  - `test_tone_per_item`
  - `test_two_matching_offers_both_sparkle`
- [ ] Step 2: Implement §6:
  - object binding, a 0.2 s fade, the survivors' centre
  - gain / threat / use chips and card frames
  - gate sign sparkles (no ellipse), obstacle tags
  - tutorial ring tones
  - the riot shield icon
  - `hint_shown`
- [ ] Step 3: Screenshots under `_local/hints/` at 540x960: a gain hint (L4 sergeant), a threat hint (L5 armour), a use hint (L3 barrel), a gang hint as the gang thins, and the L7 riot.
- [ ] Step 4: Tests pass. Commit.

### Task 7: TUNE (calibration profiles and guard checks)

**Files:** `tests/tune.gd`, `tests/test_levels.gd` (the level test's profile checks), `tools/gen_levels.py` (`--merge` reads the new fit fields only).

**Interfaces (produces):**
- `tune.gd profile=greedy|noisy|paced`.
- `calibrate=1` fits per level:
  - the greedy keep share into its band
  - the noisy first-try fail rate (40 runs)
  - random wins ≥ 5%
  - the no-ad guarantee (stored route at `_local/pace.json` upgrades, no powers, wins)
- `checks=1` prints and asserts the §2 guard checks.
- Hard levels = slot 9, lieutenants and bosses (from the level's `archetype` if present, else by slot).

- [ ] Step 1: Failing tests for the greedy pilot (`test_greedy_matches_tutorial_best_lane`) and the band classification.
- [ ] Step 2: Implement the profiles, fits and checks against today's rules. Do not recalibrate the levels.
- [ ] Step 3: Commit, with a dry-run table for L1-L20 in the summary.

### Task 8: INTEGRATE and CALIBRATE (after Tasks 1-7)

- [ ] Merge into dev's current state (which includes the v2 polish round), in order: FIGHT, FIGHTVIEW, ECON, LEVELS, GIFT, HINTS, TUNE.
- [ ] Rebuild the pace (`econ_sim`).
- [ ] Full calibration with the new targets (CLAUDE.md "Level calibration" with `profile=greedy`; boss levels with dodging).
- [ ] Checks green. Tests 0 failed.
- [ ] Autoplays: L1, 5, 10, 11, 15, 21, 31, 41, 50 with no SCRIPT ERROR.
- [ ] Perf runs on L15 and L50.
- [ ] Screenshots of every visible change.
- [ ] Docs: CLAUDE.md status, DECISIONS.md.
