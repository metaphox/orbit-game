# Orbit Game — Design Document

*KSP distilled to "burn fuel to change orbit," in a NASA-punk retro-futurist skin.*

Status: agreed via grilling session, 2026-07-19. This document is the shared understanding; change it before changing the game.

## 1. Pitch

A level-based 3D orbital-mechanics game. Each level you fly a single spacecraft with limited propellant and must reach a target: raise or lower an orbit, rendezvous with a station, transfer to the Moon, land on it, or make it to Mars. Physics is plausible in form (real equations, tuned constants). The fiction and look are late-70s spaceflight: Apollo hardware and green-phosphor flight computers.

## 2. Design pillars

1. **The burn is the game.** Choosing when, in which direction, and for how long to burn is every puzzle's core. Nothing that dilutes this (rocket building, life support, docking minigames) gets in.
2. **Plausible, not pedantic.** Real orbital mechanics — Kepler orbits, patched conics, the rocket equation — with constants tuned for pacing. If a physicist squints, it should hold up in shape, not in SI units.
3. **Failure is information.** Free instant retries, deterministic physics, readable trajectory feedback. The player should always understand *why* an attempt failed.
4. **Two coherent halves of one fiction.** Flight view = NASA-punk hardware. Map view = vector-CRT mission computer. Every UI element belongs to one of these.

## 3. Platform & tech

| Decision | Choice | Rationale |
|---|---|---|
| Engine | Godot 4.x | Editor-driven level authoring, native exports |
| Language | GDScript | 64-bit floats, fastest iteration, keeps web export open later |
| v1 platforms | macOS, Windows, Linux desktop | Mobile explicitly out of scope (touch UX redesign) |
| Physics | Hand-rolled; engine physics unused for orbits | Orbital scales/timesteps rule out engine rigid bodies |

**Precision strategy:** all orbital math in GDScript doubles, in per-SOI local coordinate frames (positions relative to the current parent body). Rendering uses a floating/scaled origin — camera stays near world origin, the world shifts around it — because float32 GPU precision does not survive interplanetary distances.

## 4. Physics model

### 4.1 Patched conics

- Celestial bodies are **on rails**: each has a parent and fixed Kepler elements; positions are closed-form functions of time. Epochs are real, so **transfer windows exist** and levels can start at chosen phase angles.
- A **coasting** ship is a set of Kepler elements + epoch around exactly one parent body. Propagation is closed-form (Kepler's equation; elliptic and hyperbolic cases). Orbits are perfectly stable under any time warp.
- A **burning** ship switches to numerical integration (RK4 over thrust + parent gravity). When thrust ends, state vectors convert back to elements.
- **SOI transitions:** when a coasting trajectory crosses a sphere-of-influence boundary, the ship's state is re-expressed in the new parent's frame and new elements are computed. Detected analytically/root-found on the predicted trajectory, not by per-frame polling, so rails warp can jump across them exactly.

### 4.2 Scale & time

- **Shrunken system**, KSP-style: real body names, radii and orbits roughly 1/10 real scale, gravitational parameters tuned so a low Earth orbit takes **5–10 real minutes**. Exact constants are tuning values, not commitments.
- **Time warp:** unlimited rails warp while coasting (stepped: 1×, 5×, 25×, 100×, …, tuned to make lunar transfers take a coffee-sip and Mars transfers a minute); capped physics warp (≤4×) while burning or inside a "close to surface" envelope.

### 4.3 Propulsion — rocket equation, single stage

Ship parameters: `dry_mass`, `prop_mass`, `thrust`, `isp`. Burning depletes propellant at `thrust / (isp · g₀)`; acceleration rises as the ship lightens. HUD shows propellant fraction **and** remaining Δv (Tsiolkovsky). No staging, ever — one ship per level keeps levels tunable.

### 4.4 Attitude

- Rate-based rotation (finite turn rate — flying, not twitch-aiming).
- **Early levels:** rotation is free.
- **Later levels:** rotation consumes RCS propellant (separate small budget) as an explicit added constraint.
- SAS-style hold modes (prograde/retrograde/normal/anti-normal/radial) exist but are an **unlock** (see §6).

## 5. Objectives — the win-condition vocabulary

Levels compose these predicates:

| Objective | Win condition | Notes |
|---|---|---|
| `OrbitMatch` | Ap/Pe (and optionally inclination) within tolerance bands | Ghost target orbit drawn in map view |
| `TransferCapture` | Bound orbit (e < 1, Ap < SOI) around a specified body | The patched-conic showpiece |
| `Rendezvous` | Distance + relative velocity below thresholds vs target object | No docking; proximity ends it. Needs closest-approach markers |
| `AirlessLanding` | Touchdown on airless body under vertical/horizontal speed limits | Real powered descent; terrain is the body sphere |
| `EntryCorridor` | Periapsis + flight-path angle inside target band at atmospheric body | **No atmosphere is ever simulated**; the capsule "takes it from there" |

**Fail conditions:** surface impact (outside a landing objective), off-corridor atmospheric entry, escaping the mission's SOI envelope. **Running out of propellant is not a fail** — the current trajectory may still win; a "mission unrecoverable" prompt appears only when the objective is provably unreachable or the player concedes.

**Retry:** instant, free, no lives. **Scoring:** medals (bronze/silver/gold) for propellant remaining vs a designer-set Δv par; mission elapsed time displayed but unscored.

## 6. Controls & progression

Two difficulty axes, both act-gated:

- **Capabilities granted:** manual-only piloting → SAS hold modes → maneuver nodes ("the flight computer," an in-fiction avionics upgrade).
- **Constraints imposed:** free rotation → RCS propellant costs.

**Manual flight:** pitch/yaw/roll keys, throttle, live trajectory readout in map view. **Maneuver nodes (once unlocked):** place node on predicted orbit, drag prograde/normal/radial handles, see resulting conic instantly; ship auto-orients to node; player still executes the burn (timing + cutoff skill).

## 7. Campaign

~15–20 handcrafted levels, three linear acts:

- **Act 1 — Earth orbit school.** Raise/lower/circularize, inclination change, phasing + rendezvous. Manual flying only; SAS then maneuver nodes unlock at act boundaries.
- **Act 2 — Lunar program.** Trans-lunar injection, capture, powered landing, return to entry corridor. RCS costs introduced.
- **Act 3 — Interplanetary.** Transfer windows (phase-angle departure), Mars capture on a tight budget, entry corridors. Light branching allowed here.

Level definitions are data (Godot resources): initial ship state + `ShipConfig` + `RulesFlags` (SAS? nodes? RCS cost?) + objective predicates + Δv par + fail envelope + intro text.

## 8. Views & UI

Two views, toggled (M key / tab):

- **Flight view:** 3D exterior chase camera. Ship model, planet, sun. Navball (attitude sphere with prograde/retrograde/target markers), throttle, propellant + Δv gauges, mission clock, warp indicator.
- **Map view:** the mission computer. Orbit conics, SOI circles, ghost target orbits, ship/body markers, node handles, Ap/Pe readouts, closest-approach markers (rendezvous levels). Fully in vector-CRT style.

## 9. Aesthetic — NASA-punk + vector CRT

- **Flight view:** Apollo/Skylab hardware language — off-white hulls, orange accents, foil textures, film grain, subtle chromatic bleed, warm sun flares. Modeled, lit 3D; modest asset count (one ship family, planets, one station).
- **Map view / HUD:** green/amber monochrome phosphor CRT — wireframe conics, glow, scanlines, slight barrel distortion. All screen-space shaders.
- **Audio (deferred until sim works):** analog-synth palette, radio-filtered voice blips, tape-machine UI sounds.

## 10. Domain model

```
Body            μ (grav param), radius, soi_radius, parent, kepler_elements, epoch
                — all celestial motion closed-form on rails

Ship            state: Coasting{elements, epoch, parent} | Burning{r, v, parent}
                dry_mass, prop_mass, thrust, isp
                rcs_budget (when RulesFlags.rcs_cost enabled)
                attitude, turn_rate

Level           initial ship state, ShipConfig, RulesFlags{sas, nodes, rcs_cost},
                objectives: [predicate], dv_par, fail_envelope, intro_text

TimeController  warp ladder; rails warp iff ship Coasting; physics warp cap while
                Burning or below altitude threshold

Campaign        act/level sequence, unlock state, medals, save data

ManeuverNode    anchor (true anomaly on predicted orbit), Δv vector (prograde/normal/radial)
```

**Invariants:** a ship always has exactly one parent body; `Coasting` state never drifts (closed-form only); propellant is monotonically non-increasing; all objective predicates are pure functions of (ship state, time); levels are fully deterministic given player input.

## 11. Out of scope for v1

Atmospheric flight/drag/heating · staging & rocket building · docking · n-body effects (Lagrange points, free returns) · mobile · sandbox mode (v2 candidate) · life support/comms/thermal.

## 12. Deferred decisions

- Exact scale constants and warp ladder (tune in M2/M3 playtesting).
- Whether Act 3 gets a second destination (Venus) — content-budget call.
- Web export (test an HTML5 build mid-project; ship it only if CRT shaders behave in WebGL).
- Narrative framing/voice (mission-control flavor text) — after the vertical slice.
