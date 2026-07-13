@tool
class_name ExtensionResolverCore
extends Object

## The orchestration core registered as the "ExtensionResolver" Engine
## singleton (see ExtensionResolverEditorPlugin.gd) — the one entry point
## every gem's gate stub calls, via
## Engine.get_singleton("ExtensionResolver").resolve(...). Deliberately
## mirrors heathen_gate.gd's existing
## ensure_unlocked(host, addon_id, on_unlocked) -> bool contract so it's a
## drop-in replacement at each gem's one-line _enter_tree() call site, just
## with real version checking instead of presence-only checking.
##
## Unlike heathen_gate.gd (which has to stay copy-pasted and dependency-free
## because it might be checking whether ITS OWN addon's dependencies are
## met), this class can freely reference ExtensionManifestReader/
## ExtensionSemver/ExtensionSourceGithubRelease — they all ship together as
## one addon, so there's no bootstrapping ordering problem here.

const GATED_UNLOCK_SUFFIX := ".gdextension"

## Returns true if addon_id's dependencies are already satisfied (and any
## gating unlock already performed) — caller can proceed immediately,
## synchronously, same as heathen_gate.gd's contract. Returns false if
## resolution isn't complete yet; on_ready is invoked later, possibly after
## a user-confirmed fetch, once it is. host is any Node currently in the
## tree, used only to parent dialogs/HTTPRequests.
func resolve(host: Node, addon_id: String, on_ready: Callable) -> bool:
	var manifest = ExtensionManifestReader.read_manifest_for(addon_id)
	if manifest == null:
		push_warning("ExtensionResolver: %s has no extension.manifest.json — nothing to check, unlocking directly." % addon_id)
		_finish(null, addon_id, on_ready)
		return true

	var issues := _check_dependencies(manifest.get("dependencies", []))
	if issues.is_empty():
		_finish(manifest, addon_id, on_ready)
		return true

	_show_dialog(host, addon_id, issues, func():
		resolve(host, addon_id, on_ready)
	)
	return false

## Dictionary per dependency currently missing or out of range:
## { id, reason ("missing"/"version"), installed_version, min_version,
##   max_version, source }. Empty array means every declared dependency is
## present and version-satisfying.
func _check_dependencies(dependencies: Array) -> Array:
	var issues: Array = []
	for dep in dependencies:
		if typeof(dep) != TYPE_DICTIONARY or not dep.has("id"):
			continue
		var dep_id: String = dep["id"]
		var dep_manifest = ExtensionManifestReader.read_manifest_for(dep_id)
		var min_version: String = dep.get("min_version", "")
		var max_version: String = dep.get("max_version", "")

		if dep_manifest == null:
			issues.append({
				"id": dep_id, "reason": "missing", "installed_version": "",
				"min_version": min_version, "max_version": max_version,
				"source": dep.get("source", {}),
			})
			continue

		var installed_version: String = dep_manifest.get("version", "")
		if not ExtensionSemver.satisfies(installed_version, min_version, max_version):
			issues.append({
				"id": dep_id, "reason": "version", "installed_version": installed_version,
				"min_version": min_version, "max_version": max_version,
				"source": dep.get("source", {}),
			})

	return issues

func _finish(manifest: Variant, addon_id: String, on_ready: Callable) -> void:
	if manifest != null:
		_ensure_gdextension_loaded(addon_id)
	on_ready.call()

## Makes sure addon_id's own native library, if it has one, is actually
## loaded in the running process — renaming <id>.gdextension.available ->
## <id>.gdextension first if it's still gated/inert. Handles three cases:
## pure-GDScript addons (no .gdextension at all — no-op), gated addons
## (rename + load), and already-ungated addons whose .gdextension is real
## but genuinely not yet loaded this session (load only, no rename).
##
## That third case is the one a real cold-install test caught this
## session that isn't obvious from the gating story alone: fetching a
## *dependency* only ever wrote its files to disk — nothing loaded the
## dependency's own native library into the process, since _unlock() (this
## method's earlier, narrower form) only ever ran for the addon actually
## being resolved, and only when it was itself gated. An ungated dependency
## like Game-Framework (ships a real .gdextension directly, nothing to
## rename) was never loaded at all after being fetched, so a freshly-loaded
## *dependent*'s native library failed to dlopen it — "cannot open shared
## object file", even though the file plainly existed on disk. Every
## fetched dependency now goes through this same method (see _fetch_one()),
## not just the resolve() target.
func _ensure_gdextension_loaded(addon_id: String) -> void:
	var addon_dir := "res://addons/%s" % addon_id
	var real_path := "%s/%s%s" % [addon_dir, addon_id, GATED_UNLOCK_SUFFIX]
	var inert_path := "%s.available" % real_path

	if not FileAccess.file_exists(real_path):
		if not FileAccess.file_exists(inert_path):
			return # No .gdextension at all — a pure-GDScript addon, nothing to load.

		var ok := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(inert_path),
			ProjectSettings.globalize_path(real_path)
		)
		if ok != OK:
			push_error("ExtensionResolver: failed to rename %s -> %s (error %d)." % [inert_path, real_path, ok])
			return

	var mgr = Engine.get_singleton("GDExtensionManager") if Engine.has_singleton("GDExtensionManager") else null
	if mgr != null and not mgr.is_extension_loaded(real_path):
		mgr.load_extension(real_path)

	# Deferred for the same re-entrancy reason documented in
	# heathen_gate.gd's original _unlock(): triggering a full filesystem
	# rescan from inside another plugin's still-running _enter_tree()
	# re-enters Godot's own plugin-activation bookkeeping for that plugin.
	# load_extension() above already makes everything usable in this
	# session regardless of whether this runs.
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().call_deferred("scan")

## ── Confirm-and-fetch dialog ─────────────────────────────────────────────
## Never fetches automatically — every action here requires the explicit
## "Fetch/Update All" click, same safety posture as
## HeathenDependencyFetcher/heathen_gate.gd today.

func _show_dialog(host: Node, addon_id: String, issues: Array, retry: Callable) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "%s — Dependencies" % addon_id
	dialog.dialog_hide_on_ok = false

	var vbox := VBoxContainer.new()
	var label := Label.new()
	var lines: PackedStringArray = []
	for issue in issues:
		if issue["reason"] == "missing":
			lines.append("- %s (not installed)" % issue["id"])
		else:
			lines.append("- %s (installed %s, needs >= %s)" % [issue["id"], issue["installed_version"], issue["min_version"]])
	label.text = (
		"%s needs the following:\n\n%s\n\n" % [addon_id, "\n".join(lines)]
		+ "Fetch/update them automatically from their declared source, or resolve them "
		+ "yourself and press Recheck."
	)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size = Vector2(420, 0)
	vbox.add_child(label)

	var status_label := Label.new()
	vbox.add_child(status_label)
	dialog.add_child(vbox)

	var fetch_button := dialog.add_button("Fetch/Update All", true, "fetch")
	var recheck_button := dialog.add_button("Recheck", false, "recheck")

	dialog.custom_action.connect(func(action: StringName):
		if action == "fetch":
			fetch_button.disabled = true
			recheck_button.disabled = true
			await _fetch_all(host, issues, status_label)
			dialog.hide()
			retry.call()
		elif action == "recheck":
			dialog.hide()
			retry.call()
	)

	if Engine.is_editor_hint():
		EditorInterface.get_base_control().add_child(dialog)
	else:
		host.add_child(dialog)
	dialog.popup_centered(Vector2i(480, 360))

func _fetch_all(host: Node, issues: Array, status_label: Label) -> void:
	for issue in issues:
		status_label.text = "Fetching %s..." % issue["id"]
		var ok := await _fetch_one(host, issue)
		if not ok:
			status_label.text = "Failed to fetch %s — install it manually." % issue["id"]

func _fetch_one(host: Node, issue: Dictionary) -> bool:
	var source: Dictionary = issue.get("source", {})
	var repo: String = source.get("repo", "")
	var id: String = issue["id"]
	if repo.is_empty() or id.is_empty():
		return false

	var err: Array = [""]
	# Always targets "latest" for now — explicit version-targeting is a
	# Settings-tab UI concern (Phase 2 of the build plan), layered on top of
	# fetch_release()'s already-supported explicit-tag parameter, not a gap
	# in this method.
	var release = await ExtensionSourceGithubRelease.fetch_release(host, repo, "latest", err)
	if release == null:
		return false

	var url := ExtensionSourceGithubRelease.select_asset_url(release, id, source.get("asset_pattern", ""))
	if url.is_empty():
		return false

	var ok := await ExtensionSourceGithubRelease.fetch_and_extract(host, url, id, err)
	if not ok:
		return false

	# See _ensure_gdextension_loaded()'s doc comment — a freshly-fetched
	# dependency's own native library (if it has one) needs to actually be
	# loaded into the process, not just extracted to disk, or a dependent
	# fetched later in this same chain fails to dlopen it.
	_ensure_gdextension_loaded(id)
	return true
