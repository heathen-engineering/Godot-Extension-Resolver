extends RefCounted

## Covers ExtensionSemver.parse/compare/satisfies — the exact logic
## dependency gating hinges on, and the highest-leverage place for a silent
## bug to hide (see docs/manifest-schema.md's resolved "pre-release
## suffixes" question — this is what pins that behavior down).
##
## preload(), not the global class_name — a plain `--headless --script` run
## (no `--editor`) never builds the global script-class cache, so bare
## "ExtensionSemver" wouldn't resolve; preloading by path sidesteps that
## entirely and needs no editor session just to run these tests.
const ExtensionSemver = preload("res://addons/ExtensionResolver/semver.gd")

func run(assert_fn: Callable) -> void:
	assert_fn.call(ExtensionSemver.compare("1.0.0", "1.0.0") == 0, "1.0.0 == 1.0.0")
	assert_fn.call(ExtensionSemver.compare("1.0.1", "1.0.0") == 1, "1.0.1 > 1.0.0")
	assert_fn.call(ExtensionSemver.compare("1.0.0", "1.0.1") == -1, "1.0.0 < 1.0.1")
	assert_fn.call(ExtensionSemver.compare("2.0.0", "1.9.9") == 1, "2.0.0 > 1.9.9 (major beats minor/patch)")
	assert_fn.call(ExtensionSemver.compare("v1.2.3", "1.2.3") == 0, "leading 'v' is stripped")
	assert_fn.call(ExtensionSemver.compare("1.2.3-beta", "1.2.3") == 0, "pre-release suffix is ignored, not compared")
	assert_fn.call(ExtensionSemver.compare("1.2.3+build5", "1.2.3") == 0, "build metadata is ignored")
	assert_fn.call(ExtensionSemver.compare("1.2.3-beta+build5", "1.2.3") == 0, "combined -/+ suffix, cuts at the earlier one")
	assert_fn.call(ExtensionSemver.compare("1.2", "1.2.0") == 0, "missing patch defaults to 0")
	assert_fn.call(ExtensionSemver.compare("1", "1.0.0") == 0, "missing minor and patch default to 0")
	assert_fn.call(ExtensionSemver.compare("abc", "0.0.0") == 0, "malformed version compares as very old instead of crashing")
	assert_fn.call(ExtensionSemver.compare("1.x.0", "1.0.0") == 0, "non-numeric component defaults to 0, doesn't crash")

	assert_fn.call(ExtensionSemver.satisfies("1.5.0", "1.0.0", "") == true, "satisfies: at/above min, no max bound")
	assert_fn.call(ExtensionSemver.satisfies("1.0.0", "1.0.0", "") == true, "satisfies: exactly at min is inclusive")
	assert_fn.call(ExtensionSemver.satisfies("0.9.0", "1.0.0", "") == false, "satisfies: below min fails")
	assert_fn.call(ExtensionSemver.satisfies("1.5.0", "", "2.0.0") == true, "satisfies: below max, no min bound")
	assert_fn.call(ExtensionSemver.satisfies("2.0.0", "", "2.0.0") == true, "satisfies: exactly at max is inclusive")
	assert_fn.call(ExtensionSemver.satisfies("2.5.0", "", "2.0.0") == false, "satisfies: above max fails")
	assert_fn.call(ExtensionSemver.satisfies("1.5.0", "1.0.0", "2.0.0") == true, "satisfies: within an explicit range")
	assert_fn.call(ExtensionSemver.satisfies("2.5.0", "1.0.0", "2.0.0") == false, "satisfies: above range fails even with a min set")
	assert_fn.call(ExtensionSemver.satisfies("1.5.0") == true, "satisfies: no bounds at all always passes")
