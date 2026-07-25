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


## True once this level has been cleared without spending any rewinds - the sticky
## ◇ CLEAN ribbon (DESIGN.md §14.4), mirroring Profile.is_clean for the campaign.
func is_clean(id: String) -> bool:
	return bool(_records.get(id, {}).get("clean", false))


## Keep the run with the lowest Δv (best medal), but track CLEAN as sticky-best
## INDEPENDENTLY of the dv (CR-10): a slower clean run after a faster
## rewind-assisted one must still flip CLEAN on, and a later dirty run never
## revokes it. Mirrors Profile.record_win.
func record(id: String, medal: String, dv_used: float, clean: bool) -> void:
	var prev: Dictionary = _records.get(id, {})
	var sticky_clean: bool = clean or bool(prev.get("clean", false))
	if prev.is_empty() or dv_used < float(prev.get("dv", INF)):
		_records[id] = {"medal": medal, "dv": dv_used, "clean": sticky_clean}
	else:  # slower run: keep best medal/dv, but CLEAN still sticks
		prev["clean"] = sticky_clean
		_records[id] = prev


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
