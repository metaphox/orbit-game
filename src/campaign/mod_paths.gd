class_name ModPaths
extends RefCounted
## Where community level files live in a DEPLOYED game (not user:// — that's a
## hidden appdata path). Levels are scanned from a union of discoverable folders;
## the Documents one is created on first launch with a README + example so a
## creator has somewhere obvious to drop files.

const SUBDIR := "mods/levels"


static func game_name() -> String:
	return str(ProjectSettings.get_setting("application/config/name", "Limited Propellant"))


## The canonical, always-writable folder (used for the scaffold + "Open folder").
static func documents_dir() -> String:
	return OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join(game_name()).path_join(SUBDIR)


## All folders scanned for community levels, in priority order (first wins on an
## id clash): beside the game binary (portable zip), Documents, and — only in the
## editor — a project-local folder for development.
static func dirs() -> Array[String]:
	var out: Array[String] = [OS.get_executable_path().get_base_dir().path_join(SUBDIR), documents_dir()]
	if OS.has_feature("editor"):
		out.append(ProjectSettings.globalize_path("res://mods/levels"))
	return out


## Create the Documents mods folder with a README + one example on first run.
static func ensure_scaffold() -> void:
	if DisplayServer.get_name() == "headless":
		return  # don't touch the real Documents folder from tests / CI
	var dir := documents_dir()
	if DirAccess.dir_exists_absolute(dir):
		return
	DirAccess.make_dir_recursive_absolute(dir)
	_write(dir.path_join("README.txt"),
		"Drop a level .json (and an optional same-named .md brief) in this folder.\n"
		+ "It appears under MISSIONS ▶ COMMUNITY in-game. See example.json, and the\n"
		+ "full field reference in the game's docs/LEVELS.md.\n")
	_write(dir.path_join("example.json"), _EXAMPLE)
	_write(dir.path_join("example.md"),
		"A gentle first custom mission.\nBurn **prograde** at periapsis, then circularize at apoapsis.\n")


## The .json files in a folder, as [{id, path}] (id = filename without extension).
static func scan_dir(dir: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f: String in da.get_files():
		if f.to_lower().ends_with(".json"):
			out.append({"id": f.get_basename(), "path": dir.path_join(f)})
	return out


static func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


const _EXAMPLE := """{
  "title": "COMMUNITY: FIRST ORBIT",
  "system": "EARTH",
  "start": { "radius_km": 70 },
  "ship": { "dry_mass": 1000, "prop_mass": 300, "thrust": 6000, "isp": 82 },
  "objective": { "type": "orbit_match", "radius_km": 120, "tolerance_km": 2 },
  "dv_par": 140, "difficulty": 2
}
"""
