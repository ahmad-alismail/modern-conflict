extends SceneTree
## Headless test runner. Discovers tests/test_*.gd, runs every method starting with
## `test_`, prints results and exits with code 1 on any failure.
##   godot --headless --path . -s res://tests/run_tests.gd -- --filter=nav

var _failures: Array[String] = []
var _current := ""


func _initialize() -> void:
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--filter="):
			filter = String(a).substr(9)
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd"):
			if filter == "" or f.contains(filter):
				files.append(f)
	files.sort()
	var total := 0
	var t0 := Time.get_ticks_msec()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		var inst = script.new()
		inst.set("runner", self)
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			_current = f.get_basename() + "." + name
			var before := _failures.size()
			var t := Time.get_ticks_msec()
			inst.call(name)
			total += 1
			var ok := _failures.size() == before
			print("%s %s (%d ms)" % ["  PASS" if ok else "  FAIL", _current, Time.get_ticks_msec() - t])
		if inst is Node:
			inst.free()
	print("\n%d tests, %d failures, %d ms" % [total, _failures.size(), Time.get_ticks_msec() - t0])
	for msg in _failures:
		print("  - " + msg)
	quit(1 if _failures.size() > 0 else 0)


func fail(msg: String) -> void:
	_failures.append("%s: %s" % [_current, msg])
	push_error(_current + ": " + msg)
