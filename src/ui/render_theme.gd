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


static func default() -> RenderTheme:
	return RenderTheme.new()
