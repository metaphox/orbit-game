#!/usr/bin/env python3
"""Unit tests for station_gen. Runs standalone (`python3 tools/test_station_gen.py`)
with no dependencies; also discoverable by pytest if installed."""

import importlib.util
import math
import os
import sys

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("station_gen",
                                               os.path.join(_here, "station_gen.py"))
sg = importlib.util.module_from_spec(_spec)
sys.modules["station_gen"] = sg  # so the dataclass can resolve its module
_spec.loader.exec_module(sg)


def _close(a, b, tol=1e-6):
    return abs(a - b) <= tol


# --- geometry helpers ----------------------------------------------------------
def test_cylinder_along_x_has_expected_aabb():
    # a cylinder (local axis Y) rotated to lie along X: AABB (h/2, r, r)
    r, h = 2.0, 10.0
    p = sg.Part("m", "cylinder", (r, h / 2, r), (0, 0, 0), "hull",
                sg.rot_axis("z", 90))
    wh = p.world_half()
    assert _close(wh[0], h / 2) and _close(wh[1], r) and _close(wh[2], r), wh


def test_radial_band_centered_vs_offset():
    centered = sg.Part("m", "box", (1, 1, 1), (0, 0, 0), "hull")
    rmn, rmx = sg.radial_band(centered)
    assert _close(rmn, 0.0), rmn                       # contains the axis
    assert _close(rmx, math.hypot(1, 1)), rmx          # far corner
    offset = sg.Part("m", "box", (1, 1, 1), (0, 5, 0), "hull")
    rmn2, rmx2 = sg.radial_band(offset)
    assert _close(rmn2, 4.0) and _close(rmx2, math.hypot(6, 1)), (rmn2, rmx2)


def test_aabb_overlap_detects_hit_and_miss():
    a = sg.Part("a", "box", (1, 1, 1), (0, 0, 0), "hull")
    hit = sg.Part("b", "box", (1, 1, 1), (1.5, 0, 0), "hull")
    miss = sg.Part("c", "box", (1, 1, 1), (5, 0, 0), "hull")
    assert sg.aabb_overlap(a, hit, 0.0)
    assert not sg.aabb_overlap(a, miss, 0.0)


# --- generation invariants -----------------------------------------------------
def test_every_archetype_and_size_has_no_interference():
    for arch in ("stack", "truss", "ring", "radial", "power", "dualkeel", "cylinder"):
        for iss in (0.5, 1, 3, 10, 20):
            for seed in (1, 2, 3):
                st = sg.generate_one(iss * sg.ISS_METERS, seed, arch, 1, 1, 1, 0.35)
                assert sg.validate(st) is True


def test_minimums_are_respected():
    st = sg.generate_one(3 * sg.ISS_METERS, 5, "stack",
                         min_panels=3, min_labs=2, min_habs=2, scale=0.35)
    assert st.counts["panels"] >= 2 * 3
    assert st.counts["labs"] >= 2
    assert st.counts["habs"] >= 2


def test_panels_are_paired_and_bounded():
    for seed in range(1, 8):
        st = sg.generate_one(2 * sg.ISS_METERS, seed, "truss", 1, 1, 1, 0.35)
        assert st.counts["panels"] % 2 == 0          # always mirrored pairs
        assert 2 <= st.counts["panels"] <= 16        # never zero, never a swarm
        assert st.counts["antennas"] >= 1            # comms present


def test_ring_annulus_clearance_holds():
    for seed in range(1, 12):
        st = sg.generate_one(10 * sg.ISS_METERS, seed, "ring", 1, 1, 1, 0.35)
        assert sg.validate(st) is True               # ring vs modules/arrays OK


# --- palette: output references ONLY the player-ship materials -----------------
def test_tscn_uses_only_ship_materials_no_raw_colours():
    st = sg.generate_one(2 * sg.ISS_METERS, 1, "truss", 1, 1, 1, 0.35)
    tscn = sg.to_tscn(st, 0.35)
    import re
    paths = re.findall(r'path="([^"]+)"', tscn)
    assert set(paths) == set(sg.MAT.values()), paths   # exactly the 5 ship mats
    assert "Color(" not in tscn                         # no hard-coded colours
    assert "albedo_color" not in tscn                   # colour comes from the .tres


def _run():
    tests = [v for k, v in sorted(globals().items())
             if k.startswith("test_") and callable(v)]
    passed = 0
    for t in tests:
        t()
        print(f"  ok  {t.__name__}")
        passed += 1
    print(f"{passed}/{len(tests)} tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(_run())
