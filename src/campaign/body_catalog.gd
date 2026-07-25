class_name BodyCatalog
extends RefCounted
## Canonical body registry loaded from assets/bodies/catalog.json. build() turns a
## level's root + moon list into a runtime BodyDef graph: the root is forced to
## soi=INF / no parent (it's the universe centre for that level), moons carry
## their catalog soi/orbit and their parent is linked to the *same* in-graph
## instance so objective.target identity holds. Phase is a per-level scenario
## value passed in moon_specs, not stored in the catalog.

const PATH := "res://assets/bodies/catalog.json"
## Synthetic bodies for the debug-only perf test levels, merged only in a debug
## build so the shared community catalog stays clean in release.
const DEBUG_PATH := "res://assets/bodies/debug_catalog.json"

static var _cat: Dictionary = {}


static func _catalog() -> Dictionary:
	if _cat.is_empty():
		_merge_file(PATH)
		if OS.has_feature("debug"):
			_merge_file(DEBUG_PATH)
	return _cat


static func _merge_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
	if data is Dictionary:
		for k: String in data:
			if not k.begins_with("_"):  # "_comment" etc.
				_cat[k] = data[k]


static func names() -> Array:
	return _catalog().keys()


static func has_body(body_name: String) -> bool:
	return _catalog().has(body_name)


## A fresh BodyDef from the catalog (moon role: keeps its soi/orbit/parent-name).
static func _make(body_name: String) -> BodyDef:
	var d: Dictionary = _catalog()[body_name]
	var b := BodyDef.new()
	b.name = body_name
	b.mu = float(d.get("mu", 0.0))
	b.radius = float(d.get("radius", 0.0))
	b.soi_radius = float(d.get("soi_radius", INF))
	b.orbit_radius = float(d.get("orbit_radius", 0.0))
	if d.has("color"):
		b.color = Color(str(d["color"]))
	return b


## Build a per-level body graph. `moon_specs` = [{"name": String, "phase_deg"?: float}, …].
## Returns {"root": BodyDef, "moons": Array[BodyDef], "by_name": Dictionary}.
static func build(root_name: String, moon_specs: Array) -> Dictionary:
	var by_name := {}
	var root := _make(root_name)
	root.soi_radius = INF   # a level's root is its universe centre
	root.parent = null
	root.orbit_radius = 0.0
	root.orbit_phase_deg = 0.0
	by_name[root_name] = root

	var moons: Array[BodyDef] = []
	for spec: Dictionary in moon_specs:
		var b := _make(String(spec["name"]))
		b.orbit_phase_deg = float(spec.get("phase_deg", 0.0))
		b.decorative = bool(spec.get("decorative", false))
		by_name[b.name] = b
		moons.append(b)

	# Second pass: link each moon's parent to the shared in-graph instance.
	for b: BodyDef in moons:
		var pname := String((_catalog()[b.name] as Dictionary).get("parent", ""))
		b.parent = by_name.get(pname)  # null if the parent isn't in this level (loader validates)
	return {"root": root, "moons": moons, "by_name": by_name}
