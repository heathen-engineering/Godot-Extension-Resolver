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

## Bundled with this addon itself (see default_library.json), listing every
## current Heathen Foundation gem for Godot, so installing Extension Resolver
## "raw" surfaces the whole family in the Libraries tab immediately, rather
## than a user needing to already know each Foundation's repo URL to add it
## by hand one at a time. Seeded into a project's own config the first time
## that config is created (see load_configured_sources() below), not
## hardcoded into every read. Once seeded, it's a completely ordinary
## configured source: editable/removable through the normal Libraries
## management window like any other, no special-cased "can't remove this
## one" behavior.
const DEFAULT_LIBRARY_SOURCE := {
	"type": "local",
	"path": "res://addons/ExtensionResolver/default_library.json",
}

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

## Returns the list of configured Library sources, each a Dictionary shaped
## { "type": "url"|"local", "url"|"path": String }. If the config file
## doesn't exist yet, it's created and seeded with DEFAULT_LIBRARY_SOURCE
## (see that constant's own comment for why) rather than just returning an
## empty array. This is the one case where this method writes, not just
## reads, but only on the very first call for a given project; every
## subsequent call reads whatever the file already says, including a project
## that has since removed the default source entirely.
static func load_configured_sources() -> Array:
	var path := configured_path()
	if not FileAccess.file_exists(path):
		save_configured_sources([DEFAULT_LIBRARY_SOURCE])
		return [DEFAULT_LIBRARY_SOURCE]

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
