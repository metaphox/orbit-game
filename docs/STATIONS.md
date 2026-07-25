# Space-station design guideline

Reference notes + rules that the procedural generator (`tools/station_gen.py`)
follows so its output reads as a *plausible* station in this game's art style —
and not like the level-2 placeholder (clipping rings, off-palette colours).

> The cited, longer-form research this distils from — the NASA Space Station
> Freedom redesign saga (Power Tower → Dual Keel → Alpha), Mir/Skylab/Tiangong,
> and the sci-fi wheels/tori/cylinders — lives in **`docs/STATIONS_research.md`**.

## 1. What real stations are made of

| Part | Real examples | Role | Shape |
|---|---|---|---|
| Pressurised module | ISS Destiny/Zarya, Mir modules | lab / habitat / storage | cylinder, ~4 m dia |
| Node / hub | ISS Unity/Harmony | connects modules, many ports | short fat cylinder |
| Docking adapter / port | ISS IDA, Mir ports | where ships berth | small collar/cone |
| Truss / keel | ISS Integrated Truss | backbone holding arrays clear of modules | long box beam |
| Solar array | ISS SAWs, Tiangong wings | power; tracks the sun | large flat wings, **in pairs** |
| Radiator | ISS ATCS panels | dump heat; edge-on to sun | flat panels, **perpendicular to arrays** |
| High-gain antenna | ISS, relay dishes | comms to Earth/relay | dish on a mast |
| Cupola / dome | ISS Cupola | observation | small dome |
| Rotating ring | 2001 / Babylon-5 (fiction) | spin gravity | torus around the spine |

## 2. Structural archetypes

> **Design stance (Taowu, playtest feedback):** this is a *quasi-sci-fi* game, not
> a NASA simulator — **archetypes MAY be mixed**. The old "pick ONE per station,
> never mix" rule is retired. A single station can be, e.g., a **dual-keel frame
> carrying a giant dome AND a rotating ring**. Coherence comes from the shared
> palette + connection logic, not from real-world purity. Each archetype below is
> a *reusable module of form* the generator can compose, not a mutually-exclusive
> mode.

Nine archetypes worth generating (from the research). **Implemented** ones are in
the tool today; the rest are the roadmap.

| # | Archetype | Logic | Status |
|---|---|---|---|
| 1 | **Monolith** (Salyut, Skylab) | one fat cylinder L/D≈2–3, 1–2 wing pairs, axial ports | via `stack` (n=1) |
| 2 | **Stack** (Mir core, Axiom) | cylinders end-to-end on one axis, joined by fat nodes, wings near ends | **done** |
| 3 | **Truss spine** (ISS) | module spine + perpendicular truss holding arrays/radiators clear | **done** |
| 4 | **Dual-keel frame** (Freedom '86) | rectangular truss loop (~2:1); modules on a mid boom, instruments on the edges | **done** (`dualkeel`) |
| 5 | **Power-Tower totem** (Freedom '84) | tall thin keel, mass at both ends, arrays amidships, modules at one end | **done** (`power`) |
| 6 | **Radial-node cluster** (Mir) | central node, 4–6 ports (1 axial + radials @90°), modules stick out radially | **done** (`radial`) |
| 7 | **Rotating wheel/torus** (2001, Stanford) | non-rotating axial hub + spokes + ring(s); R/r≈10–30 | **done** (`ring`) |
| 8 | **O'Neill/Rama cylinder** (B5, Cooper) | long rotating cylinder L/D≈4–6, endcap dock, hull ribs | **done** (`cylinder`) |
| 9 | **Geometric shell** (Elite Coriolis) | faceted polyhedron, slow spin, docking slot in one face | planned |

The hybrid archetype composes routed form modules rather than selecting just one.
The implemented recipes are dual-keel + ring + observatory dome, truss + ring +
radial cluster, and power tower + ring + tank farm. Auto-selection may choose a
hybrid for large stations. Each graft reserves an X-slab before arrays, radiators,
and antennas are mounted, so the same interference validator governs the whole.

Auto-selection by size: small → stack/monolith, medium → truss/stack, large →
truss/ring/dual-keel/power-tower/cylinder/hybrid.

## 2a. Signature details that sell realism (bake these in)

- **Paired sun-tracking arrays** — mirrored about the station but articulated
  toward one local sun vector. Their narrow deployable spine, repeated hinge bays,
  and stowed-envelope logic must explain how the array could fold for launch.
  Rectangular blankets are the common family, not the only family.
- **Radiators edge-on to the sun** — long, narrow accordion wings
  *perpendicular to the arrays*, mounted through a truss or structural boom rather
  than pasted onto a crew module. Their area follows the station's thermal budget,
  not its overall bounding length.
- **High-gain dish antennas** on masts (1–4) + small whips.
- **Docking nodes with multiple ports** — fat short cylinders, collars/cones, radial
  ports @90°; a berthed ship reads as "active."
- **MMOD blankets / greebling** — quilted insulation + repeated truss bays = a strong
  "engineered" texture cue. *(cheap future win)*
- **Robotic arm caught mid-reach**, sparse green/red nav lights, and an
  "under-construction" motif (partial ring, docked tug) for a lived-in feel.
- **Crewed-module details** — every lab and habitat carries a restrained cluster
  of dark windows plus at most one green status light near a hatch or module end.
  Windows belong to their module surface; they are not free-floating greebles.
- **Orientation logic** — instruments point where they look, radiators edge-on,
  arrays track one declared local sun vector within their gimbal limits. Coherent
  aiming is what actually sells plausibility; random independent tilts do not.

## 3. Hard rules (what keeps it plausible)

1. **No interpenetration.** Every payload part's volume is disjoint. A connector
   (collar, adapter, spoke, tunnel, hinge) may enter the two assemblies named by
   its joint and may meet other connector geometry at a structural hub, but may
   not pass through an unrelated solid payload.
2. **Arrays clear of the hull.** Solar wings sit on booms long enough that the
   wing's inner edge is beyond the widest module radius + a clearance margin. They
   never overlap each other, the radiators, or a ring.
3. **Arrays come in symmetric pairs.** A pair shares one family, effective area,
   dimensions, and fold topology. The two deployment directions mirror each
   other while their active faces track the same local sun vector.
4. **Radiators are perpendicular to the arrays** (edge-on to the sun), have a
   connected structural boom, and use one deployable panel layer per bank. An
   ordinary solar-powered station keeps total radiator face area near 25–35% of
   total solar collecting area; a declared high-power profile may exceed that
   band within its own validated limit.
5. **Symmetry / balance.** Mass is roughly balanced about the centre; paired parts
   are mirrored.
6. **Sensible counts (never none, never a swarm, never all-identical):**
   - Solar wing pairs scale with size: ~1 pair when small → several when huge.
     Minimum 1 pair (a station needs power). Cap so it doesn't become a pin-cushion.
   - Antennas: 1–4. Docking ports: ≥1. Radiator bank count follows required
     thermal area and the maximum plausible area of one deployable wing.
   - Modules vary in length/diameter within a family; at least one accent part
     (cupola, dome, orange trim, green nav lights). Avoid a row of identical cans
     *and* avoid a junkyard of one-off shapes.
7. **Palette = the player ship.** Reuse the ship materials so a station reads as
   "same universe": hull cream `#e0dbc9`, structure dark metallic, solar blue,
   orange accents *sparingly*, green status lights. Never invent new hues.
8. **Connectivity is a hard gate.** Every structural assembly reaches the station
   root; every crewed volume reaches the pressurised core; every solar leaf reaches
   its gimbal through hinges; every surface detail names its owning module. A high
   organisation score can never excuse a disconnected assembly.
9. **Labs and habitats look occupied.** Every generated lab and habitat has a
   simple, plausible window/light treatment derived from its cylindrical surface.
   Decoration density remains restrained and consistent within a station.

## 4. Scale

Size is handled as a single number **L = longest dimension in metres**, with the
ISS as the yardstick (**ISS ≈ 109 m**). The generator's `--iss` flag sets L in ISS
multiples; `--game-scale` converts metres → Godot units for the emitted `.tscn`.

- Smallest useful station ≈ **0.5× ISS** (~55 m) — a core module, a node, one
  wing pair, one antenna.
- Largest showcase ≈ **20× ISS** (~2.2 km) — long trussed spine or a ring hub,
  many wing pairs, radiator banks, multiple rings/domes.

Power collection and part counts grow softly with L. Radiator area is derived
from the generated solar collecting area, crewed-module load, and thermal profile;
it is deliberately not a fixed fraction of L².

## 5. Generator contract (see `tools/station_gen.py --help`)

- **Inputs:** rough size (`--iss` or `--meters`), minimum part counts, seed,
  every implemented single archetype plus hybrid or auto, count, game scale, and
  output directory. Optional PNG previews can go to a separate preview directory.
- **Pipeline:** seed RNG → choose one archetype or a routed hybrid recipe → build
  semantic assemblies and consume typed mounts → derive render parts → add
  sun-tracking foldable arrays, load-sized radiator banks, signature parts, and
  module-owned surface details → **validate** geometry, structural reachability,
  pressurised reachability, joint attachment, solar/radiator
  topology/orientation/area, and content minimums → calculate the report-only
  organisation index → serialise a Godot `.tscn` plus a `.json` blueprint
  containing the assembly graph, thermal budget, and diagnostic report.
- **Failure is explicit:** if constraints can't be met (e.g. min-panels won't fit
  the chosen size) the tool reports why and exits non-zero rather than emitting a
  clipping mess.

## 6. Current iteration (Taowu playtest feedback, 2026-07-25)

The requested changes are implemented in the generator and represented by
the five assets in `assets/station_review/`, with three-view PNGs in
`docs/station_review/`.

1. **Thinner solar panels.** Blanket half-thickness now uses a proportional value
   with a 0.004–0.18 m absolute clamp, and radiator fins use the same capped
   approach. A 20× ISS station therefore cannot scale back into metre-thick slabs.
2. **More part variety / more part *types*.** Every station receives two seeded
   signature families selected from domes/blisters, tank racks, robotic arms, and
   docked tugs. Truss forms use repeated open lattice bays; dishes are tapered and
   vary in size; tugs add capsule and truncated-cone meshes plus fins and
   navigation lights.
3. **Allow HYBRID / mixed archetypes.** The three recipes in §2 compose existing
   builders around shared routed clearance slabs, including the canonical
   **dual-keel frame carrying a giant dome and a rotating ring**. Hybrids pass the
   same AABB + torus-annulus validation as single-form stations.
4. **Reference-sized radiators.** The old near-square duplicate fins are replaced
   by narrow 6–8-panel accordion banks. Their count and area come from the thermal
   budget in §7.6, and both the budget and deployed topology are hard-validated.

## 7. Connected assemblies, foldable arrays, and organisation reporting

**Status:** implemented on 2026-07-25. Connectivity is a hard generation gate and
the organisation index is emitted in report-only mode. Candidate ranking remains
intentionally disabled until human review calibrates the component weights.

The next iteration changes the generator's internal unit of composition. A
station is not merely an unordered list of render primitives. It is a graph of
semantic assemblies joined through typed mounting points; primitive mesh parts
are derived from that graph for collision checks, previews, and serialisation.

### 7.1 Semantic model

| Type | Owns |
|---|---|
| **Assembly** | One meaningful unit: lab, habitat, node, dome, solar wing, radiator bank, truss bay, ring, antenna, tug |
| **Mount** | Owner, world position, outward normal, usable radius, supported joint types, occupied state |
| **Joint** | Parent/child mounts, connection type, visible connector parts, capacity metadata |
| **Part** | Render/collision primitive belonging to one assembly; no longer the source of structural meaning |

Assemblies expose mounts and builders consume compatible free mounts. Major
objects must not be placed at arbitrary coordinates and retroactively declared
connected. The station root is a node or core module. Decorative parts inherit
their owning assembly and do not become independent graph nodes.

Joint types are:

- **Structural** — rigid load path such as a truss, brace, boom, or collar.
- **Pressurised** — crew-accessible tunnel or adapter; also structural.
- **Articulated** — hinge, rotary joint, solar gimbal, or rotating-ring bearing.
- **Surface mount** — window, light, sensor, or other skin detail.
- **Docked** — occupied docking collars between the station and a berthed craft.

The JSON blueprint records assemblies, mounts, joints, the station root, and the
derived part IDs. This makes a failed validation explainable without inspecting
the generated scene by eye.

### 7.2 Connectivity and physical attachment validation

Connectivity is evaluated at the assembly level and then confirmed geometrically.
The following are hard generation requirements:

1. Every non-decoration assembly has a structural path to the station root.
2. Every lab, habitat, dome, crewed ring, and docking vestibule has a pressurised
   path to the core.
3. Every solar leaf reaches its gimbal through a connected hinge tree; the gimbal
   reaches a structural mount.
4. Every window/light has exactly one valid surface owner.
5. Both endpoints of a joint coincide with the declared mounts within a
   scale-relative tolerance and face compatible directions.
6. Connector geometry touches both endpoint assemblies. It may overlap their
   payload geometry and meet other connector geometry at a load-sharing hub, but
   must remain clear of every third assembly's solid payload.
7. Pressurised connectors meet a minimum aperture appropriate to the child
   volume; a thin structural brace cannot masquerade as crew access.
8. Docking ports retain an unobstructed approach volume.

The old global exemption from payload collision is therefore retired.
Connector-to-connector contacts remain legal because truss hubs, paired gimbals,
and multi-member bearings intentionally share space; connector-to-payload checks
remain joint-specific. A declared graph edge cannot make floating or crossing
payload geometry valid: topology and physical attachment must both pass.

### 7.3 Foldable solar-array families

The detail reference supplied in review establishes the default visual language:
a very narrow deployable lattice, repeated blanket bays, visible fold lines, thin
edge tapes, and sparse cross-bracing. The support should read as a lightweight
deployment mechanism, not a solid central slab.

Each station selects one primary solar family. A showcase-sized station may use
one secondary family, but individual wings do not choose unrelated shapes. Every
mirrored pair shares dimensions, effective area, fold topology, and material.

| Family | Deployed form | Plausible stowage |
|---|---|---|
| **Accordion rectangle** | Two segmented blankets alongside a narrow lattice spine | Repeated rectangular bays fold back-to-back |
| **Petal fan** | Tapered polygon leaves spreading from a spar or hub | Leaves pivot and nest into a compact fan |
| **Round umbrella** | Circular/radial sectors supported by ribs | Ribs close around the hub like an umbrella |
| **Honeycomb** | Hexagonal cells grouped into two or three ordered strips | Strips fold at shared hex edges; never an unstructured tile cloud |

Geometry rules:

- Rename the solar-specific mast role to **solar spine** so it is distinct from
  antenna masts.
- The spine occupies roughly 2–4% of total wing width and is built from two rails
  plus sparse diagonal braces.
- Structural thickness is capped independently of station length.
- Accordion blankets use roughly 5–12 separate bays with narrow gaps and
  alternating hinge directions.
- Every family declares hinge edges, effective collecting area, deployed bounds,
  and an approximate stowed envelope.
- Initial validation checks the hinge tree and whether the analytic stowed
  envelope can contain the leaves. Full collision-sampled folding animation is a
  later enhancement, not required for the first pass.

### 7.4 Sun tracking and varied tilt

Tilt is functional, not arbitrary noise:

- A station owns one deterministic local **sun vector**, stored in its blueprint
  and as scene metadata.
- Every wing has a boom, rotary joint, and gimbal limits.
- The deployed transform is solved so the active panel normal remains within
  roughly 10–15 degrees of the sun vector.
- Mirrored wings reverse their deployment direction but face the same sun.
- Different mount axes and allowed gimbal solutions create visible angle
  variation without making arrays point toward unrelated light sources.
- Clearance and collision checks use the final rotated geometry.

`Part.cols` stores local axes as matrix columns. Godot's text
`Transform3D(...)` syntax lists matrix rows, so scene serialisation transposes at
that boundary. Blueprints retain the column axes and the Godot load check compares
each instantiated basis/origin against them; this prevents a valid analytic boom
from being rotated away from its panel in the emitted scene.

When a generated asset is placed in a level, the station root can be rotated so
its local sun vector points toward the real parent star. Runtime solar tracking
may be added later without changing the generated assembly contract.

### 7.5 Windows and restrained module lighting

Every lab and habitat receives a small surface-detail assembly:

- Habitats: 2–6 dark windows, usually in one or two grouped clusters.
- Labs: 1–4 narrower observation windows near a work-zone end.
- At most one green status light per module, near a hatch or end collar.
- Nodes may carry sparse navigation lights; tanks and trusses do not receive
  decorative windows.

Placement uses the owning cylinder's local axial coordinate and azimuth, then
transforms the detail onto its surface. Windows use the existing dark ship
material and status lights use the existing green material. No new colour seam or
raw colour literal is introduced.

### 7.6 Radiator thermal budget and deployable geometry

The ISS is the calibration reference, not a shape to copy literally. NASA reports
approximately 1,300 m² of ISS radiator surface rejecting about 125 kW, and an ISS
Heat Rejection System wing uses eight 2.7 × 3.4 m panels over a roughly 23 m
deployed length. The resulting visual lesson is more important than the exact
hardware: practical radiator wings are long, narrow, segmented, and sized from
waste heat. Sources: [NASA ISS radiator-area comparison](https://ntrs.nasa.gov/api/citations/20250010635/downloads/MARVL%20ECI%20Continuation%20Review_STARK-V3.pdf)
and [NASA HRS geometry](https://ntrs.nasa.gov/api/citations/20100033102/downloads/20100033102.pdf).

The generator uses a deterministic, ISS-calibrated proxy budget:

- Solar-supported equipment contributes **0.026 kW of rejected heat per m²** of
  generated collecting area.
- Each lab adds **0.60 kW**, each habitat **0.35 kW**, and other crewed volumes
  **0.20 kW**.
- A radiator face rejects **0.096 kW/m²**. This is a system-level visual-sizing
  coefficient, not an ideal Stefan–Boltzmann material limit.
- Power-tower forms use a **1.24× high-power load multiplier**. Ordinary target
  area is clamped to **25–35%** of solar collecting area; high-power forms are
  allowed up to **42%**.

The blueprint records the profile, estimated heat load, target and emitted
radiator area, solar area, and their ratio. Validation rejects missing or
inconsistent budgets rather than silently emitting an oversized decorative slab.

Each radiator bank is one two-sided deployable sheet rather than two
near-coincident fins. It has:

- a deployed aspect ratio of roughly **5:1–7:1**;
- **6–8** rectangular panels separated by visible fold gaps;
- hinge bars and one continuous backing spar connected to the station boom;
- enough banks to carry the target area without making any one bank broader than
  the reference silhouette; and
- a panel normal perpendicular to the local sun vector.

Full coolant routing and loop redundancy remain outside the visual generator's
scope. A future redundant loop must be declared in metadata and represented as a
separate connected bank, not as coincident geometry.

### 7.7 Connected dual-keel observatory

The large dome on the current dual-keel hybrid looks isolated because its narrow
neck terminates at a structural frame edge. The replacement is a crewed
observatory chain:

    central pressurised node
        → pressurised trunk/cabin
        → wide vestibule and base collar
        → observatory dome

The dual-keel may brace the trunk and collar, but the frame is not the crew-access
path. The dome sits on a short, broad base and may use a shallower cap silhouette
rather than an unsupported full sphere. Validation requires both a pressurised
path to the core and an adequate structural path. The rotating ring is routed
around this trunk instead of visually replacing it.

### 7.8 Organisation score

The blueprint exposes a deterministic **organization_score** from 0–100. Do not
call it SOI: that abbreviation already means sphere of influence in the game.
Hard validity and the score are separate; disconnected or colliding stations are
invalid regardless of score.

| Component | Weight | Measures |
|---|---:|---|
| **Connection quality** | 25 | Joint capacity, pressurised path length, large volumes on plausible connectors |
| **Functional orientation** | 20 | Solar alignment, radiator orthogonality, unobstructed antenna directions |
| **Spatial clearance** | 15 | Normalised margins, docking approach volumes, uncrowded mounts |
| **Mass balance** | 15 | Volume-weighted centre offset and paired appendage balance |
| **Routing and hierarchy** | 15 | Connector path stretch, overloaded hubs, excessive branch depth |
| **Pattern coherence** | 10 | Fold-bay rhythm, window spacing, controlled repetition and variety |

Each component is normalised to 0–1 and the weighted sum produces the final
score. The report includes component values plus human-readable penalties such as
"docking approach margin is narrow" or "habitat is four joints from the pressure
core."

Scoring is archetype-aware. A radial station may be intentionally asymmetric and
a power tower deliberately end-heavy; the score measures balance and coherent
load paths against the recipe's design intent rather than pushing every station
toward one silhouette. Diversity remains a separate constraint so maximising the
score cannot collapse all outputs into the same design.

Rollout status:

1. **Done:** emit the score in report-only mode over the full archetype/size/seed
   self-test matrix and the five-station review set.
2. **Next:** compare score components with human rankings of the review set.
3. **Pending:** calibrate an acceptance threshold from those results rather than
   guessing one.
4. **Pending:** after calibration, generate several deterministic valid candidates and select
   the highest-scoring candidate instead of returning the first valid candidate.
5. **Done:** record requested seed, resolved candidate seed, total score, components, and
   penalties in JSON; optionally show the score in previews and CLI diagnostics.

### 7.8 Implementation and acceptance sequence

Implemented now: assembly/mount/joint data; builder ownership; structural and
pressurised hard validation; four foldable solar families; station-level sun
tracking; module-owned windows/lights; the pressure-connected dual-keel
observatory; report-only organisation scoring; and five regenerated review
scenes/blueprints/previews. The only deferred step is deterministic
best-candidate selection, which must follow human calibration rather than encode
an unreviewed aesthetic preference.

Required tests include:

- A disconnected dome, a declared joint with a physical gap, and a connector
  crossing an unrelated part all fail explicitly.
- Every archetype, size, and seed has one structural component; every crewed
  assembly reaches the pressurised core.
- Every solar segment reaches its gimbal through hinges, mirrored pairs have equal
  area/topology, and panel normals meet the sun-alignment tolerance.
- All labs/habitats own valid windows and no surface detail floats off its parent.
- Organisation reports are deterministic, bounded, serialised, and explain their
  penalties.
- The existing palette, no-interference, min-count, Godot-load, project-suite, and
  warning-clean checks remain green.
