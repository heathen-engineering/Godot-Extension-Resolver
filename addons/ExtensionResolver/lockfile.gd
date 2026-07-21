@tool
class_name ExtensionLockfile
extends RefCounted

## Records exactly which addons + exact versions are currently installed, so a project that
## deliberately doesn't check its fetched addons/ contents into version control (deep-copied
## GDExtension binaries are large and don't diff meaningfully — see docs/lockfile-schema.md)
## can still restore itself deterministically from a fresh, stripped-down clone. Modeled on
## Unity UPM's Packages/packages-lock.json: a single project-root file, regenerated
## automatically after every install/update/remove, never hand-edited.
##
## Deliberately separate from both manifest_reader.gd (reads one already-installed addon's own
## authoritative extension.manifest.json) and library_manifest.gd (reads a third party's
## discovery catalogue) — this file's job is narrower than either: a project-wide snapshot of
## "what's actually here right now", for the one purpose of rebuilding that same state later.

const DEFAULT_LOCKFILE_PATH := "res://addons.lock.json"
const CURRENT_LOCKFILE_SCHEMA_VERSION := 1

## preload(), not bare global class_name references — restore_missing()'s whole reason to exist
## is bootstrapping a fresh, stripped clone that may never have had an editor session build the
## global script-class cache (same reasoning as test_semver.gd's header comment). Bare names
## work fine everywhere else in this addon because everything else only ever runs inside an
## already-running editor.
const ExtensionManifestReader = preload("res://addons/ExtensionResolver/manifest_reader.gd")
const ExtensionSemver = preload("res://addons/ExtensionResolver/semver.gd")
const ExtensionSourceGithubRelease = preload("res://addons/ExtensionResolver/source_github_release.gd")

## Rebuilds the lockfile from whatever's actually installed right now (via
## ExtensionManifestReader.scan_installed()) and writes it to DEFAULT_LOCKFILE_PATH. Always a
## full regeneration, never a partial patch — same reasoning as
## ExtensionLibraryManifest.save_configured_sources(): the file only ever reflects one thing
## (current ground truth), so there's no merge/patch case to get wrong. Addons with no "source"
## declared are skipped — nothing for a restore to fetch them from, so listing them would just
## be noise a restore can never satisfy.
static func write_lockfile() -> bool:
	var installed := ExtensionManifestReader.scan_installed()
	var ids := installed.keys()
	ids.sort()

	var entries: Array = []
	for id in ids:
		var manifest: Dictionary = installed[id]
		var source: Dictionary = manifest.get("source", {})
		if String(source.get("repo", "")).is_empty():
			continue
		entries.append({
			"id": id,
			"version": manifest.get("version", ""),
			"source": source,
		})

	var doc := {
		"schema_version": CURRENT_LOCKFILE_SCHEMA_VERSION,
		"entries": entries,
	}

	var file := FileAccess.open(DEFAULT_LOCKFILE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("ExtensionLockfile: could not open %s for writing." % DEFAULT_LOCKFILE_PATH)
		return false
	file.store_string(JSON.stringify(doc, "    "))
	file.close()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().call_deferred("scan")
	return true

## Defensive parse, same shape/behavior as manifest_reader.gd and library_manifest.gd: a
## malformed or absent lockfile degrades to "nothing found here" (empty entries array), never a
## crash — a stripped clone that has no lockfile yet at all is a normal, valid state, not an
## error.
static func read_lockfile() -> Array:
	if not FileAccess.file_exists(DEFAULT_LOCKFILE_PATH):
		return []
	var file := FileAccess.open(DEFAULT_LOCKFILE_PATH, FileAccess.READ)
	if file == null:
		push_warning("ExtensionLockfile: could not open %s for reading." % DEFAULT_LOCKFILE_PATH)
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("entries"):
		push_warning("ExtensionLockfile: %s is not a valid lockfile (expected an 'entries' array)." % DEFAULT_LOCKFILE_PATH)
		return []
	var entries: Variant = parsed["entries"]
	return entries if typeof(entries) == TYPE_ARRAY else []

## Pure function, no I/O — diffs lockfile_entries (as read_lockfile() returns) against
## installed (as ExtensionManifestReader.scan_installed() returns) and returns the subset that
## needs fetching: not installed at all, or installed at a version that doesn't match the
## pinned one exactly (restoring should reproduce precisely what was locked, not just "some
## version satisfying a range" — that's dependency-resolution's job, a different concern from
## this one). Kept separate from restore_missing() so it's testable without any network access,
## same shape as every other pure-logic function in this addon (ExtensionSemver.compare(),
## ExtensionSourceGithubRelease.relative_path_within_id()/select_asset_url()).
static func compute_missing(lockfile_entries: Array, installed: Dictionary) -> Array:
	var missing: Array = []
	for entry in lockfile_entries:
		if typeof(entry) != TYPE_DICTIONARY or not entry.has("id"):
			continue
		var id: String = entry["id"]
		var locked_version: String = String(entry.get("version", ""))
		if not installed.has(id):
			missing.append(entry)
			continue
		var installed_version: String = String(installed[id].get("version", ""))
		if ExtensionSemver.compare(installed_version, locked_version) != 0:
			missing.append(entry)
	return missing

## Fetches and extracts every lockfile entry compute_missing() flags, at its exact pinned
## version (not "latest" — see resolver.gd's _fetch_one() doc comment on why that method can't
## be reused here as-is: it only ever runs for an addon that's already present and loading,
## which is exactly the case a stripped clone doesn't have). Returns { fetched: [ids...],
## failed: [ids...] }. status_callback(String), if given, is called with a one-line progress
## message per entry — same "something is visibly happening" reasoning as
## ExtensionResolverCore._fetch_all()'s status_label.
static func restore_missing(host: Node, status_callback: Callable = Callable()) -> Dictionary:
	var lockfile_entries := read_lockfile()
	var installed := ExtensionManifestReader.scan_installed()
	var missing := compute_missing(lockfile_entries, installed)

	var result := {"fetched": [], "failed": []}
	for entry in missing:
		var id: String = entry["id"]
		var version: String = String(entry.get("version", ""))
		var source: Dictionary = entry.get("source", {})
		var repo: String = String(source.get("repo", ""))

		if status_callback.is_valid():
			status_callback.call("Restoring %s @ %s..." % [id, version])

		if repo.is_empty():
			result["failed"].append(id)
			continue

		var err: Array = [""]
		# Ecosystem convention (confirmed against list_panel.gd's own
		# tag_name.trim_prefix("v") assumption): release tags are "v" + semver, not bare semver.
		var release = await ExtensionSourceGithubRelease.fetch_release(host, repo, "v" + version, err)
		if release == null:
			result["failed"].append(id)
			continue

		var url := ExtensionSourceGithubRelease.select_asset_url(release, id, source.get("asset_pattern", ""))
		if url.is_empty():
			result["failed"].append(id)
			continue

		var ok := await ExtensionSourceGithubRelease.fetch_and_extract(host, url, id, err)
		if not ok:
			result["failed"].append(id)
			continue

		result["fetched"].append(id)

	return result
