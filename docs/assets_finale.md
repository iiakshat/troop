# Bottle Shot finale: assets (v1.1)

Everything new in the finale this round is built in code from Godot primitives (boxes,
cylinders, spheres, SurfaceTool meshes) and drawn UI. No files were downloaded or generated,
so there is nothing to license or credit.

| Asset | Where | Made from |
|---|---|---|
| Pistol (slide, sights with white dots, frame, magazine, gloved hands, sleeves) | `src/finale/weapon_models.gd` `pistol()` | boxes, cylinders |
| Spare / dropped magazine, brass casings (pistol and rifle) | `weapon_models.gd` `magazine()`, `casing()` | boxes, cylinders |
| Bolt-action rifle with scope and bolt | `weapon_models.gd` `rifle()` | boxes, cylinders, sphere |
| Recurve bow with live string and pin sight, arrows | `weapon_models.gd` `bow()`, `bow_string()`, `arrow()` | boxes, ImmediateMesh lines, cylinders |
| Four-point throwing star | `weapon_models.gd` `star()` | SurfaceTool mesh |
| Bullet (sniper bullet cam) | `weapon_models.gd` `bullet()` | cylinders |
| Clay jug (decoy) | `src/finale/bottle_shot.gd` `_jug()` | sphere, cylinders, torus |
| Steel ricochet plates | `bottle_shot.gd` `_build_wall()` | boxes |
| Stash sets: back-alley bar, carnival stall, docks crates/containers, factory conveyors, rooftop lounge (+ our roof) | `src/finale/finale_stash.gd` | boxes, cylinders, existing `planks.gdshader` |
| Street-end stash facades per district, neon bottle sign | `finale_stash.gd` `facade()`, `neon_bottle()` | boxes with emissive materials |
| HUD glyphs: bullet, arrow, star, flame, wind arrow, magazine with swipe chevrons | `src/finale/finale_hud.gd` `Glyph` | `_draw()` polygons and lines |
| Sniper scope mask and duplex crosshair | `src/finale/weapon_sniper.gd` `ScopeOverlay` | `_draw()` |

Sounds reuse existing recordings (`shot`, `shot_sniper`, `clink`, `tick`, `thunk`, `swoosh`,
`glass_break`, `blocked`, `punch`, `boom`) at different pitches; no new audio files.
