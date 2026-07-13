@tool
class_name ExtensionSemver
extends RefCounted

## Minimal MAJOR.MINOR.PATCH version comparison — the concrete gap this whole
## tool exists to close (every heathen_manifest.json in this ecosystem
## already declares a min_version today; nothing has ever actually checked
## it). Deliberately not full semver precedence: pre-release/build-metadata
## suffixes ("-beta", "+build5") are stripped and ignored rather than given
## proper precedence rules, per the "Open questions" note in
## docs/manifest-schema.md — revisit only once an extension actually needs
## pre-release channels, not speculatively now.

## Parses "v1.2.3", "1.2.3-beta", "1.2" etc. into a 3-element
## PackedInt32Array [major, minor, patch]. Missing components default to 0;
## non-numeric components default to 0 rather than failing outright — a
## malformed version string shouldn't crash dependency resolution, it should
## just compare as very old.
static func parse(version: String) -> PackedInt32Array:
	var v := version.strip_edges()
	if v.begins_with("v") or v.begins_with("V"):
		v = v.substr(1)

	# Drop pre-release/build-metadata suffixes — whichever comes first.
	var dash := v.find("-")
	var plus := v.find("+")
	var cut := -1
	if dash != -1 and plus != -1:
		cut = min(dash, plus)
	elif dash != -1:
		cut = dash
	elif plus != -1:
		cut = plus
	if cut != -1:
		v = v.substr(0, cut)

	var parts := v.split(".")
	var result := PackedInt32Array([0, 0, 0])
	for i in range(min(parts.size(), 3)):
		if parts[i].is_valid_int():
			result[i] = int(parts[i])
	return result

## -1 if a < b, 0 if equal, 1 if a > b.
static func compare(a: String, b: String) -> int:
	var pa := parse(a)
	var pb := parse(b)
	for i in range(3):
		if pa[i] != pb[i]:
			return -1 if pa[i] < pb[i] else 1
	return 0

## True if installed_version satisfies [min_version, max_version] (both
## inclusive, both optional — an empty string means "no bound"). This is
## the actual version guard: called from ExtensionResolver when checking a
## dependency, and from the Settings tab when deciding whether to badge a
## row "update available".
static func satisfies(installed_version: String, min_version: String = "", max_version: String = "") -> bool:
	if not min_version.is_empty() and compare(installed_version, min_version) < 0:
		return false
	if not max_version.is_empty() and compare(installed_version, max_version) > 0:
		return false
	return true
