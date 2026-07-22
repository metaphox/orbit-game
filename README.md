# Limited Propellant

**KSP distilled to "burn fuel to change orbit," in a NASA‑punk retro‑futurist skin.**

*Limited Propellant* (**LP** — also *Lambert's Problem*) is a level‑based 3D
orbital‑mechanics game built in Godot. Each level hands you a
single spacecraft with a fixed tank of propellant and one job: raise an orbit,
rendezvous with a station, slip through a plane change, transfer to the Moon,
land on it, come home through an entry corridor, or make the crossing to Mars.
The physics is real in *shape* — Kepler orbits, patched conics, the rocket
equation — with constants tuned for pacing rather than SI accuracy. The look is
late‑70s spaceflight: Apollo hardware and green‑phosphor flight computers.

> **This is a vertical slice, open‑sourced as a playable demo of a larger game.**
> Seven levels exercise every mechanic and every act; the full campaign (15–20
> levels) and a second difficulty axis are designed but not built. See
> [What's intentionally left out](#whats-intentionally-left-out) and
> [`DESIGN.md`](DESIGN.md) §13. Contributions to the open parts are welcome.

---

## The core idea

**The burn is the game.** Everything reduces to one question asked in a hundred
shapes: *when, in which direction, and for how long do you fire the engine?*
There is no rocket building, no staging, no life support, no docking minigame —
nothing that dilutes the single decision at the heart of spaceflight. You get a
ship, a target, a Δv budget, and a trajectory you can read.

Three principles hold the whole thing together:

- **Plausible, not pedantic.** If a physicist squints, it holds up in form. The
  numbers are tuned so a low orbit takes ~5–7 minutes at 1× time and the system
  is ~1/100 real scale, but Hohmann transfers, phase angles, spheres of
  influence, and Tsiolkovsky all behave the way they really do.
- **Failure is information.** Physics is deterministic, retries are instant and
  free, and the trajectory feedback is honest. You should always finish an
  attempt knowing *why* it failed — too fast, wrong phase, periapsis too low.
- **Two coherent halves of one fiction.** The world (chase & orbit cameras) is
  modeled Apollo‑era hardware over a procedural starfield with aged‑footage film
  grade. The instruments (minimap, ship status hologram) are vector‑CRT mission
  computers — scanlines, phosphor glow, barrel curve.

## Why it's fun to play

The satisfying loop is *reading a trajectory and bending it with one well‑placed
burn.* A few moments the current levels are built around:

- Watching your dashed **target ring** and your glowing orbit line drift apart,
  nudging prograde at apoapsis, and seeing the ellipse snap into a circle.
- Realizing that to **catch** the station ahead of you, you drop to a *lower,
  faster* orbit and let orbital mechanics do the chasing — the counterintuitive
  click that rendezvous always delivers.
- Timing a **trans‑lunar injection** so the Moon is where your apoapsis will be,
  coasting for (warped) hours, and feeling the frame hand off as you cross into
  the Moon's sphere of influence.
- Flying a **suicide burn** onto the lunar surface: free‑falling to save fuel,
  then braking hard and late, threading the touchdown under the speed limits.
- Waiting for the **Mars window**, burning out of Earth's gravity well, and
  correcting mid‑flight to intercept a planet that has moved millions of km by
  the time you arrive.

Time is a resource too. A 9‑step warp ladder (`1×` → `1000×`) fast‑forwards the
coasts, but rails warp automatically clamps to the next thing that matters —
impact, an SOI boundary, a planned maneuver node — so it can never skip past the
moment you were waiting for.

## What physics it teaches

Each objective type is a lesson in disguise. Play the seven levels and you will
have internalized, by feel:

| Level (objective) | What it teaches |
|---|---|
| Orbit School 1 — raise orbit (`OrbitMatch`) | Apoapsis/periapsis, circular orbital velocity, why a Hohmann transfer burns at the two apsides |
| Orbit School 2 — rendezvous (`Rendezvous`) | Phasing, relative velocity, "burn to change *where you'll be*, not where you are" |
| Orbit School 3 — plane change (`OrbitMatch` + inclination) | Plane changes are brutally expensive and belong at the orbital nodes |
| Lunar Program 1 — TLI (`TransferCapture`) | Transfer windows, phase‑angle lead, spheres of influence, patched‑conic capture burns |
| Lunar Program 2 — landing (`AirlessLanding`) | Powered descent, gravity losses, the suicide‑burn tradeoff |
| Lunar Program 3 — come home (`EntryCorridor`) | Trans‑Earth injection and targeting a reentry periapsis band |
| Interplanetary 1 — Earth→Mars (`TransferCapture`, one SOI deeper) | Heliocentric transfers, launch windows, mid‑course correction to a moving target |

Underneath all of them: the **rocket equation** — the HUD always shows both your
propellant fraction and your remaining Δv, so you learn to think in a Δv budget,
and to feel how acceleration climbs as the tank empties.

## What's intentionally left out

Two kinds of omission — deliberate design boundaries, and simply not‑built‑yet.

**Design boundaries (out of scope on purpose):** atmospheric flight / drag /
heating (entry corridors hand off to "the capsule takes it from here" — no
atmosphere is ever simulated), staging & rocket building, docking (rendezvous
ends on proximity), n‑body effects and Lagrange points, mobile, life
support/comms/thermal. One ship per level, one continuous 3D space, one decision.

**Not built yet (the "bigger game" this demo points at):**

- **The campaign.** Seven levels is a vertical slice that touches every act and
  every objective type. The intended game is **15–20 levels**, with their Δv
  pars tuned by real playtesting (possibly a second Act 3 destination — Venus was
  floated).
- **RCS / rotation‑cost.** The planned *second difficulty axis*: rotation is free
  everywhere right now; later levels are meant to charge propellant for attitude
  changes. Designed (`DESIGN.md` §4.4), not yet introduced.
- **Web export, audio, and narrative framing** — all deferred, none started.

See [`DESIGN.md`](DESIGN.md) for the full design record (including *why*
implementation diverged from the plan where it did) and §13 for the open list.

## Running it

Requires **[Godot 4.7](https://godotengine.org/download)** (built and tested on
4.7.1 stable). No other dependencies — the orbital math is hand‑rolled pure
GDScript, and the only addon (GUT, for tests) is vendored in `addons/`.

**From the editor:** open the project folder in Godot and press ▶ (Play). The
main scene is `src/campaign_root.tscn` (title → profile → mission select →
flight).

**From the command line:**

```sh
godot --path .
```

**Debug mode** unlocks every level, shows an FPS readout, and enables the
built‑in autopilot (below):

```sh
godot --path . --debug-mode
```

### Watch it fly itself

In debug mode, press **`J`** on any mission to engage the **flight director** —
a live autopilot that flies the level to its win condition through the real
simulation, narrating each maneuver in the HUD (`TRANS‑LUNAR INJECTION`,
`COAST TO MOON SOI`, `CAPTURE BURN`, …). It's both a reference solution to learn
from and a regression harness: every level is verified to be winnable, headless,
in `tests/`. Handy when you're tuning a level or trying to understand a transfer.

## Building / exporting

Release builds for macOS, Windows, and Linux go through one script (requires the
Godot 4.7.1 export templates installed via **Editor → Manage Export Templates**):

```sh
./tools/export.sh      # → build/{macos,windows,linux}/
```

Export presets live in `export_presets.cfg` (committed; no secrets).

## Tests

The orbital‑math core is the one place bugs are silent and catastrophic, so it's
covered by a headless [GUT](https://github.com/bitwes/Gut) suite — round‑trip
conversions, energy/momentum conservation on rails, integrator‑vs‑closed‑form,
SOI‑crossing detection against brute force, plus full‑game‑loop tests that fly
each level (including the autopilot) to a win.

```sh
./tools/test.sh        # imports, then runs the suite headless
```

## Repository layout

```
src/
  core/          # pure math, no Nodes: conics, kepler, integrator, frames, Lambert
  sim/           # ShipSim, BodyDef, ManeuverNode, SOI logic
  objectives/    # the five win/fail predicate classes
  ui/            # HUD, flight/orbit/minimap views, screens
  levels/data/   # level_01..07 as .tres resources (edit in the Inspector)
  autopilot/     # the live flight director (debug feature)
  campaign/      # profiles, save/resume, settings
  shaders/       # CRT, film grade, starfield
tests/           # GUT unit + full-loop tests
tools/           # test.sh, export.sh
DESIGN.md        # the design record — read this first
PLAN.md          # milestone-by-milestone build history
```

Levels are plain Godot `Resource` files (`src/levels/data/*.tres`): body
hierarchy, ship stats, objective, and Δv par are all Inspector‑editable data —
no code needed to author a new mission.

## Contributing

The open work is exactly the "not built yet" list above. High‑value places to
start:

- **New levels.** Author a `LevelDef` `.tres` (copy an existing one), set the
  bodies/ship/objective/par, and add it to the `Campaign` registry. The autopilot
  and tests give you fast feedback on whether it's winnable and roughly how much
  Δv it costs.
- **Δv‑par tuning** through real play — the current pars are author estimates.
- **RCS / rotation‑cost** (`DESIGN.md` §4.4) — the designed‑but‑unbuilt second
  difficulty axis.
- **Audio, web export, narrative** — all greenfield.

Ground rules from the project's own conventions:

- The `src/core` orbital library stays **pure GDScript, no Node dependencies** —
  it must remain unit‑testable headless.
- **Every change keeps the test suite green** (`./tools/test.sh`). Physics and
  level‑winnability changes should add or update a test.
- Prefer self‑documenting code; match the surrounding style.
- Update `DESIGN.md` when you change a design decision — it's the shared source
  of truth, "a record of decisions, not just a spec."

Please open an issue to discuss anything larger than a level or a bug fix so it
can be checked against the design intent first.

## License

_No license has been chosen yet._ Before redistributing, add a `LICENSE` file —
a permissive license (MIT or Apache‑2.0) is the intended direction for the
open‑source demo. The vendored GUT addon under `addons/gut/` is MIT‑licensed by
its authors and retains its own license.
