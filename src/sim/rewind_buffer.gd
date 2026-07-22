class_name RewindBuffer
extends RefCounted
## In-memory undo history for one mission (DESIGN.md §14). Anchors are coast
## snapshots taken an instant before each burn ignites (plus mission start);
## landmarks are SOI crossings, kept only as scrub navigation aids. Pure
## data - game_root records into it and restores from it via
## ShipSim.apply_serialized. Nothing here touches Nodes or the render tree.

## Burns whose start falls within this many seconds of the previous burn
## ending coalesce into the standing anchor (no tap-burn spam). Burns run at
## warp 0, so sim-seconds == real-seconds here.
const COALESCE := 0.5

# {"sim_time": float, "warp_index": int, "label": String, "state": Dictionary}
var anchors: Array[Dictionary] = []
# {"sim_time": float, "label": String} - scrub-only, never a resume point
var landmarks: Array[Dictionary] = []

var charges := 0
var rewinds_used := 0

var _last_burn_end := -INF


func setup(budget: int) -> void:
	charges = maxi(budget, 0)
	rewinds_used = 0
	anchors.clear()
	landmarks.clear()
	_last_burn_end = -INF


## The mission-start anchor (t == 0), always present so the player can rewind
## all the way back to the pad.
func record_launch(state: Dictionary) -> void:
	set_floor(0.0, 0, state, "LAUNCH")


## Seed the history with a single anchor and no landmarks. Used at launch and
## when resuming a mid-mission save (the save point becomes the rewind floor -
## anchor history is session-only in v1, DESIGN.md §14.5).
func set_floor(sim_time: float, warp_index: int, state: Dictionary, label: String) -> void:
	anchors = [{"sim_time": sim_time, "warp_index": warp_index, "label": label, "state": state}]
	landmarks.clear()
	_last_burn_end = -INF


## Called on the rising edge of a burn, with the coast state captured an
## instant before ignition. Returns true if a new anchor was added, false if
## it coalesced into the previous one.
func note_burn_start(sim_time: float, warp_index: int, state: Dictionary) -> bool:
	if not anchors.is_empty() and sim_time - _last_burn_end < COALESCE:
		return false
	anchors.append({
		"sim_time": sim_time, "warp_index": warp_index, "label": "BURN", "state": state})
	return true


func note_burn_end(sim_time: float) -> void:
	_last_burn_end = sim_time


func add_landmark(sim_time: float, label: String) -> void:
	landmarks.append({"sim_time": sim_time, "label": label})


func has_charges() -> bool:
	return charges > 0


## Commit a rewind to the anchor at `index`: spend a charge, drop every
## anchor/landmark after it (the discarded future), and let the next burn
## anchor freshly. Caller guarantees has_charges() when `charged` is true.
func commit(index: int, charged: bool) -> void:
	if charged:
		charges -= 1
		rewinds_used += 1
	var cut: float = anchors[index]["sim_time"]
	anchors = anchors.slice(0, index + 1)
	var kept: Array[Dictionary] = []
	for lm in landmarks:
		if lm["sim_time"] <= cut:
			kept.append(lm)
	landmarks = kept
	_last_burn_end = -INF
