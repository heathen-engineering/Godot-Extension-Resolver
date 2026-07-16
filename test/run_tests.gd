extends SceneTree

## Lightweight standalone test runner — no GUT dependency, since this addon
## has none of its own and shouldn't gain one just for tests. Run via:
##   godot --headless --script res://test/run_tests.gd
## Exits with code 1 if any assertion fails (so CI can gate on it), 0 if all
## pass. Each test_*.gd file under this folder is a plain RefCounted with a
## run(assert_fn: Callable) method; assert_fn(condition, message) records a
## pass/fail without stopping the run, so one failing assertion doesn't hide
## the rest.

var _pass := 0
var _fail := 0

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	var suite_paths := [
		"res://test/test_semver.gd",
		"res://test/test_source_github_release.gd",
		"res://test/test_default_library.gd",
	]
	for path in suite_paths:
		var suite = load(path).new()
		suite.run(_assert)

	print("\n%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
