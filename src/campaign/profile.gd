class_name Profile
extends RefCounted
## One player's campaign progress: which levels are unlocked and the best
## medal earned on each. Pure in-memory state — ProfileStore owns
## persistence for all profiles together.

var profile_name := ""
var unlocked: Dictionary[int, bool] = {0: true}
var medals: Dictionary[int, Dictionary] = {}  # level_index -> {"medal": String, "dv": float}
# Dictionary (ShipSim.serialize() + level_index/sim_time/warp_index) or null
# for "no mission in progress" - typed Variant rather than Dictionary: a
# strictly-typed Dictionary field can't hold null in GDScript (it defaults
# to {} instead), which would break that meaningful distinction.
var mission_save: Variant = null


func is_unlocked(index: int) -> bool:
	return unlocked.has(index)


func medal_for(index: int) -> String:
	var m: Dictionary = medals.get(index, {})
	return m.get("medal", "")


## Records a win, keeps the best (lowest-dv) medal per level, unlocks
## whatever comes next in the campaign order, and clears any in-progress
## save for this mission (nothing to resume once it's won). Caller
## (campaign_root) is responsible for calling ProfileStore.save() after.
func record_win(index: int, medal: String, dv_used: float) -> void:
	var prev: Dictionary = medals.get(index, {})
	if prev.is_empty() or dv_used < prev["dv"]:
		medals[index] = {"medal": medal, "dv": dv_used}
	var next_index := Campaign.next_after(index)
	if next_index != -1:
		unlocked[next_index] = true
	if mission_save != null and mission_save.get("level_index") == index:
		mission_save = null
