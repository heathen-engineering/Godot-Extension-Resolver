extends SceneTree

## preload(), not the bare global class_name — see lockfile.gd's own header comment: this is
## exactly the "fresh clone, no editor session has ever built the class cache" case.
const ExtensionLockfile = preload("res://addons/ExtensionResolver/lockfile.gd")

## Headless bootstrap for a project that deliberately does NOT check its fetched addons/
## contents into version control (see docs/lockfile-schema.md) — reads addons.lock.json and
## fetches/extracts every entry at its exact pinned version, so a fresh clone can be restored to
## a runnable state without ever opening the editor. Run via:
##   godot --headless --script res://addons/ExtensionResolver/restore_cli.gd
## Exits 0 if every locked entry is present and restorable, 1 if anything failed to fetch (so a
## setup script/CI job can gate on it). Deliberately doesn't touch GDExtensionManager/plugin
## enablement (see lockfile.gd's restore_missing() doc comment) — that's an editor/runtime
## concern for the next real launch, not this one-shot file-placement step.

func _initialize() -> void:
	var lockfile_path := ExtensionLockfile.DEFAULT_LOCKFILE_PATH
	if not FileAccess.file_exists(lockfile_path):
		print("No %s found — nothing to restore." % lockfile_path)
		quit(0)
		return

	var host := Node.new()
	get_root().add_child(host)

	var result: Dictionary = await ExtensionLockfile.restore_missing(host, func(message: String): print(message))

	var fetched: Array = result.get("fetched", [])
	var failed: Array = result.get("failed", [])
	print("\nRestored: %s" % (", ".join(fetched) if not fetched.is_empty() else "(nothing missing)"))
	if not failed.is_empty():
		printerr("Failed to restore: %s" % ", ".join(failed))
		quit(1)
		return
	quit(0)
