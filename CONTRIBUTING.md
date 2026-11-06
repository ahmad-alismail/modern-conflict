# Contributing to Modern Conflict

Thanks for your interest. Whether you fix a typo, tune a weapon, add a unit or build multiplayer, you are welcome here. This guide gets you productive quickly.

## Ways to help

- **Play and report.** Open an issue with what happened, what you expected, and a screenshot if possible.
- **Balance and tactics.** Tune units, weapons and AI behaviour, backed by AI-vs-AI data (see below).
- **Content.** New units, scenarios, support powers, map styles, prop kinds.
- **Visuals and audio.** Better procedural buildings and vehicles, effects, or a proper sound mix. Audio has only been checked with tools so far, so a pair of ears helps a lot.
- **Systems.** Multiplayer (the simulation is deterministic, so lockstep fits well), a campaign layer, more AI doctrines, accessibility, localization.

## Setup (5 minutes)

```bash
git clone https://github.com/ahmad-alismail/modern-conflict.git
cd modern-conflict
tools/setup.sh          # downloads Godot 4.7.2 into .tools/ (git-ignored)
tools/gd.sh run         # play
tools/gd.sh test        # headless test suite, should end with "0 failures"
tools/gd.sh editor      # optional: open in the Godot editor
```

Windows users run these in **Git Bash**. The engine version is pinned to **Godot 4.7.2**; use the same version to avoid format churn in `.godot`/`.uid` files.

## How the project is organised

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) first (about 5 minutes). The key idea:

```
commands → SimWorld (deterministic 20 Hz simulation, no engine nodes) → events → WorldView / HUD / audio
```

| Folder | What lives there |
|---|---|
| `src/sim/` | Simulation: units, combat, detection, support powers, save/load. **Deterministic.** |
| `src/map/` | Map schema (`MapDef`), procedural city generator, image importer. |
| `src/ai/` | Classic AI (`classic_ai.gd`) and the optional LLM commander (`llm/`). |
| `src/render/` | 3D presentation: terrain, buildings, units, effects, fog of war, camera. |
| `src/ui/`, `src/game/` | HUD, menus, Force Builder, game session, input. |
| `src/editor/` | Map editor and image import dialog. |
| `src/audio/` | Synthesized sound and the audio manager. |
| `tests/` | Headless tests (`test_*.gd`), run by `tests/run_tests.gd`. |
| `tools/` | Dev helpers: `gd.sh`, `setup.sh`, balance tools, preview scenes for art modules. |

Unit and weapon stats are plain data in `src/sim/defs.gd`. Adding a unit is mostly a new entry there, plus a model in `src/render/units/`. Interfaces between modules are documented in [docs/CONTRACTS.md](docs/CONTRACTS.md).

## Rules that keep the game working

1. **Keep the simulation deterministic.** Anything under `src/sim/` (and AI decisions) must:
   - use `world.rng`, never `randf()`, `randi()` or the system time;
   - iterate `world.units` in order and avoid relying on Dictionary hash order of new keys;
   - not depend on rendering, frame rate or engine nodes.

   Replays, save games and tests depend on this; `test_determinism` and `test_replay` will catch violations.
2. **The AI must not cheat.** It reads only its own units, enemies its team currently sees (`vis_mask`), and last-known contacts. Difficulty may change decision quality, never information.
3. **Everything is procedural.** Don't add binary assets without discussing it in an issue first (licensing, repo size).
4. **GDScript type inference gotcha.** `var x := some_dict["k"]` or `:=` on an untyped loop variable fails to parse. Write `var x: float = some_dict["k"]`, or type the loop variable: `for u: SimUnit in units`.

## Workflow

1. Create a branch, make your change, and keep it focused.
2. `tools/gd.sh check`: every script parses.
3. `tools/gd.sh test`: all tests pass. Add a test for new simulation logic (see `tests/test_sim.gd` for small arena tests).
4. **Visual changes:** attach before/after screenshots to the PR, e.g. `tools/gd.sh shot after.png 10 --screen=skirmish --no-briefing --cam-dist=60`. Art modules have preview scenes: `--preview=units`, `--preview=buildings`, `--preview=fx`.
5. **Gameplay or balance changes:** include AI-vs-AI numbers:
   ```bash
   .tools/godot/<godot binary> --headless --path . -s res://tools/aivai_headless.gd -- --pairs=cdf:pdb,pdb:cdf --seeds=3
   .tools/godot/<godot binary> --headless --path . -s res://tools/kill_stats.gd -- --pair=pdb:cdf --seed=117   # who kills what
   ```
   Run both side orders (`cdf:pdb` *and* `pdb:cdf`), because maps can favour one side.
6. Open a pull request describing **what** changed and **why**. CI runs the parse check and the tests automatically.

## Good first issues

Look for the [`good first issue`](https://github.com/ahmad-alismail/modern-conflict/labels/good%20first%20issue) label. Some ideas that are self-contained:

- A "can capture / garrisons / transport" tag line in the unit info panel (`src/ui/hud.gd`).
- New scenario missions (`src/game/scenarios.gd`, pure data).
- More Force Builder presets (`src/game/force_presets.gd`, pure data).
- A visible incoming-missile trail for the Missile Strike support power (`src/render/world_view.gd`).
- Smooth shorelines for water (`src/render/terrain_builder.gd`).
- Translating UI strings / adding localization support.

## Code of conduct

Be kind and constructive. Critique ideas, not people. Assume good intent.

## License

By contributing you agree that your contributions are licensed under the [Apache License 2.0](LICENSE).
