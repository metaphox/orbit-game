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

SOLAR_SUPPORTED_HEAT_KW_PER_M2 = 0.026
RADIATOR_REJECTION_KW_PER_M2 = 0.096
CREWED_HEAT_KW = {"lab": 0.60, "hab": 0.35}
OTHER_CREWED_HEAT_KW = 0.20
HIGH_POWER_LOAD_MULTIPLIER = 1.24
ORDINARY_RADIATOR_AREA_RATIO = (0.25, 0.35)
HIGH_POWER_RADIATOR_AREA_RATIO = (0.25, 0.42)


# --- tiny 3-vector / matrix helpers (columns = local axes in world space) ------
Vec = tuple  # (x, y, z)

IDENT = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))


def vadd(a: Vec, b: Vec) -> Vec:
    return tuple(a[i] + b[i] for i in range(3))


def vsub(a: Vec, b: Vec) -> Vec:
    return tuple(a[i] - b[i] for i in range(3))


def vscale(v: Vec, scale: float) -> Vec:
    return tuple(x * scale for x in v)


def vdot(a: Vec, b: Vec) -> float:
    return sum(a[i] * b[i] for i in range(3))


def vcross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def vlength(v: Vec) -> float:
    return math.sqrt(vdot(v, v))


def vunit(v: Vec) -> Vec:
    length = vlength(v)
    if length <= 1e-9:
        raise ValueError("cannot normalize a zero vector")
    return vscale(v, 1.0 / length)


def axis_cols(axis: Vec) -> tuple:
    """Return transform columns whose local Y axis follows `axis`."""
    local_y = vunit(axis)
    reference = (0.0, 0.0, 1.0) if abs(local_y[2]) < 0.9 else (1.0, 0.0, 0.0)
    local_x = vunit(vcross(local_y, reference))
    local_z = vunit(vcross(local_x, local_y))
    return local_x, local_y, local_z


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
    `connector` parts are checked through their declared joint rather than as
    free solids, so they may enter endpoint assemblies but no unrelated payload."""
    kind: str            # semantic role, for the blueprint + naming
    mesh: str            # cylinder | cone | capsule | box | torus | sphere
    half: Vec            # local half-extents (x, y, z) before rotation
    pos: Vec
    mat: str
    cols: tuple = IDENT
    connector: bool = False
    extra: dict = field(default_factory=dict)  # mesh-specific (e.g. torus radii)
    assembly: str = ""

    def world_half(self) -> Vec:
        return tuple(
            sum(abs(self.cols[j][i]) * self.half[j] for j in range(3)) for i in range(3)
        )

    def aabb(self):
        wh = self.world_half()
        lo = tuple(self.pos[i] - wh[i] for i in range(3))
        hi = tuple(self.pos[i] + wh[i] for i in range(3))
        return lo, hi


@dataclass
class Assembly:
    id: str
    role: str
    crewed: bool = False
    decorative: bool = False
    part_indices: list[int] = field(default_factory=list)
    metadata: dict = field(default_factory=dict)


@dataclass
class Mount:
    id: str
    owner: str
    name: str
    pos: Vec
    normal: Vec
    radius: float
    joint_types: tuple[str, ...]
    occupied: bool = False


@dataclass
class Joint:
    id: str
    parent_mount: str
    child_mount: str
    kind: str
    connector_parts: list[int] = field(default_factory=list)
    metadata: dict = field(default_factory=dict)


@dataclass
class OrganizationReport:
    score: float
    components: dict[str, float]
    penalties: list[str]


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


def solar_collecting_area(st: Station) -> float:
    return sum(
        assembly.metadata.get("collecting_area", 0.0)
        for assembly in st.assemblies.values()
        if assembly.role == "solar_wing")


def radiator_face_area(st: Station) -> float:
    return sum(
        part.half[1] * 2.0 * part.half[2] * 2.0
        for part in st.parts if part.kind == "radiator")


def estimate_thermal_budget(st: Station) -> dict:
    solar_area = solar_collecting_area(st)
    crewed_heat = sum(
        CREWED_HEAT_KW.get(assembly.role, OTHER_CREWED_HEAT_KW)
        for assembly in st.assemblies.values() if assembly.crewed)
    high_power = st.archetype == "power" or "power" in st.forms
    profile = "high_power" if high_power else "ordinary"
    multiplier = HIGH_POWER_LOAD_MULTIPLIER if high_power else 1.0
    solar_heat = solar_area * SOLAR_SUPPORTED_HEAT_KW_PER_M2
    estimated_heat = (solar_heat + crewed_heat) * multiplier
    raw_area = estimated_heat / RADIATOR_REJECTION_KW_PER_M2
    ratio_range = (HIGH_POWER_RADIATOR_AREA_RATIO if high_power
                   else ORDINARY_RADIATOR_AREA_RATIO)
    target_area = max(solar_area * ratio_range[0],
                      min(raw_area, solar_area * ratio_range[1]))
    return {
        "profile": profile,
        "solar_area_m2": solar_area,
        "solar_supported_heat_kw": solar_heat,
        "crewed_heat_kw": crewed_heat,
        "load_multiplier": multiplier,
        "estimated_heat_load_kw": estimated_heat,
        "rejection_kw_per_m2": RADIATOR_REJECTION_KW_PER_M2,
        "minimum_area_ratio": ratio_range[0],
        "maximum_area_ratio": ratio_range[1],
        "target_radiator_area_m2": target_area,
    }


# --- station builder -----------------------------------------------------------
class Station:
    def __init__(self, seed: int, meters: float, archetype: str,
                 min_panels: int, min_labs: int, min_habs: int):
        self.rng = random.Random(seed)
        self.seed = seed
        self.requested_seed = seed
        self.meters = meters
        self.min_panels = min_panels
        self.min_labs = min_labs
        self.min_habs = min_habs
        self.parts: list[Part] = []
        self.assemblies: dict[str, Assembly] = {}
        self.mounts: dict[str, Mount] = {}
        self.joints: list[Joint] = []
        self.root_assembly: str | None = None
        self.pressure_root: str | None = None
        self.module_assemblies: list[str] = []
        self.frame_assembly: str | None = None
        self.organization: OrganizationReport | None = None
        self.thermal: dict = {}
        self.appendage_x_avoid: list[tuple[float, float]] = []
        self.archetype = self._pick_archetype(archetype)
        self.forms = [self.archetype]
        if self.archetype == "hybrid":
            self.forms = self._pick_hybrid_forms()
        sun_angle = math.radians(self.jitter(-32.0, 32.0))
        self.sun_vector = (0.0, math.cos(sun_angle), math.sin(sun_angle))
        self.sun_angle_deg = math.degrees(sun_angle)
        self.solar_family = self.rng.choice([
            "accordion_rect", "accordion_rect", "petal_fan",
            "round_umbrella", "honeycomb"])
        self.counts = {"labs": 0, "habs": 0, "nodes": 0, "panels": 0,
                       "radiators": 0, "antennas": 0, "ports": 0, "rings": 0,
                       "domes": 0, "tanks": 0, "arms": 0, "tugs": 0,
                       "truss_bays": 0, "windows": 0, "module_lights": 0}

    # -- helpers
    def new_assembly(self, role: str, crewed: bool = False,
                     decorative: bool = False, metadata=None) -> str:
        assembly_id = f"{role}_{len(self.assemblies):03d}"
        self.assemblies[assembly_id] = Assembly(
            assembly_id, role, crewed, decorative, metadata=metadata or {})
        if self.root_assembly is None:
            self.root_assembly = assembly_id
        if crewed and self.pressure_root is None:
            self.pressure_root = assembly_id
        return assembly_id

    def add(self, p: Part, assembly: str | None = None) -> int:
        owner = assembly or self.root_assembly
        if owner is None:
            owner = self.new_assembly("structure")
        p.assembly = owner
        self.parts.append(p)
        part_index = len(self.parts) - 1
        self.assemblies[owner].part_indices.append(part_index)
        return part_index

    def add_mount(self, owner: str, name: str, pos: Vec, normal: Vec,
                  radius: float, joint_types: tuple[str, ...]) -> str:
        mount_id = f"mount_{len(self.mounts):03d}"
        self.mounts[mount_id] = Mount(
            mount_id, owner, name, pos, vunit(normal), radius, joint_types)
        return mount_id

    def connect(self, parent: str, child: str, kind: str,
                parent_pos: Vec, child_pos: Vec, radius: float,
                connector_parts=None, parent_name="out", child_name="in") -> str:
        parent_mount = self.add_mount(
            parent, parent_name, parent_pos, vsub(child_pos, parent_pos)
            if vlength(vsub(child_pos, parent_pos)) > 1e-9 else (1.0, 0.0, 0.0),
            radius, (kind,))
        child_mount = self.add_mount(
            child, child_name, child_pos, vsub(parent_pos, child_pos)
            if vlength(vsub(parent_pos, child_pos)) > 1e-9 else (-1.0, 0.0, 0.0),
            radius, (kind,))
        self.mounts[parent_mount].occupied = True
        self.mounts[child_mount].occupied = True
        joint_id = f"joint_{len(self.joints):03d}"
        self.joints.append(Joint(
            joint_id, parent_mount, child_mount, kind, list(connector_parts or []),
            {"capacity_radius": radius,
             "span": vlength(vsub(parent_pos, child_pos))}))
        return joint_id

    def register_module(self, assembly: str, role: str, center: Vec,
                        radius: float, length: float, axis: Vec) -> None:
        data = self.assemblies[assembly].metadata
        data.update({"center": center, "radius": radius, "length": length,
                     "axis": vunit(axis), "module_role": role})
        self.module_assemblies.append(assembly)

    def containing_module(self, pos: Vec) -> str | None:
        if not self.module_assemblies:
            return None
        containing = []
        containment_tolerance = max(0.02, self.meters * 0.0002)
        for assembly_id in self.module_assemblies:
            data = self.assemblies[assembly_id].metadata
            offset = vsub(pos, data["center"])
            axial = abs(vdot(offset, data["axis"]))
            radial = vlength(vsub(offset, vscale(data["axis"],
                                                 vdot(offset, data["axis"]))))
            if axial <= data["length"] / 2 + containment_tolerance \
                    and radial <= data["radius"] + containment_tolerance:
                containing.append(assembly_id)
        if not containing:
            return None
        return min(
            containing,
            key=lambda assembly_id: vlength(vsub(
                self.assemblies[assembly_id].metadata["center"], pos)))

    def nearest_module(self, pos: Vec) -> str:
        if not self.module_assemblies:
            if self.root_assembly is None:
                raise ValidationError("station has no structural root")
            return self.root_assembly
        containing = self.containing_module(pos)
        if containing is not None:
            return containing
        return min(
            self.module_assemblies,
            key=lambda assembly_id: vlength(vsub(
                self.assemblies[assembly_id].metadata["center"], pos)))

    def connect_module_chain(self, previous: str | None, current: str,
                             boundary: Vec, radius: float) -> str:
        if previous is not None:
            self.connect(previous, current, "pressurized",
                         boundary, boundary, radius,
                         parent_name="axial_out", child_name="axial_in")
        elif self.root_assembly != current:
            self.connect(self.root_assembly, current, "structural",
                         boundary, boundary, radius)
        return current

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
        for _ in range(120):
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
        return self.rng.choice(["truss", "ring", "power", "dualkeel", "cylinder", "hybrid"])

    def _pick_hybrid_forms(self):
        """Choose a coherent recipe rather than mixing arbitrary overlapping forms."""
        return self.rng.choice([
            ["dualkeel", "ring", "dome"],
            ["truss", "ring", "radial"],
            ["power", "ring", "tank_farm"],
        ])

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
        previous_module = None
        axial_modules = []
        for i, ln in enumerate(lengths):
            r = rad * self.jitter(0.82, 1.06)
            joint_radius = r
            # a node hub every few modules: fatter, short, many ports
            is_node = (i > 0 and i < n_mod - 1 and (i % 3 == 0))
            cx = x + ln / 2
            if is_node:
                r_node = rad * 1.18
                module = self.new_assembly("node", crewed=True)
                self.add(Part("node", "cylinder", (r_node, ln / 2, r_node),
                              (cx, 0, 0), MAT["hull"], rot_axis("z", 90)), module)
                self.register_module(module, "node", (cx, 0, 0), r_node, ln,
                                     (1.0, 0.0, 0.0))
                joint_radius = r_node
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
                module = self.new_assembly(role, crewed=True)
                self.counts["labs" if role == "lab" else "habs"] += 1
                self.add(Part(role, "cylinder", (r, ln / 2, r),
                              (cx, 0, 0), mat, rot_axis("z", 90)), module)
                self.register_module(module, role, (cx, 0, 0), r, ln,
                                     (1.0, 0.0, 0.0))
                rmax = max(rmax, r)
                # accent: an orange trim collar mid-module (sparingly)
                if self.rng.random() < 0.28:
                    self.add(Part("trim", "cylinder", (r * 1.04, ln * 0.06, r * 1.04),
                                  (cx, 0, 0), MAT["orange"], rot_axis("z", 90),
                                  connector=True), module)
            previous_module = self.connect_module_chain(
                previous_module, module, (x, 0, 0), min(joint_radius, rad) * 0.7)
            axial_modules.append(module)
            x += ln
        x0, x1 = -span / 2, span / 2
        # end caps / docking ports
        for end, module in ((x0, axial_modules[0]), (x1, axial_modules[-1])):
            sgn = -1 if end == x0 else 1
            self.add(Part("port", "cylinder", (rad * 0.4, rad * 0.22, rad * 0.4),
                          (end + sgn * rad * 0.22, 0, 0), MAT["dark"],
                          rot_axis("z", 90), connector=True,
                          extra={"approach_direction": (float(sgn), 0.0, 0.0)}),
                     module)
            self.counts["ports"] += 1
            if self.rng.random() < 0.6:  # a green nav light by the port
                self.add(Part("light", "sphere", (rad * 0.12,) * 3,
                              (end + sgn * rad * 0.36, rad * 0.2, 0), MAT["green"],
                              connector=True), module)
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
        # A deployed blanket is foil-thin.  Cap the absolute half-thickness so a
        # 20x showcase station does not turn the panels back into metre-scale slabs.
        blanket_half = max(0.004, min(0.18, self.meters * 0.00008))
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
            power_frame_mount = (self.frame_assembly is not None
                                 and (self.archetype == "power" or "power" in self.forms))
            if power_frame_mount:
                mount_host = self.frame_assembly
            else:
                mount_host = self.nearest_module((mx, 0.0, 0.0))
                host_data = self.assemblies[mount_host].metadata
                mount_margin = max(rmax * 0.18, self.meters * 0.003)
                lower = host_data["center"][0] - host_data["length"] / 2 + mount_margin
                upper = host_data["center"][0] + host_data["length"] / 2 - mount_margin
                mx = host_data["center"][0] if lower > upper else min(max(mx, lower), upper)
            wl = wing_len * self.jitter(0.85, 1.15)   # vary so not identical
            self.appendage_x_avoid.append((mx, wing_wid * 0.51))
            pair_leaf_count = self.rng.randint(4, 6)
            tracking_angle = self.sun_angle_deg + self.jitter(-8.0, 8.0)
            angle = math.radians(tracking_angle)
            width_axis = (1.0, 0.0, 0.0)
            panel_normal = (0.0, math.cos(angle), math.sin(angle))
            deploy_axis = (0.0, -math.sin(angle), math.cos(angle))
            for sgn in (-1, 1):                        # symmetric pair
                direction = vscale(deploy_axis, sgn)
                base = (mx, 0.0, 0.0)
                hub = vadd(base, vscale(direction, clear))
                wing = self.new_assembly(
                    "solar_wing",
                    metadata={"family": self.solar_family,
                              "pair": k,
                              "side": sgn,
                              "normal": panel_normal,
                              "tracking_angle_deg": tracking_angle,
                              "hinge_connected": True})
                boom_half = max(rmax * 0.06, blanket_half * 2.5)
                boom_index = self.add(
                    Part("solar_boom", "box",
                         (boom_half, boom_half, clear / 2),
                         vadd(base, vscale(direction, clear / 2)), MAT["dark"],
                         (width_axis, panel_normal, deploy_axis), connector=True),
                    wing)
                spine_half = max(blanket_half * 1.6,
                                 min(0.16, self.meters * 0.0003))
                rail_half = wing_wid * 0.006
                rail_offset = wing_wid * 0.016
                panel_indices = []
                hinge_count = 0
                collecting_area = 0.0

                def wing_point(width_offset, distance):
                    return vadd(
                        vadd(hub, vscale(width_axis, width_offset)),
                        vscale(direction, distance))

                def add_spine(spine_len):
                    for rail_sign in (-1, 1):
                        self.add(
                            Part("solar_spine", "box",
                                 (rail_half, spine_half, spine_len / 2),
                                 wing_point(rail_sign * rail_offset, spine_len / 2),
                                 MAT["dark"],
                                 (width_axis, panel_normal, deploy_axis),
                                 connector=True),
                            wing)

                if self.solar_family == "accordion_rect":
                    bay_count = max(5, min(12, int(round(wl / max(wing_wid * 0.45, 1.0)))))
                    gap = max(blanket_half * 3.0, wl * 0.004)
                    bay_len = (wl - gap * (bay_count - 1)) / bay_count
                    blanket_width = wing_wid * 0.42
                    blanket_offset = wing_wid * 0.255
                    add_spine(wl)
                    for side in (-1, 1):
                        for bay_index in range(bay_count):
                            distance = bay_len / 2 + bay_index * (bay_len + gap)
                            panel_indices.append(self.add(
                                Part("panel", "box",
                                     (blanket_width / 2, blanket_half, bay_len / 2),
                                     wing_point(side * blanket_offset, distance),
                                     MAT["solar"],
                                     (width_axis, panel_normal, deploy_axis)),
                                wing))
                            collecting_area += blanket_width * bay_len
                    for hinge_index in range(1, bay_count):
                        distance = hinge_index * bay_len + (hinge_index - 0.5) * gap
                        self.add(
                            Part("solar_hinge", "box",
                                 (wing_wid * 0.48, spine_half, gap * 0.22),
                                 wing_point(0.0, distance), MAT["dark"],
                                 (width_axis, panel_normal, deploy_axis),
                                 connector=True),
                            wing)
                    hinge_count = (bay_count - 1) * 2
                elif self.solar_family == "petal_fan":
                    leaf_count = pair_leaf_count
                    radius = min(wing_wid * 0.3, wl / (leaf_count * 2.3))
                    add_spine(leaf_count * radius * 2.25)
                    for leaf_index in range(leaf_count):
                        distance = radius * (1.15 + leaf_index * 2.25)
                        width_offset = ((leaf_index % 2) * 2 - 1) * radius * 0.22
                        panel_indices.append(self.add(
                            Part("panel", "polygon",
                                 (radius, blanket_half, radius),
                                 wing_point(width_offset, distance), MAT["solar"],
                                 (width_axis, panel_normal, deploy_axis),
                                 extra={"sides": 5}),
                            wing))
                        collecting_area += 2.38 * radius * radius
                        if leaf_index > 0:
                            self.add(
                                Part("solar_hinge", "box",
                                     (radius * 0.35, spine_half, radius * 0.12),
                                     wing_point(0.0, distance - radius * 1.12),
                                     MAT["dark"],
                                     (width_axis, panel_normal, deploy_axis),
                                     connector=True),
                                wing)
                    hinge_count = leaf_count - 1
                elif self.solar_family == "round_umbrella":
                    radius = min(wing_wid * 0.48, wl * 0.42)
                    centre_distance = radius * 1.35
                    add_spine(centre_distance)
                    centre = wing_point(0.0, centre_distance)
                    panel_indices.append(self.add(
                        Part("panel", "polygon",
                             (radius, blanket_half, radius), centre, MAT["solar"],
                             (width_axis, panel_normal, deploy_axis),
                             extra={"sides": 20}),
                        wing))
                    collecting_area += math.pi * radius * radius
                    for spoke_index in range(8):
                        spoke_angle = math.radians(spoke_index * 22.5)
                        spoke_width = vadd(
                            vscale(width_axis, math.cos(spoke_angle)),
                            vscale(direction, math.sin(spoke_angle)))
                        spoke_axis = vadd(
                            vscale(width_axis, -math.sin(spoke_angle)),
                            vscale(direction, math.cos(spoke_angle)))
                        self.add(
                            Part("solar_rib", "box",
                                 (spine_half, spine_half, radius * 0.88),
                                 centre, MAT["dark"],
                                 (spoke_width, panel_normal, spoke_axis),
                                 connector=True),
                            wing)
                    hinge_count = 8
                else:  # honeycomb
                    row_count = max(3, min(7, int(round(wl / max(wing_wid * 0.55, 1.0)))))
                    cell_radius = min(wing_wid * 0.18, wl / (row_count * 2.3))
                    row_step = cell_radius * 2.2
                    add_spine(row_count * row_step)
                    for row in range(row_count):
                        for column in (-1, 1):
                            width_offset = column * cell_radius * 1.12
                            distance = cell_radius * 1.1 + row * row_step
                            panel_indices.append(self.add(
                                Part("panel", "polygon",
                                     (cell_radius, blanket_half, cell_radius),
                                     wing_point(width_offset, distance), MAT["solar"],
                                     (width_axis, panel_normal, deploy_axis),
                                     extra={"sides": 6}),
                                wing))
                            collecting_area += 2.598 * cell_radius * cell_radius
                        if row > 0:
                            self.add(
                                Part("solar_hinge", "box",
                                     (cell_radius * 1.35, spine_half,
                                      cell_radius * 0.12),
                                     wing_point(0.0, row * row_step),
                                     MAT["dark"],
                                     (width_axis, panel_normal, deploy_axis),
                                     connector=True),
                                wing)
                    hinge_count = max(1, row_count * 2 - 2)

                self.assemblies[wing].metadata.update({
                    "leaf_count": len(panel_indices),
                    "leaf_part_indices": panel_indices,
                    "hinge_edges": ([['gimbal', panel_indices[0]]] +
                                    [[panel_indices[index - 1], panel_indices[index]]
                                     for index in range(1, len(panel_indices))]),
                    "hinge_count": hinge_count,
                    "collecting_area": collecting_area,
                    "stowed_volume": collecting_area * blanket_half * 2.4,
                })
                self.connect(
                    mount_host, wing, "articulated", base, hub, boom_half,
                    connector_parts=[boom_index],
                    parent_name=f"solar_pair_{k}", child_name="gimbal")
            self.counts["panels"] += 2
        return clear

    # -- radiators (perpendicular to the arrays) -------------------------------
    def build_radiators(self, rmax, span, avoid=None):
        budget = estimate_thermal_budget(self)
        target_area = budget["target_radiator_area_m2"]
        nominal_bank_area = max(1.0, self.meters ** 2 * 0.0075)
        required_banks = max(1, math.ceil(target_area / nominal_bank_area))
        solar_pairs = max(1, self.counts["panels"] // 2)
        bank_count = min(6, solar_pairs, required_banks)
        clear = rmax * 1.5
        emitted_area = 0.0
        for i in range(bank_count):
            routed_avoid = list(avoid or []) + self.appendage_x_avoid
            mx = self._free_x(-span * 0.42, span * 0.42, routed_avoid, rmax * 0.3)
            if mx is None:
                raise ValidationError("no room for radiators clear of the rings")
            sgn = -1 if i % 2 == 0 else 1
            area_share = target_area / bank_count
            panel_aspect = self.jitter(5.2, 6.8)
            radiating_length = math.sqrt(area_share * panel_aspect)
            panel_width = math.sqrt(area_share / panel_aspect)
            panel_count = self.rng.randint(6, 8)
            panel_length = radiating_length / panel_count
            fin_half = max(0.02, min(0.12, self.meters * 0.00005))
            gap = max(fin_half * 3.0,
                      min(panel_width * 0.025, panel_length * 0.08))
            deployed_length = radiating_length + gap * (panel_count - 1)
            root_y = sgn * clear
            centre_y = root_y + sgn * deployed_length / 2.0
            spar_half = max(fin_half * 1.6,
                            min(0.18, panel_width * 0.012))
            radiator = self.new_assembly(
                "radiator_bank",
                metadata={"normal": (1.0, 0.0, 0.0),
                          "sun_dot": abs(self.sun_vector[0]),
                          "thermal_profile": budget["profile"],
                          "panel_count": panel_count,
                          "hinge_count": panel_count - 1,
                          "panel_aspect_ratio": panel_aspect,
                          "deployed_aspect_ratio": deployed_length / panel_width,
                          "deployed_length_m": deployed_length,
                          "panel_width_m": panel_width,
                          "radiating_area_m2": area_share,
                          "panel_layer_count": 1,
                          "panel_part_indices": []})
            self.add(
                Part("spar", "box",
                     (spar_half, deployed_length / 2.0, spar_half),
                     (mx, centre_y, 0.0), MAT["dark"], connector=True),
                radiator)
            panel_indices = []
            for panel_index in range(panel_count):
                distance = (panel_length / 2.0
                            + panel_index * (panel_length + gap))
                panel_indices.append(self.add(
                    Part("radiator", "box",
                         (fin_half, panel_length / 2.0, panel_width / 2.0),
                         (mx, root_y + sgn * distance, 0.0), MAT["hull"]),
                    radiator))
                if panel_index < panel_count - 1:
                    hinge_distance = ((panel_index + 1) * panel_length
                                      + panel_index * gap + gap / 2.0)
                    self.add(
                        Part("radiator_hinge", "box",
                             (spar_half * 1.2, gap * 0.18,
                              panel_width * 0.51),
                             (mx, root_y + sgn * hinge_distance, 0.0),
                             MAT["dark"], connector=True),
                        radiator)
            self.assemblies[radiator].metadata["panel_part_indices"] = panel_indices
            boom_index = self.add(
                Part("radiator_boom", "cylinder",
                     (rmax * 0.08, clear / 2, rmax * 0.08),
                     (mx, sgn * clear / 2, 0), MAT["dark"], connector=True),
                radiator)
            host_pos = (mx, 0.0, 0.0)
            bank_pos = (mx, sgn * clear, 0.0)
            host = (self.frame_assembly if self.frame_assembly is not None
                    and (self.archetype == "power" or "power" in self.forms)
                    else self.nearest_module(host_pos))
            self.connect(host, radiator, "structural", host_pos, bank_pos,
                         rmax * 0.08, connector_parts=[boom_index],
                         parent_name="radiator_mount", child_name="bank_spar")
            self.appendage_x_avoid.append((mx, spar_half * 4.5))
            self.counts["radiators"] += 1
            emitted_area += area_share
        budget.update({
            "bank_count": bank_count,
            "emitted_radiator_area_m2": emitted_area,
            "area_ratio": emitted_area / max(budget["solar_area_m2"], 1e-9),
        })
        self.thermal = budget

    # -- structural texture + quasi-sci-fi signature parts -------------------
    def build_truss_lattice(self, x0, x1, rmax):
        """Turn a plain backbone into repeated open lattice bays."""
        truss = self.frame_assembly or self.new_assembly("truss")
        if self.frame_assembly is None:
            self.frame_assembly = truss
            if self.root_assembly != truss:
                host = self.nearest_module(((x0 + x1) / 2, 0.0, 0.0))
                self.connect(host, truss, "structural",
                             ((x0 + x1) / 2, 0, 0),
                             ((x0 + x1) / 2, 0, 0), rmax * 0.2)
        span = x1 - x0
        n_bays = max(3, min(10, int(round(span / max(rmax * 4.0, 1.0)))))
        bay = span / n_bays
        offset = rmax * 1.25
        beam = max(0.12, rmax * 0.11)
        for sz in (-1, 1):
            self.add(Part("truss_rail", "box", (span / 2, beam, beam),
                          ((x0 + x1) / 2, 0, sz * offset), MAT["dark"],
                          connector=True), truss)
        for i in range(n_bays + 1):
            bx = x0 + i * bay
            self.add(Part("truss_crossbeam", "box", (beam, beam, offset),
                          (bx, 0, 0), MAT["dark"], connector=True), truss)
        diag_len = math.hypot(bay, offset * 2)
        diag_angle = math.degrees(math.atan2(offset * 2, bay))
        for i in range(n_bays):
            sign = -1 if i % 2 == 0 else 1
            self.add(Part("truss_brace", "box", (diag_len / 2, beam * 0.7, beam * 0.7),
                          (x0 + (i + 0.5) * bay, 0, 0), MAT["dark"],
                          rot_axis("y", sign * diag_angle), connector=True), truss)
        self.counts["truss_bays"] += n_bays

    def build_tank_cluster(self, rmax, x0, x1, avoid):
        tank_r = rmax * self.jitter(0.28, 0.4)
        routed_avoid = list(avoid) + self.appendage_x_avoid
        mx = self._free_x(x0 * 0.72, x1 * 0.72, routed_avoid, tank_r * 1.5)
        if mx is None:
            return avoid
        host_pos = (mx, 0.0, 0.0)
        host = (self.containing_module(host_pos) or self.frame_assembly
                or self.nearest_module(host_pos))
        if host in self.module_assemblies:
            host_data = self.assemblies[host].metadata
            margin = tank_r * 0.7
            lower = host_data["center"][0] - host_data["length"] / 2 + margin
            upper = host_data["center"][0] + host_data["length"] / 2 - margin
            mx = host_data["center"][0] if lower > upper else min(max(mx, lower), upper)
            host_pos = (mx, 0.0, 0.0)
        host_radius = self.assemblies[host].metadata.get("radius", rmax)
        tanks = self.new_assembly("tank_cluster")
        cy = host_radius + tank_r * 1.15
        spacing = tank_r * 2.35
        for i, z in enumerate((-spacing, 0.0, spacing)):
            mat = MAT["orange"] if i == 1 else MAT["hull"]
            self.add(Part("tank", "sphere", (tank_r,) * 3, (mx, cy, z), mat),
                     tanks)
            self.counts["tanks"] += 1
        rack_index = self.add(
            Part("tank_rack", "box",
                 (tank_r * 0.45, tank_r * 0.18, spacing * 1.25),
                 (mx, host_radius + tank_r * 0.08, 0), MAT["dark"], connector=True),
            tanks)
        mount_index = self.add(
            Part("tank_mount", "cylinder",
                 (tank_r * 0.16, host_radius / 2, tank_r * 0.16),
                 (mx, host_radius / 2, 0), MAT["dark"], connector=True),
            tanks)
        rack_pos = (mx, host_radius, 0.0)
        self.connect(host, tanks, "structural", host_pos, rack_pos,
                     tank_r * 0.3, connector_parts=[rack_index, mount_index],
                     parent_name="tank_rack", child_name="rack_base")
        return avoid + [(mx, tank_r * 1.5)]

    def build_dome(self, rmax, x0, x1, avoid):
        dome_r = rmax * self.jitter(0.7, 1.15)
        mx = self._free_x(x0 * 0.68, x1 * 0.68, avoid, dome_r * 1.15)
        if mx is None:
            return avoid
        host = self.nearest_module((mx, 0.0, 0.0))
        if self.containing_module((mx, 0.0, 0.0)) is None:
            mx = self.assemblies[host].metadata["center"][0]
        host_radius = self.assemblies[host].metadata.get("radius", rmax)
        host_data = self.assemblies[host].metadata
        neck_margin = max(rmax * 0.2, dome_r * 0.18)
        lower = host_data["center"][0] - host_data["length"] / 2 + neck_margin
        upper = host_data["center"][0] + host_data["length"] / 2 - neck_margin
        mx = host_data["center"][0] if lower > upper else min(max(mx, lower), upper)
        dome = self.new_assembly("dome", crewed=True)
        cy = -(host_radius + dome_r)
        self.add(Part("dome", "sphere", (dome_r,) * 3,
                      (mx, cy, 0), MAT["hull"]), dome)
        neck = max(rmax * 0.14, dome_r * 0.12)
        neck_index = self.add(
            Part("dome_neck", "cylinder", (neck, dome_r * 0.22, neck),
                 (mx, -host_radius - dome_r * 0.12, 0), MAT["dark"],
                 connector=True),
            dome)
        parent_pos = (mx, -host_radius, 0.0)
        self.connect(host, dome, "pressurized", parent_pos, parent_pos,
                     neck, connector_parts=[neck_index],
                     parent_name="dome_tunnel", child_name="vestibule")
        self.counts["domes"] += 1
        return avoid + [(mx, dome_r * 1.15)]

    def build_frame_dome(self, frame_height, beam):
        """Raise an observatory from a crew module on a pressure-bearing trunk."""
        if not self.module_assemblies:
            raise ValidationError("frame observatory needs a crew module")
        host = max(
            self.module_assemblies,
            key=lambda assembly_id: self.assemblies[assembly_id].metadata["center"][0])
        host_data = self.assemblies[host].metadata
        host_x = host_data["center"][0]
        host_radius = host_data["radius"]
        dome_r = frame_height * self.jitter(0.085, 0.11)
        cy = frame_height / 2 + dome_r * 0.58
        dome_bottom = cy - dome_r
        trunk_bottom = host_radius
        trunk_length = dome_bottom - trunk_bottom
        if trunk_length <= 0:
            raise ValidationError("observatory trunk has no positive length")
        observatory = self.new_assembly(
            "observatory", crewed=True,
            metadata={"connected_to": host, "pressure_trunk": True})
        self.add(Part("dome", "sphere", (dome_r,) * 3,
                      (host_x, cy, 0), MAT["hull"]), observatory)
        trunk_radius = max(beam * 0.75, host_radius * 0.32)
        trunk_index = self.add(
            Part("pressure_trunk", "cylinder",
                 (trunk_radius, trunk_length / 2, trunk_radius),
                 (host_x, trunk_bottom + trunk_length / 2, 0), MAT["dark"],
                 connector=True), observatory)
        vestibule_radius = max(trunk_radius * 1.55, dome_r * 0.18)
        vestibule_index = self.add(
            Part("observatory_vestibule", "cylinder",
                 (vestibule_radius, dome_r * 0.16, vestibule_radius),
                 (host_x, dome_bottom + dome_r * 0.08, 0), MAT["hull"],
                 connector=True), observatory)
        self.connect(
            host, observatory, "pressurized",
            (host_x, trunk_bottom, 0), (host_x, dome_bottom, 0), trunk_radius,
            connector_parts=[trunk_index, vestibule_index],
            parent_name="observatory_lift", child_name="dome_vestibule")
        self.appendage_x_avoid.append((host_x, vestibule_radius * 1.35))
        self.counts["domes"] += 1

    def build_robot_arm(self, rmax, x0, x1, avoid):
        mx = self._free_x(x0 * 0.75, x1 * 0.75, avoid, rmax * 0.45)
        if mx is None:
            return
        host = self.nearest_module((mx, 0.0, 0.0))
        if self.containing_module((mx, 0.0, 0.0)) is None:
            mx = self.assemblies[host].metadata["center"][0]
        host_radius = self.assemblies[host].metadata.get("radius", rmax)
        reach = rmax * self.jitter(1.1, 1.8)
        thick = max(0.08, rmax * 0.07)
        elbow_y = -host_radius - reach
        wrist_x = mx + reach * 0.85
        arm = self.new_assembly("robot_arm")
        root_segment = self.add(
            Part("arm_segment", "box", (thick, reach / 2, thick),
                 (mx, -host_radius - reach / 2, 0), MAT["orange"], connector=True),
            arm)
        self.add(Part("arm_joint", "sphere", (thick * 2.0,) * 3,
                      (mx, elbow_y, 0), MAT["dark"], connector=True), arm)
        self.add(Part("arm_segment", "box", (reach * 0.425, thick, thick),
                      ((mx + wrist_x) / 2, elbow_y, 0), MAT["orange"], connector=True),
                 arm)
        self.add(Part("arm_joint", "sphere", (thick * 1.6,) * 3,
                      (wrist_x, elbow_y, 0), MAT["green"], connector=True), arm)
        anchor = (mx, -host_radius, 0.0)
        self.connect(host, arm, "articulated", anchor, anchor, thick,
                     connector_parts=[root_segment],
                     parent_name="arm_socket", child_name="shoulder")
        self.counts["arms"] += 1

    def build_docked_tug(self, rmax, x1):
        tug_r = rmax * self.jitter(0.28, 0.42)
        tug_len = max(tug_r * 2.6, rmax * self.jitter(1.1, 1.7))
        gap = rmax * 0.48
        cx = x1 + gap + tug_len / 2
        tug = self.new_assembly("docked_tug")
        self.add(Part("tug_hull", "capsule", (tug_r, tug_len / 2, tug_r),
                      (cx, 0, 0), MAT["hull"], rot_axis("z", 90)), tug)
        self.add(Part("tug_engine", "cone", (tug_r * 1.1, tug_r * 0.26, tug_r * 1.1),
                      (cx + tug_len / 2, 0, 0), MAT["dark"], rot_axis("z", 90),
                      connector=True,
                      extra={"top_radius": tug_r * 0.55,
                             "bottom_radius": tug_r * 1.1}), tug)
        for sy in (-1, 1):
            self.add(Part("tug_fin", "box", (tug_r * 0.45, tug_r * 0.06, tug_r * 0.85),
                          (cx + tug_len * 0.24, sy * tug_r * 0.85, 0), MAT["orange"],
                          connector=True), tug)
        self.add(Part("light", "sphere", (tug_r * 0.16,) * 3,
                      (cx - tug_len * 0.36, tug_r * 0.65, 0), MAT["green"],
                      connector=True), tug)
        adapter_len = gap
        adapter_index = self.add(
            Part("docking_adapter", "cylinder",
                 (tug_r * 0.34, adapter_len / 2, tug_r * 0.34),
                 (x1 + adapter_len / 2, 0, 0), MAT["dark"],
                 rot_axis("z", 90), connector=True),
            tug)
        host_pos = (x1, 0.0, 0.0)
        host = (self.frame_assembly if self.archetype == "power"
                or "power" in self.forms else self.nearest_module(host_pos))
        self.connect(host, tug, "docked", host_pos,
                     (x1 + adapter_len, 0.0, 0.0), tug_r * 0.34,
                     connector_parts=[adapter_index],
                     parent_name="docking_port", child_name="tug_port")
        self.counts["tugs"] += 1

    def build_signature_details(self, rmax, x0, x1, avoid=None):
        """Add two silhouette-level feature families, varied per seed."""
        routed = list(avoid or [])
        features = ["tank", "dome", "arm", "tug"]
        if "tank_farm" in self.forms:
            features.remove("tank")
        if "dome" in self.forms:
            features.remove("dome")
        if self.archetype == "dualkeel" or "dualkeel" in self.forms:
            features.remove("tug")
        for feature in self.rng.sample(features, min(2, len(features))):
            if feature == "tank":
                routed = self.build_tank_cluster(rmax, x0, x1, routed)
            elif feature == "dome":
                routed = self.build_dome(rmax, x0, x1, routed)
            elif feature == "arm":
                self.build_robot_arm(rmax, x0, x1, routed)
            else:
                self.build_docked_tug(rmax, x1)
        return routed

    # -- antennas + observation accents ----------------------------------------
    def build_details(self, rmax, x0, x1, span, avoid=None):
        iss = self.meters / ISS_METERS
        desired = max(1, min(4, int(round(1 + iss * 0.3))))
        n_ant = max(0, desired - self.counts["antennas"])
        frame_edge_mount = self.frame_assembly is not None and (
            self.archetype in ("power", "dualkeel")
            or "power" in self.forms or "dualkeel" in self.forms)
        dual_frame_mount = self.frame_assembly is not None and (
            self.archetype == "dualkeel" or "dualkeel" in self.forms)
        detail_avoid = list(avoid or []) + ([] if dual_frame_mount
                                           else self.appendage_x_avoid)
        for i in range(n_ant):
            mount_lo = -span * 0.5 if frame_edge_mount else x0 * 0.7
            mount_hi = span * 0.5 if frame_edge_mount else x1 * 0.7
            mx = self._free_x(mount_lo, mount_hi, detail_avoid, rmax * 0.7)
            if mx is None:
                raise ValidationError("no room for antennas clear of the rings")
            sgn = self.rng.choice([-1, 1])
            if frame_edge_mount:
                host = self.frame_assembly
            else:
                host = self.nearest_module((mx, 0.0, 0.0))
            if host in self.module_assemblies and self.containing_module(
                    (mx, 0.0, 0.0)) is None:
                mx = self.assemblies[host].metadata["center"][0]
            host_radius = self.assemblies[host].metadata.get(
                "radius", self.assemblies[host].metadata.get("mount_radius", rmax))
            mount_y = self.assemblies[host].metadata.get("antenna_mount_y", 0.0)
            mast = rmax * self.jitter(0.9, 1.6)
            # masts stick out along +/-Z, clear of the +/-Y radiators
            antenna = self.new_assembly("antenna")
            mast_index = self.add(
                Part("mast", "cylinder", (rmax * 0.05, mast / 2, rmax * 0.05),
                     (mx, mount_y, sgn * (host_radius + mast / 2)), MAT["dark"],
                     rot_axis("x", 90), connector=True), antenna)
            dish_r = rmax * self.jitter(0.35, 0.6)
            dish_kind = "antenna" if i == 0 else "sensor_dish"
            self.add(Part(dish_kind, "cone", (dish_r, rmax * 0.08, dish_r),
                          (mx, mount_y,
                           sgn * (host_radius + mast + dish_r * 0.1)), MAT["hull"],
                          rot_axis("x", 90),
                          extra={"top_radius": dish_r * 0.18,
                                 "bottom_radius": dish_r}), antenna)
            anchor = (mx, mount_y, sgn * host_radius)
            self.connect(host, antenna, "structural", anchor, anchor,
                         rmax * 0.05, connector_parts=[mast_index],
                         parent_name="antenna_socket", child_name="mast_base")
            self.counts["antennas"] += 1
            detail_avoid.append((mx, dish_r))
        # a cupola/dome flush on one module (surface feature -> connector)
        if self.counts["domes"] == 0 and self.rng.random() < 0.8:
            mx = self.jitter(x0 * 0.5, x1 * 0.5)
            host = self.nearest_module((mx, 0.0, 0.0))
            if self.containing_module((mx, 0.0, 0.0)) is None:
                mx = self.assemblies[host].metadata["center"][0]
            host_radius = self.assemblies[host].metadata.get("radius", rmax)
            host_data = self.assemblies[host].metadata
            cupola_radius = rmax * 0.5
            lower = host_data["center"][0] - host_data["length"] / 2 + cupola_radius
            upper = host_data["center"][0] + host_data["length"] / 2 - cupola_radius
            mx = host_data["center"][0] if lower > upper else min(max(mx, lower), upper)
            cupola = self.new_assembly("cupola", decorative=True)
            cupola_index = self.add(
                Part("cupola", "sphere", (cupola_radius,) * 3,
                     (mx, -host_radius * 0.9, 0), MAT["dark"], connector=True), cupola)
            anchor = (mx, -host_radius, 0.0)
            self.connect(host, cupola, "surface", anchor, anchor,
                         rmax * 0.25, connector_parts=[cupola_index],
                         parent_name="cupola_mount", child_name="cupola_base")

    # -- rotating habitat ring(s) (ring archetype) -----------------------------
    def build_rings(self, rmax, span, count=None, xs=None, outer_base=None):
        """Non-rotating axial hub + rotating habitat ring(s), spokes between
        (spin-gravity fiction always separates the two). Returns the X-slabs to
        keep arrays/radiators/antennas out of. The torus is treated as a
        connector for the box test; validate() does the real annulus clearance."""
        n = count if count is not None else self.rng.choice([1, 1, 2])
        ring_clear = rmax * 3.0   # inner radius must clear the (conservative) hull band
        ring_xs = xs if xs is not None else (
            [0.0] if n == 1 else [-span * 0.18, span * 0.18])
        slabs = []
        for i in range(n):
            mx = ring_xs[i]
            ring_host = self.nearest_module((mx, 0.0, 0.0))
            mx = self.assemblies[ring_host].metadata["center"][0]
            outer = ((outer_base * self.jitter(0.94, 1.06)) if outer_base is not None
                     else ring_clear * self.jitter(1.0, 1.3))
            tube = max(rmax * self.jitter(0.3, 0.45), outer * 0.045)
            ring = self.new_assembly(
                "habitat_ring", crewed=True,
                metadata={"spin_axis": (1.0, 0.0, 0.0), "radius": outer})
            # ring in the Y-Z plane (spins about the X spine)
            ring_index = self.add(
                Part("ring", "torus", (outer, tube, outer),
                     (mx, 0, 0), MAT["hull"], rot_axis("z", 90), connector=True,
                     extra={"inner": outer - 2 * tube, "outer": outer}), ring)
            self.counts["rings"] += 1
            slabs.append((mx, tube + rmax * 0.3))
            # spokes (connectors) hub -> ring, radial symmetry
            connector_indices = [ring_index]
            for a in range(6):
                ang = math.radians(a * 60)
                y, z = math.sin(ang) * outer / 2, math.cos(ang) * outer / 2
                connector_indices.append(self.add(
                    Part("spoke", "box",
                         (rmax * 0.08, outer / 2, rmax * 0.08),
                         (mx, y, z), MAT["dark"],
                         rot_axis("x", math.degrees(ang)), connector=True), ring))
            host_pos = (mx, 0.0, 0.0)
            self.connect(ring_host, ring, "pressurized", host_pos, host_pos,
                         rmax * 0.18, connector_parts=connector_indices,
                         parent_name=f"ring_{i}_bearing", child_name="spin_hub")
        return slabs

    def build_radial(self, rmax, span, mount_x=0.0):
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
            direction = ((0.0, float(sgn), 0.0) if axis == "y"
                         else (0.0, 0.0, float(sgn)))
            cols = axis_cols(direction)
            ctr = base + ln / 2
            hub = (mount_x, 0.0, 0.0)
            pos = vadd(hub, vscale(direction, ctr))
            role = "lab" if self.rng.random() < 0.5 else "hab"
            module = self.new_assembly(role, crewed=True)
            self.counts["labs" if role == "lab" else "habs"] += 1
            self.add(Part(role, "cylinder", (r, ln / 2, r), pos,
                          MAT["hull"], cols), module)
            self.register_module(module, role, pos, r, ln, direction)
            host = self.nearest_module(hub)
            if host == module and len(self.module_assemblies) > 1:
                host = self.module_assemblies[-2]
            host_radius = self.assemblies[host].metadata.get("radius", rmax)
            tunnel_length = base - host_radius
            tunnel_radius = max(r * 0.28, host_radius * 0.18)
            tunnel_start = vadd(hub, vscale(direction, host_radius))
            tunnel_end = vadd(hub, vscale(direction, base))
            tunnel_index = self.add(
                Part("pressure_tunnel", "cylinder",
                     (tunnel_radius, tunnel_length / 2, tunnel_radius),
                     vscale(vadd(tunnel_start, tunnel_end), 0.5), MAT["dark"],
                     axis_cols(direction), connector=True), module)
            self.connect(host, module, "pressurized", tunnel_start, tunnel_end,
                         tunnel_radius, connector_parts=[tunnel_index],
                         parent_name="radial_hub", child_name="tunnel_in")
            # docking port cap at the far end (connector) + a nav light
            capd = base + ln
            cpos = vadd(hub, vscale(direction, capd))
            self.add(Part("port", "cylinder", (r * 0.4, r * 0.22, r * 0.4),
                          cpos, MAT["dark"], cols, connector=True,
                          extra={"approach_direction": direction}), module)
            self.counts["ports"] += 1
            self.add(Part("light", "sphere", (r * 0.12,) * 3, cpos, MAT["green"],
                          connector=True), module)
        return [(mount_x, rmax * 1.4)]

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
        keel = self.new_assembly("power_keel", metadata={"mount_radius": keel_r})
        self.frame_assembly = keel
        self.add(Part("keel", "box", (span / 2, keel_r, keel_r), (0, 0, 0),
                      MAT["dark"], connector=True), keel)
        # bottom: pressurised module cluster (a short stack)
        n_mod = max(self.min_labs + self.min_habs + 1, self.rng.randint(3, 5))
        clen = span * self.jitter(0.22, 0.32)
        lengths = [self.jitter(0.7, 1.3) for _ in range(n_mod)]
        tot = sum(lengths)
        lengths = [ln / tot * clen for ln in lengths]
        x = x0
        rmax = rad
        wl, wh = self.min_labs, self.min_habs
        previous_module = None
        axial_modules = []
        for ln in lengths:
            r = rad * self.jitter(0.85, 1.05)
            if wl > 0:
                role, wl = "lab", wl - 1
            elif wh > 0:
                role, wh = "hab", wh - 1
            else:
                role = self.rng.choice(["lab", "hab", "hab"])
            module = self.new_assembly(role, crewed=True)
            self.counts["labs" if role == "lab" else "habs"] += 1
            center = (x + ln / 2, 0.0, 0.0)
            self.add(Part(role, "cylinder", (r, ln / 2, r), center,
                          MAT["hull"], rot_axis("z", 90)), module)
            self.register_module(module, role, center, r, ln, (1.0, 0.0, 0.0))
            previous_module = self.connect_module_chain(
                previous_module, module, (x, 0.0, 0.0), min(r, rad) * 0.7)
            axial_modules.append(module)
            rmax = max(rmax, r)
            x += ln
        self.add(Part("port", "cylinder", (rad * 0.4, rad * 0.22, rad * 0.4),
                      (x0 - rad * 0.22, 0, 0), MAT["dark"], rot_axis("z", 90),
                      connector=True,
                      extra={"approach_direction": (-1.0, 0.0, 0.0)}),
                 axial_modules[0])
        self.counts["ports"] += 1
        self.add(Part("light", "sphere", (rad * 0.12,) * 3,
                      (x0 - rad * 0.36, rad * 0.2, 0), MAT["green"], connector=True),
                 axial_modules[0])
        # top: instrument / astronomy mass (a small stack of boxes) + a dish
        mlen = span * self.jitter(0.12, 0.2)
        n_inst = self.rng.randint(2, 4)
        for i in range(n_inst):
            iw = rad * self.jitter(0.55, 0.9)
            ix = x1 - mlen + mlen * (i + 0.5) / n_inst
            self.add(Part("instrument", "box", (mlen / n_inst * 0.4, iw, iw),
                          (ix, 0, 0), MAT["hull"]), keel)
        dish_r = rad * self.jitter(0.5, 0.8)
        self.add(Part("antenna", "cone", (dish_r, rad * 0.08, dish_r),
                      (x1 - mlen * 0.5, 0, rad + dish_r), MAT["hull"], rot_axis("x", 90),
                      extra={"top_radius": dish_r * 0.18,
                             "bottom_radius": dish_r}), keel)
        self.counts["antennas"] += 1
        avoid = [(x0 + clen / 2, clen / 2 + rad * 0.5),
                 (x1 - mlen / 2, mlen / 2 + rad * 0.9)]
        return rmax, x0, x1, span, avoid

    def build_dual_keel(self, height_scale=1.0):
        """1986 NASA Freedom 'Dual Keel' (never flew): a rectangular truss
        picture-frame (aspect ~2:1) with a horizontal mid-boom carrying the
        pressurised modules + arrays, and instruments on the top (astronomy) and
        bottom (Earth-sensing) edges. Frame beams are connectors; the modules ride
        the mid-boom along X. Returns (rmax, x0, x1, span, avoid=[])."""
        iss = self.meters / ISS_METERS
        height = self.meters * height_scale       # hybrid grafts reserve room for a dome
        kx = height * self.jitter(0.21, 0.28)     # half-width (2:1-ish frame)
        beam = max(0.6, 1.2 * (iss ** 0.5))
        frame = self.new_assembly(
            "dual_keel_frame",
            metadata={"mount_radius": beam, "antenna_mount_y": height / 2})
        self.frame_assembly = frame
        # picture-frame: two vertical keels + top/bottom booms (all connectors)
        for sx in (-1, 1):
            self.add(Part("keel", "box", (beam, height / 2, beam),
                          (sx * kx, 0, 0), MAT["dark"], connector=True), frame)
        for sy in (-1, 1):
            self.add(Part("boom", "box", (kx, beam, beam), (0, sy * height / 2, 0),
                          MAT["dark"], connector=True), frame)
        self.add(Part("boom", "box", (kx, beam * 0.8, beam * 0.8), (0, 0, 0),
                      MAT["dark"], connector=True), frame)       # horizontal mid-boom
        # module stack along the mid-boom
        rad = max(1.4, beam * 1.7 * self.jitter(0.9, 1.1))
        n_mod = max(self.min_labs + self.min_habs + 1, self.rng.randint(3, 5))
        stack = kx * 1.4
        lengths = [self.jitter(0.7, 1.3) for _ in range(n_mod)]
        tot = sum(lengths)
        lengths = [ln / tot * stack for ln in lengths]
        x, rmax = -stack / 2, rad
        wl, wh = self.min_labs, self.min_habs
        previous_module = None
        axial_modules = []
        for ln in lengths:
            r = rad * self.jitter(0.85, 1.05)
            if wl > 0:
                role, wl = "lab", wl - 1
            elif wh > 0:
                role, wh = "hab", wh - 1
            else:
                role = self.rng.choice(["lab", "hab", "hab"])
            module = self.new_assembly(role, crewed=True)
            self.counts["labs" if role == "lab" else "habs"] += 1
            center = (x + ln / 2, 0.0, 0.0)
            self.add(Part(role, "cylinder", (r, ln / 2, r), center,
                          MAT["hull"], rot_axis("z", 90)), module)
            self.register_module(module, role, center, r, ln, (1.0, 0.0, 0.0))
            previous_module = self.connect_module_chain(
                previous_module, module, (x, 0.0, 0.0), min(r, rad) * 0.7)
            axial_modules.append(module)
            rmax = max(rmax, r)
            x += ln
        for sgn, module in ((-1, axial_modules[0]), (1, axial_modules[-1])):
            module_data = self.assemblies[module].metadata
            direction = (0.0, 0.0, float(sgn))
            port_half = rad * 0.2
            port_pos = vadd(module_data["center"], vscale(
                direction, module_data["radius"] + port_half))
            self.add(Part("port", "cylinder", (rad * 0.4, rad * 0.2, rad * 0.4),
                          port_pos, MAT["dark"], axis_cols(direction), connector=True,
                          extra={"approach_direction": direction}), module)
            self.counts["ports"] += 1
        # instruments: astronomy on the top edge, Earth-sensing on the bottom
        instrument_sides = ((-1, MAT["dark"]),) if height_scale < 1.0 else (
            (1, MAT["hull"]), (-1, MAT["dark"]))
        for sy, mat in instrument_sides:
            n = self.rng.randint(1, 3)
            for i in range(n):
                iw = beam * self.jitter(1.3, 2.1)
                ix = -kx * 0.6 + (kx * 1.2) * (i + 0.5) / n
                self.add(Part("instrument", "box", (iw, beam * 1.2, iw),
                              (ix, sy * (height / 2 - beam * 1.6), 0), mat), frame)
        return rmax, -stack / 2, stack / 2, kx * 1.7, []

    def build_hybrid(self):
        """Compose proven form-builders with routed X-slabs between each graft."""
        primary = self.forms[0]
        if primary == "dualkeel":
            frame_scale = 0.72
            rmax, x0, x1, span, avoid = self.build_dual_keel(frame_scale)
            frame_height = self.meters * frame_scale
            avoid += self.build_rings(rmax, span, count=1, xs=[0.0],
                                      outer_base=frame_height * 0.29)
            beam = max(0.6, 1.2 * ((self.meters / ISS_METERS) ** 0.5))
            self.build_frame_dome(frame_height, beam)
        elif primary == "truss":
            rmax, x0, x1, span = self.build_spine()
            ring_x = -span * 0.23
            radial_x = span * 0.24
            avoid = self.build_rings(
                rmax, span, count=1, xs=[ring_x],
                outer_base=max(rmax * 4.6, self.meters * 0.07))
            avoid += self.build_radial(rmax, span, mount_x=radial_x)
            self.build_truss_lattice(x0, x1, rmax)
        else:
            rmax, x0, x1, span, avoid = self.build_power_tower()
            avoid += self.build_rings(rmax, span, count=1, xs=[0.0],
                                      outer_base=max(rmax * 3.2, self.meters * 0.085))
            self.build_truss_lattice(x0, x1, rmax)
            avoid = self.build_tank_cluster(rmax, x0, x1, avoid)
        avoid = self.build_signature_details(rmax, x0, x1, avoid)
        self.build_solar(rmax, x0, x1, span, avoid=avoid)
        self.build_radiators(rmax, span, avoid=avoid)
        self.build_details(rmax, x0, x1, span, avoid=avoid)
        return self

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
        drum = self.new_assembly(
            "rotating_drum", crewed=True,
            metadata={"spin_axis": (1.0, 0.0, 0.0)})
        self.add(Part("hab", "cylinder", (rad, length / 2, rad), (0, 0, 0),
                      MAT["hull"], rot_axis("z", 90)), drum)       # the drum
        self.register_module(drum, "hab", (0.0, 0.0, 0.0), rad, length,
                             (1.0, 0.0, 0.0))
        self.counts["habs"] += 1
        for sx in (-1, 1):                                          # endcap rims
            self.add(Part("collar", "cylinder", (rad * 1.05, rad * 0.05, rad * 1.05),
                          (sx * length / 2, 0, 0), MAT["dark"], rot_axis("z", 90),
                          connector=True), drum)
        n_rib = self.rng.randint(3, 6)                             # stiffening ribs
        for i in range(n_rib):
            rx = -length / 2 + length * (i + 1) / (n_rib + 1)
            t = rad * 0.05
            self.add(Part("rib", "torus", (rad * 1.03, t, rad * 1.03), (rx, 0, 0),
                          MAT["dark"], rot_axis("z", 90), connector=True,
                          extra={"inner": rad * 1.03 - 2 * t,
                                 "outer": rad * 1.03}), drum)
        # non-rotating docking hub + module stack beyond the +X endcap
        hub_r = rad * 0.3
        hub_x = length / 2 + hub_r * 1.5
        hub = self.new_assembly("node", crewed=True)
        self.add(Part("node", "cylinder", (hub_r, hub_r * 1.2, hub_r), (hub_x, 0, 0),
                      MAT["hull"], rot_axis("z", 90)), hub)
        self.register_module(hub, "node", (hub_x, 0.0, 0.0), hub_r,
                             hub_r * 2.4, (1.0, 0.0, 0.0))
        shaft_start = (x1, 0.0, 0.0)
        shaft_end = (hub_x - hub_r * 1.2, 0.0, 0.0)
        shaft_length = shaft_end[0] - shaft_start[0]
        shaft_index = self.add(
            Part("pressure_shaft", "cylinder",
                 (hub_r * 0.34, shaft_length / 2, hub_r * 0.34),
                 ((shaft_start[0] + shaft_end[0]) / 2, 0, 0), MAT["dark"],
                 rot_axis("z", 90), connector=True), hub)
        self.connect(drum, hub, "pressurized", shaft_start, shaft_end,
                     hub_r * 0.34, connector_parts=[shaft_index],
                     parent_name="drum_bearing", child_name="docking_hub")
        self.counts["nodes"] += 1
        lx, ant_xs = hub_x + hub_r * 1.2, [hub_x]
        mods = ["lab"] * max(self.min_labs, 1) + ["hab"] * max(0, self.min_habs - 1)
        previous_module = hub
        last_module = hub
        for role in mods:
            ll = hub_r * 1.7
            module = self.new_assembly(role, crewed=True)
            center = (lx + ll / 2, 0.0, 0.0)
            self.add(Part(role, "cylinder", (hub_r * 0.85, ll / 2, hub_r * 0.85),
                          center, MAT["hull"], rot_axis("z", 90)), module)
            self.register_module(module, role, center, hub_r * 0.85, ll,
                                 (1.0, 0.0, 0.0))
            self.connect(previous_module, module, "pressurized",
                         (lx, 0.0, 0.0), (lx, 0.0, 0.0), hub_r * 0.55,
                         parent_name="axial_out", child_name="axial_in")
            previous_module = module
            last_module = module
            self.counts["labs" if role == "lab" else "habs"] += 1
            ant_xs.append(lx + ll / 2)
            lx += ll
        self.add(Part("port", "cylinder", (hub_r * 0.5, hub_r * 0.2, hub_r * 0.5),
                      (lx + hub_r * 0.2, 0, 0), MAT["dark"], rot_axis("z", 90),
                      connector=True,
                      extra={"approach_direction": (1.0, 0.0, 0.0)}), last_module)
        self.counts["ports"] += 1
        self.add(Part("light", "sphere", (hub_r * 0.16,) * 3,
                      (lx + hub_r * 0.35, hub_r * 0.4, 0), MAT["green"], connector=True),
                 last_module)
        # comms dishes on the hub, pointing ±Y (clear of the ±Z solar wings)
        n_ant = max(1, min(2, int(round(1 + iss * 0.2))))
        for i in range(n_ant):
            sgn = 1 if i % 2 == 0 else -1
            ax = ant_xs[i % len(ant_xs)]
            host = self.nearest_module((ax, 0.0, 0.0))
            mount_radius = self.assemblies[host].metadata["radius"]
            mast = hub_r * 1.4
            antenna = self.new_assembly("antenna")
            mast_index = self.add(
                Part("mast", "cylinder", (hub_r * 0.08, mast / 2, hub_r * 0.08),
                     (ax, sgn * (mount_radius + mast / 2), 0), MAT["dark"],
                     connector=True),
                antenna)
            dish_r = hub_r * 0.6
            dish_kind = "antenna" if i == 0 else "sensor_dish"
            self.add(Part(dish_kind, "cone", (dish_r, hub_r * 0.08, dish_r),
                          (ax, sgn * (mount_radius + mast + dish_r * 0.1), 0),
                          MAT["hull"],
                          extra={"top_radius": dish_r * 0.18,
                                 "bottom_radius": dish_r}), antenna)
            anchor = (ax, sgn * mount_radius, 0.0)
            self.connect(host, antenna, "structural", anchor, anchor,
                         hub_r * 0.08, connector_parts=[mast_index],
                         parent_name="antenna_socket", child_name="mast_base")
            self.counts["antennas"] += 1
        # solar wings + radiators alongside the drum (booms clear its radius)
        self.build_solar(rad, x0, x1, length, avoid=[])
        self.build_radiators(rad, length, avoid=[])
        self.build_robot_arm(hub_r, hub_x - hub_r, lx, [])
        self.build_docked_tug(hub_r, lx)
        return self

    def build_crewed_surface_details(self):
        """Give each lab/hab a restrained, clustered band of readable windows."""
        for module_id in tuple(self.module_assemblies):
            module = self.assemblies[module_id]
            role = module.metadata["module_role"]
            if role not in ("lab", "hab"):
                continue
            center = module.metadata["center"]
            radius = module.metadata["radius"]
            length = module.metadata["length"]
            axis = module.metadata["axis"]
            radial_a = ((0.0, 1.0, 0.0) if abs(axis[0]) > 0.8
                        else (1.0, 0.0, 0.0))
            radial_b = vunit(vcross(axis, radial_a))
            radial_a = vunit(vcross(radial_b, axis))
            azimuth = math.radians(self.jitter(-38.0, 38.0))
            normal = vunit(vadd(vscale(radial_a, math.cos(azimuth)),
                                vscale(radial_b, math.sin(azimuth))))
            tangent = vunit(vcross(axis, normal))
            detail = self.new_assembly(
                "module_details", decorative=True,
                metadata={"module": module_id, "clustered": True})
            window_count = (self.rng.randint(1, 4) if role == "lab"
                            else self.rng.randint(2, 6))
            width = max(0.08, min(radius * 0.16, length / (window_count + 2) * 0.34))
            height = max(0.07, radius * 0.11)
            thickness = max(0.018, radius * 0.018)
            first_window = None
            for window_index in range(window_count):
                axial_fraction = ((window_index + 1) / (window_count + 1) - 0.5) * 0.62
                window_center = vadd(
                    vadd(center, vscale(axis, length * axial_fraction)),
                    vscale(normal, radius + thickness))
                part_index = self.add(
                    Part("window", "box", (width, thickness, height),
                         window_center, MAT["dark"],
                         (axis, normal, tangent), connector=True), detail)
                if first_window is None:
                    first_window = part_index
                self.counts["windows"] += 1
            if self.rng.random() < 0.55:
                light_pos = vadd(
                    vadd(center, vscale(axis, length * 0.34)),
                    vadd(vscale(normal, radius + thickness * 2.0),
                         vscale(tangent, height * 1.8)))
                self.add(Part("module_light", "sphere", (height * 0.34,) * 3,
                              light_pos, MAT["green"], connector=True), detail)
                self.counts["module_lights"] += 1
            surface_pos = vadd(center, vscale(normal, radius))
            self.connect(module_id, detail, "surface", surface_pos, surface_pos,
                         max(height, thickness), connector_parts=[first_window],
                         parent_name="window_band", child_name="surface_patch")

    def build(self):
        if self.archetype == "hybrid":
            self.build_hybrid()
        elif self.archetype == "cylinder":
            self.build_cylinder()
        else:
            end_builders = {"power": self.build_power_tower,
                            "dualkeel": self.build_dual_keel}
            if self.archetype in end_builders:
                rmax, x0, x1, span, avoid = end_builders[self.archetype]()
            else:
                rmax, x0, x1, span = self.build_spine()
                avoid = []
                if self.archetype == "ring":
                    avoid = self.build_rings(rmax, span)
                elif self.archetype == "radial":
                    avoid = self.build_radial(rmax, span)
                elif self.archetype == "truss":
                    self.build_truss_lattice(x0, x1, rmax)
            if self.archetype not in ("hybrid", "cylinder"):
                avoid = self.build_signature_details(rmax, x0, x1, avoid)
                self.build_solar(rmax, x0, x1, span, avoid=avoid)
                self.build_radiators(rmax, span, avoid=avoid)
                self.build_details(rmax, x0, x1, span, avoid=avoid)
        self.build_crewed_surface_details()
        return self


# --- validation ----------------------------------------------------------------
class ValidationError(Exception):
    pass


def assembly_bounds(st: Station, assembly_id: str):
    indices = st.assemblies[assembly_id].part_indices
    if not indices:
        raise ValidationError(f"empty assembly: {assembly_id}")
    bounds = [st.parts[index].aabb() for index in indices]
    lo = tuple(min(bound[0][axis] for bound in bounds) for axis in range(3))
    hi = tuple(max(bound[1][axis] for bound in bounds) for axis in range(3))
    return lo, hi


def point_in_bounds(point: Vec, bounds, tolerance: float) -> bool:
    lo, hi = bounds
    return all(lo[axis] - tolerance <= point[axis] <= hi[axis] + tolerance
               for axis in range(3))


def joint_owners(st: Station, joint: Joint) -> tuple[str, str]:
    return (st.mounts[joint.parent_mount].owner,
            st.mounts[joint.child_mount].owner)


def assembly_graph(st: Station, kinds: set[str]) -> dict[str, set[str]]:
    graph = {assembly_id: set() for assembly_id in st.assemblies}
    for joint in st.joints:
        if joint.kind not in kinds:
            continue
        parent, child = joint_owners(st, joint)
        graph[parent].add(child)
        graph[child].add(parent)
    return graph


def graph_distances(graph: dict[str, set[str]], root: str) -> dict[str, int]:
    distances = {root: 0}
    frontier = [root]
    while frontier:
        current = frontier.pop(0)
        for neighbour in graph[current]:
            if neighbour not in distances:
                distances[neighbour] = distances[current] + 1
                frontier.append(neighbour)
    return distances


def validate_radiators(st: Station) -> None:
    if not st.thermal:
        raise ValidationError("station has no thermal budget")
    expected_budget = estimate_thermal_budget(st)
    for key, expected in expected_budget.items():
        actual = st.thermal.get(key)
        if isinstance(expected, str):
            if actual != expected:
                raise ValidationError(f"thermal budget has wrong {key}")
        elif actual is None or not math.isclose(actual, expected, rel_tol=1e-8):
            raise ValidationError(f"thermal budget has inconsistent {key}")

    banks = [assembly for assembly in st.assemblies.values()
             if assembly.role == "radiator_bank"]
    if len(banks) != st.counts["radiators"] or not banks:
        raise ValidationError("radiator bank count does not match the blueprint")
    if st.thermal.get("bank_count") != len(banks):
        raise ValidationError("thermal budget has inconsistent bank count")

    solar_area = expected_budget["solar_area_m2"]
    emitted_area = radiator_face_area(st)
    target_area = expected_budget["target_radiator_area_m2"]
    if not math.isclose(emitted_area, target_area, rel_tol=1e-8):
        raise ValidationError("radiator area does not satisfy the thermal budget")
    if not math.isclose(st.thermal.get("emitted_radiator_area_m2", -1.0),
                        emitted_area, rel_tol=1e-8):
        raise ValidationError("thermal budget has inconsistent emitted area")
    area_ratio = emitted_area / solar_area
    if not math.isclose(st.thermal.get("area_ratio", -1.0), area_ratio,
                        rel_tol=1e-8):
        raise ValidationError("thermal budget has inconsistent area ratio")
    if not (expected_budget["minimum_area_ratio"] - 1e-8 <= area_ratio
            <= expected_budget["maximum_area_ratio"] + 1e-8):
        raise ValidationError("radiator area ratio is outside its thermal profile")

    normal_tolerance = math.sin(math.radians(15.0))
    for bank in banks:
        data = bank.metadata
        panel_indices = data.get("panel_part_indices", [])
        panel_count = data.get("panel_count", 0)
        if panel_count not in range(6, 9) or len(panel_indices) != panel_count:
            raise ValidationError(f"{bank.id} needs 6-8 accordion panels")
        if data.get("hinge_count") != panel_count - 1:
            raise ValidationError(f"{bank.id} has an incomplete hinge sequence")
        if data.get("panel_layer_count") != 1:
            raise ValidationError(f"{bank.id} has duplicate radiator layers")
        if not 5.0 <= data.get("panel_aspect_ratio", 0.0) <= 7.0:
            raise ValidationError(f"{bank.id} has an implausible aspect ratio")
        normal = vunit(data["normal"])
        if abs(vdot(normal, vunit(st.sun_vector))) > normal_tolerance:
            raise ValidationError(f"{bank.id} is not edge-on to the sun")
        panels = [st.parts[index] for index in panel_indices]
        if any(panel.kind != "radiator" or panel.assembly != bank.id
               for panel in panels):
            raise ValidationError(f"{bank.id} references a foreign panel")
        normal_offsets = [vdot(panel.pos, normal) for panel in panels]
        if max(normal_offsets) - min(normal_offsets) > max(0.02, st.meters * 0.0001):
            raise ValidationError(f"{bank.id} has duplicate radiator layers")
        bank_area = sum(panel.half[1] * 2.0 * panel.half[2] * 2.0
                        for panel in panels)
        if not math.isclose(bank_area, data.get("radiating_area_m2", -1.0),
                            rel_tol=1e-8):
            raise ValidationError(f"{bank.id} has inconsistent panel area")
        hinges = [st.parts[index] for index in bank.part_indices
                  if st.parts[index].kind == "radiator_hinge"]
        if len(hinges) != panel_count - 1:
            raise ValidationError(f"{bank.id} has missing visible hinges")


def validate_connectivity(st: Station) -> None:
    if st.root_assembly is None or st.pressure_root is None:
        raise ValidationError("station needs structural and pressurized roots")
    if st.root_assembly not in st.assemblies or st.pressure_root not in st.assemblies:
        raise ValidationError("station root references an unknown assembly")
    for part_index, part in enumerate(st.parts):
        if part.assembly not in st.assemblies:
            raise ValidationError(f"part {part_index} has no valid assembly owner")
    structural = assembly_graph(
        st, {"structural", "pressurized", "articulated", "docked"})
    connected = graph_distances(structural, st.root_assembly)
    disconnected = [assembly_id for assembly_id, assembly in st.assemblies.items()
                    if not assembly.decorative and assembly_id not in connected]
    if disconnected:
        raise ValidationError(
            "disconnected assemblies: " + ", ".join(disconnected))
    pressure = assembly_graph(st, {"pressurized", "docked"})
    pressurized = graph_distances(pressure, st.pressure_root)
    isolated_crew = [assembly_id for assembly_id, assembly in st.assemblies.items()
                     if assembly.crewed and assembly_id not in pressurized]
    if isolated_crew:
        raise ValidationError(
            "crewed assemblies lack a pressurized path: " +
            ", ".join(isolated_crew))

    tolerance = max(0.04, st.meters * 0.001)
    bounds = {assembly_id: assembly_bounds(st, assembly_id)
              for assembly_id in st.assemblies}
    valid_joint_types = {"structural", "pressurized", "articulated",
                         "surface", "docked"}
    for joint in st.joints:
        if joint.kind not in valid_joint_types:
            raise ValidationError(f"unknown joint type: {joint.kind}")
        parent_mount = st.mounts[joint.parent_mount]
        child_mount = st.mounts[joint.child_mount]
        if joint.kind not in parent_mount.joint_types or joint.kind not in child_mount.joint_types:
            raise ValidationError(f"joint {joint.id} uses an incompatible mount")
        if not parent_mount.occupied or not child_mount.occupied:
            raise ValidationError(f"joint {joint.id} has an unoccupied mount")
        if vdot(parent_mount.normal, child_mount.normal) > -0.5:
            raise ValidationError(f"joint {joint.id} mount normals do not oppose")
        if not point_in_bounds(parent_mount.pos, bounds[parent_mount.owner], tolerance):
            raise ValidationError(f"joint {joint.id} parent mount floats off its owner")
        if not point_in_bounds(child_mount.pos, bounds[child_mount.owner], tolerance):
            raise ValidationError(f"joint {joint.id} child mount floats off its owner")
        gap = vlength(vsub(parent_mount.pos, child_mount.pos))
        if gap > tolerance:
            if not joint.connector_parts:
                raise ValidationError(f"joint {joint.id} has a physical gap")
            connector_bounds = [st.parts[index].aabb()
                                for index in joint.connector_parts]
            connector_union = (
                tuple(min(bound[0][axis] for bound in connector_bounds)
                      for axis in range(3)),
                tuple(max(bound[1][axis] for bound in connector_bounds)
                      for axis in range(3)))
            if not point_in_bounds(parent_mount.pos, connector_union, tolerance):
                raise ValidationError(f"joint {joint.id} connector misses parent")
            if not point_in_bounds(child_mount.pos, connector_union, tolerance):
                raise ValidationError(f"joint {joint.id} connector misses child")
        if joint.kind == "pressurized":
            minimum_aperture = max(0.18, min(0.65, st.meters * 0.0015))
            if min(parent_mount.radius, child_mount.radius) < minimum_aperture:
                raise ValidationError(f"joint {joint.id} pressure aperture is too small")
        endpoints = {parent_mount.owner, child_mount.owner}
        connector_epsilon = max(0.02, st.meters * 0.0002)
        for connector_index in joint.connector_parts:
            connector = st.parts[connector_index]
            if connector.assembly not in endpoints:
                raise ValidationError(f"joint {joint.id} uses a foreign connector")
            for other in st.parts:
                if other.connector or other.assembly in endpoints:
                    continue
                if aabb_overlap(connector, other, connector_epsilon):
                    raise ValidationError(
                        f"joint {joint.id} connector crosses {other.assembly}")

    surface_joints = {}
    for joint in st.joints:
        if joint.kind == "surface":
            _, child = joint_owners(st, joint)
            surface_joints.setdefault(child, []).append(joint)
    for module_id in st.module_assemblies:
        module = st.assemblies[module_id]
        role = module.metadata["module_role"]
        if role not in ("lab", "hab"):
            continue
        details = [assembly_id for assembly_id, assembly in st.assemblies.items()
                   if assembly.metadata.get("module") == module_id]
        if len(details) != 1 or len(surface_joints.get(details[0], [])) != 1:
            raise ValidationError(f"{module_id} needs exactly one owned surface detail")
        detail_parts = [st.parts[index]
                        for index in st.assemblies[details[0]].part_indices]
        window_count = sum(part.kind == "window" for part in detail_parts)
        expected = (range(1, 5) if role == "lab" else range(2, 7))
        if window_count not in expected:
            raise ValidationError(f"{module_id} has an implausible window count")
        if sum(part.kind == "module_light" for part in detail_parts) > 1:
            raise ValidationError(f"{module_id} has too many status lights")
        axis = module.metadata["axis"]
        center = module.metadata["center"]
        radius = module.metadata["radius"]
        for part in detail_parts:
            offset = vsub(part.pos, center)
            radial = vsub(offset, vscale(axis, vdot(offset, axis)))
            if abs(vlength(radial) - radius) > max(radius * 0.08, tolerance):
                raise ValidationError(f"{module_id} has a floating {part.kind}")

    solar_pairs = {}
    for assembly_id, assembly in st.assemblies.items():
        if assembly.role != "solar_wing":
            continue
        data = assembly.metadata
        if not data.get("hinge_connected") or data.get("leaf_count", 0) < 1:
            raise ValidationError(f"{assembly_id} has no connected solar leaves")
        hinge_graph = {}
        for parent, child in data.get("hinge_edges", []):
            hinge_graph.setdefault(parent, set()).add(child)
        reachable_leaves = {"gimbal"}
        hinge_frontier = ["gimbal"]
        while hinge_frontier:
            hinge_parent = hinge_frontier.pop()
            for hinge_child in hinge_graph.get(hinge_parent, set()):
                if hinge_child not in reachable_leaves:
                    reachable_leaves.add(hinge_child)
                    hinge_frontier.append(hinge_child)
        if any(part_index not in reachable_leaves
               for part_index in data["leaf_part_indices"]):
            raise ValidationError(f"{assembly_id} has a leaf outside its hinge tree")
        if data.get("hinge_count", 0) < max(1, data["leaf_count"] - 2):
            raise ValidationError(f"{assembly_id} has an incomplete hinge tree")
        if data.get("collecting_area", 0.0) <= 0 or data.get("stowed_volume", 0.0) <= 0:
            raise ValidationError(f"{assembly_id} has no plausible stowed envelope")
        if vdot(vunit(data["normal"]), vunit(st.sun_vector)) < math.cos(math.radians(15)):
            raise ValidationError(f"{assembly_id} is not tracking the sun")
        solar_pairs.setdefault(data["pair"], []).append(data)
    for pair, wings in solar_pairs.items():
        if len(wings) != 2:
            raise ValidationError(f"solar pair {pair} is not mirrored")
        left, right = wings
        if (left["family"], left["leaf_count"], left["hinge_count"]) != (
                right["family"], right["leaf_count"], right["hinge_count"]):
            raise ValidationError(f"solar pair {pair} has mismatched topology")
        if not math.isclose(left["collecting_area"], right["collecting_area"],
                            rel_tol=1e-8):
            raise ValidationError(f"solar pair {pair} has mismatched area")

    validate_radiators(st)

    occupied_port_owners = {joint_owners(st, joint)[0] for joint in st.joints
                            if joint.kind == "docked"}
    approach_epsilon = max(0.02, st.meters * 0.0002)
    for port in (part for part in st.parts if part.kind == "port"):
        if port.assembly in occupied_port_owners:
            continue
        if "approach_direction" not in port.extra:
            raise ValidationError(f"port on {port.assembly} has no approach direction")
        direction = vunit(port.extra["approach_direction"])
        approach_length = max(port.half[0] * 4.0, st.meters * 0.01)
        approach_start = vadd(port.pos, vscale(direction, port.half[1]))
        approach = Part(
            "docking_approach", "box",
            (port.half[0] * 1.2, approach_length / 2, port.half[0] * 1.2),
            vadd(approach_start, vscale(direction, approach_length / 2)),
            MAT["dark"], axis_cols(direction))
        for other in st.parts:
            if other.assembly == port.assembly:
                continue
            if aabb_overlap(approach, other, approach_epsilon):
                raise ValidationError(
                    f"docking approach from {port.assembly} is obstructed by "
                    f"{other.assembly}")


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
    validate_connectivity(st)
    c = st.counts
    if c["panels"] < 2 * st.min_panels:
        raise ValidationError(f"too few solar pairs: {c['panels']//2} < {st.min_panels}")
    if c["labs"] < st.min_labs:
        raise ValidationError(f"too few labs: {c['labs']} < {st.min_labs}")
    if c["habs"] < st.min_habs:
        raise ValidationError(f"too few habitats: {c['habs']} < {st.min_habs}")
    if c["panels"] == 0 or c["antennas"] == 0 or c["ports"] == 0:
        raise ValidationError("a station needs power, comms and a docking port")
    if c["antennas"] > 4:
        raise ValidationError(f"too many antennas: {c['antennas']} > 4")
    signature_families = sum(
        int(c[name] > 0) for name in ("domes", "tanks", "arms", "tugs"))
    if signature_families < 2:
        raise ValidationError("a station needs at least two signature detail families")
    # not-all-identical: at least a few distinct part kinds present
    kinds = {p.kind for p in st.parts}
    if len(kinds) < 5:
        raise ValidationError(f"too monotonous: only {len(kinds)} part kinds")
    return True


def part_volume(part: Part) -> float:
    if part.mesh == "sphere":
        return 4.0 / 3.0 * math.pi * part.half[0] * part.half[1] * part.half[2]
    if part.mesh == "capsule":
        radius = (part.half[0] + part.half[2]) / 2.0
        cylinder_length = max(0.0, part.half[1] * 2.0 - radius * 2.0)
        return (math.pi * radius * radius * cylinder_length
                + 4.0 / 3.0 * math.pi * radius ** 3)
    if part.mesh in ("cylinder", "polygon"):
        return math.pi * part.half[0] * part.half[2] * part.half[1] * 2.0
    if part.mesh == "cone":
        top = part.extra.get("top_radius", part.half[0])
        bottom = part.extra.get("bottom_radius", part.half[2])
        height = part.half[1] * 2.0
        return math.pi * height * (top * top + top * bottom + bottom * bottom) / 3.0
    if part.mesh == "torus":
        major = max(part.extra["outer"] - part.half[1], part.half[1])
        return 2.0 * math.pi * math.pi * major * part.half[1] * part.half[1]
    return part.half[0] * part.half[1] * part.half[2] * 8.0


def analyze_organization(st: Station) -> OrganizationReport:
    """Return a deterministic report-only quality index for human calibration."""
    structural = assembly_graph(
        st, {"structural", "pressurized", "articulated", "docked"})
    pressure = assembly_graph(st, {"pressurized", "docked"})
    structural_depths = graph_distances(structural, st.root_assembly)
    pressure_depths = graph_distances(pressure, st.pressure_root)
    crew_depths = [pressure_depths[assembly_id]
                   for assembly_id, assembly in st.assemblies.items()
                   if assembly.crewed]
    mean_crew_depth = sum(crew_depths) / max(1, len(crew_depths))
    pressure_path_quality = max(0.0, 1.0 - max(0.0, mean_crew_depth - 1.0) / 5.0)
    connected_joint_ratio = sum(
        bool(joint.connector_parts)
        or vlength(vsub(st.mounts[joint.parent_mount].pos,
                        st.mounts[joint.child_mount].pos)) <= st.meters * 0.001
        for joint in st.joints) / max(1, len(st.joints))
    connection_quality = 0.68 * pressure_path_quality + 0.32 * connected_joint_ratio

    solar_alignment = [vdot(vunit(assembly.metadata["normal"]),
                            vunit(st.sun_vector))
                       for assembly in st.assemblies.values()
                       if assembly.role == "solar_wing"]
    radiator_alignment = [1.0 - abs(vdot(vunit(assembly.metadata["normal"]),
                                          vunit(st.sun_vector)))
                          for assembly in st.assemblies.values()
                          if assembly.role == "radiator_bank"]
    functional_samples = solar_alignment + radiator_alignment
    functional_orientation = (sum(functional_samples) / len(functional_samples)
                              if functional_samples else 0.0)

    degrees = [len(neighbours) for assembly_id, neighbours in structural.items()
               if not st.assemblies[assembly_id].decorative]
    maximum_degree = max(degrees, default=0)
    hub_margin = max(0.0, 1.0 - max(0, maximum_degree - 6) / 18.0)
    mount_margin = max(0.0, 1.0 - len(st.joints) / max(18.0, len(st.assemblies) * 2.2))
    spatial_clearance = 0.72 * hub_margin + 0.28 * mount_margin

    total_volume = 0.0
    weighted_center = (0.0, 0.0, 0.0)
    for part in st.parts:
        weight = part_volume(part) * (0.22 if part.connector else 1.0)
        total_volume += weight
        weighted_center = vadd(weighted_center, vscale(part.pos, weight))
    center_offset = vlength(vscale(weighted_center, 1.0 / max(total_volume, 1e-9)))
    balance_allowance = (0.30 if st.archetype == "power" or "power" in st.forms
                         else 0.20 if st.archetype == "radial" or "radial" in st.forms
                         else 0.14)
    mass_balance = max(0.0, 1.0 - center_offset /
                       max(st.meters * balance_allowance, 1.0))

    maximum_depth = max(structural_depths.values(), default=0)
    depth_quality = max(0.0, 1.0 - max(0, maximum_depth - 4) / 7.0)
    overload_quality = max(0.0, 1.0 - max(0, maximum_degree - 8) / 14.0)
    routing_hierarchy = 0.62 * depth_quality + 0.38 * overload_quality

    solar_pairs = {}
    for assembly in st.assemblies.values():
        if assembly.role == "solar_wing":
            solar_pairs.setdefault(assembly.metadata["pair"], []).append(assembly.metadata)
    pair_coherence = sum(
        len(wings) == 2
        and wings[0]["leaf_count"] == wings[1]["leaf_count"]
        and math.isclose(wings[0]["collecting_area"], wings[1]["collecting_area"])
        for wings in solar_pairs.values()) / max(1, len(solar_pairs))
    detailed_modules = sum(
        assembly.metadata.get("module") in st.module_assemblies
        for assembly in st.assemblies.values())
    crew_modules = sum(
        st.assemblies[assembly_id].metadata["module_role"] in ("lab", "hab")
        for assembly_id in st.module_assemblies)
    window_coherence = detailed_modules / max(1, crew_modules)
    kind_count = len({part.kind for part in st.parts})
    variety_quality = max(0.0, 1.0 - abs(kind_count - 18) / 28.0)
    pattern_coherence = (0.46 * pair_coherence + 0.34 * window_coherence
                         + 0.20 * variety_quality)

    components = {
        "connection_quality": max(0.0, min(1.0, connection_quality)),
        "functional_orientation": max(0.0, min(1.0, functional_orientation)),
        "spatial_clearance": max(0.0, min(1.0, spatial_clearance)),
        "mass_balance": max(0.0, min(1.0, mass_balance)),
        "routing_hierarchy": max(0.0, min(1.0, routing_hierarchy)),
        "pattern_coherence": max(0.0, min(1.0, pattern_coherence)),
    }
    weights = {"connection_quality": 25, "functional_orientation": 20,
               "spatial_clearance": 15, "mass_balance": 15,
               "routing_hierarchy": 15, "pattern_coherence": 10}
    score = sum(components[name] * weight for name, weight in weights.items())
    penalties = []
    if max(crew_depths, default=0) > 3:
        penalties.append("a crewed volume is more than three joints from the pressure core")
    if maximum_degree > 8:
        penalties.append("one attachment hub carries too many branches")
    if components["spatial_clearance"] < 0.72:
        penalties.append("mount spacing leaves narrow service clearance")
    if components["mass_balance"] < 0.72:
        penalties.append("volume-weighted mass is noticeably off the recipe axis")
    if components["pattern_coherence"] < 0.8:
        penalties.append("surface and appendage rhythms need stronger repetition")
    rounded_components = {name: round(value, 4)
                          for name, value in components.items()}
    return OrganizationReport(round(score, 1), rounded_components, penalties)


# --- serialisation -------------------------------------------------------------
def _fmt(v: float) -> str:
    return f"{v:.4f}".rstrip("0").rstrip(".") if v == v else "0"


def godot_transform_values(part: Part, scale: float) -> tuple[float, ...]:
    """Godot's text Transform3D constructor takes matrix rows, while Part.cols
    stores world-space local axes (matrix columns). Transpose at this boundary."""
    cols = part.cols
    origin = tuple(value * scale for value in part.pos)
    return (cols[0][0], cols[1][0], cols[2][0],
            cols[0][1], cols[1][1], cols[2][1],
            cols[0][2], cols[1][2], cols[2][2],
            origin[0], origin[1], origin[2])


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
    report = st.organization or analyze_organization(st)
    sun = st.sun_vector
    subs, nodes = [], [
        '[node name="Station" type="Node3D"]',
        f'metadata/sun_vector = Vector3({_fmt(sun[0])}, {_fmt(sun[1])}, {_fmt(sun[2])})',
        f'metadata/solar_family = "{st.solar_family}"',
        f'metadata/thermal_profile = "{st.thermal["profile"]}"',
        f'metadata/radiator_area_ratio = {_fmt(st.thermal["area_ratio"])}',
        f'metadata/estimated_heat_load_kw = {_fmt(st.thermal["estimated_heat_load_kw"])}',
        f'metadata/organization_score = {_fmt(report.score)}', '']
    matname = {v: k for k, v in MAT.items()}
    for idx, p in enumerate(st.parts):
        mid = f"m{idx}"
        h = tuple(x * scale for x in p.half)
        mat_id = ext[matname[p.mat]]
        if p.mesh in ("cylinder", "cone", "polygon"):
            top_radius = (p.extra.get("top_radius", p.half[0]) * scale)
            bottom_radius = (p.extra.get("bottom_radius", p.half[2]) * scale)
            subs += [f'[sub_resource type="CylinderMesh" id="{mid}"]',
                     f'material = ExtResource("{mat_id}")',
                     f'top_radius = {_fmt(top_radius)}',
                     f'bottom_radius = {_fmt(bottom_radius)}',
                     f'height = {_fmt(h[1]*2)}',
                     f'radial_segments = {p.extra.get("sides", 12)}', 'rings = 1', '']
        elif p.mesh == "capsule":
            subs += [f'[sub_resource type="CapsuleMesh" id="{mid}"]',
                     f'material = ExtResource("{mat_id}")',
                     f'radius = {_fmt(h[0])}', f'height = {_fmt(h[1]*2)}',
                     'radial_segments = 12', 'rings = 4', '']
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
        tf = ", ".join(_fmt(value)
                       for value in godot_transform_values(p, scale))
        nm = f"{p.kind.capitalize()}{idx}"
        nodes += [f'[node name="{nm}" type="MeshInstance3D" parent="."]',
                  f'transform = Transform3D({tf})',
                  f'mesh = SubResource("{mid}")', '']
    return "\n".join(head + subs + nodes)


def to_json(st: Station, scale: float) -> dict:
    report = st.organization or analyze_organization(st)
    return {
        "requested_seed": st.requested_seed, "seed": st.seed,
        "resolved_seed": st.seed, "archetype": st.archetype, "forms": st.forms,
        "meters": round(st.meters, 1), "iss_multiple": round(st.meters / ISS_METERS, 2),
        "game_scale": scale, "counts": st.counts,
        "sun_vector": [round(value, 6) for value in st.sun_vector],
        "solar_family": st.solar_family,
        "thermal": st.thermal,
        "station_root": st.root_assembly,
        "pressurized_root": st.pressure_root,
        "organization_score": report.score,
        "organization": {"score": report.score,
                         "components": report.components,
                         "penalties": report.penalties,
                         "mode": "report_only"},
        "assemblies": [
            {"id": assembly.id, "role": assembly.role,
             "crewed": assembly.crewed, "decorative": assembly.decorative,
             "part_indices": assembly.part_indices,
             "metadata": assembly.metadata}
            for assembly in st.assemblies.values()],
        "mounts": [
            {"id": mount.id, "owner": mount.owner, "name": mount.name,
             "pos": [round(value, 3) for value in mount.pos],
             "normal": [round(value, 6) for value in mount.normal],
             "radius": round(mount.radius, 3),
             "joint_types": list(mount.joint_types), "occupied": mount.occupied}
            for mount in st.mounts.values()],
        "joints": [
            {"id": joint.id, "parent_mount": joint.parent_mount,
             "child_mount": joint.child_mount, "kind": joint.kind,
             "connector_parts": joint.connector_parts,
             "metadata": joint.metadata}
            for joint in st.joints],
        "parts": [{"kind": p.kind, "mesh": p.mesh,
                   "pos": [round(x, 3) for x in p.pos],
                   "half": [round(x, 3) for x in p.half],
                   "connector": p.connector, "assembly": p.assembly,
                   "extra": p.extra,
                   "cols": [[round(value, 6) for value in axis]
                            for axis in p.cols]}
                  for p in st.parts],
    }


# --- CLI -----------------------------------------------------------------------
def generate_one(meters, seed, archetype, min_panels, min_labs, min_habs,
                 scale, retries=40):
    """Build + validate, retrying with a nudged seed until it passes."""
    last = None
    for k in range(retries):
        try:
            st = Station(seed + k * 101, meters, archetype,
                         min_panels, min_labs, min_habs).build()
            validate(st)
            st.requested_seed = seed
            st.organization = analyze_organization(st)
            return st
        except ValidationError as e:
            last = e
    raise ValidationError(f"could not satisfy constraints after {retries} tries: {last}")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Procedurally generate space stations.")
    ap.add_argument("--iss", type=float, help="rough size in ISS multiples (~109 m)")
    ap.add_argument("--meters", type=float, help="rough longest dimension, metres")
    ap.add_argument("--archetype", default="auto",
                    choices=["auto", "stack", "truss", "ring", "radial", "power",
                             "dualkeel", "cylinder", "hybrid"],
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
    ap.add_argument("--preview-out",
                    help="optional directory for PNG previews (default: --out)")
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
                "power", "ring", "hybrid", "cylinder", "hybrid"]
    os.makedirs(args.out, exist_ok=True)
    preview_out = args.preview_out or args.out
    if preview is not None:
        os.makedirs(preview_out, exist_ok=True)
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
        descriptor = st.archetype
        if st.archetype == "hybrid":
            descriptor += "_" + "_".join(st.forms)
        stem = f"station_{i:02d}_{descriptor}_{int(round(meters/ISS_METERS*10)):03d}i"
        with open(os.path.join(args.out, stem + ".tscn"), "w") as f:
            f.write(to_tscn(st, args.game_scale))
        with open(os.path.join(args.out, stem + ".json"), "w") as f:
            json.dump(to_json(st, args.game_scale), f, indent=2)
        if preview is not None:
            preview.render(st, os.path.join(preview_out, stem + ".png"))
        made.append((stem, st))
        print(f"  {stem}: {st.archetype}, {meters/ISS_METERS:.1f}x ISS, "
              f"{len(st.parts)} parts, panels={st.counts['panels']//2}pr "
              f"labs={st.counts['labs']} habs={st.counts['habs']} "
              f"organization={st.organization.score:.1f}")
    print(f"generated {len(made)} station(s) into {args.out}/")
    return 0


def selftest():
    """Generate across the whole size range AND every archetype; assert each
    validates (no interference, min-counts met, not monotonous)."""
    ok = 0
    for arch in ("auto", "stack", "truss", "ring", "radial", "power", "dualkeel",
                 "cylinder", "hybrid"):
        for iss in (0.5, 1, 2, 5, 10, 20):
            for seed in range(1, 4):
                st = generate_one(iss * ISS_METERS, seed, arch, 1, 1, 1, 0.35)
                validate(st)
                ok += 1
    print(f"selftest OK: {ok} stations across 0.5x..20x ISS x every archetype validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
