@tool
extends EditorPlugin

## Registers the "ExtensionResolver" Engine singleton (ExtensionResolverCore,
## resolver.gd) so any gem's gate stub can call
## Engine.get_singleton("ExtensionResolver").resolve(host, addon_id, on_ready)
## with no preload/class_name coupling required on the caller's side — same
## access pattern this project's other Engine singletons already use (e.g.
## GameplayTagsEditorPlugin.gd calling
## Engine.get_singleton("SubsystemManagerBridge"); Engine.register_singleton()
## does NOT make a bare "ExtensionResolver" identifier available in GDScript
## the way an autoload does — confirmed against that existing call site
## rather than assumed).
##
## This plugin has no gate of its own and no extension.manifest.json
## dependency — see plugin.cfg's own description for why: pure GDScript, no
## native binary, nothing that can hard-crash on a missing dependency the
## way a GDExtension can.
##
## Also owns the "Extension Resolver" Project Settings tab (settings_tab.gd)
## — its own top-level tab, separate from any other addon's, added the same
## way Godot-Game-Framework's FoundationGameFrameworkEditorPlugin.gd adds
## its "Subsystems" tab (add_control_to_container, confirmed elsewhere in
## this project to create a genuine standalone tab rather than merging into
## an existing one).

var _resolver: ExtensionResolverCore
var _tab: ExtensionResolverSettingsTab

func _enter_tree() -> void:
	_resolver = ExtensionResolverCore.new()
	Engine.register_singleton("ExtensionResolver", _resolver)

	_tab = ExtensionResolverSettingsTab.new()
	add_control_to_container(CONTAINER_PROJECT_SETTING_TAB_LEFT, _tab)

func _exit_tree() -> void:
	if _tab != null:
		remove_control_from_container(CONTAINER_PROJECT_SETTING_TAB_LEFT, _tab)
		_tab.queue_free()
		_tab = null

	if Engine.has_singleton("ExtensionResolver"):
		Engine.unregister_singleton("ExtensionResolver")
	# ExtensionResolverCore extends Object, not RefCounted (see resolver.gd's
	# own doc comment — Engine.register_singleton() rejects RefCounted as of
	# this Godot version), so it needs an explicit free() here rather than
	# relying on refcounting to release it when _resolver goes out of scope.
	if _resolver != null:
		_resolver.free()
	_resolver = null
