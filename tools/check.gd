extends SceneTree
## Parse-checks every script under res://src and res://tests. Exit 1 on failure.

func _initialize() -> void:
	var bad := 0
	var files: Array[String] = []
	_collect("res://src", files)
	_collect("res://tests", files)
	for f in files:
		var s = ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_IGNORE)
		if s == null or not (s as GDScript).can_instantiate():
			bad += 1
			print("FAILED: ", f)
	print("checked %d scripts, %d failed" % [files.size(), bad])
	quit(1 if bad > 0 else 0)


func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + d, out)
