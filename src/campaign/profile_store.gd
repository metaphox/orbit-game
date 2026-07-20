class_name ProfileStore
extends RefCounted
## Up to MAX_PROFILES named profiles in a single save file (no per-user
## save files), plus which one was last active and device-level settings.

const DEFAULT_PATH := "user://save.json"
const MAX_PROFILES := 5
const NAME_MAX_LENGTH := 20

var profiles: Array[Profile] = []
var last_active_name := ""

var _path := DEFAULT_PATH


static func load_or_new(path := DEFAULT_PATH) -> ProfileStore:
	var store := ProfileStore.new()
	store._path = path
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			store.last_active_name = parsed.get("last_active", "")
			Settings.effects_enabled = parsed.get("effects_enabled", true)
			for p_data in parsed.get("profiles", []):
				var profile := Profile.new()
				profile.profile_name = p_data.get("name", "")
				profile.unlocked.clear()
				for k in p_data.get("unlocked", []):
					profile.unlocked[int(k)] = true
				for k in p_data.get("medals", {}):
					profile.medals[int(k)] = p_data["medals"][k]
				profile.mission_save = p_data.get("mission_save")
				store.profiles.append(profile)
	return store


func save() -> void:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	var profiles_out := []
	for profile in profiles:
		var medals_out := {}
		for k in profile.medals:
			medals_out[str(k)] = profile.medals[k]
		profiles_out.append({
			"name": profile.profile_name,
			"unlocked": profile.unlocked.keys(),
			"medals": medals_out,
			"mission_save": profile.mission_save,
		})
	f.store_string(JSON.stringify({
		"last_active": last_active_name,
		"effects_enabled": Settings.effects_enabled,
		"profiles": profiles_out,
	}))
	f.close()


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


## Assumes validate_new_name(profile_name) == "" already.
func create_profile(profile_name: String) -> Profile:
	var profile := Profile.new()
	profile.profile_name = profile_name.strip_edges()
	profiles.append(profile)
	last_active_name = profile.profile_name
	save()
	return profile


func set_active(profile_name: String) -> void:
	last_active_name = profile_name
	save()


func last_active_profile() -> Profile:
	return find_profile(last_active_name)
