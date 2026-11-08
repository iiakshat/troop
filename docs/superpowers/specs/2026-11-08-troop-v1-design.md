# Troop v1.0: full game design and build contract

Date: 2026-11-08. Owner direction (round 4): "build an end-to-end game, not a prototype; make it very addictive and high revenue." Meta chosen by owner: **Rebuild the city**. This document is the single contract all builders work to. Where it is silent, use judgment consistent with it, `CLAUDE.md`, `PSYCH.md` and `DECISIONS.md`.

## 0. Non-negotiables (every builder)

- Godot 4.7.2, Mobile renderer, portrait 720x1280. Godot binary (absolute): `C:/Users/Akshat/Desktop/programs/Gems/_tools/godot/Godot_v4.7.2-stable_win64_console.exe` (call it `$G`). In a fresh worktree run `$G --headless --path . --import` once before anything else. Tests: `$G --headless --path . --script res://tests/run_tests.gd` must end `0 failed`.
- Every number lives in `config/`. Pure logic lives in `src/core/` (no nodes) and gets tests.
- Arithmetic stays exact (see DECISIONS.md). Never fake an outcome.
- **No words on game objects or buttons.** Icons and numbers. The only text allowed: numbers, the game title, gang banners, 1-3 word loss tips, legal credits, and in the Codex/rank cards at most ~3 words per line next to numbers ("= 3 constables").
- Original or licensed assets only; add a row to `ASSETS.md` for anything new; CC BY items also go into `SettingsPanel.CREDITS`.
- Missing assets must never crash: `UiKit.icon_texture()` falls back to `star_icon`; `Sfx.play()` of an unknown id is silent.
- **Engagement without deception** (Google Play policy and India's 2023 dark-pattern guidelines). Allowed and wanted: variable rewards, daily streaks, goal-gradient progress bars, offline storage caps, build timers, star chests, near-miss revives, opt-in rewarded ads at moments of high want, interstitials only at natural breaks. Forbidden: fake countdowns, disguised ads, ads that cannot be closed, confirm-shaming copy, spin wheels whose slice sizes misrepresent odds, hidden costs, reward bait-and-switch. Spin wheel slice size = true probability.
- Ads and analytics are **stubs** behind interfaces (`Ads`, `Analytics` autoloads). No SDKs. Owner connects Google ads at the end.
- Git: work only in your worktree branch; commit there with messages ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push. Never touch `.env`. Report your branch name and a summary of what you built, what you couldn't, and any contract deviations.
- Gemini (images) and Lyria (music) use a **shared key**: only the ART and AUDIO builders may call them, few requests, many assets per image. Key file: set env `TROOP_ENV=C:/Users/Akshat/Desktop/programs/Gems/Troop/.env` (worktrees have no .env). Never print the key.

## 1. The player's loop

1. **Level** (60-90 s): steer the squad through gate rows, shoot gangs, Bottle Shot finale. Ends with 1-3 stars and coins.
2. **Result**: coins count up; "x2" rewarded-ad button (stub); stars; Next.
3. **City map** (the lobby): a vertical scrolling map of 5 districts x 10 levels = 50 levels. Beating a district's 10th level (district boss) liberates it. Each district has 5 buildings that start ruined; coins rebuild them (with a short build timer). Built buildings earn coins per hour while away, into a storage that caps (come back to collect).
4. **Police Station**: squad power upgrades (more levels, costs grow, gated by district progress).
5. **Daily**: 7-day login calendar, 3 daily missions, 1 free lucky spin (+3 ad spins).
6. **Boosters before a level**: head start / extra shield / extra bomb, from tokens or a rewarded ad (owner asked for "ads to get headstart, or powers").
7. **Loss**: "so close" screen showing how far you got; revive once via rewarded ad (+50% of your peak squad).

## 2. Ranks and enemies (SIM owns numbers; CODEX shows them)

Allies (unlock by level; numbers are a starting point, tune with `tune.gd`):

| id | unlock level | weapon / proj | dmg | rate/s | special | value line |
|---|---|---|---|---|---|---|
| hero | 1 | knife | 1 | 3 | never copied by x | - |
| constable | 1 | pistol | 1 | 1.6 | - | = 1 |
| sergeant | 4 | shotgun | 2 | 1.4 | - | = 2 |
| inspector | 7 | revolver | 3 | 1.2 | pierces armour + shields | = 3 |
| swat | 13 | rifle | 1 | 3 | burst hits 2 weak enemies | = 4 |
| sniper | 21 | sniper rifle | 12 | 0.5 | pierce, shoots the toughest target first | = 4 (vs bosses x10) |
| commando | 31 | launcher | 2 | 0.8 | splash: hits 5 enemies | = 6 |

Value line = DPS relative to a constable, computed from config (not hard-coded) and shown as "= N".

Enemies: existing thug, knifer, gunman, brute, riot, biker, boss, plus:
- **molotov** (unlock ~L9): stops at 22 m, every 2.5 s lobs a firebomb into the squad's lane that kills `burn` troops (shield blocks). Visible arc + fire splash.
- **sniper_foe** (~L17): stands at 40 m, every 1.8 s kills 1 troop (shield blocks), hp 3. A red laser line telegraphs the shot.
- **grenadier** (~L27): like gunman but shot kills 3.
- **boss** variants per district boss (L10/20/30/40/50): scale hp; **bosses walk in slowly and shoot while walking** (no holding distance); they reach melee only if you fail. Big HP bar over the head (number = remaining hp), flash white on every hit, label never hidden inside the model.

"Enemies should be quite damaging" (owner): waves are tuned so a sloppy route loses; planned routes win with 30-60% of peak squad left in mid levels.

## 3. Level design rules (SIM)

- 50 levels generated by `tools/gen_levels.py` (deterministic seed per level) into `config/levels/level_N.json`, with hand-authored overrides allowed for 1-3 and each boss level. `Config.LEVEL_COUNT := 50`.
- Difficulty curve: sawtooth inside each district (levels 1-9 ramp, 10 = boss), each district starts a bit harder than the last started. Level length 60-90 s.
- **Gate rarity (owner):** in a gate row, offers (good gates: +N, xk, recruits, weapons, powers, foe mods) appear in **1 or 2 lanes only**; the other lane(s) hold **obstacles**: pothole, barricade, red gate (-N, -%, ÷k: shootable up), car, barrel. A row with offers in all 3 lanes is rare (≤1 per 3 levels, a "lucky row").
- **Potholes** (new obstacle, unshootable): passing through its lane costs `fall` troops (or a %) - shown as an orange/black hole with a number. Steer around.
- **Barricade** (shootable, hp shown): if not destroyed when it reaches you, it costs troops and blocks that lane's next gate.
- New mechanic introduced roughly every 2-3 levels in district 1, then mixed; every new enemy/obstacle/rank gets one icon hint the first time ever (existing `hint` event + `seen_hints`).
- Every level must be winnable: `tests/tune.gd` brute-forces lane routes; requirement: ≥1 route wins without powers for levels 1-10, ≥1 route wins with powers for all; win-rate across routes falls from ~70% (L1-5) to ~15-25% (L40-50). Keep `test_levels_are_winnable_and_reward_planning` (extend to all 50, can sample routes for speed).

## 4. Economy (META-CORE owns; numbers in `config/economy.json`)

- **Level coins**: finale result (existing BottleLogic formula) x `level_coin_mult(L)`, where the curve rises slowly (about +3%/level) while everything you buy rises ~12-20% per step. Coins get harder to earn relative to costs as you go deeper (owner: "why would someone watch an ad"). x2 rewarded ad doubles the final number.
- **Stars**: 1 = win, 2 = finish with ≥ `star2` of peak squad, 3 = ≥ `star3` (config per level band). Stars saved per level (keep best).
- **Star chests**: every 15 stars opens a chest (coins + booster tokens, sometimes a cosmetic).
- **Police Station**: rooms armory, range, training, barracks, evidence, garage with up to 10 levels; costs grow geometrically; level k of a room requires district `ceil(k/2)` liberated (prevents maxing early - owner maxed everything in a few matches).
- **City**: 25 buildings (5 per district, see §6). Each: rebuild cost, build time (30 s for the first, growing to ~2 h), income/hour, 3 upgrade levels (income x1.6 each). Storage cap: 3 h of income, +1 h per City Hall level. Income only accrues for built buildings, using real time (`Time.get_unix_time_from_system()`), clamped to the cap, never negative (clock moved back = no income). Welcome-back popup shows coins earned while away; collect, or x2 via rewarded ad.
- **Boosters** (consumable tokens): `headstart` (+5 constables at start), `shield` (+1 charge), `bomb` (+1 charge). From chests, missions, spin, daily calendar, or one rewarded ad per booster per level.
- **Daily calendar**: 7 days, escalating (day 7 = big chest). Missing a day resets to day 1 (shown honestly).
- **Missions**: 3 per day from a pool (kill N thugs, break N bottles, win N levels, collect city coins, use a bomb, earn 3 stars...). Completing all 3 = bonus chest.
- **Spin**: 1 free per day + 3 ad spins per day; weighted rewards with slice size = weight.
- **Revive**: once per level via rewarded ad: squad back to 50% of the peak it reached, enemies in melee pushed back.
- **Interstitials (stub)**: only between levels, from level 6, at most every 2 completed levels, never right after a rewarded ad or a revive offer; always closable.

Save (bump `SaveData.VERSION` to 3, migrate v2): add `stars: {level: n}`, `city: {building_id: {lv, built_at, ready_at}}`, `city_collected_at`, `boosters: {headstart, shield, bomb}`, `daily: {day, last_claim_date, streak}`, `missions: {date, list:[{id, goal, progress, done, claimed}]}`, `spin: {date, free_used, ad_used}`, `star_chests_opened`, `stats` (lifetime counters used by missions), `rank_seen: []`, `last_interstitial_level`. Keep everything existing.

## 5. Contracts between builders

### 5.1 Sim events (SIM emits; VIEW consumes). Keep all existing events. New:
`pothole_pass {lane, lost}`, `barricade_hit {id, lost}`, `obstacle_spawn` gains kinds `pothole`, `barricade`; `firebomb_throw {horde, lane, t}` then `firebomb_hit {lane, lost, blocked}`; `snipe_aim {horde}` then `snipe {horde, lost, blocked}`; `boss_hit {horde, hp, max}` (throttled ~10/s); `rank_join {unit, first_time}` (first time this level a rank arrives); `revive {troops}`. Hordes keep existing fields; bosses add `max_hp`.

### 5.2 Sim API additions
`LevelSim.revive(troops: int)`; `LevelSim.peak_squad: int`; `LevelSim.stars() -> int` (after finish, using level config thresholds); upgrades dict accepts `headstart`, `shield`, `bomb` booster counts in addition to station effects.

### 5.3 Sound ids (AUDIO provides files in `assets/audio/`, variants `name2.ogg`...; `Sfx.play(id)`)
`knife, shot, shot_big, shot_rifle, shot_sniper, shot_shotgun, launcher, blast, boom, glass_break, glass_tinkle, thunk, punch, hit, die, hurt, coin, coin_bag, win, lose, tap, upgrade, error, banner, recruit, rank_up, gate_good, gate_bad, swoosh, tick, shield, pothole, fire, snipe, boss_roar, build, build_done, collect, chest_open, spin_tick, spin_win, daily_claim, star1, star2, star3, mission_done, unlock`. Music: `Sfx.play_music(mode)` with `mode` in `menu | level | boss` (files `music_menu.ogg`, `music_level.ogg`, `music_boss.ogg`, looping).

### 5.4 Icon names (ART provides glossy PNGs in `assets/icons/gloss/`; existing ones stay)
New: `sergeant, sniper, commando, molotov, sniper_foe, grenadier, pothole, barricade, gift, wheel, missions, star_chest, clock, hammer, map_pin, ad_play, headstart, boss_crown, fire, city_hall, crown, trophy_gold, stars3, district_lock`.
Buildings (two states each, `assets/city/<id>_ruin.png`, `assets/city/<id>.png`), ids in §6.
Map background: `assets/city/map.png` (tall portrait, 5 district bands bottom→top) plus `assets/city/map_layout.json` giving, per district, the band's y-range in 0..1 and the building anchor points and level path points (normalised 0..1 coordinates).

### 5.5 Autoload stubs (META-CORE)
- `Ads` (`src/autoload/ads.gd`): `signal reward_granted(placement)`, `func show_rewarded(placement: String, cb: Callable)` → in stub mode calls `cb.call(true)` after a short fake delay and logs; `func show_interstitial(placement)`; `func can_show_interstitial(level) -> bool` implementing §4 rules; `var stub_mode := true`. Placements: `x2_coins, revive, x2_offline, spin, booster_headstart, booster_shield, booster_bomb`.
- `Analytics` (`src/autoload/analytics.gd`): `func event(name: String, params := {})` appends JSON lines to `user://events.log` (cap 2 MB). Call sites: level_start, level_end (result, stars, troops, time), purchase (room/building), ad_offer/ad_watch (placement), daily_claim, mission_done, spin.

### 5.6 Core logic classes (META-CORE, pure, tested)
- `City` (`src/core/city.gd`): static helpers over `economy.city` + save: `buildings_in(district)`, `cost(id, lv)`, `build_time(id, lv)`, `income_per_hour(save)`, `storage_cap_hours(save)`, `pending_income(save, now)`, `collect(save, now) -> int`, `start_build(save, id, now) -> bool` (with Game spending), `is_ready(save, id, now)`, `district_liberated(save, d)`.
- `Daily` (`src/core/daily.gd`): calendar state machine with injected `today: String` (YYYY-MM-DD) for tests; `can_claim(save, today)`, `claim(save, today) -> reward dict`.
- `Missions` (`src/core/missions.gd`): `roll(save, today, rng_seed)`, `record(save, stat, amount)`, `claimable(save)`, `claim(save, i)`.
- `Spin` (`src/core/spin.gd`): `slices(economy)`, `pick(rng) -> index` (weighted), `can_spin_free(save, today)`.
- `Rewards` (`src/core/rewards.gd`): apply a reward dict `{coins, headstart, shield, bomb, cosmetic}` to the save; chest rolls.
- `Economy` (`src/core/economy_math.gd`): `level_coin_mult(L)`, `station_cost(room, lv)`, `station_requirement(room, lv)`, `stars_needed_for_chest(n)`.
- `Game` (autoload) wraps these with save writes and signals: `coins_changed`, `city_changed`, `boosters_changed`, `missions_changed`.

### 5.7 UI entry points (RETENTION-UI builds; INTEGRATE wires into lobby/main)
All are full-screen `Control`s you `add_child` to the UI layer; each frees itself on close and emits `closed`:
`DailyPanel`, `MissionsPanel`, `SpinPanel`, `BoosterPanel(level)` (signal `start(boosters: Dictionary)`), `RevivePanel(progress: float, peak: int)` (signals `revive`, `give_up`), `CodexPanel` (tabs Ranks / Enemies), `RankToast.show(parent, unit)` (static; 2.5 s corner card: icon + dmg + rate + "= N"), `StarChestPanel`, `WelcomeBackPanel(coins)` (signals `collect(mult)`). `ResultPanel.show_win` gains stars, "x2 coins" ad button and the coin count-up; `show_loss` becomes the "so close" layout (progress bar of how far you got, revive button).

MAP-UI builds `CityMap` (`src/ui/city_map.gd`, the new lobby body: scrollable map, level nodes with stars/locks, current-level pulse, district banners with progress "7/10", buildings with ruined/rebuilt art, build timers, coin bubbles over buildings to tap-collect) and `BuildingPanel(id)` (icon/art, income/h with coin+clock icons, cost, timer, build/upgrade/speed-up-by-ad). Lobby keeps top bar (settings, coins) and a bottom bar: Station, Codex, big Play, Style; side buttons: Daily (gift), Spin (wheel), Missions; all with "!" alerts when something is claimable.

## 6. City content (ART paints, META-CORE configures)

| District (levels) | Theme / lighting | Buildings (ids) |
|---|---|---|
| 1 Downtown (1-10) | sunny day | cafe, newsstand, pharmacy, bus_stop, police_post |
| 2 Market (11-20) | warm afternoon | fruit_market, bakery, barber, cinema, clinic |
| 3 Docks (21-30) | golden hour | fish_market, warehouse, lighthouse, diner, ferry |
| 4 Industrial (31-40) | dusk, orange haze | factory, power_station, garage, train_station, fire_station |
| 5 Uptown (41-50) | night, neon | hotel, bank, museum, fountain_park, city_hall |

`World.set_theme(district: int)` (FINALE-WORLD owns `world.gd`) switches sky, sun colour/angle, fog, ambient and facade tint per district; night adds street-lamp glow. LevelView calls it from the level number (`district = ceil(level/10)`).

## 7. Bottle Shot polish (FINALE-WORLD)

Owner: "zoom on the knife from another camera angle till it nears the bottles, then before the shatter the angle changes; realistic bottle-breaking sound; the balls coming out make no sense." So: during flight a **side-on tracking camera** close to the knife (knife fills ~1/3 of the screen, bottles growing behind it, slow motion), then ~0.15 s before impact **cut to a front-three-quarter close-up of the target bottle**, time returns to normal on contact, glass bursts (shards only, plus a short liquid spray made of thin streak particles, **no spheres**), `glass_break` + `glass_tinkle` sounds. Misses: thunk into the wood, camera holds 0.3 s on the stuck knife. Keep layouts, logic and rewards.

## 8. Builders and file ownership

| Builder | Owns (may edit) | Must not edit |
|---|---|---|
| SIM | `src/core/level_sim.gd, squad.gd, autopilot.gd, bottle_logic.gd(read)`, `config/units.json, characters.json, levels/*`, `tools/gen_levels.py, tools/bake_vat.gd`, `assets/characters/*` (re-bake), `tests/test_level_sim.gd, test_squad.gd, tune.gd`, `src/core/config.gd` (LEVEL_COUNT) | UI, world, finale, audio |
| META-CORE | `src/core/{city,daily,missions,spin,rewards,economy_math,save_data}.gd`, `src/autoload/{game,ads,analytics}.gd`, `project.godot` (autoloads only), `config/economy.json, finale.json (coin curve keys only)`, new tests | UI, sim, world |
| AUDIO | `src/autoload/sfx.gd`, `assets/audio/*`, `tools/lyria_music.py` | everything else |
| ART | `assets/icons/gloss/*`, `assets/city/*`, `art_src/gen/*`, `tools/slice_*.py` | code |
| FINALE-WORLD | `src/finale/*`, `src/game/world.gd`, world shaders | sim, UI |
| VIEW (after SIM) | `src/game/level_view.gd, gate_row_view.gd, fx.gd, crowd.gd`, crowd shaders | sim logic, UI panels |
| MAP-UI (after META-CORE, ART) | `src/ui/city_map.gd, building_panel.gd, lobby.gd, station_panel.gd, ui_kit.gd` | main.gd (INTEGRATE), sim |
| RETENTION-UI (after META-CORE, ART) | `src/ui/{daily_panel,missions_panel,spin_panel,booster_panel,revive_panel,codex_panel,rank_toast,star_chest_panel,welcome_back_panel,result_panel}.gd` | lobby.gd, main.gd |
| INTEGRATE | merges all branches; `src/main.gd, src/ui/hud.gd`, wiring anywhere, conflict resolution, docs (`CLAUDE.md, DECISIONS.md, ASSETS.md`) | - |

## 9. Done means

All tests pass; `tune.gd` shows all 50 levels winnable per §3; a new player can go L1 → result → map → build a cafe → L2 ... L10 boss → district 2, headless autoplay screenshots of each screen look correct; no words on buttons; every icon/sound referenced exists or falls back silently; APK builds.
