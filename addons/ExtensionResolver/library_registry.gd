@tool
class_name ExtensionLibraryRegistry
extends RefCounted

## Owns the "Libraries" tab's data: the configured Library sources, their
## last-scanned entries (cached per-machine under user://, never
## project-shared — only the *list of configured sources* is project-shared,
## via library_manifest.gd), and installing/updating/removing an entry.
## Deliberately a plain RefCounted the Libraries tab instantiates for itself,
## not a second Engine singleton — nothing else in this addon needs to reach
## a Library Entry, unlike ExtensionResolverCore, which every gem's gate stub
## calls into.
##
## Scanning is on-demand only, never live/polling — refresh_all() runs when
## the Libraries tab is first shown in a session, or when the user clicks an
## explicit Refresh control. This is a utility, not a background service.

const CACHE_DIR := "user://extension_resolver/library_cache"

var _entries: Array = [] # each a Dictionary: the Library Entry itself, plus "_library_name"/"_library_source" bookkeeping keys.
var _has_scanned_this_session := false

## Every entry from every configured Library, flattened. Loads from the
## per-machine cache on first call if refresh_all() hasn't run yet this
## session, so the tab has something to show immediately rather than an
## empty list before the user ever clicks Refresh.
func get_all_entries() -> Array:
	if not _has_scanned_this_session:
		_load_from_cache()
	return _entries

## Re-fetches every configured Library source and rebuilds _entries, writing
## each successfully-fetched Library's parsed content to the per-machine
## cache. Failures (unreachable URL, missing local file, malformed JSON) are
## skipped, not fatal to the others — one bad Library shouldn't blank the
## whole tab.
func refresh_all(host: Node) -> void:
	var sources := ExtensionLibraryManifest.load_configured_sources()
	var new_entries: Array = []

	for source in sources:
		if typeof(source) != TYPE_DICTIONARY:
			continue
		var err: Array = [""]
		var library = await ExtensionLibraryManifest.fetch_library(host, source, err)
		if library == null:
			push_warning("ExtensionLibraryRegistry: skipping library (%s): %s" % [source.get("url", source.get("path", "?")), err[0]])
			continue

		_write_cache(source, library)
		new_entries.append_array(_flatten(source, library))

	_entries = new_entries
	_has_scanned_this_session = true

## Installs a not-yet-installed entry via the exact same fetch pipeline a
## missing-dependency fetch already uses (ExtensionResolverCore._fetch_one())
## — an entry Dictionary is already shaped { id, source: { repo, asset_pattern } },
## the same shape _fetch_one() expects for a dependency issue, so no
## adaptation/duplication is needed, just the same call from a different
## trigger (a Libraries-tab button instead of a missing-dependency dialog).
func install_entry(host: Node, resolver: ExtensionResolverCore, entry: Dictionary) -> bool:
	return await resolver._fetch_one(host, entry)

func _flatten(source: Dictionary, library: Dictionary) -> Array:
	var library_name: String = String(library.get("name", ""))
	var out: Array = []
	var entries: Array = library.get("entries", [])
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY or not entry.has("id"):
			continue
		var tagged: Dictionary = entry.duplicate(true)
		tagged["_library_name"] = library_name
		tagged["_library_source"] = source
		out.append(tagged)
	return out

func _cache_key(source: Dictionary) -> String:
	var identity: String = String(source.get("url", source.get("path", "")))
	return str(identity.hash())

func _write_cache(source: Dictionary, library: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(CACHE_DIR):
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var path := "%s/%s.json" % [CACHE_DIR, _cache_key(source)]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"fetched_at": Time.get_unix_time_from_system(),
		"source": source,
		"library": library,
	}))

func _load_from_cache() -> void:
	_entries = []
	var sources := ExtensionLibraryManifest.load_configured_sources()
	for source in sources:
		if typeof(source) != TYPE_DICTIONARY:
			continue
		var path := "%s/%s.json" % [CACHE_DIR, _cache_key(source)]
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("library", null)) != TYPE_DICTIONARY:
			continue
		_entries.append_array(_flatten(source, parsed["library"]))
	_has_scanned_this_session = true
