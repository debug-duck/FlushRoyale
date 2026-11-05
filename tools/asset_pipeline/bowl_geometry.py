"""Toilet geometry shared by the Python tools. Mirrors game/bowl/bowl_geometry.gd exactly
(same Catmull-Rom subdivision), so the Layer art guide and the Godot collision line up."""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SUBDIV = 6


def load():
    with open(os.path.join(ROOT, "data", "bowl.json")) as f:
        return json.load(f)


def _catmull(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return tuple(0.5 * ((2 * p1[i]) + (-p0[i] + p2[i]) * t + (2 * p0[i] - 5 * p1[i] + 4 * p2[i] - p3[i]) * t2
                        + (-p0[i] + 3 * p1[i] - 3 * p2[i] + p3[i]) * t3) for i in range(2))


def inner_left(b):
    """Smoothed left interior wall from the rim lip down to the throat (top -> bottom)."""
    cx, w = b["center_x"], b["drain_width"]
    ctrl = [tuple(p) for p in b["inner_left"]] + [(cx - w / 2.0, b["throat_y"])]
    out = []
    for i in range(len(ctrl) - 1):
        p0 = ctrl[max(i - 1, 0)]
        p1, p2 = ctrl[i], ctrl[i + 1]
        p3 = ctrl[min(i + 2, len(ctrl) - 1)]
        for s in range(SUBDIV):
            out.append(_catmull(p0, p1, p2, p3, s / SUBDIV))
    out.append(ctrl[-1])
    return out


def mirror(pts, cx):
    return [(2 * cx - x, y) for x, y in pts]
