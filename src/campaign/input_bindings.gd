class_name InputBindings
extends RefCounted
## Registers the actions that aren't in project.godot's [input] (rewind +
## autopilot, which used to be raw keycodes) and applies user key rebinds from
## Settings (TECH_DEBTS.md TD-4). Defaults live here in code; overrides persist
## in Settings "key_bindings" as action -> [physical_keycode ints]. install() is
## idempotent, so it's safe to call from both the menu shell and (for tests) a
## directly-instantiated game scene.

## Actions this game owns beyond project.godot, with their default physical keys.
const EXTRA_DEFAULTS := {
	"rewind_open": [KEY_H],
	"rewind_prev": [KEY_LEFT, KEY_A],
	"rewind_next": [KEY_RIGHT, KEY_D],
	"rewind_confirm": [KEY_ENTER, KEY_KP_ENTER],
	"rewind_cancel": [KEY_ESCAPE],
	"autopilot_toggle": [KEY_J],
	"kill_rotation": [KEY_C],  # brake: SAS STABILITY, sits by the WASDQE attitude cluster
}


## Register the extra actions (if missing) then apply any saved rebinds. Safe to
## call more than once.
static func install() -> void:
	for action: String in EXTRA_DEFAULTS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for keycode: int in EXTRA_DEFAULTS[action]:
				InputMap.action_add_event(action, _key_event(keycode))
	apply_overrides()


## Overlay the player's saved rebinds onto whatever defaults are registered.
static func apply_overrides() -> void:
	var binds: Dictionary = Settings.get_value("key_bindings")
	for action: String in binds:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
			for keycode: Variant in binds[action]:
				InputMap.action_add_event(action, _key_event(int(keycode)))


## Rebind an action to a single physical key, persist it, and apply immediately.
static func rebind(action: String, physical_keycode: int) -> void:
	var binds: Dictionary = (Settings.get_value("key_bindings") as Dictionary).duplicate(true)
	binds[action] = [physical_keycode]
	Settings.set_value("key_bindings", binds)
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, _key_event(physical_keycode))


## Human-readable label for an action's primary key (for HUD hints etc.).
static func primary_key_label(action: String) -> String:
	if InputMap.has_action(action):
		for e: InputEvent in InputMap.action_get_events(action):
			if e is InputEventKey:
				return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	return "?"


static func _key_event(physical_keycode: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = physical_keycode as Key
	return e
