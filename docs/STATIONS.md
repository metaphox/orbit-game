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
> mode. (See §6 for the next-iteration plan to actually build hybrids.)

Nine archetypes worth generating (from the research). **Implemented** ones are in
the tool today; the rest are the roadmap. Today the tool emits one archetype per
station; hybrids are the next step (§6).

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

Auto-selection by size: small → stack/monolith, medium → truss/stack, large →
truss/ring (later: dual-keel, power-tower, cylinder for the showcase sizes).

## 2a. Signature details that sell realism (bake these in)

- **Paired sun-tracking arrays** — mirrored, broadside to the "sun" axis, on booms
  that hold them clear of the hull; long thin wings, faint blue cell grid.
- **Radiators edge-on to the sun** — flat panels *perpendicular to the arrays*, on
  the truss, never on the modules; banks of 2–3.
- **High-gain dish antennas** on masts (1–4) + small whips.
- **Docking nodes with multiple ports** — fat short cylinders, collars/cones, radial
  ports @90°; a berthed ship reads as "active."
- **MMOD blankets / greebling** — quilted insulation + repeated truss bays = a strong
  "engineered" texture cue. *(cheap future win)*
- **Robotic arm caught mid-reach**, sparse green/red nav lights, and an
  "under-construction" motif (partial ring, docked tug) for a lived-in feel.
- **Orientation logic** — instruments point where they look, radiators edge-on,
  arrays to the sun. Coherent aiming is what actually sells plausibility.

## 3. Hard rules (what keeps it plausible)

1. **No interpenetration.** Every solid part's volume is disjoint. The only parts
   allowed to touch/overlap are *connectors* (collars, adapters, spokes) that
   deliberately join two things. The generator enforces this with an AABB overlap
   check over all non-connector parts and refuses to emit a station that fails.
2. **Arrays clear of the hull.** Solar wings sit on booms long enough that the
   wing's inner edge is beyond the widest module radius + a clearance margin. They
   never overlap each other, the radiators, or a ring.
3. **Arrays come in symmetric pairs**, broadside to the station's "sun" axis.
4. **Radiators are perpendicular to the arrays** (edge-on to the sun) and ride the
   truss, not the modules.
5. **Symmetry / balance.** Mass is roughly balanced about the centre; paired parts
   are mirrored.
6. **Sensible counts (never none, never a swarm, never all-identical):**
   - Solar wing pairs scale with size: ~1 pair when small → several when huge.
     Minimum 1 pair (a station needs power). Cap so it doesn't become a pin-cushion.
   - Antennas: 1–4. Docking ports: ≥1. Radiators scale with array count.
   - Modules vary in length/diameter within a family; at least one accent part
     (cupola, dome, orange trim, green nav lights). Avoid a row of identical cans
     *and* avoid a junkyard of one-off shapes.
7. **Palette = the player ship.** Reuse the ship materials so a station reads as
   "same universe": hull cream `#e0dbc9`, structure dark metallic, solar blue,
   orange accents *sparingly*, green status lights. Never invent new hues.

## 4. Scale

Size is handled as a single number **L = longest dimension in metres**, with the
ISS as the yardstick (**ISS ≈ 109 m**). The generator's `--iss` flag sets L in ISS
multiples; `--game-scale` converts metres → Godot units for the emitted `.tscn`.

- Smallest useful station ≈ **0.5× ISS** (~55 m) — a core module, a node, one
  wing pair, one antenna.
- Largest showcase ≈ **20× ISS** (~2.2 km) — long trussed spine or a ring hub,
  many wing pairs, radiator banks, multiple rings/domes.

Power, radiator area, and part counts all grow with L (roughly with mass ∝ L³,
softened so huge stations stay readable rather than exploding in part count).

## 5. Generator contract (see `tools/station_gen.py --help`)

- **Inputs:** rough size (`--iss` or `--meters`), `--min-panels`, `--min-labs`,
  `--min-habs`, `--seed`, `--archetype {auto,stack,truss,ring}`, `--count`,
  `--game-scale`, `--out`.
- **Pipeline:** seed RNG → choose archetype for the size → lay out the spine →
  attach modules (labs/habitats/nodes/ports) → attach truss/booms → mount solar
  wings + radiators clear of the hull → antennas/cupola/accents → **validate**
  (AABB non-interference, min-count constraints, "not all identical") → serialise
  to a Godot `.tscn` that references the ship materials, plus a `.json` blueprint.
- **Failure is explicit:** if constraints can't be met (e.g. min-panels won't fit
  the chosen size) the tool reports why and exits non-zero rather than emitting a
  clipping mess.

## 6. Next-iteration changes (Taowu playtest feedback, 2026-07-25)

The generator works and reads plausibly, but three changes are wanted next. Not
yet implemented — captured here and in `tools/station_gen_PROGRESS.md`.

1. **Thinner solar panels.** The blankets are currently *way* too thick — they read
   as slabs even for a toy solar system. Drop the panel/blanket Y-thickness hard
   (today `meters * 0.006`; try ~`meters * 0.0015` or a small absolute floor), and
   thin the radiator fins similarly. Panels should look like foil, not plywood.
2. **More part variety / more part *types*.** Stations should feel more complex and
   varied — and parts **need not be realistic** (quasi-sci-fi). Add new distinct
   part kinds beyond the current cylinder/box/torus/sphere vocabulary and their
   handful of roles: e.g. domes/blisters, greebled truss-lattice bays, tanks/spheres
   clusters, dishes of varying size, a robotic arm, docked tugs, comms masts,
   antennae farms, angled/tapered hull sections, decorative fins. Goal: any two
   stations look clearly *different in kind*, not just in size/count.
3. **Allow HYBRID / mixed archetypes.** Retire the "pick ONE archetype per station"
   rule (see §2). A station may compose several forms at once — the canonical
   example: a **dual-keel frame carrying a giant dome and a rotating ring**. The
   generator should be able to graft archetype "modules of form" onto a shared
   spine/frame and still pass the non-interference validator. Keep the shared
   palette + connection logic as the coherence anchor. This is the big structural
   change; the current per-archetype builders are the building blocks to compose.
