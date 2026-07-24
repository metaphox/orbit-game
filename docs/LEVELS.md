# Making custom levels

You can add your own missions to **Limited Propellant** — no coding, no Godot. A
level is a small text file (JSON) you drop in a folder. It shows up in-game under
**MISSIONS ▸ COMMUNITY**.

## Where to put files

Put your `.json` (and an optional same-named `.md` brief) in the **mods/levels**
folder:

| Platform | Folder |
|---|---|
| Windows / Linux (portable zip) | `mods/levels/` next to the game executable |
| Any platform | `Documents/Limited Propellant/mods/levels/` |
| macOS | `~/Documents/Limited Propellant/mods/levels/` |

The Documents folder is created for you on first launch with a `README.txt` and an
`example.json`. The quickest way there: the **OPEN MODS FOLDER** button at the
bottom of the mission list.

The filename (without extension) is the level's ID. `my_cool_mission.json` →
`my_cool_mission.md` is its brief.

## A complete example

```jsonc
{
  "title": "COMMUNITY: HIGH ELLIPSE",
  "system": "EARTH",                       // the body you orbit (see catalog below)
  "start": { "periapsis_km": 70, "apoapsis_km": 300, "inclination_deg": 20 },
  "ship":  { "dry_mass": 1000, "prop_mass": 400, "thrust": 6000, "isp": 82 },
  "objective": { "type": "orbit_match", "radius_km": 150, "tolerance_km": 3 },
  "dv_par": 220,          // Δv (m/s) for a GOLD medal; SILVER ≤ par×1.2
  "difficulty": 3         // 1–4 pips, cosmetic
}
```

The mission title shows the part after the colon (`HIGH ELLIPSE`). All distances
are **kilometres**, angles **degrees**, speeds **m/s**.

## The body catalog

Reference bodies by name — you never type masses or radii. Available:

- **Star:** `SOL`
- **Planets:** `MERCURY` `VENUS` `EARTH` `MARS` `JUPITER` `SATURN` `URANUS` `NEPTUNE` `PLUTO`
- **Moons:** `MOON` (Earth) · `PHOBOS` `DEIMOS` (Mars) · `IO` `EUROPA` `GANYMEDE` `CALLISTO` (Jupiter) · `TITAN` (Saturn) · `TRITON` (Neptune)

`system` is the root body (the centre of the level). List any other bodies in
play under `bodies`. A body's real parent comes from the catalog, so to fly at
one of Jupiter's moons, set `system: "SOL"` and list `JUPITER` + the moon:

```jsonc
"system": "SOL",
"bodies": [
  { "name": "JUPITER" },
  { "name": "IO" },                        // real: has gravity, can be a target
  { "name": "EUROPA", "decorative": true } // scenery: drawn, never captures you
]
```

Per-body options: `"phase_deg"` (where it sits in its orbit at t=0),
`"decorative": true` (see below).

> Scale note: the game uses a compact, playable solar system (not real
> distances). Values for the outer planets/moons are approximate and may be
> tuned in future updates.

## `start` — where you begin

`start.body` defaults to `system`. Give a shape:

```jsonc
"start": { "radius_km": 70 }                    // circular
"start": { "periapsis_km": 70, "apoapsis_km": 300 }   // ellipse
"start": { "periapsis_km": 70, "eccentricity": 1.3 }  // open / hyperbolic
```

Optional on any: `"altitude_km"` (instead of a radius — height above the
surface), `"at": "apoapsis"` (start at the far point instead of periapsis),
`"inclination_deg"` (tilt the plane), `"retrograde": true`.

## `objective` — the win condition

| `type` | Fields | Win when… |
|---|---|---|
| `orbit_match` | `radius_km`, `tolerance_km`, opt `inclination_deg` + `inclination_tolerance_deg` | your circular orbit matches the target ring (and plane) |
| `rendezvous` | `station_radius_km`, `station_phase_deg` | you close on the station slowly |
| `transfer_capture` | `target` (a body name) | you capture into orbit around `target` |
| `airless_landing` | `target` (a body name) | you touch down gently on `target` |
| `entry_corridor` | `periapsis_km`, `tolerance_km` | your periapsis drops into the reentry band |

`transfer_capture` / `airless_landing` targets must be **real** bodies (not
decorative), listed in `bodies`.

## `decorative` bodies (scenery)

Mark a body `"decorative": true` to show it for context without simulating it —
you can never be captured by it and it can't be a target. Great for showing all
of Jupiter's moons while only one is the mission, or a distant Earth for scale.

## Other fields

- `"ship"`: `dry_mass` (kg), `prop_mass` (kg), `thrust` (N), `isp` (s).
- `"avionics"`: `{ "sas": true, "nodes": true }` — grant the attitude autopilot / maneuver nodes.
- `"rewind_budget"`: number of do-overs (default 1).
- `"map_extent_km"`, `"draw_limit_km"`, `"fail_radius_km"`: minimap size / trajectory
  clip / mission-envelope radius. Optional; `fail_radius_km` of 0 means no envelope.

## Limits

A level may have at most **48 bodies** total and **12 active** (non-decorative)
bodies — mark distant scenery `decorative` to stay under the active cap. A file
that fails to load is skipped (the rest still work); the error names the problem.

## The brief (optional `.md`)

Alongside `my_mission.json`, a `my_mission.md` is shown as the **FLIGHT PLAN**.
Plain text with line breaks; a little markdown is supported:

```
Fly a Hohmann transfer to the higher ring.
**Burn prograde** at periapsis, then circularize.
*Trim in short pulses — overshoot and you fall short.*
```

`**bold**` and `*italic*` render; nothing else. Keep it to a few concise lines.

## Progress

Community missions are always unlocked and tracked separately from the campaign
(your best Δv / medal per mission is saved). They don't have a mid-mission save.
