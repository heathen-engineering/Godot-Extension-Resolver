extends RefCounted

## Covers the two pure functions in source_github_release.gd — the fetch/
## extract mechanics that (per docs/manifest-schema.md's "Expected zip
## layout") were never actually exercised end-to-end before this tool
## existed, and where a wrong zip-layout assumption silently double-nests
## extracted files rather than failing loudly.
##
## preload(), not the global class_name — see test_semver.gd's header
## comment for why.
const ExtensionSourceGithubRelease = preload("res://addons/ExtensionResolver/source_github_release.gd")

func run(assert_fn: Callable) -> void:
	_test_relative_path_within_id(assert_fn)
	_test_select_asset_url(assert_fn)

func _test_relative_path_within_id(assert_fn: Callable) -> void:
	assert_fn.call(
		ExtensionSourceGithubRelease.relative_path_within_id("FoundationXxHash/plugin.cfg", "FoundationXxHash") == "plugin.cfg",
		"one-level nesting (id at archive root)")
	assert_fn.call(
		ExtensionSourceGithubRelease.relative_path_within_id("addons/FoundationXxHash/plugin.cfg", "FoundationXxHash") == "plugin.cfg",
		"two-level nesting (id under addons/, this project's own CI shape)")
	assert_fn.call(
		ExtensionSourceGithubRelease.relative_path_within_id("addons/FoundationXxHash/src/thing.cpp", "FoundationXxHash") == "src/thing.cpp",
		"nested subpath under the id folder is preserved")
	assert_fn.call(
		ExtensionSourceGithubRelease.relative_path_within_id("README.md", "FoundationXxHash") == "",
		"a stray entry with no id segment at all returns empty (skip, don't extract)")
	assert_fn.call(
		ExtensionSourceGithubRelease.relative_path_within_id("FoundationXxHashExtra/plugin.cfg", "FoundationXxHash") == "",
		"id must be its own path segment, not just a string prefix of a longer folder name")

func _test_select_asset_url(assert_fn: Callable) -> void:
	var single := {"assets": [{"name": "Whatever.zip", "browser_download_url": "https://x/whatever.zip"}]}
	assert_fn.call(
		ExtensionSourceGithubRelease.select_asset_url(single, "FoundationXxHash") == "https://x/whatever.zip",
		"single-asset fallback: name doesn't matter when there's exactly one asset")

	var prefixed := {"assets": [
		{"name": "Other.zip", "browser_download_url": "https://x/other.zip"},
		{"name": "FoundationXxHash.zip", "browser_download_url": "https://x/fxh.zip"},
	]}
	assert_fn.call(
		ExtensionSourceGithubRelease.select_asset_url(prefixed, "FoundationXxHash") == "https://x/fxh.zip",
		"id-prefix fallback picks the asset whose name starts with id among multiple assets")

	var patterned := {"tag_name": "v1.2.3", "assets": [
		{"name": "FoundationXxHash-1.2.3.zip", "browser_download_url": "https://x/versioned.zip"},
	]}
	assert_fn.call(
		ExtensionSourceGithubRelease.select_asset_url(patterned, "FoundationXxHash", "FoundationXxHash-{version}.zip") == "https://x/versioned.zip",
		"asset_pattern with a {version} placeholder, version taken from tag_name with 'v' stripped")

	assert_fn.call(
		ExtensionSourceGithubRelease.select_asset_url({"assets": []}, "FoundationXxHash") == "",
		"no assets at all returns empty, not a crash")
	var no_match := {"assets": [
		{"name": "Unrelated.zip", "browser_download_url": "https://x/u.zip"},
		{"name": "AlsoUnrelated.zip", "browser_download_url": "https://x/au.zip"},
	]}
	assert_fn.call(
		ExtensionSourceGithubRelease.select_asset_url(no_match, "FoundationXxHash") == "",
		"multiple assets, none matching id prefix and no asset_pattern, returns empty rather than guessing")
