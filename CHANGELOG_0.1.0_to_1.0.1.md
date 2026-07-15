# Changelog: v0.1.0 to v1.0.1

## New

- **Libraries**: a second discovery mechanism alongside the existing installed-extension list. Browse a catalogue of extensions you don't have installed yet, and install, update, or remove them directly.
- **Dialog queueing**: when several installed extensions share a missing dependency, only one dialog is shown instead of one per extension.
- **Update button** now actually fetches and installs an available update in one click, instead of only reporting that one exists.
- **Remove button**, with a warning if another installed extension still depends on what you're removing.
- **Publisher-grouped, collapsible sections** in the extension list, with documentation, support, and license links per extension.
- **Conflicting dependency source detection**: if two installed extensions declare different fetch sources for the same shared dependency, a warning is now shown instead of silently picking one.

## Fixes

- Fixed a duplicate plugin activation bug where a freshly resolved dependency's own editor plugin could be enabled twice.
- Fixed an unconditional filesystem rescan firing on every boot, even when nothing had changed.
- Fixed a real gap where a fetched dependency's native library was never actually loaded into the running process, only extracted to disk, causing a dependent extension to fail to find it.
- Fixed a duplicate CI run and a Godot 4.3 parse error in the shared gate script, caught by the addition of automated tests and CI that actually runs the addon rather than only packaging it.

## Other

- Added a real test suite covering version comparison and the fetch/extract path.
- Publisher metadata standardized, and documentation/support links updated to point at the Heathen Group Knowledge Base and Discord.
- This addon now ships its own `extension.manifest.json`, so it shows up correctly in its own settings tab and supports update checking like every other extension it manages.
