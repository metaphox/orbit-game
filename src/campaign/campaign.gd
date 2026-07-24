class_name Campaign
extends RefCounted
## The level registry and act grouping (DESIGN.md section 7). LEVELS is
## ordered by act (level_<act>_<level>.tres), so its index equals play
## order; ACTS carves those indices into contiguous per-act ranges. The
## index is still the stable ID that tests and save files reference, so
## append new levels at the end of their act's range rather than reordering.

## Not `const`: GDScript's const requires a compile-time constant
## expression, and preload() calls don't qualify.
static var LEVELS: Array[LevelDef] = [
	preload("res://src/levels/data/level_01_01.tres"),
	preload("res://src/levels/data/level_01_02.tres"),
	preload("res://src/levels/data/level_01_03.tres"),
	preload("res://src/levels/data/level_02_01.tres"),
	preload("res://src/levels/data/level_02_02.tres"),
	preload("res://src/levels/data/level_02_03.tres"),
	preload("res://src/levels/data/level_03_01.tres"),
]

const ACTS: Array[Dictionary] = [
	{"name": "ACT 1 — EARTH ORBIT SCHOOL", "code": "ORB", "indices": [0, 1, 2]},
	{"name": "ACT 2 — LUNAR PROGRAM", "code": "LUN", "indices": [3, 4, 5]},
	{"name": "ACT 3 — INTERPLANETARY", "code": "INT", "indices": [6]},
]


## Accessor functions, not direct const access: GDScript's static analyzer
## can fail to resolve an external class's const Array/Dictionary members
## through dotted access ("Could not resolve external class member"),
## even though it happily resolves a function call on the same class.
static func level_count() -> int:
	return LEVELS.size()


## A fresh, independent LevelDef every call - preload() caches a single
## shared Resource instance process-wide, but callers (a mission attempt,
## an in-progress save) expect their own copy to mutate freely without
## leaking into other attempts or profiles.
static func level_at(index: int) -> LevelDef:
	return LEVELS[index].duplicate(true)


static func acts() -> Array[Dictionary]:
	return ACTS


## Flat play order: Act 1's levels, then Act 2's, in each act's own order.
static func order() -> Array[int]:
	var flat: Array[int] = []
	for act in ACTS:
		flat.append_array(act["indices"])
	return flat


## The level unlocked by winning `index`, or -1 if it was the last one.
static func next_after(index: int) -> int:
	var flat := order()
	var pos := flat.find(index)
	if pos == -1 or pos + 1 >= flat.size():
		return -1
	return flat[pos + 1]


static func title(index: int) -> String:
	return LEVELS[index].title


## Index of the act that contains this level.
static func act_of(index: int) -> int:
	for a: int in ACTS.size():
		if index in (ACTS[a]["indices"] as Array):
			return a
	return 0


## Short mission code like "ORB-02": the act's prefix + 1-based position in it.
static func code(index: int) -> String:
	var a := act_of(index)
	var within: int = (ACTS[a]["indices"] as Array).find(index)
	return "%s-%02d" % [ACTS[a]["code"], within + 1]


## (position, total) in flat play order, 1-based — for "SORTIE nn / NN".
static func sortie(index: int) -> Vector2i:
	return Vector2i(order().find(index) + 1, level_count())


## The mission name for cards: the level title after the ":" (whole title if
## there's no colon), trimmed. "ORBIT SCHOOL 1: RAISE ORBIT" -> "RAISE ORBIT".
static func short_title(index: int) -> String:
	var parts := title(index).split(":")
	return (parts[1] if parts.size() > 1 else parts[0]).strip_edges()
