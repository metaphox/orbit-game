#!/usr/bin/env python3
"""Procedurally generate plausible space stations for the orbit-game.

Emits a Godot `.tscn` (primitive meshes that reference the *ship* materials, so a
station reads as the same universe as the player craft) plus a `.json` blueprint.
Every solid part is bounds-checked so nothing interpenetrates — see docs/STATIONS.md
for the design rules this encodes.

    python3 tools/station_gen.py --iss 1 --seed 1 --out assets/stations
    python3 tools/station_gen.py --count 10 --spread --out assets/stations
    python3 tools/station_gen.py --selftest

The tool is the deliverable; the stations are its output. Language: Python (no
build step, and the .tscn text format is trivial to write). Godot never runs this
at play time — stations are pre-generated assets.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import math
import os
import random
import sys
from dataclasses import dataclass, field

# --- Palette: reference the player-ship materials so colours always match ------
MAT = {
    "hull": "res://src/ui/world/materials/ship_hull_material.tres",     # cream
    "dark": "res://src/ui/world/materials/ship_dark_material.tres",     # structure
    "solar": "res://src/ui/world/materials/ship_solar_material.tres",   # panels
    "orange": "res://src/ui/world/materials/ship_nose_material.tres",   # accent
    "green": "res://src/ui/world/materials/ship_light_material.tres",   # nav lights
}

ISS_METERS = 109.0  # yardstick: ISS longest dimension


# --- tiny 3-vector / matrix helpers (columns = local axes in world space) ------
Vec = tuple  # (x, y, z)

IDENT = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))


def rot_axis(axis: str, deg: float):
    """Rotation matrix (as 3 world-space column axes) about x/y/z by `deg`."""
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    if axis == "x":
        return ((1, 0, 0), (0, c, s), (0, -s, c))
    if axis == "y":
        return ((c, 0, -s), (0, 1, 0), (s, 0, c))
    return ((c, s, 0), (-s, c, 0), (0, 0, 1))  # about z


# --- parts ---------------------------------------------------------------------
@dataclass
class Part:
    """One primitive. `half` is the local (unrotated) half-extent AABB used for
    both the mesh dims and collision; `cols` orients it; `pos` is its centre.
    `connector` parts (collars, spokes, booms) are allowed to touch others."""
    kind: str            # semantic role, for the blueprint + naming
    mesh: str            # cylinder | box | torus | sphere
    half: Vec            # local half-extents (x, y, z) before rotation
    pos: Vec
    mat: str
    cols: tuple = IDENT
    connector: bool = False
    extra: dict = field(default_factory=dict)  # mesh-specific (e.g. torus radii)

    def world_half(self) -> Vec:
        return tuple(
            sum(abs(self.cols[j][i]) * self.half[j] for j in range(3)) for i in range(3)
        )

    def aabb(self):
        wh = self.world_half()
        lo = tuple(self.pos[i] - wh[i] for i in range(3))
        hi = tuple(self.pos[i] + wh[i] for i in range(3))
        return lo, hi


def aabb_overlap(a: Part, b: Part, eps: float) -> bool:
    la, ha = a.aabb()
    lb, hb = b.aabb()
    return all(ha[i] - eps > lb[i] and hb[i] - eps > la[i] for i in range(3))


def x_range(p: Part):
    lo, hi = p.aabb()
    return lo[0], hi[0]


def radial_band(p: Part):
    """Min/max distance of the part's AABB from the X (spine) axis, in the Y-Z
    plane — the radial band it sweeps. Conservative (uses the box corners) so a
    ring clearance test never lets a real crossing through."""
    lo, hi = p.aabb()
    ymax = max(abs(lo[1]), abs(hi[1]))
    zmax = max(abs(lo[2]), abs(hi[2]))
    ny = 0.0 if lo[1] <= 0 <= hi[1] else min(abs(lo[1]), abs(hi[1]))
    nz = 0.0 if lo[2] <= 0 <= hi[2] else min(abs(lo[2]), abs(hi[2]))
    return math.hypot(ny, nz), math.hypot(ymax, zmax)


# --- station builder -----------------------------------------------------------
class Station:
    def __init__(self, seed: int, meters: float, archetype: str,
                 min_panels: int, min_labs: int, min_habs: int):
        self.rng = random.Random(seed)
        self.seed = seed
        self.meters = meters
        self.min_panels = min_panels
        self.min_labs = min_labs
        self.min_habs = min_habs
        self.parts: list[Part] = []
        self.archetype = self._pick_archetype(archetype)
        self.counts = {"labs": 0, "habs": 0, "nodes": 0, "panels": 0,
                       "radiators": 0, "antennas": 0, "ports": 0, "rings": 0}

    # -- helpers
    def add(self, p: Part):
        self.parts.append(p)

    def jitter(self, lo, hi):
        return self.rng.uniform(lo, hi)

    def _free_xs(self, n, lo, hi, avoid, pad):
        """`n` spread-out X positions in [lo, hi] that avoid the given (centre,
        halfwidth) slabs by `pad` — so parts don't share a ring's X-slice."""
        grid = [lo + (hi - lo) * k / 240 for k in range(241)]
        free = [x for x in grid if all(abs(x - c) > hw + pad for c, hw in avoid)]
        if len(free) < n:
            return None
        if n == 1:
            return [free[len(free) // 2]]
        step = (len(free) - 1) / (n - 1)
        return [free[int(round(i * step))] for i in range(n)]

    def _free_x(self, lo, hi, avoid, pad):
        for _ in range(40):
            x = self.rng.uniform(lo, hi)
            if all(abs(x - c) > hw + pad for c, hw in avoid):
                return x
        return None

    def _pick_archetype(self, a: str) -> str:
        if a != "auto":
            return a
        # small -> stack, medium -> truss, big -> ring/truss showcase
        iss = self.meters / ISS_METERS
        if iss < 1.2:
            return self.rng.choice(["stack", "stack", "radial"])
        if iss < 6:
            return self.rng.choice(["truss", "truss", "stack", "radial", "power", "dualkeel"])
        return self.rng.choice(["truss", "truss", "ring", "power", "dualkeel", "cylinder"])

    # -- module spine (shared by all archetypes) -------------------------------
    def build_spine(self):
        """Modules end-to-end along X. Returns (module_radius_max, x_min, x_max)."""
        iss = self.meters / ISS_METERS
        # target spine length ~ 55% of longest dimension; module radius grows softly
        span = self.meters * self.jitter(0.45, 0.6)
        rad = 2.0 * (iss ** 0.5) * self.jitter(0.85, 1.15)  # ~ISS 4m dia at 1x
        rad = max(1.4, rad)
        # how many pressurised modules
        n_mod = max(self.min_labs + self.min_habs + 1,
                    int(round(2 + iss * self.jitter(0.8, 1.4))))
        n_mod = min(n_mod, 14)
        # distribute lengths with variety (not all identical)
        lengths = [self.jitter(0.6, 1.4) for _ in range(n_mod)]
        tot = sum(lengths)
        lengths = [ln / tot * span for ln in lengths]
        x = -span / 2
        rmax = rad
        want_labs, want_habs = self.min_labs, self.min_habs
        for i, ln in enumerate(lengths):
            r = rad * self.jitter(0.82, 1.06)
            # a node hub every few modules: fatter, short, many ports
            is_node = (i > 0 and i < n_mod - 1 and (i % 3 == 0))
            cx = x + ln / 2
            if is_node:
                r_node = rad * 1.18
                self.add(Part("node", "cylinder", (r_node, ln / 2, r_node),
                              (cx, 0, 0), MAT["hull"], rot_axis("z", 90)))
                self.counts["nodes"] += 1
                rmax = max(rmax, r_node)
            else:
                # assign role: satisfy minimums first, then habitat/lab mix
                if want_labs > 0:
                    role, mat = "lab", MAT["hull"]; want_labs -= 1
                elif want_habs > 0:
                    role, mat = "hab", MAT["hull"]; want_habs -= 1
                else:
                    role = self.rng.choice(["lab", "hab", "hab"])
                    mat = MAT["hull"]
                self.counts["labs" if role == "lab" else "habs"] += 1
                self.add(Part(role, "cylinder", (r, ln / 2, r),
                              (cx, 0, 0), mat, rot_axis("z", 90)))
                rmax = max(rmax, r)
                # accent: an orange trim collar mid-module (sparingly)
                if self.rng.random() < 0.28:
                    self.add(Part("trim", "cylinder", (r * 1.04, ln * 0.06, r * 1.04),
                                  (cx, 0, 0), MAT["orange"], rot_axis("z", 90),
                                  connector=True))
            x += ln
        x0, x1 = -span / 2, span / 2
        # end caps / docking ports
        for end in (x0, x1):
            sgn = -1 if end == x0 else 1
            self.add(Part("port", "cylinder", (rad * 0.4, rad * 0.22, rad * 0.4),
                          (end + sgn * rad * 0.22, 0, 0), MAT["dark"],
                          rot_axis("z", 90), connector=True))
            self.counts["ports"] += 1
            if self.rng.random() < 0.6:  # a green nav light by the port
                self.add(Part("light", "sphere", (rad * 0.12,) * 3,
                              (end + sgn * rad * 0.36, rad * 0.2, 0), MAT["green"],
                              connector=True))
        return rmax, x0, x1, span

    # -- solar wings (paired, clear of the hull) -------------------------------
    def build_solar(self, rmax, x0, x1, span, avoid=None):
        iss = self.meters / ISS_METERS
        n_pairs = max(self.min_panels,
                      int(round(1 + iss * self.jitter(0.5, 0.9))))
        n_pairs = max(1, min(n_pairs, 8))          # never zero, never a swarm
        clear = rmax * 1.6 + self.meters * 0.02    # inner edge beyond the hull
        wing_len = self.meters * self.jitter(0.16, 0.26)   # outboard extent (Z)
        wing_wid = self.meters * self.jitter(0.05, 0.09)   # along the spine (X)
        # distribute mount points along the usable spine so wings don't share X
        # (and, in the ring archetype, stay clear of the rings' X-slices)
        usable = span * 0.8
        xs = self._free_xs(n_pairs, -usable / 2, usable / 2,
                           avoid or [], wing_wid * 0.5 + rmax * 0.4)
        if xs is None:
            raise ValidationError("no room for solar arrays clear of the rings")
        self.rng.shuffle(xs)
        for k in range(n_pairs):
            mx = xs[k]
            wl = wing_len * self.jitter(0.85, 1.15)   # vary so not identical
            for sgn in (-1, 1):                        # symmetric pair
                zc = sgn * (clear + wl / 2)
                # boom (connector) from hull to wing
                self.add(Part("boom", "cylinder", (rmax * 0.12, (clear) / 2, rmax * 0.12),
                              (mx, 0, sgn * clear / 2), MAT["dark"],
                              rot_axis("x", 90), connector=True))
                # a real array (ISS SAW-like): two solar blankets flanking a dark
                # central mast, all thin in Y (facing the sun), long in Z.
                self.add(Part("mast", "box", (wing_wid * 0.05, self.meters * 0.009, wl / 2),
                              (mx, 0, zc), MAT["dark"], connector=True))
                for bx in (-1, 1):
                    self.add(Part("panel", "box",
                                  (wing_wid * 0.21, self.meters * 0.006, wl / 2),
                                  (mx + bx * wing_wid * 0.27, 0, zc), MAT["solar"]))
                # transverse battens segment the blanket (the iconic array look)
                for frac in (-0.3, 0.3):
                    self.add(Part("batten", "box",
                                  (wing_wid * 0.5, self.meters * 0.008, wl * 0.02),
                                  (mx, 0, zc + frac * wl), MAT["dark"], connector=True))
            self.counts["panels"] += 2
        return clear

    # -- radiators (perpendicular to the arrays) -------------------------------
    def build_radiators(self, rmax, span, avoid=None):
        n = max(1, self.counts["panels"] // 4)
        rad_len = self.meters * self.jitter(0.08, 0.14)
        clear = rmax * 1.4
        for i in range(n):
            mx = self._free_x(-span * 0.3, span * 0.3, avoid or [], rmax * 0.4)
            if mx is None:
                raise ValidationError("no room for radiators clear of the rings")
            sgn = -1 if i % 2 == 0 else 1              # alternate up/down
            yc = sgn * (clear + rad_len / 2)
            # a radiator BANK: two fins flanking a dark backing spar, broad faces
            # ±X (perpendicular to the ±Y-facing arrays), tall in Y. Same envelope
            # as the old single slab but reads as a real deployed panel bank.
            depth = self.meters * 0.05
            fin_x = self.meters * 0.004
            self.add(Part("spar", "box", (fin_x * 1.4, rad_len / 2, depth),
                          (mx, yc, 0), MAT["dark"], connector=True))
            for fx in (-1, 1):
                self.add(Part("radiator", "box",
                              (fin_x, rad_len / 2, depth * 0.92),
                              (mx + fx * fin_x * 3.0, yc, 0), MAT["hull"]))
            self.add(Part("boom", "cylinder", (rmax * 0.08, clear / 2, rmax * 0.08),
                          (mx, sgn * clear / 2, 0), MAT["dark"], connector=True))
            self.counts["radiators"] += 1

    # -- antennas + observation accents ----------------------------------------
    def build_details(self, rmax, x0, x1, span, avoid=None):
        iss = self.meters / ISS_METERS
        n_ant = max(1, min(4, int(round(1 + iss * 0.3))))
        for i in range(n_ant):
            mx = self._free_x(x0 * 0.7, x1 * 0.7, avoid or [], rmax * 0.4)
            if mx is None:
                raise ValidationError("no room for antennas clear of the rings")
            sgn = self.rng.choice([-1, 1])
            mast = rmax * self.jitter(0.9, 1.6)
            # masts stick out along +/-Z, clear of the +/-Y radiators
            self.add(Part("mast", "cylinder", (rmax * 0.05, mast / 2, rmax * 0.05),
                          (mx, 0, sgn * (rmax + mast / 2)), MAT["dark"],
                          rot_axis("x", 90), connector=True))
            dish_r = rmax * self.jitter(0.35, 0.6)
            self.add(Part("antenna", "cylinder", (dish_r, rmax * 0.06, dish_r),
                          (mx, 0, sgn * (rmax + mast + dish_r * 0.1)), MAT["hull"],
                          rot_axis("x", 90)))
            self.counts["antennas"] += 1
        # a cupola/dome flush on one module (surface feature -> connector)
        if self.rng.random() < 0.8:
            mx = self.jitter(x0 * 0.5, x1 * 0.5)
            self.add(Part("cupola", "sphere", (rmax * 0.5,) * 3,
                          (mx, -rmax * 0.9, 0), MAT["dark"], connector=True))

    # -- rotating habitat ring(s) (ring archetype) -----------------------------
    def build_rings(self, rmax, span):
        """Non-rotating axial hub + rotating habitat ring(s), spokes between
        (spin-gravity fiction always separates the two). Returns the X-slabs to
        keep arrays/radiators/antennas out of. The torus is treated as a
        connector for the box test; validate() does the real annulus clearance."""
        n = self.rng.choice([1, 1, 2])
        ring_clear = rmax * 3.0   # inner radius must clear the (conservative) hull band
        xs = [0.0] if n == 1 else [-span * 0.18, span * 0.18]
        slabs = []
        for i in range(n):
            mx = xs[i]
            outer = ring_clear * self.jitter(1.0, 1.3)
            tube = rmax * self.jitter(0.3, 0.45)
            # ring in the Y-Z plane (spins about the X spine)
            self.add(Part("ring", "torus", (outer, tube, outer),
                          (mx, 0, 0), MAT["hull"], rot_axis("z", 90), connector=True,
                          extra={"inner": outer - 2 * tube, "outer": outer}))
            self.counts["rings"] += 1
            slabs.append((mx, tube + rmax * 0.3))
            # spokes (connectors) hub -> ring, radial symmetry
            for a in range(6):
                ang = math.radians(a * 60)
                y, z = math.sin(ang) * outer / 2, math.cos(ang) * outer / 2
                self.add(Part("spoke", "box",
                              (rmax * 0.08, outer / 2, rmax * 0.08),
                              (mx, y, z), MAT["dark"],
                              rot_axis("x", math.degrees(ang)), connector=True))
        return slabs

    def build_radial(self, rmax, span):
        """Mir / Orbital-Reef 'grown' look: purpose-built modules stick out
        radially (±Y/±Z) from the spine centre, deliberately asymmetric (2-4 of
        the 4 directions). Returns the centre X-slab so arrays/radiators/antennas
        route around it (they can't share the X of the radial modules)."""
        dirs = [("y", 1), ("y", -1), ("z", 1), ("z", -1)]
        self.rng.shuffle(dirs)
        for axis, sgn in dirs[:self.rng.randint(2, 4)]:
            r = rmax * self.jitter(0.72, 0.95)
            ln = rmax * self.jitter(2.2, 4.2)
            base = rmax * 1.18                      # start beyond the hub radius
            cols = IDENT if axis == "y" else rot_axis("x", 90)  # cylinder axis
            ctr = base + ln / 2
            pos = (0.0, sgn * ctr, 0.0) if axis == "y" else (0.0, 0.0, sgn * ctr)
            role = "lab" if self.rng.random() < 0.5 else "hab"
            self.counts["labs" if role == "lab" else "habs"] += 1
            self.add(Part(role, "cylinder", (r, ln / 2, r), pos, MAT["hull"], cols))
            # docking port cap at the far end (connector) + a nav light
            capd = base + ln
            cpos = (0.0, sgn * capd, 0.0) if axis == "y" else (0.0, 0.0, sgn * capd)
            self.add(Part("port", "cylinder", (r * 0.4, r * 0.22, r * 0.4),
                          cpos, MAT["dark"], cols, connector=True))
            self.counts["ports"] += 1
            self.add(Part("light", "sphere", (r * 0.12,) * 3, cpos, MAT["green"],
                          connector=True))
        return [(0.0, rmax * 1.4)]

    def build_power_tower(self):
        """1984 NASA Freedom 'Power Tower' (never flew): a tall thin keel held in
        a gravity-gradient orientation, mass clustered at both ends (modules at
        the bottom, instruments at the top), arrays amidships. Legible 'totem'.
        Replaces build_spine and returns (rmax, x0, x1, span, avoid) with the two
        end clusters as avoid-slabs so the arrays land in the middle."""
        iss = self.meters / ISS_METERS
        span = self.meters
        rad = max(1.4, 2.0 * (iss ** 0.5) * self.jitter(0.85, 1.1))
        keel_r = rad * 0.28
        x0, x1 = -span / 2, span / 2
        # keel backbone (connector) runs the full length
        self.add(Part("keel", "box", (span / 2, keel_r, keel_r), (0, 0, 0),
                      MAT["dark"], connector=True))
        # bottom: pressurised module cluster (a short stack)
        n_mod = max(self.min_labs + self.min_habs + 1, self.rng.randint(3, 5))
        clen = span * self.jitter(0.22, 0.32)
        lengths = [self.jitter(0.7, 1.3) for _ in range(n_mod)]
        tot = sum(lengths)
        lengths = [ln / tot * clen for ln in lengths]
        x = x0
        rmax = rad
        wl, wh = self.min_labs, self.min_habs
        for ln in lengths:
            r = rad * self.jitter(0.85, 1.05)
            if wl > 0:
                role, wl = "lab", wl - 1
            elif wh > 0:
                role, wh = "hab", wh - 1
            else:
                role = self.rng.choice(["lab", "hab", "hab"])
            self.counts["labs" if role == "lab" else "habs"] += 1
            self.add(Part(role, "cylinder", (r, ln / 2, r), (x + ln / 2, 0, 0),
                          MAT["hull"], rot_axis("z", 90)))
            rmax = max(rmax, r)
            x += ln
        self.add(Part("port", "cylinder", (rad * 0.4, rad * 0.22, rad * 0.4),
                      (x0 - rad * 0.22, 0, 0), MAT["dark"], rot_axis("z", 90),
                      connector=True))
        self.counts["ports"] += 1
        self.add(Part("light", "sphere", (rad * 0.12,) * 3,
                      (x0 - rad * 0.36, rad * 0.2, 0), MAT["green"], connector=True))
        # top: instrument / astronomy mass (a small stack of boxes) + a dish
        mlen = span * self.jitter(0.12, 0.2)
        n_inst = self.rng.randint(2, 4)
        for i in range(n_inst):
            iw = rad * self.jitter(0.55, 0.9)
            ix = x1 - mlen + mlen * (i + 0.5) / n_inst
            self.add(Part("instrument", "box", (mlen / n_inst * 0.4, iw, iw),
                          (ix, 0, 0), MAT["hull"]))
        dish_r = rad * self.jitter(0.5, 0.8)
        self.add(Part("antenna", "cylinder", (dish_r, rad * 0.06, dish_r),
                      (x1 - mlen * 0.5, 0, rad + dish_r), MAT["hull"], rot_axis("x", 90)))
        self.counts["antennas"] += 1
        avoid = [(x0 + clen / 2, clen / 2 + rad * 0.5),
                 (x1 - mlen / 2, mlen / 2 + rad * 0.9)]
        return rmax, x0, x1, span, avoid

    def build_dual_keel(self):
        """1986 NASA Freedom 'Dual Keel' (never flew): a rectangular truss
        picture-frame (aspect ~2:1) with a horizontal mid-boom carrying the
        pressurised modules + arrays, and instruments on the top (astronomy) and
        bottom (Earth-sensing) edges. Frame beams are connectors; the modules ride
        the mid-boom along X. Returns (rmax, x0, x1, span, avoid=[])."""
        iss = self.meters / ISS_METERS
        height = self.meters                      # keel height = the long dimension
        kx = height * self.jitter(0.21, 0.28)     # half-width (2:1-ish frame)
        beam = max(0.6, 1.2 * (iss ** 0.5))
        # picture-frame: two vertical keels + top/bottom booms (all connectors)
        for sx in (-1, 1):
            self.add(Part("keel", "box", (beam, height / 2, beam),
                          (sx * kx, 0, 0), MAT["dark"], connector=True))
        for sy in (-1, 1):
            self.add(Part("boom", "box", (kx, beam, beam), (0, sy * height / 2, 0),
                          MAT["dark"], connector=True))
        self.add(Part("boom", "box", (kx, beam * 0.8, beam * 0.8), (0, 0, 0),
                      MAT["dark"], connector=True))       # horizontal mid-boom
        # module stack along the mid-boom
        rad = max(1.4, beam * 1.7 * self.jitter(0.9, 1.1))
        n_mod = max(self.min_labs + self.min_habs + 1, self.rng.randint(3, 5))
        stack = kx * 1.4
        lengths = [self.jitter(0.7, 1.3) for _ in range(n_mod)]
        tot = sum(lengths)
        lengths = [ln / tot * stack for ln in lengths]
        x, rmax = -stack / 2, rad
        wl, wh = self.min_labs, self.min_habs
        for ln in lengths:
            r = rad * self.jitter(0.85, 1.05)
            if wl > 0:
                role, wl = "lab", wl - 1
            elif wh > 0:
                role, wh = "hab", wh - 1
            else:
                role = self.rng.choice(["lab", "hab", "hab"])
            self.counts["labs" if role == "lab" else "habs"] += 1
            self.add(Part(role, "cylinder", (r, ln / 2, r), (x + ln / 2, 0, 0),
                          MAT["hull"], rot_axis("z", 90)))
            rmax = max(rmax, r)
            x += ln
        for end in (-stack / 2, stack / 2):
            sgn = -1 if end < 0 else 1
            self.add(Part("port", "cylinder", (rad * 0.4, rad * 0.2, rad * 0.4),
                          (end + sgn * rad * 0.2, 0, 0), MAT["dark"],
                          rot_axis("z", 90), connector=True))
            self.counts["ports"] += 1
        # instruments: astronomy on the top edge, Earth-sensing on the bottom
        for sy, mat in ((1, MAT["hull"]), (-1, MAT["dark"])):
            n = self.rng.randint(1, 3)
            for i in range(n):
                iw = beam * self.jitter(1.3, 2.1)
                ix = -kx * 0.6 + (kx * 1.2) * (i + 0.5) / n
                self.add(Part("instrument", "box", (iw, beam * 1.2, iw),
                              (ix, sy * (height / 2 - beam * 1.6), 0), mat))
        return rmax, -stack / 2, stack / 2, kx * 1.7, []

    def build_cylinder(self):
        """O'Neill / Rama rotating cylinder (Babylon 5, Cooper Station): a big
        rotating drum (L/D ~ 4-6) with external stiffening ribs + endcap rims, a
        non-rotating docking hub + module stack beyond one end, solar wings and
        radiators alongside the drum (clear of its radius), and small comms dishes
        on the hub. SELF-CONTAINED — it does its own detailing (the generic
        antenna/radiator sizing is tuned to a module radius, not a hull radius)."""
        iss = self.meters / ISS_METERS
        length = self.meters
        rad = length / self.jitter(8.0, 12.0)     # L/D 4-6
        x0, x1 = -length / 2, length / 2
        self.add(Part("hab", "cylinder", (rad, length / 2, rad), (0, 0, 0),
                      MAT["hull"], rot_axis("z", 90)))              # the drum
        self.counts["habs"] += 1
        for sx in (-1, 1):                                          # endcap rims
            self.add(Part("collar", "cylinder", (rad * 1.05, rad * 0.05, rad * 1.05),
                          (sx * length / 2, 0, 0), MAT["dark"], rot_axis("z", 90),
                          connector=True))
        n_rib = self.rng.randint(3, 6)                             # stiffening ribs
        for i in range(n_rib):
            rx = -length / 2 + length * (i + 1) / (n_rib + 1)
            t = rad * 0.05
            self.add(Part("rib", "torus", (rad * 1.03, t, rad * 1.03), (rx, 0, 0),
                          MAT["dark"], rot_axis("z", 90), connector=True,
                          extra={"inner": rad * 1.03 - 2 * t, "outer": rad * 1.03}))
        # non-rotating docking hub + module stack beyond the +X endcap
        hub_r = rad * 0.3
        hub_x = length / 2 + hub_r * 1.5
        self.add(Part("node", "cylinder", (hub_r, hub_r * 1.2, hub_r), (hub_x, 0, 0),
                      MAT["hull"], rot_axis("z", 90)))
        self.counts["nodes"] += 1
        lx, ant_xs = hub_x + hub_r * 1.2, [hub_x]
        mods = ["lab"] * max(self.min_labs, 1) + ["hab"] * max(0, self.min_habs - 1)
        for role in mods:
            ll = hub_r * 1.7
            self.add(Part(role, "cylinder", (hub_r * 0.85, ll / 2, hub_r * 0.85),
                          (lx + ll / 2, 0, 0), MAT["hull"], rot_axis("z", 90)))
            self.counts["labs" if role == "lab" else "habs"] += 1
            ant_xs.append(lx + ll / 2)
            lx += ll
        self.add(Part("port", "cylinder", (hub_r * 0.5, hub_r * 0.2, hub_r * 0.5),
                      (lx + hub_r * 0.2, 0, 0), MAT["dark"], rot_axis("z", 90),
                      connector=True))
        self.counts["ports"] += 1
        self.add(Part("light", "sphere", (hub_r * 0.16,) * 3,
                      (lx + hub_r * 0.35, hub_r * 0.4, 0), MAT["green"], connector=True))
        # comms dishes on the hub, pointing ±Y (clear of the ±Z solar wings)
        n_ant = max(1, min(3, int(round(1 + iss * 0.2))))
        for i in range(n_ant):
            sgn = 1 if i % 2 == 0 else -1
            ax = ant_xs[i % len(ant_xs)]
            mast = hub_r * 1.4
            self.add(Part("mast", "cylinder", (hub_r * 0.08, mast / 2, hub_r * 0.08),
                          (ax, sgn * (hub_r + mast / 2), 0), MAT["dark"], connector=True))
            dish_r = hub_r * 0.6
            self.add(Part("antenna", "cylinder", (dish_r, hub_r * 0.06, dish_r),
                          (ax, sgn * (hub_r + mast + dish_r * 0.1), 0), MAT["hull"]))
            self.counts["antennas"] += 1
        # solar wings + radiators alongside the drum (booms clear its radius)
        self.build_solar(rad, x0, x1, length, avoid=[])
        self.build_radiators(rad, length, avoid=[])
        return self

    def build(self):
        if self.archetype == "cylinder":
            return self.build_cylinder()
        _end_builders = {"power": self.build_power_tower,
                         "dualkeel": self.build_dual_keel}
        if self.archetype in _end_builders:
            rmax, x0, x1, span, avoid = _end_builders[self.archetype]()
            self.build_solar(rmax, x0, x1, span, avoid=avoid)
            self.build_radiators(rmax, span, avoid=avoid)
            self.build_details(rmax, x0, x1, span, avoid=avoid)
            return self
        rmax, x0, x1, span = self.build_spine()
        avoid = []
        if self.archetype == "ring":
            avoid = self.build_rings(rmax, span)
        elif self.archetype == "radial":
            avoid = self.build_radial(rmax, span)
        self.build_solar(rmax, x0, x1, span, avoid=avoid)
        self.build_radiators(rmax, span, avoid=avoid)
        self.build_details(rmax, x0, x1, span, avoid=avoid)
        return self


# --- validation ----------------------------------------------------------------
class ValidationError(Exception):
    pass


def validate(st: Station):
    solids = [p for p in st.parts if not p.connector]
    eps = st.meters * 0.004  # tolerance so parts may kiss but not overlap
    for i in range(len(solids)):
        for j in range(i + 1, len(solids)):
            if aabb_overlap(solids[i], solids[j], eps):
                raise ValidationError(
                    f"interference: {solids[i].kind} <-> {solids[j].kind}")
    # Rings need an annulus test, not a box test: a torus has a hollow centre
    # but a filled AABB, so modules may sit inside the hole and arrays must stay
    # out of its X-slice. A part clashes only if it shares the ring's X-slab AND
    # its radial band reaches into the ring's [inner, outer].
    for R in (p for p in st.parts if p.mesh == "torus" and p.kind == "ring"):
        rlo, rhi = x_range(R)
        inner, outer = R.extra["inner"], R.extra["outer"]
        for S in solids:
            slo, shi = x_range(S)
            if shi - eps <= rlo or rhi - eps <= slo:
                continue  # X-slabs disjoint
            rmn, rmx = radial_band(S)
            if rmx - eps > inner and outer - eps > rmn:
                raise ValidationError(f"ring interference: ring <-> {S.kind}")
    c = st.counts
    if c["panels"] < 2 * st.min_panels:
        raise ValidationError(f"too few solar pairs: {c['panels']//2} < {st.min_panels}")
    if c["labs"] < st.min_labs:
        raise ValidationError(f"too few labs: {c['labs']} < {st.min_labs}")
    if c["habs"] < st.min_habs:
        raise ValidationError(f"too few habitats: {c['habs']} < {st.min_habs}")
    if c["panels"] == 0 or c["antennas"] == 0 or c["ports"] == 0:
        raise ValidationError("a station needs power, comms and a docking port")
    # not-all-identical: at least a few distinct part kinds present
    kinds = {p.kind for p in st.parts}
    if len(kinds) < 5:
        raise ValidationError(f"too monotonous: only {len(kinds)} part kinds")
    return True


# --- serialisation -------------------------------------------------------------
def _fmt(v: float) -> str:
    return f"{v:.4f}".rstrip("0").rstrip(".") if v == v else "0"


def to_tscn(st: Station, scale: float) -> str:
    """Serialise to a Godot scene. `scale` converts design-metres -> game units."""
    ext = {}
    for i, (name, path) in enumerate(MAT.items()):
        ext[name] = f"{i+1}_{name}"
    head = ['[gd_scene load_steps=%d format=3]' % (len(MAT) + len(st.parts) + 1), '']
    for name, path in MAT.items():
        head.append('[ext_resource type="Material" path="%s" id="%s"]'
                     % (path, ext[name]))
    head.append('')
    subs, nodes = [], ['[node name="Station" type="Node3D"]', '']
    matname = {v: k for k, v in MAT.items()}
    for idx, p in enumerate(st.parts):
        mid = f"m{idx}"
        h = tuple(x * scale for x in p.half)
        mat_id = ext[matname[p.mat]]
        if p.mesh == "cylinder":
            subs += [f'[sub_resource type="CylinderMesh" id="{mid}"]',
                     f'material = ExtResource("{mat_id}")',
                     f'top_radius = {_fmt(h[0])}', f'bottom_radius = {_fmt(h[2])}',
                     f'height = {_fmt(h[1]*2)}', 'radial_segments = 12', 'rings = 1', '']
        elif p.mesh == "box":
            subs += [f'[sub_resource type="BoxMesh" id="{mid}"]',
                     f'material = ExtResource("{mat_id}")',
                     f'size = Vector3({_fmt(h[0]*2)}, {_fmt(h[1]*2)}, {_fmt(h[2]*2)})', '']
        elif p.mesh == "torus":
            inr = p.extra["inner"] * scale
            outr = p.extra["outer"] * scale
            subs += [f'[sub_resource type="TorusMesh" id="{mid}"]',
                     f'material = ExtResource("{mat_id}")',
                     f'inner_radius = {_fmt(inr)}', f'outer_radius = {_fmt(outr)}', '']
        else:  # sphere
            subs += [f'[sub_resource type="SphereMesh" id="{mid}"]',
                     f'material = ExtResource("{mat_id}")',
                     f'radius = {_fmt(h[0])}', f'height = {_fmt(h[0]*2)}',
                     'radial_segments = 12', 'rings = 6', '']
        c = p.cols
        o = tuple(x * scale for x in p.pos)
        tf = ", ".join(_fmt(v) for v in (
            c[0][0], c[0][1], c[0][2], c[1][0], c[1][1], c[1][2],
            c[2][0], c[2][1], c[2][2], o[0], o[1], o[2]))
        nm = f"{p.kind.capitalize()}{idx}"
        nodes += [f'[node name="{nm}" type="MeshInstance3D" parent="."]',
                  f'transform = Transform3D({tf})',
                  f'mesh = SubResource("{mid}")', '']
    return "\n".join(head + subs + nodes)


def to_json(st: Station, scale: float) -> dict:
    return {
        "seed": st.seed, "archetype": st.archetype,
        "meters": round(st.meters, 1), "iss_multiple": round(st.meters / ISS_METERS, 2),
        "game_scale": scale, "counts": st.counts,
        "parts": [{"kind": p.kind, "mesh": p.mesh,
                   "pos": [round(x, 3) for x in p.pos],
                   "half": [round(x, 3) for x in p.half],
                   "connector": p.connector} for p in st.parts],
    }


# --- CLI -----------------------------------------------------------------------
def generate_one(meters, seed, archetype, min_panels, min_labs, min_habs,
                 scale, retries=40):
    """Build + validate, retrying with a nudged seed until it passes."""
    last = None
    for k in range(retries):
        st = Station(seed + k * 101, meters, archetype,
                     min_panels, min_labs, min_habs).build()
        try:
            validate(st)
            return st
        except ValidationError as e:
            last = e
    raise ValidationError(f"could not satisfy constraints after {retries} tries: {last}")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Procedurally generate space stations.")
    ap.add_argument("--iss", type=float, help="rough size in ISS multiples (~109 m)")
    ap.add_argument("--meters", type=float, help="rough longest dimension, metres")
    ap.add_argument("--archetype", default="auto",
                    choices=["auto", "stack", "truss", "ring", "radial", "power", "dualkeel", "cylinder"],
                    help="structural archetype (default: auto = size-appropriate)")
    ap.add_argument("--min-panels", type=int, default=1, help="min solar wing PAIRS")
    ap.add_argument("--min-labs", type=int, default=1, help="min lab modules")
    ap.add_argument("--min-habs", type=int, default=1, help="min habitat modules")
    ap.add_argument("--seed", type=int, default=1, help="RNG seed (reproducible)")
    ap.add_argument("--count", type=int, default=1, help="how many to emit")
    ap.add_argument("--spread", action="store_true",
                    help="with --count, ramp size 0.5x..20x ISS across the batch")
    ap.add_argument("--game-scale", type=float, default=0.35,
                    help="design-metres -> Godot units (station_model hub ~ ISS*0.35)")
    ap.add_argument("--out", default="assets/stations", help="output directory")
    ap.add_argument("--preview", action="store_true",
                    help="also write a <stem>.png orthographic preview (needs Pillow)")
    ap.add_argument("--selftest", action="store_true",
                    help="validate every archetype across 0.5x..20x ISS and exit")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()

    preview = None
    if args.preview:
        spec = importlib.util.spec_from_file_location(
            "station_preview", os.path.join(os.path.dirname(__file__),
                                            "station_preview.py"))
        preview = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(preview)

    meters0 = args.meters if args.meters else (args.iss or 1.0) * ISS_METERS
    # When spreading with the default (auto) archetype, walk a size-appropriate
    # sequence so a --count 10 batch showcases every archetype instead of a random
    # draw. Falls back to auto for other counts / explicit --archetype.
    SHOWCASE = ["stack", "radial", "stack", "truss", "dualkeel",
                "power", "ring", "truss", "cylinder", "ring"]
    os.makedirs(args.out, exist_ok=True)
    made = []
    for i in range(args.count):
        arch = args.archetype
        if args.spread and args.count > 1:
            frac = i / (args.count - 1)
            iss = 0.5 * (40.0 ** frac)  # geometric 0.5x -> 20x
            meters = iss * ISS_METERS
            if args.archetype == "auto" and args.count == len(SHOWCASE):
                arch = SHOWCASE[i]
        else:
            meters = meters0
        seed = args.seed + i * 1000
        st = generate_one(meters, seed, arch, args.min_panels,
                          args.min_labs, args.min_habs, args.game_scale)
        stem = f"station_{i:02d}_{st.archetype}_{int(round(meters/ISS_METERS*10)):03d}i"
        with open(os.path.join(args.out, stem + ".tscn"), "w") as f:
            f.write(to_tscn(st, args.game_scale))
        with open(os.path.join(args.out, stem + ".json"), "w") as f:
            json.dump(to_json(st, args.game_scale), f, indent=2)
        if preview is not None:
            preview.render(st, os.path.join(args.out, stem + ".png"))
        made.append((stem, st))
        print(f"  {stem}: {st.archetype}, {meters/ISS_METERS:.1f}x ISS, "
              f"{len(st.parts)} parts, panels={st.counts['panels']//2}pr "
              f"labs={st.counts['labs']} habs={st.counts['habs']}")
    print(f"generated {len(made)} station(s) into {args.out}/")
    return 0


def selftest():
    """Generate across the whole size range AND every archetype; assert each
    validates (no interference, min-counts met, not monotonous)."""
    ok = 0
    for arch in ("auto", "stack", "truss", "ring", "radial", "power", "dualkeel", "cylinder"):
        for iss in (0.5, 1, 2, 5, 10, 20):
            for seed in range(1, 4):
                st = generate_one(iss * ISS_METERS, seed, arch, 1, 1, 1, 0.35)
                validate(st)
                ok += 1
    print(f"selftest OK: {ok} stations across 0.5x..20x ISS x every archetype validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
