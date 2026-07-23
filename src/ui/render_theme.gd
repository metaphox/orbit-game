class_name RenderTheme
extends RefCounted
## Swappable visual configuration for the 3D flight view (TECH_DEBTS.md TD-3).
## The renderers (BodyRenderer, etc.) read their appearance from here instead of
## hardcoding materials/colors/shaders, so the "Themes" feature can later supply
## alternate looks. `default()` reproduces the current NASA-punk look exactly.
##
## Kept a plain RefCounted (not a .tres Resource) for now: themes are code-built
## and there's only one. Promote to an Inspector-authored Resource when the
## Themes feature needs user-supplied entries.

# Environment
var ambient_light_color := Color(0.25, 0.28, 0.35)
var ambient_light_energy := 0.5
var glow_bloom := 0.2
var sun_light_energy := 1.3
var sun_rotation := Vector3(-0.55, 0.65, 0.0)
var sky_shader: Shader = preload("res://src/shaders/starfield_sky.gdshader")

# Bodies
var body_shader: Shader = preload("res://src/shaders/celestial_body.gdshader")
var earth_map: Texture2D = preload("res://assets/textures/earth_abstract.svg")
var atmosphere_shader: Shader = preload("res://src/shaders/atmosphere.gdshader")
var atmosphere_glow_color := Color(0.10, 0.66, 0.88)
var atmosphere_glow_strength := 0.76

# Trajectory line colours (objective-closeness lerps FAR -> MATCH)
var traj_far_color := Color(1.0, 0.55, 0.12)
var traj_match_color := Color(0.35, 1.0, 0.45)

# Target overlays
var ring_color := Color(0.5, 0.85, 0.6)        # dashed target-orbit ring (green)
var corridor_color := Color(1.0, 0.72, 0.24)   # entry-corridor gate band (amber)

# Maneuver planning overlays
var node_ghost_color := Color(0.45, 0.85, 1.0)  # predicted post-burn conic + node marker (cyan)
var mark_ap := Color(0.4, 0.75, 1.0)
var mark_pe := Color(1.0, 0.85, 0.3)
var mark_an := Color(0.85, 0.4, 1.0)
var mark_dn := Color(0.55, 0.3, 0.75)
var mark_impact := Color(1.0, 0.2, 0.15)
var mark_encounter := Color(1.0, 1.0, 1.0)
var mark_closest := Color(1.0, 0.3, 0.6)

# Ship markers
var prograde_color := Color(0.3, 1.0, 0.4)
var retrograde_color := Color(1.0, 0.35, 0.25)
var posture_hull_color := Color(0.92, 0.9, 0.86)
var posture_nose_color := Color(0.95, 0.45, 0.1)
var posture_wing_color := Color(0.5, 0.85, 1.0)


static func default() -> RenderTheme:
	return RenderTheme.new()
