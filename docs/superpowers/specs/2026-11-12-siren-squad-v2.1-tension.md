# Siren Squad v2.1: real fights, a fair economy, variety, clear hints (2026-11-12)

Builds on `2026-11-12-siren-squad-v2-design.md` (and v1 / v1.1), which still hold unless this document changes them. Same rules:
- every number lives in `config/`, and the arithmetic stays exact
- icons and numbers instead of words
- original assets only
- no deceptive patterns
- no slow motion or pauses mid-level (except first-run tutorials)

## Why

The owner played the v2 APK on his phone up to level 15:

> 1. first game was too easy to play
> 2. nobody fired at me, i am on 15th level
> 3. boss doesnt have power either
> 4. the ring icon ... marks good thing also as warning (same as something bad) with that yellow alert ring. Also it comes anywhere in the air midgame, it doesnt know where the decision is
> 5. It gets boring as you progress
> 6. Coins now do not last which is good, but upgrading happened really quick ... I wasn't even playing, I opened it and left it running
>
> "later game is interesting but i dont think most people will stay for longer time, because it gets boring with progress"

The investigation (4 diagnosers plus 4 adversarial verifiers; evidence in `_local/inv/` of the v2 worktree) found these causes.

**Combat has no tension**
- The squad fires from 45 m. Every enemy attack has a shorter reach: return fire 32 m, gunmen 30 m, sniper_foe 40 m, molotov 22 m, grenadier 26 m, boss 40 m.
- On a decent route each gang dies within about 0.4 s of entering 45 m, and its front row backs away as rows die. So nothing ever fires.
- On the stored route at the pace upgrades, enemies cost **0 troops on 35 of the 36 normal levels from L11 to L49**.
- Ranged damage is `count × dmg` with gangs of hundreds. So any attack that does land wipes the squad: all or nothing.

**Bosses have no power**
- They deal flat, tiny damage: the L10 boss takes 8 of 308 troops.
- Calibration also scales boss HP by the level's scale. The L30 boss has 7% of its designed HP and dies before it reaches 40 m.

**The player is far stronger than calibration assumes**
- A perfect Bottle Shot multiplies coins 6.5-20×; the model assumes 3.15×. L1 paid 1,381 coins; the model books 176.
- The Armory has no level gates.
- One Station training level (110 coins) lets a non-tapper win L2-L3.
- Calibration fits random-lane players. A player who takes the bigger gate, as the gate lesson teaches, has about 2× the recommended power by L10-L15 with no ads. He keeps 96-100% of his peak, so every win is 3 stars.

**Build timers**
- Every build is at most about 6 min by L15, so it finishes while the app sits open.

**One template**
- Every level from L5 on opens the same way (gate 36 m, gang 70 m, gate ~102 m).
- Names repeat (L21 = L1, L25 = L5).
- Nothing new in L15-17, 19, 22-27, 29, 32-39 or 42-49.

**Hint ring**
- The NewItemCard marker is the same gold ellipse and "!" for good and bad items.
- Every gate or obstacle hint sits in a 3-lane choice row, so the ring reads as "this lane matters".
- When the hinted gang dies, the leftover ring time jumps to another gang of that kind spawning 95 m away (the "ring in the air").
- The ring outlives its card.
- With two matching offers, only the last lane is ringed.
- The riot card uses the player's own shield icon.

## Owner decisions (2026-11-12)

1. A perfect Bottle Shot pays **at most about 1.7×** a plain win.
2. Later Bottle Shot weapons come early as **guest weapons, given as a gift for that level**: "guest + a reward for user to keep them engaged".
3. Difficulty: **Harder**. A player who picks good gates loses 30-60% of his peak squad. Hard levels and bosses are failed on the first try 30-40% of the time.
4. **Mini-boss (lieutenant)** in the middle of each district: L5, 15, 25, 35, 45.
5. Earlier and still valid: tapping matters on L1-L3 (hero alone). Every level is winnable with no-ad coins (replays allowed). No slow motion mid-level.

## Goals

1. Enemies visibly fight back on every armed gang from L11 (gunmen from L3). The player's reactions (lane, shield, bomb) decide how much of the squad survives.
2. Bosses and lieutenants are real fights: about 8-15 s, with telegraphed attacks you dodge or shield.
3. Power stays near the challenge. Coins buy steady progress, not a runaway.
4. Something new or different every 2-3 levels, and no two levels in a row feel the same.
5. Hints are honest and readable: good vs bad at a glance, always on their object.

## Non-goals

- Mid-level surprise events, the district collection hunt, shorter levels, sharper gate trade-offs. Re-measure after this round.
- New character rigs.
- Online features.

## Anti-goals

- A cliff: an attack that wipes a decent squad in one go. Every enemy attack is capped as a share of the current squad.
- An undodgeable one-shot of the hero alone in an opening.
- Difficulty by hidden rules. Every attack is telegraphed and shown, and every loss is visible as a red −N.
- Pay-to-win pressure. Harder levels never need ads: the no-ad pace still wins every stored route, and replays are allowed.

## 1. Real fights

### 1.1 Return fire outranges the squad

`units.json return_fire`:
- `range` becomes **50 m** (gunmen too), above `fire_range` 45.
- On first entering range a gang fires an **opening volley** (`open` 1 shot) at once. After that its shots build up as today.
- **Shooters per gang** = `min(ceil(share% × count), max_shooters)`, with `max_shooters` 3 in district 1-2, rising by district (config).
- **Each hit** removes `max(1, ceil(squad / figures_shown))` troops, lowest rank first. `figures_shown` is the visible figure count (72), so one hit is one figure falling.
- A **volley cap**: one event takes at most `volley_cap_pct` (5%) of the current squad.
- **The hero falls last.** Return fire never takes the last troop while the squad has never had followers in this level (the hero-alone openings of L1-L3 and before the first gate row). Once followers have joined, the hero dies when he is the only one left. This is v2 §12.2 as the owner described it.
- The shield blocks all of it. The bomb kills shooters.

Rates in `units.json` stay per enemy (thug 0.35/s share 10, biker 0.35/s share 20, gunman 0.5/s share 100). Calibration may tune them.

**Readability (view)**
- Enemy tracers use their own orange-red pool, separate from the squad's 320-projectile cap, scale about 1.0. They are slower, so each one is on screen for about 1 s.
- A bigger muzzle flash at the gang's front.
- A red −N over the squad, summed over 0.3 s, and a pulse on the troop pill.
- A 30 ms vibrate (respects the vibration setting).
- Up to 8 tracers per event.
- The boss's and lieutenant's hits also show −N.
- L11 gets a hint card: gang ▸ bullet ▸ squad −.

### 1.2 Specials act before they die

They stop or attack beyond `fire_range`, then keep moving with the scroll until they are in range. This fixes the standoff deadlock in `standoff()`: a stopped gang beyond 45 m must not halt the street forever.

| Enemy | Attack starts at | Telegraph | Dodge |
|---|---|---|---|
| sniper_foe | about 60 m | laser on the aimed lane | change lane |
| grenadier | about 55 m | lane mark | change lane |
| molotov | about 48 m | lane mark | change lane |

Each attack takes at most `attack_cap_pct` (10-20%, by kind) of the current squad. `count × dmg` stays only as the uncapped base.

### 1.3 Bosses and lieutenants

**Boss HP**
- Designed as N seconds of the expected squad's damage per second at that level: district boss 12-15 s, lieutenant 6-8 s.
- The "expected squad" is the calibration profile of §2.
- HP is **not** multiplied by the calibration scale k×kf.
- A boss halts the street for at least 6 s.

**Barrage**
- Every 2.5 s (first one 1.0 s after the halt) the boss marks the squad's current lane.
- 1.0 s later the barrage lands on that lane and costs `barrage_pct` of the squad. Changing lane dodges it; the shield blocks it.
- `barrage_pct`: 12-18% for the boss, 8-12% for the lieutenant. Calibrate under Harder.
- The boss's plain gun becomes squad-relative as well: `gun_pct` per shot, capped.

**Lieutenant**
- At L5, 15, 25, 35 and 45 the last wave is a lieutenant: the boss branch with lieutenant numbers.
- He is drawn at 2.4× a thug with a distinct tint, with his own map-node icon and boss bar (smaller).
- No liberation.

### 1.4 Crowd clash (owner, 2026-11-13)

The owner chose this after the fight advisor's review (`_local/advisor/fable_fight_verdict.md`, verdict ADJUST). It amends v1.1's "a bigger gang visibly wipes you out": a bigger gang now visibly grinds you down in seconds, and every −N is shown.

- **The clash.** When a gang's living front reaches the squad, the two crowds grind 1:1. Every melee tick (0.22 s), at most `world.melee_cap_pct` (3) % of the squad it met strikes from the gang's front row, in troops (at least one enemy, never more than the row). Each striker takes its `power` in troops and falls. The rest of the row waits for the next tick, so the squad's number and the gang's number fall together. The squad keeps shooting the whole time, so a small remnant is shot down in a moment and a big one wins over a few seconds. Gangs in melee at the same time share that pace. On the shield, the strikers fall at the same pace and nobody is lost. A boss still swings with his own fists.
- **The crowd closes ranks.** As a walking gang's front row falls, the rows behind step up, so its front keeps its pace. What reaches the squad is the gang minus what the squad shot on the way in. A strong squad no longer pins a gang's front in place until the HQ hold, which made the outcome a race and a cliff.
- **Fire is texture.** A level's `fire_k` is fitted only within 0.5-2. Specials attack at most `telegraph.fire_k_max` (1.5×) as often. At most `telegraph.max_in_air` (2) marks are in the air, at least `min_gap_s` (0.9 s) apart. The opening volley is never multiplied.
- **Boss dial.** A level's `boss_k` (0.6, 0.8, 1, 1.25 or 1.5) scales its boss's or lieutenant's `gun_pct` and `barrage_pct`, in per mille, exact.
- **The bomb answers return fire.** A gang it lands on holds its fire for `powers.bomb.silence_s` (2 s).
- **On screen.** The front rows punch. The strikers charge in. The squad's front figures fall where the gang meets it. The red −N keeps counting while the clash lasts. There is no slow-down.

### 1.5 Autopilot and generator mirror the rules

- `autopilot.gd`:
  - Raises the shield when any armed gang is in range, or a telegraph targets its lane, and a charge is free.
  - Dodges telegraphs with probability `dodge_p` (profile).
- `gen_levels.py` mirrors return fire, special attacks, caps, the barrage and the boss HP rule.

## 2. Difficulty: Harder, measured on a player who steers well

New calibration profiles in `tests/tune.gd`:
- **greedy**: each row takes the lane that leaves the biggest squad, as `Tutorial.best_lane` teaches. Taps 2/s. Dodges telegraphs at `dodge_p` 0.7. Uses a shield or bomb charge when a free one exists and an armed gang fires or a telegraph targets it.
- **noisy**: greedy, but 20% of rows random. Used for the first-try fail rate (40 runs per level).
- **power**: the rebased economy model (§3.5) at the no-ad engaged player, not the old random-lane pace.

Targets per level:

| Levels | Greedy keeps (end ÷ peak) | Noisy fails on the first try |
|---|---|---|
| L1-L4 (tutorial band) | 70-85% | 0-10% |
| normal levels | 40-70% | 10-20% |
| hard levels: slot 9 of each district, lieutenants, bosses | 35-60% | 30-40% |

- Random routes are only a floor: at least 5% of random routes win, so the level is never a single-path puzzle.
  - Calibrator, 2026-11-13: the floor is **1%** (owner to confirm). At 5%, the gate spread stopped 35 of 50 levels above the greedy band. At 1%, 35 of 50 reach it, and the noisy first-try fail rate rises to a median of about 25-30% on normal levels. See DECISIONS.md.
- **No-ad guarantee**: the stored route at the no-ad pace (power profile, no powers) wins every level, so replays always get through.

**Guard checks** (`tune.gd checks=1` and the level test), so this never silently regresses:
- From L11, on the greedy route, at least 90% of armed gangs fire.
- Enemies cost more than 0 troops on every level from L3.
- Each boss or lieutenant spends at least 6 s (lieutenant 4 s) halted and fires at least 2 barrages.
- A no-upgrade hero-alone opening is never one-shot.
- The greedy loss share is inside the band.

## 3. Economy: steady progress

### 3.1 Level payout

```
coins = base × mult(L)
        × (1 + 0.3 × min(troops / coin_ref, 1))
        × (1 + 0.1 × min(hits, 4) + 0.3 × gold)
        × (1 + 0.1 × heat)
        × station
```

- A perfect run is about 1.7× a plain win.
- The x2 rewarded ad stays.
- `BottleLogic.coins`, the result panel and the econ model share one function.
- The tap coin bonus becomes the `0.1 × heat` term (up to +10%); it replaces v2's +25%.
- `base` is fitted so the no-ad pace stays at 1-3 meaningful buys per win.

### 3.2 Armory tiers unlock by level

`armory.json tier_unlock`: tier 2 from L9, tier 3 from L15, tier 4 from L31. Enforced in `Armory.buy` and `Economy.purchases`, shown with the existing lock (lock icon + level number).

### 3.3 Station training gated by level

Training level 1 from L4, level 2 from L6, level 3 from L8. A test asserts that the L2 and L3 stored routes at tap 0 with starting squad 1-3 lose.

### 3.4 Idle income

- Build timers: district 1 2-10 min, district 2 10-30 min, district 3 30-90 min, district 4 1-3 h, district 5 2-4 h.
- Storage cap stays 3 h (+ City Hall).
- Welcome-back "away" is measured from when the app went to the background, not from the last collection. So the x2 popup no longer fires on every resume after the map sat open.

### 3.5 Economy model rebased

`tests/econ_model.gd`:
- coin troops of the greedy pilot (measured 0.75-1.0 of the stored route)
- bottles per finale difficulty row (count − 1 normal, gold 0.6)
- the tap term
- a with-ads case (x2 on 50% of wins), as v2 §6 required

Ceiling checks:
- the engaged no-ad profile's power is at most 1.6× the recommended power
- greedy keeps inside the §2 band at that power

## 4. Variety

### 4.1 Level archetypes by district slot

`tools/gen_levels.py` gets an `ARCHETYPES` table keyed by the level's slot in its district (1-10). Each archetype changes the wave layout and the world's look, and has its own map-node icon (no words).

| Slot | Archetype | What changes |
|---|---|---|
| 1 | Gauntlet | standard mix |
| 2 | Rush | `scroll_speed` ×1.2 (per-level override), shorter, more gate rows |
| 3 | Ambush | more specials, opening from beyond range (§1.2) |
| 4 | Night | dark look (headlights, neon, nearer fog), gangs show up later |
| 5 | Lieutenant | mini-boss last wave (§1.3) |
| 6 | Rescue | hostage cages guarded by a gang: kill the guards before the cage reaches you and the hostages join as recruits; otherwise they are lost |
| 7 | Horde | few, very large gangs, more × gates |
| 8 | Storm | rain look, more obstacles, wet road |
| 9 | Hard gauntlet | every enemy kind of the district |
| 10 | Boss | district boss |

- District 1 slots 1-3 stay the tap-lesson openings (§5) but take the archetype look and name.
- Levels keep the v1 60-90 s length (Rush is shorter).
- The 6 wave banners stay as allowed gang text.

### 4.2 Something new every 2-3 levels

- Unlocks move earlier: sniper_foe L15, sniper rank L19, grenadier L22, commando L26. Each first appearance has a hint card.
- Cars get a hint card at their first level (L9).
- 50 unique level names; no cycle.
- Optional per-level `look` on top of the district look (Night and Storm use it).

### 4.3 Guest weapons, given as a gift

`finale.json level_weapon` maps a level to a guest Bottle Shot weapon; the district weapon is used elsewhere. Schedule (Claude's call; the builder may move a guest by one level for a fair difficulty row):

| District | Guests |
|---|---|
| 1 | L4 pistol, L7 bow |
| 2 | L13 bow, L16 stars, L19 sniper |
| 3 | L23 stars, L26 sniper, L29 pistol |
| 4 | L33 sniper, L36 bow, L39 pistol |
| 5 | L43 stars, L46 bow, L49 pistol |

The gift moment happens at the burst into the stash, before aiming. This is inside the finale, where pacing is allowed.
- A gift box drops in, wiggles, and opens with a sparkle burst.
- The guest weapon spins up and goes into the hero's hand.
- It lasts at most 1.5 s, and a tap skips it.
- If the weapon's Armory track is locked, a small lock + level number shows under it: the reward teases the Armory.
- The guest weapon uses the player's Armory tier for it if owned, else its base tier.
- First use plays that weapon's ghost-hand lesson as today.
- §12.1 still holds: every bottle visible.

## 5. L1-L3 for adults

- **L1**: 45-50 s and 5 rows.
  - Danger beats at about 8, 20 and 35 s, and a small gang leader at the end.
  - One **trap row** where the bigger number loses: a ×2 lane with a gang right behind it that the doubled squad cannot beat, next to a safer + lane.
  - The tap lesson needs about 1.5 taps/s for 6-8 s.
- **L2-L3**: the hero-alone openings stay (tapping decides them). L3 gunmen visibly drop troops until the shield is used; the shield lesson shows on that event.
- Targets: the §2 tutorial band.

## 6. Hints: honest and on their object

1. **One object per hint.**
   - The hint event carries the id of the object that triggered it: the horde id from `level_sim._enemy_hints_due`, the row or obstacle for gates and obstacles.
   - `NewItemCard._locate` never searches again. When the object is dead, passed or removed, the marker fades out in 0.2 s.
   - The frozen-clock / 8 s wait path is deleted, and the marker and the card share one duration.
   - A gang marker follows the survivors' real centre, not x=0.
2. **Tones**: `hints.json` items get `"tone": "gain" | "threat" | "use"`.

   | Tone | Items | Look |
   |---|---|---|
   | gain | ranks, smg, turncoat, no_armour, gang_split, shield, bomb | green chip with an up-chevron/+, green card frame and numbers |
   | threat | pothole, barricade, car, armour, riot, molotov, sniper_foe, grenadier, boss, lieutenant, return fire | red triangle with "!", red frame and numbers |
   | use | barrel, red_gate | orange aim reticle |

   - Shapes differ as well as colours (colour-blind safe).
   - The Tutorial's rings use the same tones.
   - The riot card's effect icon is an enemy riot shield, not the player's shield.
3. **No lane singled out.**
   - Gates get no screen ellipse: every matching gate sign in the row gets a small sparkle in its tone colour.
   - Obstacles get a small toned tag above the object.
   - HUD powers keep the button pulse only.
4. **Analytics**: a `hint_shown` event (item, level, t).
5. Spec v2 §11 is amended by this section.

## 7. Owner data

When the phone is connected, read `events.log` and the save (read-only, `adb exec-out run-as com.iiakshat.sirensquad ...`). Confirm against them: coins by source, bottles per win, x2 use, idle income, power per level, enemy-attack events. Adjust §3 if his numbers differ.

## Calibration and process

- After the sim, generator, economy and archetypes merge:
  1. rebuild the pace
  2. `calibrate=1` with the new targets (greedy band, noisy fail rate, random floor, no-ad guarantee)
  3. `gen_levels.py --merge`
  4. a plain run storing routes
  5. `--merge` again
  6. checks
- Boss levels are calibrated with dodging on.
- Screenshots for every visible change: return fire with −N, each telegraph, a boss barrage, the lieutenant, each archetype look, the gift reveal, hint tones.

## Left to the builder

- Exact archetype layouts and the hostage cage model.
- Night and Storm lighting values.
- Gift box art (vector or one Gemini sheet).
- The 50 names.
- Tracer colours, within "orange-red, clearly not the squad's white".
