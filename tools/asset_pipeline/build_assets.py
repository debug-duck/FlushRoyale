"""Raw Layer output (assets/source) -> runtime assets (assets/processed).

    python3 tools/asset_pipeline/build_assets.py

* bowl_background_raw.png / bowl_background_<theme>_raw.png (864x1536) -> assets/processed/bg_<level>.jpg (1080x1920)
* object sheets (flat magenta, one item per grid cell, positional) -> assets/processed/levels/<level>/tier_1..9.png
  bathroom: objects_sheet_raw.png (3x2: duck, paper, shampoo, plunger, boot, golden toilet) + bathroom_extra_raw.png
            (3x1: scale, washing machine, bathtub); tier order = duck, paper, shampoo, plunger, boot, scale, washer, tub, golden toilet
  kitchen / palace / dorm / whitehouse / royal: <level>_sheet_raw.png (3x3, tiers 1..9 left-to-right, top-to-bottom)
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
               "palace": "bowl_background_palace_raw.png", "dorm": "bowl_background_dorm_raw.png",
               "whitehouse": "bowl_background_whitehouse_raw.png", "royal": "bowl_background_royal_raw.png",
               "area51": "bowl_background_area51_raw.png", "vatican": "bowl_background_vatican_raw.png",
               "hollywood": "bowl_background_hollywood_raw.png", "earth": "bowl_background_earth_raw.png"}


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


SPLASH_BLUE = (30, 100, 210)       # brand blue: boot splash canvas, project boot_splash/bg_color + clear colour
CARVE = {"royal", "area51", "vatican", "hollywood", "earth"}      # backgrounds whose painted bowl walls bulge into the physics interior (see carve())


def carve(img):
    """Make the painted bowl interior match the collision exactly: pixels inside the collision interior (above the throat)
    that are not porcelain are repainted with the nearest porcelain colour of the same row, and the wall outline is
    redrawn on the collision line where anything was repainted."""
    from PIL import ImageDraw
    b = G.load()
    inner = G.inner_left(b)
    poly = inner + list(reversed(G.mirror(inner, b["center_x"])))
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).polygon(poly, fill=255)
    inside = np.asarray(m) > 0
    a = np.asarray(img).astype(np.int16)
    mx, mn = a.max(axis=2), a.min(axis=2)
    porcelain = (mn > 150) & (mx - mn < 70) & (a[..., 2] >= a[..., 0] - 4)   # light, bluish-white (gold is warm)
    fix = inside & ~porcelain
    fix[: int(b["rim_y"]) + 60] = False                     # the rim lip stays as painted
    fix[int(b["throat_y"]) - 14:] = False                   # the drain mouth stays as painted
    out = a.copy()
    cx = int(b["center_x"])
    for y in np.nonzero(fix.any(axis=1))[0]:
        row = porcelain[y]
        for x in np.nonzero(fix[y])[0]:
            step = 1 if x < cx else -1                      # walk toward the centre to the first porcelain pixel
            xx = x
            while 0 <= xx < img.width and not row[xx] and abs(xx - x) < 200:
                xx += step
            if 0 <= xx < img.width and row[xx]:
                out[y, x] = (a[y, xx] * 0.94).astype(np.int16)
    res = Image.fromarray(out.clip(0, 255).astype(np.uint8))
    from PIL import ImageFilter                              # soften the row-by-row fill (only where we painted)
    soft = res.filter(ImageFilter.GaussianBlur(4))
    res = Image.composite(soft, res, Image.fromarray((fix * 255).astype(np.uint8)))
    rows = np.nonzero(fix.any(axis=1))[0]
    if len(rows):
        y0, y1 = rows.min() - 10, rows.max() + 10
        d = ImageDraw.Draw(res)
        for side in (inner, G.mirror(inner, b["center_x"])):
            seg = [p for p in side if y0 <= p[1] <= y1]
            if len(seg) > 1:
                d.line(seg, fill=(28, 26, 40), width=7, joint="curve")
    print("carved %d px" % int(fix.sum()))
    return res


def backgrounds():
    for level, raw in BACKGROUNDS.items():
        p = os.path.join(SRC, raw)
        if os.path.exists(p):
            img = Image.open(p).convert("RGB").resize((1080, 1920), Image.LANCZOS)
            if level in CARVE:
                img = carve(img)
            img.save(os.path.join(OUT, "bg_%s.jpg" % level), quality=88)


def objects():
    first = grid_cells("objects_sheet_raw.png", 3, 2)
    extra = grid_cells("bathroom_extra_raw.png", 3, 1)
    for t, img in enumerate(first[:5] + extra + [first[5]]):
        save(img, "bathroom", t + 1)
    for level in ("kitchen", "palace", "dorm", "whitehouse", "royal", "area51", "vatican", "hollywood", "earth"):
        if not os.path.exists(os.path.join(SRC, "%s_sheet_raw.png" % level)):
            continue
        for t, img in enumerate(grid_cells("%s_sheet_raw.png" % level, 3, 3)):
            save(img, level, t + 1)


def thumbs(d):
    """Level-select card previews: the top of each room (y 20..450 of the 1080x1920 background), 640 wide."""
    for level in BACKGROUNDS:
        p = os.path.join(OUT, "bg_%s.jpg" % level)
        if os.path.exists(p):
            img = Image.open(p).convert("RGB").crop((0, 20, 1080, 450)).resize((640, 255), Image.LANCZOS)
            img.save(os.path.join(d, "thumb_%s.jpg" % level), quality=85)


def ui():
    """Game logo (keyed), title key art, and the boot splash: the studio logo centred by its visible content on a portrait
    1080x1920 canvas (Godot shows it with boot_splash/fullsize=true: scaled to fit, never cut, on any screen)."""
    d = os.path.join(OUT, "ui")
    os.makedirs(d, exist_ok=True)
    logo = os.path.join(SRC, "game_logo_raw.png")
    if os.path.exists(logo):
        img = trim(key_magenta(Image.open(logo)), pad=6)
        img.save(os.path.join(d, "game_logo.png"))
        print("game_logo", img.size)
    bg = os.path.join(SRC, "title_bg_raw.png")
    if os.path.exists(bg):
        Image.open(bg).convert("RGB").resize((1080, 1920), Image.LANCZOS).save(os.path.join(d, "title_bg.jpg"), quality=88)
    tall = os.path.join(SRC, "title_bg_tall_raw.png")     # 1.0.1: the same art outpainted to 9:21 (tall phones)
    if os.path.exists(tall):                              # 1080x2560: the original 1080x1920 sits at y 320..2240
        Image.open(tall).convert("RGB").resize((1080, 2560), Image.LANCZOS).save(os.path.join(d, "title_bg_tall.jpg"), quality=88)
    icons = os.path.join(SRC, "ui_icons_raw.png")         # 2x2: padlock, done badge, plunger, crown
    if os.path.exists(icons):
        for name, img in zip(("icon_lock", "icon_done", "icon_plunger", "icon_crown"), grid_cells("ui_icons_raw.png", 2, 2)):
            img = trim(img, pad=2)
            if max(img.size) > 256:
                k = 256 / max(img.size)
                img = img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)
            img.save(os.path.join(d, name + ".png"))
            print(name, img.size)
    hands = os.path.join(SRC, "hand_sheet_raw.png")     # TOILET SHAKE hand: left half open, right half gripping
    if os.path.exists(hands):
        sheet = key_magenta(Image.open(hands))
        w2 = sheet.width // 2
        for name, box in (("hand_open", (0, 0, w2, sheet.height)), ("hand_grip", (w2, 0, sheet.width, sheet.height))):
            img = trim(sheet.crop(box), pad=2)
            img.save(os.path.join(d, name + ".png"))
            print(name, img.size)
    thumbs(d)
    studio = os.path.join(G.ROOT, "Studio_Logo.png")
    if os.path.exists(studio):
        art = Image.open(studio).convert("RGBA")
        art = art.crop(art.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox())
        w = 860
        art = art.resize((w, round(art.height * w / art.width)), Image.LANCZOS)
        canvas = Image.new("RGBA", (1080, 1920), SPLASH_BLUE + (255,))   # 1.0.1: blue, = project boot_splash/bg_color
        canvas.alpha_composite(art, ((1080 - art.width) // 2, (1920 - art.height) // 2 - 60))
        canvas.convert("RGB").save(os.path.join(d, "splash_wrong_button.png"))
        print("splash", art.size, "on 1080x1920")


if __name__ == "__main__":
    import sys
    os.makedirs(OUT, exist_ok=True)
    if sys.argv[1:] == ["ui"]:          # only the UI images (fast, leaves the level art untouched)
        ui()
        sys.exit(0)
    if sys.argv[1:2] == ["levels"]:     # only these levels: build_assets.py levels area51 earth ...
        want = set(sys.argv[2:])
        BACKGROUNDS = {k: v for k, v in BACKGROUNDS.items() if k in want}
        backgrounds()
        for level in want:
            if os.path.exists(os.path.join(SRC, "%s_sheet_raw.png" % level)):
                for t, img in enumerate(grid_cells("%s_sheet_raw.png" % level, 3, 3)):
                    save(img, level, t + 1)
        sys.exit(0)
    backgrounds()
    objects()
    ui()
