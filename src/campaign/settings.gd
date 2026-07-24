class_name Settings
extends RefCounted
## Device-level preferences (not per-profile), persisted in the shared save file
## via ProfileStore. A typed key->value store so new prefs (audio, key rebinds,
## theme) don't each need a bespoke static var + save/load hook (TECH_DEBTS.md
## TD-5). Static so deeply-nested UI (Hud, FlightView, screens) can read/write
## without threading a store reference through every constructor.

## Known keys and their defaults. Add a pref here and persistence + typed access
## come for free. All values must be JSON-safe (bool/number/string/array/dict).
const DEFAULTS := {
	"effects_enabled": true,   # CRT film grade / scanlines toggle
	"menu_hints": false,       # show the up/down/act key hints in menus (F1 toggles)
	"key_bindings": {},        # action -> Array of serialized InputEvents (TD-4)
	"volume_master": 0.8,      # 0..1, wired when audio lands
	"volume_music": 0.7,
	"volume_sfx": 0.9,
	"language": "en",          # UI locale code (en/de/fr/ru/zh/ja/ko); applied at startup
}

const LANGUAGE := "language"

## Menus hide their navigation key hints by default (most players don't need
## them); F1 toggles them in any modal menu. Kept here so every screen reads one
## shared, persisted flag.
const MENU_HINTS := "menu_hints"

static var _values: Dictionary = DEFAULTS.duplicate(true)

## Convenience mirror for the one pref with many call sites; kept in sync with
## the store by to_dict()/from_dict()/set_value().
static var effects_enabled := true

## Set for the process lifetime by apply_cmdline_args(); never persisted - a
## launch-time dev flag (--debug-mode), not a player preference.
static var debug_mode := false


static func reset_to_defaults() -> void:
	_values = DEFAULTS.duplicate(true)
	effects_enabled = true


static func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	_values[key] = value
	if key == "effects_enabled":
		effects_enabled = bool(value)


static func get_bool(key: String) -> bool:
	return bool(get_value(key))


static func menu_hints_on() -> bool:
	return get_bool(MENU_HINTS)


static func toggle_menu_hints() -> void:
	set_value(MENU_HINTS, not menu_hints_on())


static func get_float(key: String) -> float:
	return float(get_value(key))


## JSON-safe snapshot of all prefs, for ProfileStore.save().
static func to_dict() -> Dictionary:
	_values["effects_enabled"] = effects_enabled  # capture direct writes to the mirror
	return _values.duplicate(true)


## Load prefs, keeping only known keys (ignores stale/unknown ones).
static func from_dict(data: Dictionary) -> void:
	for key: String in DEFAULTS:
		if data.has(key):
			_values[key] = data[key]
	effects_enabled = bool(_values.get("effects_enabled", true))


## Reads --debug-mode off the command line (e.g. Godot editor's "Main Run
## Args", or `./limited-propellant --debug-mode`) so mission select can unlock
## every level for testing without touching profile save data. Named
## --debug-mode rather than --debug: the latter is a reserved engine flag
## (Godot's script debugger, "-d"), consumed before user code sees it.
static func apply_cmdline_args() -> void:
	var args := OS.get_cmdline_args()
	debug_mode = "--debug-mode" in args
	for a: String in args:
		if a.begins_with("--locale="):
			locale_override = a.trim_prefix("--locale=")


## Launch-time UI locale: the --locale=<code> dev override wins, else the saved
## preference. Never persisted (the override is a process-lifetime flag).
static var locale_override := ""


static func language() -> String:
	return locale_override if locale_override != "" else String(get_value(LANGUAGE))
