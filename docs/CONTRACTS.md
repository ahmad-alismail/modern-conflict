# Module Contracts (presentation layer)

Godot 4.7.2, GDScript, Forward+ renderer. Everything is procedural (no asset files).
World units are meters. A map point `Vector2(x, y)` maps to world `Vector3(x, 0, y)`.
A sim heading `facing` (radians, 0 = +X, increasing toward +Z) maps to a Node3D yaw of
`rotation.y = -facing`, with models built **facing +X** in their local space.

Shared helper: `src/render/mesh_kit.gd` (`MeshKit`). It accumulates boxes, cylinders,
spheres and quads per material and commits them as one ArrayMesh with one surface per
material. Use vertex colors for per-part tint (`MeshKit.mat()` sets `vertex_color_use_as_albedo`).
Keep draw calls low: aim for 1–4 surfaces per building or vehicle.

API reference: `.tools/docs/doc/classes/<Class>.xml` (dumped from the engine). Check any
API you are not sure exists in 4.7 there.

Dev loop:
- `tools/gd.sh import`: refreshes the class_name cache after adding scripts.
- `tools/gd.sh check`: parse-checks every script.
- `tools/gd.sh test`: headless tests.
- `tools/gd.sh shot <name>.png <delay> --preview=<id>`: windowed screenshot written to
  `shots/<name>.png`. View it with your image reader.

`src/main.gd` routes `--preview=<id>` to `res://tools/preview_<id>.gd` (a Node3D script you
write that builds a showcase scene, including its own camera and light, or uses
`PreviewKit.setup(self)` for a standard environment).

---

## 1. Buildings, walls, props: `BuildingBuilder`, `PropBuilder`
Files: `src/render/building_builder.gd`, `src/render/prop_builder.gd`, plus optional helpers
under `src/render/env/`.

```gdscript
class_name BuildingBuilder
static func build(b: Dictionary) -> Node3D        # intact building
static func build_ruin(b: Dictionary) -> Node3D   # collapsed: rubble pile + broken remnants
static func apply_damage(node: Node3D, level: int) -> void   # 1 = damaged (scorch, holes, broken details)
```
- `b` is a MapDef building dict:
  `{id, c: Vector2 center, size: Vector2 (x along X, y along Z), rot: float, floors: int, style: int, color: int 0-7, seed: int}`.
- The returned node's origin is the ground center of the footprint. The **caller** positions
  it and sets `rotation.y = -b.rot`.
- The footprint must match `size` exactly. The main mass top must be about
  `MapDef.building_height(b)` (floors × 3.2 m + 1 m parapet; industrial uses 4.5 m per floor),
  because LOS uses that height.
- Styles are `MapDef.S_*`: OLD, APARTMENT, SHOP, VILLA, MOSQUE, INDUSTRIAL, UNFINISHED, TOWER.
  Use `b.seed` for deterministic variety.

```gdscript
class_name PropBuilder
static func build_props(props: Array) -> Node3D   # one MultiMeshInstance3D per prop kind
static func build_walls(walls: Array) -> Node3D   # merged wall geometry
```
- Each prop is `{kind: String, p: Vector2, rot: float, s: float}`. The kinds and footprint
  dims are listed in `MapDef.PROPS`.
- Each wall is `{a: Vector2, b: Vector2, h: float, kind: MapDef.W_*}`.

## 2. Units: `UnitModels` + `UnitModel`
Files: `src/render/unit_models.gd`, `src/render/unit_model.gd`, optional helpers in `src/render/units/`.

```gdscript
class_name UnitModels
static func create(def_id: String, team_color: Color) -> UnitModel
static func create_wreck(def_id: String) -> Node3D    # burned-out hulk, same footprint

class_name UnitModel extends Node3D
var members: Array[Node3D]                 # squads: one node per soldier/robot (local to the model root)
func set_turret_yaw(local_yaw: float) -> void       # turret relative to hull (radians, sim convention)
func set_motion(speed: float, delta: float) -> void # wheels/tracks/rotors/legs animation
func set_member_state(i: int, state: int, delta: float) -> void   # 0 idle, 1 moving, 2 firing, 3 pinned/prone, 4 dead
func muzzle_world(slot: int) -> Vector3             # vehicle weapon slot muzzle (global)
func fire_recoil(slot: int) -> void
func set_deployed(on: bool) -> void                 # sensor mast extended (hac_mast); others ignore
func top_height() -> float                          # for health-bar placement
```
- `def_id` keys come from `Defs.UNITS`. The visual must reflect the unit's loadout and role.
- Squad member positions are set by the caller each frame from `SimUnit.member_offset(i)`
  (local XZ). The model only animates poses.
- Faction looks:
  - CDF: desert tan and olive camo, modern western-style kit.
  - PDB: mixed civilian clothes and olive, scarves, white or rust pickups.
  - HAC: dark graphite with small cyan emissive accents, robots and drones.
- `team_color` is a small identification accent (armband or stripe), not the whole paint job.

## 3. Effects: `Effects` (Node3D, one instance in the world)
File: `src/render/fx/effects.gd` (+ helpers in `src/render/fx/`).

```gdscript
func muzzle_flash(pos: Vector3, dir: Vector3, size: float) -> void
func tracer(from: Vector3, to: Vector3, color: Color) -> void
func impact(pos: Vector3, kind: String) -> void          # "dirt" | "concrete" | "metal" | "spark"
func explosion(pos: Vector3, size: float) -> void         # 0.5 grenade ... 1 shell ... 3 bomb (+ crater decal)
func smoke_cloud(pos: Vector3, radius: float, duration: float) -> void
func fire(pos: Vector3, duration: float, size: float) -> void   # burning wreck: fire + rising smoke column
func dust_burst(pos: Vector3, size: float) -> void
func collapse(center: Vector3, size: Vector3) -> void     # building collapse: dust cloud + debris
func projectile(kind: int) -> Node3D                       # Defs.P_* visual (rocket/missile with trail, shell, mortar)
func set_paused(p: bool) -> void
```
Effects must look good both close up (cinematic camera at about 15 m) and from about 200 m.
They must be pooled or capped so heavy firefights stay fast.

## 4. Audio: `AudioManager` (Node, one instance per game session)
File: `src/audio/audio_manager.gd` (+ `src/audio/synth.gd`).

```gdscript
func play(sound: String, pos: Vector3, volume_db: float = 0.0) -> void   # positional
func play_ui(sound: String) -> void
func set_listener_height(h: float) -> void   # camera zoom: far = quieter details
func set_ambience(weather: String, intensity: float) -> void   # intensity 0..1 = battle level
```
All sounds are synthesized at startup (`AudioStreamWAV` from generated PCM). Use buses
Master, SFX, Ambience, UI with volumes from the `Settings` autoload (`audio.*`).
