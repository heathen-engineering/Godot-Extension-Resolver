# Extension Manifest Schema

**Status: Draft — first pass, not yet implemented or battle-tested.**

## What this is for

Extension Resolver for Godot reads one file per participating addon —
`res://addons/<id>/extension.manifest.json` — to answer three questions: what version of this
is installed, where can updates for it be found, and what does it depend on. Nothing else. This
document defines that file's shape. It is deliberately **not** Heathen-specific — any Godot
extension author can ship this file and get dependency resolution, version guarding, and
update-checking for free, without adopting anything else Heathen-shaped.

## Non-goals (keep re-reading this before adding a field)

- **Not a marketplace.** The resolver never browses or discovers extensions a project doesn't
  already reference (directly, or transitively via another installed extension's
  `dependencies`). Discovery is the Asset Library's job; this tool starts from "I already know
  what I want," the same premise `heathen_manifest.json`'s dependency-fetch flow already works
  under today.
- **Never fetches automatically.** Every fetch/update/enable action requires an explicit user
  confirmation at the point it happens. This carries over unchanged from the existing
  `HeathenDependencyManifest`/`HeathenDependencyFetcher` design in `Godot-Game-Framework` — soft
  bookkeeping and user-gated action, never silent background mutation of a project.
- **Not a build system.** The manifest describes a *shipped, already-built* addon (GDScript, or a
  GDExtension binary + its `.gdextension` file) fetched as a release artifact. It has nothing to
  say about how that artifact was produced — that's the extension author's own CI/CMake/whatever,
  same as it is today.

## File location and name

`res://addons/<id>/extension.manifest.json`, one per addon, sitting next to `plugin.cfg`. Filename
deliberately avoids `manifest.json` (collides with the web/PWA manifest convention many tools
already grep for) and avoids `package.json` (npm). `extension.manifest.json` is unambiguous and
greppable.

## Schema

```json
{
  "schema_version": 1,
  "id": "FoundationGameFramework",
  "display_name": "Foundation for Game Framework",
  "version": "1.0.0",
  "repository_url": "https://github.com/heathen-engineering/Godot-Game-Framework",
  "source": {
    "type": "github_release",
    "repo": "heathen-engineering/Godot-Game-Framework"
  },
  "gated": true,
  "dependencies": [
    {
      "id": "FoundationXxHash",
      "min_version": "1.0.0",
      "source": {
        "type": "github_release",
        "repo": "heathen-engineering/Godot-xxHash"
      }
    }
  ]
}
```

### Top-level fields

| Field | Required | Notes |
|---|---|---|
| `schema_version` | Yes | Integer. Lets the resolver evolve the format later without silently mis-parsing an old manifest. Starts at `1`. |
| `id` | Yes | Must match the addon's own folder name under `res://addons/`. This is the identity used everywhere else (dependency references, installed-version lookups) — not `display_name`, which is presentation-only and can change freely. |
| `display_name` | Yes | Human-readable, shown in the resolver's UI. |
| `version` | Yes | The version of *this* addon, as currently installed. Semver (`MAJOR.MINOR.PATCH`), optional leading `v` stripped before comparison. This is the field the resolver diffs against a dependent's `min_version`/`max_version`, and against `source`'s latest-available version to decide whether an update exists. |
| `repository_url` | No | Plain human-facing link, shown in the UI ("View project"). Not used for fetching — that's `source`'s job. Optional because not every extension author wants to point at a public repo even if `source` resolves through one (e.g. private-release-gated extensions like Steamworks today). |
| `source` | Yes, unless the addon is never expected to be fetched/updated by the resolver (e.g. something a user is expected to always hand-install) | Describes *where and how* to fetch a specific version of this extension. See "Source types" below. |
| `gated` | No, default `false` | `true` if this addon ships a GDExtension binary with a hard native-library dependency and needs the inert-`.gdextension.available` → real-`.gdextension` unlock step (see "Gating convention" below) before Godot can load it. Pure-GDScript addons, or GDExtensions with no hard dependencies, leave this `false`/omitted — nothing to gate. |
| `dependencies` | No, default `[]` | Array of dependency descriptors — see below. |

### Dependency descriptor

| Field | Required | Notes |
|---|---|---|
| `id` | Yes | The depended-on addon's own `id`. |
| `min_version` | No | Inclusive lower bound. Omitted = any installed version satisfies it (today's `HeathenDependencyManifest` behavior — presence-only, no version check — stays the *default*, not a special case). |
| `max_version` | No | Inclusive upper bound. Expected to be rare (used to pin against a known-incompatible future major version) — most dependencies should only ever need `min_version`. |
| `source` | Yes | Where to fetch this dependency from *if it turns out to be missing*. See "Source precedence" below for what happens when this disagrees with the dependency's own self-declared `source`. |

### Source types

`source.type` is an open enum — the resolver dispatches on it, unrecognised values are reported
as "can't auto-fetch this one, install it manually" rather than a hard error (an extension can
still declare metadata/dependencies even if its fetch mechanism isn't one the resolver knows yet).

- **`github_release`** (the only type implemented for v1): `repo` (`"owner/name"`), plus an
  **optional** `asset_pattern`. A GitHub Release is already scoped to a single tag/version, so
  the version doesn't need to be baked into the asset filename the way `{version}`-templated
  patterns implied in an earlier draft — real build output is typically just a fixed name
  (`FoundationXxHash.zip`, not `FoundationXxHash-1.0.0.zip`). Asset selection, in order:
  1. `asset_pattern` if present — supports an optional `{version}` placeholder for the (rarer)
     case where an author's release process really does bake the version into the filename.
  2. Otherwise, the release's only asset, if it has exactly one.
  3. Otherwise, the first asset whose name starts with `id` — the same fallback
     `HeathenDependencyFetcher`/`heathen_gate.gd` already use today.
  Fetching *any* tagged release (not only `/releases/latest`) is what makes targeting a specific
  version possible — same GitHub API, just parameterized by tag instead of hardcoded to
  `latest`.

Future candidates (not designed yet, don't build for these speculatively): a direct URL type, for
extensions that don't use GitHub Releases at all; something for a private/authenticated endpoint,
for a not-yet-designed equivalent of Steamworks' gated-SDK distribution model.

### Expected zip layout

A release asset's zip is extracted by locating the `<id>/` path segment itself within each
archive entry and keeping everything after it — **not** by assuming a fixed nesting depth. This
matters because it isn't fixed in practice: this project's own existing CI (e.g.
`Godot-xxHash/.github/workflows/build.yml`'s "Package addon" job) builds zips rooted two levels
deep (`addons/FoundationXxHash/plugin.cfg`), while the mechanism this tool replaces
(`heathen_gate.gd`) assumed exactly one level (`FoundationXxHash/plugin.cfg`) and would have
silently double-nested the extracted files had that path ever actually been exercised — it never
was; no CI in this ecosystem tests the fetch/extract flow end-to-end today. Searching for the
`id` segment itself is robust to either shape (or a future packaging change) without needing to
standardize every extension author's zip layout first.

### Source precedence

An already-*installed* dependency's own manifest is always authoritative for what to check
against (its own `version` field) — a dependent's declared `source` for that dependency is only
ever consulted when the dependency **isn't installed yet** and something needs to fetch it. If
two different installed extensions declare different `source` values for the same dependency
`id` (e.g. two forks pointing at different repos), the resolver uses whichever was declared by
the extension currently being resolved, and — flagged as an open question, not decided here —
should probably surface a warning that conflicting sources exist for the same `id`, since that
usually indicates a real project misconfiguration rather than something to silently pick a
winner for.

## Gating convention (`"gated": true`)

Unchanged from `heathen_gate.gd`'s existing mechanism, just formalized as part of this schema
instead of copy-pasted-script behavior: a gated addon ships its real GDExtension file as
`<id>.gdextension.available` instead of `<id>.gdextension`, so Godot's boot-time `.gdextension`
auto-load scan never touches it while a hard dependency might still be missing. The resolver's
unlock step — performed only after every entry in `dependencies` is confirmed present and
version-satisfying — renames the file to its real name and calls
`GDExtensionManager.load_extension()` so it's live in the current editor session without a
restart. This absorbs `heathen_gate.gd`'s `_unlock()` responsibility into the resolver itself;
see the (forthcoming) gate-stub design doc for what a hosting extension's own bootstrap script
still needs to do on its own (locating/fetching the resolver itself, before any of this can run).

## Open questions

- **Version comparison semantics for pre-release/build-metadata suffixes** (`1.0.0-beta`,
  `1.0.0+build5`) — full semver precedence rules, or a simpler "ignore anything after `-`/`+`"
  MVP? Lean toward the simpler rule until an extension actually needs pre-release channels.
- **Conflicting `source` declarations for the same dependency `id`** (see "Source precedence"
  above) — warn-and-pick vs. hard error vs. something else.
- **Uninstall / dependency-orphan cleanup** isn't covered by this schema at all yet — today's
  fetch-only flows never needed a removal story. Worth deciding whether that's in scope for v1 or
  a deliberately later addition.
