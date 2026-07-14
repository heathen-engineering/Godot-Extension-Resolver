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

## Only one addon's dialog is ever on screen at a time — see resolve()'s
## queueing below. _active_addon_id is "" when nothing is mid-resolution;
## _queue holds {host, addon_id, on_ready} for every resolve() call that
## arrived while another addon's dialog was already up.
var _active_addon_id: String = ""
var _queue: Array = []

## Returns true if addon_id's dependencies are already satisfied (and any
## gating unlock already performed) — caller can proceed immediately,
## synchronously, same as heathen_gate.gd's contract. Returns false if
## resolution isn't complete yet; on_ready is invoked later, possibly after
## a user-confirmed fetch, once it is. host is any Node currently in the
## tree, used only to parent dialogs/HTTPRequests.
##
## Queued, not fanned out: several gems calling resolve() back-to-back
## during editor startup often share a dependency (e.g. every gem depends
## on Game-Framework) — without queueing, each one independently found the
## same issue and popped its own dialog, so resolving Game-Framework once
## in the first dialog still left N-1 redundant "Game-Framework missing"
## dialogs behind it, all for a dependency that was already fixed. The
## already-satisfied fast path below (issues.is_empty()) is deliberately
## NOT gated behind the queue — it never shows UI, so there's no reason to
## make an already-clear addon wait its turn. Only the dialog-needing slow
## path queues, and only behind a DIFFERENT addon's in-flight resolution;
## a retry/recheck for the addon that already owns _active_addon_id must
## still go through immediately, not queue behind itself.
func resolve(host: Node, addon_id: String, on_ready: Callable) -> bool:
	var manifest = ExtensionManifestReader.read_manifest_for(addon_id)
	if manifest == null:
		push_warning("ExtensionResolver: %s has no extension.manifest.json — nothing to check, unlocking directly." % addon_id)
		_finish(null, addon_id, on_ready)
		_drain_queue_if_idle()
		return true

	var issues := _check_dependencies(manifest.get("dependencies", []))
	if issues.is_empty():
		_finish(manifest, addon_id, on_ready)
		_drain_queue_if_idle()
		return true

	if _active_addon_id != "" and _active_addon_id != addon_id:
		_queue.append({"host": host, "addon_id": addon_id, "on_ready": on_ready})
		return false

	_active_addon_id = addon_id
	_show_dialog(host, addon_id, issues, func():
		# Release the lock before re-checking — if this addon's own issues
		# are now resolved, resolve()'s fast path fires _drain_queue_if_idle()
		# itself; if not (recheck failed, fetch failed), resolve() re-shows
		# the dialog and re-acquires _active_addon_id immediately below, so
		# the queue never sees a window where it looks idle mid-retry.
		_active_addon_id = ""
		resolve(host, addon_id, on_ready)
	)
	return false

## Pops the next queued request (if any) and re-runs resolve() for it from
## scratch — deliberately re-checking dependencies rather than assuming
## they're still unmet, since the resolution that just finished may have
## been the exact shared dependency this queued entry was also waiting on,
## in which case it now resolves instantly via the fast path with no
## dialog of its own.
func _drain_queue_if_idle() -> void:
	if _active_addon_id != "" or _queue.is_empty():
		return
	var next: Dictionary = _queue.pop_front()
	resolve(next["host"], next["addon_id"], next["on_ready"])

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
	var has_gdextension := true
	var just_renamed := false

	if not FileAccess.file_exists(real_path):
		if not FileAccess.file_exists(inert_path):
			has_gdextension = false # No .gdextension at all — a pure-GDScript addon.
		else:
			var ok := DirAccess.rename_absolute(
				ProjectSettings.globalize_path(inert_path),
				ProjectSettings.globalize_path(real_path)
			)
			if ok != OK:
				push_error("ExtensionResolver: failed to rename %s -> %s (error %d)." % [inert_path, real_path, ok])
				has_gdextension = false
			else:
				just_renamed = true

	if has_gdextension:
		var mgr = Engine.get_singleton("GDExtensionManager") if Engine.has_singleton("GDExtensionManager") else null
		if mgr != null and not mgr.is_extension_loaded(real_path):
			mgr.load_extension(real_path)

		# Only scan when a .gdextension.available -> .gdextension rename just
		# happened — that's the only case where the filesystem actually
		# changed. Firing this unconditionally on every self-resolution fast
		# path (i.e. once per gem, every boot, even when nothing changed) was
		# producing overlapping/concurrent filesystem-thread scans; see
		# _ensure_plugin_enabled()'s doc comment for the related
		# duplicate-activation bug this was compounding.
		if just_renamed and Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().call_deferred("scan")

## A dependency fetched automatically (as opposed to an addon the user directly enabled via
## Project Settings > Plugins) never gets its own plugin.cfg enabled by anything else in this
## flow — confirmed against a real cold-install test: Game-Framework's native .gdextension
## loaded and SubsystemManagerBridge worked immediately after being pulled in as a dependency,
## but FoundationGameFrameworkEditorPlugin.gd's _enter_tree() (which is what actually builds
## the Subsystems settings tab) never ran, so the tab silently never appeared until manually
## enabled.
##
## Only ever called from _fetch_one() for a dependency that was just fetched this session —
## NOT for the addon resolving itself (that used to run from _ensure_gdextension_loaded(),
## called from both _finish()'s self-resolution path and _fetch_one()'s dependency-fetch path).
## For the self-resolution case, Godot is already mid-activation of that exact plugin — that's
## *why* its gate fired from _enter_tree() in the first place — and calling
## EditorInterface.set_plugin_enabled() on a plugin Godot is already enabling produced
## "Condition p_enabled && addon_name_to_plugin.has(addon_path)" errors, one of which (Ogham,
## the one gem with a floating EditorDock) visibly manifested as a duplicate dock entry. Deferred
## for the same re-entrancy reason the scan() call above uses.
func _ensure_plugin_enabled(addon_id: String) -> void:
	var plugin_cfg_path := "res://addons/%s/plugin.cfg" % addon_id
	if not FileAccess.file_exists(plugin_cfg_path):
		return # No EditorPlugin of its own — e.g. a pure runtime/library dependency.

	var enabled: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	if enabled.has(plugin_cfg_path):
		return # Already enabled, nothing to do.

	EditorInterface.set_plugin_enabled(addon_id, true)

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

	# Only for a freshly-fetched dependency, never for the addon resolving
	# itself — see _ensure_plugin_enabled()'s doc comment.
	if Engine.is_editor_hint():
		call_deferred("_ensure_plugin_enabled", id)
	return true
