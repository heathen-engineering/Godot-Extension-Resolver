@tool
class_name ExtensionResolverListPanel
extends HSplitContainer

## The publisher-grouped Tree + detail pane originally built directly inside
## ExtensionResolverSettingsTab, extracted so the "Libraries" tab can reuse
## the exact same look/behavior instead of inventing a second pattern — the
## user's own request when this tab grew a second view. Two instances exist:
## one fed from installed addons (In Project), one fed from Library Entries
## (Libraries). setup() is what tells a given instance which data source and
## action set it is.
##
## Trust model (settled in docs/extensions/04-libraries.md): an installed
## addon's own extension.manifest.json is always authoritative once it's on
## disk. So even inside the Libraries panel, if get_items() surfaces an id
## that's actually installed, the detail pane shows THAT manifest (Update/
## Remove, identical to In Project), not the Library Entry's own summarized
## fields — a Library Entry is display-only right up until install.

const COL_STATUS := 0
const COL_NAME := 1
const COL_VERSION := 2

const GLYPH_SIZE := 12

var _tree_panel: PanelContainer
var _tree: Tree
var _detail: VBoxContainer
var _detail_scroll: ScrollContainer
var _detail_content: VBoxContainer
var _detail_buttons: HBoxContainer
var _resolver: ExtensionResolverCore

var _setting_tree_width: String
var _setting_last_selected: String
var _get_items: Callable   # () -> Dictionary[String, Dictionary] (id -> manifest-shaped dict)
var _is_library_panel: bool = false
var _install_entry: Callable = Callable() # (id: String, entry: Dictionary) -> bool, only used when _is_library_panel
var _current_items: Dictionary = {}

const DEFAULT_TREE_WIDTH := 280

## resolver: the shared ExtensionResolverCore singleton.
## get_items: Callable, () -> Dictionary[String, Dictionary] — the full set
##   of rows to show right now.
## settings_key: unique per panel instance, so In Project and Libraries
##   remember their own tree width/last-selected independently.
## is_library_panel/install_entry: see class doc comment above.
func setup(resolver: ExtensionResolverCore, get_items: Callable, settings_key: String, is_library_panel: bool = false, install_entry: Callable = Callable()) -> void:
	_resolver = resolver
	_get_items = get_items
	_setting_tree_width = "extension_resolver/tree_panel_width_%s" % settings_key
	_setting_last_selected = "extension_resolver/last_selected_id_%s" % settings_key
	_is_library_panel = is_library_panel
	_install_entry = install_entry
	_ensure_built()

func _ensure_built() -> void:
	set_h_size_flags(Control.SIZE_EXPAND_FILL)
	set_v_size_flags(Control.SIZE_EXPAND_FILL)

	# See ExtensionResolverSettingsTab's original doc comment (this file was
	# extracted from it): PanelContainer + SIZE_FILL + fixed
	# custom_minimum_size on the panel, not the Tree — HSplitContainer's
	# split_offset is measured from its auto-computed center, not its left
	# edge, so sizing must go through custom_minimum_size instead.
	_tree_panel = PanelContainer.new()
	_tree_panel.set_h_size_flags(Control.SIZE_FILL)
	_tree_panel.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0.12)
	panel_style.border_color = Color(0, 0, 0, 0.4)
	panel_style.border_width_right = 2
	panel_style.content_margin_left = 4
	panel_style.content_margin_top = 4
	panel_style.content_margin_bottom = 4
	_tree_panel.add_theme_stylebox_override("panel", panel_style)
	var saved_width: int = int(_get_editor_setting(_setting_tree_width, DEFAULT_TREE_WIDTH))
	_tree_panel.set_custom_minimum_size(Vector2(saved_width if saved_width > 0 else DEFAULT_TREE_WIDTH, 0))
	add_child(_tree_panel)

	_tree = Tree.new()
	_tree.set_hide_root(true)
	_tree.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	_tree.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	_tree.set_columns(3)
	_tree.set_column_titles_visible(false)
	_tree.set_column_expand(COL_STATUS, false)
	_tree.set_column_custom_minimum_width(COL_STATUS, 20)
	_tree.set_column_expand(COL_NAME, true)
	_tree.set_column_custom_minimum_width(COL_NAME, 120)
	_tree.set_column_expand(COL_VERSION, false)
	_tree.set_column_custom_minimum_width(COL_VERSION, 70)
	_tree.item_selected.connect(_on_item_selected)
	_tree_panel.add_child(_tree)
	dragged.connect(_on_split_dragged)

	_detail = VBoxContainer.new()
	_detail.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	_detail.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	add_child(_detail)

	_detail_scroll = ScrollContainer.new()
	_detail_scroll.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	_detail_scroll.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	_detail.add_child(_detail_scroll)

	_detail_content = VBoxContainer.new()
	_detail_content.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	_detail_scroll.add_child(_detail_content)

	_detail_buttons = HBoxContainer.new()
	_detail.add_child(_detail_buttons)

	_show_placeholder("Select an extension on the left to view its details.")
	refresh()

func _on_split_dragged(_offset: int) -> void:
	_set_editor_setting(_setting_tree_width, int(_tree_panel.get_size().x))

func refresh() -> void:
	if _tree == null:
		return

	_current_items = _get_items.call()

	var previously_selected := _tree.get_selected()
	var reselect_id: String = String(previously_selected.get_metadata(COL_NAME)) if previously_selected != null and previously_selected.get_metadata(COL_NAME) != null else String(_get_editor_setting(_setting_last_selected, ""))

	_tree.clear()
	var root := _tree.create_item()
	var to_select: TreeItem = null
	var first_item: TreeItem = null

	# Grouped by publisher — UPM-style. Rows with no publisher.name fall back
	# to one shared "Unknown Publisher" bucket rather than erroring.
	var by_publisher: Dictionary = {}
	for id in _current_items.keys():
		var manifest: Dictionary = _current_items[id]
		var publisher: Variant = manifest.get("publisher", {})
		var publisher_name: String = String(publisher.get("name", "")) if typeof(publisher) == TYPE_DICTIONARY else ""
		if publisher_name.is_empty():
			publisher_name = "Unknown Publisher"
		if not by_publisher.has(publisher_name):
			by_publisher[publisher_name] = []
		(by_publisher[publisher_name] as Array).append(id)

	var publisher_names := by_publisher.keys()
	publisher_names.sort()
	for publisher_name in publisher_names:
		var group_item := _tree.create_item(root)
		group_item.set_text(COL_NAME, publisher_name)
		group_item.set_selectable(COL_STATUS, false)
		group_item.set_selectable(COL_NAME, false)
		group_item.set_selectable(COL_VERSION, false)
		group_item.set_custom_color(COL_NAME, Color(0.6, 0.6, 0.6))
		group_item.set_collapsed(false) # default expanded, per spec

		var member_ids: Array = by_publisher[publisher_name]
		member_ids.sort()
		for id in member_ids:
			var manifest: Dictionary = _current_items[id]
			var item := _tree.create_item(group_item)
			var issues := _resolver._check_dependencies(manifest.get("dependencies", []))
			item.set_icon(COL_STATUS, _status_icon(issues))
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
		_set_editor_setting(_setting_last_selected, String(to_select.get_metadata(COL_NAME)))
	elif _is_library_panel:
		_show_placeholder("No Libraries added yet, or nothing in them to show.")
	else:
		_show_placeholder("No extensions with an extension.manifest.json are installed yet.")

func _on_item_selected() -> void:
	var selected := _tree.get_selected()
	if selected == null or selected.get_metadata(COL_NAME) == null:
		return # a publisher-group header row — not selectable, but guard anyway
	var id: String = String(selected.get_metadata(COL_NAME))
	_show_detail_for(id)
	_set_editor_setting(_setting_last_selected, id)

## ── Status glyphs ────────────────────────────────────────────────────────
## Small solid-color glyph bitmaps generated procedurally rather than
## hand-authored pixel art (easier to verify correct than an ASCII-art
## mask). Godot's Button.icon doesn't render in this project's editor build
## (see feedback_godot_button_icon_broken) — every glyph here goes through
## TreeItem.set_icon(), the same mechanism the original flat-color status
## square used, confirmed to render correctly. Not cached in a static
## Ref<ImageTexture> for the same reason the original wasn't — a static ref
## can outlive RenderingServer's own teardown and crash on destruction.

static func _new_glyph_image() -> Image:
	var img := Image.create(GLYPH_SIZE, GLYPH_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img

## Isoceles triangle, apex pointing up — used for the warning glyph.
static func _fill_triangle_up(img: Image, color: Color, apex: Vector2i, base_y: int, half_width: int) -> void:
	var height := base_y - apex.y
	if height <= 0:
		return
	for y in range(apex.y, base_y + 1):
		var t := float(y - apex.y) / float(height)
		var half_w := int(round(t * half_width))
		for x in range(apex.x - half_w, apex.x + half_w + 1):
			if x >= 0 and x < GLYPH_SIZE and y >= 0 and y < GLYPH_SIZE:
				img.set_pixel(x, y, color)

## Hand-picked points, not procedural — a checkmark isn't a simple geometric
## primitive the way the triangle glyph is. Each point drawn 2px wide so the
## stroke reads at 12px scale instead of vanishing to single pixels.
static func _plot_checkmark(img: Image, color: Color) -> void:
	var points := [
		Vector2i(1, 6), Vector2i(2, 7), Vector2i(3, 8), Vector2i(4, 9),
		Vector2i(5, 8), Vector2i(6, 7), Vector2i(7, 6), Vector2i(8, 5),
		Vector2i(9, 4), Vector2i(10, 3), Vector2i(10, 2),
	]
	for p in points:
		if p.x >= 0 and p.x < GLYPH_SIZE and p.y >= 0 and p.y < GLYPH_SIZE:
			img.set_pixel(p.x, p.y, color)
		if p.x + 1 < GLYPH_SIZE:
			img.set_pixel(p.x + 1, p.y, color)

## issues empty -> checkmark (Good). issues non-empty -> warning triangle,
## amber for a version-range mismatch, red for a hard-missing dependency —
## same color semantics as the flat squares this replaces, just shaped now.
static func _status_icon(issues: Array) -> ImageTexture:
	var img := _new_glyph_image()
	if issues.is_empty():
		_plot_checkmark(img, Color(0.30, 0.72, 0.35))
	else:
		var hard_missing := false
		for issue in issues:
			if issue.get("reason", "") == "missing":
				hard_missing = true
				break
		var color := Color(0.85, 0.32, 0.32) if hard_missing else Color(1.0, 0.72, 0.10)
		_fill_triangle_up(img, color, Vector2i(6, 1), 10, 5)
	return ImageTexture.create_from_image(img)

## ── Detail pane ──────────────────────────────────────────────────────────

func _clear_detail_content() -> void:
	for child in _detail_content.get_children():
		child.queue_free()
	for child in _detail_buttons.get_children():
		child.queue_free()

func _show_placeholder(text: String) -> void:
	_clear_detail_content()
	var label := Label.new()
	label.text = text
	_detail_content.add_child(label)

## Converts just the `[text](url)` Markdown link subset to BBCode
## `[url=...]text[/url]` — not a full Markdown parser, RichTextLabel only
## understands BBCode natively and a real MD renderer is out of scope for
## what publishers actually need here (a short blurb with a couple of
## hyperlinks, e.g. to Patreon/Sponsorship).
static func _markdown_links_to_bbcode(text: String) -> String:
	var re := RegEx.new()
	re.compile("\\[([^\\]]+)\\]\\(([^)]+)\\)")
	return re.sub(text, "[url=$2]$1[/url]", true)

## installed_manifest != null whenever id currently exists on disk with its
## own extension.manifest.json — true for every In Project row always, and
## true for a Libraries row whose entry has already been installed. In that
## case the *installed* manifest is what renders (trust model: it's the only
## authoritative source once on disk), with Update/Remove actions. A
## Libraries row for something not yet installed renders from its Library
## Entry data instead, with an Install action.
func _show_detail_for(id: String) -> void:
	_clear_detail_content()
	var installed_manifest = ExtensionManifestReader.read_manifest_for(id)
	if installed_manifest != null:
		_render_detail(id, installed_manifest, true)
		return

	if not _is_library_panel:
		_show_placeholder("%s has no extension.manifest.json." % id)
		return

	var entry: Dictionary = _current_items.get(id, {})
	if entry.is_empty():
		_show_placeholder("No data for %s." % id)
		return
	_render_detail(id, entry, false)

func _render_detail(id: String, manifest: Dictionary, is_installed: bool) -> void:
	var title := Label.new()
	var version_text: String = String(manifest.get("version", "")) if is_installed else "latest"
	title.text = "%s  (%s)" % [manifest.get("display_name", id), version_text]
	title.add_theme_font_size_override("font_size", 18)
	_detail_content.add_child(title)

	var publisher: Variant = manifest.get("publisher", {})
	if typeof(publisher) == TYPE_DICTIONARY and not String(publisher.get("name", "")).is_empty():
		var publisher_row := HBoxContainer.new()
		var by_label := Label.new()
		by_label.text = "by "
		publisher_row.add_child(by_label)
		var publisher_url: String = String(publisher.get("url", ""))
		if publisher_url.is_empty():
			var name_label := Label.new()
			name_label.text = String(publisher["name"])
			publisher_row.add_child(name_label)
		else:
			var publisher_link := LinkButton.new()
			publisher_link.text = String(publisher["name"])
			publisher_link.uri = publisher_url
			publisher_row.add_child(publisher_link)
		_detail_content.add_child(publisher_row)

	var description: String = String(manifest.get("description", ""))
	if not description.is_empty():
		var desc_label := RichTextLabel.new()
		desc_label.bbcode_enabled = true
		desc_label.fit_content = true
		desc_label.scroll_active = false
		desc_label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		desc_label.text = _markdown_links_to_bbcode(description)
		_detail_content.add_child(desc_label)

	var repo_url: String = manifest.get("repository_url", "")
	if not repo_url.is_empty():
		var link := LinkButton.new()
		link.text = repo_url
		link.uri = repo_url
		_detail_content.add_child(link)

	# Standard links row — Documentation / Support / License — only the
	# ones the manifest/entry actually provides.
	var standard_links := {
		"Documentation": String(manifest.get("documentation_url", "")),
		"Support": String(manifest.get("support_url", "")),
		"License": String(manifest.get("license_url", "")),
	}
	var has_any_standard_link := false
	for url in standard_links.values():
		if not url.is_empty():
			has_any_standard_link = true
			break
	if has_any_standard_link:
		var links_row := HBoxContainer.new()
		for link_label in standard_links:
			var url: String = standard_links[link_label]
			if url.is_empty():
				continue
			var link_button := LinkButton.new()
			link_button.text = link_label
			link_button.uri = url
			links_row.add_child(link_button)
		_detail_content.add_child(links_row)

	_detail_content.add_child(HSeparator.new())

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
	_detail_content.add_child(deps_label)

	if is_installed and not issues.is_empty():
		var resolve_button := Button.new()
		resolve_button.text = "Resolve Dependencies"
		resolve_button.pressed.connect(func():
			_resolver.resolve(self, id, func(): refresh())
		)
		_detail_content.add_child(resolve_button)

	var status_label := Label.new()
	status_label.text = ""
	_detail_content.add_child(status_label)

	if not is_installed:
		var install_button := Button.new()
		install_button.text = "Install"
		install_button.pressed.connect(func():
			install_button.disabled = true
			status_label.text = "Installing..."
			var ok: bool = await _install_entry.call(id, manifest)
			install_button.disabled = false
			if ok:
				status_label.text = "Installed."
				refresh()
			else:
				status_label.text = "Failed to install %s." % id
		)
		_detail_buttons.add_child(install_button)
		return

	# Buttons pinned to the bottom of the panel (_detail_buttons is a
	# sibling of the scrolling _detail_scroll, not inside it — see
	# _ensure_built()).
	var check_update_button := Button.new()
	check_update_button.text = "Update"
	var source: Dictionary = manifest.get("source", {})
	check_update_button.disabled = source.get("repo", "") == ""
	check_update_button.pressed.connect(func():
		check_update_button.disabled = true
		status_label.text = "Checking..."
		var err: Array = [""]
		var repo: String = source.get("repo", "")
		var release = await ExtensionSourceGithubRelease.fetch_release(self, repo, "latest", err)
		if release == null:
			check_update_button.disabled = false
			status_label.text = "Could not check for updates: %s" % err[0]
			return
		var latest_version: String = String(release.get("tag_name", "")).trim_prefix("v")
		var installed_version: String = manifest.get("version", "")
		if ExtensionSemver.compare(latest_version, installed_version) <= 0:
			check_update_button.disabled = false
			status_label.text = "Already up to date (%s)." % installed_version
			return

		status_label.text = "Updating %s -> %s..." % [installed_version, latest_version]
		var url := ExtensionSourceGithubRelease.select_asset_url(release, id, source.get("asset_pattern", ""))
		if url.is_empty():
			check_update_button.disabled = false
			status_label.text = "Update available (%s) but no matching release asset found." % latest_version
			return
		var ok := await ExtensionSourceGithubRelease.fetch_and_extract(self, url, id, err)
		check_update_button.disabled = false
		if not ok:
			status_label.text = "Failed to update: %s" % err[0]
			return
		_resolver._ensure_gdextension_loaded(id)
		status_label.text = "Updated to %s." % latest_version
		refresh()
	)
	_detail_buttons.add_child(check_update_button)

	var remove_button := Button.new()
	remove_button.text = "Remove"
	remove_button.pressed.connect(func(): _on_remove_pressed(id))
	_detail_buttons.add_child(remove_button)

## ── Remove ───────────────────────────────────────────────────────────────

func _find_dependents(id: String) -> Array:
	var dependents: Array = []
	var installed: Dictionary = ExtensionManifestReader.scan_installed()
	for other_id in installed:
		if other_id == id:
			continue
		var deps: Array = installed[other_id].get("dependencies", [])
		for dep in deps:
			if typeof(dep) == TYPE_DICTIONARY and String(dep.get("id", "")) == id:
				dependents.append(other_id)
				break
	return dependents

func _on_remove_pressed(id: String) -> void:
	var dependents := _find_dependents(id)
	var confirm := ConfirmationDialog.new()
	confirm.title = "Remove %s?" % id
	var message := "This will delete res://addons/%s and disable its plugin.\n\n" % id
	if dependents.is_empty():
		message += "Nothing else installed depends on it."
	else:
		message += "The following installed extensions depend on it and will likely break:\n- " + "\n- ".join(dependents)
	confirm.dialog_text = message
	confirm.confirmed.connect(func(): _do_remove(id))
	if Engine.is_editor_hint():
		EditorInterface.get_base_control().add_child(confirm)
	else:
		add_child(confirm)
	confirm.popup_centered(Vector2i(420, 220))

func _do_remove(id: String) -> void:
	var plugin_cfg_path := "res://addons/%s/plugin.cfg" % id
	if Engine.is_editor_hint() and FileAccess.file_exists(plugin_cfg_path):
		EditorInterface.set_plugin_enabled(id, false)
	_remove_dir_recursive(ProjectSettings.globalize_path("res://addons/%s" % id))
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().call_deferred("scan")
	refresh()

## DirAccess has no built-in recursive delete — walks and removes children
## before removing the now-empty directory itself.
static func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full := path.path_join(entry)
			if dir.current_is_dir():
				_remove_dir_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

## ── EditorSettings persistence ──────────────────────────────────────────

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
