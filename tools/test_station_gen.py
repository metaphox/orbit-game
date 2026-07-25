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


def _validation_message(st):
    try:
        sg.validate(st)
    except sg.ValidationError as error:
        return str(error)
    raise AssertionError("station unexpectedly validated")


# --- geometry helpers ----------------------------------------------------------
def test_cylinder_along_x_has_expected_aabb():
    # a cylinder (local axis Y) rotated to lie along X: AABB (h/2, r, r)
    r, h = 2.0, 10.0
    p = sg.Part("m", "cylinder", (r, h / 2, r), (0, 0, 0), "hull",
                sg.rot_axis("z", 90))
    wh = p.world_half()
    assert _close(wh[0], h / 2) and _close(wh[1], r) and _close(wh[2], r), wh


def test_tscn_transform_transposes_part_axes_into_godot_rows():
    part = sg.Part("m", "box", (1, 1, 1), (10, 20, 30), "hull",
                   ((1, 2, 3), (4, 5, 6), (7, 8, 9)))
    assert sg.godot_transform_values(part, 0.5) == (
        1, 4, 7, 2, 5, 8, 3, 6, 9, 5.0, 10.0, 15.0)


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
    for arch in ("stack", "truss", "ring", "radial", "power", "dualkeel", "cylinder",
                 "hybrid"):
        for iss in (0.5, 1, 3, 10, 20):
            for seed in (1, 2, 3):
                st = sg.generate_one(iss * sg.ISS_METERS, seed, arch, 1, 1, 1, 0.35)
                assert sg.validate(st) is True
                graph = sg.assembly_graph(
                    st, {"structural", "pressurized", "articulated", "docked"})
                reachable = sg.graph_distances(graph, st.root_assembly)
                assert all(assembly.decorative or assembly.id in reachable
                           for assembly in st.assemblies.values())


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
        assert 1 <= st.counts["antennas"] <= 4       # comms present, never a swarm


def test_solar_families_fold_and_track_as_mirrored_pairs():
    seen = set()
    for seed in range(1, 80):
        st = sg.generate_one(2 * sg.ISS_METERS, seed, "truss", 1, 1, 1, 0.35)
        seen.add(st.solar_family)
        pairs = {}
        for assembly in st.assemblies.values():
            if assembly.role != "solar_wing":
                continue
            data = assembly.metadata
            assert data["hinge_connected"]
            assert data["hinge_count"] >= max(1, data["leaf_count"] - 2)
            assert sg.vdot(sg.vunit(data["normal"]), sg.vunit(st.sun_vector)) \
                >= math.cos(math.radians(15))
            pairs.setdefault(data["pair"], []).append(data)
        assert all(len(wings) == 2 for wings in pairs.values())
        assert all(wings[0]["leaf_count"] == wings[1]["leaf_count"]
                   and _close(wings[0]["collecting_area"],
                              wings[1]["collecting_area"])
                   for wings in pairs.values())
        if len(seen) == 4:
            break
    assert seen == {"accordion_rect", "petal_fan", "round_umbrella", "honeycomb"}


def test_solar_validator_rejects_a_leaf_outside_the_hinge_tree():
    st = sg.generate_one(2 * sg.ISS_METERS, 6, "truss", 1, 1, 1, 0.35)
    wing = next(assembly for assembly in st.assemblies.values()
                if assembly.role == "solar_wing")
    wing.metadata["hinge_edges"] = []
    assert "leaf outside its hinge tree" in _validation_message(st)


def test_deployed_surfaces_stay_foil_thin_at_showcase_scale():
    for iss in (0.5, 1, 20):
        st = sg.generate_one(iss * sg.ISS_METERS, 3, "truss", 1, 1, 1, 0.35)
        panels = [p for p in st.parts if p.kind == "panel"]
        radiator_fins = [p for p in st.parts if p.kind == "radiator"]
        assert panels and radiator_fins
        assert max(p.half[1] for p in panels) <= 0.35
        assert max(p.half[0] for p in radiator_fins) <= 0.12
        assert all(p.half[1] / max(p.half[0], p.half[2]) < 0.012 for p in panels)


def test_radiators_follow_thermal_budget_and_reference_proportions():
    for arch, expected_profile in (("stack", "ordinary"),
                                   ("truss", "ordinary"),
                                   ("power", "high_power")):
        st = sg.generate_one(3 * sg.ISS_METERS, 9, arch, 1, 1, 1, 0.35)
        thermal = st.thermal
        assert thermal["profile"] == expected_profile
        assert _close(thermal["solar_area_m2"], sg.solar_collecting_area(st))
        assert _close(thermal["target_radiator_area_m2"],
                      sg.radiator_face_area(st))
        assert (thermal["minimum_area_ratio"] <= thermal["area_ratio"]
                <= thermal["maximum_area_ratio"])
        banks = [assembly for assembly in st.assemblies.values()
                 if assembly.role == "radiator_bank"]
        assert len(banks) == thermal["bank_count"]
        for bank in banks:
            data = bank.metadata
            assert 6 <= data["panel_count"] <= 8
            assert data["hinge_count"] == data["panel_count"] - 1
            assert 5.0 <= data["panel_aspect_ratio"] <= 7.0
            assert data["panel_layer_count"] == 1
            assert len(data["panel_part_indices"]) == data["panel_count"]
        blueprint = sg.to_json(st, 0.35)
        assert blueprint["thermal"] == thermal
        assert 'metadata/thermal_profile = ' in sg.to_tscn(st, 0.35)


def test_radiator_validator_rejects_duplicate_panel_layers():
    st = sg.generate_one(sg.ISS_METERS, 10, "stack", 1, 1, 1, 0.35)
    bank = next(assembly for assembly in st.assemblies.values()
                if assembly.role == "radiator_bank")
    bank.metadata["panel_layer_count"] = 2
    try:
        sg.validate_radiators(st)
    except sg.ValidationError as error:
        assert "duplicate radiator layers" in str(error)
    else:
        raise AssertionError("duplicate radiator layers unexpectedly validated")


def test_hybrid_recipes_compose_multiple_proven_forms():
    expected = {
        ("dualkeel", "ring", "dome"),
        ("truss", "ring", "radial"),
        ("power", "ring", "tank_farm"),
    }
    seen = set()
    for seed in range(1, 40):
        st = sg.generate_one(5 * sg.ISS_METERS, seed, "hybrid", 1, 1, 1, 0.35)
        seen.add(tuple(st.forms))
        assert st.counts["rings"] >= 1
        assert len(st.forms) == 3
    assert seen == expected


def test_dual_keel_observatory_has_a_pressure_trunk_to_a_module():
    station = sg.generate_one(6 * sg.ISS_METERS, 14, "hybrid", 1, 1, 1, 0.35)
    assert station.forms[0] == "dualkeel"
    observatories = [assembly for assembly in station.assemblies.values()
                     if assembly.role == "observatory"]
    assert len(observatories) == 1
    observatory = observatories[0]
    assert observatory.metadata["pressure_trunk"]
    assert any(part.kind == "pressure_trunk"
               for part in (station.parts[index]
                            for index in observatory.part_indices))
    assert any(joint.kind == "pressurized"
               and sg.joint_owners(station, joint)[1] == observatory.id
               for joint in station.joints)


def test_each_station_gets_two_signature_detail_families():
    signatures = {"tank", "dome", "arm_segment", "tug_hull"}
    for arch in ("stack", "truss", "ring", "radial", "power", "dualkeel", "cylinder"):
        st = sg.generate_one(5 * sg.ISS_METERS, 4, arch, 1, 1, 1, 0.35)
        kinds = {p.kind for p in st.parts}
        assert len(kinds & signatures) >= 2, (arch, kinds & signatures)


def test_ring_annulus_clearance_holds():
    for seed in range(1, 12):
        st = sg.generate_one(10 * sg.ISS_METERS, seed, "ring", 1, 1, 1, 0.35)
        assert sg.validate(st) is True               # ring vs modules/arrays OK


def test_labs_and_habitats_own_plausible_surface_details():
    st = sg.generate_one(5 * sg.ISS_METERS, 7, "radial", 1, 2, 2, 0.35)
    for module_id in st.module_assemblies:
        module = st.assemblies[module_id]
        role = module.metadata["module_role"]
        if role not in ("lab", "hab"):
            continue
        details = [assembly for assembly in st.assemblies.values()
                   if assembly.metadata.get("module") == module_id]
        assert len(details) == 1
        parts = [st.parts[index] for index in details[0].part_indices]
        windows = [part for part in parts if part.kind == "window"]
        assert (1 <= len(windows) <= 4) if role == "lab" else (2 <= len(windows) <= 6)
        assert sum(part.kind == "module_light" for part in parts) <= 1


def test_connectivity_validator_rejects_disconnected_assembly():
    st = sg.generate_one(sg.ISS_METERS, 11, "stack", 1, 1, 1, 0.35)
    orphan = st.new_assembly("orphan_lab", crewed=True)
    st.add(sg.Part("lab", "box", (1, 1, 1), (999, 0, 0), sg.MAT["hull"]), orphan)
    assert "disconnected assemblies" in _validation_message(st)


def test_connectivity_validator_rejects_declared_joint_with_gap():
    st = sg.generate_one(sg.ISS_METERS, 12, "stack", 1, 1, 1, 0.35)
    joint = next(joint for joint in st.joints
                 if sg.vlength(sg.vsub(st.mounts[joint.parent_mount].pos,
                                      st.mounts[joint.child_mount].pos)) > 1.0)
    joint.connector_parts = []
    assert "physical gap" in _validation_message(st)


def test_connectivity_validator_rejects_blocked_docking_approach():
    st = sg.generate_one(sg.ISS_METERS, 21, "stack", 1, 1, 1, 0.35)
    occupied = {sg.joint_owners(st, joint)[0] for joint in st.joints
                if joint.kind == "docked"}
    port = next(part for part in st.parts
                if part.kind == "port" and part.assembly not in occupied)
    direction = sg.vunit(port.extra["approach_direction"])
    obstruction_pos = sg.vadd(
        port.pos, sg.vscale(direction, port.half[1] + port.half[0] * 2.0))
    third = next(assembly_id for assembly_id in st.assemblies
                 if assembly_id != port.assembly)
    st.add(sg.Part("approach_block", "box", (0.1, 0.1, 0.1),
                       obstruction_pos, sg.MAT["hull"]), third)
    assert "docking approach" in _validation_message(st)


def test_connectivity_validator_rejects_connector_crossing_third_assembly():
    st = sg.generate_one(sg.ISS_METERS, 13, "stack", 1, 1, 1, 0.35)
    joint = next(joint for joint in st.joints
                 if joint.connector_parts and joint.kind == "articulated")
    parent, child = sg.joint_owners(st, joint)
    third = next(assembly_id for assembly_id, assembly in st.assemblies.items()
                 if assembly_id not in (parent, child) and not assembly.decorative)
    connector = st.parts[joint.connector_parts[0]]
    st.add(sg.Part("intruder", "box", (0.08, 0.08, 0.08), connector.pos,
                       sg.MAT["hull"]), third)
    assert "connector crosses" in _validation_message(st)


def test_organization_report_is_deterministic_bounded_and_serialized():
    first = sg.generate_one(5 * sg.ISS_METERS, 17, "hybrid", 1, 1, 1, 0.35)
    second = sg.generate_one(5 * sg.ISS_METERS, 17, "hybrid", 1, 1, 1, 0.35)
    assert first.organization == second.organization
    assert 0.0 <= first.organization.score <= 100.0
    assert all(0.0 <= value <= 1.0
               for value in first.organization.components.values())
    blueprint = sg.to_json(first, 0.35)
    assert blueprint["organization"]["mode"] == "report_only"
    assert blueprint["organization"]["score"] == first.organization.score
    assert blueprint["organization_score"] == first.organization.score
    assert blueprint["requested_seed"] == 17
    assert blueprint["resolved_seed"] == first.seed


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
