@tool
class_name ExtensionResolverSettingsTab
extends VBoxContainer

## The "Extension Resolver" Project Settings tab — its own top-level tab,
## deliberately separate from any other addon's tab (e.g. Godot-Game-
## Framework's "Subsystems" tab); this tool has nothing to do with any
## particular addon's runtime concept, it's generic dependency bookkeeping.
##
## Two child tabs, both built from the same ExtensionResolverListPanel
## (list_panel.gd) so they share one look, not two:
## - "In Project": today's addons-already-installed view, fed from
##   ExtensionManifestReader.scan_installed().
## - "Libraries": entries from every added Library (see
##   docs/extensions/04-libraries.md in TheBarrow, docs/library-schema.md
##   here), fed from ExtensionLibraryRegistry. Its own toolbar above the
##   panel carries the "Libraries (N)" button, opening
##   ExtensionLibraryManageWindow to add/edit/remove Library sources.

var _tabs: TabContainer
var _in_project_panel: ExtensionResolverListPanel
var _library_panel: ExtensionResolverListPanel
var _libraries_button: Button
var _refresh_button: Button
var _resolver: ExtensionResolverCore
var _library_registry: ExtensionLibraryRegistry
var _manage_window: ExtensionLibraryManageWindow
var _did_initial_library_scan := false

func _ready() -> void:
	# Reuses the "ExtensionResolver" Engine singleton (registered by
	# ExtensionResolverEditorPlugin.gd) rather than creating a second
	# ExtensionResolverCore instance — ExtensionResolverCore extends Object,
	# not RefCounted (Engine.register_singleton() rejects RefCounted as of
	# this Godot version, confirmed against a real editor warning while
	# building this), so a second instance here would need its own manual
	# free() lifecycle for no benefit over just sharing the one that already
	# exists.
	_resolver = Engine.get_singleton("ExtensionResolver")
	_library_registry = ExtensionLibraryRegistry.new()
	_ensure_built()

func _ensure_built() -> void:
	set_name("Extension Resolver")
	set_h_size_flags(Control.SIZE_EXPAND_FILL)
	set_v_size_flags(Control.SIZE_EXPAND_FILL)
	visibility_changed.connect(_on_visibility_changed)

	_tabs = TabContainer.new()
	_tabs.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	_tabs.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	add_child(_tabs)

	_in_project_panel = ExtensionResolverListPanel.new()
	_in_project_panel.set_name("In Project")
	_in_project_panel.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	_in_project_panel.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	_tabs.add_child(_in_project_panel)
	_in_project_panel.setup(_resolver, Callable(ExtensionManifestReader, "scan_installed"), "in_project")

	var libraries_container := VBoxContainer.new()
	libraries_container.set_name("Libraries")
	libraries_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	libraries_container.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	_tabs.add_child(libraries_container)

	var toolbar := HBoxContainer.new()
	_libraries_button = Button.new()
	_libraries_button.pressed.connect(_on_libraries_button_pressed)
	toolbar.add_child(_libraries_button)

	var spacer := Control.new()
	spacer.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	toolbar.add_child(spacer)

	# Icon button, far right — Button.icon doesn't render in this project's
	# editor build (see feedback_godot_button_icon_broken), so this uses a
	# single-glyph text label ("⟳") rather than an ImageTexture, the same
	# workaround reasoning as list_panel.gd's TreeItem status glyphs (that
	# one goes through TreeItem.set_icon() instead, since that mechanism
	# does render — a plain toolbar Button has no TreeItem to hang an icon
	# off, so text is the simplest thing confirmed to actually paint here).
	_refresh_button = Button.new()
	_refresh_button.text = "⟳"
	_refresh_button.tooltip_text = "Refresh Libraries — re-fetches every configured Library now."
	_refresh_button.pressed.connect(_on_refresh_button_pressed)
	toolbar.add_child(_refresh_button)

	libraries_container.add_child(toolbar)

	_library_panel = ExtensionResolverListPanel.new()
	_library_panel.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	_library_panel.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	libraries_container.add_child(_library_panel)
	_library_panel.setup(_resolver, Callable(self, "_get_library_items"), "libraries", true, Callable(self, "_install_library_entry"))

	_tabs.tab_changed.connect(_on_tab_changed)
	_update_libraries_button_text()

func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		return
	_in_project_panel.refresh()
	_library_panel.refresh()
	_update_libraries_button_text()

	# "Scanning happens when the window is first opened" (settled in
	# docs/extensions/04-libraries.md) — this is that first-open moment,
	# once per session. Every subsequent tab/panel refresh reads whatever
	# refresh_all() last populated (or the on-disk cache from a previous
	# session), never hitting the network again on its own — only this
	# first-open scan and the explicit Refresh button ever do.
	if not _did_initial_library_scan:
		_did_initial_library_scan = true
		await _refresh_libraries()

func _on_tab_changed(_tab: int) -> void:
	# Switching tabs never re-scans the network — both calls here just
	# reread already-known state (disk for In Project, the registry's
	# in-memory/cached entries for Libraries) so a change made from one tab
	# (e.g. installing something from Libraries) is reflected the moment you
	# look at the other, not left stale until some unrelated refresh fires.
	_in_project_panel.refresh()
	_library_panel.refresh()

## A network fetch with literally nothing visible changing until it's done
## (button just goes disabled, easy to miss) reads as "did that even do
## anything?" — this popup is purely to give a refresh some on-screen
## presence for however long it takes, not because there's any user
## decision to make; it has no buttons of its own and closes itself the
## moment refresh_all() resolves.
func _refresh_libraries() -> void:
	_refresh_button.disabled = true

	var progress := AcceptDialog.new()
	progress.title = "Libraries"
	progress.dialog_hide_on_ok = false
	progress.get_ok_button().visible = false
	var label := Label.new()
	label.text = "Refreshing Libraries..."
	progress.add_child(label)
	if Engine.is_editor_hint():
		EditorInterface.get_base_control().add_child(progress)
	else:
		add_child(progress)
	progress.popup_centered(Vector2i(260, 90))

	await _library_registry.refresh_all(self)

	progress.hide()
	progress.queue_free()
	_refresh_button.disabled = false
	_library_panel.refresh()
	_update_libraries_button_text()

func _on_refresh_button_pressed() -> void:
	await _refresh_libraries()

## Called by ExtensionResolverListPanel's data-provider Callable for the
## Libraries tab — reshapes the registry's flat entry list into the same
## id -> manifest-shaped Dictionary grouping the tree-building code already
## expects (identical shape to ExtensionManifestReader.scan_installed()).
func _get_library_items() -> Dictionary:
	var items := {}
	for entry in _library_registry.get_all_entries():
		var id: String = String(entry.get("id", ""))
		if not id.is_empty():
			items[id] = entry
	return items

## Called by ExtensionResolverListPanel's Install button for a not-yet-
## installed Libraries row — see library_registry.gd's install_entry() doc
## comment for why this is just _fetch_one() under a different trigger.
## Refreshes In Project too, not just the Libraries panel the button lives
## on — installing something is exactly the kind of change In Project needs
## to reflect immediately, not only whenever the user next happens to switch
## tabs (_on_tab_changed() is a second, general-purpose safety net for that,
## not the only path).
func _install_library_entry(_id: String, entry: Dictionary) -> bool:
	var ok: bool = await _library_registry.install_entry(self, _resolver, entry)
	if ok:
		_in_project_panel.refresh()
	return ok

func _update_libraries_button_text() -> void:
	var count := ExtensionLibraryManifest.load_configured_sources().size()
	_libraries_button.text = "Libraries (%d)" % count

func _on_libraries_button_pressed() -> void:
	if _manage_window == null:
		_manage_window = ExtensionLibraryManageWindow.new()
		add_child(_manage_window)
	_manage_window.open(self, _library_registry, func():
		_update_libraries_button_text()
		_library_panel.refresh()
	)
