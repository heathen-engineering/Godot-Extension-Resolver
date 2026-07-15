# Extension Resolver for Godot

A dependency resolver for Godot addons. Any addon that ships a small manifest file gets, for free: version-checked dependency resolution, one-click fetching of missing dependencies from their declared source, update-availability checking, and a safe unlock step for GDExtension binaries with a hard native-library dependency.

## What it does

Godot has no built-in package manager, so addons that depend on other addons have historically had to hand-roll their own fetch and version-check logic, or simply assume the dependency is already there. Extension Resolver replaces that with one shared mechanism.

- Version-checked dependencies: not just "is it installed," but "is it installed at a version that actually satisfies what I need."
- One-click fetching: missing or out-of-range dependencies are fetched from their declared source with a single confirmation, never automatically.
- Update checking: every installed extension is checked against its source for a newer release, right in the Project Settings tab.
- Safe native-library gating: GDExtension binaries with a hard dependency stay inert until every dependency is confirmed present, then unlock without needing an editor restart.
- Libraries: a catalogue view for installing addons you don't have yet, not just managing the ones you do.

Generic, not tied to any one publisher. Any Godot extension author can ship the manifest file and get resolution for free.

## Requirements

- Godot 4.6 or compatible
- No compiled binary, no native-library load order to worry about. Pure GDScript.

## Links

- GitHub: [https://github.com/heathen-engineering/Godot-Extension-Resolver](https://github.com/heathen-engineering/Godot-Extension-Resolver)
- Documentation: [https://heathen.group/kb/godot-welcome/#extension-resolver](https://heathen.group/kb/godot-welcome/#extension-resolver)
- Support and Discord: [https://discord.gg/xmtRNkW7hW](https://discord.gg/xmtRNkW7hW)
- License: Apache 2.0
