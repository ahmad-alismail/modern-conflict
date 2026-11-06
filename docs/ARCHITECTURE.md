# Architecture

Modern Conflict is a Godot 4.7 (GDScript, Forward+) desktop game. The core idea is a strict split between a **deterministic simulation** and the **presentation**.

```
           commands (dicts)                     events (dicts)
 Player ─┐                    ┌──────────────┐                ┌─> WorldView (3D, fx, audio)
 ClassicAI ├─> SimWorld.issue ─>│  SimWorld    │──> drain_events ┼─> Hud (log, alerts)
 LLMCommander┘  (next tick)    │  20 Hz tick  │                └─> GameSession (game over)
                               └──────────────┘
                     state read every frame (interpolated) by WorldView / Hud / Minimap
```

## Simulation (`src/sim`, `src/map`)
No engine nodes. Plain `RefCounted` classes with a seeded RNG. The same setup plus the same command stream always produces the same battle.

| File | Responsibility |
|---|---|
| `defs.gd` | All data: weapons, 30 units, 3 factions, support powers. Factions differ by capability, not skin. |
| `map_def.gd` | Map schema shared by the generator, editor, importer, sim and renderer. Serializes to JSON. |
| `city_generator.gd` | Procedural fictional Middle-Eastern city. Recursive block subdivision into districts, perimeter blocks with courtyards, landmarks, props, war damage, objectives and spawns. |
| `nav_grid.gd` | 2 m grid. One `AStarGrid2D` per movement class (foot / wheeled / tracked), vehicle clearance, cover, DDA line of sight over building and wall heights. Runtime edits for collapsed buildings and wrecks. |
| `sim_unit.gd` | Unit state: squads with per-member health, vehicles, aircraft, weapons, morale, orders. |
| `sim_world.gd` | Tick loop, command validation, orders, movement and steering, garrison and transport, morale, objectives and tickets, victory, smoke. |
| `combat.gd` | Target selection, hit chance (cover, garrison, motion, suppression, night, weather, network link, EW), armor penetration by facing (front / side / rear / top), projectiles, splash, building damage and collapse, wrecks, critical hits, resupply, mines. |
| `detection.gd` | Team visibility (camouflage, firing reveals, garrison, thermal, sensor masts, drones heard at close range, smoke). Every consumer reads only this, so there is no hidden-information leak. |
| `support.gd` | Artillery, airstrike, recon UAV, smoke, rocket barrage, minefield, tunnel ambush, drone strike, EW burst. Also reinforcements. |
| `serializer.gd` | Full state capture and restore for save games. |

Replays store the initial map, the config and the command log (including AI and LLM commands). Playback re-simulates them.

## Commanders (`src/ai`)
- `commander.gd` is the interface: `think(world)` is called each tick, and orders go through `world.issue()`.
- `classic_ai.gd` is the offline AI. It has a strategic layer (objective scoring, force split, staged assaults), a tactical layer (garrison, smoke, retreat, focus fire, AT response, helicopter AA avoidance, FPV targeting) and support usage. Easy / Medium / Hard change decision quality only.
- `llm/` is the optional LLM commander (Ollama, OpenAI-compatible, Anthropic). It takes a fog-filtered `Observation`, validates the JSON orders it gets back, and falls back to the classic AI if it is unavailable.

## Presentation (`src/render`, `src/audio`, `src/ui`, `src/game`)
| Module | Responsibility |
|---|---|
| `game/game_session.gd` | Owns one battle. Fixed-step sim, tactical pause (the sim stops; camera, UI and orders keep working), speed control, routing. |
| `render/world_view.gd` | Builds the city and keeps a `UnitView` per unit. Turns events into effects and sounds. Respects fog. |
| `render/unit_view.gd` | Interpolation, squad member animation, corpses that stay where they fell, selection rings. |
| `render/fog_of_war.gd` | Viewshed ray marching against building heights, explored memory, full-screen depth-based fog pass. |
| `render/terrain_builder.gd` | Splat-shaded ground from the terrain grid, road markings, outskirts silhouettes. |
| `render/environment_rig.gd` | Sky, sun, time of day, weather, volumetric fog, quality presets. |
| `render/camera_rig.gd` | RTS camera that pitches from strategic to cinematic, follow mode, shake. |
| `render/building_builder.gd`, `prop_builder.gd`, `unit_models.gd`, `fx/effects.gd`, `audio/audio_manager.gd` | Procedural art behind the contracts in `docs/CONTRACTS.md`. |
| `game/player_input.gd` | Selection, context orders, targeting modes, hotkeys, order feedback. |
| `ui/*` | HUD, minimap, health overlay, menus, setup screens, settings, sandbox panel, scenario list. |
| `editor/*`, `map/image_importer.gd` | Map editor and image-to-map importer. |

## Testing
- `tools/gd.sh test` runs the headless tests in `tests/`: RNG, generator validity and reachability, LOS, penetration, combat outcomes, garrison, determinism, fog, AI fairness, LLM order validation, a full AI-vs-AI match, and the image importer.
- `tools/aivai_headless.gd` batch-runs AI-vs-AI matches for balance work.
- `tools/gd.sh shot` takes windowed screenshots for visual checks (`--screen=skirmish`, `--preview=<id>`, ...).
