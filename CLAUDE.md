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

- **2026-11-08, v0.1.0:** first playable. 3 levels (First Blood, Brass, Kingpin), lobby with upgrades, strike bar, result screens, pause, synthesised sound, haptics. 14 headless tests pass. All 3 levels win on autoplay with the planned routes (L1 33 troops, L2 24, L3 68).
- Owner's first look (popup window): "looks cool". Feedback applied: no slow motion, recruits as people with a "+N" tag instead of gates, no floating words, small squad counter in a corner. Still open: **characters don't look good yet** (owner).
- **Not done:** Android APK pipeline (needs a GitHub repo, so ask the owner first), analytics, ads, store listing, real-device performance check, package ID, name check.

## Commands

- Play on PC: double-click `play.bat` (arrows or A/D or swipe to change lane, S = shield, B = bomb). `play.bat -- lobby=1` opens the menu.
- Godot: `../_tools/godot/Godot_v4.7.2-stable_win64_console.exe` (call it `$G`).
- Import: `$G --headless --path . --import`
- Tests: `$G --headless --path . --script res://tests/run_tests.gd`
- Tuning report (every lane combination of every level): `$G --headless --path . --script res://tests/tune.gd -- [level=N] [upgrades=k,s,q]`
- Debug args after `--`: `level=N autoplay=1 lanes=2,1,1 strike=1 report=1 frames=N screenshot=path shots=100,200 out=prefix lobby=1 reset=1`. For screenshots add `--always-on-top --fixed-fps 60 --resolution 540x960` (a covered window stops rendering). Autoplay ignores mouse and touch.
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
- Git: local config is iiakshat / jakshat569@gmail.com. No remote yet.
