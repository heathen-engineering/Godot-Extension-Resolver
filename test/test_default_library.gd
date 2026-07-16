extends RefCounted

## Covers the bundled default_library.json shipped with this addon (see
## library_manifest.gd's DEFAULT_LIBRARY_SOURCE). Regression protection so a
## future hand-edit of that file can't silently break its own JSON or drop
## one of the Foundation entries it's meant to always list. Doesn't exercise
## the seeding side effects (FileAccess/ProjectSettings) themselves; that
## needs a real project context and is covered by manual verification
## instead (see docs/extensions/12-discord-showcase.md's session history in
## the consuming TheBarrow repo for the cold-install test this was verified
## against).

const EXPECTED_IDS := [
	"FoundationGameFramework",
	"FoundationGameplayTags",
	"FoundationLexicon",
	"FoundationOgham",
	"FoundationSteamworks",
	"FoundationXxHash",
]

func run(assert_fn: Callable) -> void:
	var file := FileAccess.open("res://addons/ExtensionResolver/default_library.json", FileAccess.READ)
	assert_fn.call(file != null, "default_library.json should exist and be readable")
	if file == null:
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert_fn.call(typeof(parsed) == TYPE_DICTIONARY, "default_library.json should parse as a JSON object")
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	assert_fn.call(parsed.has("entries") and typeof(parsed["entries"]) == TYPE_ARRAY, "default_library.json should have an 'entries' array")
	var entries: Array = parsed.get("entries", [])
	assert_fn.call(entries.size() == EXPECTED_IDS.size(), "expected exactly %d bundled Foundation entries, found %d" % [EXPECTED_IDS.size(), entries.size()])

	var found_ids: Array = []
	for entry in entries:
		assert_fn.call(typeof(entry) == TYPE_DICTIONARY and entry.has("id"), "every entry should be an object with an 'id'")
		if typeof(entry) == TYPE_DICTIONARY:
			found_ids.append(entry.get("id", ""))
			assert_fn.call(String(entry.get("source", {}).get("type", "")) == "github_release", "entry '%s' should use a github_release source" % entry.get("id", "?"))
			assert_fn.call(not String(entry.get("description", "")).is_empty(), "entry '%s' should have a non-empty description" % entry.get("id", "?"))

	for expected_id in EXPECTED_IDS:
		assert_fn.call(found_ids.has(expected_id), "default_library.json is missing expected entry '%s'" % expected_id)
