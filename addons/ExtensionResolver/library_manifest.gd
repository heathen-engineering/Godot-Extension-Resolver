@tool
class_name ExtensionLibraryManifest
extends RefCounted

## Reads/writes the project's configured Library sources, and fetches/parses
## a single Library's own JSON (see docs/library-schema.md). Deliberately
## separate from manifest_reader.gd — that file reads an *installed* addon's
## own extension.manifest.json (authoritative, on disk next to plugin.cfg);
## this file reads a third party's *catalogue* of entries about addons that
## may not be installed at all yet. Mirrors manifest_reader.gd's defensive
## parsing shape (validate TYPE_DICTIONARY + a required key, warn-not-error
## on anything else) on purpose, for the same reason: a malformed file from
## an external source should degrade to "nothing found here", never a crash.

const CONFIG_SETTING := "extension_resolver/libraries_config_path"
const DEFAULT_CONFIG_PATH := "res://addon_libraries.json"
const CURRENT_LIBRARY_SCHEMA_VERSION := 1

## Registers the ProjectSettings entry if it isn't already there, and returns
## its current value — same "just works with the default, but is a real
## editable project setting" shape ProjectSettings expects, rather than the
## caller reaching for get_setting() with an inline default every time.
static func configured_path() -> String:
	if not ProjectSettings.has_setting(CONFIG_SETTING):
		ProjectSettings.set_setting(CONFIG_SETTING, DEFAULT_CONFIG_PATH)
		ProjectSettings.set_initial_value(CONFIG_SETTING, DEFAULT_CONFIG_PATH)
	var path: String = ProjectSettings.get_setting(CONFIG_SETTING, DEFAULT_CONFIG_PATH)
	return path if not path.is_empty() else DEFAULT_CONFIG_PATH

## Returns the list of configured Library sources — each a Dictionary shaped
## { "type": "url"|"local", "url"|"path": String }. Empty array (not an
## error) if the config file doesn't exist yet — a project that has never
## added a Library is a perfectly normal, common state, same as "no
## extensions installed yet" is for manifest_reader.gd.
static func load_configured_sources() -> Array:
	var path := configured_path()
	if not FileAccess.file_exists(path):
		return []

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("ExtensionLibraryManifest: could not open %s for reading." % path)
		return []

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("libraries"):
		push_warning("ExtensionLibraryManifest: %s is not a valid libraries config (expected a 'libraries' array)." % path)
		return []

	var libraries: Variant = parsed["libraries"]
	return libraries if typeof(libraries) == TYPE_ARRAY else []

## Writes sources back to the configured path, creating the file fresh if it
## didn't already exist. Called by the Libraries management window's
## Add/Edit/Remove actions — never by anything that runs unprompted.
static func save_configured_sources(sources: Array) -> bool:
	var path := configured_path()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("ExtensionLibraryManifest: could not open %s for writing." % path)
		return false

	var doc := {
		"schema_version": CURRENT_LIBRARY_SCHEMA_VERSION,
		"libraries": sources,
	}
	file.store_string(JSON.stringify(doc, "    "))
	file.close()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().call_deferred("scan")
	return true

## Fetches and parses one Library's JSON from its source Dictionary. Returns
## null (and leaves details in out_error, if given) on any failure — same
## contract as ExtensionSourceGithubRelease.fetch_release(). host is any Node
## currently in the tree, used only to parent a temporary HTTPRequest for the
## "url" source type.
static func fetch_library(host: Node, source: Dictionary, out_error: Array = []) -> Variant:
	var source_type: String = String(source.get("type", ""))
	var text: String

	if source_type == "local":
		var path: String = String(source.get("path", ""))
		if path.is_empty() or not FileAccess.file_exists(path):
			if not out_error.is_empty():
				out_error[0] = "Local library path %s not found." % path
			return null
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			if not out_error.is_empty():
				out_error[0] = "Could not open local library path %s." % path
			return null
		text = file.get_as_text()

	elif source_type == "url":
		var url: String = String(source.get("url", ""))
		if url.is_empty():
			if not out_error.is_empty():
				out_error[0] = "Library source has no url."
			return null
		# Reuses ExtensionSourceGithubRelease's own HTTPRequest-await helper
		# directly rather than duplicating the same boilerplate here — this
		# codebase already treats underscore-prefixed static helpers as fair
		# game to call across files within the addon (settings_tab.gd calls
		# ExtensionResolverCore._check_dependencies() the same way).
		var body := await ExtensionSourceGithubRelease._get_bytes(host, url, PackedStringArray(), out_error)
		if body.is_empty():
			return null
		text = body.get_string_from_utf8()

	else:
		if not out_error.is_empty():
			out_error[0] = "Unknown library source type '%s' (expected 'local' or 'url')." % source_type
		return null

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("entries"):
		if not out_error.is_empty():
			out_error[0] = "Library JSON is not valid (expected an 'entries' array)."
		return null

	var schema_version: int = int(parsed.get("schema_version", 0))
	if schema_version > CURRENT_LIBRARY_SCHEMA_VERSION:
		push_warning("ExtensionLibraryManifest: library declares schema_version %d, newer than this resolver's %d — parsing anyway, some fields may be ignored." % [schema_version, CURRENT_LIBRARY_SCHEMA_VERSION])

	return parsed
