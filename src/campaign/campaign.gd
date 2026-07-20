class_name Campaign
extends RefCounted
## The level registry and act grouping (DESIGN.md section 7). LEVELS keeps
## its existing index meaning (tests and save files reference indices
## directly); ACTS reorders those same indices for display and unlock
## progression without renumbering anything.

## Not `const`: GDScript's const requires a compile-time constant
## expression, and preload() calls don't qualify.
static var LEVELS: Array[LevelDef] = [
	preload("res://src/levels/data/level_01.tres"),
	preload("res://src/levels/data/level_02.tres"),
	preload("res://src/levels/data/level_03.tres"),
	preload("res://src/levels/data/level_04.tres"),
	preload("res://src/levels/data/level_05.tres"),
	preload("res://src/levels/data/level_06.tres"),
	preload("res://src/levels/data/level_07.tres"),
]

const ACTS := [
	{"name": "ACT 1 — EARTH ORBIT SCHOOL", "indices": [0, 2, 5]},
	{"name": "ACT 2 — LUNAR PROGRAM", "indices": [1, 3, 4]},
	{"name": "ACT 3 — INTERPLANETARY", "indices": [6]},
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


static func acts() -> Array:
	return ACTS


## Flat play order: Act 1's levels, then Act 2's, in each act's own order.
static func order() -> Array:
	var flat := []
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
