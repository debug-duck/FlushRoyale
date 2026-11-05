"""Render the flat layout guide that Layer repaints into the toilet background.

    python3 tools/asset_pipeline/make_bowl_guide.py [--overlay path/to/background.png]

Writes assets/source/guide/bowl_guide.png (864x1536 = 0.8 x design size). With --overlay it instead draws the
collision outline in red over a finished background, to check that art and physics agree."""
import math
import os
import sys

from PIL import Image, ImageDraw

import bowl_geometry as G

S = 0.8
W, H = 864, 1536
OUT = os.path.join(G.ROOT, "assets", "source", "guide")


def sc(pts):
    return [(x * S, y * S) for x, y in pts]


def guide():
    b = G.load()
    cx = b["center_x"]
    inner = G.inner_left(b)
    throat = inner[-1]
    floor = b["floor_y"]
    img = Image.new("RGB", (W, H), (190, 228, 218))
    d = ImageDraw.Draw(img)
    # wall tiles + floor
    tile = 120 * S
    for i in range(0, 20):
        d.line([(0, i * tile), (W, i * tile)], fill=(170, 210, 200), width=3)
        d.line([(i * tile, 0), (i * tile, H)], fill=(170, 210, 200), width=3)
    d.rectangle([0, floor * S, W, H], fill=(214, 168, 118))
    d.line([(0, floor * S), (W, floor * S)], fill=(60, 45, 40), width=6)
    # left porcelain wall: rim slope -> inner wall -> outlet -> pedestal -> outer wall
    outer = []
    for i, (x, y) in enumerate(inner):
        a = inner[max(i - 1, 0)]
        c = inner[min(i + 1, len(inner) - 1)]
        tx, ty = c[0] - a[0], c[1] - a[1]
        ln = math.hypot(tx, ty) or 1.0
        outer.append((x - ty / ln * b["wall_thickness"], y + tx / ln * b["wall_thickness"]))
    outer = [p for p in outer if p[1] < 1400 and p[0] > 0]
    ped = b["pedestal"]
    left = [(0, b["rim_slope_top_y"])] + inner + [(throat[0], floor)] + [tuple(ped[2]), tuple(ped[1]), tuple(ped[0])] \
        + list(reversed(outer)) + [(0, outer[0][1])]
    right = G.mirror(left, cx)
    porcelain, outline = (250, 250, 252), (40, 44, 58)
    # pedestal body behind the walls
    d.polygon(sc([tuple(p) for p in ped]), fill=porcelain, outline=outline, width=6)
    for poly in (left, right):
        d.polygon(sc(poly), fill=porcelain, outline=outline, width=6)
    # bowl interior (back wall of the cut-away bowl) and the outlet channel
    hollow = inner + list(reversed(G.mirror(inner, cx)))
    d.polygon(sc(hollow), fill=(206, 222, 236))
    d.line(sc(inner), fill=outline, width=6)
    d.line(sc(G.mirror(inner, cx)), fill=outline, width=6)
    d.rectangle([throat[0] * S, throat[1] * S, (2 * cx - throat[0]) * S, floor * S], fill=(120, 140, 160))
    d.line([(throat[0] * S, throat[1] * S), (throat[0] * S, floor * S)], fill=outline, width=6)
    d.line([((2 * cx - throat[0]) * S, throat[1] * S), ((2 * cx - throat[0]) * S, floor * S)], fill=outline, width=6)
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, "bowl_guide.png"))
    print("wrote", os.path.join(OUT, "bowl_guide.png"))


def overlay(path):
    b = G.load()
    img = Image.open(path).convert("RGB").resize((1080, 1920))
    d = ImageDraw.Draw(img)
    inner = G.inner_left(b)
    for side in (inner, G.mirror(inner, b["center_x"])):
        d.line(side, fill=(255, 0, 0), width=3)
    d.line([(b["center_x"] - b["drain_width"] / 2, b["throat_y"]), (b["center_x"] - b["drain_width"] / 2, b["floor_y"])], fill=(255, 0, 0), width=3)
    d.line([(b["center_x"] + b["drain_width"] / 2, b["throat_y"]), (b["center_x"] + b["drain_width"] / 2, b["floor_y"])], fill=(255, 0, 0), width=3)
    d.line([(0, b["rim_slope_top_y"]), inner[0]], fill=(255, 0, 0), width=3)
    d.line([(0, b["overflow_y"]), (1080, b["overflow_y"])], fill=(255, 120, 0), width=2)
    out = os.path.splitext(path)[0] + "_overlay.png"
    img.save(out)
    print("wrote", out)


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--overlay":
        overlay(sys.argv[2])
    else:
        guide()
