# Space-station design research

Real, cited design inspiration for the procedural station generator (`tools/station_gen.py`).
Feeds the design rules in `STATIONS.md`. Everything below is sourced; URLs in the
bibliography. Focus is on **structural logic that reads as plausible** — what parts exist,
how they're arranged, and what proportions make a shape "click" as a real station.

---

## 1. The ISS *planned*-design saga (1984–1993)

A decade of redesigns turned a von-Braun wheel dream into the modular truss we got. The
dropped ideas are a goldmine of readable, distinctive silhouettes.

### 1984 — "Power Tower"
First reference configuration from the new Space Station Program Office at JSC (April 1984).
- A **~400 ft (122 m) vertical keel** (single mast) hanging in a gravity-gradient orientation,
  pointed at Earth.
- **Mass concentrated at both ends** so the gravity gradient keeps it aligned without constant
  thruster firing (a real orbital-mechanics trick — long axis wants to point at Earth).
- Modules clustered at the **bottom**, articulated solar arrays branching from the **middle**,
  astronomy payloads at the **top**, plus a **servicing bay**.
- Takeaway: a tall thin spine, heavy top and bottom, arrays amidships — a very legible "totem" shape.

### 1985–86 — "Dual Keel"
Redesign that moved modules to the center of gravity for a steadier microgravity environment.
- A **rectangular truss loop ~310 ft × 150 ft (94 × 46 m)**, assembled in orbit from cubic
  **16 ft × 16 ft (5 m) truss bays**.
- Two vertical keels joined by upper and lower transverse booms = a picture-frame with a
  horizontal boom across the middle carrying the pressurized modules and arrays.
- **Astronomy payloads on the top edge, Earth-sensing instruments on the bottom edge** (each end
  points where it wants to look).
- Room for **servicing hangars / free-flyer companion platforms**.
- Takeaway: the "picture-frame" / **dual-keel** silhouette is unmistakable and very sci-fi-industrial.
  Nobody actually flew it, so it reads as "alternate-history NASA."

### 1987 — "Revised Baseline" (post-Challenger)
Challenger (Jan 1986) forced a scale-back to reduce Shuttle assembly flights.
- **Keels deleted.** Reduced to a **single transverse boom** with solar arrays at each end and
  the lab/habitat modules clustered at the center.
- Phased assembly; ~75 kW power. This is essentially the "spine + end arrays" shape that survived
  all the way to ISS.

### 1988–91 — "Freedom" → Restructured
Named *Freedom* (1988). By 1990–91 it was **23% overweight, underpowered, and too complex to
assemble** (too many EVA hours). March 1991 restructuring trimmed it hard; first launch slipped
to 1995+.

### 1993 — Redesign, Options A/B/C, "Alpha"
Clinton ordered cheaper alternatives; a Station Redesign Team in Crystal City produced three:
- **Option A — "Modular Buildup"**: incremental, smaller modules; *this is the one chosen* (June 1993).
- **Option B**: closest to the existing *Freedom* / "Fred" design; most expensive; couldn't hit the
  5-year / $9B cap, so it died.
- **Option C**: a clean-sheet **single large-diameter can** — a Skylab-like "wet/dry workshop"
  monolith launched more or less whole, rather than trussed assembly.
- Result named **Space Station Alpha**, reusing ~**75%** of *Freedom* hardware designs. Days later
  the White House merged it with Russia's *Mir-2* program for foreign-policy reasons → **ISS**.

### How the final ISS differs from every early plan
- **No keels.** A single **Integrated Truss Structure (~109 m, aluminum + stainless)** — one long
  transverse spine carrying arrays and radiators, perpendicular to the pressurized-module stack.
- **No hangars, no servicing bay, no artificial-gravity provisions** — all proposed, all dropped.
- The pressurized volume is a **modular Lego of cylinders and nodes** (Zarya, Zvezda, Unity/Harmony
  nodes, Destiny lab…), not a purpose-built frame. Russian segment stacks/radials + US truss = a
  slightly asymmetric hybrid of two design philosophies bolted together.
- **8 solar array wings on alpha/beta gimbals; radiators mounted edge-on** on the truss.

**Generator takeaways from the saga:** the *dropped* shapes (Power Tower spine, Dual-Keel frame,
Option-C monolith) are more distinctive than the ISS itself and worth offering as archetypes.

---

## 2. Other real stations

### Salyut / Almaz (1971–, USSR) — the monolith
- **First generation = single module, no resupply, no expansion.** One can, ~4 m dia, a couple of
  solar wings, one docking port (Salyut 1). Almaz was the military variant (contributed gyrodyne
  flywheels + digital flight computer to later designs).
- Salyut 6 & 7 added a **second axial docking port** (fore + aft) → first refuelable/relievable stations.

### Skylab (1973) — the big dry can
- Converted **S-IVB stage: Orbital Workshop 14.7 m long × 6.7 m dia** — huge single volume.
- Was to be a **"wet workshop"** (fuel the stage, launch it, then vent and inhabit the spent tank).
  Cancelled Apollo landings freed a Saturn V, so it flew as a **"dry workshop"** (outfitted on the
  ground, launched whole) — this is the Option-C ancestor.
- **Apollo Telescope Mount**: an **octagonal structure 3.4 m dia × 4.4 m**, with its own **4 windmill
  solar arrays** (a cross/pinwheel), separate from the workshop's two main wings (111 m² total).
- **Skylab B**: a fully built backup workshop that never flew.
- Takeaway: a single fat cylinder + one perpendicular instrument mount with a **cruciform "windmill"
  array** is a strong, simple silhouette.

### Mir (1986–2001) — modular radial docking
- **Third-generation: first station built from multiple primary modules.** Core module had a
  **5-port node up front (1 axial + 4 radial at 90°)** plus an aft axial port = **6 ports total**.
- Modules (Kvant, Kristall, Spektr, Priroda…) berthed **radially** off that node, each purpose-built.
  The result is a lumpy, asymmetric **radial cluster** — a hub with modules sticking out in several
  directions, each with its own solar wings. Iconic "grown, not designed" look.

### Tiangong (2021–, China) — the T (→ cross)
- **Tianhe core** in the middle, **Wentian + Mengtian** labs berthed on **opposite radial ports** →
  clean **T-shape**. Planned growth to a **six-module cruciform/cross**.
- Notable: **large steerable solar wings** and a **Canadarm-like arm**; much tidier and more
  symmetric than Mir.

### Near-future commercial
- **Axiom Station**: modules first attach to ISS, later detach to free-fly — a **linear stack** of
  cylinders with a bell-end cupola ("Earth Observatory").
- **Orbital Reef** (Blue Origin + Sierra Space): **core node with many docking collars** (Dragon,
  Starliner, Dream Chaser, Soyuz all fit) + inflatable **LIFE** habitats → radial-node hub, ~10 crew.
- **Starlab** (Voyager + Airbus): **one big-diameter inflatable habitat + a service/power bus** —
  ~17 m tall × 7.7 m wide. A modern Option-C monolith with a large single solar/power truss.
- **Vast Haven-1**: **single rigid module** (Falcon 9-launchable), ~45 m³ habitable; **Haven-2**
  scales to multi-module.
- **Lunar Gateway**: tiny by comparison — **PPE (Power & Propulsion Element, big roll-out arrays +
  ion thrusters) + HALO habitat** launched **stacked**, then more modules. Deep-space, so **big power
  bus, minimal structure**.

**Generator takeaways:** four real structural logics — **monolith** (Salyut/Skylab/Starlab),
**linear stack** (Mir core/Axiom), **radial-node cluster** (Mir/Orbital Reef), **T/cross**
(Tiangong). Solar arrays are always **paired and broadside to the sun**; radiators edge-on.

---

## 3. Iconic sci-fi stations

### Rotating wheels / tori (spin gravity)
- **2001's Space Station V**: a **double wheel** (two concentric rings), a von-Braun descendant,
  used as an orbital transfer hub with docking at the **hub along the spin axis** (ships approach the
  non-rotating center). One wheel complete, the second still under construction — a great "in-progress"
  visual motif.
- **Stanford Torus** (NASA 1975 SP-413): **1.8 km (1 mi) dia ring, 1 rpm → 1 g**, houses 10,000. A
  large mirror ring reflects sunlight into the habitat ring. Ring + hub + spokes.
- **Elysium**: open **Stanford-torus** — inner rim *open to space* (dramatic license), spokes to a hub.

### Cylinders (O'Neill)
- **O'Neill Cylinder** (NASA 1975): **paired counter-rotating cylinders, ~32 km long × 6.4 km dia**,
  three land "valleys" alternating with three window strips, hinged mirrors making day/night. The pair
  counter-rotate to cancel gyroscopic precession.
- **Babylon 5**: explicitly an **O'Neill-type cylinder, ~8 km (5 mi) long**; rotating hull = spin
  gravity, docking bay along the axis, external "fins"/heat-radiator spine.
- **Interstellar's Cooper Station**: classic **O'Neill cylinder** interior (fields, houses on the
  curved-up inner wall).
- **Rama** (*Rendezvous with Rama*): a **~50 km long × 16 km dia perfect cylinder**, spun for gravity,
  interior "Cylindrical Sea" band, three-fold radial symmetry (features in triples at 120°).

### Spheres & drums
- **Bernal Sphere** (NASA 1975): **~500 m sphere**, spins about an axis; agriculture rings stacked
  along the axis outside the sphere. Babylon-5's silhouette is often compared to it.
- **The Expanse — Tycho Station**: a **construction ring/drum ~0.5 km sphere with two counter-rotating
  habitation rings**; a working shipyard hub, not a pristine wheel — scaffolding, cranes, ships docked
  radially.
- **The Expanse — spun-up asteroids** (Ceres/Eros): asteroids **hollowed and spun** so gravity points
  *outward* toward the surface; Coriolis makes "down" tilt and lessen as you go deeper toward the axis.

### Modular / non-rotating sci-fi
- **Deep Space Nine** (Cardassian): **>1 km dia**; **three concentric rings** — outer **docking ring**
  with radial **docking pylons that curve up**, inner **habitat ring**, and a **central core** (Promenade,
  reactors, Ops). Strong **radial symmetry** with dramatic swept pylons.
- **Elite's Coriolis**: a **cuboctahedron ~2 km** (square + triangular faces), *slowly rotating*, ships
  enter a **slot in one face** aligned with the rotation. Orbis/Ocellus are later geometric-shell variants.
- **Star Citizen / general game stations**: **central spine or ring + radial docking arms**, running
  lights everywhere, layered greebled panels.

**Recurring motifs to steal:** (1) **rotating ring/wheel/cylinder for gravity**, with a **non-rotating
axial hub where ships dock**; (2) **spokes** connecting hub to ring; (3) **strong radial symmetry**
(pairs, triples at 120°, quads at 90°); (4) a **central spine** everything hangs off; (5) **docking
bays along the spin axis**; (6) an "**under construction**" look (partial ring, scaffolding) that makes
a station feel lived-in.

---

## 4. Structural archetypes worth implementing

Pick ONE per station. Each with the proportions/rules that make it read as plausible.

1. **Monolith** (Salyut, Skylab dry workshop, Starlab, Option C)
   - One fat cylinder, **L/D ≈ 2–3**. 1–2 solar wing pairs near one end, 1 docking port each axial end,
     one perpendicular instrument mount optional. Smallest, simplest silhouette.

2. **Linear module stack** (Mir core, Axiom, Tiangong core)
   - Cylinders **end-to-end on one axis**, varying length/diameter, joined by short fat **nodes**.
     Solar wings in pairs near the ends. Length grows with size; keep diameter roughly constant so
     it reads as "same kit."

3. **Truss spine** (ISS, Revised-Baseline Freedom)
   - Module stack on one axis; a **perpendicular box-truss ~1× the module-stack length** carrying the
     big arrays and radiators **well clear** of the hull. Arrays at the truss ends, radiators mid-truss
     edge-on. The workhorse "big real station."

4. **Dual-keel frame** (Freedom 1986 — never flew)
   - A **rectangular truss loop, aspect ~2:1**, built from repeated **cubic bays** (~5 m). A horizontal
     boom across the middle holds modules + arrays; top and bottom edges carry instruments pointing out.
     Distinctive "picture-frame." Medium/large only.

5. **Power-Tower totem** (Freedom 1984 — never flew)
   - A **tall thin single keel**, mass at both ends, arrays amidships, modules at one end. Reads as a
     gravity-gradient "hanging" station. Great vertical showcase.

6. **Radial-node cluster** (Mir, Orbital Reef)
   - A central **node with 4–6 ports (1 axial + radials at 90°)**; purpose-built modules stick out
     radially, each with its own small wings. Deliberately **asymmetric / "grown"**. Cap the sprawl.

7. **Rotating wheel / torus** (2001, Stanford Torus, Elysium)
   - A **non-rotating axial hub** (where ships dock) + **spokes (2–6, radial-symmetric)** + one or more
     **rings**. Ring radius must clear the module envelope; **ring cross-section ≪ ring radius**
     (**R/r ≈ 10–30**). Optional **second concentric wheel** or partial ("under construction") ring.

8. **O'Neill / Rama cylinder** (Babylon 5, Cooper, Rama)
   - A **long rotating cylinder, L/D ≈ 3–8** (B5) up to extreme (Rama ~3), spin axis = long axis,
     **docking bay on one axial endcap**, external spine ribs / radiator fins along the hull. Optional
     **counter-rotating pair** on a shared axis. The "big showcase" alt to the wheel.

9. **Geometric shell** (Elite Coriolis/Orbis)
   - A **cuboctahedron or faceted polyhedron**, slowly rotating, with a **docking slot in one face**
     aligned to the spin. Radial arms/antennas off the vertices. Stylized, game-y, instantly readable.

(Existing `STATIONS.md` covers Stack / Truss / Ring — archetypes 4, 5, 6, 8, 9 are the new candidates.)

---

## 5. Signature details that sell realism

These are the cheap-to-add cues that make any silhouette read as a *real* station:

- **Paired, sun-tracking solar arrays** — always mirrored pairs, broadside to the "sun" axis, on
  booms/gimbals that hold them **clear of the hull**. Long thin rectangular wings, faint blue cell grid.
- **Radiators edge-on to the sun** — flat white/silver panels **perpendicular to the arrays**, mounted
  on the truss, never on the modules. Often in banks of 2–3.
- **High-gain dish antenna(s)** on a mast/gimbal (1–4), plus small whip/patch antennas.
- **Docking nodes with multiple ports** — short fat cylinders with visible collars/cones; radial ports
  at 90°, axial ports at the ends. A ship or two berthed radially reads as "active."
- **Micrometeoroid blankets / MMOD shielding** — quilted gold/white multi-layer insulation and offset
  "standoff" bumper panels over the modules; the quilted texture is a strong realism cue.
- **Robotic arm** (Canadarm2-style) — a jointed arm on a rail/base, ideally caught mid-reach; instantly
  says "under construction / serviced."
- **Running/nav lights** — small green/red/white points along edges and at ports; sparse, not a light show.
- **Truss lattice / greebling** — repeated cubic bays and cabling read as engineered structure.
- **"Under construction" motif** — a partial ring, exposed truss bay, or docked tug/cargo module makes
  the station feel lived-in rather than a sterile prop.
- **Orientation logic** — instruments point where they look (Earth-sensing down, astronomy up/out),
  radiators edge-on, arrays face the sun. Coherent aiming = plausibility.

---

## Bibliography

- Space Station Freedom — Wikipedia: https://en.wikipedia.org/wiki/Space_Station_Freedom
- Design & Assembly of the ISS — Defense Media Network: https://www.defensemedianetwork.com/stories/design-and-assembly-of-the-international-space-station/
- Space Station 20th: Historical Origins of ISS — NASA: https://www.nasa.gov/history/space-station-20th-historical-origins-of-iss/
- Dual Keel Space Station 1985 — Astronautix: http://www.astronautix.com/d/dualkeelspaestation-1985.html
- Model, Space Station, Dual Keel — Smithsonian NASM: https://airandspace.si.edu/collection-objects/model-space-station-dual-keel/nasm_A20100236000
- Space Station Options 1993 — Astronautix: http://www.astronautix.com/s/spacestationoptions1993.html
- Space Station Redesign Option A (Modular buildup) — NASA NTRS: https://ntrs.nasa.gov/citations/19940006353
- Space Station Redesign fact sheet — Clinton White House archive: https://clintonwhitehouse3.archives.gov/WH/EOP/OSTP/other/spstfact.html
- Space Station "Fred" — Astronautix: http://www.astronautix.com/s/spacestationfred.html
- Integrated Truss Structure — Wikipedia: https://en.wikipedia.org/wiki/Integrated_Truss_Structure
- Integrated Truss Structure — NASA: https://www.nasa.gov/international-space-station/integrated-truss-structure/
- Zvezda (ISS module) — Wikipedia: https://en.wikipedia.org/wiki/Zvezda_(ISS_module)
- Canadarm2 — Canadian Space Agency: https://www.asc-csa.gc.ca/eng/iss/canadarm2/about.asp
- ISS MMOD shielding — Acta Astronautica (abstract): https://ui.adsabs.harvard.edu/abs/2009AcAau..65..921C/abstract
- Mir — Astronautix: http://www.astronautix.com/m/mir.html
- Mir-2 — Wikipedia: https://en.wikipedia.org/wiki/Mir-2
- Soviet Space Stations: Salyut to Mir: https://sovietspaceprogram.com/space-stations/
- Skylab — Historic Spacecraft: https://historicspacecraft.com/skylab.html
- Apollo Telescope Mount — HandWiki: https://handwiki.org/wiki/Astronomy:Apollo_Telescope_Mount
- Orbital Workshop — Astronautix: http://astronautix.com/o/orbitalworkshop.html
- Design & Application Prospect of China's Tiangong — Space: Science & Technology: https://spj.science.org/doi/10.34133/space.0035
- Gateway PPE — NASA: https://www.nasa.gov/missions/artemis/gateway/a-powerhouse-in-deep-space-gateways-power-and-propulsion-element/
- Commercial Space Stations — NASA: https://www.nasa.gov/humans-in-space/commercial-space/commercial-space-stations/
- The Future of Space Stations, Part II: Commercial — Universe Today: https://www.universetoday.com/articles/the-future-of-space-stations-part-ii-commercial-space
- Stanford torus — Wikipedia: https://en.wikipedia.org/wiki/Stanford_torus
- Bernal sphere — Wikipedia: https://en.wikipedia.org/wiki/Bernal_sphere
- Space Colony Form Factors: Stanford Torus and Beyond — Core77: https://www.core77.com/posts/39727/space-colony-form-factors-part-3-the-stanford-torus-and-beyond
- Space Station V — 2001 Wiki: https://2001.fandom.com/wiki/Space_Station_V
- 7 Awesome Sci-Fi Space Stations — Space.com: https://www.space.com/22288-awesome-space-stations-science-fiction.html
- Deep Space Nine (fictional space station) — Wikipedia: https://en.wikipedia.org/wiki/Deep_Space_Nine_(fictional_space_station)
- Tycho Station — The Expanse Wiki: https://expanse.fandom.com/wiki/Tycho_Station
- Cooper Station (Interstellar) analysis — GS Talk: https://gstalk.substack.com/p/what-would-it-take-to-build-cooper
- Coriolis — Elite Dangerous Wiki: https://elite-dangerous.fandom.com/wiki/Coriolis
