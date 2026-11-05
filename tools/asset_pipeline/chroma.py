"""Magenta chroma-key utilities for Layer-generated sprite sheets (flat #FF00FF-ish backgrounds)."""
import numpy as np
from PIL import Image
from scipy import ndimage

BG = np.array([251.0, 2.0, 251.0])


def key_magenta(img: Image.Image) -> Image.Image:
    """Return RGBA with the magenta background removed and edge colours un-mixed."""
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    m = np.clip(np.minimum(r, b) - g, 0, None)
    hi, lo = 155.0, 30.0
    alpha = np.clip((hi - m) / (hi - lo), 0.0, 1.0)
    # un-mix partially covered edge pixels from the background colour
    safe = np.maximum(alpha, 0.05)[..., None]
    fg = (a - (1.0 - alpha)[..., None] * BG) / safe
    fg = np.clip(fg, 0, 255)
    out = np.dstack([fg, alpha * 255.0]).astype(np.uint8)
    out[alpha < 0.04] = 0
    return Image.fromarray(out, "RGBA")


def components(rgba: Image.Image, dilate=6, min_area=400):
    """Connected components of the alpha channel (after dilation to merge close fragments).
    Returns list of (bbox(l,t,r,b), cropped RGBA image) sorted left-to-right then top-to-bottom."""
    arr = np.asarray(rgba)
    mask = arr[..., 3] > 20
    grown = ndimage.binary_dilation(mask, iterations=dilate) if dilate else mask
    lab, n = ndimage.label(grown)
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab), start=1):
        if sl is None:
            continue
        region = (lab[sl] == i) & mask[sl]
        if region.sum() < min_area:
            continue
        crop = arr[sl].copy()
        crop[~ndimage.binary_dilation(region, iterations=dilate)] = 0
        t, bt = sl[0].start, sl[0].stop
        l, rt = sl[1].start, sl[1].stop
        out.append(((l, t, rt, bt), Image.fromarray(crop, "RGBA")))
    return out


def trim(rgba: Image.Image, pad=2) -> Image.Image:
    bb = rgba.getbbox()
    if not bb:
        return rgba
    l, t, r, b = bb
    return rgba.crop((max(0, l - pad), max(0, t - pad), min(rgba.width, r + pad), min(rgba.height, b + pad)))
