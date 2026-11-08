"""Cuts the Gemini city sheets (art_src/gen) into game art in assets/city/.
  python -I tools/slice_city.py            # everything
  python -I tools/slice_city.py ref        # only the downscaled, text-free reference sent with city_ruin.txt
  python -I tools/slice_city.py buildings  # only the 50 building sprites
  python -I tools/slice_city.py map        # only the map (and its layout)
  python -I tools/slice_city.py layout     # only assets/city/map_layout.json

city_built.png / city_ruin.png: 5x5 sheets on magenta, one district per row (ids in ROWS) ->
  <id>.png and <id>_ruin.png, 512x512 RGBA, all at ONE scale, centred, base tile on a shared
  ground line (BUILDING_PIVOT_Y). A few painted shop words are painted out first (PAINT_OUT).
map_panels.png: five tall district panels side by side (Downtown left .. Uptown right),
  split by white gutters -> stacked bottom (Downtown) to top (Uptown) with cross-fades, every
  other panel mirrored so the roads join up (FLIP)
  -> map.png (whole map, at most MAP_MAX_H tall so every phone GPU can hold it) and
  map_1..5.png (one district each at full resolution; same pixels, sharper).
"""
import importlib.util
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
GEN = ROOT / "art_src" / "gen"
OUT = ROOT / "assets" / "city"

_spec = importlib.util.spec_from_file_location("slice_icons", Path(__file__).with_name("slice_icons.py"))
icons = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(icons)

ROWS = [["cafe", "newsstand", "pharmacy", "bus_stop", "police_post"],
        ["fruit_market", "bakery", "barber", "cinema", "clinic"],
        ["fish_market", "warehouse", "lighthouse", "diner", "ferry"],
        ["factory", "power_station", "garage", "train_station", "fire_station"],
        ["hotel", "bank", "museum", "fountain_park", "city_hall"]]
SPRITE = 512
PAD = 6           # px of empty border in a sprite
BUILDING_PIVOT_Y = 0.808  # base-tile centre in a sprite (0..1 of height), printed by buildings()
REF_SIDE = 1536   # the reference image sent to Gemini (matches tools/gemini_image.py)

# Painted shop words in city_built.png: cell-local pixel polygons. "ink" repaints only the
# letter pixels from the sign colour around them; "all" repaints the whole polygon.
PAINT_OUT = {
    "city_built.png": {
        "newsstand": ("ink", [(280, 310), (357, 341), (357, 378), (280, 346)]),
        "pharmacy": ("ink", [(236, 280), (466, 386), (466, 440), (236, 334)]),
        "bakery": ("ink", [(248, 276), (442, 374), (442, 409), (248, 333)]),
        "museum": ("all", [(173, 333), (323, 396), (321, 430), (173, 372)]),
    },
    "city_ruin.png": {
        "pharmacy": ("ink", [(383, 352), (465, 385), (465, 432), (383, 400)]),
    },
}
# Buildings with a painted glow around a lamp or sign: keep only what the outline encloses.
GLOW = {"pharmacy", "police_post", "lighthouse"}
# Buildings with lattices or glass that the magenta shows through: key them like icons.
SEE_THROUGH = {"power_station", "bus_stop"}


def polygon_mask(shape, pts):
    from PIL import ImageDraw
    m = Image.new("L", (shape[1], shape[0]), 0)
    ImageDraw.Draw(m).polygon(pts, fill=1)
    return np.asarray(m).astype(bool)


def plane_fill(img, hole, sample, ref):
    """Fills `hole` with a smooth colour gradient fitted to the `sample` pixels whose colour is
    near `ref` (so outlines and other surfaces are ignored), feathering the seam a little."""
    vals = img[sample]
    good = np.abs(vals - ref).sum(axis=1) < 60
    ys, xs = np.where(sample)
    A = np.c_[np.ones(good.sum()), xs[good], ys[good]]
    coef, *_ = np.linalg.lstsq(A, vals[good], rcond=None)
    hy, hx = np.mgrid[0:img.shape[0], 0:img.shape[1]]
    plane = coef[0] + hx[..., None] * coef[1] + hy[..., None] * coef[2]
    w = ndimage.gaussian_filter(hole.astype(float), 1.2)[..., None]
    w = np.maximum(w, hole[..., None])
    return img * (1 - w) + plane * w


def paint_out(a, sheet, cells):
    """Removes painted words from the sheet in place (a: float RGB array)."""
    for bid, (mode, pts) in PAINT_OUT.get(sheet, {}).items():
        y0, x0 = cells[bid]
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        bx0, bx1, by0, by1 = min(xs) - 30, max(xs) + 30, min(ys) - 30, max(ys) + 30
        sub = a[y0 + by0:y0 + by1, x0 + bx0:x0 + bx1]
        poly = polygon_mask(sub.shape, [(x - bx0, y - by0) for x, y in pts])
        if mode == "ink":
            px = sub[poly]
            lum = px.mean(axis=1)
            board = np.median(px[lum >= np.percentile(lum, 60)], axis=0)  # signs are lighter than their words
            ink = (np.abs(sub - board).sum(axis=2) > 70) & poly
            hole = ndimage.binary_dilation(ink, iterations=3) & poly
            sample = ndimage.binary_dilation(poly, iterations=8) & ~hole
        else:
            hole = poly
            sample = ndimage.binary_dilation(poly, iterations=4) & ~poly
            board = np.median(sub[sample], axis=0)
        sub[...] = plane_fill(sub, hole, sample, board)


def cell_origins(H, W):
    return {bid: (r * H // 5, c * W // 5) for r, row in enumerate(ROWS) for c, bid in enumerate(row)}


def load_sheet(sheet):
    a = np.asarray(Image.open(GEN / sheet).convert("RGB")).astype(float)
    paint_out(a, sheet, cell_origins(*a.shape[:2]))
    return a


MAGENTA = np.array([240.0, 5.0, 249.0])  # the sheets' background, measured


def key_building(win, core, glow, lattice=False):
    """RGBA for one building. Unlike icons, pinks INSIDE the outline stay (neon, petals): only
    background magenta, magenta seen through small gaps, and the soft edge next to them go."""
    r, g, b = win[..., 0], win[..., 1], win[..., 2]
    bg = (g < 45) & (r > 200) & (b > 200)
    c, a_key = icons.key_alpha(win.copy())
    a_key = icons.keep_centred(a_key, core)
    solid = a_key > 0.5
    sil = ndimage.binary_fill_holes(ndimage.binary_closing(solid, iterations=3))
    see_through = (np.minimum(r, b) - g) > (30 if lattice else 110)  # gaps, glass over magenta
    interior = (ndimage.binary_erosion(sil, iterations=3) & ~see_through
                & ~ndimage.binary_dilation(bg, iterations=3))
    alpha = np.where(interior, 1.0, a_key * sil)
    col = np.where(interior[..., None], win, c)
    if glow:
        # A lamp's painted glow outside the navy outline: unmix it from the magenta into a
        # soft halo (alpha from the green channel, which magenta lacks).
        enclosed = icons.outline_only(win, np.where(sil, 1.0, 0.0)) > 0.5
        outer = sil & ~ndimage.binary_erosion(enclosed, iterations=2)
        a_g = np.clip((g - 15.0) / 200.0, 0.0, 1.0)
        unmixed = (win - (1.0 - a_g[..., None]) * MAGENTA) / np.maximum(a_g[..., None], 1e-3)
        alpha = np.where(outer, a_g, alpha)
        col = np.where(outer[..., None], np.clip(unmixed, 0, 255), col)
    alpha[bg] = 0.0
    return col, drop_strays(icons.remove_specks(alpha, 200))


def drop_strays(alpha):
    """Removes small loose bits (smoke dots) floating away from the building."""
    lab, n = ndimage.label(alpha > 0.5)
    if n < 2:
        return alpha
    sizes = ndimage.sum(np.ones_like(alpha), lab, range(1, n + 1))
    main = lab == (int(np.argmax(sizes)) + 1)
    dist = ndimage.distance_transform_edt(~main)
    for i, sz in enumerate(sizes, 1):
        part = lab == i
        if sz < 0.01 * sizes.max() and dist[part].min() > 12:
            alpha[ndimage.binary_dilation(part, iterations=3)] = 0.0
    return alpha


def cut_sheet(sheet):
    """Returns {id: (rgb, alpha)} cropped to each building's bounding box."""
    a = load_sheet(sheet)
    H, W = a.shape[:2]
    out = {}
    for bid, (y0, x0) in cell_origins(H, W).items():
        y1, x1 = y0 + H // 5, x0 + W // 5
        my, mx = (y1 - y0) // 6, (x1 - x0) // 6
        wy0, wy1, wx0, wx1 = max(0, y0 - my), min(H, y1 + my), max(0, x0 - mx), min(W, x1 + mx)
        col, alpha = key_building(a[wy0:wy1, wx0:wx1], (y0 - wy0, y1 - wy0, x0 - wx0, x1 - wx0),
                                    bid in GLOW, bid in SEE_THROUGH)
        ys, xs = np.where(alpha > 0.05)
        out[bid] = (col[ys.min():ys.max() + 1, xs.min():xs.max() + 1],
                    alpha[ys.min():ys.max() + 1, xs.min():xs.max() + 1])
    return out


def write_ref():
    """The text-free rebuilt sheet, downscaled exactly as gemini_image.py sends it."""
    a = load_sheet("city_built.png")
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    img.thumbnail((REF_SIDE, REF_SIDE), Image.LANCZOS)
    img.save(GEN / "city_built_ref.jpg", quality=90)
    print("wrote", GEN / "city_built_ref.jpg")


def buildings():
    OUT.mkdir(parents=True, exist_ok=True)
    built = cut_sheet("city_built.png")
    ruin = cut_sheet("city_ruin.png") if (GEN / "city_ruin.png").exists() else {}
    sheets = [("", built)] + ([("_ruin", ruin)] if ruin else [])
    # One scale for all 50 sprites: the largest bounding box fills the sprite.
    side = max(max(c.shape[0], c.shape[1]) for _, d in sheets for c, _ in d.values())
    scale = (SPRITE - 2 * PAD) / side
    pivots = []
    for suffix, d in sheets:
        for bid, (col, alpha) in d.items():
            rgba = np.dstack([np.clip(col, 0, 255), alpha * 255]).astype(np.uint8)
            img = Image.fromarray(rgba, "RGBA")
            w, h = max(1, round(img.width * scale)), max(1, round(img.height * scale))
            img = img.resize((w, h), Image.LANCZOS)
            canvas = Image.new("RGBA", (SPRITE, SPRITE), (0, 0, 0, 0))
            canvas.paste(img, ((SPRITE - w) // 2, SPRITE - PAD - h))  # shared ground line
            canvas.save(OUT / f"{bid}{suffix}.png")
            pivots.append(base_centre(np.asarray(canvas)[..., 3]))
            print("building", bid + suffix, (w, h))
    py = float(np.median([p for p in pivots if p is not None]))
    print("base-tile centre (median, 0..1 of sprite height):", round(py, 3))
    return round(py, 3)


def base_centre(alpha):
    """Vertical centre of the base tile's top face. The tile is a diamond slab: its side
    corners show at the sprite's leftmost/rightmost columns as a short vertical run (the slab's
    thickness), and the lowest pixel is the bottom of its front corner."""
    a = alpha > 128
    rows, cols = np.where(a.any(axis=1))[0], np.where(a.any(axis=0))[0]
    if len(rows) == 0:
        return None
    bottom = rows.max()
    runs = []
    for c in (cols.min() + 2, cols.max() - 2):
        ys = np.where(a[:, c])[0]
        end = ys.max()
        top = end
        while top > 0 and a[top - 1, c]:
            top -= 1
        runs.append((end, end - top + 1))
    end, thick = min(runs, key=lambda r: r[1])  # a pole at one corner makes that run long
    side_top = end - thick                       # side corners of the top face
    front_top = bottom - thick                   # front corner of the top face
    return (side_top + front_top) / 2.0 / alpha.shape[0]


# ---------------------------------------------------------------- map

MAP_MAX_H = 8192   # many phone GPUs cannot hold a taller texture
FADE = 160         # px cross-fade where two district panels meet
# Every panel's road runs from bottom-left to top-right; mirroring every other district makes
# each road leave a district on the side where the next one's road comes in.
FLIP = {2, 4}


def panel_runs(a):
    """Column ranges of the five panels between white gutters."""
    white = (a.min(axis=2) > 225).mean(axis=0) > 0.85
    runs, start = [], None
    for i, wcol in enumerate(white):
        if not wcol and start is None:
            start = i
        elif wcol and start is not None:
            runs.append((start, i))
            start = None
    if start is not None:
        runs.append((start, len(white)))
    return [r for r in runs if r[1] - r[0] > 200]


def trim_panel(p):
    """Drops white or near-white frame rows/columns left at a panel's edges."""
    lum_min = p.min(axis=2)
    keep_r = np.where((lum_min > 225).mean(axis=1) < 0.6)[0]
    keep_c = np.where((lum_min > 225).mean(axis=0) < 0.6)[0]
    return p[keep_r.min() + 4:keep_r.max() - 3, keep_c.min() + 4:keep_c.max() - 3]


def build_map():
    a = np.asarray(Image.open(GEN / "map_panels.png").convert("RGB")).astype(float)
    runs = panel_runs(a)
    assert len(runs) == 5, runs
    panels = [trim_panel(a[:, x0:x1]) for x0, x1 in runs]
    panels = [p[:, ::-1] if d in FLIP else p for d, p in enumerate(panels, 1)]
    w = min(p.shape[1] for p in panels)
    panels = [np.asarray(Image.fromarray(p.astype(np.uint8)).resize(
        (w, round(p.shape[0] * w / p.shape[1])), Image.LANCZOS)).astype(float) for p in panels]
    # stack: Uptown (panel 5) at the top ... Downtown (panel 1) at the bottom
    order = panels[::-1]
    total = sum(p.shape[0] for p in order) - FADE * 4
    out = np.zeros((total, w, 3))
    y = 0
    bands = []
    for i, p in enumerate(order):
        h = p.shape[0]
        if i == 0:
            out[0:h] = p
        else:
            t = np.linspace(0, 1, FADE)[:, None, None]
            out[y:y + FADE] = out[y:y + FADE] * (1 - t) + p[:FADE] * t
            out[y + FADE:y + h] = p[FADE:]
        bands.append((y, y + h))
        y += h - FADE
    district_bands = {}
    for i, (y0, y1) in enumerate(bands):
        d = 5 - i
        # the boundary between two districts is the middle of their cross-fade
        top = y0 + (FADE // 2 if i > 0 else 0)
        bot = y1 - (FADE // 2 if i < 4 else 0)
        district_bands[d] = (top / total, bot / total)
        tile = Image.fromarray(np.clip(out[top:bot], 0, 255).astype(np.uint8))
        tile.save(OUT / f"map_{d}.png")
        print("map tile", d, tile.size)
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))
    full_size = img.size
    if img.height > MAP_MAX_H:
        img = img.resize((round(img.width * MAP_MAX_H / img.height), MAP_MAX_H), Image.LANCZOS)
    img.save(OUT / "map.png")
    print("map", full_size, "->", img.size)
    (GEN / "map_bands.json").write_text(json.dumps(
        {"full_size": full_size, "bands": {str(k): v for k, v in district_bands.items()}}, indent=1))
    return district_bands


# ---------------------------------------------------------------- map layout
# Placed by eye on each district tile (x, y in 0..1 of that tile, y down), bottom to top.
# plots: where the 5 buildings sit (the four empty paved lots plus one open spot), in build
# order. road: waypoints along the road's middle; the level path is a smooth curve through
# them and the 10 level nodes are spread evenly along it.
DISTRICTS = [
    {"id": 1, "name": "downtown", "tint": "#ffffff",
     "plots": [(0.67, 0.865), (0.37, 0.735), (0.47, 0.60), (0.62, 0.405), (0.67, 0.215)],
     "road": [(0.06, 0.95), (0.30, 0.865), (0.52, 0.80), (0.68, 0.72), (0.73, 0.62), (0.63, 0.50),
              (0.42, 0.43), (0.22, 0.35), (0.19, 0.25), (0.32, 0.16), (0.55, 0.09), (0.88, 0.02)]},
    {"id": 2, "name": "market", "tint": "#fff1de",
     "plots": [(0.33, 0.87), (0.62, 0.745), (0.70, 0.58), (0.37, 0.40), (0.33, 0.21)],
     "road": [(0.92, 0.96), (0.62, 0.84), (0.40, 0.77), (0.25, 0.70), (0.21, 0.60), (0.30, 0.50),
              (0.50, 0.44), (0.59, 0.37), (0.63, 0.27), (0.59, 0.18), (0.45, 0.12), (0.25, 0.06),
              (0.08, 0.02)]},
    {"id": 3, "name": "docks", "tint": "#ffe5c4",
     "plots": [(0.68, 0.87), (0.37, 0.75), (0.20, 0.585), (0.63, 0.415), (0.68, 0.215)],
     "road": [(0.06, 0.95), (0.30, 0.87), (0.55, 0.80), (0.72, 0.72), (0.76, 0.62), (0.68, 0.52),
              (0.50, 0.46), (0.30, 0.40), (0.22, 0.30), (0.28, 0.20), (0.45, 0.12), (0.70, 0.06),
              (0.92, 0.02)]},
    {"id": 4, "name": "industrial", "tint": "#f6cba8",
     "plots": [(0.33, 0.875), (0.62, 0.745), (0.66, 0.57), (0.36, 0.415), (0.32, 0.21)],
     "road": [(0.92, 0.95), (0.70, 0.86), (0.50, 0.80), (0.33, 0.75), (0.20, 0.68), (0.18, 0.60),
              (0.25, 0.50), (0.42, 0.44), (0.60, 0.38), (0.68, 0.30), (0.66, 0.20), (0.55, 0.14),
              (0.35, 0.08), (0.10, 0.02)]},
    {"id": 5, "name": "uptown", "tint": "#9aa6d6",
     "plots": [(0.65, 0.875), (0.38, 0.75), (0.32, 0.58), (0.62, 0.415), (0.67, 0.225)],
     "road": [(0.06, 0.94), (0.30, 0.87), (0.50, 0.82), (0.65, 0.75), (0.72, 0.65), (0.68, 0.55),
              (0.52, 0.48), (0.35, 0.42), (0.22, 0.33), (0.22, 0.24), (0.32, 0.17), (0.50, 0.12),
              (0.75, 0.06), (0.92, 0.02)]},
]
NODE_SPAN = (0.06, 0.94)  # level nodes stay off the district seams
BUILDING_WIDTH = 0.44     # suggested sprite width as a fraction of the map width (fits a plot)


def road_curve(waypoints, w, h):
    """Dense pixel path (y, x) of a smooth curve through the road waypoints of a w x h tile."""
    from scipy.interpolate import splev, splprep
    xs = np.array([x * w for x, _ in waypoints])
    ys = np.array([y * h for _, y in waypoints])
    tck, _ = splprep([xs, ys], s=len(xs) * 4.0, k=3)
    cx, cy = splev(np.linspace(0, 1, 2000), tck)
    return np.c_[cy, cx]


def spread(path, n, span):
    """n points (x, y) evenly spaced by arc length over the `span` fraction of the path."""
    seg = np.sqrt((np.diff(path, axis=0) ** 2).sum(axis=1))
    s = np.concatenate([[0.0], np.cumsum(seg)])
    targets = np.linspace(span[0], span[1], n) * s[-1]
    return [(float(np.interp(t, s, path[:, 1])), float(np.interp(t, s, path[:, 0]))) for t in targets]


def build_layout():
    info = json.loads((GEN / "map_bands.json").read_text())
    bands = {int(k): v for k, v in info["bands"].items()}
    districts, level = [], 1
    for d in DISTRICTS:
        y0, y1 = bands[d["id"]]
        with Image.open(OUT / f"map_{d['id']}.png") as tile:
            w, h = tile.size
        nodes = [(x / w, y / h) for x, y in spread(road_curve(d["road"], w, h), 10, NODE_SPAN)]

        def to_map(x, y):
            return [round(x, 4), round(y0 + y * (y1 - y0), 4)]

        districts.append({
            "id": d["id"], "name": d["name"], "band": [round(y0, 4), round(y1, 4)],
            "tile": f"map_{d['id']}.png", "tint": d["tint"],
            "buildings": [{"id": bid, "pos": to_map(*p)} for bid, p in zip(ROWS[d["id"] - 1], d["plots"])],
            "levels": [{"level": level + i, "pos": to_map(*p)} for i, p in enumerate(nodes)],
        })
        level += 10
    with Image.open(OUT / "map.png") as m:
        size = list(m.size)
    layout = {
        "_doc": "Normalised 0..1 coordinates over map.png (x right, y down, 0 = top). Downtown "
                "(district 1) is the bottom band, Uptown (5) the top. Each district's tile is the "
                "same band at full resolution (use either). Building sprites (assets/city/<id>.png "
                "and <id>_ruin.png, 512x512, one shared scale) have the centre of their base tile "
                "at building_pivot: put that point on the building's pos, drawn about "
                "building_width of the map width wide. tint: suggested modulate for building "
                "sprites so they match the band's lighting. Level nodes follow the road in order.",
        "image": "map.png", "size": size, "full_size": info["full_size"],
        "building_pivot": [0.5, BUILDING_PIVOT_Y], "building_width": BUILDING_WIDTH,
        "districts": districts,
    }
    (OUT / "map_layout.json").write_text(json.dumps(layout, indent=1), encoding="utf-8")
    print("wrote", OUT / "map_layout.json")
    return layout


def main():
    what = set(sys.argv[1:]) or {"buildings", "map"}
    if "ref" in what:
        write_ref()
    if "buildings" in what:
        buildings()
    if "map" in what and (GEN / "map_panels.png").exists():
        build_map()
    if ("map" in what or "layout" in what) and (OUT / "map_1.png").exists():
        build_layout()


if __name__ == "__main__":
    main()
