class_name SaveData
extends RefCounted
## Campaign progress: which levels are unlocked and the best medal earned
## on each, persisted as JSON in the user data directory.

const DEFAULT_PATH := "user://save.json"

var unlocked: Dictionary = {}  # level_index (int) -> true
var medals: Dictionary = {}  # level_index (int) -> {"medal": String, "dv": float}

var _path := DEFAULT_PATH


static func load_or_new(path := DEFAULT_PATH) -> SaveData:
	var save := SaveData.new()
	save._path = path
	save.unlocked[0] = true  # the first mission is always available
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			for k in parsed.get("unlocked", []):
				save.unlocked[int(k)] = true
			for k in parsed.get("medals", {}):
				save.medals[int(k)] = parsed["medals"][k]
	return save


func save() -> void:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	var medals_out := {}
	for k in medals:
		medals_out[str(k)] = medals[k]
	f.store_string(JSON.stringify({"unlocked": unlocked.keys(), "medals": medals_out}))
	f.close()


func is_unlocked(index: int) -> bool:
	return unlocked.has(index)


func medal_for(index: int) -> String:
	var m = medals.get(index)
	return m["medal"] if m != null else ""


## Records a win, keeps the best (lowest-dv) medal per level, unlocks
## whatever comes next in the campaign order, and persists immediately.
func record_win(index: int, medal: String, dv_used: float) -> void:
	var prev = medals.get(index)
	if prev == null or dv_used < prev["dv"]:
		medals[index] = {"medal": medal, "dv": dv_used}
	var next_index := Campaign.next_after(index)
	if next_index != -1:
		unlocked[next_index] = true
	save()
