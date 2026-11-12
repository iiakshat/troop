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

## v1.1 finale and tutorials (2026-11-09, FINALE + TUTOR)

**One weapon and one stash per district** (owner, v1.1 items 9-10). The level ends at the gang's stash (1 back-alley bar, 2 carnival stall, 3 docks crates, 4 factory conveyor, 5 rooftop neon lounge; `FinaleStash`), the squad bursts in, and Bottle Shot uses the district's weapon: knives, pistol (iron sights, 6-round magazine, swipe-down reload), bow (hold to draw, wind, drop), throwing stars (swipe, ricochet off steel) and sniper (scope sway, drop, bolt cycle). Each weapon owns its camera, input, ammo and physics (`src/finale/weapon_*.gd`); BottleLogic keeps the rules and the coins. All numbers are in `config/finale.json` (`district_weapon`, `weapons`, `difficulty`). `BottleShot.throw_at` is the autoplay entry and always shoots the next real target. Procedural weapon models are logged in `docs/assets_finale.md`.

**Bottle Shot difficulty and combo** (owner, v1.1 item 7). The level's place inside its district picks a difficulty row (more bottles, motion, smaller and farther targets, clay-jug decoys, fewer spare shots). Hits in a row raise a combo (+0.5 per hit, at most x3) that weights each bottle's bonus; a miss or a decoy resets it. `tests/econ_model.gd` now counts its expected bottles as a streak; with that the purchase curve still holds (92% of wins buy 1-3 things; districts 1.7 / 1.9 / 1.4 / 1.2 / 1.1 buys per win).

**First-run tutorials freeze the street** (owner, v1.1 item 11). `src/ui/tutorial.gd` (a CanvasLayer over the HUD) holds the level (`LevelView.hold`, time scale 0) with a spotlight, a ring and a ghost hand, no words, each once ever in `seen_hints`: `swipe` (hand sweeps across the squad; held until the player drags), `gate_pick` (the first row with 2+ offers lights the lane that leaves the biggest squad; held until the squad is in it, or a short light without a hold if it already is), `red_gate` (the squad lines up with a red gate just before fire range: ghost bullets fly into it and a green chevron rises; tap to go on), `shield` / `bomb` (the first gang in fire range while a charge is ready: the button is lit; tap or use it). Bottle Shot: `bottle_<weapon>` loops that weapon's gesture (drag-release, hold-drag-release, swipe) until the first touch, once per weapon, and `bottle_reload` shows the pistol's swipe-down the first time the magazine is empty. The first shot always waits for the player (nothing auto-fires). The tutorial replaces the level-data hints with the same ids (Hud skips them while it runs), so players who saw the old hints are not taught twice. Never created under autoplay; `tutor=auto` (debug) runs it under autoplay and acts each step out after 1.6 s for screenshots. Why freeze instead of slow motion: the owner asked for "stopping and teaching", and a freeze cannot kill a first-timer who is reading the hand.

**v1.1 review fixes (2026-11-09).** (1) A red gate's dps-scaled step (`gate_step`, "clears to 0 in about 2.5 s") now covers only the climb to 0; past 0 the gate is a troop offer and each tick costs the level's own `step` again. Before, a squad of 3 maxed a +40 gate in 5.4 s, which made the red lane the best lane at any squad size. Levels were recalibrated after it. (2) The map warns (red pill, tint) only on the current and next node, only when the recommendation is more than 15% above Squad Power, and never while the first-build hand is up; recommended power is flat at 60 through L3. Every level is winnable without upgrades, so a red pill on every node was close to a pressure-to-spend pattern. (3) The red-gate lesson no longer freezes the street: it opens at -28 m (number readable, in fire range), runs at 0.3 speed and ends after two ticks; L1's second gate row has a small red gate (-3, max 9) in the lane the first gate choice leaves the squad in, so every new player meets it early. (4) First-person Bottle Shot views (pistol sights, bow, scope) never draw the hero's body (`BottleShot.camera_in_head`), and the view models show only gloved hands (no forearms); a stash sign that crosses any eye-to-bottle line is lifted at finale start (`FinaleStash.clear_sightlines`). (5) Fire rate has its own icon (bullets with speed lines); the winged sneaker means enemy speed only. Pierce is a helmet with a bullet through it. Rank cards and the Codex show each rank's weapon. (6) The Bottle Shot combo (flame) is the big number; the reward multiplier is smaller, behind a coin.

## v2 combat: return fire, big numbers, thrown bomb (2026-11-12, COMBAT)

**Return fire is a stream, not volleys** (spec v2 §12.2). A gang with guns fires while its front is within `range` (32 m, inside the squad's 45 m, so the squad always shoots first): `share` % of it carries guns (rounded up), each shooter fires `rate` shots/s, and each hit is one troop, lowest rank first, so the hero falls last (`LevelSim._return_fire`, one event per gang and tick for the tracers). Thugs 10% x 0.5/s, bikers 20% x 0.5/s, from district 2. Gunmen use the same rule in every district at their old volley's average (100% x 0.625/s), so their volley is gone; they still stop at 26 m (a standoff). Knifers, brutes, riot and molotovs carry no guns; bosses, sniper foes and grenadiers keep their own attacks. The shield blocks it. Autopilot raises the shield when return fire costs 2+ troops/s.

**Big numbers stay exact and cheap.** The squad cap is per district (`world.squad_cap` 300/1K/5K/25K/100K); barracks levels add a percent of it (`upgrades.capacity` is now a percent; Squad Power's cap weight halved to 0.1 so level 1 still reads 60). Every count is a 64-bit int (percent gates, obstacle and revive maths are integer). A gang never draws or fights as more than `world.gang_figures` (180) figures: each carries `per` = ceil(n / 180) people, a row is cols x per, so a 90K gang is 20 rows deep and its front row strikes together; without that a huge gang was kilometres deep and the squad's fire outran its front. Below 181 nothing changes. The finale pays on `LevelSim.coin_troops()` (the squad as district-1 troops), so a 100K squad pays like a full district-1 squad and the coin curve holds. `NumFormat` shows 9,999 in full, then 12.3K / 1.25M, digits cut, never rounded up.

**Generator scaling.** Growth offers size on max(squad, 1% of the cap) (district 5's first +N is hundreds, not +7); multipliers reach x4 in district 3 and x5 in districts 4-5 while the squad is under a fifth of the cap (districts 1-2 draw exactly as v1); gang ceilings grow with the cap; bosses' gun and fists grow with the cap. The battle model mirrors the sim (capped rows, return fire). Levels were regenerated but not recalibrated (the integrator does that).

**The bomb is thrown** (spec v2 §12.5). Any moment of a level: the hero's throw clip, a round bomb with a sparking fuse arcs `flight` (0.8 s) down the lane to the nearest gang front, barricade, car or barrel within `reach`, else the road at reach. The sim applies the blast at landing (kills, boss damage, wrecks, barrels set off) at the target's position then, so the arithmetic stays exact. Gangs are hit by z (they fill the road); obstacles by 2D distance within `radius` (4 m), so a wreck right beside the target in the next lane goes too. An empty road still spends the charge and explodes: the player's choice.

**Live firepower** (§12.4): `Squad.firepower` = damage per second against a plain unarmoured crowd, every rank at its best (bursts, splash, a sniper round's full damage), the hero and a held weapon at the current tap rate. The HUD shows it next to the troop count (lightning + number). `LevelSim.start_firepower(units, upgrades)` is the same unit with a hot hero, for the lobby's Squad Power and recommended power (not wired yet).

**Tests never write the real save.** The Game autoload exists in a `--script` run before its `_ready`, so a test that saved and restored `Game.save_path` restored `user://save.json`; `run_tests.gd` now points it at a throwaway file first, and `Game.write_save` refuses `save.json` under any SceneTree script.

## v2 Armory, powers and outfits (2026-11-12, ECON)

**Squad Power is the level-start firepower (spec 12.4).** One unit under the lightning icon everywhere: nominal dps against an unarmoured target. The lobby, the Armory and Station pills and each level's recommended power show the squad a level starts with (hero at full tap rate + starting constables, times their Armory multipliers); the HUD shows the same unit live. So a step for a rank that joins during a level (shotgun and up), the squad cap and the coin bonus add no Squad Power; their cards show the before > after stats instead of a lightning gain. Values are small early (3 = the hero alone), so `Economy.fmt_power` shows one decimal below 100 so that one knife step (+0.2) is visible. The best-buy hand and the loss tip rank by a separate `value`: the firepower a step adds to the squad a level builds (`power.ref_troops` of each unlocked rank), plus `cap_value` / `coin_value` weights for the cap and coin bonus (never shown); the loss tip ignores the coin bonus (it never wins a fight). `recommended` was refitted by iterating `tests/econ_sim.gd` to a fixed point (the curve changes what the pointer buys): the spending player always meets it, 90% of wins buy 1-3 things. Armory step prices rose a little (bases, growth 1.21) to keep that band once rank steps count. Bottle Shot handling steps add no power and are never pointed at.

**Shield and bomb are powers, not tokens.** Every charge the player has (free + stored) comes into every level; only the used ones are spent at the level end (`PowersTimer.settle`), also when a level is left early (restart, home) so a restart never refunds a used free charge. The recharge countdown and the "refill with an ad" button live on the booster screen before a level; in the level the empty button only shows the clock and h:mm, because an ad mid-level would pause the street (v2 rule: no pause during a level).

**Outfit accessories ride on the baked head.** Each paid outfit adds one head accessory (cap, hood, shades, crown; `HeroAccessory`), built from primitives and placed every frame from the hero's VAT pose (the head vertices' baked positions), so there is no extra bake per outfit (each would add about 1.5 MB) and no change to the crowd shader.

**Armory tiers show in the level by recolouring the baked weapons** (`WeaponLook`): the owner's crowd swaps the weapon's bake colours (blued steel, chrome and gold, gold and navy) once at level start; the Bottle Shot view models take the same colours on their metal parts. No new meshes, so performance is unchanged.

**Lobby bottom bar: Station, Armory, Play, Style.** Codex moved to the left column (under Missions) so Play keeps its width on a 720 px screen; the Squad Power pill opens the Armory.

## v2 ads, analytics and audience (2026-11-12, SDK)

**Plugins.** AdMob: the Godot AdMob plugin v7.0 (godot-sdk-integrations/godot-admob, MIT). It is maintained, built on the Godot v2 Android plugin API, and it exposes every request setting the spec needs: child-directed and under-age-of-consent tags, max content rating, non-personalised (`PersonalizationState.DISABLED`), first-party ID off, and the UMP consent flow. It bundles Google Mobile Ads 24.9.0, with no mediation. Firebase: Godotx Firebase v3.1.0 (godot-x/firebase, MIT), Core + Analytics modules only. It starts only when the game calls `initialize()`, has `set_consent` and `set_analytics_collection_enabled`, and its export plugin writes privacy-safe manifest defaults (collection off, consent denied). Alternatives (Poing Studios' AdMob plugin; older single-purpose Firebase Analytics plugins, mostly for Godot 3) were not needed once these two loaded and built cleanly on 4.7.2. All three addons load in the Godot 4.7.2 editor (headless `--editor` and the export run), and the Gradle export builds with them.

**Who is a child.** Under 13, or under 18 when the device region or locale is India (DPDP Act). Godot has no region API, so an India Standard Time clock (UTC+5:30) also counts as India: an Indian phone in `en_US` keeps the stricter rule, and a false positive only means safer ads. Unknown age = child. The answer is decided once, when the wheel is answered, and it survives "reset progress", so the question cannot be retried for a different result.

**Neutral age screen.** A birth-year wheel, numbers only, starting blank with no pre-picked adult year (a pre-picked adult year would nudge kids to tap through). It shows once, before any SDK. `main.gd` only defers its first screen until the wheel is answered.

**Child path is fixed in code.** `Ads.request_config(true)` returns child-directed + under-age + G + NPA + no first-party ID + no UMP, whatever `config/ads.json` says. Config may only tune the adult path, and even there the rating is clamped to G or PG (a mixed-audience Families app shows adults at most PG). Firebase never starts for a child. The manifest also removes `FirebaseInitProvider`, so Firebase cannot auto-start before the age answer. Ad-ID and SSAID collection are off in Firebase for everyone. Adults grant only `analytics_storage`.

**No-ad fallback.** When AdMob has no rewarded ad ready (offline, no fill), the old placeholder countdown stands in, so a reward button the player tapped always works and the "offline-friendly" promise holds. A missing interstitial is simply skipped: never a blank forced screen.

**Gradle build tooling.** `build_apk.bat` runs `tools/android_template.py`, which installs Godot's build template into `android/build/` (git-ignored, like the editor's "Install Android Build Template"). It also fetches Gradle resumably, because the wrapper's own 10 s timeout failed on this connection, and adds the google-services Gradle plugin, applied only when `google-services.json` exists. The Firebase `.aar` files in `android/firebase_*/` are committed (the export plugin reads them from there). `google-services.json` lives in the project root, is git-ignored and excluded from the PCK, and is copied into `android/build/` at export.

## v2 integration and calibration (2026-11-12, Task 13)

**Merge.** CORE, VIEW + COMBAT (one shared worktree), ECON, UX, FINALE, BRAND and SDK are merged; every conflict keeps both intents. The boot screens play first, then the age screen (only on a first launch, before any SDK), then the flow. The best-buy hand in the lobby points at the Station or the Armory with UX's PointerHand and its icon tag. LevelSim applies the Armory multipliers and the district squad cap. Each file keeps dev's line endings (`config/units.json` back to LF, `ASSETS.md` back to CRLF).

**One firepower.** `Economy.firepower` is now `Squad.firepower` on the upgraded stats, with the hero at full tap rate. The lobby's Squad Power, each level's recommended power and the HUD's live number are one calculation, and the HUD shows it in the lobby's format (`Economy.fmt_power`, so a +0.2 knife step reads 3.2 in both places). One side effect: splash now counts in the pointer's value for commandos, the way the HUD counts it.

**The calibration profile** (spec v2 calibration rule 2). `tests/econ_model.gd` records the no-ad pace: the upgrades its player brings into each level (`_local/pace.json`; `tune.gd profile=paced` = those upgrades, 4 taps/s, no shield or bomb). Level 1 is played with nothing, because a brand-new player goes straight into it. The pace check (`no_ad_pace_reaches_every_level`) is stricter than the plan asks. Its player earns only by playing (first wins plus missions, star chests and liberation; no ads, no city and no daily rewards) and buys only squad progress. It still affords the pace at every level with 0 replays, because these coins run about 1.6 times ahead of the pace's squad spending.

**Levels 1-3 open with the hero alone** against a gang that calibration never rescales (`gen_levels.py OPENING`: 5, 8 and 9 thugs). Light tapping (1.5/s) wins L1. Only a tapping hero (about 4/s) wins L2-L3, and a non-tapper loses all three. From L4 on the followers carry the fight, and a non-tapper wins every level with the stored route. The tap numbers in `units.json` are unchanged.

**Calibration ran win-rate only (`ratio=0`) with powers off.** In districts 2-5 the last-wave ratio fit never worked: the best route ends at or near its cap, so even ×4 could not dent it. Each failed fit also multiplied kf by 1.5, and it cost about 10 minutes per level. Stars still come from the best route's finish. L7, L23 and L31 were refitted on the report's own 100 routes (`fit_routes=100`), because their 48-route fit landed up to 11 points off. That was sampling noise, not the generator, so the generator's wave mix was not changed. Every level now ends within 10 points of its target.

**Upgrades gate progress** (rule 1). In the `need_upgrades` levels (18, 28, 29, 34, 37, 38, 42, 47 and 50), even the best route a tapping player can find loses with zero upgrades, while the pace wins whether it taps or not. `tune.gd` grows the last wave until that holds and refits the earlier waves. District 1 cannot be held to that bar on the win curve. A last wave that beats a capped zero-upgrade squad also beats 85-98% of random routes (L8-L10 tried: 2-13% wins against 45-54% targets; at L7 even an 8× last wave did not stop a zero-upgrade squad; L20, L40, L45 and L49 fell 7-16 points under their targets the same way). District 1's gate is milder: with zero upgrades the planned route fails at L10. From district 2 on it fails in 4 levels per district (17-20, 25-29, 34-40, 42-50).

**A gang firing at the squad takes the fire first.** Stopped gunmen stand at 26 m, outside CORE's 15 m gang priority, and halt the street. A squad behind a climbing red gate therefore shot the gate forever while the gunmen killed it troop by troop. This caused about a quarter of L4's random-route losses. Now any gang with guns in range (return fire or a stopped shooter) is shot before lane objects.

**Bottle Shot coins follow the level, not only the district cap.** Calibrated levels end far below their cap: L40's best route finishes with 1,066 of 25,000 troops. Under COMBAT's cap rule a winning run paid 6-55 district-1 troops in late levels, against the economy model's 115-145. So a level's `coin_ref` (its stored route's finish, written by `gen_levels.py`) now pays like a full district-1 squad, never more than the cap rule's maximum. Winning random routes now pay 41-167 against the model's 71-145, so the pace stays reachable.

**`formation_half_width` stays 1.4** (spec §4 wants a wide squad to brush the next lane). Measured: a lane-centred squad of 20-40 loses 1 troop to an obstacle in the next lane, and other sizes lose none (at 1.3 nobody would).

**The new-item card is pre-warmed.** The card, its outline and badge, and every hint icon and number in the level draw nearly transparent while the level loads. L13's first SWAT card had cost a 99 ms frame (a canvas pipeline compile, then texture and glyph uploads).

**Tap analytics are wired** (spec §2). Each hero tap feeds `Analytics.note_tap` (10 s buckets: tap fatigue), and `level_end` carries `taps_per_min` (wins and losses by tap band). A SceneTree script (tests, tools) never writes the player's event log, even before the Analytics autoload's `_ready`.

**Builder decisions recorded here at their request.**
- FINALE: the docks' upper rows stand on a plank on two posts, because crates hid the lower bottles. The carnival shelves are thin, with a flush lighter edge, because the old lip hid the necks. The bar and rooftop string lights hang above the tallest bottle. The L10 knife lens is 0.5° wider (spec §12.1).
- BRAND: the save stays at `%APPDATA%/Godot/app_userdata/Troop` through `custom_user_dir_name`. The boot screens play only on a plain launch (any debug arg skips them, `boot=1` forces them).
- UX: one hint language. Gesture hands appear only in gesture lessons. A new object gets the top card (icon ▸ effects) and a gold outline, never a hand. A menu hand always carries the item icon and before ▸ after. The old HUD hint hand is gone.
