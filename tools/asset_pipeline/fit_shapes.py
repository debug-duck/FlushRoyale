"""Collision shapes for generated objects -> data/shapes_generated.json.

    python3 tools/asset_pipeline/fit_shapes.py

For every assets/processed/levels/<level>/tier_N.png that has no hand-authored shapes in data/levels.json, the alpha
mask is split into at most 4 convex parts (recursive best cut along x or y while a part's convex hull wastes too much
area) and each part's hull is simplified to <= 8 points. Units = sprite pixels around the sprite centre (the game
scales shapes and sprite together to the tier's target area). The result is plain data: hand-edit freely, or move a
tier to authored shapes in levels.json. Also writes a preview sheet to assets/source/shapes_preview.png."""
import json
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy.spatial import ConvexHull

import bowl_geometry as G

LEVELS = os.path.join(G.ROOT, "assets", "processed", "levels")
OUT = os.path.join(G.ROOT, "data", "shapes_generated.json")
WASTE = 1.28          # hull area / mask area above this -> split
MAX_PARTS = 4
MAX_POINTS = 8


def hull_of(pts):
    if len(pts) < 3:
        return None, 0.0
    try:
        h = ConvexHull(pts)
    except Exception:
        return None, 0.0
    return pts[h.vertices], h.volume


def simplify(poly, n):
    """Drop the vertex whose removal loses the least area until n remain (keeps it convex)."""
    poly = [tuple(p) for p in poly]
    while len(poly) > n:
        best, best_a = 0, 1e18
        for i in range(len(poly)):
            a, b, c = poly[i - 1], poly[i], poly[(i + 1) % len(poly)]
            area = abs((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])) * 0.5
            if area < best_a:
                best, best_a = i, area
        poly.pop(best)
    return poly


def decompose(pts, depth=0):
    poly, harea = hull_of(pts)
    if poly is None:
        return []
    if depth >= 2 or harea <= WASTE * len(pts) or len(pts) < 200:
        return [poly]
    best = None
    for axis in (0, 1):
        lo, hi = pts[:, axis].min(), pts[:, axis].max()
        for f in np.linspace(0.15, 0.85, 15):
            cut = lo + (hi - lo) * f
            a, b = pts[pts[:, axis] < cut], pts[pts[:, axis] >= cut]
            if len(a) < 50 or len(b) < 50:
                continue
            ha, hb = hull_of(a)[1], hull_of(b)[1]
            if best is None or ha + hb < best[0]:
                best = (ha + hb, a, b)
    if best is None or best[0] > harea * 0.9:
        return [poly]
    return decompose(best[1], depth + 1) + decompose(best[2], depth + 1)


def fit(path):
    img = Image.open(path)
    a = np.asarray(img)[..., 3] > 100
    ys, xs = np.nonzero(a)
    step = max(1, int(np.sqrt(len(xs) / 6000)))       # subsample big masks
    pts = np.stack([xs[::step], ys[::step]], axis=1).astype(float) + 0.5
    parts = decompose(pts)[:MAX_PARTS]
    c = np.array([img.width / 2.0, img.height / 2.0])
    shapes = []
    for p in parts:
        q = simplify(p - c, MAX_POINTS)
        shapes.append({"type": "poly", "points": [[round(x, 1), round(y, 1)] for x, y in q]})
    return {"size": [img.width, img.height], "shapes": shapes}


def main():
    with open(os.path.join(G.ROOT, "data", "levels.json")) as f:
        data = json.load(f)
        levels = data["levels"] + data.get("bonus_levels", [])
    out = {}
    previews = []
    for lv in levels:
        for t, d in enumerate(lv["tiers"]):
            if "shapes" in d:
                continue
            key = d["sprite"]
            res = fit(os.path.join(G.ROOT, "assets", "processed", key))
            out[key] = res
            previews.append((key, res))
            print(key, len(res["shapes"]), "parts")
    with open(OUT, "w") as f:
        json.dump(out, f, indent=1)
    # preview sheet: sprite + red outlines
    cols = 6
    cell = 220
    rows = (len(previews) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (40, 50, 70, 255))
    for i, (key, res) in enumerate(previews):
        img = Image.open(os.path.join(G.ROOT, "assets", "processed", key))
        s = (cell - 20) / max(img.size)
        im = img.resize((int(img.width * s), int(img.height * s)))
        ox, oy = (i % cols) * cell + (cell - im.width) // 2, (i // cols) * cell + (cell - im.height) // 2
        sheet.alpha_composite(im, (ox, oy))
        d = ImageDraw.Draw(sheet)
        cx, cy = ox + im.width / 2, oy + im.height / 2
        for sh in res["shapes"]:
            pts = [(cx + x * s, cy + y * s) for x, y in sh["points"]]
            d.polygon(pts, outline=(255, 40, 40, 255), width=2)
    sheet.save(os.path.join(G.ROOT, "assets", "source", "shapes_preview.png"))


if __name__ == "__main__":
    main()
