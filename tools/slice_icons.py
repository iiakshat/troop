"""Cuts the Gemini icon sheets (art_src/gen/icons_*.png, grids on magenta) into transparent
PNGs in assets/icons/gloss/<name>.png. UiKit prefers these over the SVGs.
  python -I tools/slice_icons.py              # every sheet
  python -I tools/slice_icons.py icons_c.png  # just one sheet

icons_a/icons_b (4x4) are cut on exact cell lines. icons_c (5x5) was not painted on an exact
grid, so each cell keeps the whole connected shapes whose centre lies in it ("loose" mode).
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
GEN = ROOT / "art_src" / "gen"
OUT = ROOT / "assets" / "icons" / "gloss"
SIZE = 320

SHEETS = {
    "icons_a.png": {"grid": [["coin", "gem", "trophy", "star_icon"],
                             ["shield", "bomb", "knife", "pistol"],
                             ["smg", "badge", "inspector", "swat"],
                             ["station", "money", "armour_break", "gang_split"]]},
    "icons_b.png": {"grid": [["thug", "brute", "riot", "boss"],
                             ["barrel", "bottle", "broken_bottle", "speed"],
                             ["shirt", "knife_power", "turncoat", "lock"],
                             ["chest", "fist", "police_car", "aim"]]},
    "icons_c.png": {"loose": True,
                    "outline_only": {"star_chest"},  # drop the painted glow halo
                    "grid": [["sergeant", "sniper", "commando", "molotov", "sniper_foe"],
                             ["grenadier", "pothole", "barricade", "gift", "wheel"],
                             ["missions", "star_chest", "clock", "hammer", "map_pin"],
                             ["ad_play", "headstart", "boss_crown", "fire", "city_hall"],
                             ["crown", "trophy_gold", "stars3", "district_lock", "heart"]]},
}


def key_alpha(c):
    """Alpha from 'pinkness' (min(R,B) - G): magenta background and pink tiles go clear."""
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    pink = np.minimum(r, b) - g
    alpha = np.clip((95.0 - pink) / 45.0, 0.0, 1.0)  # >=95 clear, <=50 solid
    # The pink tiles' pale highlight rims: light, pink-tinted, low saturation.
    pale = (np.minimum(r, b) > 185) & (np.minimum(r, b) - g > 18)
    alpha[pale] = 0.0
    # De-spill: pull pink-tinted edge pixels back towards neutral.
    excess = np.clip(np.minimum(r, b) - g, 0, None) * (1.0 - alpha)
    out = c.copy()
    out[..., 0] = r - excess
    out[..., 2] = b - excess
    return np.clip(out, 0, 255), alpha


def drop_frames(alpha):
    """Removes tile frames: big thin rings spanning most of the cell."""
    solid = alpha > 0.5
    lab, n = ndimage.label(solid)
    h, w = alpha.shape
    for i in range(1, n + 1):
        ys, xs = np.where(lab == i)
        bh, bw = ys.max() - ys.min() + 1, xs.max() - xs.min() + 1
        fill = len(ys) / float(bh * bw)
        if bh > 0.75 * h and bw > 0.75 * w and fill < 0.35:
            alpha[lab == i] = 0.0
    return alpha


def remove_specks(alpha, min_px=60):
    lab, n = ndimage.label(alpha > 0.5)
    sizes = ndimage.sum(np.ones_like(alpha), lab, range(1, n + 1))
    for i, sz in enumerate(sizes, 1):
        if sz < min_px:
            alpha[lab == i] = 0.0
    return alpha


def outline_only(c, alpha):
    """Keeps only what the thick navy outline encloses (removes glows painted around it)."""
    lum = c.mean(axis=2)
    dark = (lum < 80) & (alpha > 0.5)
    inside = ndimage.binary_fill_holes(ndimage.binary_closing(dark, iterations=3))
    inside = ndimage.binary_dilation(inside, iterations=2)
    return alpha * inside


def keep_centred(alpha, core):
    """Loose mode: keeps the shapes whose centre lies inside `core` (y0, y1, x0, x1)."""
    lab, n = ndimage.label(alpha > 0.5)
    if n == 0:
        return alpha
    keep = np.zeros(n + 1, bool)
    for i, (cy, cx) in enumerate(ndimage.center_of_mass(np.ones_like(alpha), lab, range(1, n + 1)), 1):
        keep[i] = core[0] <= cy < core[1] and core[2] <= cx < core[3]
    # soft edge pixels (alpha <= 0.5) follow the nearest kept shape
    near = ndimage.binary_dilation(keep[lab], iterations=4)
    return alpha * near


def paint_out_text(c, alpha):
    """The SWAT helmet carries the word SWAT; cover near-white text pixels on the dome."""
    h, w = alpha.shape
    region = (slice(int(h * 0.15), int(h * 0.42)), slice(int(w * 0.25), int(w * 0.75)))
    sub = c[region]
    lum = sub.mean(axis=2)
    dark = lum < 90
    dome = np.median(sub[dark].reshape(-1, 3), axis=0)
    text = lum > float(np.median(lum[dark])) + 35
    text = ndimage.binary_dilation(text, iterations=3)
    sub[text] = dome
    return c


def save(c, alpha, name):
    ys, xs = np.where(alpha > 0.05)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    rgba = np.dstack([c, alpha * 255]).astype(np.uint8)[y0:y1, x0:x1]
    img = Image.fromarray(rgba, "RGBA")
    side = max(img.width, img.height)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    canvas.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / f"{name}.png")


def cut(sheet, spec):
    a = np.asarray(Image.open(GEN / sheet).convert("RGB")).astype(float)
    H, W = a.shape[:2]
    grid = spec["grid"]
    rows, cols = len(grid), len(grid[0])
    for r, row in enumerate(grid):
        for col, name in enumerate(row):
            y0, y1 = r * H // rows, (r + 1) * H // rows
            x0, x1 = col * W // cols, (col + 1) * W // cols
            if spec.get("loose"):
                my, mx = (y1 - y0) // 6, (x1 - x0) // 6  # look a little into the neighbours
                wy0, wy1, wx0, wx1 = max(0, y0 - my), min(H, y1 + my), max(0, x0 - mx), min(W, x1 + mx)
                c, alpha = key_alpha(a[wy0:wy1, wx0:wx1].copy())
                alpha = keep_centred(alpha, (y0 - wy0, y1 - wy0, x0 - wx0, x1 - wx0))
            else:
                c, alpha = key_alpha(a[y0:y1, x0:x1].copy())
            alpha = remove_specks(drop_frames(alpha))
            if name in spec.get("outline_only", ()):
                alpha = outline_only(c, alpha)
            if name == "swat":
                c = paint_out_text(c, alpha)
            save(c, alpha, name)
            print("icon", name)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    only = set(sys.argv[1:])
    for sheet, spec in SHEETS.items():
        if not only or sheet in only:
            cut(sheet, spec)


if __name__ == "__main__":
    main()
