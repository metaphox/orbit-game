# Limited Propellant — UI Design

The visual language for the HUD and instruments. Aesthetic target is **NASA-punk / "ORBITAL OS"** (see `ref/design-ref.html`): black void, phosphor green, hazard amber, sparing red — bold, high-contrast, readable through a burn.

This document grows one instrument at a time. Each section is the source of truth for that surface; change it before changing the code. The palette and label conventions are meant to be **consistent across every view** — a green dot means the same thing on the minimap, the flight view, and any future planner.

## Palette (semantic — one meaning per colour)

Defined in code as `Palette` (`src/ui/palette.gd`); keep the two in lockstep.

| Role | Colour | Hex | Used for |
|---|---|---|---|
| **LIVE** | phosphor green | `#4dffa0` | your current state — own orbit, apoapsis, periapsis, ship marker |
| **INTENT** | hazard amber | `#ffb100` | planned intent — maneuver node, planned burn |
| **TARGET** | cyan | `#4fd8e2` | the objective — target orbit, target point, station |
| **WARNING** | red | `#ff3b2a` | imminent danger — impact / collision corridor (rare, loud) |
| **INK** | bone | `#f2ecdb` | labels, body outlines |
| **DIM** | grey-green | `#7f877d` | secondary structure — moon tracks, SOI rings, grid |
| **BODY** | neutral grey | `#8a9188` | celestial-body fill (moons) |
| **VOID** | near-black | `#050705` | background |

**Rule of loud:** one saturated field per view. Green owns your live telemetry, amber owns intent, cyan owns the target, red fires only when something can end the mission.

## Point-label vocabulary

Two-to-four-character tags, drawn in the point's own colour. Consistent everywhere a point is marked.

| Tag | Meaning | Colour |
|---|---|---|
| `AP` | apoapsis of your orbit | LIVE |
| `PE` | periapsis of your orbit | LIVE |
| `NODE` | maneuver node | INTENT |
| `TGT` | target point / station | TARGET |
| *(body name)* | a moon / body | DIM |

---

## Minimap

The schematic mission-computer map, top-right of the HUD. A slightly-tilted top-down orthographic view of the current sphere-of-influence, heading-up (your nose points to the top of the map). Rendered as layer-2 3D geometry into a `SubViewport` (`map_view.gd`), with a 2D marker/label overlay projected through the same camera (`minimap_overlay.gd`).

### What it shows
- **Your orbit** — solid LIVE-green conic.
- **Target** — TARGET-cyan ring (orbit-match / entry corridor) or point (rendezvous station), matching the objective.
- **Bodies** — the focused body (INK outline) and any moons (BODY dots, DIM orbit tracks, DIM SOI rings).
- **Ship** — a LIVE-green directional wedge (shows heading; the map rotates so it points up).
- **Marked points** — coloured dots with tiny labels per the vocabulary above: `AP`, `PE`, `NODE`, `TGT`, moon names. `AP`/`PE` are hidden when the orbit is effectively circular (they'd coincide and mean nothing).

### Zoom
The map **centres on the current parent body** (Earth, or the Moon once inside its SOI) and frames that local orbit — no more dead black margin around a tiny orbit.

Three controls, bottom-right corner of the panel:
- **`⊙` AUTO** — continuously fits the view to your current orbit + target (default).
- **`+`** — zoom in one step (switches to manual).
- **`−`** — zoom out one step (switches to manual).

Manual zoom is clamped between roughly the body's surface and the draw limit. Zoom changes ease in rather than snapping.
