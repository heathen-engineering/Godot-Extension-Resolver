@tool
class_name ExtensionResolverSettingsTab
extends VBoxContainer

## The "Extension Resolver" Project Settings tab — its own top-level tab,
## deliberately separate from any other addon's tab (e.g. Godot-Game-
## Framework's "Subsystems" tab); this tool has nothing to do with any
## particular addon's runtime concept, it's generic dependency bookkeeping.
##
## Layout carries forward two concrete lessons from building
## SubsystemsSettingsTab (Godot-Game-Framework, C++) this same session:
## 1. The list side is SIZE_FILL (not EXPAND_FILL) with a fixed
##    custom_minimum_size, and only the detail pane expands — deliberately
##    NOT using HSplitContainer.split_offset to size it. That property is
##    measured from the container's auto-computed center, not its left
##    edge, and cost real time to root-cause on the C++ side of this same
##    session's work.
## 2. Last-selected row and any user-dragged panel width persist via
##    EditorSettings (per-user editor state), not ProjectSettings.

const SETTING_TREE_WIDTH := "extension_resolver/tree_panel_width"
const SETTING_LAST_SELECTED := "extension_resolver/last_selected_id"
const DEFAULT_TREE_WIDTH := 220

const COL_STATUS := 0
const COL_NAME := 1
const COL_VERSION := 2

var _split: HSplitContainer
var _tree: Tree
var _detail: VBoxContainer
var _resolver: ExtensionResolverCore

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
	_ensure_built()

func _ensure_built() -> void:
	set_name("Extension Resolver")
	set_h_size_flags(Control.SIZE_EXPAND_FILL)
	set_v_size_flags(Control.SIZE_EXPAND_FILL)
	visibility_changed.connect(_on_visibility_changed)

	_split = HSplitContainer.new()
	_split.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	_split.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	add_child(_split)

	_tree = Tree.new()
	_tree.set_hide_root(true)
	_tree.set_h_size_flags(Control.SIZE_FILL)
	_tree.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	var saved_width: int = int(_get_editor_setting(SETTING_TREE_WIDTH, DEFAULT_TREE_WIDTH))
	_tree.set_custom_minimum_size(Vector2(saved_width if saved_width > 0 else DEFAULT_TREE_WIDTH, 0))
	_tree.set_columns(3)
	_tree.set_column_titles_visible(false)
	_tree.set_column_expand(COL_STATUS, false)
	_tree.set_column_custom_minimum_width(COL_STATUS, 20)
	_tree.set_column_expand(COL_NAME, true)
	_tree.set_column_custom_minimum_width(COL_NAME, 120)
	_tree.set_column_expand(COL_VERSION, false)
	_tree.set_column_custom_minimum_width(COL_VERSION, 70)
	_tree.item_selected.connect(_on_item_selected)
	_split.add_child(_tree)
	_split.dragged.connect(_on_split_dragged)

	_detail = VBoxContainer.new()
	_detail.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	_detail.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	_split.add_child(_detail)
	_show_placeholder("Select an extension on the left to view its details.")

	refresh()

func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		refresh()

func _on_split_dragged(_offset: int) -> void:
	_set_editor_setting(SETTING_TREE_WIDTH, int(_tree.get_size().x))

func refresh() -> void:
	if _tree == null:
		return

	var previously_selected := _tree.get_selected()
	var reselect_id: String = previously_selected.get_text(COL_NAME) if previously_selected != null else String(_get_editor_setting(SETTING_LAST_SELECTED, ""))

	_tree.clear()
	var root := _tree.create_item()
	var installed: Dictionary = ExtensionManifestReader.scan_installed()
	var to_select: TreeItem = null
	var first_item: TreeItem = null

	var ids := installed.keys()
	ids.sort()
	for id in ids:
		var manifest: Dictionary = installed[id]
		var item := _tree.create_item(root)
		var issues := _resolver._check_dependencies(manifest.get("dependencies", []))
		item.set_icon(COL_STATUS, _status_icon(_status_color(issues)))
		item.set_text(COL_NAME, String(manifest.get("display_name", id)))
		item.set_metadata(COL_NAME, id)
		item.set_text(COL_VERSION, String(manifest.get("version", "")))

		if first_item == null:
			first_item = item
		if id == reselect_id:
			to_select = item

	if to_select == null:
		to_select = first_item

	if to_select != null:
		to_select.select(COL_NAME)
		_show_detail_for(String(to_select.get_metadata(COL_NAME)))
		_set_editor_setting(SETTING_LAST_SELECTED, String(to_select.get_metadata(COL_NAME)))
	else:
		_show_placeholder("No extensions with an extension.manifest.json are installed yet.")

func _on_item_selected() -> void:
	var selected := _tree.get_selected()
	if selected == null:
		return
	var id: String = String(selected.get_metadata(COL_NAME))
	_show_detail_for(id)
	_set_editor_setting(SETTING_LAST_SELECTED, id)

func _status_color(issues: Array) -> Color:
	if issues.is_empty():
		return Color(0.30, 0.72, 0.35) # Good/green
	for issue in issues:
		if issue["reason"] == "missing":
			return Color(0.85, 0.32, 0.32) # Error/red — hard-missing dependency
	return Color(1.0, 0.72, 0.10) # NeedsAttention/amber — present but out of range

func _status_icon(color: Color) -> ImageTexture:
	# NOT cached in a static — a static Ref<ImageTexture> across editor
	# sessions can outlive RenderingServer's own teardown and crash on
	# destruction, the same class of bug already hit and documented in this
	# session's SubsystemsSettingsTab (C++) and OghamGraphView work. At most
	# a handful of rows redrawn on an explicit refresh, not a hot path.
	var size := 12
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)

func _clear_detail() -> void:
	for child in _detail.get_children():
		child.queue_free()

func _show_placeholder(text: String) -> void:
	_clear_detail()
	var label := Label.new()
	label.text = text
	label.set_anchors_preset(Control.PRESET_CENTER)
	_detail.add_child(label)

func _show_detail_for(id: String) -> void:
	_clear_detail()
	var manifest = ExtensionManifestReader.read_manifest_for(id)
	if manifest == null:
		_show_placeholder("%s has no extension.manifest.json." % id)
		return

	var title := Label.new()
	title.text = "%s  (%s)" % [manifest.get("display_name", id), manifest.get("version", "?")]
	title.add_theme_font_size_override("font_size", 18)
	_detail.add_child(title)

	var repo_url: String = manifest.get("repository_url", "")
	if not repo_url.is_empty():
		var link := LinkButton.new()
		link.text = repo_url
		link.uri = repo_url
		_detail.add_child(link)

	_detail.add_child(HSeparator.new())

	var issues: Array = _resolver._check_dependencies(manifest.get("dependencies", []))
	var deps_label := Label.new()
	if manifest.get("dependencies", []).is_empty():
		deps_label.text = "No dependencies declared."
	elif issues.is_empty():
		deps_label.text = "All dependencies satisfied."
	else:
		var lines: PackedStringArray = []
		for issue in issues:
			if issue["reason"] == "missing":
				lines.append("- %s: not installed" % issue["id"])
			else:
				lines.append("- %s: installed %s, needs >= %s" % [issue["id"], issue["installed_version"], issue["min_version"]])
		deps_label.text = "Unresolved dependencies:\n" + "\n".join(lines)
	deps_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_detail.add_child(deps_label)

	if not issues.is_empty():
		var resolve_button := Button.new()
		resolve_button.text = "Resolve Dependencies"
		resolve_button.pressed.connect(func():
			_resolver.resolve(self, id, func(): refresh())
		)
		_detail.add_child(resolve_button)

	var update_label := Label.new()
	update_label.text = ""
	_detail.add_child(update_label)

	var check_update_button := Button.new()
	check_update_button.text = "Check for Updates"
	var source: Dictionary = manifest.get("source", {})
	check_update_button.disabled = source.get("repo", "") == ""
	check_update_button.pressed.connect(func():
		check_update_button.disabled = true
		update_label.text = "Checking..."
		var err: Array = [""]
		var release = await ExtensionSourceGithubRelease.fetch_release(self, source.get("repo", ""), "latest", err)
		check_update_button.disabled = false
		if release == null:
			update_label.text = "Could not check for updates: %s" % err[0]
			return
		var latest_version: String = String(release.get("tag_name", "")).trim_prefix("v")
		var installed_version: String = manifest.get("version", "")
		if ExtensionSemver.compare(latest_version, installed_version) > 0:
			update_label.text = "Update available: %s -> %s" % [installed_version, latest_version]
		else:
			update_label.text = "Up to date (%s)." % installed_version
	)
	_detail.add_child(check_update_button)

static func _get_editor_setting(key: String, default_value: Variant) -> Variant:
	if not Engine.is_editor_hint():
		return default_value
	var settings := EditorInterface.get_editor_settings()
	if settings == null or not settings.has_setting(key):
		return default_value
	return settings.get_setting(key)

static func _set_editor_setting(key: String, value: Variant) -> void:
	if not Engine.is_editor_hint():
		return
	var settings := EditorInterface.get_editor_settings()
	if settings == null:
		return
	settings.set_setting(key, value)
