# `src/` Code Review

Date: 2026-07-25

## Scope and method

This review covers the implementation under `src/`, including GDScript, scenes,
resources, and shaders. It compares that implementation with `DESIGN.md`,
`UI-DESIGN.md`, `AGENTS.md`, `TECH_DEBTS.md`, and `docs/LEVELS.md`, and examines
correctness, robustness, maintainability, and likely performance hot paths.

`tools/*` was not reviewed. The existing test runner was invoked only as a
verification entry point.

This is primarily a static review. Performance findings are based on call paths,
allocation patterns, and the timing notes already present in the source; except
where explicitly stated, they are not profiler measurements.

## Executive summary

The core simulation architecture is generally strong and follows the important
design invariants:

- Orbital state uses `DVec3`/double-precision math, and coasting uses closed-form
  `OrbitElements` rather than incremental integration.
- Body motion remains on rails and parent traversal is recursive.
- Rendering consistently subtracts the ship position before converting important
  trajectory geometry to `Vector3`, preserving the floating-origin design.
- Objective checks are mostly pure functions of ship state/time, and the test suite
  has broad coverage of the simulation and campaign layers.
- Several expensive paths already have thoughtful caches, notably body orbits,
  rendezvous closest approach, node encounter previews, and frozen-state UI work.

The most important remaining work is:

1. Make throttle-cut-to-warp transitions event-safe.
2. Clear static community-launch state before resuming a campaign save.
3. Treat community JSON and persisted saves as untrusted input with full structural
   and numeric validation.
4. Restore the documented zero-warning and single-source theme guarantees.
5. Consolidate child-SOI prediction so gameplay and visuals do not repeat seconds
   of synchronous work on large community systems.

No critical issue was found, but the first three items are high-severity because
they can produce incorrect simulation transitions, load the wrong mission, or
crash on user-authored data.

## Verification baseline

- `./tools/test.sh`: **286/286 tests passed**, 2,218 assertions, 45 scripts; the
  script/test baseline and UI/i18n checks passed.
- `godot --headless --debug --import`: completed, but reported three GDScript
  warnings:
  - `src/ui/menu/mission_detail_pane.gd:75`: incompatible ternary branches.
  - `src/ui/menu/level_select.gd:96`: `wrap` shadows a built-in.
  - `src/ui/menu/level_select.gd:133`: incompatible ternary branches.

The green test suite therefore does not currently imply compliance with the
documented zero-warning requirement.

## Correctness and robustness findings

### CR-1 — High: throttle cut can enter high warp before the coast/event state is ready

**Evidence:** `src/game_root.gd:192-201` clamps the next step to an impact/SOI/node
event only when both `ship.flight_state == COASTING` and `ship.throttle == 0`.
`throttle_cut` sets only the throttle (`src/game_root.gd:327-328`), while direct
warp keys immediately accept zero throttle (`src/game_root.gd:395-400`). The
`BURNING -> COASTING` refit does not happen until `ShipSim.advance_to()`
(`src/sim/ship_sim.gd:73-89`), after the high-warp `t_target` has already been
chosen.

**Impact:** Pressing throttle cut and a high-warp key between physics ticks can
skip event clamping for that tick. `advance_to()` refits at the old time and then
coasts all the way to the already-computed target. Near an impact or narrow child
SOI, this violates the documented rule that rails warp must never step across the
next event.

**Suggestion:** Make throttle cutting a simulation transition rather than a bare
field assignment. For example, expose `ShipSim.cut_throttle(at_time)` that refits
immediately when needed, then compute the warp target. Alternatively normalize an
effectively non-thrusting ship to `COASTING` before `_next_event_time()` and before
accepting a warp change.

Add a regression test for: burn near an event, press throttle cut, select 1000x
before the next physics update, and assert the ship lands just past the event at
1x rather than skipping it.

### CR-2 — High: stale community launch state can replace a resumed campaign level

**Evidence:** `GameRoot.custom_level` is static and wins over `level_index`
(`src/game_root.gd:34-39`, `86-92`). `_launch_custom()` sets it and also sets
`_active_community_id` (`src/campaign_root.gd:174-184`). A normal new launch clears
both values (`src/campaign_root.gd:162-171`), but `_resume_mission()` clears neither
before constructing `GameRoot` (`src/campaign_root.gd:89-98`).

**Impact:** After flying a community mission and returning to the menus, Continue
can instantiate the stale community `LevelDef` and then apply a built-in campaign
save to it. If the resulting mission reaches `_on_win()`, the stale community ID
can also route the result into `SandboxStore` instead of the active profile
(`src/campaign_root.gd:195-203`).

**Suggestion:** Centralize launch context setup in one method that always assigns
all of `{custom_level, level_index, hardcore, active_community_id}`. Campaign
resume must explicitly set `custom_level = null` and `_active_community_id = ""`.

Add an integration test for: launch community -> exit -> Continue a campaign save
-> verify the campaign `LevelDef` and campaign persistence path are selected.

### CR-3 — High: community-level loading does not fulfill its “never a crash” contract

**Evidence:** `LevelLoader` promises a readable rejection rather than a crash
(`src/campaign/level_loader.gd:3-8`), but it directly coerces JSON values to typed
containers and loop variables at lines 25, 30, 38, 57, 70, 76, and 84. Valid JSON
such as `{"bodies":"not-an-array"}`, `{"start":[]}`, or a non-object body entry
can therefore cause a runtime type error instead of returning `_err(...)`.

The loader also accepts zero, negative, or otherwise nonsensical values for ship
mass, propellant, thrust, Isp, start radius, tolerances, and view bounds
(`src/campaign/level_loader.gd:70-90`, `163-191`). Those values reach divisions and
rocket-equation calls such as `src/ui/hud/propellant_flight_strip.gd:55-65`.

`CommunityLevels._load_one()` additionally dereferences the result of
`FileAccess.open()` without checking it (`src/campaign/community_levels.gd:53-58`),
so a permission/race failure can crash the scan.

**Impact:** A malformed drop-in mod can abort loading or create NaN/INF/invalid
physics instead of appearing as a skipped level with a readable error. This is an
external-input boundary, so it should be more defensive than built-in content.

**Suggestion:** Validate the JSON shape before typed assignment, using small
helpers such as “required dictionary/array/finite number/positive number/range.”
Require finite positive `mu`, radii, masses, thrust and Isp where applicable;
non-negative propellant/tolerances; valid start geometry; bounded difficulty and
rewind budget; and positive map/draw extents. Check `FileAccess.open()` and cap
input file size before reading.

Add table-driven tests for wrong container types, wrong body-entry types, missing
and unreadable files, zeros/negatives, extreme numbers, and every objective block.

### CR-4 — High policy violation: the source is not warning-clean

**Evidence:** The debug import reports the three warnings listed in the baseline.
This directly contradicts `AGENTS.md` sections 0 and 7.

**Suggestion:** Rename `wrap` to a specific name such as `header_margin`, and make
both ternary branches explicitly `String` (or assign an explicitly typed `String`
before returning). Add the debug-import warning check to the normal required CI
path if it is not already enforced there; the current green suite did not catch
these warnings.

### CR-5 — Medium: a successful airless landing has no stable landed state

**Evidence:** Surface contact can win while the ship is actively thrusting
(`src/objectives/airless_landing.gd:11-19`). `_win()` changes the phase but does not
cut throttle or settle the craft (`src/game_root.gd:682-689`). In the `WON` phase,
the game continues calling `ship.advance_to()` every physics tick
(`src/game_root.gd:161-170`).

**Impact:** After a successful powered landing, the craft can keep burning, lift
off, or continue along a refitted conic through the body. The result is already
locked, but the non-modal post-win scene no longer depicts the achieved state.
The design phrase “keeps coasting its new orbit” does not define a physically
meaningful terminal behavior for a surface objective.

**Suggestion:** Add an explicit landed/terminal motion state. Clamp the craft to
the surface, zero body-relative velocity and throttle, and keep its body-relative
position fixed while the parent body remains on rails. Document that landing wins
remain landed while orbital wins continue coasting.

### CR-6 — Medium: parseable but semantically corrupt saves can fail before recovery

**Evidence:** `ProfileStore._apply()` accepts any dictionary as `mission_save`
without validating its schema (`src/campaign/profile_store.gd:78-113`). The title
screen immediately uses the saved `level_index` for unchecked `Campaign.code()`
and `Campaign.short_title()` calls (`src/ui/menu/title_screen.gd:95-102`). Later,
`ShipSim.apply_serialized()` assumes fixed-length numeric arrays and known node
fields (`src/sim/ship_sim.gd:389-420`).

**Impact:** A syntactically valid damaged or hand-edited save can crash while
building the title screen, before `GameRoot` gets a chance to clamp the index. It
can also fail during state restoration through short arrays or invalid types.

**Suggestion:** Validate/migrate each profile and mission-save dictionary at the
store boundary. Check level range or stable ID, finite time/mass/vector values,
array lengths, enum ranges, known body names, and node schema. Discard only the
invalid mission slot, retain the rest of the profile, and surface a `load_warning`.

### CR-7 — Medium: maneuver execution and prediction disagree near/through completion

There are two related issues:

1. `ShipSim.predicted_elements()` always applies the full authored node delta-v
   (`src/sim/ship_sim.gd:288-294`) even after `node.remaining` has been depleted by
   an in-progress burn (`src/sim/ship_sim.gd:346-350`). The predicted ghost can
   therefore add already-delivered delta-v a second time during a burn.
2. Completion is detected only when the remaining vector length falls below
   0.5 m/s. A high-acceleration community craft can subtract a per-tick delta-v
   larger than that neighborhood, cross zero, and leave a growing vector in the
   opposite direction without ever completing the node.

**Suggestion:** Use the remaining planned impulse for live prediction, with a
well-defined frame/rebase rule. During execution, clamp the delivered node impulse
to the remaining projection or detect a sign/projection crossing, then complete at
zero. Test a half-completed burn, an off-axis burn, and a craft whose single tick
delivers more than `NODE_COMPLETE_DV`.

### CR-8 — Medium: transfer guidance is not route-aware for supported deep nesting

**Evidence:** `docs/LEVELS.md` supports graphs such as Sol -> Jupiter -> Io, but
`TransferCaptureObjective.status_lines()` compares a root-frame ship apoapsis with
`target.orbit.a` (`src/objectives/transfer_capture.gd:31-39`). For Io,
`target.orbit.a` is Jupiter-centric, so those quantities are from different
frames. While the ship is under any non-root body, closeness is a hardcoded `0.2`
(`src/objectives/transfer_capture.gd:47-59`), even if it has reached the target's
parent and is preparing the next transfer leg.

The win predicate itself is correctly target-body-local; the misleading part is
the status/closeness feedback and resulting trajectory color.

**Suggestion:** Build the ancestry route from the ship's current body to the
target. Guide toward the next body on that route and compare conics only in their
shared parent frame. Advance the guidance leg after each SOI transition. Test at
least root -> planet -> moon and a departure from an unrelated sibling branch.

### CR-9 — Medium: minimap AUTO does not consistently include the target

**Evidence:** `UI-DESIGN.md` says AUTO fits “current orbit + target.”
`MapView._target_reach()` handles only orbit match, rendezvous, and entry corridor
(`src/ui/world/map_view.gd:185-240`), returning zero for transfer-capture and
landing targets. The zoom minimum is also permanently based on the level root
body (`src/ui/hud/minimap_objective_rail.gd:26-31`) rather than the ship's current
SOI.

**Impact:** A lunar/interplanetary target can be off-screen during the transfer
setup, and a Sol-root level can remain constrained by a Sun-scale minimum after
the ship enters a much smaller planet/moon SOI.

**Suggestion:** Compute the target extent relative to the current focus for every
objective type, including the target body's position/ring. Recompute the minimum
zoom from `ship.body` after SOI changes. Add visual-logic tests for Earth -> Moon
and Sol -> planet -> moon at each leg.

### CR-10 — Medium: community CLEAN is not actually sticky

**Evidence:** `SandboxStore.record()` updates a record only when the new delta-v
is lower (`src/campaign/sandbox_store.gd:40-44`). A slower clean run after a faster
rewind-assisted run never changes the stored `clean` flag. This differs from
`Profile.record_win()` (`src/campaign/profile.gd:52-60`) and from the sticky CLEAN
rule in `DESIGN.md` section 14.4.

**Suggestion:** Update `clean = previous_clean or new_clean` independently of the
best medal/delta-v fields. Add `is_clean(id)` and cover both result orders in tests.

### CR-11 — Medium: index-based campaign identity is incompatible with adding levels inside acts

**Evidence:** `Campaign` says indices are stable save IDs and also says to append
new levels inside an act's contiguous range (`src/campaign/campaign.gd:3-16`). Once
later acts exist, inserting into an earlier act necessarily shifts their indices;
appending to the global end breaks the act ranges/order. `ProfileStore` has already
needed a schema-wide progress reset after one renumbering
(`src/campaign/profile_store.gd:13-16`, `86-92`).

**Impact:** The planned expansion to 15–20 missions will either constrain mission
ordering or repeatedly invalidate progress.

**Suggestion:** Persist unlocks, medals, and mission saves by `LevelDef.id`
(`level_01_01`, etc.), with presentation order kept separately in `ACTS`. Perform
one explicit migration from current integer keys; never use display position as
persistent identity afterward.

### CR-12 — Low: quick pause does not freeze node deletion

**Evidence:** Node creation/adjustment checks `phase == FLYING`
(`src/game_root.gd:740-764`), but the direct node-delete branch mutates the node
without a phase check (`src/game_root.gd:364-371`). Quick pause has no modal menu
to intercept the key.

**Suggestion:** Route deletion through a helper with the same phase/capability
guard as creation and adjustment. More generally, gate all mission mutations at a
single input dispatch boundary when the phase is not `FLYING`.

### CR-13 — Low: community win UI can advertise a nonexistent next mission

**Evidence:** `_win()` calculates `has_next` only from the static campaign
`level_index` (`src/game_root.gd:682-689`), even when `custom_level` is active.
Campaign routing later returns community players to mission select, but the win
banner can still show “Next Mission.”

**Suggestion:** Pass explicit launch context into `GameRoot`, and set
`has_next = not is_community and Campaign.next_after(level_index) != -1`.

## Documentation and architecture alignment

### DA-1 — High: `generated_ui_theme.tres` is baked despite the single-source guarantee

**Documentation:** `AGENTS.md` says the generated theme is script-only, rebuilt
from `Palette` on every load, with nothing baked that can drift. `UiTheme` repeats
that all styling is populated from the single source
(`src/ui/theme/ui_theme.gd:4-12`).

**Implementation:** `src/ui/theme/generated_ui_theme.tres` is a 708-line serialized
theme containing font resources, many `StyleBoxFlat` subresources, and literal
colors/properties; the generating script is assigned only at the end. This is a
second persisted copy of the theme.

**Risk:** Editor serialization can silently preserve stale values and override or
obscure what `_init()` populated. A Palette change is no longer guaranteed to be
the only change needed.

**Suggestion:** Reduce the resource to the minimal `Theme + script` shell described
by the docs, or deliberately adopt a generated artifact workflow and change the
docs/tests accordingly. For the current architecture, add a test/lint asserting
that the `.tres` contains no subresources or theme properties beyond its script.

### DA-2 — Medium: `RenderTheme.body_colors` is not authoritative for known bodies

**Documentation:** `AGENTS.md` and the paid TD-3 entry say body surface colors and
every flight-view surface color flow through `RenderTheme`.

**Implementation:** `BodyRenderer` supplies `base_color` from the theme
(`src/ui/world/body_renderer.gd:230-239`), but the shader overwrites it with
hardcoded colors/maps for Earth, Moon, Sun, and Mars
(`src/shaders/celestial_body.gdshader:85-149`). Only the generic branch actually
uses `base_color`. `ship_flame.gdshader:10-18` also embeds amber/white colors outside
the theme seam. Catalog bodies beyond the four recognized names are treated as
generic (`src/ui/world/body_renderer.gd:202-213`).

**Risk:** Swapping `RenderTheme.body_colors` does not swap the rendered appearance
the API claims to own. Newly supported named bodies rely on catalog fallback colors
rather than a complete render theme.

**Suggestion:** Make the procedural ramps/tints shader uniforms owned by
`RenderTheme`, and key body appearance by stable catalog name or an explicit body
visual kind. Move engine-flame appearance into the same seam or document it as an
intentional exception. Add an end-to-end theme-swap test that inspects actual
material uniforms, not just `RenderTheme` fields.

### DA-3 — Medium: menu implementation and the contributor guide describe opposite architectures

**Documentation:** `AGENTS.md` section 3 says the menu redesign is deliberately
code-built rather than `.tscn`, and elsewhere says scene-authored UI styles nodes
only through `theme_type_variation` with no per-node overrides.

**Implementation:** `MenuShell`, mission detail, pause, new profile, settings,
credits, title hero, and load detail instantiate `.tscn` layouts. Menu/HUD code and
scenes also contain many `add_theme_*_override` and `theme_override_*` assignments,
including dynamic colors in `mission_card.gd`, `option_card.gd`, and HUD scripts.

**Suggestion:** Decide which architecture is now intentional. The current source
looks coherently headed toward scene-first menus, so the lower-cost path is likely
to update `AGENTS.md` and then move semantic selected/locked/warning states into
named theme variations. If per-node runtime overrides are intentionally needed,
document narrowly allowed cases rather than maintaining an absolute rule the code
does not follow.

### DA-4 — Medium: the authored-level documentation still describes the removed `.tres` pipeline

Examples:

- `AGENTS.md`, `README.md`, and `LevelDef`'s header still direct authors to
  `src/levels/data/*.tres` (`src/levels/level_def.gd:1-6`).
- `Campaign` begins with a stale `.tres`/index comment immediately before the
  correct JSON description (`src/campaign/campaign.gd:3-11`).
- `BodyDef` still says the hierarchy is single-level and only SOI logic needs work,
  although both graph construction and SOI traversal now support deeper nesting
  (`src/sim/body_def.gd:1-6`).
- Palette/theme paths in `AGENTS.md` and `UI-DESIGN.md` do not match the current
  `src/ui/theme/` and `src/ui/world/` layout.

**Suggestion:** Update the contributor guide, README, class comments, and UI design
paths in one documentation pass. Declare `assets/levels/*.json` + `LevelLoader` the
only built-in/community authoring pipeline and remove legacy `.tres` guidance.

### DA-5 — Medium: rewind implementation does not match the powered-flight history described in DESIGN

**Documentation:** `DESIGN.md` section 14 says powered flight is handled by
snapshotting every frame while burning.

**Implementation:** `RewindBuffer` stores only launch/pre-burn anchors and
landmarks (`src/sim/rewind_buffer.gd:3-17`, `48-64`). The reverse sweep restores the
selected anchor and cosmetically evaluates that anchor's coast conic backward
(`src/game_root.gd:580-612`). It does not replay the actual discarded powered path.

The anchor restore behavior remains useful and deterministic; the mismatch is in
the visual/history claim.

**Suggestion:** Either retain short per-frame burn samples for an honest reverse
sweep, or update DESIGN to state explicitly that the sweep is an illustrative
coast interpolation and that only discrete anchors are historical truth.

### DA-6 — Low: a standalone UI color bypasses the palette rule

`src/ui/world/orbit_labels.gd:25` exports `ink_color := Color.BLACK`. That violates
the documented “no standalone colors” rule even though it is a named color rather
than a numeric `Color(...)` literal. The current verification did not flag it.

**Suggestion:** Add an appropriate `Palette` token and broaden the rule/check to
cover named `Color` constants in UI source, or explicitly document why inspector
defaults are exempt.

## Performance findings

### PF-1 — High: child-SOI prediction is synchronous, duplicated, and can select the wrong visual encounter

**Evidence:** `LevelLoader` documents `child_soi_entry_time` at about 165 ms per
call and allows 12 active children (`src/campaign/level_loader.gd:12-17`).
`GameRoot._recompute_events()` scans every active child synchronously
(`src/game_root.gd:706-730`). `ManeuverVisuals` independently repeats the scan for
the encounter marker (`src/ui/world/maneuver_visuals.gd:276-302`) and may scan again
for a node preview (`331-360`).

With 12 active children, one refit can therefore spend roughly seconds in event
search before the visual duplicates are counted. The visual current-orbit loop
also stops at the first encounter in level-list order rather than selecting the
earliest encounter time (`src/ui/world/maneuver_visuals.gd:294-301`). Gameplay uses
the minimum and can disagree with the marker.

**Suggestion:** Introduce one `OrbitEventPrediction` result/cache keyed by ship
revision, parent body, start time, and horizon. Compute all child entries once,
select the minimum, and share the result with gameplay and visuals. Add a cheap
broad-phase rejection before the fine search. If work is scheduled incrementally,
temporarily cap warp until the safety-critical result is available; event clamping
cannot depend on a late background answer.

Benchmark worst-case 12-child community systems on the minimum target hardware.
Reduce `MAX_ACTIVE_MOONS` if the measured frame budget cannot support the current
cap even after consolidation.

### PF-2 — Medium: body ephemerides are repeatedly solved and allocated per frame

`BodyDef.position_at()` recursively evaluates parent orbits and allocates `DVec3`
objects (`src/sim/body_def.gd:57-66`). `BodyRenderer.sync()` does this for every
body (`src/ui/world/body_renderer.gd:79-91`), and `MapView.sync()` plus
`marked_points()` repeats overlapping work (`src/ui/world/map_view.gd:132-176`,
`200-229`). Nested bodies re-evaluate their ancestors each time.

The 48-body loader cap makes this relevant even for “decorative” bodies, which are
cheap only to the physics event scanner, not to rendering. Startup also constructs
a unique faceted sphere mesh for every body (`src/ui/world/body_renderer.gd:54-68`).

**Suggestion:** Build one parent-first ephemeris snapshot per rendered `sim_time`,
containing root-frame positions/velocities for all bodies, and pass/share it across
the flight view, minimap, labels, and objective visuals. Reuse unit sphere meshes by
tessellation level and apply radius through node scaling. Consider lower update
cadence/culling for distant decorative markers.

### PF-3 — Medium: mid-burn element fits and trajectory/map mesh rebuilds multiply each other

While burning, every `ShipSim.current_elements()` call performs a full
`OrbitElements.from_state()` fit (`src/sim/ship_sim.gd:242-247`). In a displayed
frame, separate callers include telemetry, objectives, trajectory color/geometry,
maneuver marks, minimap auto-fit, minimap markers, and autopilot phases.

The main trajectory intentionally rebuilds a 256-point `ImmediateMesh` whenever
time changes (`src/ui/world/trajectory_renderer.gd:142-156`, `215-244`). The minimap
also rebuilds its conic every 0.2 seconds even during an unchanged coasting
revision (`src/ui/world/map_view.gd:171-176`, `243-252`). Sampling uses arrays of
heap-allocated `DVec3` values.

**Suggestion:** Cache the osculating elements once per ship state generation or
physics tick and make all consumers share that instance. Key minimap geometry by
`ship.revision` while coasting, using the timed refresh only during powered flight.
Profile a packed/vector-component sampling path that avoids allocating one
`DVec3` per vertex before changing the already-correct floating-origin math.

### PF-4 — Low: rendezvous station orbit is rebuilt on every access

`RendezvousObjective.station_orbit` calls `OrbitElements.circular()` on every
getter access (`src/objectives/rendezvous.gd:19-25`), despite the earlier comment
saying it is cached and despite repeated status, closest-approach, map, and ship
visual consumers. `BodyDef.orbit` already contains the appropriate lazy-cache and
setter-invalidation pattern.

**Suggestion:** Apply the `BodyDef.orbit` pattern to station radius, phase, mu, and
epoch. This is a small, low-risk allocation/fit reduction.

### PF-5 — Profiling target: celestial-body fragment shaders may dominate close views

`celestial_body.gdshader` uses multi-octave procedural noise repeatedly; Earth runs
several FBM evaluations and the Moon combines FBM with five crater-angle tests per
fragment (`src/shaders/celestial_body.gdshader:85-149`). Large close-up bodies can
cover much of the screen, and the effects setting currently does not provide a
body-shader quality tier.

**Suggestion:** Capture GPU timings on the weakest target before changing the art.
If this is significant, use distance/effects quality variants, reduce octaves and
craters at distance, or bake static detail into small textures while retaining the
theme-driven ramps. This is a measurement recommendation, not a confirmed current
frame-rate defect.

## Recommended implementation order

1. **Correctness first:** CR-1, CR-2, CR-3, and CR-4, each with regression tests.
2. **Persistence/terminal state:** CR-5, CR-6, CR-10, and the stable-ID migration
   design in CR-11.
3. **Prediction coherence:** CR-7 through CR-9, then consolidate the event service
   in PF-1 so physics, markers, nodes, and minimap share one answer.
4. **Restore architectural contracts:** DA-1 and DA-2, then resolve the menu and
   documentation drift in DA-3 through DA-6.
5. **Profile and optimize:** PF-2 and PF-3 are the strongest CPU candidates after
   event scans; validate PF-5 with GPU measurements.

## Suggested regression coverage

- Cut throttle and select maximum warp in the same frame immediately before an
  impact and immediately before a child-SOI encounter.
- Community launch followed by campaign Continue, restart, win, and save routing.
- Fuzz/table tests for every JSON container boundary and numeric range in
  `LevelLoader`, plus unreadable community files.
- Corrupt-but-parseable profile/save fixtures that preserve valid profile data and
  discard only the bad mission slot.
- Powered landing followed by several seconds in the post-win scene.
- Node completion when per-tick delivered delta-v exceeds remaining delta-v.
- Sol -> planet -> moon transfer guidance and minimap framing at every SOI.
- CLEAN persistence for fast-dirty then slow-clean and the reverse order.
- Theme-swap verification at the final material/shader parameter level.
- A worst-case active/decorative body benchmark with an explicit frame-time budget.

