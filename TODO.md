TODO List
=========

- improve texture for spaceships
- F1 leaks in pause menu, maybe other places as well
- 2nd minimap mode: the minimap always follow the ship from behind, everything rotates around it.
- decide a minimal game window size
- menu overhaul / redesign based on design-ref
- revamp UI contrls based on design-ref
  - check if the fonts mentioned in design-ref can be used commercially
- detailed tutorials:
  - dedicated tutorial level for absolute beginners: basic terms e.g. ship directions, how spaceship turns (in realife vs. in game)
  - brief tutorial for space nerds just to introduce the game controls and what the limits e.g. what are simulated and what are not / inaccurate / impossible
- "Themes", i.e. the visual of almost everything other than the UI can be changed, e.g. the whole universe looks like an all-abstract classic sci-fi coarse grid-based simulation, or wild Van-Gogh "Starry Night" look dreamy universe. Also extendable by the user.
- BGM and sound effects
- in-game calculator for hardcore space nerds
- more levels!
- FLIGHT PLAN brief formatting: inline icon syntax (deferred). Define a small set of brief-embeddable icons rendered inline in the FLIGHT PLAN RichTextLabel — e.g. `:prograde:` `:retrograde:` `:normal:` `:node:` → a glyph next to the maneuver. Extend `BriefText.md_to_bbcode()` to map tokens to `[img]`/font-icon BBCode; pick/draw the icon set. Tokens stay locale-independent.
- localize the briefs: English lives in `assets/briefs/en/`; add `assets/briefs/<locale>/<level>.md` per locale (loader already falls back to English).
