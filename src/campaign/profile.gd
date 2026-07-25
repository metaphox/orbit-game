class_name Profile
extends RefCounted
## One player's campaign progress: which levels are unlocked and the best
## medal earned on each. Pure in-memory state — ProfileStore owns
## persistence for all profiles together.

var profile_name := ""
## Chosen at creation, never changed after (DESIGN.md §14): no rewind, no
## predictive flight aids, every win inherently CLEAN, emblem on display.
var hardcore := false
## Progress is keyed by STABLE LevelDef.id ("level_01_01"), never by display
## index — so inserting a level inside an act can't shift saved progress
## (CR-11). The public API still takes the runtime index and converts at this
## boundary via the current ordering.
var unlocked: Dictionary[String, bool] = {}
# id -> {"medal": String, "dv": float, "clean": bool}. "clean" is sticky: true
# once the level has ever been cleared with zero rewinds.
var medals: Dictionary[String, Dictionary] = {}
# Dictionary (ShipSim.serialize() + level_id/sim_time/warp_index) or null for
# "no mission in progress" - typed Variant rather than Dictionary: a
# strictly-typed Dictionary field can't hold null in GDScript (it defaults
# to {} instead), which would break that meaningful distinction.
var mission_save: Variant = null


func _init() -> void:
	unlocked[Campaign.id_at(0)] = true  # the first mission is always unlocked


func is_unlocked(index: int) -> bool:
	return unlocked.has(Campaign.id_at(index))


func medal_for(index: int) -> String:
	var m: Dictionary = medals.get(Campaign.id_at(index), {})
	return m.get("medal", "")


## The mission-select status word: LOCKED (not unlocked), the earned medal once
## cleared, else ACTIVE (unlocked, not yet cleared).
func status_for(index: int) -> String:
	if not is_unlocked(index):
		return "LOCKED"
	var medal := medal_for(index)
	return medal if medal != "" else "ACTIVE"


## True once this level has been cleared without spending any rewinds - the
## ◇ CLEAN ribbon (DESIGN.md §14.4). Sticky: a later rewind-assisted run
## never revokes it. Hardcore profiles are CLEAN by construction.
func is_clean(index: int) -> bool:
	var m: Dictionary = medals.get(Campaign.id_at(index), {})
	return m.get("clean", false)


## Records a win, keeps the best (lowest-dv) medal per level, tracks the
## sticky CLEAN flag, unlocks whatever comes next in the campaign order, and
## clears any in-progress save for this mission (nothing to resume once it's
## won). Caller (campaign_root) calls ProfileStore.save() after.
func record_win(index: int, medal: String, dv_used: float, rewinds_used := 0) -> void:
	var id := Campaign.id_at(index)
	var prev: Dictionary = medals.get(id, {})
	var best_medal: String = medal
	var best_dv := dv_used
	if not prev.is_empty() and prev["dv"] <= dv_used:
		best_medal = prev["medal"]
		best_dv = prev["dv"]
	var clean: bool = prev.get("clean", false) or hardcore or rewinds_used == 0
	medals[id] = {"medal": best_medal, "dv": best_dv, "clean": clean}
	var next_index := Campaign.next_after(index)
	if next_index != -1:
		unlocked[Campaign.id_at(next_index)] = true
	if mission_save != null and mission_save.get("level_id") == id:
		mission_save = null
