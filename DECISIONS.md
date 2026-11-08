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

**Local APK builds, minimal toolchain** (owner: "setup locally… only install what's needed", 2026-11-08). Godot's non-Gradle export only needs adb, apksigner and a Java runtime, so `tools/setup_android.py` installs platform-tools, build-tools 36 and a Temurin 17 JRE (not the JDK), and pulls just the Android templates out of Godot's 1 GB pack with HTTP range requests. About 500 MB total; no Android Studio. The build runs at below-normal CPU priority. After a green local build, `main` is fast-forwarded to `dev` by hand (replacing the CI promote job while Actions is locked). The debug APK is about 70 MB because it carries the engine for both 32- and 64-bit phones; Play's per-device split will make a store download much smaller.
