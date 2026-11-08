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
