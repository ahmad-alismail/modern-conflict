extends RefCounted
## Static, data-driven game definitions: weapons, units, factions, support powers.
## All names are fictional. Units differ by capability (armor, sensors, weapons,
## mobility, morale model), which is what makes factions play differently.
class_name Defs

# --- unit categories / movement classes ---------------------------------------
const CAT_INF := 0
const CAT_VEH := 1
const CAT_AIR := 2

const MOVE_FOOT := 0
const MOVE_WHEELED := 1
const MOVE_TRACKED := 2
const MOVE_AIR := 3

# --- weapon target masks ------------------------------------------------------
const T_INF := 1
const T_VEH := 2
const T_AIR := 4
const T_GROUND := T_INF | T_VEH

# --- projectile kinds (visual + resolution) -----------------------------------
const P_BULLET := 0     # hitscan, tracer visual
const P_SHELL := 1      # fast ballistic, direct fire
const P_ROCKET := 2     # unguided, dispersion, smoke trail
const P_MISSILE := 3    # guided, smoke trail
const P_MORTAR := 4     # indirect, high arc
const P_BOMB := 5       # dropped munition
const P_KAMIKAZE := 6   # the unit itself is the munition

## Weapon fields:
##  range, min_range (m) | damage (per hit), pen (armor penetration, mm-equivalent)
##  acc_near / acc_far (hit probability at 0 m / max range, vs standing infantry)
##  burst (shots per trigger pull), burst_dt (s between shots), cooldown (s between bursts)
##  ammo (bursts carried), splash (m radius, 0 = none), suppress (suppression per burst)
##  proj (kind), speed (m/s for projectiles), targets (mask), setup (s stationary before firing)
##  top_attack (hits top armor), indirect (needs no LOS from shooter, needs team visibility)
##  air_acc (multiplier vs air targets)
const WEAPONS := {
	"rifle": {"name": "Assault Rifle", "range": 70.0, "damage": 24.0, "pen": 3.0, "acc_near": 0.55, "acc_far": 0.16,
		"burst": 3, "burst_dt": 0.11, "cooldown": 1.5, "ammo": 70, "suppress": 4.0, "proj": P_BULLET, "targets": T_INF | T_VEH | T_AIR, "air_acc": 0.25},
	"ak": {"name": "Battle Rifle", "range": 65.0, "damage": 26.0, "pen": 3.0, "acc_near": 0.45, "acc_far": 0.12,
		"burst": 3, "burst_dt": 0.12, "cooldown": 1.6, "ammo": 60, "suppress": 4.5, "proj": P_BULLET, "targets": T_INF | T_VEH | T_AIR, "air_acc": 0.2},
	"smart_rifle": {"name": "Smart Rifle", "range": 80.0, "damage": 24.0, "pen": 4.0, "acc_near": 0.7, "acc_far": 0.28,
		"burst": 2, "burst_dt": 0.12, "cooldown": 1.4, "ammo": 70, "suppress": 4.0, "proj": P_BULLET, "targets": T_INF | T_VEH | T_AIR, "air_acc": 0.45},
	"lmg": {"name": "Machine Gun", "range": 85.0, "damage": 22.0, "pen": 4.0, "acc_near": 0.4, "acc_far": 0.11,
		"burst": 8, "burst_dt": 0.08, "cooldown": 1.9, "ammo": 45, "suppress": 11.0, "proj": P_BULLET, "targets": T_INF | T_VEH | T_AIR, "air_acc": 0.3},
	"gpmg": {"name": "GPMG", "range": 95.0, "damage": 24.0, "pen": 5.0, "acc_near": 0.42, "acc_far": 0.13,
		"burst": 10, "burst_dt": 0.07, "cooldown": 1.8, "ammo": 50, "suppress": 14.0, "proj": P_BULLET, "targets": T_INF | T_VEH | T_AIR, "setup": 1.5, "air_acc": 0.3},
	"coax": {"name": "Coaxial MG", "range": 90.0, "damage": 22.0, "pen": 5.0, "acc_near": 0.45, "acc_far": 0.14,
		"burst": 10, "burst_dt": 0.07, "cooldown": 1.6, "ammo": 80, "suppress": 12.0, "proj": P_BULLET, "targets": T_INF},
	"hmg": {"name": "Heavy MG", "range": 115.0, "damage": 34.0, "pen": 20.0, "acc_near": 0.42, "acc_far": 0.12,
		"burst": 6, "burst_dt": 0.1, "cooldown": 1.5, "ammo": 45, "suppress": 16.0, "proj": P_BULLET, "targets": T_INF | T_VEH | T_AIR, "air_acc": 0.55},
	"hmg_team": {"name": "Heavy MG", "range": 120.0, "damage": 34.0, "pen": 20.0, "acc_near": 0.45, "acc_far": 0.14,
		"burst": 7, "burst_dt": 0.1, "cooldown": 1.5, "ammo": 45, "suppress": 18.0, "proj": P_BULLET, "targets": T_INF | T_VEH | T_AIR, "setup": 2.5, "air_acc": 0.55},
	"robot_mg": {"name": "Integrated MG", "range": 75.0, "damage": 20.0, "pen": 4.0, "acc_near": 0.6, "acc_far": 0.22,
		"burst": 5, "burst_dt": 0.08, "cooldown": 1.6, "ammo": 60, "suppress": 8.0, "proj": P_BULLET, "targets": T_INF | T_VEH | T_AIR, "air_acc": 0.35},
	"sniper": {"name": "Sniper Rifle", "range": 145.0, "damage": 110.0, "pen": 10.0, "acc_near": 0.92, "acc_far": 0.6,
		"burst": 1, "burst_dt": 0.0, "cooldown": 4.5, "ammo": 30, "suppress": 22.0, "proj": P_BULLET, "targets": T_INF, "setup": 1.0},
	"dmr": {"name": "Marksman Rifle", "range": 115.0, "damage": 65.0, "pen": 6.0, "acc_near": 0.78, "acc_far": 0.4,
		"burst": 1, "burst_dt": 0.0, "cooldown": 2.6, "ammo": 35, "suppress": 14.0, "proj": P_BULLET, "targets": T_INF},
	"grenade": {"name": "Hand Grenades", "range": 28.0, "min_range": 6.0, "damage": 70.0, "pen": 6.0, "acc_near": 0.7, "acc_far": 0.45,
		"burst": 1, "burst_dt": 0.0, "cooldown": 9.0, "ammo": 4, "splash": 5.0, "suppress": 25.0, "proj": P_MORTAR, "speed": 18.0, "targets": T_INF},
	"law": {"name": "Light AT Rocket", "range": 55.0, "min_range": 8.0, "damage": 260.0, "pen": 290.0, "acc_near": 0.6, "acc_far": 0.3,
		"burst": 1, "burst_dt": 0.0, "cooldown": 14.0, "ammo": 2, "splash": 3.0, "suppress": 15.0, "proj": P_ROCKET, "speed": 140.0, "targets": T_VEH},
	"rpg": {"name": "RPG", "range": 65.0, "min_range": 8.0, "damage": 300.0, "pen": 320.0, "acc_near": 0.55, "acc_far": 0.22,
		"burst": 1, "burst_dt": 0.0, "cooldown": 7.0, "ammo": 6, "splash": 3.5, "suppress": 18.0, "proj": P_ROCKET, "speed": 115.0, "targets": T_VEH | T_INF | T_AIR, "air_acc": 0.15},
	"atgm": {"name": "ATGM", "range": 170.0, "min_range": 25.0, "damage": 460.0, "pen": 620.0, "acc_near": 0.88, "acc_far": 0.8,
		"burst": 1, "burst_dt": 0.0, "cooldown": 11.0, "ammo": 4, "splash": 3.0, "suppress": 20.0, "proj": P_MISSILE, "speed": 85.0, "targets": T_VEH, "setup": 2.5, "guided": true},
	"recoilless": {"name": "Recoilless Rifle", "range": 105.0, "min_range": 10.0, "damage": 330.0, "pen": 360.0, "acc_near": 0.62, "acc_far": 0.3,
		"burst": 1, "burst_dt": 0.0, "cooldown": 6.0, "ammo": 10, "splash": 4.0, "suppress": 20.0, "proj": P_SHELL, "speed": 300.0, "targets": T_VEH | T_INF},
	"cannon120": {"name": "120mm Gun", "range": 165.0, "min_range": 0.0, "damage": 540.0, "pen": 680.0, "acc_near": 0.88, "acc_far": 0.55,
		"burst": 1, "burst_dt": 0.0, "cooldown": 6.5, "ammo": 32, "splash": 4.5, "suppress": 30.0, "proj": P_SHELL, "speed": 700.0, "targets": T_VEH | T_INF},
	"cannon100": {"name": "100mm Gun", "range": 140.0, "min_range": 0.0, "damage": 430.0, "pen": 390.0, "acc_near": 0.72, "acc_far": 0.35,
		"burst": 1, "burst_dt": 0.0, "cooldown": 8.5, "ammo": 26, "splash": 4.5, "suppress": 28.0, "proj": P_SHELL, "speed": 550.0, "targets": T_VEH | T_INF},
	"autocannon30": {"name": "30mm Autocannon", "range": 135.0, "damage": 62.0, "pen": 65.0, "acc_near": 0.55, "acc_far": 0.24,
		"burst": 3, "burst_dt": 0.18, "cooldown": 1.3, "ammo": 55, "splash": 1.8, "suppress": 18.0, "proj": P_BULLET, "targets": T_INF | T_VEH | T_AIR, "air_acc": 0.6},
	"autocannon25": {"name": "25mm Autocannon", "range": 125.0, "damage": 52.0, "pen": 50.0, "acc_near": 0.62, "acc_far": 0.28,
		"burst": 3, "burst_dt": 0.18, "cooldown": 1.3, "ammo": 55, "splash": 1.5, "suppress": 15.0, "proj": P_BULLET, "targets": T_INF | T_VEH | T_AIR, "air_acc": 0.7},
	"ifv_atgm": {"name": "Turret ATGM", "range": 180.0, "min_range": 25.0, "damage": 460.0, "pen": 620.0, "acc_near": 0.88, "acc_far": 0.8,
		"burst": 1, "burst_dt": 0.0, "cooldown": 14.0, "ammo": 3, "splash": 3.0, "suppress": 20.0, "proj": P_MISSILE, "speed": 90.0, "targets": T_VEH, "guided": true},
	"heli_cannon": {"name": "30mm Chain Gun", "range": 150.0, "damage": 60.0, "pen": 60.0, "acc_near": 0.5, "acc_far": 0.22,
		"burst": 6, "burst_dt": 0.1, "cooldown": 1.8, "ammo": 40, "splash": 2.0, "suppress": 20.0, "proj": P_BULLET, "targets": T_INF | T_VEH | T_AIR, "top_attack": true, "air_acc": 0.5},
	"heli_rockets": {"name": "Rocket Pods", "range": 150.0, "min_range": 30.0, "damage": 130.0, "pen": 60.0, "acc_near": 0.4, "acc_far": 0.2,
		"burst": 4, "burst_dt": 0.15, "cooldown": 9.0, "ammo": 6, "splash": 6.0, "suppress": 30.0, "proj": P_ROCKET, "speed": 160.0, "targets": T_INF | T_VEH, "top_attack": true},
	"heli_atgm": {"name": "Air ATGM", "range": 210.0, "min_range": 40.0, "damage": 500.0, "pen": 700.0, "acc_near": 0.9, "acc_far": 0.82,
		"burst": 1, "burst_dt": 0.0, "cooldown": 9.0, "ammo": 6, "splash": 3.0, "suppress": 20.0, "proj": P_MISSILE, "speed": 110.0, "targets": T_VEH, "top_attack": true, "guided": true},
	"mortar": {"name": "Mortar", "range": 260.0, "min_range": 45.0, "damage": 160.0, "pen": 25.0, "acc_near": 0.6, "acc_far": 0.35,
		"burst": 1, "burst_dt": 0.0, "cooldown": 5.5, "ammo": 18, "splash": 9.0, "suppress": 35.0, "proj": P_MORTAR, "speed": 70.0, "targets": T_INF | T_VEH, "setup": 3.0, "indirect": true, "scatter": 10.0},
	"mrl": {"name": "107mm Rockets", "range": 320.0, "min_range": 70.0, "damage": 150.0, "pen": 30.0, "acc_near": 0.4, "acc_far": 0.25,
		"burst": 6, "burst_dt": 0.35, "cooldown": 26.0, "ammo": 4, "splash": 8.0, "suppress": 40.0, "proj": P_MORTAR, "speed": 95.0, "targets": T_INF | T_VEH, "setup": 2.0, "indirect": true, "scatter": 20.0},
	"manpads": {"name": "MANPADS", "range": 190.0, "min_range": 30.0, "damage": 420.0, "pen": 100.0, "acc_near": 0.8, "acc_far": 0.65,
		"burst": 1, "burst_dt": 0.0, "cooldown": 12.0, "ammo": 3, "splash": 2.0, "suppress": 0.0, "proj": P_MISSILE, "speed": 160.0, "targets": T_AIR, "guided": true, "air_acc": 1.0},
	"ugv_missile": {"name": "Top-Attack Missile", "range": 185.0, "min_range": 30.0, "damage": 470.0, "pen": 650.0, "acc_near": 0.9, "acc_far": 0.84,
		"burst": 1, "burst_dt": 0.0, "cooldown": 10.0, "ammo": 6, "splash": 3.0, "suppress": 20.0, "proj": P_MISSILE, "speed": 95.0, "targets": T_VEH, "top_attack": true, "guided": true},
	"drone_grenade": {"name": "Drop Grenade", "range": 30.0, "damage": 130.0, "pen": 45.0, "acc_near": 0.75, "acc_far": 0.55,
		"burst": 1, "burst_dt": 0.0, "cooldown": 6.0, "ammo": 6, "splash": 4.5, "suppress": 30.0, "proj": P_BOMB, "speed": 20.0, "targets": T_INF | T_VEH, "top_attack": true},
	"ucav_missile": {"name": "Precision Missile", "range": 230.0, "min_range": 40.0, "damage": 480.0, "pen": 650.0, "acc_near": 0.9, "acc_far": 0.85,
		"burst": 1, "burst_dt": 0.0, "cooldown": 10.0, "ammo": 4, "splash": 5.0, "suppress": 30.0, "proj": P_MISSILE, "speed": 130.0, "targets": T_VEH | T_INF, "top_attack": true, "guided": true},
	"fpv_charge": {"name": "Shaped Charge", "range": 6.0, "damage": 380.0, "pen": 260.0, "acc_near": 0.85, "acc_far": 0.85,
		"burst": 1, "burst_dt": 0.0, "cooldown": 1.0, "ammo": 1, "splash": 4.0, "suppress": 30.0, "proj": P_KAMIKAZE, "targets": T_VEH | T_INF, "top_attack": true},
}

## Unit fields:
##  name, cat, move, speed (m/s), turn (rad/s), hp (per member for squads), members
##  loadout: weapon per member (squads) or list of mounted weapons (vehicles)
##  armor: [front, side, rear, top]; sight (m); camo (detection multiplier, lower = stealthier)
##  thermal (sees at night / through light smoke); morale ("human" | "robot"); base_morale
##  radius (m); eye (eye height m); alt (flight altitude); capture (can capture objectives)
##  garrison (can enter buildings); transport (passenger slots); smoke (charges)
##  turret (turret turn rate rad/s, 0 = none); points (strength value for AI / setups)
##  model (renderer key); role (UI text); special: Array of tags
const UNITS := {
	# ---------------- Coalition Defense Force (conventional) ----------------
	"cdf_rifle": {"name": "Rifle Squad", "faction": "cdf", "cat": CAT_INF, "move": MOVE_FOOT, "speed": 3.4, "turn": 6.0,
		"hp": 100.0, "members": 6, "loadout": ["rifle", "rifle", "lmg", "rifle", "law", "grenade"], "armor": [0, 0, 0, 0],
		"sight": 70.0, "camo": 0.8, "thermal": false, "morale": "human", "base_morale": 90.0, "radius": 3.5, "eye": 1.6,
		"capture": true, "garrison": true, "smoke": 1, "points": 10, "role": "Line infantry. Captures, garrisons, carries light AT."},
	"cdf_mg": {"name": "MG Team", "faction": "cdf", "cat": CAT_INF, "move": MOVE_FOOT, "speed": 3.2, "turn": 6.0,
		"hp": 100.0, "members": 3, "loadout": ["gpmg", "rifle", "rifle"], "armor": [0, 0, 0, 0],
		"sight": 70.0, "camo": 0.8, "morale": "human", "base_morale": 90.0, "radius": 2.5, "eye": 1.6,
		"capture": true, "garrison": true, "points": 9, "role": "Suppression. Pins infantry; must set up to fire."},
	"cdf_atgm": {"name": "ATGM Team", "faction": "cdf", "cat": CAT_INF, "move": MOVE_FOOT, "speed": 3.0, "turn": 6.0,
		"hp": 100.0, "members": 3, "loadout": ["atgm", "rifle", "rifle"], "armor": [0, 0, 0, 0],
		"sight": 75.0, "camo": 0.75, "morale": "human", "base_morale": 90.0, "radius": 2.5, "eye": 1.6,
		"capture": true, "garrison": true, "points": 12, "role": "Long-range anti-armor. Weak vs infantry."},
	"cdf_sniper": {"name": "Sniper Team", "faction": "cdf", "cat": CAT_INF, "move": MOVE_FOOT, "speed": 3.2, "turn": 6.0,
		"hp": 100.0, "members": 2, "loadout": ["sniper", "rifle"], "armor": [0, 0, 0, 0],
		"sight": 115.0, "camo": 0.4, "thermal": true, "morale": "human", "base_morale": 95.0, "radius": 2.0, "eye": 1.6,
		"capture": false, "garrison": true, "points": 10, "role": "Recon and precision fire. Hard to detect."},
	"cdf_mortar": {"name": "Mortar Section", "faction": "cdf", "cat": CAT_INF, "move": MOVE_FOOT, "speed": 2.9, "turn": 6.0,
		"hp": 100.0, "members": 3, "loadout": ["mortar", "rifle", "rifle"], "armor": [0, 0, 0, 0],
		"sight": 65.0, "camo": 0.8, "morale": "human", "base_morale": 85.0, "radius": 2.5, "eye": 1.6,
		"capture": false, "garrison": false, "points": 11, "role": "Indirect fire on spotted enemies."},
	"cdf_mbt": {"name": "Sentinel MBT", "faction": "cdf", "cat": CAT_VEH, "move": MOVE_TRACKED, "speed": 8.5, "turn": 1.3,
		"hp": 1000.0, "members": 1, "loadout": ["cannon120", "coax"], "armor": [720, 160, 60, 35],
		"sight": 62.0, "camo": 1.25, "thermal": true, "morale": "human", "base_morale": 100.0, "radius": 4.2, "eye": 2.6,
		"turret": 1.4, "smoke": 2, "points": 40, "role": "Main battle tank. Heavy frontal armor; vulnerable sides, rear, top."},
	"cdf_ifv": {"name": "Warden IFV", "faction": "cdf", "cat": CAT_VEH, "move": MOVE_TRACKED, "speed": 10.0, "turn": 1.6,
		"hp": 620.0, "members": 1, "loadout": ["autocannon30", "ifv_atgm", "coax"], "armor": [130, 45, 25, 15],
		"sight": 62.0, "camo": 1.1, "thermal": true, "morale": "human", "base_morale": 100.0, "radius": 3.6, "eye": 2.5,
		"turret": 1.8, "transport": 6, "smoke": 2, "points": 28, "role": "Infantry fighting vehicle. Autocannon, ATGM, carries a squad."},
	"cdf_mrap": {"name": "Bulwark MRAP", "faction": "cdf", "cat": CAT_VEH, "move": MOVE_WHEELED, "speed": 13.0, "turn": 1.5,
		"hp": 400.0, "members": 1, "loadout": ["hmg"], "armor": [30, 25, 20, 10],
		"sight": 60.0, "camo": 1.0, "thermal": true, "morale": "human", "base_morale": 100.0, "radius": 3.0, "eye": 2.4,
		"turret": 2.5, "transport": 6, "smoke": 1, "points": 16, "role": "Fast protected transport with heavy MG."},
	"cdf_heli": {"name": "Kestrel Attack Helicopter", "faction": "cdf", "cat": CAT_AIR, "move": MOVE_AIR, "speed": 24.0, "turn": 1.4,
		"hp": 480.0, "members": 1, "loadout": ["heli_cannon", "heli_rockets", "heli_atgm"], "armor": [25, 25, 20, 15],
		"sight": 130.0, "camo": 1.6, "thermal": true, "morale": "human", "base_morale": 100.0, "radius": 6.0, "eye": 35.0, "alt": 35.0,
		"turret": 3.0, "points": 45, "air_kind": "heli", "role": "Air support. Devastating, but vulnerable to MANPADS and heavy guns."},
	"cdf_supply": {"name": "Supply Truck", "faction": "cdf", "cat": CAT_VEH, "move": MOVE_WHEELED, "speed": 11.0, "turn": 1.4,
		"hp": 260.0, "members": 1, "loadout": [], "armor": [8, 6, 6, 4],
		"sight": 50.0, "camo": 1.0, "morale": "human", "base_morale": 80.0, "radius": 3.0, "eye": 2.4,
		"points": 8, "special": ["resupply", "repair"], "role": "Rearms nearby units and repairs vehicles."},

	# ---------------- People's Defense Brigades (light forces) ----------------
	"pdb_militia": {"name": "Militia Squad", "faction": "pdb", "cat": CAT_INF, "move": MOVE_FOOT, "speed": 3.5, "turn": 6.0,
		"hp": 100.0, "members": 8, "loadout": ["ak", "ak", "lmg", "ak", "ak", "ak", "grenade", "ak"], "armor": [0, 0, 0, 0],
		"sight": 68.0, "camo": 0.7, "morale": "human", "base_morale": 80.0, "radius": 4.0, "eye": 1.6,
		"capture": true, "garrison": true, "points": 8, "special": ["urban_bonus"], "role": "Numerous irregulars. Fight best from buildings."},
	"pdb_rpg": {"name": "RPG Team", "faction": "pdb", "cat": CAT_INF, "move": MOVE_FOOT, "speed": 3.5, "turn": 6.0,
		"hp": 95.0, "members": 3, "loadout": ["rpg", "rpg", "ak"], "armor": [0, 0, 0, 0],
		"sight": 65.0, "camo": 0.65, "morale": "human", "base_morale": 75.0, "radius": 2.5, "eye": 1.6,
		"capture": true, "garrison": true, "points": 10, "special": ["urban_bonus"], "role": "Short-range ambush anti-armor."},
	"pdb_hmg": {"name": "HMG Team", "faction": "pdb", "cat": CAT_INF, "move": MOVE_FOOT, "speed": 2.9, "turn": 6.0,
		"hp": 95.0, "members": 3, "loadout": ["hmg_team", "ak", "ak"], "armor": [0, 0, 0, 0],
		"sight": 68.0, "camo": 0.75, "morale": "human", "base_morale": 75.0, "radius": 2.5, "eye": 1.6,
		"capture": true, "garrison": true, "points": 10, "special": ["urban_bonus"], "role": "Heavy MG. Shreds infantry, light vehicles and drones."},
	"pdb_marksman": {"name": "Marksman", "faction": "pdb", "cat": CAT_INF, "move": MOVE_FOOT, "speed": 3.3, "turn": 6.0,
		"hp": 95.0, "members": 2, "loadout": ["dmr", "ak"], "armor": [0, 0, 0, 0],
		"sight": 100.0, "camo": 0.45, "morale": "human", "base_morale": 80.0, "radius": 2.0, "eye": 1.6,
		"capture": false, "garrison": true, "points": 8, "special": ["urban_bonus"], "role": "Concealed precision fire."},
	"pdb_mortar": {"name": "Mortar Team", "faction": "pdb", "cat": CAT_INF, "move": MOVE_FOOT, "speed": 2.9, "turn": 6.0,
		"hp": 95.0, "members": 3, "loadout": ["mortar", "ak", "ak"], "armor": [0, 0, 0, 0],
		"sight": 62.0, "camo": 0.75, "morale": "human", "base_morale": 72.0, "radius": 2.5, "eye": 1.6,
		"capture": false, "garrison": false, "points": 10, "role": "Indirect fire on spotted enemies."},
	"pdb_manpads": {"name": "MANPADS Team", "faction": "pdb", "cat": CAT_INF, "move": MOVE_FOOT, "speed": 3.3, "turn": 6.0,
		"hp": 95.0, "members": 2, "loadout": ["manpads", "ak"], "armor": [0, 0, 0, 0],
		"sight": 90.0, "camo": 0.7, "morale": "human", "base_morale": 75.0, "radius": 2.0, "eye": 1.6,
		"capture": false, "garrison": true, "points": 10, "role": "Shoulder-fired anti-air."},
	"pdb_technical": {"name": "Technical", "faction": "pdb", "cat": CAT_VEH, "move": MOVE_WHEELED, "speed": 15.0, "turn": 1.9,
		"hp": 190.0, "members": 1, "loadout": ["hmg"], "armor": [6, 5, 5, 3],
		"sight": 58.0, "camo": 0.95, "morale": "human", "base_morale": 75.0, "radius": 2.6, "eye": 2.2,
		"turret": 3.0, "transport": 4, "points": 10, "role": "Fast pickup with heavy MG. Fragile."},
	"pdb_spg": {"name": "Recoilless Technical", "faction": "pdb", "cat": CAT_VEH, "move": MOVE_WHEELED, "speed": 14.0, "turn": 1.9,
		"hp": 190.0, "members": 1, "loadout": ["recoilless"], "armor": [6, 5, 5, 3],
		"sight": 58.0, "camo": 0.95, "morale": "human", "base_morale": 75.0, "radius": 2.6, "eye": 2.2,
		"turret": 1.8, "points": 14, "role": "Mobile anti-armor gun on a pickup."},
	"pdb_mrl": {"name": "Rocket Technical", "faction": "pdb", "cat": CAT_VEH, "move": MOVE_WHEELED, "speed": 13.0, "turn": 1.8,
		"hp": 200.0, "members": 1, "loadout": ["mrl"], "armor": [6, 5, 5, 3],
		"sight": 55.0, "camo": 0.95, "morale": "human", "base_morale": 75.0, "radius": 2.8, "eye": 2.2,
		"turret": 1.2, "points": 16, "role": "Area rocket barrages on spotted targets."},
	"pdb_tank": {"name": "Relic Tank", "faction": "pdb", "cat": CAT_VEH, "move": MOVE_TRACKED, "speed": 7.5, "turn": 1.2,
		"hp": 820.0, "members": 1, "loadout": ["cannon100", "coax"], "armor": [400, 95, 45, 25],
		"sight": 55.0, "camo": 1.25, "thermal": false, "morale": "human", "base_morale": 85.0, "radius": 4.0, "eye": 2.5,
		"turret": 1.0, "smoke": 1, "points": 30, "role": "Old main battle tank. Still deadly against light forces."},

	# ---------------- Helix Autonomous Command (advanced autonomous) ----------------
	"hac_operator": {"name": "Operator Team", "faction": "hac", "cat": CAT_INF, "move": MOVE_FOOT, "speed": 3.4, "turn": 6.0,
		"hp": 100.0, "members": 4, "loadout": ["smart_rifle", "smart_rifle", "smart_rifle", "smart_rifle"], "armor": [0, 0, 0, 0],
		"sight": 80.0, "camo": 0.75, "thermal": true, "morale": "human", "base_morale": 90.0, "radius": 3.0, "eye": 1.6,
		"capture": true, "garrison": true, "points": 12, "special": ["network_node"], "role": "Human operators. Network node for nearby robots."},
	"hac_hound": {"name": "Hound Robot Pack", "faction": "hac", "cat": CAT_INF, "move": MOVE_FOOT, "speed": 4.6, "turn": 7.0,
		"hp": 150.0, "members": 4, "loadout": ["robot_mg", "robot_mg", "robot_mg", "robot_mg"], "armor": [12, 12, 12, 8],
		"sight": 78.0, "camo": 0.85, "thermal": true, "morale": "robot", "base_morale": 100.0, "radius": 3.2, "eye": 1.0,
		"capture": true, "garrison": false, "points": 14, "special": ["networked"], "role": "Armored quadruped robots. Shrug off rifle fire; no fear."},
	"hac_ugv_gun": {"name": "Mule Gun UGV", "faction": "hac", "cat": CAT_VEH, "move": MOVE_TRACKED, "speed": 7.5, "turn": 2.0,
		"hp": 420.0, "members": 1, "loadout": ["autocannon25"], "armor": [60, 35, 22, 12],
		"sight": 65.0, "camo": 0.85, "thermal": true, "morale": "robot", "base_morale": 100.0, "radius": 2.4, "eye": 1.6,
		"turret": 2.5, "points": 18, "special": ["networked"], "role": "Unmanned gun platform. Anti-infantry and anti-drone."},
	"hac_ugv_atgm": {"name": "Lancer Missile UGV", "faction": "hac", "cat": CAT_VEH, "move": MOVE_TRACKED, "speed": 7.0, "turn": 2.0,
		"hp": 340.0, "members": 1, "loadout": ["ugv_missile"], "armor": [55, 30, 20, 12],
		"sight": 65.0, "camo": 0.85, "thermal": true, "morale": "robot", "base_morale": 100.0, "radius": 2.4, "eye": 1.6,
		"turret": 2.0, "points": 22, "special": ["networked"], "role": "Top-attack missiles. Kills tanks from any angle."},
	"hac_recon": {"name": "Recon Quadcopter", "faction": "hac", "cat": CAT_AIR, "move": MOVE_AIR, "speed": 18.0, "turn": 4.0,
		"hp": 60.0, "members": 1, "loadout": [], "armor": [0, 0, 0, 0],
		"sight": 150.0, "camo": 0.45, "thermal": true, "morale": "robot", "base_morale": 100.0, "radius": 1.2, "eye": 55.0, "alt": 55.0,
		"points": 8, "air_kind": "drone", "special": ["drone"], "role": "Eye in the sky. Unarmed, hard to spot."},
	"hac_fpv": {"name": "FPV Strike Drone", "faction": "hac", "cat": CAT_AIR, "move": MOVE_AIR, "speed": 26.0, "turn": 5.0,
		"hp": 30.0, "members": 1, "loadout": ["fpv_charge"], "armor": [0, 0, 0, 0],
		"sight": 70.0, "camo": 0.5, "thermal": true, "morale": "robot", "base_morale": 100.0, "radius": 1.0, "eye": 20.0, "alt": 20.0,
		"points": 7, "air_kind": "drone", "special": ["drone", "kamikaze"], "role": "One-way attack drone. Dives onto its target."},
	"hac_wasp": {"name": "Wasp Hover Drone", "faction": "hac", "cat": CAT_AIR, "move": MOVE_AIR, "speed": 15.0, "turn": 3.5,
		"hp": 110.0, "members": 1, "loadout": ["drone_grenade"], "armor": [3, 3, 3, 3],
		"sight": 90.0, "camo": 0.55, "thermal": true, "morale": "robot", "base_morale": 100.0, "radius": 1.4, "eye": 25.0, "alt": 25.0,
		"points": 10, "air_kind": "drone", "special": ["drone"], "role": "Drops grenades on infantry and light vehicles."},
	"hac_ucav": {"name": "Raptor UCAV", "faction": "hac", "cat": CAT_AIR, "move": MOVE_AIR, "speed": 30.0, "turn": 0.9,
		"hp": 280.0, "members": 1, "loadout": ["ucav_missile"], "armor": [8, 8, 8, 8],
		"sight": 140.0, "camo": 0.9, "thermal": true, "morale": "robot", "base_morale": 100.0, "radius": 5.0, "eye": 90.0, "alt": 90.0,
		"points": 32, "air_kind": "plane", "special": ["drone", "loiter"], "role": "Loitering strike drone with precision missiles."},
	"hac_ew": {"name": "Veil EW Vehicle", "faction": "hac", "cat": CAT_VEH, "move": MOVE_WHEELED, "speed": 11.0, "turn": 1.5,
		"hp": 380.0, "members": 1, "loadout": [], "armor": [30, 20, 15, 10],
		"sight": 65.0, "camo": 1.0, "thermal": true, "morale": "human", "base_morale": 95.0, "radius": 3.0, "eye": 2.5,
		"points": 18, "special": ["jammer", "network_node"], "role": "Jams enemy drones and guided missiles nearby."},
	"hac_mast": {"name": "Sensor Mast", "faction": "hac", "cat": CAT_VEH, "move": MOVE_WHEELED, "speed": 10.0, "turn": 1.5,
		"hp": 300.0, "members": 1, "loadout": [], "armor": [20, 15, 10, 8],
		"sight": 70.0, "camo": 1.1, "thermal": true, "morale": "human", "base_morale": 95.0, "radius": 3.0, "eye": 3.0,
		"points": 14, "special": ["sensor_mast", "network_node"], "role": "Deploys a mast when stationary: huge sight, spots camouflage."},
}

## Team-level support powers (no economy: limited charges + cooldowns).
const SUPPORT := {
	"artillery": {"name": "Artillery Barrage", "desc": "8 heavy shells on an area after a short delay.", "delay": 7.0, "cooldown": 90.0, "radius": 26.0},
	"airstrike": {"name": "Airstrike", "desc": "A jet bombs a line through the target.", "delay": 9.0, "cooldown": 150.0, "radius": 40.0},
	"recon_uav": {"name": "Recon UAV", "desc": "Reveals a large area for 30 seconds.", "delay": 3.0, "cooldown": 70.0, "radius": 90.0},
	"smoke_barrage": {"name": "Smoke Screen", "desc": "Blocks line of sight across an area.", "delay": 5.0, "cooldown": 60.0, "radius": 30.0},
	"rocket_barrage": {"name": "Improvised Rockets", "desc": "Inaccurate rocket salvo on an area.", "delay": 6.0, "cooldown": 80.0, "radius": 35.0},
	"minefield": {"name": "Minefield", "desc": "Hidden anti-vehicle mines in a small area.", "delay": 2.0, "cooldown": 60.0, "radius": 14.0},
	"tunnel": {"name": "Tunnel Ambush", "desc": "A militia squad emerges from a building you can see.", "delay": 4.0, "cooldown": 75.0, "radius": 0.0},
	"drone_strike": {"name": "Orbital Drone Strike", "desc": "Precision missile on a point after a short delay.", "delay": 5.0, "cooldown": 70.0, "radius": 8.0},
	"emp": {"name": "EW Burst", "desc": "Suppresses all units and stalls guided weapons in an area.", "delay": 2.0, "cooldown": 90.0, "radius": 35.0},
}

const FACTIONS := {
	"cdf": {"name": "Coalition Defense Force", "short": "CDF", "kind": "Conventional Military",
		"color": Color(0.32, 0.55, 0.85), "desc": "Modern combined-arms military: armor, air support, thermal sights, artillery.",
		"support": {"artillery": 2, "airstrike": 1, "recon_uav": 2, "smoke_barrage": 2},
		"forces": ["cdf_rifle", "cdf_rifle", "cdf_rifle", "cdf_mg", "cdf_atgm", "cdf_sniper", "cdf_mortar", "cdf_mbt", "cdf_mbt", "cdf_ifv", "cdf_mrap", "cdf_heli", "cdf_supply"],
		"reinforcements": [["cdf_rifle", "cdf_rifle", "cdf_mrap"], ["cdf_mbt", "cdf_atgm"]]},
	"pdb": {"name": "People's Defense Brigades", "short": "PDB", "kind": "Light Forces",
		"color": Color(0.85, 0.45, 0.25), "desc": "Numerous, concealed light infantry and technicals. Master of ambush and urban terrain.",
		"support": {"rocket_barrage": 2, "minefield": 2, "tunnel": 2, "smoke_barrage": 1},
		"forces": ["pdb_militia", "pdb_militia", "pdb_militia", "pdb_militia", "pdb_militia", "pdb_rpg", "pdb_rpg", "pdb_hmg", "pdb_hmg", "pdb_marksman", "pdb_mortar", "pdb_manpads", "pdb_technical", "pdb_technical", "pdb_spg", "pdb_mrl", "pdb_tank"],
		"reinforcements": [["pdb_militia", "pdb_militia", "pdb_rpg", "pdb_technical"], ["pdb_militia", "pdb_hmg", "pdb_spg"], ["pdb_militia", "pdb_militia", "pdb_rpg"]]},
	"hac": {"name": "Helix Autonomous Command", "short": "HAC", "kind": "Advanced Autonomous Forces",
		"color": Color(0.3, 0.85, 0.8), "desc": "Drones, robots and sensors. Superb vision and precision, few humans, vulnerable to jamming.",
		"support": {"drone_strike": 3, "recon_uav": 2, "emp": 2, "smoke_barrage": 1},
		"forces": ["hac_operator", "hac_operator", "hac_hound", "hac_hound", "hac_hound", "hac_ugv_gun", "hac_ugv_gun", "hac_ugv_atgm", "hac_recon", "hac_recon", "hac_fpv", "hac_fpv", "hac_fpv", "hac_wasp", "hac_wasp", "hac_ucav", "hac_ew", "hac_mast"],
		"reinforcements": [["hac_hound", "hac_fpv", "hac_fpv", "hac_wasp"], ["hac_ugv_atgm", "hac_ugv_gun", "hac_operator"]]},
}

const FACTION_ORDER := ["cdf", "pdb", "hac"]


static func unit(id: String) -> Dictionary:
	return UNITS[id]


static func weapon(id: String) -> Dictionary:
	return WEAPONS[id]


static func has_special(def: Dictionary, tag: String) -> bool:
	return tag in def.get("special", [])


static func units_of(faction: String) -> Array:
	var out := []
	for id in UNITS:
		if UNITS[id]["faction"] == faction:
			out.append(id)
	return out
