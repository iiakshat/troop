# Siren Squad v2: brand, tap-to-fire hero, armory, polish, real ads (2026-11-12)

Builds on `2026-11-08-troop-v1-design.md` and `2026-11-09-troop-v1.1-feedback.md`, which still hold unless this document changes them. Same rules: every number lives in `config/`, the arithmetic stays exact, icons and numbers instead of words, original assets only, and no deceptive patterns.

## Why

The owner played v1.1 on a phone. Verdict: "okayish, promising, but it feels built for a 5-6 year old, and not convincing enough to put money into."

- The two best parts are **making decisions** (gates and lanes) and the **Bottle Shot finale**.
- What makes Bottle Shot good is **aiming yourself**: you want to aim better next time, and a hit makes you feel like a badass.
- The main runner is what a new player sees first, and it is less fun than the finale. Most of this round goes into it.

"Grown up" does **not** mean a darker or realistic art style. It means **Subway Surfers-level production quality**, which every age enjoys:
- everything looks finished
- clean colour
- every object explains itself
- the game runs smooth
- a proper studio intro and branding

## Goals

1. The main runner is as enjoyable as Bottle Shot: the player's own input matters, and it is smooth with no hitches.
2. Coins always have something worth buying. Power comes from weapons, and later levels need upgrades.
3. A brand: name, logo, studio intro, loading screen, app icon and package ID.
4. Fix every v1.1 problem the owner found.
5. Real ads and analytics, safe for a mixed audience that includes children.

## Non-goals

- New Bottle Shot features. The owner: "don't overdo it, it's already good." Only fix what is broken there.
- New playable heroes with different abilities. Heroes are cosmetic only.
- New characters before the owner's Mixamo files arrive (see §9).
- Online features, IAP, or the store listing text (a later round).

## Anti-goals (a failure even if it works)

- **No slow motion and no pauses in the middle of a level**, for any reason except the first-run tutorials. That includes rank joins, standoffs and big crowds.
- No on-screen fire button. Tapping is an invisible zone.
- Real gun brand names (Glock, Desert Eagle, MP5, AK-47 and so on).
- Photo-real weapon art.
- Anything a child-audience review would flag.

## Approaches considered (decided)

- **Bringing aim into the runner.**
  - Considered: (A) tap any target to throw the hero's knife; (B) slow-motion aim moments; (C) A+B.
  - Owner rejected all three: they add friction or interrupt the flow.
  - **Chosen:** the hero's fire rate rises with tapping (§2). The owner noted there is no public data comparing auto-fire with tap-to-fire, so the round adds analytics to measure it.
- **Weapon names.** Real brands rejected because of trademark risk. **Chosen:** our own realistic-sounding names plus real calibres.
- **Audience.** 13+ only was rejected. **Chosen:** a mixed audience with a neutral age screen (§8).
- **Weapon art per age.** Rejected: the content rating covers the whole app, so realistic art for adults would raise it for everyone. **Chosen:** one premium stylised look (Brawl Stars / Fortnite style) for everyone.
- **City map.** Kept as the level route and as idle income that feeds the armory. Weapons are now the main thing to buy (Claude's call; the owner can change it).

## 1. Brand

- **Name: Siren Squad.**
  - Checks so far: no Google Play result, no game found on the web or the App Store, no trademark found in US aggregators.
  - **Owner:** check the Indian register at ipindia.gov.in (Public Search, word "SIREN SQUAD", classes 9 and 41) before the first upload.
- **Package ID:** `com.iiakshat.sirensquad` (owner confirmed). Set it in `export_presets.cfg`. Project name and window title: "Siren Squad". The repo and folder keep the name `troop`.
- **Boot sequence:**
  1. **axnex studio intro**: about 2 s, the animated axnex wordmark plus a short original siren "whoop".
     - The first launch plays it in full; later launches can skip it with a tap.
  2. **Siren Squad logo**: a light-bar siren motif in police blue and red, with the logo sting.
  3. **Loading screen**: logo, an animated siren-light loading bar, and rotating icon-only tips (pictures, no words).
  4. Then the existing boot flow.
- Words in the logos are the brand exception to the no-words rule. Add it to spec §0's exception list.
- **Assets:**
  - app icon: adaptive Android icon, foreground and background
  - splash colour
  - the axnex mark (vector, made by us)
  - the Siren Squad logo (vector or Gemini plus clean-up)
  - a Play feature graphic (1024×500)
  - Log all of them in `ASSETS.md`.
- **Siren sounds** (original, synthesized in `tools/make_sfx.py`):
  - the intro whoop
  - a short "chirp" when backup joins (not a loop, and throttled)
  - optionally a whoop on liberating a district

## 2. Tap-to-fire hero

- **The hero's knife rate** = `hero_auto_rate × base` when idle, rising to `1.0 × base` (today's rate) with tapping.
  - Start with `hero_auto_rate = 0.4`.
  - Each tap adds `tap_heat` and the heat decays over about 1 s, so steady tapping at about 4 taps/s holds full rate.
  - All of these numbers go in `units.json` under `hero.tap`.
- **Followers are unaffected**: they always fire at full rate.
- **Tap zone:** the lower half of the screen, with no button. Telling a tap from a swipe:
  - a touch that moves under ~15 px (scaled for screen density) and lifts within ~0.25 s is a **tap**; it fires and never steers
  - anything else is a **swipe**; it steers and never fires
  - Thresholds go in config.
  - Rapid taps must never move the lane. A swipe that starts as a tap must not fire.
  - Tests use recorded touch sequences: tap-tap-swipe, swipe-tap, two fingers.
- **Feedback:**
  - a small heat arc around the hero's feet, from cold to hot
  - knives visibly faster
  - a subtle hand-flick on each tap
- **Difficulty:**
  - Levels before the first follower joins (about L1-3; check with tune) are tuned for a tapping player and are hard or impossible without tapping.
  - Once followers carry the fight, good decisions win without tapping, bosses included. Tapping still adds damage and finale coins.
- **Sim and autopilot:**
  - `LevelSim` takes a tap-heat input.
  - The autopilot has a `tap_rate` parameter: a tapping player (about 4/s) and a non-tapper (0).
  - `tune.gd` reports both.
  - Win targets: the existing curve applies to the tapping player. Non-tappers must lose L1-L3 and must be able to win every level from about L6 on with stored decisions. The builder confirms the exact cut-over from tune output.
- **Analytics:**
  - taps per minute per level, and how it changes within a level (tap fatigue)
  - wins and losses split by tap rate band
  - These answer the owner's "we need data" question.

## 3. Smoothness

- Remove the 0.3× new-rank spotlight. The ring and toast stay; time stays at 1.0.
- No `Engine.time_scale` changes and no pauses in a level, except the tutorial steps on the first run.
- The standoff brake (about 0.3 s) stays, because it is a stop and not a slow-down.
- **Find and fix the hitch when followers join.** Profile it first. Suspects:
  - a first-use shader or material compile
  - MultiMesh buffer resizing
  - per-join node or tween creation
  - The fix: pre-warm every crowd, effect and rank material at level load, and size buffers to the cap once.
- **Frame-time pass:**
  - big crowds (150+)
  - explosions
  - the first gang
  - the boss arrival
  - the transition into the finale
- **Target:** 60 fps on a mid-range phone, and no single frame over 50 ms during a level. Add a debug frame-time log (`perf=1`).

## 4. Camera and formation

- Move the squad lower: hero at about 25% of screen height from the bottom, followers about 18-20%. This shows more street ahead.
  - The owner's numbers are visual estimates; match the look, not the exact numbers.
- Spread followers wider, about one lane wide at full size.
  - A wide squad can now brush obstacles in the next lane. That is intended: steering matters more.
  - Re-tune `formation_half_width` and re-calibrate every level.
- Fix the grey and purple smudge in the middle of big squads (overlapping figures or headgear); see the owner's screenshots.

## 5. Fixes from the play-test

- **Kingpin invisible.** The boss HP bar ("111") floats over the stash, but the boss is not visible (likely hidden by the v1.1 stash set or placed behind it). Bosses must walk out in front of the stash and be clearly visible for the whole fight.
- **Explosive barrel (the "red-yellow box").** Make it self-explanatory:
  - a red oil drum with a hazard flame icon
  - shooting it fills a fuse ring, and when it's full it blinks
  - when the next gang reaches it, a big readable blast shows the kill count
  - Never a box.
  - Contact with an armed barrel hurts the squad as the config says. Decide whether an unarmed barrel blocks; it must not read as "rubber".
  - Add the barrel to the tutorial set: the first time one appears, a one-time ghost hand shows shooting it. That is a first-run pause, which is allowed.
- **Bottle Shot:**
  - Remove the semi-transparent rectangles behind bottles (the glass or refraction quads show on Mobile/GL).
  - **Bow:**
    - the camera must not follow the swipe (no scene sway)
    - several bottles visible at once
    - the nocked arrow must read as an arrow: a real head, fletching and shaft thickness, not a "matchstick"
    - the wind indicator shows a clear arrow and strength (no "0.0" with a full arrow)
    - every arrow in the quiver must be usable
  - Pistol and bow models: premium stylised models replace the box primitives. The weapon must not block the targets.
  - No other Bottle Shot changes.
- **Colour.** Remove the heavy orange haze. Do a balanced colour grade per district (fog colour and density, sun tint, exposure, saturation) so the street, the squad, threats and pickups each read clearly. Bright and clean like Subway Surfers, not sepia.
- **Red gate in front of a gang** (Claude's call): a gang within about 15 m of the squad takes priority over gates and obstacles, so the squad never shoots a gate while a gang walks in.
- **Off-curve levels** (L12, L22, L23, L30): fix through the generator (wave mix or row count) so each lands within ±10 points of its target.

## 6. Armory: the coin sink

- **A weapon track for every weapon in the game:**
  - hero knives
  - Constable pistol
  - Sergeant shotgun
  - Inspector revolver
  - SWAT rifle
  - Sniper rifle
  - Commando launcher
  - the Bottle Shot weapons (pistol, bow, stars, sniper)
- **Locked weapons** show a visual lock and "unlocks at level N" (the unlock level of their rank or district; the number and level icon only).
- **Tiers:**
  - Each weapon has tiers (start with 4).
  - Each tier needs several purchases (start with 5). Each purchase adds a small stat step and fills a bar.
  - When the bar is full, the weapon **evolves**: a new name, a new calibre or ammo, a visibly better model and a stat jump.
  - Bottle Shot weapons upgrade only things that make them easier to handle: magazine, steadier scope, draw speed. No auto-aim.
- **Names:** our own, realistic-sounding (for example "Viper 9", "Desert Hawk .50", "Bulldog 12-gauge"), with real calibres (9mm, .45 ACP, .50 AE, 12-gauge, 5.56, .308). No real brand or model names. Run every name through a quick web check for collisions with real products.
- **Armory screen:**
  - premium stylised art for each tier (Gemini sheets, few requests, many items per sheet)
  - name and calibre
  - stat bars with before ▸ after
  - the tier bar
  - an evolve celebration
  - It replaces the Police Station's knife and speed rows.
  - The Station keeps starting squad, squad cap and coin bonus. Charges move to §7.
  - Squad Power, the loss tip and the "best next purchase" hand include weapon upgrades.
- **In the level:** the same low-poly weapons, recoloured and slightly reshaped per tier, so performance stays light.
- **Difficulty:**
  - From mid district 1 (about L5-L7) on, the levels assume a player who spends coins on weapons at the expected pace: gently at first, then more. A player who never upgrades stalls in late district 1 or early district 2.
  - Good decisions still matter as much as power.
  - Extend `tests/econ_sim.gd` so coins (with and without the x2 ad) → upgrades → power keep each level's win target, and show 1-3 meaningful buys after most wins.
- **Hero skins:** cosmetic only, sold for coins in the existing Style panel. Outfits for the current hero model now; Mixamo heroes later.

## 7. Powers: shield and bomb

- One free shield and one free bomb. Each recharges **5 hours** after use (owner).
- The recharge uses the real clock and is guarded against setting the clock back (reuse the daily calendar's guard).
- "Refill now" with a rewarded ad: the placeholder popup now, real AdMob after §8.
- Extra charges from daily rewards, spin, chests and boosters still exist as stored items on top of the free ones.
- Every level must be winnable without powers. Re-calibrate.
- The Station's charge rows are removed. Save migration keeps existing charges as stored items.

## 8. Real ads and analytics (mixed audience)

- **Target audience: includes children** (owner), so this is a mixed-audience setup.
- **Neutral age screen** on first launch:
  - a birth-year wheel (numbers only, no "are you a kid" wording)
  - stored locally
  - Under 13 counts as a child. **If the device region or locale is India, under 18 counts as a child (DPDP Act).**
- **AdMob**, through a maintained Godot 4 Android plugin (the builder picks it and checks it against Godot 4.7.2):
  - **Child:**
    - child-directed tag on
    - max ad content rating G
    - non-personalised ads
    - no advertising ID
  - **Adult:**
    - normal ads
    - Google UMP consent form for GDPR regions
  - Placements: the existing `Ads` stub placements (rewarded and interstitial, with the same frequency rules).
  - Use Google's official **test ad unit IDs** until the owner sends real ones.
  - IDs go in `config/ads.json` (not secret). The placeholder popup stays as the fallback when there is no network or under autoplay.
- **Firebase Analytics**, through a Godot 4 Android plugin, behind the existing `Analytics` interface:
  - Ad-ID collection is always off.
  - For children, the minimum events with no identifiers.
  - `google-services.json` is git-ignored; the owner adds it.
  - The local JSON log stays for PC and debug.
- **Privacy:**
  - a privacy-policy draft at `docs/PRIVACY.md`, ready to host
  - Data Safety form answers in `docs/play_data_safety.md`
  - A Families-policy checklist.
- **Owner checklist** (10 minutes): create the AdMob app and ad units, create the Firebase Android app with the package ID, download `google-services.json`, and send the IDs.
- **Content rating:** keep the game in the "cartoon violence" range. Defeated enemies fall and fade (no blood), and weapon art is stylised.

## 9. Mixamo characters (waiting on the owner)

- The owner is downloading Mixamo characters and animations into `art_src/mixamo/`. They will send a message when done.
- **Repo rule:** `art_src/mixamo/` is git-ignored, because the repo is public and Adobe's terms forbid sharing the raw files. Only the baked in-game data is committed.
- **When the files arrive:**
  - extend `tools/bake_vat.gd` to import the FBX characters and retarget the Mixamo clips onto the clip table (run, idle, pistol run, rifle run, throw, death, hit, shoot, punch, victory, boss walk)
  - re-bake
  - keep the cartoon look and the toon shader
  - Until then, polish the current characters only (§4 smudge, boss visibility).

## 10. Process notes

- Remove the owner's five screenshots (`WhatsApp Image 2026-11-12 *.jpeg` in the repo root) from the repo in this round's first commit. They are untracked, so delete them and never commit them.
- Update `CLAUDE.md`, `DECISIONS.md` and `ASSETS.md`.
- Git flow as before: `dev`, a green local build, then fast-forward `main` and push.

## 11. Hints and pointers: one clear visual language

- **Owner's problem.** The ghost hand that appears mid-level (the `hint` events in the level files: sergeant, pothole, armour, barrel and so on, plus the gate-pick lesson) is ugly and unclear. You can't tell whether it means "something new unlocked", "go this way", or just "this exists", and it points in arbitrary directions.
- **Rule:** each kind of message gets its own look, never shared:
  - **Teaching a gesture** (first run only: drag, tap-to-fire, the bottle weapons):
    - an animated hand that performs the gesture (a tap ripple, a swipe trail) where you should do it
    - the screen dimmed around it
    - This is the only use of the hand in a level.
  - **"This is new"** (a new enemy, obstacle, rank or power appears for the first time):
    - no hand
    - the object gets a pulsing gold outline and a small "new" burst badge (sparkle + "!")
    - a one-time icon card slides in at the top edge: the object's icon, then ▸ its effect as icons and numbers (barrel: shoot → fuse → blast kills N)
    - No freeze. It disappears by itself after about 2 s.
  - **"Best choice here"** (only for the first gate lesson):
    - green chevrons painted on the road leading into the best lane
    - a result preview above the gate (squad 16 ▸ 48)
    - No hand pointing sideways.
  - **"Buy this" in menus** (best next purchase, loss tip): the hand stays, bouncing *on* the button, always next to the item's icon and the before ▸ after number.
- **New hand art:** a glossy, polished cartoon hand in the game's style, replacing the current one, with a soft shadow.
- Remove every hand that points at nothing in particular. Each hint must be anchored to its object and follow it on screen.

## Calibration, migration and data rules (Claude's calls after the builder check)

1. **Upgrades gate progress, fairly.** This replaces v1's "every level is winnable without purchases" (the owner: upgrading should be required).
   - **It starts gently in district 1** (owner): from about L5-L7 a few cheap weapon steps are needed. The requirement grows from there, and §6's "from district 2 on" wording changes to match.
   - Every level stays winnable with what a player can buy from coins earned by playing, with **no ads**. Replaying earlier levels for coins counts.
   - Ads only speed this up.
   - Squad Power and the loss tip become real guidance, not decoration.
2. **The calibration profile** for the win-target curve:
   - a tapping player (about 4 taps/s)
   - the no-ad upgrade pace from `econ_sim`
   - no powers, no boosters
   - Checks on top of that:
     - a non-tapper with the same upgrades must win every level from about L6 on with stored decisions
     - a non-tapper must lose L2-L3
     - everything stays winnable with zero powers
3. **Save migration v3 → v4:**
   - Station knife and speed levels convert into hero-knife track progress worth the coins already spent (rounded up, never less).
   - Garage levels convert once into stored shield and bomb charges equal to what that level gave (shield ceil(lv/2), bomb floor(lv/2)).
   - Nothing bought is lost.
4. **Children's data:**
   - For a child (under 13, or under 18 in India), Firebase is **not started at all**; events stay in the local log only.
   - Tap-rate and retention analytics come from adult sessions only. That is enough to answer the tap question, and the Data Safety answers stay simple.
   - The age-screen result decides this before any SDK starts.
5. **Level 1 for a brand-new player:**
   - L1 needs only light tapping and teaches it: a first-run ghost-hand tap lesson (tutorial pause allowed) shows that tapping the lower half speeds the hero up, and the game waits for a few taps.
   - The steeper "hard without tapping" bar applies to L2-L3.
   - Revive still exists.
6. **Upgrades and the arithmetic:**
   - Weapon upgrades change **damage and rate per troop**, never troop counts. "+N" gates still add exactly N troops.
   - Codex "= N constables" values compare the player's current upgraded stats.
   - The hero's PISTOL pickup uses tap heat but not the knife track.
   - Squad Power uses upgraded stats.

## Left to the builder

- exact tap, heat and threshold numbers within the stated ranges
- the AdMob and Firebase plugin choice
- tier stat curves and prices (driven by the econ sim)
- weapon names that pass the collision check
- logo and intro animation details within the stated concept
- the colour-grade values
- how to profile and fix the join hitch
- the work order and how to split it among builders
