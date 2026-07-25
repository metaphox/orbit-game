# DEBUG: PATHOLOGICAL 12-MOON BELT

The **worst-case SOI scan** as a flyable level — the living companion to
`test_perf_heavy_level`.

One planet with **12 active** Moon-like children packed into a radial belt. The
ship starts on an ellipse (periapsis 1500 km, apoapsis 5500 km) whose band
**spans the whole belt** — the case the broad-phase rejection can't skip — so
each burn/SOI refit pays the full ~12-child scan.

Fly it and feel the refit hitch on real hardware. Debug builds only.
