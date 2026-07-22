> **Migrating to Codeberg:** this repo is moving to [codeberg.org/Heathen-Engineering/Godot-Extension-Resolver](https://codeberg.org/Heathen-Engineering/Godot-Extension-Resolver). GitHub will remain a read-only mirror during the transition.

# Extension Resolver for Godot

![License](https://img.shields.io/badge/License-Apache_2.0-blue?style=flat-square)
![Maintained](https://img.shields.io/badge/Maintained%3F-yes-green?style=flat-square)
![Godot](https://img.shields.io/badge/Godot-4.6%20%2B-%23478CBF?style=flat-square&logo=godotengine&logoColor=white)

A dependency resolver for Godot addons. Any addon that ships a small manifest file gets, for free: version-checked dependency resolution, one-click fetching of missing dependencies from their declared source, update-availability checking, and a safe unlock step for GDExtension binaries with a hard native-library dependency.

- **License:** Apache 2.0
- **Origin:** Heathen Group
- **Platforms:** Windows, Linux, macOS

> [!TIP]
> **Looking for the easiest way to install?**
> Copy `addons/ExtensionResolver/` straight into your project's `addons/` folder and enable the plugin. See [Install](#install) below.

<img width="1201" height="729" alt="Extension Resolver's Project Settings tab, showing installed extensions grouped by publisher" src="https://github.com/user-attachments/assets/d0c7d727-5d02-4664-b99d-3af6f5b51fd9" />

---

## Support

For general questions, help, and troubleshooting, join our [Discord](https://discord.gg/xmtRNkW7hW). Thousands of developers are there and can often help faster than waiting on a maintainer. Please use [GitHub Issues](https://github.com/heathen-engineering/Godot-Extension-Resolver/issues) for a confirmed bug or a feature request that needs tracking, not general support questions.

---

## Become a GitHub Sponsor
[![Discord](https://img.shields.io/badge/Discord--1877F2?style=social&logo=discord)](https://discord.gg/xmtRNkW7hW)
[![GitHub followers](https://img.shields.io/github/followers/heathen-engineering?style=social)](https://github.com/heathen-engineering?tab=followers)

Support Heathen by becoming a [GitHub Sponsor](https://github.com/sponsors/heathen-engineering). Sponsorship directly funds the development and maintenance of free tools like this, as well as our game development [Knowledge Base](https://heathen.group/) and community on [Discord](https://discord.gg/xmtRNkW7hW).

Sponsors also get access to our private SourceRepo, which includes developer tools for O3DE, Unreal, Unity, and Godot.
Learn more or explore other ways to support at [heathen.group/kb](https://heathen.group/kb/do-more/)

---

## What it does

Godot has no built-in package manager, so addons that depend on other addons have historically had to hand-roll their own fetch/version-check logic, or simply assume the dependency is already there. Extension Resolver replaces that with one shared mechanism:

| Feature | Description |
|---|---|
| **Version-checked dependencies** | Not just "is it installed," but "is it installed at a version that actually satisfies what I need." |
| **One-click fetching** | Missing or out-of-range dependencies are fetched from their declared source with a single confirmation, never automatically. |
| **Update checking** | Every installed extension is checked against its source for a newer release, right in the Project Settings tab. |
| **Safe native-library gating** | GDExtension binaries with a hard dependency stay inert until every dependency is confirmed present, then unlock without needing an editor restart. |
| **Libraries** | A catalogue view for installing addons you don't have yet, not just managing the ones you do. See [Library Schema](docs/library-schema.md). |

Full documentation of the manifest format is in [`docs/manifest-schema.md`](docs/manifest-schema.md).

---

## Install

Copy `addons/ExtensionResolver/` into your project's `addons/` folder and enable the plugin from **Project Settings > Plugins**. It is pure GDScript: no compiled binary, no native-library load order to worry about.

Alternatively, if you install an addon that already depends on Extension Resolver, its own gate script will offer to fetch and enable Extension Resolver for you automatically the first time it is needed.

---

## For extension authors

1. Ship an `extension.manifest.json` at your addon's root. See [`docs/manifest-schema.md`](docs/manifest-schema.md) for the full schema.
2. Copy `gate/extension_resolver_gate.gd` into your own `addons/<YourAddon>/gate/` folder.
3. From your `EditorPlugin`'s `_enter_tree()`, call `Gate.ensure_unlocked(self, "<YourAddonId>", _on_unlocked)`, using a `preload()` of the gate script you copied in step 2.

That is the entire integration surface. Version comparison, fetching, and the Project Settings tab that lists every installed extension and its update status all live in Extension Resolver itself, so none of it needs to be duplicated per addon.

---

## License

Apache 2.0.
