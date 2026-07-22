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
| TD-1 | No shared UI theme — `SystemFont.new()` in 9 files, `const GREEN`/`DIM_GREEN` copy-pasted across 7 screens; `Palette` only used by the 3D views | `src/ui/*_screen.gd`, `pause_menu.gd`, `level_select.gd`, `hud.gd` | **Partly paid** — foundation (bundled fonts, `Palette` as sole colour source, `UiTheme`) built; `title_screen` + `hud` migrated. **Remaining/deferred:** the other menu screens (`new_profile`, `load_profile`, `settings`, `credits`, `level_select`, `pause_menu`) still use `SystemFont.new()` + local colour consts — deferred to the later UI-redesign stage per owner's call. |
| TD-2 | `flight_view.gd` is a ~1000-line god object rendering cameras, bodies, trajectory, markers, station, hologram, starfield, node visuals — all in one file | `src/ui/flight_view.gd` | **In progress** (Phase 4) — `BodyRenderer` (993→813) + `CameraRig` (813→751) extracted, each pinned by unit tests + baseline screenshot diff (orbit views byte-identical). Remaining collaborators: TrajectoryRenderer, ManeuverVisuals, ShipVisuals. |
| TD-3 | Visuals hardcoded (materials, shaders, colors, meshes inline) — blocks the "Themes" feature | `src/ui/flight_view.gd`, `map_view.gd`, shaders | **In progress** (Phase 4) — `RenderTheme` resource introduced (env, bodies, atmosphere, trajectory colours); `flight_view` + `BodyRenderer` read from it. Marker/orbit-mark colours still inline. |
| TD-4 | Gameplay input partly bypasses InputMap (raw `KEY_H` rewind, `KEY_J` autopilot); no key rebinding | `src/game_root.gd` | **Paid** (Phase 3) — `InputBindings` registers the rewind/autopilot actions; `game_root` uses `is_action_pressed`; rebinds persist in Settings + apply at startup (`apply_overrides`). Note: the rebind *UI* is left to the deferred menu redesign — mechanism is done and unit-tested. |
| TD-5 | `Settings` is 2 static vars with no store — no room for audio, theme choice, rebinds, window prefs | `src/campaign/settings.gd` | **Paid** (Phase 2) — typed key→value store with `DEFAULTS`, persisted via `ProfileStore` under `"settings"` (old top-level `effects_enabled` migrates); seeded for audio/rebind keys |
| TD-6 | The test runner silently drops test files that fail to parse (a broken file went from 162→161 unnoticed while still reporting "all passed") | `tools/test.sh` | **Paid** (Phase 0) |

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
- **Phase 4 — TD-2 & TD-3.** Introduce a `RenderTheme` resource and decompose
  `flight_view` into focused renderers (CameraRig, BodyRenderer,
  TrajectoryRenderer, ManeuverVisuals, ShipVisuals) that read from it. One
  collaborator at a time, verified against baseline screenshots — no visual change.

## Notes for future debt entries

Include: what the shortcut is, the file(s), why it was acceptable to defer, and
what "done" looks like. Link the phase/PR that pays it when scheduled.
