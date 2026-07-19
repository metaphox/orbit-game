# Orbit Game — Implementation Plan

Companion to `DESIGN.md`. Milestones are ordered by dependency and de-risking: math core first (testable without an engine loop), then a playable vertical slice, then breadth, then polish. Each milestone ends in something runnable.

## Guiding rules

- The orbital math library is **pure GDScript with no Node dependencies** — plain `RefCounted` classes operating on doubles. Unit-testable headless, reusable, and the only part of the codebase where bugs are silent and catastrophic.
- Everything player-facing is placeholder-ugly until M7. Do not touch shaders before the sim is right.
- Every milestone's "Done when" is checked by playing, not by code review.

## Proposed project layout

```
orbit-game/
  project.godot
  src/
    core/            # pure math, no Nodes: conics, kepler, integrator, frames
    sim/             # Ship, Body, TimeController, SOI logic (Nodes/Resources)
    objectives/      # win/fail predicate classes
    ui/              # HUD, navball, map view widgets
    levels/          # level .tres resources + LevelLoader
    shaders/         # CRT, film grain (M7)
  assets/            # models, textures, audio
  tests/             # GUT unit tests for src/core and objectives
```

---

## M0 — Project skeleton (small)

- Godot 4.x project, folder layout above, main scene with empty game loop.
- GUT (Godot Unit Test) addon wired up; one trivial passing test; headless test run scripted (`godot --headless -s addons/gut/gut_cmdln.gd`).
- Git repo initialized, `.gitignore` for Godot.

**Done when:** `godot --headless` runs the (empty) test suite green.

## M1 — Orbital math core (the risk magnet — do it right)

Pure-GDScript library, fully unit-tested before any rendering exists:

- Kepler elements ↔ state vectors (both directions, all conic types).
- Kepler's equation solvers: elliptic (Newton on E) and hyperbolic (Newton on H); universal-variable formulation is an acceptable alternative if it simplifies edge cases (near-parabolic).
- Closed-form propagation: `propagate(elements, epoch, t) → r, v`.
- Trajectory sampling for orbit-line rendering (adaptive in true anomaly).
- RK4 integrator for powered flight: gravity of parent + thrust along attitude; mass depletion `ṁ = F/(Isp·g₀)`.
- Frame transforms: parent-relative ↔ grandparent-relative (needed for SOI handoff).
- Analytic/root-found event detection on a coasting trajectory: SOI exit, SOI entry of a child body, surface impact, periapsis/apoapsis passage times.

Tests: round-trip conversions, energy/angular-momentum conservation on rails, integrator vs closed-form on unpowered arcs, hyperbolic cases, SOI-crossing detection against brute-force stepping.

**Done when:** test suite covers the above and a scripted "TLI-like" scenario (impulse at periapsis → SOI handoff → bound orbit around second body) produces sane numbers headless.

## M2 — Vertical slice: one level, playable (the proof)

Act 1, Level 1: circular LEO → `OrbitMatch` a higher circular orbit.

- `Body` (Earth, on rails at origin for now), `Ship` with Coasting/Burning state machine over the M1 core.
- Manual controls: pitch/yaw/roll at finite rate, throttle; keyboard.
- Flight view: placeholder ship mesh, textured sphere Earth, chase camera.
- Map view toggle: line-drawn current orbit + ghost target orbit, Ap/Pe readouts. Ugly is fine; correct is mandatory.
- HUD: altitude, Ap/Pe, propellant, derived Δv, mission clock.
- `OrbitMatch` predicate + win screen with propellant-vs-par medal; fail on surface impact; instant retry.
- Floating-origin rendering rig (world shifts around camera) — establish it now, before distances grow.

**Done when:** a first-time player can raise an orbit and win, and the fun of "cutoff timing" is perceptible. **This is the go/no-go gate for the whole game.**

## M3 — Time warp, SOI, the Moon

- `TimeController`: warp ladder, rails warp while coasting (jumping across pre-computed events exactly), physics-warp cap while burning/low.
- Moon on rails; SOI handoff live in gameplay; map view renders multi-body scene + SOI circles.
- `TransferCapture` objective; a rough TLI level to exercise everything.
- Scale-constant tuning pass (orbit periods, warp ladder feel).

**Done when:** fly LEO → Moon capture in under ~10 real minutes, with warp, and the map view stays truthful across the handoff.

## M4 — The flight computer (unlocks)

- SAS hold modes: prograde/retrograde/normal/anti-normal/radial ± target.
- Maneuver nodes: place on predicted orbit, drag prograde/normal/radial handles, predicted post-burn conic (including SOI handoff preview); burn timer + auto-orient; player-executed burn.
- `RulesFlags` plumbing: levels declare which capabilities exist; RCS rotation cost mode.
- Navball (this is really a capability display surface — build it here).

**Done when:** the TLI level is completable both ways: manually (sweaty) and with nodes (planned), and a level file can turn each feature on/off.

## M5 — Full objective vocabulary

- `Rendezvous`: target object on rails, closest-approach markers in map view, distance/rel-velocity win check.
- `AirlessLanding`: terrain = body sphere, radar altitude, touchdown speed limits, simple landing-leg tolerance.
- `EntryCorridor`: periapsis + flight-path-angle band check at atmospheric bodies; off-corridor = fail.
- Fail envelope generalized (mission SOI bounds, "provably unreachable" detector — conservative: flag only when Δv-to-go under ideal impulse exceeds remaining Δv).

**Done when:** one throwaway test level per objective type is winnable and failable.

## M6 — Campaign shell

- Level definitions as `.tres` resources per DESIGN §7; `LevelLoader`.
- Level-select screen (acts, lock state, medals), save file (JSON in `user://`), settings (keybinds, volume).
- Intro-text panel per level (mission briefing).

**Done when:** the game runs start→level→win→next-level→quit→resume without the editor.

## M7 — Aesthetic pass

- Map view/HUD: vector-CRT screen-space shader (phosphor glow, scanlines, slight barrel), amber/green palette, wireframe styling.
- Flight view: NASA-punk ship model (one family), planet textures/atmosphere rim shader, film grain + chromatic bleed post-process, sun flare.
- Audio: analog-synth ambient, engine/RCS loops, radio-blip UI sounds.
- Title screen in-fiction (mission computer boot sequence).

**Done when:** a screenshot of each view is recognizably "this game."

## M8 — Content & tuning

- Author the ~15–20 campaign levels per DESIGN §7; set Δv pars empirically (author's best × margin).
- Difficulty/pacing playtests; tutorialization of Act 1 (diegetic mission-control hints).
- Medal threshold tuning.

**Done when:** an orbital-mechanics-naive playtester clears Act 1 unaided, and Act 3 makes the author sweat.

## M9 — Ship it

- Export presets: macOS (signed/notarized if distributing), Windows, Linux.
- Performance pass (shader cost on weak GPUs), crash/edge-case sweep (warp during handoff, node beyond SOI, zero-prop edge states).
- Optional: test an HTML5 export; ship only if CRT shaders behave in WebGL.
- itch.io page / distribution.

---

## Risk register

| Risk | Mitigation |
|---|---|
| Kepler/conic edge cases (near-parabolic, near-zero inclination) corrupt state | M1 test rigor; universal-variable fallback; clamp/normalize elements on every conversion |
| Rails warp skipping events (SOI, impact) | Event times computed analytically on the trajectory *before* warping; warp jumps to `min(next_event, target_t)` |
| Float precision at Mars distances | Doubles + per-SOI frames in sim; floating origin in render — established in M2, verified in M3 |
| M2 slice isn't fun | It's the go/no-go gate; tune turn rate/thrust/scale before building breadth |
| Node-drag UX is fiddly | Copy KSP's proven interaction verbatim first; innovate only if it still feels bad |
| Scope creep via Act 3 ambitions | Objective vocabulary is closed at M5; new mechanics require editing DESIGN.md first |

## Suggested order of first work sessions

1. M0 skeleton + GUT.
2. M1 elements↔state + elliptic Kepler solver + tests (the deep end — everything sits on this).
3. M1 integrator + event detection + tests.
4. M2 ship + manual flight + flight view.
5. M2 map view + OrbitMatch + win/fail loop. ← *first playable*
