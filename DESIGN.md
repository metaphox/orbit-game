# Limited Propellant — Design Document

*KSP distilled to "burn fuel to change orbit," in a NASA-punk retro-futurist skin.*

Status: agreed via grilling session, 2026-07-19; updated 2026-07-20 to match what was actually built through M9 and the post-ship feature rounds (pause/save, profiles, orbit marks, toolbar); 2026-07-23 rotational inertia + RCS/camera feedback (§4.4). This document is the shared understanding; change it before changing the game. Where implementation diverged from the original plan, that's called out explicitly with the reason — this is a record of decisions, not just a spec.

> **Writing code here?** Read [`AGENTS.md`](AGENTS.md) first — the contributor & agent guide covers the conventions this design depends on: architecture invariants (doubles, floating origin, on-rails determinism), the swappable-theme rule (no standalone colours in levels or UI — everything flows through `RenderTheme` / `Palette` / `UiTheme`), the design references (`ref/*.html`, `UI-DESIGN.md`), tech-debt discipline (`TECH_DEBTS.md`), and testing. `DESIGN.md` is *what* we build; `AGENTS.md` is *how*.

**The game is not finished.** The current 7-level roster is a testing/vertical-slice set, not the shipped campaign — 15–20 levels is still the goal. RCS/rotation-cost is still planned for later levels, not cut (§4.4). Both are open work, not settled scope decisions; see §13.

## 1. Pitch

A level-based 3D orbital-mechanics game. Each level you fly a single spacecraft with limited propellant and must reach a target: raise or lower an orbit, rendezvous with a station, transfer to the Moon, land on it, or make it to Mars. Physics is plausible in form (real equations, tuned constants). The fiction and look are late-70s spaceflight: Apollo hardware and green-phosphor flight computers.

**The name.** *Limited Propellant* names the one constraint every level is built around — a fixed tank and a Δv budget you cannot exceed. Its initials, **LP**, also read as **Lambert's Problem**, the classic orbital-mechanics task of finding the transfer orbit that connects two positions in a given time — which is, under the hood, exactly what every intercept and transfer in the game asks you to solve. The double meaning is deliberate: a plain statement of the mechanic on the surface, an insider handshake for anyone who knows the math.

## 2. Design pillars

1. **The burn is the game.** Choosing when, in which direction, and for how long to burn is every puzzle's core. Nothing that dilutes this (rocket building, life support, docking minigames) gets in.
2. **Plausible, not pedantic.** Real orbital mechanics — Kepler orbits, patched conics, the rocket equation — with constants tuned for pacing. If a physicist squints, it should hold up in shape, not in SI units.
3. **Failure is information.** Free instant retries, deterministic physics, readable trajectory feedback. The player should always understand *why* an attempt failed.
4. **Two coherent halves of one fiction.** Flight/orbit views = NASA-punk hardware (starfield, film grain, modeled ship). Instrument surfaces — chiefly the minimap — = vector-CRT mission computer (scanlines, phosphor glow, barrel curve). This held up through implementation even though the original "flight view vs. full-screen map view" split (§8) didn't — the CRT treatment moved to specific *instruments* rather than an alternate full-screen mode. (A diegetic ship-status hologram was planned as a second CRT instrument but was **removed** once the screen HUD became the primary readout — see §9.)

## 3. Platform & tech

| Decision | Choice | Rationale |
|---|---|---|
| Engine | Godot 4.7 | Editor-driven level authoring, native exports |
| Language | GDScript | 64-bit floats, fastest iteration, keeps web export open later |
| v1 platforms | macOS, Windows, Linux desktop | Mobile explicitly out of scope (touch UX redesign). All three actually export clean via `tools/export.sh` against the official 4.7.1 templates — verified, not just planned |
| Physics | Hand-rolled; engine physics unused for orbits | Orbital scales/timesteps rule out engine rigid bodies |
| Window | Windowed (borderless) fullscreen by default, 1280×720 floor | Enforced by a direct `DisplayServer.window_set_min_size` call in `campaign_root.gd` (Godot 4 exposes no project-level min-size setting). The UI and `UiScale` are tuned against this floor. |

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
- No separate "physics warp cap while burning" was built as a distinct mode — burns simply can't be warped at all (`warp_index` is forced to 0 the moment throttle > 0), which is simpler than the originally-planned capped-physics-warp tier and never felt like a gap. Attitude input does the same: nudging the stick under warp drops to 1×, because rotation is a 1× activity (§4.4).

### 4.3 Propulsion — rocket equation, single stage

Ship parameters: `dry_mass`, `prop_mass`, `thrust`, `isp`. Burning depletes propellant at `thrust / (isp · g₀)`; acceleration rises as the ship lightens. HUD shows propellant fraction **and** remaining Δv (Tsiolkovsky). No staging, ever — one ship per level keeps levels tunable.

### 4.4 Attitude & rotational inertia

- **The ship has mass, and rotation is Newtonian (as shipped, 2026-07-23).** Rotation was originally rate-based — hold a key for a fixed turn rate, release and it stops dead. It now carries **real angular momentum**: attitude control applies angular *acceleration*, spin builds up over time, and — the point of the change — **releasing the controls does not stop the ship**; the spin persists until it is actively countered. The ship's **mass is felt directly**: available angular acceleration scales inversely with current mass (`initial_mass / mass()`), so a fuel-laden craft is sluggish and grows nimbler as the tank drains (capped so a near-dry ship never turns twitchy), and angular velocity is clamped to a per-axis ceiling (roll fastest). This makes attitude a flying skill with weight rather than twitch-aiming — a deepening of pillar 1, not a new subsystem — and it kept the "plausible, not pedantic" line: it's a single-rigid-body torque model with tuned constants, not a full inertia tensor.
- **Kill-rotation brake + smart SAS keep it fair.** So the player is never forced to hand-null every tumble, a dedicated **kill-rotation** command (`C`, sitting by the WASDQE cluster) actively brakes all spin to zero; it reads `KILL ROT` on the HUD and lives as a SAS mode. The existing SAS hold modes (prograde/retrograde/etc.) became **time-optimal slew-and-stop controllers** — they slew the nose onto target and decelerate to arrive *without overshoot*, rather than the old fixed-rate turn that stopped instantly. This is the deliberate answer to "how Newtonian": full momentum, but with a brake and smart holds, not a punishing hand-fly-everything model.
- **SAS holds are quiet — they track on momentum, not constant trim.** A held direction like prograde *sweeps with the orbit*, so a naive controller chatters endless micro-corrections (and, once rotation costs propellant, burns it for nothing). Instead the hold **feed-forwards the target's own rotation rate** (analytic under gravity for prograde/retrograde/radial; the orbit normal is fixed during a coast) and then goes silent inside a small pointing/rate **deadband**: once aligned and rotating *with* the reference, the ship's angular momentum carries the track for free, and RCS fires only to re-acquire after drift. Roll is left free in a pointing hold (it never changes where the nose points). This keeps the eventual RCS-propellant cost (§4.4, still to come) minimal by construction.
- **Rotation is a 1× activity — it's rails-consistent under time warp.** Attitude integrates in real wall-clock time, but the world races ahead under warp, so a real-time slew can't track a target (prograde/etc.) that sweeps around the orbit far faster than it can turn. Rather than integrate spin in warped time (uncontrollable, blurry, and it would wreck the RCS/camera feedback), attitude follows the same on-rails logic as everything else under warp (§4.1/§4.2): **manual stick input drops warp back to 1×** (joining throttle, which already does), **a SAS hold snaps to its target and stays locked** as the orbit sweeps (the same attitude-snap the autopilot uses), and **a free spin freezes** — its angular velocity preserved so it resumes the instant warp returns to 1×. So you set attitude at 1×, engage a hold, and warp with the nose staying put; the Newtonian feel is intact where it matters (1×) and never fights the warp.
- **The autopilot is exempt by design.** The analytic autopilot (Δv-par test harness and the debug flight director) steers by snapping attitude directly, bypassing the inertia model entirely — so every level's Δv par, which is measured empirically through that autopilot, is **provably unaffected** by the rotation change. Inertia is a player-side *feel* change only.
- **Feedback that sells the mass.** The hull's modeled RCS nozzle clusters now emit small additive puffs at the physically-correct thrusters (torque = arm × jet-force) whenever the ship torques, on manual input *and* SAS/kill-rotation braking. The chase camera carries subtle racing-game cues — attitude lag (the ship leads the frame during a fast slew, camera catches up), a thrust-driven FOV widen and dolly-back, and angular-velocity sway — so acceleration and rotation are *felt*, deliberately toned down to match the NASA-punk restraint (§9).
- **RCS/rotation-cost constraint is still planned, not yet built.** Rotation and the RCS puffs are currently **free** — no propellant is spent. The original plan's second difficulty axis (RCS propellant cost on later levels) is unchanged and still intended for the campaign build-out (§13): the inertia model added the *physical behavior*, not yet the *budget* that would turn it into a resource constraint. Still open: which act/level introduces the cost, and whether it draws its own tank or the main one.
- SAS-style hold modes (prograde/retrograde/normal/anti-normal/radial in/out, plus kill-rotation) exist and are an **unlock**, gated per-level by `LevelDef.sas_enabled` (see §6).

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
| Attitude | `W`/`S`, `A`/`D`, `Q`/`E` | pitch, yaw, roll (inertial — momentum persists, §4.4) |
| Throttle | `Shift`/`Ctrl` (hold), `Z`, `X` | up/down, max, cut |
| Time warp | `1`–`9`, `-`/`=` | jump to warp step, walk one step |
| Pause | `Space` or `0` (quick toggle), `Esc` (opens the pause menu) | see §7 |
| View | `Tab`, mouse-drag, wheel/trackpad | toggle chase↔orbit view, rotate, zoom (orbit view only) |
| View reset | `R` | resets the active camera to its default framing *while flying or paused*; on the win/fail screen the same key instead restarts the mission, matching what's printed on screen there — a context-sensitive rebind, not two different keys |
| SAS locks | `F` prograde, `B` retrograde, `N` normal, `G` anti-normal, `U`/`I` radial out/in, `C` kill-rotation, `T` off | auto-orient and hold (slew-and-stop, no overshoot); `C` brakes all spin; pressing the same lock again releases it |
| Maneuver node | `Enter` add, `Backspace` delete, `[`/`]` time, `↑`/`↓` prograde, `←`/`→` normal, `O`/`P` radial, `V` hold-toward-node | Shift = coarse step |

**Toolbar:** every keybind above except `1`–`9` (the warp indicator already covers those) is also a real clickable button — grouped VIEW / THROTTLE / WARP / SAS / NODE and wrapped across rows, bottom-center of the HUD, visible in both the chase and orbit views since the HUD is a plain overlay not tied to either camera. A click emits the button's **semantic action**, and `game_root` replays that action's *current* binding through the same input handler — so there's exactly one code path for "did the player do X" (keyboard or mouse), and a rebound key keeps its button working (the button label follows the binding). Buttons for capabilities the level hasn't unlocked (SAS, maneuver nodes — §6 `LevelDef` flags) are omitted. The throttle-trim buttons press-and-hold (`button_down`/`button_up`) rather than tap, matching their held semantics.

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

The reasoning for the pivot: a flat 2D schematic map view never got built past a placeholder before the question came up directly of "let the camera zoom out into the same 3D world instead of cutting to a different screen" — and once the floating-origin trick made "camera follows the ship" nearly free, there was no real cost to keeping everything in one continuous 3D space. The vector-CRT aesthetic that was meant for the map view moved onto the instrument that still reads as a physical mission-computer screen: the minimap. (A ship status hologram was planned as a second such instrument but later removed — §9.)

**Orbit marks** (in-world, orbit-view only — meaningless at chase-cam range where the whole orbit shape isn't visible anyway): small colored dots on the current trajectory —

| Mark | Color | Source |
|---|---|---|
| Apoapsis / Periapsis | sky blue / gold | always shown on an elliptical/any orbit |
| Ascending / descending node | violet / dark violet | `OrbitElements.xz_plane_crossings` — world-plane crossings, not the orbit's own tilt |
| Predicted surface impact | red | doubles as a crash warning and a landing aid |
| Target-SOI encounter | white | Moon/Mars transfer missions |
| Rendezvous closest approach | pink | reuses the same solver the HUD text already used |

**Ship posture marker.** The orbit-view ship marker was originally a plain sphere — pure location, no orientation. It's now a small directional shape (hull, nose cone, an off-axis wing so roll reads too, not just pitch/yaw) whose basis follows `ship.attitude` every frame, scaled to keep a constant *angular* size regardless of zoom (matching how the trajectory line itself stays legible at any distance).

**HUD instruments (chase and orbit view alike, since HUD isn't tied to either camera):** status/objective/engine text blocks, the minimap, a time-warp readout under it, and the toolbar (§6). *(A ship-status hologram — a billboarded 3D panel beside the hull with an acceleration dial, propellant ring, and Δv — was planned here but **removed**; that telemetry lives in the screen HUD text blocks instead. `ShipVisuals` records the removal.)*

## 9. Aesthetic — NASA-punk + vector CRT

- **World (chase + orbit views):** Apollo/Skylab hardware language on the ship — off-white hull, orange nose accent — against a procedural starfield sky (hashed voxel grid, no texture assets) and a whole-screen film grade (grain, vignette, warm tint) that reads as aged hardware footage, not a modern render. Planets get a cheap rim/fresnel glow for an atmosphere hint.
- **Instrument screens (the minimap; the status hologram was removed):** green/amber monochrome phosphor CRT — scanlines, glow, slight barrel distortion, faint flicker — rendered as a post-process inside the instrument's own `SubViewport`, so it composites into that instrument specifically rather than the whole screen.
- **Settings toggle:** the whole effects layer (film grade + CRT) can be switched off from Settings (§7) — a straightforward accessibility/preference option once it existed as a distinct visual layer.
- **Audio:** still fully deferred, unchanged from the original plan. Analog-synth palette, radio-filtered voice blips, tape-machine UI sounds remain the intent whenever it gets built.

## 10. Domain model

Reflects the classes as shipped, not the original sketch (some names/shapes changed — e.g. `TimeController` was never a distinct object, it's a few fields on the level orchestrator; `ManeuverNode` gained a `remaining` vector that depletes as a burn executes).

```
BodyDef         name, mu, radius, soi_radius, parent, orbit (OrbitElements around
                parent; null for the root), color
                — position_at(t)/velocity_at(t) recurse through parent, so
                nesting depth isn't hardcoded (the Sun/Earth/Mars case)

ShipSim         body (current parent), elements, r, v, attitude,
                angular_velocity (body-local rad/s — momentum persists; §4.4),
                throttle, dry_mass, prop_mass, thrust_max, isp, flight_state
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

Atmospheric flight/drag/heating · staging & rocket building · docking · n-body effects (Lagrange points, free returns) · mobile · sandbox mode (v2 candidate) · life support/comms/thermal · provable-unreachability "mission unrecoverable" detector (§5) · an in-game key-rebinding **UI** (the `InputMap` mechanism and persisted rebinds already exist — gameplay uses actions and the toolbar dispatches actions, not fixed keys — so only the settings screen to edit them is deferred to the menu redesign).

RCS/rotation-cost is *not* in this list — see §4.4, it's still planned, just not built yet.

## 12. Resolved during implementation

Decisions the original doc left open, now genuinely settled by what shipped:

- **Scale constants and warp ladder:** 1/100 length scale; 9-step round-number ladder `1,5,10,25,50,100,200,500,1000×` (§4.2).
- **Map view fate:** resolved differently than either original option — see §8's rewrite.

## 13. Still open — this game is not finished

Not settled scope decisions, just not done yet:

- **Campaign content: 15–20 levels, not the current 7.** The 7-level roster (Earth orbit school ×3, lunar program ×3, interplanetary ×1 — Mars only) is a testing/vertical-slice set built to exercise every objective type and act, not the intended final campaign. Getting to 15–20 means more levels within the existing acts (and possibly a second Act 3 destination — Venus was floated originally and never ruled out) plus empirically tuning Δv pars per DESIGN's own content process, which needs real playtesting rather than more solo authoring against guessed numbers.
- **RCS/rotation-cost** (§4.4): planned second difficulty axis, not yet introduced anywhere in the current roster.
- **Web export:** still not attempted. Neither shipped nor explicitly re-deferred by a real test — genuinely just not gotten to.
- **Narrative framing/voice:** still not started, unchanged from "after the vertical slice."
- **Rebindable keys, provable-unreachability detector:** listed in §11 as out of scope for now; revisit if they become a real ask.

## 14. Rewind, difficulty & hardcore

Agreed via grilling session, 2026-07-21. Rewind is the continuous extension of pillar 3 ("failure is information — free instant retries"): instead of re-flying 40 minutes to Mars over one mistake, you rewind to before it. It is a **tool, not a scored mechanic** — but a *limited* one, so it has weight.

**Why the architecture makes this cheap.** The universe is a pure function of `sim_time` (bodies on rails), coasting is closed-form and time-symmetric (`OrbitElements.state_at_time`), and `ShipSim.serialize()`/`apply_serialized()` round-trip the dynamic state (it's the save system). A **persisted** save deliberately resumes COASTING (a mid-burn substep isn't meaningful across a save boundary); an in-session **live** snapshot (`apply_serialized(..., live = true)`) additionally restores throttle and flight state, so CANCEL returns to "now" unchanged and burns stay atomic (§14.1–14.2). Rewind is a small in-memory snapshot buffer over primitives that already exist and are tested. The only path-dependent part is powered flight (RK4 + mass loss), which is not reversible — handled by snapshotting per-frame *only while burning*.

### 14.1 The unit and its cost
- You rewind to discrete **anchors**. Scrubbing the timeline to *look* is always free.
- A **charge is spent the instant you RESUME live play from an earlier anchor** — that branches the timeline and discards the future after it. First change burns the charge; no grace window.
- Anchors = `{ mission start } ∪ { the start of each burn }`. A burn is the only player action that changes the trajectory (attitude/SAS during coast don't), so burns are the only things worth undoing.
- Burns whose start is within **0.5 s** of the previous burn ending coalesce into one anchor (no tap-burn spam). Tunable.
- Burns are **atomic**: you redo a whole burn, never trim its tail.
- **SOI crossings** are labelled **scrub landmarks** (navigation only), not resume points.

### 14.2 The interaction
- A paused **`REWINDING`** phase (reuses the pause plumbing) shows a mission timeline: anchor ticks + SOI landmarks. Stepping between anchors plays a **0.5 s reverse-sweep tween** (the whole scene animates backward, because everything renders from `sim_time`).
- Two exits: **`RESUME HERE — USES 1 OF N REWINDS`** (commit, spend a charge, truncate the future, go FLYING) or **CANCEL** (snap back to now, free).
- At **0 charges** you can still enter and scrub to *look*; RESUME is disabled ("NO REWINDS LEFT").
- The labelled RESUME button is the only confirmation.

### 14.3 Failure and success
- Rewind reaches into **FAILED**: same rules, costs a charge; the fail screen offers rewind first, restart as the 0-charge fallback.
- **Success no longer freezes.** The win locks the instant it is achieved (medal, Δv, and CLEAN/rewinds-used frozen; rewind dead). The ship keeps coasting its new orbit on rails, **camera free, no ship input**, under a non-modal "MISSION COMPLETE" banner (Next / Restart / Exit).

### 14.4 Budget, scoring and hardcore
- `rewind_budget` is authored **per level** (like `dv_par`; e.g. Act 1 L1 → 1, a long Mars run → 3; default 1). Per-mission; **resets on restart**; the remaining count persists across mid-mission save/reload.
- Δv medals are unchanged. A run that spends **zero** rewinds earns a **`◇ CLEAN`** ribbon (sticky once earned); `rewinds_used` is recorded per level. There is no aggregate score — scoring stays per-level.
- **Hardcore** is a binary profile choice made at creation, **immutable**, and explicitly prompted. Hardcore forces `rewind_budget` to 0 everywhere, **strips the predictive aids** (forward trajectory line + maneuver-node preview; keeps the target ring), wears a profile emblem, and makes every win inherently CLEAN. Same pars throughout — hardcore's achievement is the *same* targets with fewer aids.

### 14.5 Persistence (v1) and fast-follows
- **v1:** anchor history is session-only — the mid-mission save point is the rewind floor; only the remaining charge count persists. The save confirmation warns "rewind anchors will not be saved."
- **Fast-follows (not first cut):** ghost of the discarded trajectory on resume · free-form fine scrub between anchors · full cross-save history persistence · a diegetic "mission simulator" framing (rewind = "reset sim to timestamp", hardcore = "live-fire") if/when the game gets a narrative voice.
