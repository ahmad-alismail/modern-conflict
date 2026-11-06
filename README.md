# Modern Conflict

A modern-warfare real-time strategy game with **tactical pause**, built as a native Windows desktop app in Godot 4.7. You command forces in a fictional Middle-Eastern city. There is no base building and no economy: just decisions, consequences, and an opponent who reacts.

- **Three asymmetric factions**
  - *Coalition Defense Force*: armor, attack helicopters, thermal sights, artillery.
  - *People's Defense Brigades*: numerous concealed infantry, technicals, ambushes, tunnels, mines.
  - *Helix Autonomous Command*: robots and drones, sensor masts, EW jamming, and a network link its robots depend on.
- **A believable battlefield**
  - Line of sight through a real 3D city, with fog of war.
  - Cover and garrisoned buildings.
  - Suppression, pinning and broken morale.
  - Armor penetration by facing.
  - Limited ammo and resupply.
  - Smoke.
  - Destructible buildings that collapse into rubble, changing movement and sightlines for the rest of the match.
  - Burning wrecks that stay on the map.
- **Living environments**
  - A procedural city generator: old quarter, souq, mosque, apartment blocks, villas, industrial zone.
  - Time of day and weather (haze, dust storm, rain, night with thermal advantage).
  - Smoke, fire, debris and craters.
- **Classic offline AI** at Easy, Medium and Hard. It sees only what its units see; difficulty changes decision quality, never information.
- **Modes**: Skirmish, five Scenarios, Sandbox, AI vs AI spectator, Map Editor with **image-to-map import**, save/load, replays.
- **Optional LLM commanders** (Ollama, LM Studio or any OpenAI-compatible endpoint, Anthropic Claude). They are never required and never enabled automatically. Cloud providers need an explicit paid-service consent.

## Playing
Run `build/ModernConflict.exe` (after building, see below). Everything works offline.

| | |
|---|---|
| Camera | **hold right mouse + drag to pan** · WASD / arrows / screen edge pan · wheel zoom (zooming in lowers the camera to a cinematic angle) · Q/E or middle-drag rotate · F follow |
| Select | Left-click, drag box, Shift add, double-click for all of a type, Ctrl+1–9 groups |
| Orders | Right-click: move / attack / garrison a building / board a transport · Alt+right-click attack-move · Ctrl+right-click area fire · Shift queues |
| Commands | T attack-move · X stop · H hold · G leave building · U unload · C smoke · R retreat · V stance |
| Support | F1–F4 support powers, F5 reinforcements |
| Time | **Space tactical pause** (give orders while paused) · +/- speed |

## Building from source
Requirements: Windows. Godot 4.7.2 and its export templates go in `.tools/` (gitignored):

```bash
mkdir -p .tools/godot && cd .tools/godot
curl -LO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip && unzip *.zip
# export templates: install Godot_v4.7.2-stable_export_templates.tpz (Windows files) into
# %APPDATA%/Godot/export_templates/4.7.2.stable/
```

```bash
tools/gd.sh import        # first run: import resources and build the class cache
tools/gd.sh test          # headless test suite
tools/gd.sh run           # play from source
tools/gd.sh export        # build/ModernConflict.exe (single self-contained executable)
```

Dev shortcuts: `tools/gd.sh run --screen=skirmish --seed=7 --faction=hac --enemy=cdf --tod=night`, `--screen=scenario:iron_sky`, `--screen=aivai`, `--screen=editor`. Screenshots: `tools/gd.sh shot out.png 8 --screen=skirmish`.

Balance batch: `.tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tools/aivai_headless.gd -- --pairs=cdf:pdb,hac:pdb --seeds=3`.

## Project layout
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/CONTRACTS.md](docs/CONTRACTS.md). All art and audio is generated procedurally at runtime, so there are no asset files to license.

## Known limitations
- **Procedural art.** All models are generated from primitives at runtime. The look comes from lighting, atmosphere and detail density, not sculpted assets. Real glTF models can be swapped in behind `UnitModels` / `BuildingBuilder` (see `docs/CONTRACTS.md`).
- **Audio** is fully synthesized and was tuned from waveform analysis (levels, clipping, loop seams). Nobody has listened to it yet, so expect the mix to need adjusting by ear.
- **LLM commander:**
  - Verified end-to-end with a local Ollama model (`qwen3.5:9b`).
  - The OpenAI-compatible and Anthropic paths use the documented request formats but have not been run against a live endpoint here.
  - If an endpoint rejects schema-constrained output, the commander retries with plain JSON instructions.
  - If it fails repeatedly, the classic AI takes over.
- **Balance** was tuned with headless AI-vs-AI batches (all faction matchups near even). Human play will surface different strengths.
- **Multiplayer** is not implemented (listed as future in the vision). The deterministic simulation and command stream are a natural foundation for lockstep networking.

## Notes
All factions, places, units and events are fictional.
