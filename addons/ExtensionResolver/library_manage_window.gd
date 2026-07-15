@tool
class_name ExtensionLibraryManageWindow
extends Window

## Modal behind the Libraries tab's "Libraries (N)" toolbar button — add,
## view, and remove configured Library sources (res://addon_libraries.json
## via library_manifest.gd), and trigger an on-demand refresh. This is the
## only place (other than the Libraries panel's own first-open-this-session
## load) a scan ever happens — no timer, no file-system watch, matching the
## settled "not a live tool" decision in docs/extensions/04-libraries.md.
##
## Lazy-built on first open() call, same contract (not the same base class —
## this addon is pure GDScript by design) as the popup pattern found
## elsewhere in this codebase: build Controls once, guard re-entry, close
## via one idempotent path regardless of whether it was the window's own X
## button or a Close button that triggered it.

var _built := false
var _registry: ExtensionLibraryRegistry
var _on_changed: Callable
var _list_container: VBoxContainer
var _add_type: OptionButton
var _add_value: LineEdit
var _status_label: Label

func open(host: Node, registry: ExtensionLibraryRegistry, on_changed: Callable) -> void:
	_registry = registry
	_on_changed = on_changed
	_ensure_built()
	_repopulate_list()
	popup_centered(Vector2i(560, 420))

func _ensure_built() -> void:
	if _built:
		return
	_built = true

	title = "Libraries"
	size = Vector2i(560, 420)
	close_requested.connect(hide)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 8)
	add_child(root)

	var scroll := ScrollContainer.new()
	scroll.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	scroll.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	root.add_child(scroll)

	_list_container = VBoxContainer.new()
	_list_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	scroll.add_child(_list_container)

	root.add_child(HSeparator.new())

	var add_row := HBoxContainer.new()
	_add_type = OptionButton.new()
	_add_type.add_item("URL")
	_add_type.add_item("Local Path")
	add_row.add_child(_add_type)

	_add_value = LineEdit.new()
	_add_value.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	_add_value.placeholder_text = "https://... or a local file path"
	add_row.add_child(_add_value)

	var add_button := Button.new()
	add_button.text = "Add Library"
	add_button.pressed.connect(_on_add_pressed)
	add_row.add_child(add_button)
	root.add_child(add_row)

	var bottom_row := HBoxContainer.new()
	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(_on_refresh_pressed)
	bottom_row.add_child(refresh_button)

	_status_label = Label.new()
	bottom_row.add_child(_status_label)
	root.add_child(bottom_row)

func _repopulate_list() -> void:
	for child in _list_container.get_children():
		child.queue_free()

	var sources := ExtensionLibraryManifest.load_configured_sources()
	if sources.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No Libraries added yet."
		_list_container.add_child(empty_label)
		return

	for i in range(sources.size()):
		var source: Dictionary = sources[i]
		var row := HBoxContainer.new()
		var label := Label.new()
		var identity: String = String(source.get("url", source.get("path", "?")))
		label.text = "[%s] %s" % [String(source.get("type", "?")), identity]
		label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		row.add_child(label)

		var remove_button := Button.new()
		remove_button.text = "Remove"
		remove_button.pressed.connect(_on_remove_pressed.bind(i))
		row.add_child(remove_button)

		_list_container.add_child(row)

func _on_add_pressed() -> void:
	var value := _add_value.text.strip_edges()
	if value.is_empty():
		_status_label.text = "Enter a URL or path first."
		return

	var source_type := "url" if _add_type.selected == 0 else "local"
	var key := "url" if source_type == "url" else "path"

	var sources := ExtensionLibraryManifest.load_configured_sources()
	sources.append({ "type": source_type, key: value })
	if ExtensionLibraryManifest.save_configured_sources(sources):
		_add_value.text = ""
		_status_label.text = "Added — click Refresh to scan it."
		_repopulate_list()
		_on_changed.call()
	else:
		_status_label.text = "Could not save the Libraries config."

func _on_remove_pressed(index: int) -> void:
	var sources := ExtensionLibraryManifest.load_configured_sources()
	if index < 0 or index >= sources.size():
		return
	sources.remove_at(index)
	if ExtensionLibraryManifest.save_configured_sources(sources):
		_status_label.text = "Removed."
		_repopulate_list()
		_on_changed.call()
	else:
		_status_label.text = "Could not save the Libraries config."

func _on_refresh_pressed() -> void:
	_status_label.text = "Refreshing..."
	await _registry.refresh_all(self)
	_status_label.text = "Refreshed."
	_repopulate_list()
	_on_changed.call()
