class_name Settings
extends RefCounted
## Device-level toggles (not per-profile), persisted via ProfileStore.
## Static so deeply-nested UI builders (Hud, FlightView, LevelSelect) can
## check them without threading a store reference through every
## constructor.

static var effects_enabled := true
