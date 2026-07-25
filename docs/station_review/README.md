# Station generator iteration review

Five deterministic examples exercise the connected-assembly validator, module
windows/lights, sun-tracking tilt, all four foldable solar families, and the
load-sized accordion radiators. Each PNG contains SIDE, TOP, and END orthographic
views and labels the report-only organisation score. Requested and resolved seeds
differ when invalid candidates were skipped; both are preserved in the blueprint.

| Example | Form / size / requested → resolved seed | Array / radiator ratio / score | Review focus | Files |
|---|---|---|---|---|
| A | Stack / 1× ISS / 4 → 4 | Accordion / 30.7% / 96.9 | Two narrow reference-scale radiator wings, tilted arrays, and readable module windows | [PNG](station_00_stack_010i.png) · [scene](../../assets/station_review/station_00_stack_010i.tscn) · [blueprint](../../assets/station_review/station_00_stack_010i.json) |
| B | Truss / 3× ISS / 8 → 8 | Round umbrella / 27.9% / 91.2 | One long accordion radiator, radial solar ribs, open lattice, and window rhythm | [PNG](station_00_truss_030i.png) · [scene](../../assets/station_review/station_00_truss_030i.tscn) · [blueprint](../../assets/station_review/station_00_truss_030i.json) |
| C | Dual-keel + ring + dome / 6× ISS / 14 → 14 | Honeycomb / 27.2% / 75.8 | Pressure trunk and broad vestibule visibly connect the observatory to a crew module | [PNG](station_00_hybrid_dualkeel_ring_dome_060i.png) · [scene](../../assets/station_review/station_00_hybrid_dualkeel_ring_dome_060i.tscn) · [blueprint](../../assets/station_review/station_00_hybrid_dualkeel_ring_dome_060i.json) |
| D | Truss + ring + radial / 10× ISS / 45 → 247 | Petal fan / 27.2% / 70.0 | Polygon leaves, two segmented radiator banks, and radial pressure tunnels | [PNG](station_00_hybrid_truss_ring_radial_100i.png) · [scene](../../assets/station_review/station_00_hybrid_truss_ring_radial_100i.tscn) · [blueprint](../../assets/station_review/station_00_hybrid_truss_ring_radial_100i.json) |
| E | Power tower + ring + tank farm / 16× ISS / 5 → 2631 | Accordion / 33.6% / 69.6 | Six-bank high-power cooling profile, coherent repeated bays, and long-keel organisation | [PNG](station_00_hybrid_power_ring_tank_farm_160i.png) · [scene](../../assets/station_review/station_00_hybrid_power_ring_tank_farm_160i.tscn) · [blueprint](../../assets/station_review/station_00_hybrid_power_ring_tank_farm_160i.json) |

Questions for the review:

- Do the four array families read as foldable mechanisms rather than decorative tiles?
- Does the shared sun-facing normal still leave enough visible tilt variation?
- Do the windows/lights make labs and habitats feel occupied without becoming noisy?
- Does example C's pressure trunk make the large dome feel genuinely connected?
- Do the 6–8-panel radiator wings read as appropriately narrow cooling hardware,
  especially the ordinary 27–31% cases versus example E's 33.6% high-power case?
- Rank the five stations by organisation before looking at the numeric score; those
  rankings will calibrate the weights before candidate selection is enabled.

The previews are palette-accurate diagrams, not final lit Godot renders. Geometry,
scale, placement, and material assignment match the emitted scenes.
