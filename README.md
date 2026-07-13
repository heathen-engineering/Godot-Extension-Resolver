# Extension Resolver for Godot

Dependency resolution for Godot extensions. Any addon that ships an `extension.manifest.json` at
its root gets, for free: version-guarded dependency checking (not just "is it installed" but "is
it installed at a version that actually satisfies what I need"), user-confirmed fetching of
missing or out-of-range dependencies from their declared source, update-availability checking
against already-installed extensions, and the unlock step for gated GDExtension binaries with a
hard native-library dependency.

Not Heathen-specific — the manifest format and resolution mechanism are generic. Any Godot
extension author can adopt it without adopting anything else Heathen-shaped. Not a marketplace —
it never browses or discovers extensions a project doesn't already reference; that's the Asset
Library's job.

See [`docs/manifest-schema.md`](docs/manifest-schema.md) for the manifest format.

## Installing

Extension Resolver is pure GDScript — no compiled binary, no native-library load-order risk. Drop
`addons/ExtensionResolver/` into `res://addons/` and enable the plugin, or let another extension's
gate stub (`gate/extension_resolver_gate.gd`) fetch and enable it for you the first time it's
needed.

## For extension authors

1. Ship `extension.manifest.json` at your addon's root — see the schema doc.
2. Copy `gate/extension_resolver_gate.gd` verbatim into your own `addons/<Name>/gate/` folder.
3. In your `EditorPlugin` script: `const Gate = preload("res://addons/<Name>/gate/extension_resolver_gate.gd")`,
   then call `Gate.ensure_unlocked(self, "<YourAddonId>", _on_unlocked)` from `_enter_tree()` — the
   gate script has no `class_name` (deliberately, so multiple addons' copies don't collide), so it's
   always reached via `preload()`, same as this ecosystem's existing gate convention. See the gate
   script's own header comment for the exact contract.

That's the entire integration surface — everything else (version comparison, fetching, the
Project Settings tab listing installed extensions and their update status) lives in Extension
Resolver itself, not duplicated per-addon.
