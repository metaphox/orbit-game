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
| **INK** | bone | `#f2ecdb` | labels |
| **DIM** | grey-green | `#7f877d` | secondary structure — orbit tracks, grid, body-name labels |
| **SOI** | dark orange | `#c9722b` | sphere-of-influence boundaries (drawn dotted) |
| **VOID** | near-black | `#050705` | background |

**Rule of loud:** one saturated field per view. Green owns your live telemetry, amber owns intent, cyan owns the target, red fires only when something can end the mission.

## Celestial body tints

Bodies render as a **dark, faintly-tinted disc — no outline**. The tint is a low-saturation dark cast of the real world's colour, enough to identify which body you're looking at without competing with the orbits and markers drawn over it. Defined in `Palette.BODY_TINTS`, keyed by body name; unknown bodies fall back to a neutral dark grey.

| Body | Tint feel | Hex |
|---|---|---|
| Sun (`SUN`/`SOL`) | warm solar amber | `#472f0a` |
| Mercury | grey-brown | `#241f1a` |
| Venus | pale sulphur cream | `#332b1a` |
| Earth | green-blue ocean | `#0d2a2e` |
| Moon | light neutral grey | `#2b2e30` |
| Mars | rust red | `#33120d` |
| Jupiter | tan banded | `#302114` |
| Saturn | pale gold | `#332b1c` |
| Uranus | pale cyan | `#172f33` |
| Neptune | deep blue | `#0f1a3b` |

Further bodies (e.g. Jupiter's moons) get their tint added here when a level first needs them.

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

The schematic mission-computer map, top-right of the HUD. A slightly-tilted top-down orthographic view of the current sphere-of-influence, **prograde-up** (your velocity vector points to the top of the map — a stable reference that doesn't spin when you re-point the nose). Rendered as layer-2 3D geometry into a `SubViewport` (`map_view.gd`), with a 2D marker/label overlay projected through the same camera (`minimap_overlay.gd`).

### What it shows
- **Your orbit** — solid LIVE-green conic.
- **Target** — TARGET-cyan ring (orbit-match / entry corridor) or point (rendezvous station), matching the objective.
- **Bodies** — the focused body and any moons as dark tinted discs (see Celestial body tints), with DIM (solid) orbit tracks.
- **SOI boundaries** — each body's sphere of influence is a **dotted dark-orange ring** (its own colour code), visually distinct from the solid orbit lines and planet tracks: it's the patched-conic handoff line you cross to switch which body you're flying under.
- **Ship** — a LIVE-green 3D dart (bright nose tip + dorsal fin) oriented by the ship's **real attitude**. Because the map is prograde-up, nose-prograde points up, retrograde down, radial toward/away from the body, and normal/antinormal toward/away from you (foreshortened along the view axis). This is how you read where the nose is aimed for a burn.
- **Moving objects** — the ship and any tracked flying object (the rendezvous station now; other traffic later) are 3D glyphs **auto-scaled to a constant on-screen size**, so they stay legible at any zoom, and drawn over everything so they never hide behind a body. Ship = green attitude dart; tracked object = cyan diamond (with its `TGT`/name label from the marker overlay).
- **Marked points** — coloured dots with tiny labels per the vocabulary above: `AP`, `PE`, `NODE`, `TGT`, moon names. `AP`/`PE` are hidden when the orbit is effectively circular (they'd coincide and mean nothing).

### Zoom
The map **centres on the current parent body** (Earth, or the Moon once inside its SOI) and frames that local orbit — no more dead black margin around a tiny orbit.

Three controls, bottom-right corner of the panel:
- **`⊙` AUTO** — continuously fits the view to your current orbit + target (default).
- **`+`** — zoom in one step (switches to manual).
- **`−`** — zoom out one step (switches to manual).

Manual zoom is clamped between roughly the body's surface and the draw limit. Zoom changes ease in rather than snapping.
