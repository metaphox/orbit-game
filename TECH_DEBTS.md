# Tech Debts

A living registry of known tech debt in this codebase, plus the plan to pay it
down. **Convention:** whenever a change knowingly introduces debt — a shortcut,
a hardcode, a "fix-later" — add a row to the table below (what, where, why it
was deferred). Keep this current; it's cheaper than rediscovering the debt.

The debt is currently concentrated in the **view/UI layer**; the sim/campaign
core is clean and well-tested.

## Registry

| ID | Debt | Where | Status |
|---|---|---|---|
| TD-1 | No shared UI theme — system fonts and duplicated per-screen styling prevented consistent, scene-authored UI | `src/ui/*_screen.gd`, `pause_menu.gd`, `level_select.gd`, `hud.gd` | **Paid** — `UiTheme.shared()` now caches one generated Godot `Theme`, sourced only from `Palette` and the bundled Chakra Petch / IBM Plex Mono fonts. Reusable type variations cover titles, mono copy, eyebrows, HUD values, panels, toolbar, primary, and danger controls. The complete HUD hierarchy lives in `hud_layout.tscn` and focused typed component scenes; `Hud` is a compatibility-preserving coordinator. Title, profile, mission-select, settings, credits, and pause layouts are scene-owned and inherit the same theme. No `SystemFont.new()` calls remain. |
| TD-2 | `flight_view.gd` is a ~1000-line god object rendering cameras, bodies, trajectory, markers, station, hologram, starfield, node visuals — all in one file | `src/ui/flight_view.gd` | **Paid** (Phase 4) — decomposed **993→117 lines**, now a thin orchestrator delegating to five focused collaborators: `CameraRig`, `BodyRenderer`, `TrajectoryRenderer`, `ManeuverVisuals`, `ShipVisuals` (the rendezvous station lives with `ShipVisuals`, sized as a matched pair with the ship posture marker). Each extraction pinned by unit tests + baseline screenshot diff (orbit views byte-identical; chase diffs within star-dust noise). |
| TD-3 | Visuals hardcoded (materials, shaders, colors, meshes inline) — blocks the "Themes" feature | `src/ui/flight_view.gd`, `map_view.gd`, shaders | **Paid** — the `RenderTheme` seam is proven swappable end-to-end, and **every flight-view surface colour now reads from it**: env/atmosphere/bodies/trajectory, plus the player craft's typed `ShipSkin`, target ring, corridor band, node ghost, all seven orbit marks, prograde/retrograde, and the posture marker (theme threaded into `ManeuverVisuals` + `ShipVisuals` as an optional param). The craft OBJ now supplies only geometry and stable material-slot names; a theme-selected `.tres` skin explicitly overrides every surface, ready for future texture-backed materials. **Intentional exceptions:** the chase-camera fill light + star-dust particle tint stay inline (lighting/particle detail, not themeable surfaces); the rendezvous station is a shared `.tscn` (`station_model`); and the minimap (`map_view`) deliberately draws the semantic `Palette` colours (own=green, target=cyan) rather than a swappable theme. **CR-6 pass:** the sun lens-flare tints moved into `RenderTheme` (`flare_*`), and the remaining stray literals (debug-grid, minimap ship-nose, map label-shadow, `TRANSPARENT`) moved into `Palette`; the one baked minimap colour in `hud_layout.tscn` is now transparent (the real fill is applied at runtime from `Palette.MAP_BG`). A seam lint (`tools/lint_ui_colors.sh`, wired into `tools/test.sh`) now rejects any raw `Color(<number>...)` in `src/ui` outside `palette.gd`/`render_theme.gd`; the two inline exceptions carry a `# lint-ok:` marker. **Coverage gap (post–UI-revamp):** the lint scans `.gd` only, not `.tscn`/`.tres`. New menu/HUD chrome scenes stay colour-clean by using `theme_type_variation`; the player-ship material resources are owned by `RenderTheme.ship_skin`, while two 3D **material** scenes still hold baked colours — `station_model.tscn` (a documented exception) and `map_view_layout.tscn`'s minimap-grid materials (undocumented; small, pre-existing). Not machine-enforced. |
| TD-4 | Gameplay input partly bypasses InputMap (raw `KEY_H` rewind, `KEY_J` autopilot); no key rebinding | `src/game_root.gd` | **Paid** (Phase 3) — `InputBindings` registers the rewind/autopilot actions; `game_root` uses `is_action_pressed`; rebinds persist in Settings + apply at startup (`apply_overrides`). Note: the rebind *UI* is left to the deferred menu redesign — mechanism is done and unit-tested. |
| TD-5 | `Settings` is 2 static vars with no store — no room for audio, theme choice, rebinds, window prefs | `src/campaign/settings.gd` | **Paid** (Phase 2) — typed key→value store with `DEFAULTS`, persisted via `ProfileStore` under `"settings"` (old top-level `effects_enabled` migrates); seeded for audio/rebind keys |
| TD-6 | The test runner silently drops test files that fail to parse (a broken file went from 162→161 unnoticed while still reporting "all passed") | `tools/test.sh` | **Paid** (Phase 0) |
| TD-7 | HUD rebuild shortcut: the OBJECTIVE card renders `objective.status_lines(ship)` as one mono block, so the label/value columns are only approximately aligned (proper two-column would need objectives to return `(label, value)` pairs) | `src/ui/minimap_objective_rail.gd`, `src/objectives/*.gd` | **Open** (objective columns only). **Toolbar resolved (CR-5):** the bottom strip (`flight_toolbar.gd`, embedded in `propellant_flight_strip.gd`) is the *full* clickable control set per DESIGN §6 (VIEW/THROTTLE/WARP/SAS/NODE, capability-gated, wrapped across rows), and each chip emits a semantic **action** — `game_root` replays the action's current binding, so buttons follow rebinds instead of breaking. Button labels derive from `InputBindings.primary_key_label`. |

## Payoff plan

Ordered by dependency and escalating risk; each phase ends with a green suite
and is independently shippable.

- **Phase 0 — TD-6.** This document + a hardened `tools/test.sh` that fails on any
  parse/load error and on a coverage drop below `tests/.test-baseline`.
- **Phase 1 — TD-1 (+ design-ref restyle).** Bundle Chakra Petch + IBM Plex Mono,
  make `Palette` the single UI color source, build a shared Godot `Theme`, and
  apply the "ORBITAL OS" look (`ref/design-ref.html`) across every screen + HUD.
- **Phase 2 — TD-5.** Generalize `Settings` into a typed, persisted store
  (via `ProfileStore`'s atomic save), seeded for audio/rebind/theme keys.
- **Phase 3 — TD-4.** Move all input to InputMap actions; add a rebinding layer
  backed by the settings store.
- **Phase 4 — TD-2 & TD-3.** ✅ Done. Introduced the `RenderTheme` resource and
  decomposed `flight_view` (993→117 lines) into focused renderers — CameraRig,
  BodyRenderer, TrajectoryRenderer, ManeuverVisuals, ShipVisuals — that read from
  it. Extracted one collaborator at a time, each verified against baseline
  screenshots (orbit views byte-identical) and pinned by unit tests. TD-2 paid;
  TD-3 substantially paid (seam proven swappable; some inline colours remain).

## Notes for future debt entries

Include: what the shortcut is, the file(s), why it was acceptable to defer, and
what "done" looks like. Link the phase/PR that pays it when scheduled.
