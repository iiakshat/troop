"""Slices the Gemini environment sheets (art_src/gen) into game textures (assets/env/tex).
  python -I tools/slice_env.py
facades.png: 4 facades in columns split by white gutters -> facade_1..4.png (cropped to the walls).
ground.png: 2x2 tiles -> asphalt, sidewalk, grass, pavers .png, made seamless by a centre cross-fade.
"""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GEN = ROOT / "art_src" / "gen"
OUT = ROOT / "assets" / "env" / "tex"


def white_runs(mask):
    """[start, end) runs where mask is False (content between gutters)."""
    runs, start = [], None
    for i, m in enumerate(mask):
        if not m and start is None:
            start = i
        elif m and start is not None:
            runs.append((start, i)); start = None
    if start is not None:
        runs.append((start, len(mask)))
    return [r for r in runs if r[1] - r[0] > 50]


def facades():
    a = np.asarray(Image.open(GEN / "facades.png").convert("RGB")).astype(int)
    gutter = (a.min(axis=2) > 235).mean(axis=0) > 0.9
    cols = white_runs(gutter)
    assert len(cols) == 4, cols
    for i, (x0, x1) in enumerate(cols, 1):
        c = a[:, x0:x1]
        bg = np.median(c[:, 8:20].reshape(-1, 3), axis=0)  # background colour at the column edge
        diff = np.abs(c - bg).sum(axis=2) > 40
        rows = np.where(diff.mean(axis=1) > 0.3)[0]
        y0, y1 = rows[0], rows[-1] + 1
        body = diff[y0 + (y1 - y0) // 5:y1 - (y1 - y0) // 5]
        wall = body.mean(axis=0) > 0.97  # columns that are wall on nearly every row
        wall[:14] = False                 # ignore anti-aliased pixels next to the gutters
        wall[-14:] = False
        xs = np.where(wall)[0]
        crop = c[y0:y1, xs[0] + 3:xs[-1] - 2]
        img = Image.fromarray(crop.astype(np.uint8)).resize((1024, 2560), Image.LANCZOS)
        img.save(OUT / f"facade_{i}.png")
        print("facade", i, crop.shape)


def seamless(img):
    a = np.asarray(img).astype(float)
    h, w = a.shape[:2]
    rolled = np.roll(np.roll(a, h // 2, axis=0), w // 2, axis=1)
    y = np.abs(np.linspace(-1, 1, h))[:, None]
    x = np.abs(np.linspace(-1, 1, w))[None, :]
    wgt = np.clip((1 - np.maximum(x, y)) / 0.35, 0, 1)[..., None]  # 1 in the middle, 0 at edges
    return Image.fromarray((a * wgt + rolled * (1 - wgt)).astype(np.uint8))


def ground():
    a = np.asarray(Image.open(GEN / "ground.png").convert("RGB")).astype(int)
    white = a.min(axis=2) > 235
    cols = white_runs(white.mean(axis=0) > 0.9)
    rows = white_runs(white.mean(axis=1) > 0.9)
    names = [["asphalt", "sidewalk"], ["grass", "pavers"]]
    for r, (y0, y1) in enumerate(rows):
        for c, (x0, x1) in enumerate(cols):
            tile = Image.fromarray(a[y0 + 6:y1 - 6, x0 + 6:x1 - 6].astype(np.uint8)).resize((1024, 1024), Image.LANCZOS)
            seamless(tile).save(OUT / f"{names[r][c]}.png")
            print("tile", names[r][c])


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    facades()
    ground()
