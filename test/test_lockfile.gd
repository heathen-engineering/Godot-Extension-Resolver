extends RefCounted

## Covers ExtensionLockfile.compute_missing() — the pure diff logic restore_missing() builds on.
## Deliberately doesn't test write_lockfile()/read_lockfile() (real file I/O against res://,
## awkward to isolate in this test runner) or restore_missing() (needs a live network fetch) —
## just the part that's pure logic and where a wrong diff would silently under- or over-fetch.
##
## preload(), not the global class_name — see test_semver.gd's header comment for why.
const ExtensionLockfile = preload("res://addons/ExtensionResolver/lockfile.gd")

func run(assert_fn: Callable) -> void:
	_test_missing_when_not_installed(assert_fn)
	_test_missing_when_version_differs(assert_fn)
	_test_not_missing_when_version_matches(assert_fn)
	_test_ignores_malformed_entries(assert_fn)

func _test_missing_when_not_installed(assert_fn: Callable) -> void:
	var lockfile_entries := [
		{"id": "FoundationXxHash", "version": "1.0.0", "source": {"type": "github_release", "repo": "x/y"}},
	]
	var installed := {}
	var missing := ExtensionLockfile.compute_missing(lockfile_entries, installed)
	assert_fn.call(missing.size() == 1 and missing[0]["id"] == "FoundationXxHash",
		"an entry with nothing installed at all is reported missing")

func _test_missing_when_version_differs(assert_fn: Callable) -> void:
	var lockfile_entries := [
		{"id": "FoundationXxHash", "version": "1.2.0", "source": {"type": "github_release", "repo": "x/y"}},
	]
	var installed := {"FoundationXxHash": {"version": "1.0.0"}}
	var missing := ExtensionLockfile.compute_missing(lockfile_entries, installed)
	assert_fn.call(missing.size() == 1,
		"an entry installed at a different version than locked is reported missing (exact match required, not a range)")

func _test_not_missing_when_version_matches(assert_fn: Callable) -> void:
	var lockfile_entries := [
		{"id": "FoundationXxHash", "version": "1.0.0", "source": {"type": "github_release", "repo": "x/y"}},
	]
	var installed := {"FoundationXxHash": {"version": "1.0.0"}}
	var missing := ExtensionLockfile.compute_missing(lockfile_entries, installed)
	assert_fn.call(missing.is_empty(),
		"an entry installed at exactly the locked version is not reported missing")

	var installed_v_prefixed := {"FoundationXxHash": {"version": "v1.0.0"}}
	var missing_v := ExtensionLockfile.compute_missing(lockfile_entries, installed_v_prefixed)
	assert_fn.call(missing_v.is_empty(),
		"version comparison ignores a 'v' prefix either side (delegates to ExtensionSemver.compare)")

func _test_ignores_malformed_entries(assert_fn: Callable) -> void:
	var lockfile_entries := ["not a dictionary", {"no_id": true}, {"id": "Real", "version": "1.0.0"}]
	var installed := {}
	var missing := ExtensionLockfile.compute_missing(lockfile_entries, installed)
	assert_fn.call(missing.size() == 1 and missing[0]["id"] == "Real",
		"non-dictionary and id-less entries are skipped rather than crashing or being reported missing")
