## Headless test runner for the splat addon. It runs every [code]test_*.gd[/code] beside it, so a new
## suite is a new file and nothing here changes. From a project assembled by
## [code]dev/make_project.py[/code]:
##
##   godot --path <folder> --headless -s res://tests/test_runner.gd
##
## A suite extends [Object] and has [code]run_tests() -> int[/code], which returns how many checks failed.
## Exit code 0: every suite passed. 1: a check failed, a suite could not be loaded, or there was none.
extends SceneTree


# region Lifecycle
# Not in _init: a suite that draws needs the tree's root in the tree, which it is once the loop has started.
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var folder: String = (get_script() as Script).resource_path.get_base_dir()
	var files: PackedStringArray = PackedStringArray()
	for file: String in DirAccess.get_files_at(folder):
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_runner.gd":
			files.append(file)
	files.sort()
	print("Starting tests: %d suite(s) in %s" % [files.size(), folder])

	var failures: int = 0
	var broken: int = 0
	for file: String in files:
		var script: GDScript = load(folder.path_join(file)) as GDScript
		var suite: Object = script.new() if script != null and script.can_instantiate() else null
		if suite == null or not suite.has_method("run_tests"):
			print("FAIL: %s could not be loaded, or has no run_tests()" % file)
			broken += 1
			continue
		print("--- %s" % file)
		failures += suite.call("run_tests")
		if not suite is RefCounted:
			suite.free()

	print("Tests finished. Total failures: %d%s" % [failures, "" if broken == 0 else ", and %d suite(s) not run" % broken])
	var passed: bool = failures == 0 and broken == 0 and not files.is_empty()
	print("Status: %s" % ("PASSED" if passed else "FAILED"))
	quit(0 if passed else 1)
# endregion
