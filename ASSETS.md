# ASSETS.md: every asset and its licence

Research notes, verified URLs and checks are in `docs/ASSET_SOURCES.md`. Everything below is free for commercial use. Only game-icons.net needs attribution; it's on the in-game Settings → credits panel.

| Asset (in repo) | Source | Licence |
|---|---|---|
| `art_src/characters/*.fbx` (Casual2/Casual3/Casual_Bald/Worker/Suit/BlueSoldier/Soldier) | Quaternius, *Ultimate Animated Character Pack* (Nov 2019), opengameart.org/sites/default/files/ultimate_animated_character_pack_by_quaternius.zip | CC0 1.0 |
| `assets/characters/*_mesh.res`, `*_vat.res` | Baked by us from the Quaternius models (recoloured, weapons added) with `tools/bake_vat.gd` | CC0 source + our own |
| `assets/env/commercial/*` | Kenney, *City Kit (Commercial) 2.1*, OGA kenney_city-kit-commercial_2.1.zip | CC0 1.0 (`License.txt` inside) |
| `assets/env/roads/*` | Kenney, *City Kit (Roads) 2.2*, OGA kenney_city-kit-roads_2.2.zip | CC0 1.0 |
| `assets/env/cars/*` | Kenney, *Car Kit 3.1*, OGA kenney_car-kit_3.1.zip | CC0 1.0 |
| `assets/env/food/*` (knife model, barrel, bottle shapes) | Kenney, *Food Kit*, OGA kenney_food-kit.zip (sha256 cdad9085…96f6f) | CC0 1.0 |
| `assets/env/bits/*` (hydrant, bench, bins, bush, box) | Kay Lousberg, *KayKit City Builder Bits 1.0*, GitHub KayKit-Game-Assets @63976910 | CC0 1.0 (`LICENSE.txt`) |
| `assets/ui/*.png` (glossy buttons, stars) | Kenney, *UI Pack 2.0*, OGA kenney_ui-pack.zip | CC0 1.0 |
| `assets/icons/*.svg` | game-icons.net by Lorc, Delapouite, Skoll, Sbed, Andy Meneely, Guard13007 (`LICENSE-game-icons.txt`) | CC BY 3.0: **credit required** (in-game credits) |
| `assets/fonts/LuckiestGuy-Regular.ttf` | Google Fonts (apache/luckiestguy), Astigmatic | Apache 2.0 (`LICENSE-LuckiestGuy.txt`) |
| `assets/fonts/LilitaOne-Regular.ttf` | Google Fonts (ofl/lilitaone), Juan Montoreano | SIL OFL 1.1 (`OFL-LilitaOne.txt`) |
| `assets/audio/tap, upgrade, error, banner, recruit, swoosh, tick` | Kenney, *Interface Sounds*, OGA kenney_interfaceSounds.zip | CC0 1.0 |
| `assets/audio/win, lose, gate_good, flip` | Kenney, *85 Music Jingles*, OGA jingleSounds_Kenney.zip | CC0 1.0 |
| `assets/audio/glass*, thunk, punch*, clink, crash` | rubberduck, *75 CC0 breaking/falling/hit sfx*, OGA sfx_breaking_and_falling.zip | CC0 1.0 |
| `assets/audio/knife*, coin_bag` | Kenney, *50 RPG sound effects*, OGA RPGsounds_Kenney.zip | CC0 1.0 |
| `assets/audio/music_fight.ogg` | XCVG, *fight_looped*, OGA fight_looped.ogg | CC0 1.0 |
| Gunshots, hits, explosions and other synth sounds | Synthesised at startup in `src/autoload/sfx.gd` | Our own |
| `icon.svg` (app icon) | Our own composition around the game-icons.net knife icon (`assets/icons/knife.svg`) | CC BY 3.0 (credited in-game) + our own |
| Bottles (lathe meshes + glass shader), bullets, particles, road and building shaders | Code in `src/finale/`, `src/game/` | Our own |

Add a row before adding any new asset. Prefer CC0. Anything CC BY must also go into `SettingsPanel.CREDITS`.
