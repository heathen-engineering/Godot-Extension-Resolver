@tool
class_name ExtensionSourceGithubRelease
extends RefCounted

## Implements source.type == "github_release" from the manifest schema (see
## docs/manifest-schema.md) — the only source type this resolver understands
## for v1. Fetches a specific tagged release (not hardcoded to
## /releases/latest the way HeathenDependencyFetcher/heathen_gate.gd both
## are today) so a specific version can be targeted, not just "whatever's
## newest right now".
##
## All network/extract mechanics here are the same approach already proven
## in Godot-Game-Framework's HeathenDependencyFetcher and every gem's
## heathen_gate.gd — HTTPRequest + JSON.parse_string + ZIPReader — just
## generalized past "always latest" and consolidated into one place instead
## of four copy-pasted ones.

const GITHUB_API_ROOT := "https://api.github.com/repos/"

## Fetches release metadata for repo ("owner/name"). version_tag == "" (or
## "latest") fetches the newest published release; any other value fetches
## that exact tag. Returns null (and leaves details in out_error, if given)
## on any failure. host is any Node currently in the tree, used only to
## parent the temporary HTTPRequest node.
static func fetch_release(host: Node, repo: String, version_tag: String = "", out_error: Array = []) -> Variant:
	var path := "%s%s/releases/latest" % [GITHUB_API_ROOT, repo]
	if not version_tag.is_empty() and version_tag != "latest":
		path = "%s%s/releases/tags/%s" % [GITHUB_API_ROOT, repo, version_tag]

	var body := await _get_bytes(host, path, ["Accept: application/vnd.github+json"], out_error)
	if body.is_empty():
		return null

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		if not out_error.is_empty():
			out_error[0] = "GitHub API response for %s was not valid JSON." % repo
		return null
	return parsed

## Lists every published release for repo, newest first — used by the
## Settings tab's "install a specific version" picker (Phase 2), not needed
## for the basic resolve-dependencies flow, which only ever fetches one
## release at a time via fetch_release().
static func list_releases(host: Node, repo: String, out_error: Array = []) -> Array:
	var body := await _get_bytes(host, "%s%s/releases" % [GITHUB_API_ROOT, repo], ["Accept: application/vnd.github+json"], out_error)
	if body.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	return parsed if typeof(parsed) == TYPE_ARRAY else []

## Picks a download URL from a release's assets, per the manifest schema's
## documented fallback order: an explicit asset_pattern (with an optional
## "{version}" placeholder) first; otherwise the release's only asset, if it
## has exactly one; otherwise the first asset whose name starts with id.
## Returns "" if nothing matches.
static func select_asset_url(release: Dictionary, id: String, asset_pattern: String = "") -> String:
	var assets: Array = release.get("assets", [])
	if assets.is_empty():
		return ""

	if not asset_pattern.is_empty():
		var version: String = String(release.get("tag_name", "")).trim_prefix("v")
		var wanted_name := asset_pattern.replace("{version}", version)
		for asset in assets:
			if typeof(asset) == TYPE_DICTIONARY and asset.get("name", "") == wanted_name:
				return asset.get("browser_download_url", "")
		return ""

	if assets.size() == 1 and typeof(assets[0]) == TYPE_DICTIONARY:
		return assets[0].get("browser_download_url", "")

	for asset in assets:
		if typeof(asset) == TYPE_DICTIONARY and String(asset.get("name", "")).begins_with(id):
			return asset.get("browser_download_url", "")

	return ""

## Locates the "<id>/" segment itself within a zip entry's path, rather than
## assuming a fixed nesting depth (e.g. always "strip exactly one leading
## component"), and returns everything after it — "" if dependency_id never
## appears in entry_path at all (a stray entry that isn't part of this
## addon's own folder). Real release zips built by this project's own CI
## (Godot-xxHash/.github/workflows/*.yml's "Package addon" job) are rooted
## two levels deep — "addons/FoundationXxHash/plugin.cfg" — not one
## ("FoundationXxHash/plugin.cfg") the way heathen_gate.gd's own
## strip-first-component logic assumed. That mismatch was never caught
## because nothing exercised the fetch-and-extract path end-to-end before
## this tool existed — searching for the id itself is robust to either
## shape, and to any other prefix a future packaging change might add. Pure
## function, no I/O — see test/test_source_github_release.gd.
static func relative_path_within_id(entry_path: String, dependency_id: String) -> String:
	var marker := "%s/" % dependency_id
	var marker_at := entry_path.find(marker)
	if marker_at == -1:
		return ""
	return entry_path.substr(marker_at + marker.length())

## Downloads and extracts a zip asset into res://addons/<id>/, stripping the
## archive's own root folder the same way HeathenDependencyFetcher/
## heathen_gate.gd both already do (an archive is expected to be rooted at
## "<id>/plugin.cfg", not "plugin.cfg" at the top level).
static func fetch_and_extract(host: Node, download_url: String, id: String, out_error: Array = []) -> bool:
	var zip_bytes := await _get_bytes(host, download_url, PackedStringArray(), out_error)
	if zip_bytes.is_empty():
		return false
	return await _extract_zip(zip_bytes, id, out_error)

static func _get_bytes(host: Node, url: String, headers: PackedStringArray = PackedStringArray(), out_error: Array = []) -> PackedByteArray:
	var http := HTTPRequest.new()
	host.add_child(http)
	var err := http.request(url, headers)
	if err != OK:
		if not out_error.is_empty():
			out_error[0] = "Failed to start request for %s (error %d)." % [url, err]
		http.queue_free()
		return PackedByteArray()

	var result: Array = await http.request_completed
	http.queue_free()

	var response_code: int = result[1]
	var body: PackedByteArray = result[3]
	if response_code != 200:
		if not out_error.is_empty():
			out_error[0] = "Request to %s returned HTTP %d." % [url, response_code]
		return PackedByteArray()
	return body

static func _extract_zip(zip_bytes: PackedByteArray, dependency_id: String, out_error: Array = []) -> bool:
	var tmp_path := "user://%s_resolver_download.zip" % dependency_id
	var tmp_file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if tmp_file == null:
		if not out_error.is_empty():
			out_error[0] = "Could not write temp file %s." % tmp_path
		return false
	tmp_file.store_buffer(zip_bytes)
	tmp_file.close()

	var reader := ZIPReader.new()
	if reader.open(tmp_path) != OK:
		if not out_error.is_empty():
			out_error[0] = "Could not open downloaded archive as a zip."
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
		return false

	var dest_root := "res://addons/%s" % dependency_id
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dest_root)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest_root))

	for entry_path in reader.get_files():
		if entry_path.ends_with("/"):
			continue

		var relative_path := relative_path_within_id(entry_path, dependency_id)
		if relative_path.is_empty():
			continue

		var dest_path := "%s/%s" % [dest_root, relative_path]
		var dest_dir := dest_path.get_base_dir()
		var globalized_dir := ProjectSettings.globalize_path(dest_dir)
		if not DirAccess.dir_exists_absolute(globalized_dir):
			DirAccess.make_dir_recursive_absolute(globalized_dir)

		var out_file := FileAccess.open(dest_path, FileAccess.WRITE)
		if out_file == null:
			if not out_error.is_empty():
				out_error[0] = "Could not write extracted file %s." % dest_path
			reader.close()
			DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
			return false
		out_file.store_buffer(reader.read_file(entry_path))
		out_file.close()

	reader.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
	if Engine.is_editor_hint():
		# scan() only STARTS an async rescan — it doesn't wait for Godot to
		# finish registering any newly-extracted class_name scripts or
		# GDExtension dependencies. A caller that immediately enables a
		# plugin or calls GDExtensionManager.load_extension() right after
		# fetch_and_extract() returns can hit either a "class not found in
		# scope" parse error (global class list not updated yet) or a
		# dynamic-linker "No such file or directory" for a genuinely
		# just-written .gdextension dependency (Godot's own internal
		# dependency-loading appears to go through the same not-yet-
		# refreshed project index) — both confirmed the hard way during a
		# real cold-install test. Awaiting script_classes_updated blocks
		# until that registration has actually happened.
		var fs := EditorInterface.get_resource_filesystem()
		fs.scan()
		await fs.script_classes_updated
	return true
