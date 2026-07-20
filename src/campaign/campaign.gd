class_name Campaign
extends RefCounted
## The level registry and act grouping (DESIGN.md section 7). LEVELS keeps
## its existing index meaning (tests and save files reference indices
## directly); ACTS reorders those same indices for display and unlock
## progression without renumbering anything.

## Not `const`: GDScript's const requires a compile-time constant
## expression, and references to other class_name scripts don't qualify.
static var LEVELS := [Level01, Level02, Level03, Level04, Level05]

const ACTS := [
	{"name": "ACT 1 — EARTH ORBIT SCHOOL", "indices": [0, 2]},
	{"name": "ACT 2 — LUNAR PROGRAM", "indices": [1, 3, 4]},
]


## Accessor functions, not direct const access: GDScript's static analyzer
## can fail to resolve an external class's const Array/Dictionary members
## through dotted access ("Could not resolve external class member"),
## even though it happily resolves a function call on the same class.
static func level_count() -> int:
	return LEVELS.size()


static func level_at(index: int) -> GDScript:
	return LEVELS[index]


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
	return LEVELS[index].make().title
