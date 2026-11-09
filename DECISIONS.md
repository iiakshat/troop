# DECISIONS.md: choices and why

**2026-11-08: Engine: Godot 4.7.2, Compatibility renderer** (owner chose Godot over Unity).
Unity wasn't installed, would need about 15 GB plus a licence sign-in, and is heavy on this 16 GB laptop. Godot is already in `../_tools`, and Tamra's GitHub Actions setup already builds Android APKs from it.

**2026-11-08: Theme: a neutral city** (owner). An ordinary guy in casual clothes throws knives; police join him (Constable with a pistol, Inspector with a revolver, more ranks later). Armed gangs attack in big numbers. A neutral city rather than an Indian setting, because ad revenue per player is far higher outside India.

**2026-11-08: No merging** (owner). Bullets get stronger through better ranks (Inspector: 3 damage, pierces armour) and lobby upgrades (knife power, throw speed, starting squad), not by merging troops.

**2026-11-08: Money from ads only** (owner): ads between levels plus optional rewarded ads (head start, powers, 2x coins). **No ads in the current build.** The interstitials go against "no forced ads" in `../CLAUDE.md`; the owner made that call.

**2026-11-08: The arithmetic is exact** (Claude). x2 makes the shown troop count exactly double (the hero, who can't be copied, brings a constable). Losses take constables first and the hero last. Percentages and division round down. PSYCH.md requires every decision to be mathematically consistent, and players feel cheated otherwise.

**2026-11-08: Shooting rule** (Claude): troops shoot the nearest gang in range, and only shoot what's in their lane (red gates) when no gang is in range. It's one sentence to teach, and it gives a reason to clear gangs fast (more time to shoot red gates up).

**2026-11-08: Fire range 20 m, slower gangs** (Claude, after screenshots). At 30 m, gangs died tiny and far away. At 20 m, fights happen close and fill the screen. Fire rates went up about 25% to keep the balance.

**2026-11-08: Pickups instead of gates** (owner feedback). Recruits stand in the lane as real people with a small "+N" tag. Other effects (x2, -8, NO ARMOUR, GANG ÷2, PISTOL, BOMB) are compact signs. A red sign shot past zero turns into a troop group. The tag reads "+N", not "xN": "x2" already means "double the squad", so "x8" for "8 troops" would muddle the maths. Easy to switch if the owner insists.

**2026-11-08: No slow motion, no floating words** (owner). The squad count is a small HUD pill (top right). Enemy gangs keep a small number over them (red, or grey-blue when armoured) because the arithmetic needs it. The one pause left is Level 1's first row, and only while the player stands in an empty lane ("swipe" hint); without it, a player who never swipes dies at 10 seconds.

**2026-11-08: Brand-new players skip the menu** (Claude). The first launch drops straight into Level 1 for the fastest possible first win. The lobby appears from the first result screen onwards.

**2026-11-08: Three levels, tuned by brute force** (Claude). `tests/tune.gd` plays every lane combination of every level (351 runs in about 8 seconds). Current: L1 wins on all 18 real routes; L2 on 45/81 (planned route ~32 troops vs sloppy ~16); L3 on 101/243 and needs the powers.

## Open

- Package ID (`com.iiakshat.troop`?) is permanent after the first Play upload. Confirm with the owner before any release build.
- Name "Troop" is a working title; no trademark check done yet.
- Character look: owner says they "don't look good yet". Revisit (proportions, faces, maybe proper low-poly models).
- Analytics (Firebase) must go in before any stranger tests it (parent CLAUDE.md rule 3). Consent and age screen as in Tamra.
- Kill/fix rules before launch: not set yet.

## v0.2 (2026-11-08, owner feedback round 2)

**Honest melee** (owner: "I died while enemies were still away"). Gangs are blocks of rows and bullets kill from the front, so a gang's front is its frontmost living row. Nothing hurts until that front reaches the squad; then the front row strikes every 0.22 s, each enemy taking its `power` in troops. A bigger gang visibly wipes you out.

**Bullets stream down your lane to 45 m and hit the first thing in it** (owner: "bullets should go further"). That can be a gang, a red gate, a barrel or a car. This makes red gates and barrels tactical: you choose what your fire is spent on.

**Barrels arm, then trigger** (Claude). Shooting a barrel arms it, and it blows up when the next gang's front reaches it. This avoids needing frame-perfect timing.

**Characters: Quaternius CC0, baked to vertex-animation textures** (owner chose "low-poly, real proportions"). Kenney Mini (the best for performance) is chibi, which the owner rejected. Quaternius has a 32-bone shared rig and 11 clips, with no run or death; the walk is played 1.7× as a run and Defeat is the death. Recoloured into 11 roles; weapons are boxes on the hand bone. VAT keeps a crowd at one draw call per role; flat shading is rebuilt per pixel, so no normal textures. About 15 MB of textures.

**City: Kenney City Kit Commercial/Roads + KayKit bits** (from verified research). One palette texture per kit.

**Bottle Shot finale replaces the strike bar** (owner design): 3 knives, a slow-motion chase cam that snaps to 1× at impact, glass that shatters into shards, and coins boosted per bottle (gold doubles). The layout changes per level: static, slide, swing or drive. Bottles are our own lathe meshes with a fake-reflection glass shader (Compatibility renderer has no screen-space refraction).

**Coins buy only police-station rooms and cosmetics** (owner). Ranks unlock by level progress. Room bonuses are capped; the front desk gates rooms. Old v1 upgrades migrate into rooms.

**UI: bright cartoon, icons not words** (owner picked direction A, "use icons"). Kenney UI Pack glossy 9-slice buttons, game-icons.net SVGs, Luckiest Guy. Text only for numbers, short loss tips, gang banners and legal credits.

**Hints: once ever, icon plus pointing hand** (owner: "too much verbosity"). Saved in `seen_hints`.

**5 levels** (owner): new idea per level, boss on 5. Brute-force tuned: L1 18/18 real routes win, L2 34/81, L3 15/27, L4 17/27, L5 34/81.

**APK builds blocked by GitHub billing** (2026-11-08). Every Actions run on the account fails with "account is locked due to a billing issue", including on public repos. The owner has to clear it on GitHub. Code still pushes to `dev`.

**v0.3 look: textured cartoon on the Mobile renderer** (owner: "textured cartoon", Mixamo + AI art, OK to drop pre-2017 phones). Forward Mobile with automatic GL fallback. Facades, ground and icons are Gemini-painted sheets sliced locally; the shared key gets few requests (owner). Crowds keep VAT but bake smooth normals for two-tone light, rim and ink outline.

**Armour halves, never blocks** (owner: "some enemies never go to 0"). Zero-damage immunity made brutes and the Kingpin unkillable without Inspectors. Inspectors still pierce, so they stay the counter.

**Squad cap** (owner: "keep track of how many max char can be added, add a bar"). 150 from `units.json`, plus 25 per Barracks level; overflow gains are dropped, lowest rank first, and the HUD bar turns gold when full.

**Station without the front desk** (owner: "upgrades do not make sense"). Every room is open; each row shows the real value now ▸ next.

**Local APK builds, minimal toolchain** (owner: "setup locally… only install what's needed", 2026-11-08). Godot's non-Gradle export only needs adb, apksigner and a Java runtime, so `tools/setup_android.py` installs platform-tools, build-tools 36 and a Temurin 17 JRE (not the JDK), and pulls just the Android templates out of Godot's 1 GB pack with HTTP range requests. About 500 MB total; no Android Studio. The build runs at below-normal CPU priority. After a green local build, `main` is fast-forwarded to `dev` by hand (replacing the CI promote job while Actions is locked). The debug APK is about 70 MB because it carries the engine for both 32- and 64-bit phones; Play's per-device split will make a store download much smaller.

## v1.0 (2026-11-08/09, owner round 4: "an end-to-end game, very addictive, high revenue")

**Meta: rebuild the city** (owner's pick). 5 districts × 10 levels; each district boss liberates its district. 25 buildings start ruined, are rebuilt with coins behind a short build timer (30 s for the first, up to about 2 h), and earn coins per hour into a storage that caps at 3 h (+1 h per City Hall level). The cap and timers bring players back; income uses real time and a clock moved backwards earns nothing. A district's ruins can be rebuilt once the player reaches it; upgrades need it liberated. The map is the lobby, so progress is always in view (goal gradient).

**Coin curve** (owner: "why would someone watch an ad"). Win coins = finale coins × mult(L), mult = 1 + 0.03 × (L-1), ×1.5 on boss levels, ×0.5 on replays. Everything bought grows 12-20% per step, so coins get scarcer relative to costs as you go deeper, which gives the x2 rewarded ad its value without starving early players. Daily, mission, spin and chest coins scale with the player's level so they stay worth having.

**Station gates read "ceil(k/2)" as district reached.** Room level k needs district ceil(k/2) *reached* (ceil(k/2)-1 districts liberated): levels 1-2 are buyable at once, 9-10 need district 5. The literal reading ("liberated") would lock the whole station until level 10 and break "generous early game". Owner had maxed everything in a few matches before, which the gates now prevent.

**Gate rarity** (owner). Offers appear in 1-2 lanes of a row; the other lanes hold obstacles (pothole, barricade, red gate, car, barrel). A row with offers in all three lanes is a rare "lucky row" (at most one every 3 levels). Choosing a lane is now a real decision every row.

**Ranks.** Allies unlock by level (Sergeant 4, Inspector 7, SWAT 13, Sniper 21, Commando 31). Each is shown as "= N constables", computed from config DPS, never hard-coded. The first time a rank ever joins, a small corner card shows its stats (RankToast) once.

**Stars from the share of the peak squad left** (1 = win, 2 ≥ 30%, 3 ≥ 55%, in units.json). It rewards planning a route, not just surviving, and feeds the star chests (every 15 stars).

**Ads are stubs with a visible placeholder** (owner, 2026-11-08: wants to see where ads go). Every placement opens a blank near-black popup with a countdown number and ring, no words. Rewarded: 5 s, reward only at 0, close X visible from the start (closing early = no reward). Interstitial: 3 s, then a close X. Autoplay and headless skip it. Placements: x2 coins, revive, x2 offline coins, extra spins, one per booster per level, build speed-up.

**Interstitial rules.** Only between levels (after a win, on the way from the result to the map), from level 6, at most one per 2 completed levels, at least 45 s apart, never right after a rewarded ad or a revive offer, always closable. Never during play, never on a loss screen. Numbers in `economy.json` `ads.interstitial`.

**Flow order after a win: result → star chest → interstitial → map.** The chest comes first because it's a reward; the interstitial sits at the natural break before the map, and the map then shows the pin hopping to the new level (a small progress win right after the ad). "Next" also opens the next level's boosters on the map; "Home" just shows the map.

**Boot order: welcome back → daily → map.** Offline coins first (the biggest "you were missed" reward), then the calendar once a day if it can be claimed. A brand-new player skips both and lands in level 1 (fastest first win); the popups start when they first reach the map.

**Revive: once per level, for a rewarded ad**, back to 50% of the peak squad, gangs in melee pushed back, 2 s shield. No countdown on the offer and the X simply gives up: a near miss is a moment of high want, but pressure tactics are out.

**Engagement without deception** (Google Play policy, India's 2023 dark-pattern guidelines). Wanted: variable rewards, daily streaks, goal-gradient bars, storage caps, build timers, star chests, near-miss revives, opt-in rewarded ads at moments of high want. Forbidden: fake countdowns, disguised ads, ads that can't be closed, confirm-shaming, wheels whose slice sizes lie about odds (slice size = true probability), hidden costs, bait-and-switch rewards. A missed daily day resets the calendar and says so honestly.

**Liberation celebration.** Beating a district boss shows a LiberationPanel (crown, district number, its 5 buildings popping in with a hammer badge), then the map scrolls to that district so the next step (build) is obvious.

**Mission stats are counted at the end of a run** from the sim (kills per enemy kind via `LevelSim.kills_by`, bottles, powers used by watching charges drop), so a quit mid-level doesn't count partial progress twice and revives add up correctly.

**World themes are visual-only tables in world.gd**, not config: sky, sun, fog and tint per district have no gameplay meaning. Night extras are fake glows (additive quads, emissive neon), not real lights, for phone performance; window masks use the MULTIPLY emission operator; glass shards are unshaded because lit transparent emission rendered black on the Mobile renderer.

## v1.0 merge-verify (2026-11-09)

**Calibration is the source of level balance.** `tools/gen_levels.py` writes the 50 levels, `tests/tune.gd calibrate=1` fits a per-level gang scale to each level's `target_win`, and `config/levels/calibration.json` keeps the scale plus the winning routes (`route`, and `route_np` for L1-10 without powers). The generator's own sizer makes gangs 2-10x too big, so fitted scales sit well below 1; fixing the sizer is a later SIM task.

**Planned routes still end near full strength** (85-100% of peak; spec §2 wanted 30-60%). The last-wave fit could not reach that even at 4x, so it falls back to x1.5 and stars are 3 at 85%, 2 at 45% of peak. Open for the owner: lower the 150 cap, add percent damage late, or allow a bigger last wave.

**Revive shield 4 s, not 2 s.** A revive is paid for with a rewarded ad; with 2 s, a molotov volley already in flight (throw every 2.5 s, 1.1 s flight) could wipe the revived squad, which would make the ad a bad deal. 4 s covers one full throw cycle.

**Autoplay follows the stored winning route** when no `lanes=` is given, so `chain=N` and screenshot runs reach later levels; under autoplay the star chest closes itself after 2.5 s.

**`save=path` never touches the real save**, even when the file is missing (it then starts a blank player). An agent run without a real file behind `save=` had written test coins into the owner's save; it was restored from the 09:53 backup.

**Gang HQ sign is the gang's hood icon**, not the words "GANG HQ" (no words on game objects).

**Music:** a level always starts on the level loop; LevelView switches to the boss loop when the Kingpin walks in and back when he dies; a revive resumes whichever is right.

## v1.0 review fixes (2026-11-09)

**The clock only moves forward for rewards.** Daily, free spins and missions reset only on a later date than the stored one; moving the phone date back grants nothing (matches the city's "clock moved back = no income").

**Debug runs never write the real save.** Any run with autoplay, level, coins, reset, stop_at, frames, shots, screenshot, chain, boosters or district plays on a throwaway copy (`write=1` persists, `real_reset=1` wipes). Saves are atomic (`.tmp` then rename) with `save.json.bak` as a fallback when `save.json` is broken.

**Fights read bigger.** Longer lens from further back (camera (0, 9, 12) looking at z = -14, FOV 42): the squad keeps its size, fights 20-45 m away are drawn about 25% bigger. Gang members are drawn 1.3x and their counts grow with distance. A district boss inside 35 m leans the camera down the street (FOV 35); his death plays 0.5 s of slow motion, a big burst and the HP bar shatters. Escort counts sit above the boss bar. The camera follows the squad sideways by half, and a big squad packs narrower. The sim's fire range (45 m) is unchanged, so gangs still die far up the street; bringing fights closer needs a shorter range plus re-calibration (owner call).

**Ranks read from behind** (they were dark hair and navy from the camera's view): inspector purple cap and khaki suit, sergeant gold hat, SWAT grey helmet, sniper olive helmet, commando tan helmet. Placeholder colours; the owner can change them in `config/characters.json` and re-bake.

**Tracers are thinned visually** past about 36 shooters (one in k drawn, thinner, 60% alpha). Damage is unchanged.

**Level coins cut** (finale `per_troop` 2 -> 0.5, `clear_bonus` 40 -> 20): a full L1 win paid about 1,700, enough for every district-1 sink after 1-2 levels, so the x2 ad, spin and daily coins meant nothing. A typical L1 win (2 bottles) now pays about 190, about one district-1 building.

**First build is pointed at, wordlessly.** After L1, a hand taps the cheapest affordable ruin, then the Build button; the gift and wheel badges and the daily popup wait until the first build starts.

**Good play stays powerful** (owner, 2026-11-09). Planned routes finish at 85-100% of their peak squad (the spec had aimed for 30-60%); the owner chose to keep it that way. Difficulty comes from sloppy routes losing, not from punishing good ones.

**Troops smaller than the hero, a step behind him** (owner, 2026-11-09). Troops draw at 0.85 of the hero's size (0.68 in big crowds) and form up about 1 m further back, so the hero reads as the leader.

**Red gate "-40% shot to 0%, passed, died" (v1.1 probe).** Reproduced headless (`_local/probe_red.gd`, a squad at 30% of the planned route takes the red gate): passing at 0% never cost anything; the deaths came 5-6 s later from the gang right behind the gate (L13 knifers, L20 brutes, L22 gunmen). Bullets hit the first thing in the lane, so while the whole squad shot the gate up, that gang walked in unshot. Fixes: a red gate's tick is now fixed when the squad first shoots it so that squad reaches 0 within `red_gate_clear_s` (2.5 s) whatever its size (the level's `step` is the upper bound), so far less fire is spent on it; a gang closing in (front within 18 m) while the fire goes elsewhere pulses its count; on a loss a red ring marks what did it (gang, obstacle or firebomb lane). 0% stays exactly no change; past 0 it is a troop offer.

**Spatial obstacle hits** (owner, v1.1). An obstacle has a footprint (`width` in `units.json`) and a capacity (its number, now shown on every obstacle in red; the yellow number is the hits it still takes). Only the troops whose formation slots overlap the footprint die, nearest first, up to the capacity. The formation is shared by sim and view (`Squad.slot_offset`; at most 72 figures, each carrying total/72 troops) and is never wider than `formation_half_width` (1.25 m) either side, so a squad standing in the middle of its lane never brushes the next lane's obstacle: the danger is in steering, not in a neighbouring lane. The view feeds its real steering x every frame (`LevelSim.set_squad_x`); autoplay and headless runs stand at lane centres, where the old lane rule and the new one agree. Survivors keep their places and ease into the gaps.

**Standoffs** (owner, v1.1). When a boss is within 40 m, or any gang that stops to shoot has stopped, the street stops (the sim's `traveled` does not advance; the scroll brakes in about 0.3 s) and resumes when it is cleared. Bosses walk in at their real pace with heavy footfalls. Levels were re-calibrated afterwards.

**New rank spotlight** (v1.1). The first time a rank joins in a level, 1 s at 0.3 speed with a pulsing gold ring under the newcomers, plus the existing RankToast.

## v1.1 economy and why-upgrade (2026-11-09, ECON-UI)

**1-3 buys after nearly every win, fewer deeper in.** `tests/econ_sim.gd` plays levels 1-50 with a typical player (`tests/econ_model.gd`: 3 sessions of 5 levels a day, 4 h apart, ~2 bottles, 2.3 stars; the welcome-back, daily and spin coins are spent at session start, not counted as a win's buys) who buys what the map's pointer suggests. With the v1.1 numbers 90% of wins buy 1-3 things (more only at L7 and L20, a star chest or a liberation bonus), no win in districts 1-3 buys nothing, and buys per win fall from about 2 (districts 1-2) to about 1 (districts 4-5); the three thin late wins (L38, L43, L49) each become a purchase with the x2 ad. `test_purchase_curve_holds` keeps this.

**What changed to get there.** The current district's buildings can be upgraded to lv 2 before its boss falls (`pre_liberation_max_level`), liberating a district pays a one-time bonus (250/500/750/1000/1500), a third builder, station rooms cheaper and flatter (knife/range 80 x1.45, training 110 x1.45, barracks and evidence x1.6, garage x2.2; the third knife/range/training level is open in district 1) so late rooms stay within a few wins instead of 4-7k, district 5 buildings earn 28% less per hour (coins scarcer at the end). Level coins grow 4% per level (was 3%). Income x1.6 per building upgrade stays as specified.

**Squad Power** is one number from the station's real effects (hero knife damage x throws/s, starting constables, squad cap, charges, coin bonus; weights in `economy.json` "power"). The lobby top bar and the Station show it; level nodes from the current one to 4 ahead show the recommended power (`power.recommended`, fitted to 80% of what the sim player has), red with a tinted node when the squad is weaker. Every level is still winnable without upgrades; the number explains, it does not gate.

**One pointer, one pick.** After the first build, the hand bobs over the single best purchase: when under the next level's recommended power, the room with the most power per coin (hand on the Station button), otherwise the building with the most income per coin (hand on the building), else the best room. Cosmetics are never pointed at. A loss shows the room whose next level adds the most power (affordable ones first) as before > after, with the hand on the Station when it is affordable.

**New Rank card** shows once per rank, before the level where it unlocks (or before the next level for a player who passed it without meeting the rank); a rank already met in a level gets no card.
