# Orbit Game — Design Document

*KSP distilled to "burn fuel to change orbit," in a NASA-punk retro-futurist skin.*

Status: agreed via grilling session, 2026-07-19; updated 2026-07-20 to match what was actually built through M9 and the post-ship feature rounds (pause/save, profiles, orbit marks, toolbar). This document is the shared understanding; change it before changing the game. Where implementation diverged from the original plan, that's called out explicitly with the reason — this is a record of decisions, not just a spec.

## 1. Pitch

A level-based 3D orbital-mechanics game. Each level you fly a single spacecraft with limited propellant and must reach a target: raise or lower an orbit, rendezvous with a station, transfer to the Moon, land on it, or make it to Mars. Physics is plausible in form (real equations, tuned constants). The fiction and look are late-70s spaceflight: Apollo hardware and green-phosphor flight computers.

## 2. Design pillars

1. **The burn is the game.** Choosing when, in which direction, and for how long to burn is every puzzle's core. Nothing that dilutes this (rocket building, life support, docking minigames) gets in.
2. **Plausible, not pedantic.** Real orbital mechanics — Kepler orbits, patched conics, the rocket equation — with constants tuned for pacing. If a physicist squints, it should hold up in shape, not in SI units.
3. **Failure is information.** Free instant retries, deterministic physics, readable trajectory feedback. The player should always understand *why* an attempt failed.
4. **Two coherent halves of one fiction.** Flight/orbit views = NASA-punk hardware (starfield, film grain, modeled ship). Instrument surfaces — the minimap and the ship's status hologram — = vector-CRT mission computer (scanlines, phosphor glow, barrel curve). This held up through implementation even though the original "flight view vs. full-screen map view" split (§8) didn't — the CRT treatment moved to specific *instruments* rather than an alternate full-screen mode.

## 3. Platform & tech

| Decision | Choice | Rationale |
|---|---|---|
| Engine | Godot 4.7 | Editor-driven level authoring, native exports |
| Language | GDScript | 64-bit floats, fastest iteration, keeps web export open later |
| v1 platforms | macOS, Windows, Linux desktop | Mobile explicitly out of scope (touch UX redesign). All three actually export clean via `tools/export.sh` against the official 4.7.1 templates — verified, not just planned |
| Physics | Hand-rolled; engine physics unused for orbits | Orbital scales/timesteps rule out engine rigid bodies |
| Window | Windowed (borderless) fullscreen by default, 1024×768 floor | Enforced two ways: project display settings and a direct `DisplayServer` call, so the floor holds even if the project setting doesn't apply on some platform |

**Precision strategy:** all orbital math in GDScript doubles, in per-SOI local coordinate frames (positions relative to the current parent body). Rendering uses a floating/scaled origin — the ship renders at exactly `(0,0,0)` and the world shifts around it — because float32 GPU precision does not survive interplanetary distances. This paid off directly: the orbit-view camera "follows the ship" (§8) simply by orbiting/looking at the render origin, no ship-tracking logic needed.

## 4. Physics model

### 4.1 Patched conics

- Celestial bodies are **on rails**: each has a parent and fixed Kepler elements; positions are closed-form functions of time. Epochs are real, so **transfer windows exist** and levels can start at chosen phase angles.
- A **coasting** ship is a set of Kepler elements + epoch around exactly one parent body. Propagation is closed-form (Kepler's equation; elliptic and hyperbolic cases). Orbits are perfectly stable under any time warp.
- A **burning** ship switches to numerical integration (RK4 over thrust + parent gravity). When thrust ends, state vectors convert back to elements.
- **SOI transitions:** when a coasting trajectory crosses a sphere-of-influence boundary, the ship's state is re-expressed in the new parent's frame and new elements are computed. Detected analytically/root-found on the predicted trajectory, not by per-frame polling, so rails warp can jump across them exactly.
- **Nesting is not hardcoded to "Earth is always root."** The Mars level puts the Sun at the root with Earth and Mars as children, and the ship starts inside Earth's SOI — i.e. one hop deeper than every Earth/Moon level. This worked with zero engine changes, which is the strongest validation the patched-conic core generalizes correctly rather than being special-cased for the Earth–Moon pair it was first built against.
- **World-frame plane crossings** (`OrbitElements.xz_plane_crossings`): a body's classical inclination (`inc`) is measured against the astrodynamics-standard +Z pole internally, which is *not* this game's "up" (+Y) — nothing surfaced that mismatch until the plane-change level needed ascending/descending node markers. Rather than touch the internal convention (highest-risk file in the project, extensively tested against that convention already), a separate `plane_normal` field and a dedicated analytic method were added for anything that needs "tilt relative to what the player actually sees."

### 4.2 Scale & time

- **Shrunken system**, KSP-style: real body names, radii and orbits roughly 1/100 real scale (not 1/10 as first floated — the constant that actually shipped), gravitational parameters tuned so a low Earth orbit takes on the order of 5–7 real minutes at 1× warp. Exact constants are tuning values, not commitments.
- **Time warp ladder (as shipped):** `1×, 5×, 10×, 25×, 50×, 100×, 200×, 500×, 1000×` — 9 steps, keys `1`–`9` jump straight to the matching step, `-`/`=` walk one step at a time. (An earlier `1,2,4,8,25,100,500,2500` version was replaced; the 9-step round-number ladder reads better on the warp indicator and matches numbered-key muscle memory 1:1.) Rails warp is clamped to the next precomputed event (impact, SOI boundary, or a scheduled maneuver node's time) so it can never warp *through* something that mattered — it lands within about a millisecond of the event and drops to 1×.
- No separate "physics warp cap while burning" was built as a distinct mode — burns simply can't be warped at all (`warp_index` is forced to 0 the moment throttle > 0), which is simpler than the originally-planned capped-physics-warp tier and never felt like a gap.

### 4.3 Propulsion — rocket equation, single stage

Ship parameters: `dry_mass`, `prop_mass`, `thrust`, `isp`. Burning depletes propellant at `thrust / (isp · g₀)`; acceleration rises as the ship lightens. HUD shows propellant fraction **and** remaining Δv (Tsiolkovsky). No staging, ever — one ship per level keeps levels tunable.

### 4.4 Attitude

- Rate-based rotation (finite turn rate — flying, not twitch-aiming), unchanged from plan.
- **RCS/rotation-cost constraint was never built.** The original plan called this the second difficulty axis ("constraints imposed": free rotation → RCS propellant cost on later levels). It was speced but not implemented in any of the 7 shipped levels — rotation is free throughout the whole campaign. The capability-unlock axis (manual → SAS → maneuver nodes, below) turned out to carry the difficulty curve on its own without this ever reading as a missing piece. Formally moved to §11 (out of scope) rather than left as stale "planned" text.
- SAS-style hold modes (prograde/retrograde/normal/anti-normal/radial in/out) exist and are an **unlock**, gated per-level by `LevelDef.sas_enabled` (see §6).

## 5. Objectives — the win-condition vocabulary

Levels compose these predicates (all five originally planned types shipped, unchanged in shape):

| Objective | Win condition | Notes |
|---|---|---|
| `OrbitMatch` | Ap/Pe (and optionally inclination, via `plane_normal`) within tolerance bands | Dashed target ring in-world; optional inclination gate powers the plane-change level |
| `TransferCapture` | Bound orbit (e < 1, Ap < SOI) around a specified body | The patched-conic showpiece; phase-angle/burn-window guidance in the HUD works from any nesting depth (see §4.1) |
| `Rendezvous` | Distance + relative velocity below thresholds vs target object | No docking; proximity ends it. Closest-approach solver and its in-world marker shipped (§8) — the original doc flagged this as still-needed, it's done |
| `AirlessLanding` | Touchdown on airless body under vertical/horizontal speed limits | Real powered descent; terrain is the body sphere |
| `EntryCorridor` | Periapsis inside a target radius band at an atmospheric body | **No atmosphere is ever simulated**; the capsule "takes it from there". Simplified from the original "periapsis + flight-path angle" to periapsis-band only — flight-path angle never ended up necessary for a readable objective |

**Fail conditions:** surface impact (outside a landing objective), mission-envelope escape (root-frame distance past a per-level radius). **Running out of propellant is not a fail** — the current trajectory may still win. The originally-planned "mission unrecoverable" provable-unreachability detector was **not built**; instant free retry (now via the pause menu's Restart, not just a bare keypress) covers the practical need without it.

**Retry:** instant, free, no lives, reachable from the pause menu. **Scoring:** medals (bronze/silver/gold) for propellant remaining vs a designer-set Δv par; mission elapsed time displayed but unscored.

## 6. Controls & the flight computer

Manual flying is the baseline; SAS hold modes and maneuver nodes are per-level unlocks (`LevelDef.sas_enabled` / `nodes_enabled`) rather than a strict act-boundary gate — Act 1's plane-change level, for instance, grants SAS but not nodes, tuned per-level rather than per-act.

**One deliberate deviation from the original plan:** maneuver nodes were planned as a mouse-drag UI ("drag prograde/normal/radial handles"). What shipped is **keyboard-driven node editing** instead — brackets adjust the node's time, arrow keys adjust prograde/normal delta-v, `O`/`P` adjust radial, Shift held gives a coarse step. This wasn't a scope cut so much as a better fit for a keyboard-first control scheme that was already true of everything else in the game (attitude, throttle, warp, SAS); it's also trivially unit-testable headless, which a drag gesture wouldn't be. A predicted post-burn conic (cyan ghost line) still renders live as the plan changes, matching the original intent of "see the resulting conic instantly."

**Full keybind map as shipped:**

| Group | Keys | Action |
|---|---|---|
| Attitude | `W`/`S`, `A`/`D`, `Q`/`E` | pitch, yaw, roll |
| Throttle | `Shift`/`Ctrl` (hold), `Z`, `X` | up/down, max, cut |
| Time warp | `1`–`9`, `-`/`=` | jump to warp step, walk one step |
| Pause | `Space` or `0` (quick toggle), `Esc` (opens the pause menu) | see §7 |
| View | `Tab`, mouse-drag, wheel/trackpad | toggle chase↔orbit view, rotate, zoom (orbit view only) |
| View reset | `R` | resets the active camera to its default framing *while flying or paused*; on the win/fail screen the same key instead restarts the mission, matching what's printed on screen there — a context-sensitive rebind, not two different keys |
| SAS locks | `F` prograde, `B` retrograde, `N` normal, `G` anti-normal, `U`/`I` radial out/in, `T` off | auto-orient and hold; pressing the same lock again releases it |
| Maneuver node | `Enter` add, `Backspace` delete, `[`/`]` time, `↑`/`↓` prograde, `←`/`→` normal, `O`/`P` radial, `V` hold-toward-node | Shift = coarse step |

**Toolbar:** every keybind above except `1`–`9` (the warp indicator already covers those) is also a real clickable button — two rows, bottom-center of the HUD, visible in both the chase and orbit views since the HUD is a plain overlay not tied to either camera. A click constructs the same key event a physical press would and feeds it through the same input handler, so there's exactly one code path for "did the player do X," whether by keyboard or mouse. `Shift`/`Ctrl` buttons press-and-hold (`button_down`/`button_up`) rather than tap, matching the physical keys' held semantics.

## 7. Profiles, save/resume, and pause

None of this section existed in the original design — it was added in full after the vertical slice shipped.

**Profiles.** Up to 5 named profiles live in a single save file (no per-profile save files). Each tracks its own unlocked levels and best medal per level, independently. A title screen is the actual entry point: Continue / New Profile / Load Profile / Settings / Credits / Quit, navigable by number key or arrow-keys-plus-Enter. Continue resumes the active profile's in-progress flight directly if one exists (see below), otherwise it goes to mission select.

**Mid-mission save.** The pause menu's "Save Progress" captures the ship's *full* state — position, velocity, attitude, propellant, current SOI, SAS mode, and any planned maneuver node — onto the active profile. Bodies are never snapshotted: since they're on rails, `sim_time` alone reconstructs every body's position on load, which kept the save payload small and made "does a save round-trip exactly" a clean, fully headless-testable question (down to re-loading the profile store from disk and resuming through it, not just an in-memory check). A win clears the save for that mission.

**Pause.** `Esc` opens a menu (Resume / Save Progress / Restart / Quit to Mission Select), pausing the sim; `Space`/`0` quick-toggle a pause without opening the menu, and also close the menu if it's open. Both freeze the star-dust particle system explicitly — it runs its own render-time clock independent of the sim, so pausing the *sim* alone didn't originally stop the *dust*.

**Settings.** Deliberately minimal: one real toggle (the M7 visual-effects layer — film grade + CRT overlays), rather than fabricated placeholder options. More settings join here as systems that need them (audio, rebindable keys) get built.

## 8. Views & UI

**This is the section that changed shape the most from the original plan.** The original design called for two alternate full-screen views (3D flight view / 2D-schematic map view, toggled). What shipped instead:

- **Chase view** (default): 3D exterior camera following the ship, mouse-drag orbitable around it.
- **Orbit view** (`Tab`): *also* a real 3D camera, not a flat schematic — it orbits and looks at the ship (which, thanks to the floating origin, is always exactly at the render origin, so "track the ship" needed no ship-tracking code at all), zoomable by mouse wheel or trackpad gesture (two-finger scroll and pinch). This is where the orbit actually reads as a shape: the glowing trajectory line, the dashed target ring, and every orbit mark below live here.
- **Minimap**: a small always-visible picture-in-picture schematic, top-right corner, in both of the views above. This is the part that actually survived from the original "map view" concept — just demoted from a full alternate screen to a persistent corner instrument.

The reasoning for the pivot: a flat 2D schematic map view never got built past a placeholder before the question came up directly of "let the camera zoom out into the same 3D world instead of cutting to a different screen" — and once the floating-origin trick made "camera follows the ship" nearly free, there was no real cost to keeping everything in one continuous 3D space. The vector-CRT aesthetic that was meant for the map view moved onto the instruments that still read as physical mission-computer screens: the minimap and the ship's status hologram (§9).

**Orbit marks** (in-world, orbit-view only — meaningless at chase-cam range where the whole orbit shape isn't visible anyway): small colored dots on the current trajectory —

| Mark | Color | Source |
|---|---|---|
| Apoapsis / Periapsis | sky blue / gold | always shown on an elliptical/any orbit |
| Ascending / descending node | violet / dark violet | `OrbitElements.xz_plane_crossings` — world-plane crossings, not the orbit's own tilt |
| Predicted surface impact | red | doubles as a crash warning and a landing aid |
| Target-SOI encounter | white | Moon/Mars transfer missions |
| Rendezvous closest approach | pink | reuses the same solver the HUD text already used |

**Ship posture marker.** The orbit-view ship marker was originally a plain sphere — pure location, no orientation. It's now a small directional shape (hull, nose cone, an off-axis wing so roll reads too, not just pitch/yaw) whose basis follows `ship.attitude` every frame, scaled to keep a constant *angular* size regardless of zoom (matching how the trajectory line itself stays legible at any distance).

**HUD instruments (chase and orbit view alike, since HUD isn't tied to either camera):** status/objective/engine text blocks, the minimap, a time-warp readout under it, the ship's status hologram (billboarded 3D panel floating beside the hull: acceleration dial, propellant ring, Δv), and the toolbar (§6).

## 9. Aesthetic — NASA-punk + vector CRT

- **World (chase + orbit views):** Apollo/Skylab hardware language on the ship — off-white hull, orange nose accent — against a procedural starfield sky (hashed voxel grid, no texture assets) and a whole-screen film grade (grain, vignette, warm tint) that reads as aged hardware footage, not a modern render. Planets get a cheap rim/fresnel glow for an atmosphere hint.
- **Instrument screens (minimap, status hologram):** green/amber monochrome phosphor CRT — scanlines, glow, slight barrel distortion, faint flicker — rendered as a post-process inside each instrument's own `SubViewport`, so it composites into that instrument specifically rather than the whole screen.
- **Settings toggle:** the whole effects layer (film grade + CRT) can be switched off from Settings (§7) — a straightforward accessibility/preference option once it existed as a distinct visual layer.
- **Audio:** still fully deferred, unchanged from the original plan. Analog-synth palette, radio-filtered voice blips, tape-machine UI sounds remain the intent whenever it gets built.

## 10. Domain model

Reflects the classes as shipped, not the original sketch (some names/shapes changed — e.g. `TimeController` was never a distinct object, it's a few fields on the level orchestrator; `ManeuverNode` gained a `remaining` vector that depletes as a burn executes).

```
BodyDef         name, mu, radius, soi_radius, parent, orbit (OrbitElements around
                parent; null for the root), color
                — position_at(t)/velocity_at(t) recurse through parent, so
                nesting depth isn't hardcoded (the Sun/Earth/Mars case)

ShipSim         body (current parent), elements, r, v, attitude, throttle,
                dry_mass, prop_mass, thrust_max, isp, flight_state
                  (Coasting: elements valid | Burning: r,v integrated live),
                sas_mode, node: ManeuverNode, revision (bumps on refit)
                serialize()/apply_serialized() for the mid-mission save (§7)

ManeuverNode    t_node, prograde/normal/radial (planned dv), remaining
                (world-frame dv still to burn — depletes live, defines the
                node-hold SAS direction)

LevelDef        title, body (root), moons: [BodyDef], start_body (may be a
                moon, not just the root), start_radius, ship stats, objective,
                dv_par, map_extent, draw_limit, fail_radius,
                sas_enabled, nodes_enabled

Objective       is_met(ship), describe(), status_lines(ship),
                trajectory_closeness(ship) -> 0..1, contact_result(ship)
                  five concrete subclasses, see §5

Campaign        static level registry + act grouping; level_count/level_at/
                order/next_after/title — pure functions over the registry,
                no save state of its own

Profile         profile_name, unlocked: {index: true}, medals: {index:
                {medal, dv}}, mission_save: Dictionary|null
                record_win() unlocks the next campaign-order level and
                clears mission_save for that index

ProfileStore    up to 5 Profiles + last_active_name + Settings.effects_enabled,
                one JSON file (user://save.json); validate_new_name() is the
                one place profile-creation rules live, callable without any
                UI/keystroke simulation
```

**Invariants (unchanged from the original plan, still hold):** a ship always has exactly one parent body; `Coasting` state never drifts (closed-form only); propellant is monotonically non-increasing; all objective predicates are pure functions of (ship state, time); levels are fully deterministic given player input.

## 11. Out of scope for v1

Atmospheric flight/drag/heating · staging & rocket building · docking · n-body effects (Lagrange points, free returns) · mobile · sandbox mode (v2 candidate) · life support/comms/thermal · **RCS/rotation-cost constraint** (speced in §4.4 originally, never implemented — see that section for why it didn't end up mattering) · provable-unreachability "mission unrecoverable" detector (§5) · rebindable keys (the toolbar buttons and the keyboard are both hardcoded to the same layout; an `InputMap` migration would be the natural way in if this becomes a real ask).

## 12. Resolved during implementation

Decisions the original doc left open, now settled by what shipped:

- **Scale constants and warp ladder:** 1/100 length scale; 9-step round-number ladder `1,5,10,25,50,100,200,500,1000×` (§4.2).
- **Act 3 second destination (Venus):** not added. The roster shipped at **7 levels across 3 acts** (Earth orbit school ×3, lunar program ×3, interplanetary ×1 — Mars only), well short of the original 15–20 stretch goal. That gap is deliberate, not an oversight: DESIGN's own §on content said pars need to be "tuned empirically" via real playtesting, which further autonomous content-authoring can't responsibly simulate. 7 levels covering every act and every objective type was treated as the honest, defensible stopping point for a vertical slice; more levels are a natural next task for a human doing real playtesting, not a backlog item to keep grinding through alone.
- **Web export:** still not attempted. Neither shipped nor explicitly re-deferred by a real test — genuinely just not gotten to.
- **Narrative framing/voice:** still not started, unchanged from "after the vertical slice."
- **Map view fate:** resolved differently than either original option — see §8's rewrite.
