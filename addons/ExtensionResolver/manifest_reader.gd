@tool
class_name ExtensionManifestReader
extends RefCounted

## Reads extension.manifest.json files — see docs/manifest-schema.md for the
## full schema. Pure read/parse only, no fetching or network access here
## (that's ExtensionSourceGithubRelease's job) and no policy decisions about
## what to do with a missing/unsatisfied dependency (that's ExtensionResolver's
## job) — this class exists so both of those, plus the Settings tab, share one
## parsing implementation instead of three slightly-different ones.

const MANIFEST_FILENAME := "extension.manifest.json"
const CURRENT_SCHEMA_VERSION := 1

## Scans res://addons/*/extension.manifest.json and returns a Dictionary of
## id -> parsed manifest Dictionary for every addon that ships one. Addons
## without a manifest are simply not represented — mirrors
## HeathenDependencyManifest.scan_installed()'s existing behavior in
## Godot-Game-Framework, rewritten against the new schema/filename.
static func scan_installed() -> Dictionary:
	var result: Dictionary = {}
	var addons_dir := DirAccess.open("res://addons")
	if addons_dir == null:
		return result

	addons_dir.list_dir_begin()
	var entry := addons_dir.get_next()
	while entry != "":
		if addons_dir.current_is_dir() and not entry.begins_with("."):
			var manifest := read_manifest_for(entry)
			if manifest != null:
				result[entry] = manifest
		entry = addons_dir.get_next()
	addons_dir.list_dir_end()

	return result

## Reads res://addons/<addon_id>/extension.manifest.json directly — used
## when only one specific addon's manifest is needed (e.g. checking a single
## dependency) rather than the whole project. Returns null if the addon
## doesn't exist, has no manifest, or the manifest is malformed.
static func read_manifest_for(addon_id: String) -> Variant:
	return _read("res://addons/%s/%s" % [addon_id, MANIFEST_FILENAME])

static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("id"):
		push_warning("ExtensionManifestReader: malformed manifest at %s" % path)
		return null

	# schema_version is forward-compatibility bookkeeping, not enforced yet —
	# there's only ever been version 1 so far. Once a version 2 exists this
	# is where a migration/rejection decision gets made; deliberately not
	# building that machinery before there's a second version to migrate
	# from.
	if int(parsed.get("schema_version", 0)) > CURRENT_SCHEMA_VERSION:
		push_warning("ExtensionManifestReader: %s declares schema_version %s, newer than this resolver understands (%s)." % [path, parsed["schema_version"], CURRENT_SCHEMA_VERSION])

	return parsed
