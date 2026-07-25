class_name Campaign
extends RefCounted
## The level registry and act grouping (DESIGN.md section 7). The built-in levels
## are authored as JSON (assets/levels/) and built through LevelLoader, the same
## pipeline community levels use. LEVEL_IDS is ordered by act, so its index equals
## play order; ACTS carves those indices into contiguous per-act ranges. Progress
## is persisted by the stable string id (LevelDef.id), not the index, so levels
## can be appended within an act's range without shifting saved progress (CR-11).
const LEVEL_IDS := [
	"level_01_01", "level_01_02", "level_01_03",
	"level_02_01", "level_02_02", "level_02_03",
	"level_03_01",
]

static var _specs: Array = []            # parsed JSON per index (loaded once)
static var _canon: Array[LevelDef] = []  # one canonical build per index, for metadata reads


static func _ensure_loaded() -> void:
	if not _specs.is_empty():
		return
	for id: String in LEVEL_IDS:
		var path := "res://assets/levels/%s.json" % id
		var spec: Variant = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
		var built := LevelLoader.from_dict(spec, id)
		assert(built.error == "", "built-in level %s failed to load: %s" % [id, built.error])
		_specs.append(spec)
		_canon.append(built.level)

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
	_ensure_loaded()
	return _canon.size()


## A fresh, independent LevelDef every call - preload() caches a single
## shared Resource instance process-wide, but callers (a mission attempt,
## an in-progress save) expect their own copy to mutate freely without
## leaking into other attempts or profiles.
static func level_at(index: int) -> LevelDef:
	_ensure_loaded()
	# Rebuilt from the spec each call: fresh body/objective instances (callers
	# mutate freely) with the loader's guaranteed objective.target === moons entry.
	return LevelLoader.from_dict(_specs[index], LEVEL_IDS[index]).level


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
	_ensure_loaded()
	return _canon[index].title


## Stable id for a level's authored brief files, e.g. "level_01_01".
static func brief_id(index: int) -> String:
	return LEVEL_IDS[index]


## Stable string identity for a display index, "" if out of range. This is the
## PERSISTENT key for progress (unlocks/medals/saves) — the integer index is a
## display/runtime handle only, so inserting levels can't shift saved progress.
static func id_at(index: int) -> String:
	return LEVEL_IDS[index] if index >= 0 and index < LEVEL_IDS.size() else ""


## Display index for a stable id, or -1 if the id isn't a current built-in.
static func index_of(id: String) -> int:
	return LEVEL_IDS.find(id)


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


## The translated mission-select status, derived from profile state (not by
## sniffing the status string). The generic state words carry the "status"
## translation context so they never collide with an unrelated future use of the
## same word; an earned medal translates plainly.
static func status_label(profile: Profile, index: int) -> String:
	if not profile.is_unlocked(index):
		return TranslationServer.translate("LOCKED", &"status")
	var medal := profile.medal_for(index)
	if medal.is_empty():
		return TranslationServer.translate("ACTIVE", &"status")
	return TranslationServer.translate(medal)
