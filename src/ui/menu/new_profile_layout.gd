class_name NewProfileLayout
extends PanelContainer
## Right-pane form for NEW PROFILE: authored in new_profile_layout.tscn; the
## backdrop / breadcrumb / hint chrome comes from the MenuShell that hosts it.

@onready var line_edit: LineEdit = %CallsignEdit
@onready var error_label: Label = %ErrorLabel
@onready var hardcore_check: CheckButton = %HardcoreCheck
