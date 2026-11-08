# CLAUDE.md: TROOP (working title)

> Live file. Keep it current in the same session as any decision or status change. Shared basics are in `../COMMON.md`; the business background is in `../CLAUDE.md`. The owner's live instructions win over both. Design psychology brief: `PSYCH.md` (read it fully before design work). Reasons for every choice: `DECISIONS.md`.

Last updated: 2026-11-08

## What this is

A 2.5D arithmetic army game for Android (portrait, offline). The squad stays put at the bottom of a city street and slides between 3 lanes. Pickups, gangs and red gates come towards it. The squad fires all the time: one bullet or knife per troop.

- **Hero:** an ordinary guy in casual clothes who always throws knives. A PISTOL pickup gives him a gun for that level.
- **Allies (ranks):** Constable (pistol, 1 damage), Inspector (revolver, 3 damage, pierces armour). More ranks and weapons later.
- **Enemies:** Thugs (crowd), Knifers (fast), Gunmen (stop and shoot; SHIELD blocks them), Brutes (armour 1: pistols and knives do nothing).
- **Pickups:** +N troops (drawn as the people waiting), ×k, -N and -% (red; shoot them up, and past zero they become troops), GANG ÷k and NO ARMOUR (apply to the next gang), PISTOL, +BOMB.
- **Powers:** SHIELD (4 s, blocks all hits) and BOMB (kills 50% of the nearest gang, minimum 10).
- **End of level:** a needle swings over a ×1/×2/×3/×5 bar. Tap to stop it; coins = 40 + troops × multiplier. Then the Gang HQ explodes.
- **Lobby:** coins buy Knife Power, Throw Speed and Starting Squad (capped). No merging (owner).
- **Money:** ads only (interstitials plus rewarded). **Not in the build yet**; Google ads get connected at the end (owner).

## Status

- **2026-11-08, v0.3 (round-3 feedback, on `dev`, APK built locally):**
  - Fixes: camera stuck in the finale view after level 1; armour now halves damage instead of blocking it (level 5's Kingpin could not die); notch-safe HUD; drag-to-steer; one knife per bottle; single knife whoosh.
  - Look: Vulkan Mobile renderer with shadows, glow and ACES; Gemini-painted facades and ground; toon-shaded, outlined crowds (sRGB fix); glossy Gemini icons, and road signs use icons, never words.
  - Feel: no sideways body twist; bodies topple, lie, then dissolve; big crowds shrink a little; squad cap 150 with a HUD bar.
  - Bottle Shot: refractive glass, layout-fitted telephoto lens, lit plank gallery, shards and splash.
  - Station: before ▸ after rows, Barracks (squad cap), "!" badges, reachable from the result screen.
  - Sound: recorded gunshots.
  - **Waiting on the owner: Mixamo characters and animations** in `art_src/mixamo/{characters,anims}` (list in chat, 2026-11-08). The bake tool needs a Mixamo path (textures, UVs) when they arrive.

- **2026-11-08, v0.2 (in progress, on `dev`):** owner's round-2 feedback is done:
  - Honest row-by-row melee, 45 m lane-first bullet streams.
  - New SWAT, riot, biker, boss, turncoat, SMG, barrels, cars.
  - 5 tuned levels.
  - Quaternius characters as VAT crowds, Kenney/KayKit city.
  - Bottle Shot finale.
  - Police station (6 rooms) and cosmetics (5 outfits, 5 knife skins).
  - Bright-cartoon icon UI, recorded CC0 SFX and music.
  - One-time icon hints.
  - 28 tests pass; every level plays end to end headless (autoplay + finale).
- **APKs are built locally** (owner's choice, 2026-11-08): GitHub Actions is refused for the whole account ("locked due to a billing issue"), so `build_apk.bat` builds on the laptop. The CI workflow stays in the repo for when billing is fixed (each push currently fails there, which is harmless).
- **Not done:** analytics, ads, store listing, real-device performance check on low-end phones, package ID, name check. Gunshots are still synthesised (CC0 firearm library is 194 MB, not pulled).
- **v0.1 (earlier):** first playable, 3 levels, procedural box characters.

## Commands

- Play on PC: double-click `play.bat` (arrows or A/D or swipe to change lane, S = shield, B = bomb). `play.bat -- lobby=1` opens the menu; `-- coins=2000` unlocks everything for testing.
- Android APK: `build_apk.bat` runs the tests, exports `build/troop-debug.apk` at low CPU priority, and installs it on a USB-connected phone if there is one (`build_apk.bat noinstall` skips that). One-time setup: `python -I tools/setup_android.py` installs only adb, apksigner (build-tools 36), a Java 17 runtime into `../_tools` (~280 MB), the Godot Android templates (only those files, ~220 MB) and a debug keystore, and points Godot's editor settings at them. No Android Studio, NDK or Gradle.
- Art with Gemini (shared key, keep requests few, many assets per sheet): `python -I tools/gemini_image.py <out.png> <aspect> <prompt.txt>`; sheets live in `art_src/gen/`, then `tools/slice_env.py` / `tools/slice_icons.py`.
- Re-bake characters after editing `config/characters.json`: `$G --headless --path . --script res://tools/bake_vat.gd [-- only=hero]`; preview: `$G --path . res://tools/preview_chars.tscn -- clip=run`.
- Godot: `../_tools/godot/Godot_v4.7.2-stable_win64_console.exe` (call it `$G`).
- Import: `$G --headless --path . --import`
- Tests: `$G --headless --path . --script res://tests/run_tests.gd`
- Tuning report (every lane combination of every level): `$G --headless --path . --script res://tests/tune.gd -- [level=N] [upgrades=k,s,q]`
- Debug args after `--`: `level=N autoplay=1 lanes=2,1,1 strike=1 (autoplay the bottle throws) report=1 frames=N screenshot=path shots=100,200 out=prefix lobby=1 reset=1 coins=N panel=station|style|settings`. For screenshots add `--always-on-top --fixed-fps 60 --resolution 540x960` (a covered window stops rendering). Autoplay ignores mouse and touch.
- Delete `%APPDATA%\Godot\app_userdata\Troop\save.json` to test as a new player (a new player skips the menu).

## Code layout

- `src/core/`: pure logic, no nodes, tested. `squad.gd` (army maths), `level_sim.gd` (the whole battle), `autopilot.gd` (bot and headless runner), `config.gd`, `save_data.gd`.
- `src/game/`: visuals. `level_view.gd` (binds the sim to the visuals, handles input), `humanoid.gd` and `crowd.gd`/`.gdshader` (box people on a MultiMesh, animated on the GPU), `world.gd` (street), `gate_row_view.gd` (pickups), `fx.gd` (projectiles, particles).
- `src/ui/`: `hud.gd`, `lobby.gd`, `result_panel.gd`, `ui_kit.gd`. `src/autoload/`: `game.gd` (configs and save), `sfx.gd` (synth audio).
- `config/`: `units.json` (all combat numbers), `economy.json` (coins, upgrades, strike bar), `levels/level_N.json` (events; each `at` = the distance at which it reaches the squad).

## Rules for this game

- Every number lives in `config/`. After changing a level, run `tune.gd` and keep `test_levels_are_winnable_and_reward_planning` passing.
- The arithmetic must stay exact (see DECISIONS.md). Never fake an outcome.
- No floating words on game objects (owner). Numbers on pickups and gangs only.
- Original assets only; log anything new in `ASSETS.md`.
- Git: local config is iiakshat / jakshat569@gmail.com. Remote `iiakshat/troop` (public). Work on `dev` only; after a green local `build_apk.bat`, fast-forward `main` to `dev` and push both. Push with the token in `.env` via a per-command auth header.
