# CLAUDE.md: TROOP (working title)

> Live file. Keep it current in the same session as any decision or status change. Shared basics are in `../COMMON.md`; the business background is in `../CLAUDE.md`. The owner's live instructions win over both. Design psychology brief: `PSYCH.md` (read it fully before design work). Reasons for every choice: `DECISIONS.md`. The v1 contract: `docs/superpowers/specs/2026-11-08-troop-v1-design.md`; what each v1 builder did: `docs/v1_builder_reports.md`.

Last updated: 2026-11-09

## What this is

A 2.5D arithmetic army game for Android (portrait, offline). The squad stays put at the bottom of a city street and slides between 3 lanes. Pickups, gangs, obstacles and red gates come towards it. The squad fires all the time: one bullet or knife per troop. Between levels the player rebuilds a ruined city.

- **Hero:** an ordinary guy in casual clothes who always throws knives. A PISTOL pickup gives him a gun for that level.
- **Allies (ranks, unlock by level):** Constable (pistol), Sergeant (shotgun, L4), Inspector (revolver, pierces armour, L7), SWAT (rifle burst, L13), Sniper (L21), Commando (launcher splash, L31). Numbers in `config/units.json`; the Codex shows each as "= N constables".
- **Enemies:** Thugs, Knifers, Gunmen, Brutes (armour halves damage), riot, biker, Molotov (firebombs a lane), sniper_foe (laser, then a kill), Grenadier, and a boss per district (walks in shooting, big HP bar).
- **Gate rows:** offers (+N, ×k, recruits, weapons, powers, foe mods) in 1-2 lanes only; the others hold obstacles (pothole, barricade, red gate, car, barrel). A rare "lucky row" has offers in all 3.
- **Powers:** SHIELD and BOMB charges; boosters (head start, +shield, +bomb) are taken in before a level.
- **End of level:** Bottle Shot finale (knife throws at bottles, multiplier), then 1-3 stars from the share of the peak squad still standing.
- **Meta (v1):** a city map of 5 districts × 10 levels. Each district boss (L10/20/30/40/50) liberates it. 25 buildings are rebuilt with coins (build timers) and earn coins per hour into capped storage. Police Station upgrades (10 levels per room, gated by district). Daily 7-day calendar, 3 daily missions, lucky spin, star chests, Codex.
- **Money:** ads only, as **stubs**: every ad opens a blank placeholder popup with a countdown (rewarded 5 s, interstitial 3 s). Google ads get connected at the end (owner).

## Status

- **2026-11-09, v1.0 (integration, branch `v1-integrate` + builder worktrees):** the full loop is wired in `src/main.gd`:
  - Boot → welcome back (offline city coins) → daily calendar (once a day, if claimable) → city map. A brand-new player goes straight into level 1, then result → map.
  - Map Play → BoosterPanel → level (boosters applied) → finale → `Game.win_level` (coin curve, stars, unlocks, mission stats) → result (x2 rewarded ad) → star chest if one is ready → interstitial (Ads rules) → map, where the pin hops to the new level; Next also opens that level's boosters. After a district boss: LiberationPanel, then the map scrolls to the district.
  - Loss → RevivePanel once per level (rewarded ad, +50% of the peak squad) → "so close" result.
  - Mission stats: kills per enemy kind, bottles, gold bottles, wins, 3 stars, bombs and shields used; city coins, builds and upgrades are recorded by Game itself.
  - Placeholder ad popup at every placement in normal play; autoplay and headless skip it.
- **2026-11-09, merge-verify:** SIM-FINISH (all 50 levels calibrated, stored winning routes), VIEW (crowds and effects for every new rank/enemy, boss bar, district themes, `rank_joined`, `revive()`), WIRE (flow) and AUDIO (real recordings for every spec id, Lyria loops) are merged. 121 tests pass. Autoplay without `lanes=` drives the level's stored `route`; `chain=N` plays L1 onward unattended. Revive shield is 4 s (outlasts one molotov throw). The Gang HQ sign is an icon.
- **Known open items:** planned routes still finish at ~85-100% of their peak squad (spec wanted 30-60%; needs an owner design call, see DECISIONS.md); L23 is harder and L12/20/26/31 easier than their win targets; the owner has not listened to the new sounds yet.
- **Not done:** real ads and analytics SDKs, store listing, real-device performance check on low-end phones, package ID, name check.
- **2026-11-08, v0.3:** Vulkan Mobile look, Gemini-painted facades, toon crowds, Bottle Shot with refractive glass, station redesign, recorded gunshots.
- **APKs are built locally** (owner's choice, 2026-11-08): GitHub Actions is refused for the whole account ("locked due to a billing issue"), so `build_apk.bat` builds on the laptop. The CI workflow stays in the repo for when billing is fixed.

## Commands

- Play on PC: double-click `play.bat` (arrows or A/D or swipe to change lane, S = shield, B = bomb). `play.bat -- lobby=1` opens the map; `-- coins=2000` unlocks everything for testing.
- Android APK: `build_apk.bat` runs the tests, exports `build/troop-debug.apk` at low CPU priority, and installs it on a USB-connected phone if there is one (`build_apk.bat noinstall` skips that). One-time setup: `python -I tools/setup_android.py` (adb, apksigner, a Java 17 runtime into `../_tools`, the Godot Android templates and a debug keystore).
- Art with Gemini (shared key, keep requests few, many assets per sheet): `python -I tools/gemini_image.py <out.png> <aspect> <prompt.txt> [--ref img]`; sheets live in `art_src/gen/`, then `tools/slice_env.py` / `tools/slice_icons.py` / `tools/slice_city.py`.
- Levels: `python -I tools/gen_levels.py` regenerates `config/levels/level_1..50.json`.
- Re-bake characters after editing `config/characters.json`: `$G --headless --path . --script res://tools/bake_vat.gd [-- only=hero]`; preview: `$G --path . res://tools/preview_chars.tscn -- clip=run`.
- Previews: `tools/preview_ui.gd` (any retention panel), `tools/preview_world.tscn` (district themes), `tools/preview_finale.tscn` (Bottle Shot).
- Godot: `../_tools/godot/Godot_v4.7.2-stable_win64_console.exe` (call it `$G`).
- Import: `$G --headless --path . --import` (also after adding a new `class_name` file).
- Tests: `$G --headless --path . --script res://tests/run_tests.gd`
- Tuning report: `$G --headless --path . --script res://tests/tune.gd -- [level=N | levels=A-B] [upgrades=k,s,q] [out=x.json]` (run 6 processes over level ranges; ~2 min).
- Level calibration (after any change to `units.json`, `level_sim.gd` or the generator): `tune.gd calibrate=1 out=...` per range, then `python -I tools/gen_levels.py --merge <outs>`, then a plain `tune.gd out=...` run (this records the winning `route`/`route_np`), then `--merge` again. Levels stuck at the gang-scale floor: `calibrate=1 ratio=0` on top. `config/levels/calibration.json` holds each level's scale and stored routes; uncalibrated levels regenerate byte-identically.
- Debug args after `--` (see the top of `src/main.gd`): `level=N autoplay=1 lanes=2,1,1 strike=1 boosters=headstart,bomb report=1 revive=1|auto stop_at=win|loss|revive frames=N screenshot=path shots=100,200 out=prefix lobby=1 reset=1 coins=N save=path.json ads=1 panel=station|style|settings|daily|missions|spin|codex|booster|chest|welcome|revive|liberation|map|ad|interstitial`. `save=` plays on a copy of a JSON save and never writes. Any run with autoplay, level, coins, reset, stop_at, frames, shots, screenshot, chain, boosters or district plays on a throwaway copy of the real save and never writes it (`write=1` persists on purpose, `real_reset=1` wipes the real save); autoplay/save runs log analytics to `user://events_debug.log`. For screenshots add `--always-on-top --position 0,0 --fixed-fps 60 --resolution 540x960`. Autoplay ignores mouse and touch and skips boosters, revive and ads.
- Delete `%APPDATA%\Godot\app_userdata\Troop\save.json` to test as a new player (a new player skips the menu). Agents: still pass `save=_local/x.json` (a missing file = blank player, never written) so runs do not depend on the owner's progress. The save is written atomically (`save.json.tmp`, then renamed; the previous file stays as `save.json.bak` and is loaded if `save.json` is broken).

## Code layout

- `src/main.gd`: the app flow (boot popups, map, boosters, level, revive, result, chest, interstitial, liberation) and debug args.
- `src/core/`: pure logic, no nodes, tested. `squad.gd` (army maths), `level_sim.gd` (the whole battle), `autopilot.gd` (bot and headless runner), `bottle_logic.gd`, `config.gd`, `save_data.gd` (v3 + migration), `economy_math.gd` (coin curve, station costs and gates, chests), `city.gd`, `daily.gd`, `missions.gd`, `spin.gd`, `rewards.gd`.
- `src/autoload/`: `game.gd` (configs, save and the meta API, see its header), `ads.gd` + `ad_placeholder.gd` (stub ads and the popup), `analytics.gd` (JSON lines in `user://events.log`), `sfx.gd` (sounds and music modes).
- `src/game/`: visuals. `level_view.gd` (binds the sim to the visuals, handles input), `crowd.gd`/shaders (VAT crowds on MultiMesh), `world.gd` (street and district themes), `gate_row_view.gd`, `fx.gd`.
- `src/finale/`: Bottle Shot (cameras, glass, shatter).
- `src/ui/`: `lobby.gd` + `city_map.gd` + `building_panel.gd` (the map lobby), `station_panel.gd`, `style_panel.gd`, `settings_panel.gd` (credits), `hud.gd`, `result_panel.gd`, `retention_panel.gd` (shared base) with `daily, missions, spin, booster, revive, codex, star_chest, welcome_back, liberation` panels and `rank_toast.gd`, `ui_kit.gd`.
- `config/`: `units.json` (combat numbers, stars, revive), `economy.json` (coins, curve, station, city, daily, missions, spin, chests, boosters, ads), `finale.json`, `levels/level_N.json`.

## Rules for this game

- Every number lives in `config/`. After changing a level, run `tune.gd` and keep `test_levels_are_winnable_and_reward_planning` passing.
- The arithmetic must stay exact (see DECISIONS.md). Never fake an outcome.
- No words on buttons or game objects (owner). Icons and numbers only; exceptions are listed in the spec §0.
- Engagement without deception: no fake countdowns, disguised or unclosable ads, confirm-shaming, or misleading odds (spec §0).
- Original assets only; log anything new in `ASSETS.md`; CC BY items also go into `SettingsPanel.CREDITS`.
- Git: local config is iiakshat / jakshat569@gmail.com. Remote `iiakshat/troop` (public). Work on `dev` only; after a green local `build_apk.bat`, fast-forward `main` to `dev` and push both. Push with the token in `.env` via a per-command auth header.
