# Library Schema

**Status: Draft — Phase 1 (github_release-sourced entries, URL/local sources only). See
docs/extensions/04-libraries.md in TheBarrow for the full design, including what's deferred to
Phase 2 (`git_subfolder` fetch, repo-root multi-library scanning, private-library detection).**

## What this is for

A **Library** is a catalogue of installable extensions a project doesn't necessarily have
installed yet — as opposed to `extension.manifest.json` (see `manifest-schema.md`), which
describes one already-installed addon authoritatively. A Library Entry is a *summary* a
publisher writes about an extension, used purely for discovery/display; once an entry is
actually installed, its own `extension.manifest.json` takes over completely and the Library
Entry that pointed at it is never consulted again for anything functional (no fallback, ever —
this is a discovery tool, not a second source of truth).

## Configured Libraries — `res://addon_libraries.json`

The list of *which* Libraries a project has added — project-relative and meant to be checked
into the project, so a whole team sees the same configured sources by default. Path is
configurable via the `extension_resolver/libraries_config_path` Project Setting; defaults to
`res://addon_libraries.json` if never set.

```json
{
    "schema_version": 1,
    "libraries": [
        { "type": "url", "url": "https://raw.githubusercontent.com/.../library.json" },
        { "type": "local", "path": "C:/dev/my-library.json" }
    ]
}
```

- **`url`** — a direct link to one Library JSON file (a raw GitHub content URL, or any other
  plain HTTPS GET). Phase 1 does **not** scan a Git repo's tree for multiple `*.library.json`
  files — that's a Phase 2 concern (needs the same "list a repo's tree" capability
  `git_subfolder` fetching does).
- **`local`** — a path to one Library JSON file on local disk.

## Library JSON (the file a `url`/`local` source points at)

```json
{
    "schema_version": 1,
    "name": "Heathen Group — Godot Extensions",
    "publisher": { "name": "Heathen Group", "url": "https://heathen.group" },
    "entries": [
        {
            "id": "FoundationSteamworks",
            "display_name": "Foundation for Steamworks",
            "publisher": { "name": "Heathen Group", "url": "https://heathen.group" },
            "description": "...",
            "documentation_url": "https://heathen.group/kb/steam-welcome/",
            "license_url": "https://github.com/heathen-engineering/Godot-Foundation-for-Steamworks/blob/main/LICENSE",
            "support_url": "https://discord.gg/xmtRNkW7hW",
            "dependencies": [
                { "id": "FoundationGameFramework", "min_version": "1.0.0" }
            ],
            "source": {
                "type": "github_release",
                "repo": "heathen-engineering/Godot-Foundation-for-Steamworks"
            }
        }
    ]
}
```

### Top-level fields

| Field | Required | Notes |
|---|---|---|
| `schema_version` | Yes | Same forward-compat convention as `extension.manifest.json` — newer than this resolver knows is a warning, not a hard failure. |
| `name` | No | The Library's own display name, shown in the management window's list of configured Libraries. |
| `publisher` | No | `{ "name": string, "url"?: string }` — the *Library's* publisher, not necessarily every entry's (an entry may declare its own `publisher` that differs, e.g. a curated third-party Library listing other authors' work). |
| `entries` | Yes | Array of Library Entry descriptors, see below. |

### Library Entry fields

Every field here is display-only until the entry is installed — see "What this is for" above.

| Field | Required | Notes |
|---|---|---|
| `id` | Yes | Must match what the real `extension.manifest.json` declares as its own `id` once installed — this is how the resolver recognizes an entry as already-installed (`ExtensionManifestReader.read_manifest_for(id) != null`). |
| `display_name` | No | Shown in the Libraries tab; falls back to `id` if omitted. |
| `publisher` | No | Same shape as the Library's own `publisher` — drives the same UPM-style publisher-grouped tree the In Project tab already uses. |
| `description` | No | Same restricted `[text](url)`-only Markdown-to-BBCode handling as `extension.manifest.json`. |
| `documentation_url` / `license_url` / `support_url` | No | Same "standard links row" as `extension.manifest.json`. |
| `dependencies` | No, default `[]` | Same shape as `extension.manifest.json`'s dependency descriptors (`id`, `min_version`, `max_version`) — shown informationally in the detail pane; never affects anything once the entry is actually installed, since the installed manifest's own `dependencies` takes over completely at that point. |
| `source` | Yes | Only `github_release` is supported in Phase 1 — see `manifest-schema.md`'s "Source types" for the exact shape (`repo`, optional `asset_pattern`). Installing a not-yet-installed entry runs the identical fetch pipeline a missing-dependency fetch already uses. |
| `access_url` | No | Reserved for Phase 2 (private-library detection) — a single link (e.g. GitHub Sponsors) shown when the entry is inaccessible with the current machine's Git credentials. Harmless to include now; nothing reads it yet. |

## Per-machine cache — `user://extension_resolver/library_cache/`

Not user-configurable, not project-shared. One JSON file per configured source (keyed by a hash
of its `url`/`path`), storing the last successfully-fetched Library JSON plus a fetch timestamp.
Exists so the Libraries tab has something to show immediately on open, and so an explicit
Refresh is the only thing that ever re-hits the network — scanning is on-demand only, never a
timer or file-system watch (this is a utility, not a background service).

## Trust model

An installed extension's own `extension.manifest.json` is the **only** thing the resolver ever
acts on functionally (dependency checks, version comparisons) once that extension is on disk. A
Library Entry never overrides it, is never merged with it, and is never consulted again for that
`id` post-install — it did its job the moment Install succeeded.
