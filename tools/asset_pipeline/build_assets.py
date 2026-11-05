"""Raw Layer output (assets/source) -> runtime assets (assets/processed).

    python3 tools/asset_pipeline/build_assets.py

* bowl_background_raw.png / bowl_background_<theme>_raw.png (864x1536) -> assets/processed/bg_<level>.jpg (1080x1920)
* object sheets (flat magenta, one item per grid cell, positional) -> assets/processed/levels/<level>/tier_1..9.png
  bathroom: objects_sheet_raw.png (3x2: duck, paper, shampoo, plunger, boot, golden toilet) + bathroom_extra_raw.png
            (3x1: scale, washing machine, bathtub); tier order = duck, paper, shampoo, plunger, boot, scale, washer, tub, golden toilet
  kitchen / palace: <level>_sheet_raw.png (3x3, tiers 1..9 left-to-right, top-to-bottom)
Afterwards run fit_shapes.py for the collision shapes of the generated objects."""
import os

import numpy as np
from PIL import Image
from scipy import ndimage

import bowl_geometry as G
from chroma import key_magenta, trim

SRC = os.path.join(G.ROOT, "assets", "source")
OUT = os.path.join(G.ROOT, "assets", "processed")
MAX_EDGE = 360

BACKGROUNDS = {"bathroom": "bowl_background_raw.png", "kitchen": "bowl_background_kitchen_raw.png",
               "palace": "bowl_background_palace_raw.png"}


def grid_cells(path, cols, rows):
    """Key a sheet and return one item per grid cell. Whole blobs are assigned to the cell holding their centre, so an
    item that reaches across a cell border stays intact and never leaks into its neighbour; specks are dropped."""
    sheet = np.asarray(key_magenta(Image.open(os.path.join(SRC, path))))
    h, w = sheet.shape[:2]
    mask = sheet[..., 3] > 20
    lab, n = ndimage.label(ndimage.binary_dilation(mask, iterations=4))
    sizes = ndimage.sum(mask, lab, range(1, n + 1))
    centres = ndimage.center_of_mass(mask, lab, range(1, n + 1))
    cells = {}
    for i in range(n):
        cy, cx = centres[i]
        key = (min(rows - 1, int(cy * rows / h)), min(cols - 1, int(cx * cols / w)))
        cells.setdefault(key, []).append(i + 1)
    out = []
    for r in range(rows):
        for c in range(cols):
            ids = cells.get((r, c), [])
            if not ids:
                out.append(None)
                continue
            biggest = max(sizes[i - 1] for i in ids)
            keep = np.isin(lab, [i for i in ids if sizes[i - 1] >= max(300, biggest * 0.04)]) & mask
            img = sheet.copy()
            img[~keep] = 0
            out.append(trim(Image.fromarray(img, "RGBA")))
    return out


def save(img, level, tier):
    s = min(1.0, MAX_EDGE / max(img.size))
    if s < 1.0:
        img = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
    d = os.path.join(OUT, "levels", level)
    os.makedirs(d, exist_ok=True)
    img.save(os.path.join(d, "tier_%d.png" % tier))
    print(level, tier, img.size)


def backgrounds():
    for level, raw in BACKGROUNDS.items():
        p = os.path.join(SRC, raw)
        if os.path.exists(p):
            img = Image.open(p).convert("RGB").resize((1080, 1920), Image.LANCZOS)
            img.save(os.path.join(OUT, "bg_%s.jpg" % level), quality=88)


def objects():
    first = grid_cells("objects_sheet_raw.png", 3, 2)
    extra = grid_cells("bathroom_extra_raw.png", 3, 1)
    for t, img in enumerate(first[:5] + extra + [first[5]]):
        save(img, "bathroom", t + 1)
    for level in ("kitchen", "palace"):
        for t, img in enumerate(grid_cells("%s_sheet_raw.png" % level, 3, 3)):
            save(img, level, t + 1)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    backgrounds()
    objects()
