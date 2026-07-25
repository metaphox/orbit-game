#!/usr/bin/env python3
"""Orthographic PNG previews of a generated Station — pure Python + Pillow, so it
needs no Godot and opens no window (headless Godot renders black). Three panels:
SIDE (X-Y), TOP (X-Z), and END (Y-Z, which exposes rings/radial clusters).
Painter's algorithm, coloured by material.

Used via `station_gen.py --preview`; also runnable to preview a fresh build:
    python3 tools/station_preview.py --iss 5 --seed 2 --out /tmp/s.png
"""

from PIL import Image, ImageDraw

import importlib.util
import os
import sys

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "station_gen", os.path.join(_here, "station_gen.py"))
sg = importlib.util.module_from_spec(_spec)
sys.modules["station_gen"] = sg
_spec.loader.exec_module(sg)

BG = (11, 14, 20)


def _corners(p):
    out = []
    if p.mesh == "polygon":
        sides = p.extra.get("sides", 6)
        for sy in (-1, 1):
            for index in range(sides):
                angle = 2.0 * sg.math.pi * index / sides + sg.math.pi / 2.0
                loc = (sg.math.cos(angle) * p.half[0], sy * p.half[1],
                       sg.math.sin(angle) * p.half[2])
                out.append(tuple(
                    p.pos[i] + sum(loc[j] * p.cols[j][i] for j in range(3))
                    for i in range(3)))
        return out
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                loc = (sx * p.half[0], sy * p.half[1], sz * p.half[2])
                out.append(tuple(
                    p.pos[i] + sum(loc[j] * p.cols[j][i] for j in range(3))
                    for i in range(3)))
    return out


def _hull(pts):
    """Andrew's monotone-chain convex hull of 2D points."""
    pts = sorted(set(pts))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower = []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper = []
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def _shade(color, f):
    return tuple(max(0, min(255, int(c * f))) for c in color)


def _draw_view(draw, parts, colors, hori, vert, depth, flip_v,
               ox, oy, sc, hmin, vmax):
    def to_px(c):
        return (ox + (c[hori] - hmin) * sc,
                oy + ((vmax - c[vert]) if flip_v else (c[vert] - vmax + 0)) * sc)
    for p in sorted(parts, key=lambda q: q.pos[depth]):
        col = colors.get(p.mat, (150, 150, 150))
        cs = _corners(p)
        if p.mesh == "torus" and depth == 0:
            cx = ox + (p.pos[hori] - hmin) * sc
            cy = oy + (vmax - p.pos[vert]) * sc
            wh = p.world_half()
            rx = wh[hori] * sc
            ry = wh[vert] * sc
            stroke = max(2, int((p.extra["outer"] - p.extra["inner"]) * sc))
            draw.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], outline=col,
                         width=stroke)
            continue
        if p.mesh == "sphere":
            cx = ox + (p.pos[hori] - hmin) * sc
            cy = oy + (vmax - p.pos[vert]) * sc
            r = max(1.5, p.half[0] * sc)
            draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col,
                         outline=_shade(col, 0.6))
            continue
        poly = _hull([to_px(c) for c in cs])
        if len(poly) >= 3:
            draw.polygon(poly, fill=col, outline=_shade(col, 0.55))


def render(st, path, px=1100):
    parts = st.parts
    colors = st.brand["preview_colors"]
    allc = [c for p in parts for c in _corners(p)]
    xs = [c[0] for c in allc]
    ys = [c[1] for c in allc]
    zs = [c[2] for c in allc]
    minx, maxx = min(xs), max(xs)
    miny, maxy = min(ys), max(ys)
    minz, maxz = min(zs), max(zs)
    pad = int(px * 0.05)
    sc = (px - 2 * pad) / max(maxx - minx, 1e-6)
    h_side = int((maxy - miny) * sc) + 2 * pad
    h_top = int((maxz - minz) * sc) + 2 * pad
    end_span = max(maxy - miny, maxz - minz, 1e-6)
    sc_end = (px - 2 * pad) / end_span
    h_end = int((maxz - minz) * sc_end) + 2 * pad
    lab = 26
    H = lab + h_side + lab + h_top + lab + h_end + pad
    img = Image.new("RGB", (px, H), BG)
    d = ImageDraw.Draw(img)
    ox = pad + (px - 2 * pad - (maxx - minx) * sc) / 2
    form_label = "+".join(st.forms).upper()
    organization = st.organization or sg.analyze_organization(st)
    d.text((pad, 6), "SIDE  (X-Y)  %s  %s  %.1fx ISS  %d parts  %s  ORG %.1f"
           % (form_label, st.brand_key.upper(), st.meters / sg.ISS_METERS,
              len(parts), st.solar_family.upper(), organization.score),
           fill=(150, 160, 170))
    _draw_view(d, parts, colors, 0, 1, 2, True,
               ox, lab + pad, sc, minx, maxy)
    y2 = lab + h_side
    d.text((pad, y2 + 4), "TOP  (X-Z)  — solar-array faces", fill=(150, 160, 170))
    _draw_view(d, parts, colors, 0, 2, 1, True,
               ox, y2 + lab + pad, sc, minx, maxz)
    y3 = y2 + lab + h_top
    d.text((pad, y3 + 4), "END  (Y-Z)  — ring / radial cross-section",
           fill=(150, 160, 170))
    ox_end = pad + (px - 2 * pad - (maxy - miny) * sc_end) / 2
    _draw_view(d, parts, colors, 1, 2, 0, True,
               ox_end, y3 + lab + pad, sc_end, miny, maxz)
    img.save(path)
    return path


def _main():
    ap = sg.argparse.ArgumentParser()
    ap.add_argument("--iss", type=float, default=1.0)
    ap.add_argument("--archetype", default="auto")
    ap.add_argument("--brand", default="auto", choices=["auto", *sg.BRAND_KEYS])
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", default="/tmp/station.png")
    a = ap.parse_args()
    st = sg.generate_one(a.iss * sg.ISS_METERS, a.seed, a.archetype,
                         1, 1, 1, 0.35, brand=a.brand)
    print(render(st, a.out))
    return 0


if __name__ == "__main__":
    sys.exit(_main())
