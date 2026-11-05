"""Raw Layer output (assets/source) -> runtime assets (assets/processed).

    python3 tools/asset_pipeline/build_assets.py

* bowl_background_raw.png (864x1536) -> assets/processed/background.jpg (1080x1920)
* objects_sheet_raw.png (3x2 grid, magenta) -> assets/processed/objects/tier_1..6.png (keyed, trimmed)
Sheet layout is positional: top row = tiers 1-3, bottom row = tiers 4-6, left to right."""
import os

from PIL import Image

import bowl_geometry as G
from chroma import components, key_magenta, trim

SRC = os.path.join(G.ROOT, "assets", "source")
OUT = os.path.join(G.ROOT, "assets", "processed")
MAX_EDGE = 360


def background():
    img = Image.open(os.path.join(SRC, "bowl_background_raw.png")).convert("RGB").resize((1080, 1920), Image.LANCZOS)
    img.save(os.path.join(OUT, "background.jpg"), quality=88)


def objects():
    sheet = key_magenta(Image.open(os.path.join(SRC, "objects_sheet_raw.png")))
    parts = components(sheet, dilate=8, min_area=4000)
    parts.sort(key=lambda p: p[0][1])
    rows = [sorted(parts[:3], key=lambda p: p[0][0]), sorted(parts[3:6], key=lambda p: p[0][0])]
    assert len(parts) == 6, "expected 6 objects, found %d" % len(parts)
    os.makedirs(os.path.join(OUT, "objects"), exist_ok=True)
    for i, (bbox, crop) in enumerate(rows[0] + rows[1]):
        img = trim(crop)
        s = min(1.0, MAX_EDGE / max(img.size))
        if s < 1.0:
            img = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
        path = os.path.join(OUT, "objects", "tier_%d.png" % (i + 1))
        img.save(path)
        print("tier_%d" % (i + 1), img.size, "aspect %.3f" % (img.width / img.height))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    background()
    objects()
