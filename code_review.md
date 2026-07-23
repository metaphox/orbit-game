# Codebase review

Date: 2026-07-23

Scope: current working tree reviewed against `DESIGN.md`, `AGENTS.md`,
`TECH_DEBTS.md`, and `PLAN.md`, with focused inspection of the simulation,
body hierarchy, objectives, rewind/persistence, input, HUD, and rendering paths.

Validation: `./tools/test.sh` passes: 31 scripts, 186 tests, 1,143 assertions.
The suite is strong around orbital math, SOI transitions, campaign persistence,
and the shipped level solutions. The findings below are mainly boundary and
presentation issues that the current tests do not exercise.

## Executive assessment

The orbital core is the strongest part of the repository. It consistently uses
`DVec3`, keeps coasting closed-form, caches the expensive encounter scans, and
has meaningful conservation, edge-case, hierarchy, and full-level tests. The
`FlightView` decomposition also demonstrates a good refactor pattern.

The highest-value next work is:

1. Fix rewind cancellation during a live burn and the incorrect failure-screen
   rewind prompt.
2. Remove root/local-frame mixing from mission-envelope, transfer-guidance, and
   nested rendering helpers.
3. Stop rebuilding hidden or unchanged trajectory geometry every render frame.
4. Replace physical-key metadata with action/command metadata shared by input,
   toolbar, prompts, and rebinding.
5. Reconcile `DESIGN.md`, `PLAN.md`, and `TECH_DEBTS.md` with the implementation
   before further behavior changes.

## Prioritized findings

| ID | Priority | Area | Finding |
|---|---|---|---|
| CR-1 | High | Rewind | Cancelling rewind during a burn cuts thrust for free. |
| CR-2 | High | Failure UI | The fail banner says `[Z] REWIND`; rewind is bound to `H` by default and `Z` does nothing from `FAILED`. |
| CR-3 | High | Frames | Mission-envelope distance is checked only in a root SOI, contrary to the specified root-frame predicate. |
| CR-4 | High for future content | Hierarchy | Several objective/render helpers mix root-frame and direct-parent-frame positions, so the advertised arbitrary nesting is incomplete outside `ShipSim`. |
| CR-5 | Medium | Input | TD-4 is marked paid, but the toolbar and several prompts still use hardcoded physical keys and break or drift under rebinding. |
| CR-6 | Medium | Theme | Raw UI colors and local HUD color aliases violate `AGENTS.md`; TD-1/TD-3 overstate completion. |
| PF-1 | High potential cost | Rendering | The forward trajectory mesh is regenerated every frame, even when hardcore hides it or the mission is frozen. |
| PF-2 | Medium-high potential cost | Orbital sampling | Every sampled point recomputes the perifocal basis and velocity and allocates multiple `RefCounted` objects. |
| PF-3 | Medium potential cost | Rendezvous | Closest approach can be recomputed every frame at high warp despite an unchanged conic. |
| PF-4 | Medium potential cost | Presentation | Static HUD, minimap, and flight state continue to be reformatted and rebuilt every frame while paused or failed. |
| RF-1 | Medium | Structure | `Hud` (1,085 lines) and `game_root` (739 lines) are the next god objects after the successful `FlightView` split. |
| DOC-1 | High process risk | Documentation | The four reviewed documents disagree with one another and with the code on shipped scope and behavior. |

## Correctness and design conformance

### CR-1 — Rewind cancel can alter the live trajectory for free

Evidence:

- `game_root._enter_rewind()` sets `ship.throttle = 0.0` before capturing the
  return state (`src/game_root.gd:502`).
- `ShipSim.serialize()` does not include throttle or flight state
  (`src/sim/ship_sim.gd:251`).
- `ShipSim.apply_serialized()` always restores as coasting with zero throttle
  (`src/sim/ship_sim.gd:266`).
- Cancel then applies that state without spending a charge
  (`src/game_root.gd:575`).

Impact: press rewind during a burn, cancel, and the burn has been cut without the
explicit branch/charge required by DESIGN §14. This also contradicts the promise
that cancel returns to “now” unchanged and weakens the “burns are atomic” rule.

Recommendation: separate persisted mission saves from in-session live snapshots.
A typed `LiveShipSnapshot` should include throttle and flight state; a persisted
save may still intentionally resume coasting. Alternatively, reject opening the
rewind scrubber while thrusting and tell the player to cut throttle first. Add an
integration test that enters/cancels rewind with non-zero throttle and compares
time, state vectors, propellant, throttle, and charge count.

### CR-2 — Failure recovery advertises the wrong input

`Hud.show_fail()` emits `[Z] REWIND` (`src/ui/hud.gd:652`), while the default
`rewind_open` action is `H` (`src/campaign/input_bindings.gd:11`). `Z` is
`throttle_full`, which is ignored unless the phase is `FLYING`, so the advertised
recovery path does nothing.

This directly harms the “failure is information” pillar. Generate the prompt
from `InputBindings.primary_key_label("rewind_open")`. At zero charges, the
design still permits scrub-only viewing, so the banner should expose that mode
rather than hiding rewind entirely. The win/fail prompts should likewise derive
Restart, Next, Exit, Confirm, and Cancel labels from live actions.

### CR-3 — Mission-envelope escape is not a root-frame predicate

DESIGN §5 defines escape as root-frame distance past `fail_radius`. The code only
checks `ship.r` when `ship.body.parent == null` (`src/game_root.gd:482`). While the
ship is inside a child SOI, no envelope check runs even though
`ShipSim.absolute_position()` already provides the required root-frame position.

Use `ship.absolute_position(sim_time).length()` regardless of current SOI. Add a
three-tier test where a ship remains inside a non-root body while its root-frame
position exceeds the level envelope.

### CR-4 — Arbitrary nesting is only partially implemented

The simulation handoff is correctly depth-independent: `BodyDef.position_at()`
recurses and `ShipSim.apply_soi_transitions()` filters the flat body list by the
current parent. The three-tier SOI tests validate that core.

Higher-level consumers still mix frames:

- `TransferCaptureObjective._phase_angle()` compares the ship’s root-frame
  absolute position with `target.orbit.state_at_time().r`, which is only relative
  to the target’s immediate parent (`src/objectives/transfer_capture.gd:69`). It
  works for Earth→Mars because Mars directly orbits the root, but not for a target
  two or more levels deep.
- `MapView` builds every child orbit track around the scene origin rather than
  the child’s parent position (`src/ui/map_view.gd:94`). A Moon orbit under an
  Earth that itself orbits the Sun will be drawn around the Sun.
- `ManeuverVisuals` stores the predicted encounter anchor with
  `moon.position_at(entry)` (root frame), then subtracts `ship.r` (current-parent
  frame) (`src/ui/maneuver_visuals.gd:68` and `:298`).

Introduce one body/frame service with explicit operations such as
`root_state(body, t)`, `state_relative_to(body, origin, t)`, `children_of(body)`,
and `root_of(body)`. Call sites should not combine raw `.r`, `.orbit.r`, and
`.position_at()` values without naming their frames. Extend the existing
three-tier hierarchy fixture to objective guidance, map tracks, encounter
preview placement, and mission-envelope checks.

### CR-5 — The action migration is incomplete at the toolbar boundary

TD-4 says the rebinding mechanism is paid, but `Hud.STRIP_GROUPS` stores labels
and physical keycodes (`src/ui/hud.gd:23`), `toolbar_key` emits those keycodes,
and `game_root` synthesizes `InputEventKey` objects (`src/game_root.gd:113`). If
an action is rebound, its old toolbar key no longer matches the action, so the
button can stop working. Toolbar pressed-state bookkeeping is also keyed by
`KEY_F`, `KEY_B`, and peers (`src/ui/hud.gd:1046`). Existing tests cover rebinding
and toolbar clicks independently, but not together.

Define command descriptors once: action name, display group, hold/tap behavior,
availability predicate, and optional active-state predicate. Let the toolbar emit
an action/command, not a physical key. Labels should come from `InputMap`, and
keyboard, mouse, and controller paths should converge on a semantic command
dispatcher. Add a test that rebinds an action and verifies both the new keyboard
binding and its toolbar button.

There is also a scope conflict to resolve first: DESIGN §6 says every binding
except warp 1–9 is clickable, while TD-7 explicitly accepts only the compact
SAS/WARP/NODE strip. Since DESIGN is the declared source of truth, either restore
the full toolbar or amend DESIGN before preserving the compact version.

### CR-6 — Theme-policy and debt-ledger drift

`AGENTS.md` forbids raw `Color(...)` literals in UI code and specifically forbids
local `const GREEN`-style aliases. Current counterexamples include:

- HUD aliases at `src/ui/hud.gd:13`.
- A baked minimap color at `src/ui/hud_layout.tscn:30`, despite TD-1 saying the
  shell has no baked colors.
- A raw marker-tip color at `src/ui/map_view.gd:331`.
- Multiple flare colors in `src/ui/sun_flare.gd:35`.
- Grid colors in `src/ui/grid_overlay.gd:33`.
- Raw colors in `src/ui/map_view_layout.tscn`.

The documented TD-3 exceptions are only chase fill, star dust, and the station
scene, so the flare/grid/map exceptions are neither routed through a seam nor
logged. Six menu files still use `SystemFont.new()`, which TD-1 correctly lists as
open.

Move semantic UI colors (including transparent, label shadow, map nose, and
debug-grid tokens) to `Palette`; move flare appearance to `RenderTheme`. Remove
the HUD aliases and reference `Palette` directly. Add a lightweight CI lint that
rejects `Color(` in `src/ui` outside `palette.gd`, `render_theme.gd`, and an
explicit reviewed allowlist, and rejects known-body `color =` in level data.
Update TD-1/TD-3 status after the actual scope is agreed.

## Performance review

These are code-path risks, not GPU/CPU measurements on target hardware. The
existing debug FPS label is useful, but M9’s weak-GPU performance acceptance has
not been demonstrated in the repository.

### PF-1 — Per-frame trajectory geometry rebuild

`TrajectoryRenderer.sync()` calls `_rebuild_line()` every render frame and only
then hides the instance when guidance is disabled (`src/ui/trajectory_renderer.gd:110`).
The rebuild samples up to 256 points and clears/reuploads an `ImmediateMesh`
(`src/ui/trajectory_renderer.gd:154`). `game_root._process()` invokes this while
flying, paused, failed, rewinding, and won (`src/game_root.gd:213`).

Immediate fixes:

- Early-out before sampling when guidance is disabled; hardcore currently pays
  the full hidden-line cost.
- Do not rebuild unchanged geometry in `PAUSED` or `FAILED`.
- Cache by elements revision/current body and update only the transform and
  material when geometry is unchanged.
- If ship-centered adaptive density must move along a closed orbit, rebuild only
  after an anomaly threshold or at a capped real-time frequency; measure whether
  a sufficiently dense cached loop removes the need entirely.
- Skip the path in a camera mode where the line is intentionally invisible.

### PF-2 — Orbital sampling repeats invariant work and allocations

`OrbitElements.sample_positions()` calls `state_at_true_anomaly()` for every
point (`src/core/orbit_elements.gd:245`). That function recomputes the perifocal
basis, computes velocity even though render sampling uses only position, creates
an `Array`, several `DVec3`s, and a `StateRV` for every point
(`src/core/orbit_elements.gd:136` and `:263`). This multiplies PF-1’s cost and also
affects minimap/node-ghost rebuilds.

Add a position-only batch sampler that computes P/Q once and writes directly to
a reusable packed render array after double-precision calculation. If
`OrbitElements` remains mutable, invalidate a cached basis whenever an element
field changes; otherwise make fitted elements effectively immutable and cache
the basis safely. Avoid broad mutation of `DVec3` semantics until profiling shows
the burn integrator needs it—the presentation sampling path is the clearer win.

### PF-3 — Rendezvous closest approach can thrash at high warp

The rendezvous cache expires after two simulation seconds
(`src/objectives/rendezvous.gd:58`). At 1000× warp, a 60 FPS render frame advances
about 16.7 simulation seconds, so the approximately 240-sample plus refinement
search can run every frame even though the conics have not changed. It is reached
through trajectory coloring and HUD status.

Cache until the predicted closest-approach time has passed or the ship revision
changes, and cap presentation refresh by real time. Recompute immediately after a
burn/refit. This preserves truthful guidance without tying solver frequency to
warp multiplier.

### PF-4 — Static presentation work remains hot

Every `_process` calls `FlightView.sync`, `MapView.sync`, and `Hud.refresh`.
`Hud.refresh()` repeatedly formats strings, applies theme overrides, computes
current elements, builds objective status arrays, updates toolbar state, and
allocates minimap point dictionaries (`src/ui/hud.gd:515` and
`src/ui/map_view.gd:196`). Much of this is unchanged while paused/failed, and many
readouts do not need render-frame frequency during ordinary coast.

Build a per-frame immutable `PresentationState` once from ship/time/body state,
then share it across view and HUD consumers. Separate update rates:

- Camera/body transforms: per render frame when moving.
- Trajectory geometry and orbit marks: revision-driven or capped.
- Text/status/minimap labels: roughly 10 Hz real time, plus immediate dirty
  updates after input, phase, node, SOI, or objective changes.
- Frozen phases: redraw only for camera movement, rewind sweep, or UI animation.

## Refactor recommendations

### 1. Extract a mission phase/state controller from `game_root`

`game_root` currently owns simulation stepping, event-cache policy, five phases,
rewind, pause menu lifecycle, save payloads, input dispatch, autopilot, win/fail,
and view coordination. Extract in this order:

1. `MissionCommandRouter` for semantic actions and phase gating.
2. `MissionRewindController` for entry/cancel/commit and live snapshots.
3. `MissionEventScheduler` for impact/SOI/node event caching.
4. Leave `game_root` as scene composition plus high-level state transitions.

Each extraction can use the existing `FlightView` approach: preserve public
behavior, add headless unit tests, and move one responsibility at a time.

### 2. Decompose `Hud`

The rebuilt HUD is visually coherent but now exceeds the old `FlightView` size.
Split it into `TelemetryBar`, `ObjectivePanel`, `GuidancePanel`,
`PropulsionStrip`, `CommandToolbar`, `MinimapController`, `MissionBanner`, and
`RewindOverlay`. Keep shared construction helpers in `UiTheme`. This also creates
natural dirty/update-rate boundaries for PF-4 and finishes TD-1 without another
large monolithic edit.

### 3. Formalize the body graph and frame API

`LevelDef.moons` is actually a flat list of every non-root body. A `BodySystem`
wrapper can retain the existing `.tres` schema while validating unique names,
acyclic parent links, parent membership, positive physical values, and root
reachability. It should expose traversal and relative-state operations so future
levels do not reintroduce depth assumptions.

### 4. Use typed snapshots and validated persistence boundaries

In-memory rewind anchors and JSON mission saves currently share loosely typed
dictionaries even though they have different restoration semantics. Introduce a
typed simulation snapshot and explicit JSON encode/decode validation. Clamp or
reject invalid body names, masses, enum values, vector sizes, and basis data at
load. This makes the CR-1 fix explicit and prevents future save-schema changes
from silently changing rewind behavior.

### 5. Centralize capability and command metadata

Warp steps are duplicated in `game_root` and `Hud`; action labels are duplicated
across `project.godot`, `InputBindings`, HUD help, toolbar definitions, and banner
strings. One command registry should own action names and display metadata, while
`LevelDef` capability flags determine availability. RCS/rotation-cost can then be
added without another large conditional chain in `game_root`.

## Documentation reconciliation

Resolve these before treating the documents as acceptance criteria:

| Source claim | Current implementation | Recommended resolution |
|---|---|---|
| DESIGN §3: 1024×768 minimum, enforced in project settings and `DisplayServer`. | `campaign_root.gd:23` enforces 1280×720; `project.godot` defines a 1920×1080 viewport, not a 1024×768 floor. | Decide the intended minimum and update DESIGN, runtime code, UI tests, and `UiScale` together. |
| DESIGN §§2, 8, 9: ship status hologram is shipped. | `ShipVisuals` says it was removed; status exists only in the screen HUD. | Update DESIGN/README if removal is intentional, or restore the instrument after a design change. |
| DESIGN §6: all non-1–9 bindings have clickable toolbar buttons. | HUD exposes only compact SAS/WARP/NODE controls; TD-7 acknowledges this. | Make DESIGN and TD-7 agree before changing the toolbar. |
| DESIGN §§11/13: input is hardcoded and an InputMap migration is future work. | Gameplay actions use InputMap and persisted rebinding exists, but UI/toolbar integration is incomplete. | Describe this as “mechanism implemented; rebinding UI and action-based toolbar outstanding.” Reopen/adjust TD-4. |
| PLAN header: M0–M9 are complete. | M4 RCS, M6 keybind/volume/briefing UI, M7 audio, M8 15–20 levels/playtesting, and parts of M9 performance/web/distribution are not complete. | Mark milestones complete/partial/deferred by acceptance criterion; retain deviations as historical notes. |
| TECH_DEBTS TD-1/TD-3: colors are fully routed and only documented exceptions remain. | Several raw UI colors and a baked HUD scene color remain. | Correct the status and add debt rows for any intentionally retained exceptions. |
| DESIGN domain model reflects shipped code. | It omits `rewind_budget`, profile `hardcore`/CLEAN data, typed settings, and rewind state. | Refresh the model after the behavior decisions above. |

## Recommended tests and safeguards

1. Rewind cancel during an active burn is state-preserving and free.
2. Fail/win/rewind prompts use the live rebound action labels; default fail
   recovery opens on `H`, not `Z`.
3. Mission envelope is evaluated in root coordinates from every SOI depth.
4. A Sun→Earth→Moon fixture validates transfer guidance, minimap orbit centers,
   target/encounter markers, and floating-origin placement.
5. Toolbar commands still work after their keyboard actions are rebound.
6. Hardcore/hidden guidance performs no trajectory sampling or mesh rebuild.
7. A static theme lint enforces the `Palette`/`UiTheme`/`RenderTheme` seams and
   known-body level-color rule.
8. Add a small trajectory/closest-approach benchmark and record target-frame
   budgets for chase, orbit, rendezvous at 1000×, lunar return, paused, and
   hardcore states on a weak-GPU/CPU target.
9. Harden `tools/test.sh`: the current baseline is a script/test-count guard, not
   line coverage, and the initial `godot --import` result/output is discarded.
   Make import failures visible or document why specific non-zero statuses are
   safe to ignore.

## Suggested delivery order

1. **Bug patch:** CR-1, CR-2, CR-3 with regression tests.
2. **Decision/doc patch:** reconcile DESIGN/PLAN/TECH_DEBTS and log accepted debt.
3. **Frame-safety patch:** body/frame service plus the three-tier consumer tests.
4. **Input patch:** semantic command registry and rebound-toolbar tests.
5. **Performance patch:** hidden-line early-out, frozen-phase gating, then profile
   PF-1/PF-2/PF-3 before deeper optimization.
6. **Structural patches:** extract rewind/commands/events from `game_root`, then
   split HUD components one at a time while keeping the suite green.

This order fixes player-visible correctness first, restores the documents as
reliable constraints, and only then changes the high-frequency rendering paths.
