class_name Palette
extends RefCounted
## The shared NASA-punk semantic palette (see UI-DESIGN.md). One meaning per
## colour, consistent across every view: green = live/own, amber = planned
## intent, cyan = target, red = danger. Only the minimap consumes this so far;
## other views will migrate onto it. Keep this and UI-DESIGN.md in lockstep.

const VOID := Color("050705")     # background void
const LIVE := Color("4dffa0")     # your current state: own orbit, apoapsis, periapsis, ship
const INTENT := Color("ffb100")   # planned intent: maneuver node, planned burn
const TARGET := Color("4fd8e2")   # the objective: target orbit / target point / station
const WARNING := Color("ff3b2a")  # imminent danger: impact / collision (rare, loud)
const INK := Color("f2ecdb")      # labels
const DIM := Color("7f877d")      # secondary structure: orbit tracks, grid
const SOI := Color("c9722b")      # sphere-of-influence boundary: dotted dark orange (its own code)

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
