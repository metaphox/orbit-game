#!/bin/sh
# Theme-seam lint (AGENTS.md, CR-6): UI code must not hold raw Color(...) RGB
# literals - semantic colours belong in Palette, flight-view appearance in
# RenderTheme, so the "Themes" feature can swap looks in one place.
#
# Flags `Color(<number>...` (a raw literal) in src/ui, both `.gd` and `.tscn`.
# Allowed:
#   - src/ui/palette.gd and src/ui/render_theme.gd (the seams themselves),
#   - src/ui/station_model.tscn (the shared 3D station model, a documented TD-3
#     exception; its material colours are authored in the scene),
#   - Color(<var>, alpha) forms like Color(Palette.DIM, 0.5) (not a literal),
#   - any line carrying a `# lint-ok:` marker (a reviewed, documented exception).
# Scene chrome must stay colour-clean via `theme_type_variation`; any colour a
# scene needs at runtime is applied in code from Palette (e.g. map_view.gd).
cd "$(dirname "$0")/.." || exit 1

HITS=$(grep -rnE 'Color8?\(\s*[-0-9.]' src/ui --include='*.gd' --include='*.tscn' \
	| grep -vE 'src/ui/(palette|render_theme)\.gd' \
	| grep -vE 'src/ui/station_model\.tscn' \
	| grep -v '# lint-ok')

if [ -n "$HITS" ]; then
	printf '\033[31mUI COLOR LINT FAILED:\033[0m raw Color() literals in src/ui (route via Palette/RenderTheme, or mark a reviewed exception with "# lint-ok: <reason>"):\n'
	printf '%s\n' "$HITS"
	exit 1
fi
printf '\033[32mUI color lint OK\033[0m - no raw Color() literals in src/ui (.gd + .tscn).\n'
