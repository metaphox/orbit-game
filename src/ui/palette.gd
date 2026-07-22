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
const INK := Color("f2ecdb")      # labels, body outlines
const DIM := Color("7f877d")      # secondary structure: moon tracks, SOI rings, grid
const BODY := Color("8a9188")     # neutral celestial-body fill (moons)
