class_name Profile
extends RefCounted
## One player's campaign progress: which levels are unlocked and the best
## medal earned on each. Pure in-memory state — ProfileStore owns
## persistence for all profiles together.

var profile_name := ""
## Chosen at creation, never changed after (DESIGN.md §14): no rewind, no
## predictive flight aids, every win inherently CLEAN, emblem on display.
var hardcore := false
var unlocked: Dictionary[int, bool] = {0: true}
# level_index -> {"medal": String, "dv": float, "clean": bool}. "clean" is
# sticky: true once the level has ever been cleared with zero rewinds.
var medals: Dictionary[int, Dictionary] = {}
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


## True once this level has been cleared without spending any rewinds - the
## ◇ CLEAN ribbon (DESIGN.md §14.4). Sticky: a later rewind-assisted run
## never revokes it. Hardcore profiles are CLEAN by construction.
func is_clean(index: int) -> bool:
	var m: Dictionary = medals.get(index, {})
	return m.get("clean", false)


## Records a win, keeps the best (lowest-dv) medal per level, tracks the
## sticky CLEAN flag, unlocks whatever comes next in the campaign order, and
## clears any in-progress save for this mission (nothing to resume once it's
## won). Caller (campaign_root) calls ProfileStore.save() after.
func record_win(index: int, medal: String, dv_used: float, rewinds_used := 0) -> void:
	var prev: Dictionary = medals.get(index, {})
	var best_medal: String = medal
	var best_dv := dv_used
	if not prev.is_empty() and prev["dv"] <= dv_used:
		best_medal = prev["medal"]
		best_dv = prev["dv"]
	var clean: bool = prev.get("clean", false) or hardcore or rewinds_used == 0
	medals[index] = {"medal": best_medal, "dv": best_dv, "clean": clean}
	var next_index := Campaign.next_after(index)
	if next_index != -1:
		unlocked[next_index] = true
	if mission_save != null and mission_save.get("level_index") == index:
		mission_save = null
