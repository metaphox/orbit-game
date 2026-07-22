class_name ProfileStore
extends RefCounted
## Up to MAX_PROFILES named profiles in a single save file (no per-user
## save files), plus which one was last active and device-level settings.
##
## Saves are written to a temp file and atomically renamed into place, with
## the previous file kept as a .bak, so a crash or a partial write can
## never leave every profile lost - it can only lose the most recent save.

const DEFAULT_PATH := "user://save.json"
const MAX_PROFILES := 5
const NAME_MAX_LENGTH := 20
## v2: LEVELS was renumbered into act order (level_<act>_<level>.tres), so
## index-keyed progress from a v1 save points at the wrong levels and is
## discarded on load (see _apply).
const SCHEMA_VERSION := 2
const BACKUP_SUFFIX := ".bak"
const TMP_SUFFIX := ".tmp"

var profiles: Array[Profile] = []
var last_active_name := ""

## Set by load_or_new() when the save file couldn't be read as-is; empty
## in the normal case. Meant to be shown to the player, not just logged.
var load_warning := ""

var _path := DEFAULT_PATH


## Dictionary on success, null on any failure (missing file, unreadable,
## or not a JSON object) - failures are also push_error'd with detail.
static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("ProfileStore: could not open %s (%s)" % [
			path, error_string(FileAccess.get_open_error())])
		return null
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("ProfileStore: %s does not contain a valid save (bad JSON)" % path)
		return null
	return parsed


static func load_or_new(path := DEFAULT_PATH) -> ProfileStore:
	var store := ProfileStore.new()
	store._path = path
	var parsed: Variant = _read_json(path)
	if parsed == null and FileAccess.file_exists(path):
		# the primary file exists but is corrupt - try the backup before
		# giving up and treating this as a brand new player.
		parsed = _read_json(path + BACKUP_SUFFIX)
		if parsed != null:
			store.load_warning = "SAVE FILE WAS DAMAGED - RECOVERED FROM BACKUP"
		else:
			store.load_warning = "SAVE FILE WAS UNREADABLE - STARTING FRESH"
	if parsed != null:
		store._apply(parsed)
	return store


## Level indices round-trip as ints in memory but as JSON numbers (floats)
## or strings on disk, depending on whether they came from an array or a
## dict key - accept any of those, reject anything else instead of crashing
## on int() of a non-numeric value.
static func _as_level_index(k: Variant) -> Variant:
	if k is int or k is float:
		return int(k)
	if k is String and k.is_valid_int():
		return int(k)
	return null


func _apply(parsed: Dictionary) -> void:
	last_active_name = parsed.get("last_active", "")
	# Device prefs live under "settings"; fall back to the pre-store top-level
	# "effects_enabled" key so old saves migrate cleanly.
	var settings_data: Dictionary = parsed.get("settings", {})
	if settings_data.is_empty() and parsed.has("effects_enabled"):
		settings_data = {"effects_enabled": parsed["effects_enabled"]}
	Settings.from_dict(settings_data)
	# Progress is keyed by LEVELS index; a pre-v2 save predates the act-order
	# renumbering, so its indices point at the wrong levels. Keep the named
	# profiles but reset their progress to a fresh campaign.
	var stale := int(parsed.get("version", 0)) < SCHEMA_VERSION
	if stale:
		load_warning = "SAVE PREDATES LEVEL RENUMBERING - PROGRESS RESET"
	for p_data: Variant in parsed.get("profiles", []):
		if not (p_data is Dictionary):
			push_warning("ProfileStore: skipping a malformed profile entry")
			continue
		var profile := Profile.new()
		profile.profile_name = p_data.get("name", "")
		profile.hardcore = p_data.get("hardcore", false)
		if not stale:
			profile.unlocked.clear()
			for k: Variant in p_data.get("unlocked", []):
				var index: Variant = _as_level_index(k)
				if index != null:
					profile.unlocked[index] = true
			var medals: Variant = p_data.get("medals", {})
			if medals is Dictionary:
				for k: Variant in medals:
					var index: Variant = _as_level_index(k)
					if index != null and medals[k] is Dictionary:
						profile.medals[index] = medals[k]
			var mission_save: Variant = p_data.get("mission_save")
			profile.mission_save = mission_save if mission_save is Dictionary else null
		profiles.append(profile)


## Writes to a temp file, backs up the previous save, then atomically
## replaces it - so a failed write or a mid-write crash never touches the
## last known-good save. Returns false (and push_error's the reason) if
## the write or replace failed.
func save() -> bool:
	var profiles_out := []
	for profile in profiles:
		var medals_out := {}
		for k in profile.medals:
			medals_out[str(k)] = profile.medals[k]
		profiles_out.append({
			"name": profile.profile_name,
			"hardcore": profile.hardcore,
			"unlocked": profile.unlocked.keys(),
			"medals": medals_out,
			"mission_save": profile.mission_save,
		})
	var json_text := JSON.stringify({
		"version": SCHEMA_VERSION,
		"last_active": last_active_name,
		"settings": Settings.to_dict(),
		"profiles": profiles_out,
	})

	var tmp_path := _path + TMP_SUFFIX
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("ProfileStore: could not open %s for writing (%s)" % [
			tmp_path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(json_text)
	f.close()

	if FileAccess.file_exists(_path):
		var backup_err := DirAccess.copy_absolute(_path, _path + BACKUP_SUFFIX)
		if backup_err != OK:
			push_warning("ProfileStore: could not refresh backup (%s)" % error_string(backup_err))

	var rename_err := DirAccess.rename_absolute(tmp_path, _path)
	if rename_err != OK:
		push_error("ProfileStore: could not replace save file (%s)" % error_string(rename_err))
		return false
	return true


func can_create_profile() -> bool:
	return profiles.size() < MAX_PROFILES


func find_profile(profile_name: String) -> Profile:
	for p in profiles:
		if p.profile_name == profile_name:
			return p
	return null


## "" if the name is usable, else a short reason to show the player.
func validate_new_name(profile_name: String) -> String:
	var trimmed := profile_name.strip_edges()
	if trimmed == "":
		return "ENTER A NAME"
	if trimmed.length() > NAME_MAX_LENGTH:
		return "NAME TOO LONG (%d CHARS MAX)" % NAME_MAX_LENGTH
	if find_profile(trimmed) != null:
		return "NAME ALREADY TAKEN"
	if not can_create_profile():
		return "ALL %d PROFILE SLOTS FULL" % MAX_PROFILES
	return ""


## Assumes validate_new_name(profile_name) == "" already. `hardcore` is
## fixed here at creation and never changes for the profile's life (§14.4).
func create_profile(profile_name: String, hardcore := false) -> Profile:
	var profile := Profile.new()
	profile.profile_name = profile_name.strip_edges()
	profile.hardcore = hardcore
	profiles.append(profile)
	last_active_name = profile.profile_name
	save()
	return profile


func set_active(profile_name: String) -> void:
	last_active_name = profile_name
	save()


func last_active_profile() -> Profile:
	return find_profile(last_active_name)
