class_name Settings
extends RefCounted
## Device-level toggles (not per-profile), persisted via ProfileStore.
## Static so deeply-nested UI builders (Hud, FlightView, LevelSelect) can
## check them without threading a store reference through every
## constructor.

static var effects_enabled := true

## Set for the process lifetime by apply_cmdline_args(); never persisted
## (unlike effects_enabled) since it's a launch-time dev flag, not a
## player preference.
static var debug_mode := false


## Reads --debug-mode off the command line (e.g. Godot editor's "Main Run
## Args", or `./orbit-game --debug-mode` for an exported build) so mission
## select can unlock every level for testing without touching profile save
## data. Named --debug-mode rather than --debug: the latter is a reserved
## engine flag (Godot's own script debugger, "-d"), consumed by the engine
## before user code ever sees it.
static func apply_cmdline_args() -> void:
	debug_mode = "--debug-mode" in OS.get_cmdline_args()
