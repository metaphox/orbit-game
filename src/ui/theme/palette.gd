class_name Palette
extends RefCounted
## The shared NASA-punk semantic palette (see UI-DESIGN.md). One meaning per
## colour, consistent across every view: green = live/own, amber = planned
## intent, cyan = target, red = danger. Only the minimap consumes this so far;
## other views will migrate onto it. Keep this and UI-DESIGN.md in lockstep.

const VOID := Color("050705")     # background void
const LIVE := Color("4dffa0")     # your current state: own orbit, apoapsis, periapsis, ship
const LIVE_DIM := Color("2f9e63")  # dimmed phosphor: secondary HUD readouts
const INTENT := Color("ffb100")   # planned intent: maneuver node, planned burn
const TARGET := Color("4fd8e2")   # the objective: target orbit / target point / station
const WARNING := Color("ff3b2a")  # imminent danger: impact / collision (rare, loud)
const INK := Color("f2ecdb")      # labels
const DIM := Color("7f877d")      # secondary structure: orbit tracks, grid
const SOI := Color("c9722b")      # sphere-of-influence boundary: dotted dark orange (its own code)

## UI-chrome tokens (the design-ref "ORBITAL OS" system, ref/design-ref.html).
## The single source of truth for menus + HUD styling; screens must not redefine
## their own colour constants.
const PANEL := Color("0d110d")       # panel / card background
const PANEL_HI := Color("111811")    # raised panel
const HAIRLINE := Color("232b24")    # 1px rules and borders
const INK_SOFT := Color("c9c3b2")    # secondary body text
const SELECT := Color("ffb100")      # selection / hover (amber; same as INTENT by design)
const DISABLED := Color("4a5349")    # disabled control text
const LIVE_DK := Color("0e2e1d")     # green button drop-shadow / fill-dark
const INTENT_DK := Color("2e2100")   # amber drop-shadow / fill-dark
const WARNING_DK := Color("330d08")  # red drop-shadow / fill-dark

## HUD surface fills — translucent tints laid over the live 3D flight view.
## Opacity is baked in, so each surface's whole tone lives in one place.
const PANEL_BG := Color(0.02, 0.035, 0.024, 0.96)    # solid card: win/fail banner, F1 overlay, flash
const PANEL_BG_SOFT := Color(0.02, 0.035, 0.024, 0.6)  # translucent chip (level title)
const BAR_BG := Color(0.016, 0.027, 0.02, 0.92)      # top + bottom telemetry bars
const CONSOLE_BG := Color(0.02, 0.05, 0.036, 0.6)    # bottom toolbar backdrop
const MAP_BG := Color(0.03, 0.22, 0.12, 0.55)        # minimap panel backdrop
const SCRIM := Color(0.0, 0.0, 0.0, 0.45)            # modal dim (pause)

## Menu / screen chrome. The menus now share the core HUD palette — text is LIVE /
## LIVE_DIM, errors WARNING, accents/selection INTENT, locked items DISABLED,
## backdrops VOID. Only these two have no core equivalent.
const MEDAL_GOLD := Color("ffd94d")            # medal / achievement gold
const PAUSE_BG := Color(0.0, 0.02, 0.0, 0.72)  # pause overlay scrim (over live flight)

## Rewind-timeline scrubber (rewind_timeline.gd).
const REWIND_LINE := Color(0.3, 0.65, 0.38)
const REWIND_ANCHOR := Color(0.45, 1.0, 0.55)
const REWIND_SELECTED := Color(1.0, 0.85, 0.3)
const REWIND_LANDMARK := Color(0.42, 0.62, 0.82)
const REWIND_LABEL := Color(0.86, 0.84, 0.72)

## Utility / miscellaneous UI tokens (kept here so nothing outside this file and
## render_theme.gd holds a raw Color literal — see tools/lint_ui_colors.sh).
const TRANSPARENT := Color(0, 0, 0, 0)          # "no fill / no outline" sentinel
const LABEL_SHADOW := Color(0, 0, 0, 0.7)       # 1px drop shadow behind map labels
const MAP_NOSE := Color(0.85, 1.0, 0.92)        # minimap ship glyph nose tip ("forward")

## Debug design-grid overlay (grid_overlay.gd; dev-only, cycled by '#').
const GRID_WHITE := Color(1.0, 1.0, 1.0)
const GRID_BLACK := Color(0.0, 0.0, 0.0)
const GRID_ALERT := Color(1.0, 0.23, 0.16)


## Convert a palette colour to a BBCode/HTML hex string ("#rrggbb").
static func hex(c: Color) -> String:
	return "#" + c.to_html(false)


## Per-body fill tints (UI-DESIGN.md → Celestial body tints). Bodies render as
## a dark, faintly-tinted disc (no bright outline) so the tint alone identifies
## which world you're looking at. Keyed by BodyDef.name, upper-cased.
const BODY_TINTS := {
	"SUN": Color(0.28, 0.19, 0.04),      # warm solar amber
	"SOL": Color(0.28, 0.19, 0.04),      # the Sun, as named in the interplanetary levels
	"MERCURY": Color(0.14, 0.12, 0.10),  # grey-brown
	"VENUS": Color(0.20, 0.17, 0.10),    # pale sulphur cream
	"EARTH": Color(0.05, 0.16, 0.18),    # green-blue ocean world
	"MOON": Color(0.17, 0.18, 0.19),     # light neutral grey
	"MARS": Color(0.20, 0.07, 0.05),     # rust red
	"JUPITER": Color(0.19, 0.13, 0.08),  # tan banded
	"SATURN": Color(0.20, 0.17, 0.11),   # pale gold
	"URANUS": Color(0.09, 0.19, 0.20),   # pale cyan
	"NEPTUNE": Color(0.06, 0.10, 0.23),  # deep blue
}
const BODY_TINT_DEFAULT := Color(0.12, 0.13, 0.13)  # unknown body: neutral dark grey


static func body_tint(body_name: String) -> Color:
	return BODY_TINTS.get(body_name.to_upper(), BODY_TINT_DEFAULT)
