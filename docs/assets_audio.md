# Audio assets (AUDIO builder, v1)

Rows for `ASSETS.md`. All sound files are mono 44.1 kHz OGG Vorbis built by
`python -I tools/make_sfx.py <downloads_dir>` from the recordings below (trimmed, silence
cut, faded, levelled; recipes and the exact slices are in the script). Downloads lived in a
temp folder outside the repo and were only decoded with ffmpeg. OGA = OpenGameArt; a file
URL is `https://opengameart.org/sites/default/files/<file>`.

## Sound effects

| Files in `assets/audio/` | Source | Licence |
|---|---|---|
| `glass_break, glass_break2, glass_break3` (the bottle smash) | Gravity Sound, *Glass breaking*, *Glass breaking 2*, *Glass breaking 4* (Wikimedia Commons, `File:Glass_breaking_(Gravity_Sound).wav` etc.) | **CC BY 4.0: credit required** |
| `glass_break4` | spookymodem, *Breaking Bottle* (OGA `Bottle%20Break.wav`) | **CC BY 3.0: credit required** |
| shard tails in `glass_break*`, `glass_tinkle*` | rubberduck, *75 CC0 breaking/falling/hit sfx* (OGA `sfx_breaking_and_falling.zip`); ignasd, *Ice breaking/shattering* (OGA `IceShatters_0.zip`) | CC0 |
| low knock under `glass_break*`, `hit*`, `pothole*` | qubodup, *independent.nu ljudbank hits and punches* (OGA `independent_nu_ljudbank-hits_and_punches.7z`) | CC0 |
| `shot_sniper*, snipe*, shot_shotgun*` | Vincent Sevedge ("Tabasco"), *gunshot sounds* (OGA `sounds.zip`, mosin/shotty takes; same pack as the existing gunshots) | **CC BY 3.0: credit required** (already credited) |
| `launcher*` | rubberduck, *25 CC0 bang sfx* (OGA `25-CC0-bang-sfx.zip`) | CC0 |
| `boom*` | Joth, *Chunky Explosion* (OGA `Chunky%20Explosion.mp3`); TinyWorlds, *explosion* (OGA `explosion.wav`); Kenney, *Sci-fi Sounds* (OGA `sci-fi_sounds.zip`) | CC0 |
| `punch*` | qubodup, *Punch* (OGA `qubodupPunch.7z`) | CC0 |
| `die*` | qubodup, *Thwack* (OGA `thwack-1.0.zip`, LICENSE.txt = CC0) | CC0 |
| `hurt*` | qubodup, *slight screams* (OGA `slightscreams.7z`) | CC0 |
| `pothole*` (groan) | EmoPreben, *Pain sounds* (OGA `painsounds.zip`) | CC0 |
| `blocked*`, `build2`, `build_done` (hammer), `unlock` (lock) | rubberduck, *100 CC0 wood and metal SFX* (OGA `100-CC0-wood-metal-SFX.zip`) | CC0 |
| `build` | themightyglider, *craft* (OGA `craft_0.ogg`) | CC0 |
| `boss_roar*` | HaelDB, *yelling sounds* (OGA `yelling%20sounds.zip`); trazzz123, *monster roar* (OGA `monster_roar.wav`); rubberduck, *80 CC0 RPG SFX* (OGA `80-CC0-RPG-SFX_0.zip`) | CC0 |
| `fire*` | themightyglider, *flame* (OGA `flame_0.ogg`); qubodup, *ignition* (OGA `ignition.flac`); rubberduck, *80 CC0 RPG SFX* | CC0 |
| `shield` | Kenney, *Sci-fi Sounds* | CC0 |
| `knife` (one take, fixed pitch) | artisticdude, *swishes* (OGA `swishes.zip`, swish-9) | CC0 |
| chime in `coin, coin_bag, collect, star1-3, unlock, chest_open, daily_claim, mission_done, build_done` | rubberduck, *100 CC0 SFX* (OGA `100-CC0-SFX_0.zip`, `bell_02`), one real bell strike re-tuned to C-major notes | CC0 |
| coins in `coin, coin_bag, collect, daily_claim, spin_win` | starninjas, *coins* (OGA `coins_-_starninjas.zip`); Kenney, *RPG Audio* (OGA `RPGsounds_Kenney.zip`, handleCoins); rubberduck, *80 CC0 RPG SFX* (item_coins) | CC0 |
| sparkle in `star1-3, chest_open, mission_done` | bobjt, *gem gather* (OGA `gem-gather-mono-files.zip`) | CC0 |
| `chest_open` (lid) | oiboo, *open chest* (OGA `open%20chest_0.wav`) | CC0 |
| `spin_win` | fvcalderan, *fanfare* (OGA `fanfare_3.ogg`) | CC0 |
| `spin_tick` | Kenney, *Interface Sounds* (OGA `kenney_interfaceSounds.zip`) | CC0 |
| `rank_up, gate_bad` | Kenney, *85 Music Jingles* (OGA `jingleSounds_Kenney.zip`) | CC0 |

Removed: `glass, glass2, glass3` (replaced by `glass_break*`), `crash` (unused; `crash` plays
`boom`), `music_fight` (XCVG; nothing played it). The XCVG credit line can go.

Unchanged from v0.3 (rows already in `ASSETS.md`): `tap, upgrade, error, banner, recruit,
swoosh, tick` (Kenney Interface Sounds), `win, lose, gate_good, flip` (Kenney Jingles),
`thunk, clink` (rubberduck), `shot, shot2, shot_big, shot_rifle, blast` (Tabasco, CC BY 3.0).
`punch`/`punch2` were rubberduck takes and are now qubodup's punches.

## Music

| Files | Source | Licence |
|---|---|---|
| `music_menu.ogg, music_level.ogg, music_boss.ogg` | Generated for this game with Google Lyria (`tools/lyria_music.py make`), then cut into whole-bar loops with a crossfaded seam and normalised to -14 LUFS (`tools/lyria_music.py loop`). Raw clips: the first AUDIO worktree's `_local/music_raw/`. | Generated output (Google Gemini API terms); no third-party samples |

Checked in this round: all three loop cleanly (seam jump under the track's normal
sample-to-sample movement), -14 LUFS, peaks -1.1 to -2.7 dBFS. No new Lyria requests.

## Credit lines for `SettingsPanel.CREDITS`

- `Glass: Gravity Sound (CC BY 4.0), spookymodem (CC BY 3.0)`
- Keep `Gunshots: Vincent Sevedge (CC BY 3.0)`.
- `Sounds: Kenney, rubberduck, qubodup and OpenGameArt artists (CC0)` replaces `Sounds: Kenney, rubberduck (CC0)`.
- `Music: made with Google Lyria` replaces `Music: XCVG (CC0)`.
