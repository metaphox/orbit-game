# Contributor & Agent Guide

Conventions for anyone (human or AI) writing code in this repo. Read this before
touching anything. It captures *how* we build; **`DESIGN.md` is the source of
truth for *what* we build** — change the design doc before changing behaviour.

## 0. Ground rules

- **Never commit.** Version control is the human owner's job — do not `git commit`
  or `git add` on your own, and do not ask whether you should. Leave changes in the
  working tree.
- **Log new tech debt.** Any deliberate shortcut, hardcode, or "fix-later" gets a
  row in `TECH_DEBTS.md` (what / where / why deferred / what "done" looks like).
  Rediscovering debt is more expensive than writing it down.
- **Self-documenting code over comments.** Name things so the code reads; comment
  *why*, not *what*. Match the surrounding file's idiom, naming, and comment density.
- **Keep the suite green.** `./tools/test.sh` must pass, and its coverage guard
  (`tests/.test-baseline`) must not drop. Prefer headless-testable designs.
- **Zero GDScript warnings.** The project is warning-clean; keep it that way (§7).
  Godot prints warnings on every script load, so a run with `--debug` or the editor
  surfaces them. Check before handing off:
  `godot --headless --debug --import 2>&1 | grep WARNING` must print nothing.

## 1. What the game is (one paragraph)

*Limited Propellant* — a level-based 3D orbital-mechanics game in a NASA-punk
retro-futurist skin. You fly one spacecraft with a fixed propellant budget to a
target orbit/rendezvous/landing. Physics is **plausible in form** (real Kepler /
patched-conic / rocket equations, constants tuned for pacing), not SI-accurate.
Full pitch, pillars, and mechanics live in `DESIGN.md`; the UI/aesthetic spec in
`UI-DESIGN.md`; the debt ledger in `TECH_DEBTS.md`.

## 2. Architecture invariants — do not violate silently

These hold across the codebase; breaking one is a design change, not a refactor.

- **Doubles for all orbital math**, in per-SOI local frames (position relative to
  the current parent body). Bodies are **on rails** — pure closed-form functions of
  `sim_time`; never snapshot a body's position, derive it from time.
- **Floating / scaled origin for rendering.** The ship renders at exactly
  `(0,0,0)` and the world shifts around it; 1 render unit = 1 m. Float32 GPU
  precision never sees large coordinates. Do not introduce world-space rendering at
  interplanetary scale.
- **Determinism.** Given the same player input, a level plays out identically.
  Objective predicates are pure functions of (ship state, time). Coasting state is
  closed-form and never drifts.
- **Nesting is not hardcoded to "Earth is root."** The Mars level roots the Sun
  with Earth/Mars as children. Anything that walks the body graph must recurse
  through `parent`, not assume a fixed depth.

## 3. The theme system — no standalone colours

Visual look is **swappable**, funnelled through three seams. The hard rule:
**no raw `Color(...)` literals in UI code or level data.** A colour lives in
exactly one of these, by meaning:

| Seam | Owns | Where |
|---|---|---|
| **`RenderTheme`** | The 3D flight view's look — env/sky, body surface colours, trajectory, target ring, corridor, node ghost, orbit marks, ship markers. | `src/ui/render_theme.gd` |
| **`Palette`** | Semantic UI colours — *one meaning per colour* (green = live/own, amber = planned intent, cyan = target, red = danger), plus ORBITAL-OS chrome tokens. | `src/ui/palette.gd` |
| **`UiTheme`** | Builds **one Godot `Theme`** for all menu/HUD chrome — fonts (Chakra Petch / IBM Plex Mono) and ~40 `theme_type_variation` tokens (titles, HUD values, panels, chips, separators, buttons). Every colour is sourced *from* `Palette`. | `src/ui/ui_theme.gd` |

The generated Theme is `src/ui/generated_ui_theme.tres` — a script-only `Theme` whose `_init()` runs `UiTheme.populate(self)`, so it's **rebuilt from `Palette` on every load** (nothing is baked into the `.tres`, so it can't drift). `UiTheme.shared()` returns that same cached instance for code/tests.

Consequences to respect:

- **Levels (`src/levels/data/*.tres`) carry no colour.** A body's surface colour is
  resolved by *kind* from `RenderTheme.body_colors` (Earth/Moon/Sun/Mars). A level
  `.tres` should not set `color =` on a known-kind body; only a genuinely *generic*
  body falls back to its own `BodyDef.color`. Adding a level = data only, no palette.
- **Menu/HUD screens must not define local colour consts.** No `const GREEN := ...`
  per screen — pull from `Palette` (use `Palette.hex()` for BBCode). The 3D
  renderers read from the `RenderTheme` threaded into their `build(...)` (optional
  param, defaults to `RenderTheme.default()` so tests stay simple).
- **Scene-first UI (post–UI-revamp).** Menu/HUD chrome is authored in `.tscn`
  layouts, not built imperatively. A layout scene (`*_layout.tscn`, root
  `class_name *Layout`) applies the generated Theme at its root and styles nodes
  **only** via `theme_type_variation` — never per-node `theme_override_colors` and
  never inline `Color(...)`. A paired behaviour script (`extends CanvasLayer`, or
  `Hud`) instantiates the layout, reaches its `%UniqueName` nodes, and owns
  data-binding/input/signals. Typed component scenes (`TopTelemetryBar`,
  `MinimapObjectiveRail`, `GuidanceWarpRail`, `PropellantFlightStrip`,
  `FlightToolbar`, `HudOverlays`) expose `configure()`/`refresh()` and are composed
  by `hud_layout.tscn`. Any colour a scene needs at runtime (a `ColorRect` fill) is
  set in the layout script from `Palette`, not baked into the `.tscn`. Several of
  these scripts are `@tool` so they preview in the editor — keep editor-only code
  (save hooks, placeholder builds) guarded by `Engine.is_editor_hint()`.
- **Lint scope.** `tools/lint_ui_colors.sh` (in `tools/test.sh`) enforces the
  no-raw-`Color()` rule on `src/ui/*.gd` only; it does **not** scan `.tscn`. Keep
  scene *chrome* colour-clean by construction (type variations). The remaining raw
  `Color(...)` in scenes are 3D **materials** (`station_model.tscn` — a TD-3
  exception — and `map_view_layout.tscn`), not chrome.
- **Adding a new coloured surface?** Add a named field to the right seam and read it
  — never inline the literal at the call site. Intentional exceptions (chase fill
  light, star-dust tint, the shared station `.tscn`) are documented in TD-3; don't
  add new ones without a note.

## 4. Design references

The intended look is authored as static HTML mockups — treat them as the visual
spec:

- `ref/design-ref.html` — the "ORBITAL OS" system: menus, panels, typography,
  chrome tokens. `Palette` + `UiTheme` implement this.
- `ref/hud-ref.html` — the in-flight HUD layout (top telemetry bar, rails, bottom
  strip, attitude director). Realised as `hud_layout.tscn` + the typed component
  scenes above; `src/ui/hud.gd` is a thin coordinator (`build`/`refresh` fan-out).
- `UI-DESIGN.md` — the written companion to the palette semantics; keep it and
  `Palette` in lockstep.

## 5. Tech-debt map )

The sim/campaign core should be clean and well-tested; Tech debt used to concentrate
in the view/UI layer. See `TECH_DEBTS.md` for the live registry. Consult the registry
before assuming a subsystem is finished, and add a row when you defer something.

## 6. Testing

- `./tools/test.sh` runs the GUT suite headless and enforces `tests/.test-baseline`
  (script/test counts) — a parse error or coverage drop fails the run, it does not
  silently pass.
- Favour logic that can be exercised without a live window or input simulation
  (this is why maneuver-node editing is keyboard-event-driven and profiles/saves
  round-trip through disk in tests). New systems should follow suit.

## 7. GDScript style — statically typed, warning-free

Godot's type-safety warnings are all treated as defects (§0). Write **fully
statically typed** code so none fire; the common cases that bite:

- **Type every declaration.** Function params, return types, and `var`s carry a
  static type (annotate, or use `:=` so it's inferred). An untyped param/var is a
  warning, not a shortcut.
- **Typed loop variables:** `for body: BodyDef in level.moons:` and
  `for i: int in count:` — never a bare `for x in …`. Same for dictionary keys
  (`for key: String in DEFAULTS:`).
- **Typed lambdas, params *and* return:** `func(s: ShipSim) -> DVec3: return s.v`.
  The autopilot (`src/autopilot/flight_director.gd`) is the reference — its phase
  closures type both sides. `.call()` returns Variant; assigning it to a typed
  target is fine (Godot inserts the runtime check).
- **Enum from int needs a cast:** assigning an integer expression to an enum-typed
  target warns — cast it: `_mode = ((int(_mode) + 1) % Mode.size()) as Mode`,
  `e.physical_keycode = keycode as Key`.
- **Unused params/vars:** prefix with `_` (`func _build_right_rail(_level: LevelDef)`)
  or delete them. Only prefix what's genuinely unused — don't blanket-underscore.
- **Don't shadow built-ins or outer scope:** no local named `wrap`, `min`, `max`,
  etc. (shadows a global function), and a lambda param must not reuse an enclosing
  param's name.
- **Intentional integer division** (e.g. `HH:MM:SS` from seconds) is annotated
  `@warning_ignore("integer_division")` on the statement, not left to warn.

To type a reference to the mission root across files, `src/game_root.gd` is
`class_name GameRoot` (its members — `ship`, `level`, `sim_time`, `warp_index`,
`WARP_STEPS` — are themselves typed, so `game: GameRoot` accesses stay safe).
