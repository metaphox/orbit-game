class_name SandboxStore
extends RefCounted
## Progress for community (drop-in) levels, kept in a separate namespace from the
## campaign's index-keyed ProfileStore: community levels have string IDs, are all
## unlocked (no next_after chain), and only their best result is remembered.
## Persisted to user://sandbox.json (game-managed — not the user-editable mod
## files). Never subject to ProfileStore's positional save reset.

const PATH := "user://sandbox.json"
const TMP_SUFFIX := ".tmp"

## id -> {"medal": String, "dv": float, "clean": bool}
var _records: Dictionary = {}


static func load_or_new(path := PATH) -> SandboxStore:
	var s := SandboxStore.new()
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
		if data is Dictionary:
			s._records = data
		else:
			push_error("SandboxStore: %s is not valid JSON; starting fresh" % path)
	return s


## Community levels never lock.
func is_unlocked(_id: String) -> bool:
	return true


func medal_for(id: String) -> String:
	return _records.get(id, {}).get("medal", "")


func best_dv(id: String) -> float:
	return _records.get(id, {}).get("dv", 0.0)


## Keep the run with the lowest Δv (best medal). `clean` is sticky-best alongside.
func record(id: String, medal: String, dv_used: float, clean: bool) -> void:
	var prev: Dictionary = _records.get(id, {})
	if prev.is_empty() or dv_used < float(prev.get("dv", INF)):
		_records[id] = {"medal": medal, "dv": dv_used, "clean": clean or prev.get("clean", false)}


func save(path := PATH) -> bool:
	var tmp := path + TMP_SUFFIX
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SandboxStore: could not open %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(_records))
	f.close()
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) == OK
