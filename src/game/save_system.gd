extends RefCounted
## Save games and replays on disk (user://saves, user://replays) using Godot's
## native variant text format (keeps Vector2 and packed arrays intact).
class_name SaveSystem

const SAVE_DIR := "user://saves"
const REPLAY_DIR := "user://replays"


static func _stamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second]


static func _write(path: String, data: Variant) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(data)   # binary variant format: lossless doubles (exact replays / saves)
	return true


static func _read(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return f.get_var()


static func save_session(s: GameSession) -> String:
	var cfg := s.config.duplicate()
	cfg.erase("map")
	cfg.erase("state")
	cfg.erase("replay")
	var data := {"version": 1, "kind": "save", "saved_at": Time.get_datetime_string_from_system(),
		"title": "%s — %s vs %s" % [s.sim.map.name, s.sim.teams[0]["name"], s.sim.teams[1]["name"]],
		"config": cfg, "map": s.sim.map.to_dict(), "initial_map": s.initial_map, "state": Serializer.capture(s.sim)}
	var path := "%s/save_%s.sav" % [SAVE_DIR, _stamp()]
	_write(path, data)
	return path


## Returns a GameSession config ready to start, or {} on failure.
static func load_save(path: String) -> Dictionary:
	var data = _read(path)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var cfg: Dictionary = data["config"].duplicate()
	cfg["map"] = MapDef.from_dict(data["map"])
	cfg["state"] = data["state"]
	cfg["initial_map"] = data.get("initial_map", data["map"])
	return cfg


static func save_replay(replay: Dictionary) -> String:
	var path := "%s/replay_%s.replay" % [REPLAY_DIR, _stamp()]
	_write(path, replay)
	return path


static func load_replay(path: String) -> Dictionary:
	var data = _read(path)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var cfg: Dictionary = data["config"].duplicate()
	cfg["map"] = MapDef.from_dict(data["map"])
	cfg["replay"] = data
	cfg["player_team"] = -1
	for t in cfg["teams"]:
		t["controller"] = "replay"
	return cfg


static func list(dir: String, ext: String) -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(ext):
			out.append(dir + "/" + f)
	out.sort()
	out.reverse()
	return out
