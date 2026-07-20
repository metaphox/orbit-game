class_name Profile
extends RefCounted
## One player's campaign progress: which levels are unlocked and the best
## medal earned on each. Pure in-memory state — ProfileStore owns
## persistence for all profiles together.

var profile_name := ""
var unlocked: Dictionary = {0: true}  # level_index (int) -> true
var medals: Dictionary = {}  # level_index (int) -> {"medal": String, "dv": float}
var mission_save = null  # Dictionary (ShipSim.serialize() + level_index/sim_time/warp_index) or null


func is_unlocked(index: int) -> bool:
	return unlocked.has(index)


func medal_for(index: int) -> String:
	var m = medals.get(index)
	return m["medal"] if m != null else ""


## Records a win, keeps the best (lowest-dv) medal per level, unlocks
## whatever comes next in the campaign order, and clears any in-progress
## save for this mission (nothing to resume once it's won). Caller
## (campaign_root) is responsible for calling ProfileStore.save() after.
func record_win(index: int, medal: String, dv_used: float) -> void:
	var prev = medals.get(index)
	if prev == null or dv_used < prev["dv"]:
		medals[index] = {"medal": medal, "dv": dv_used}
	var next_index := Campaign.next_after(index)
	if next_index != -1:
		unlocked[next_index] = true
	if mission_save != null and mission_save.get("level_index") == index:
		mission_save = null
