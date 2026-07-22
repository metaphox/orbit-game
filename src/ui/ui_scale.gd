extends Node
## Resolution-tier UI scaling. With stretch mode "disabled" the UI is drawn at
## native pixels, so controls keep their authored size as the window grows —
## constant from the 1280×720 floor up through 2560×1440 (inclusive). Above that
## (4K and beyond) the UI would read too small, so content_scale_factor steps to
## 1.5×, which in "disabled" mode is a straight multiplier on the whole 2D layer.
## Registered as an autoload so every screen inherits the policy.

const HIDPI_MAX := Vector2i(2560, 1440)  # inclusive: still 1.0× at exactly this size
const HIDPI_FACTOR := 1.5


func _ready() -> void:
	get_window().size_changed.connect(_apply)
	_apply()


func _apply() -> void:
	var s := get_window().size
	var scale_up := s.x > HIDPI_MAX.x or s.y > HIDPI_MAX.y
	get_window().content_scale_factor = HIDPI_FACTOR if scale_up else 1.0
