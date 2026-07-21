# Lockfile Schema

**Status: New in v1.2.0.** Built for one concrete case: a game project (TheBarrow) that
deliberately does not check its fetched `addons/*/` contents into version control — deep-copied
GDExtension binaries per platform/config don't diff meaningfully and bloat repo storage for no
benefit — but still needs a way to restore itself to a runnable state from a fresh, stripped
clone. Modeled on Unity UPM's `Packages/packages-lock.json`.

## What this is for

`extension.manifest.json` (see `manifest-schema.md`) answers "what version of *this addon* is
installed, right now, on this disk." The lockfile answers a different question: "what should
`res://addons/` contain, in total, for this project to run" — a project-wide snapshot, meant to
be committed even when the addons themselves are gitignored. Nothing else reads it; it exists
purely to drive `restore_missing()`.

## File: `res://addons.lock.json`

```json
{
    "schema_version": 1,
    "entries": [
        {
            "id": "FoundationGameFramework",
            "version": "1.0.3",
            "source": { "type": "github_release", "repo": "heathen-engineering/Godot-Game-Framework" }
        }
    ]
}
```

Regenerated in full every time an addon is installed, updated, or removed (see `lockfile.gd`'s
`write_lockfile()` — called from `ExtensionResolverCore._fetch_one()` and both relevant
`list_panel.gd` actions). Never hand-edited, same reasoning as
`ExtensionLibraryManifest.save_configured_sources()` for `addon_libraries.json`: the file only
ever reflects one thing (current ground truth), so there is no merge/patch case to get wrong.
Addons with no declared `source` are omitted — nothing for a restore to fetch them from.

## Restoring

- **In-editor**: not yet wired to a settings-tab button in this release (see CHANGELOG "Known
  gaps") — call `ExtensionLockfile.restore_missing(host)` directly if needed from the editor.
- **Headless** (the primary intended use — a fresh clone with no `addons/*` payloads at all,
  only what each addon's own git history tracked, e.g. `plugin.cfg` +
  `extension.manifest.json` if a project chooses to keep those): run
  `godot --headless --script res://addons/ExtensionResolver/restore_cli.gd` from the project
  root. Exits `0` if everything restored, `1` if anything failed (fresh CI/setup-script gating).

Restoring fetches the **exact pinned version**, not "latest" — reproducing precisely what was
locked is the point; that's a different concern from dependency resolution's
min/max-version-range checking, which stays as-is in `resolver.gd`.

## Non-goals

- **Not a dependency resolver.** `compute_missing()` only diffs "is this exact version present,
  yes or no" — it does not evaluate `min_version`/`max_version` ranges. That stays
  `resolver.gd`'s job, for addons that ARE checked in / already present.
- **Doesn't touch plugin enablement or GDExtension loading.** `restore_missing()` only fetches
  and extracts files. Getting a freshly-restored addon actually loaded is whatever the next
  normal editor/game launch already does — same as any other addon appearing on disk.
- **No private/non-`github_release` source support yet.** Planned as a future addition to this
  ecosystem (a private-repo source type), not built here — see TheBarrow's own
  `docs/infra/huginn/00-overview.md` for the motivating case (Toolkit-tier paid addons).
