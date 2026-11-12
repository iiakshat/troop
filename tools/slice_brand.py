"""Brand art from the owner's key-art picks (2026-11-12): no wordmark anywhere. The concept
sheet (_local/keyart/sheet.png in the main checkout, 3x2 square cells) gave three shots:
1 the hero close-up (app icon), 4 the charge and 5 the standoff (loading screen, alternating;
4 also makes the Play feature graphic). Needs numpy, scipy, Pillow and opencv-python.

  python -I tools/slice_brand.py crop <sheet.png>   cut cells 1, 4, 5 into art_src/keyart/
  python -I tools/slice_brand.py pads               the Gemini canvases (cell + grey bands)
  (Gemini, one request each, the canvas as --ref:
     python -I tools/gemini_image.py art_src/keyart/gen_<name>.png <aspect>
            art_src/keyart/prompts/<name>.txt --ref art_src/keyart/pad_<name>.png)
  python -I tools/slice_brand.py                    build every runtime and store image
  python -I tools/slice_brand.py lightbar           re-cut the loading bar's light-bar

Gemini repaints the whole canvas, so the build lays the untouched full-resolution cell back
over its own painting (registered by scale and offset, a soft colour match and a feathered
seam): the characters stay exactly the concept's, only the bands are new. The standoff's
lower band drifted (a second set of boots, off-model long legs, a hard seam), so it is
replaced by the cell's last rows smeared down with a growing blur (an out-of-focus
foreground that sits under the loading screen's scrim).

Writes:
  assets/brand/keyart_charge.jpg     loading screen, shot 4 extended to 9:16 (1152x2048)
  assets/brand/keyart_standoff.jpg   loading screen, shot 5 extended to 9:16 (1152x2048)
  assets/brand/icon.png              window icon, 512x512, full square (= the Play icon)
  assets/brand/icon_main.png         legacy launcher icon, 192x192
  assets/brand/icon_bg.png           adaptive background, 432x432, the art full bleed
  assets/brand/icon_fg.png           adaptive foreground, 432x432, clear
  assets/brand/icon_mono.png         adaptive monochrome, 432x432, the hero's head
  art_src/brand/play_icon_512.png    Play Console hi-res icon
  art_src/brand/feature_graphic.png  Play feature graphic 1024x500, wide shot 4, no text
  _local/keyart/icon_masks.png       launcher mask preview (circle, squircle, rounded square)
"""
import sys
from pathlib import Path
import cv2
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
KEY = ROOT / "art_src" / "keyart"
GEN = ROOT / "art_src" / "gen"
OUT = ROOT / "assets" / "brand"
SRC = ROOT / "art_src" / "brand"
PROOF = ROOT / "_local" / "keyart"

# Cells of the concept sheet (5056x3392): found by scanning for the gap colour, then inset
# 4 px past the 3 px blend at each cell edge.
CELLS = {1: (39, 57, 1653, 1665), 4: (39, 1727, 1653, 3337), 5: (1721, 1727, 3335, 3337)}
GREY = (128, 128, 128)
# name: (cell, aspect w:h, the share of the free space before the cell)
CANVASES = {
    "charge_portrait": (4, (9, 16), 0.45),
    "standoff_portrait": (5, (9, 16), 0.45),
    "charge_wide": (4, (21, 9), 0.5),  # Gemini has no 2:1; the feature graphic crops it
}
PORTRAIT = (1152, 2048)
INSET = 0.04  # the registration template leaves this share of each cell edge out

# Shot 1: the hero's head outline, traced by hand in cell pixels and refined by GrabCut.
HEAD_POLY = [(450, 250), (520, 165), (600, 120), (690, 78), (760, 95), (860, 100), (940, 140),
             (1010, 170), (1060, 230), (1095, 300), (1130, 400), (1145, 520), (1150, 590),
             (1190, 600), (1215, 650), (1210, 720), (1180, 760), (1150, 790), (1110, 840),
             (1040, 895), (920, 935), (800, 948), (680, 935), (560, 895), (470, 830),
             (420, 760), (350, 730), (325, 660), (340, 600), (390, 590), (395, 500), (410, 380),
             (440, 290)]
SAFE = 66.0 / 108.0       # adaptive icon safe circle, share of the layer
VISIBLE = 72.0 / 108.0    # what a launcher mask can show of a layer
ADAPTIVE_HEAD = 0.97      # the head's enclosing circle, share of the safe circle
PLAY_HEAD = 0.80          # the head's enclosing circle, share of the Play icon's side
MONO_HEAD = 0.54          # the themed icon's head, share of the layer


def cell(n):
    return Image.open(KEY / f"shot{n}.png").convert("RGB")


def layout(name):
    """(canvas size, cell box) of a canvas, in the cell's own pixels."""
    n, (aw, ah), share = CANVASES[name]
    cw, ch = cell(n).size
    if aw * ch < ah * cw:  # taller than the cell: bands above and below
        W, H = cw, round(cw * ah / aw)
        y = round((H - ch) * share)
        return (W, H), (0, y, cw, y + ch)
    W, H = round(ch * aw / ah), ch
    x = round((W - cw) * share)
    return (W, H), (x, 0, x + cw, ch)


def crop(sheet):
    im = Image.open(sheet).convert("RGB")
    KEY.mkdir(parents=True, exist_ok=True)
    for n, box in CELLS.items():
        im.crop(box).save(KEY / f"shot{n}.png", optimize=True)
        print("shot%d" % n, im.crop(box).size)


def pads():
    for name, (n, _, _) in CANVASES.items():
        (W, H), box = layout(name)
        pad = Image.new("RGB", (W, H), GREY)
        pad.paste(cell(n), box[:2])
        pad.save(KEY / f"pad_{name}.png", optimize=True)
        print("pad_" + name, pad.size)


# ---------------------------------------------------------------- composite

def _match(g_small, f, s, k, ex, ey, win):
    """Normalised-correlation peak of the cell s (scaled by k, its edges inset) inside the gen
    image seen at scale f, within win px (at f) of the expected corner (ex, ey) in gen px.
    Returns (score, x, y) of the cell's corner in gen pixels."""
    sh, sw = s.shape
    ix, iy = int(sw * INSET), int(sh * INSET)
    t = s[iy:sh - iy, ix:sw - ix]
    tw, th = max(8, round(t.shape[1] * k * f)), max(8, round(t.shape[0] * k * f))
    t = cv2.resize(t, (tw, th), interpolation=cv2.INTER_AREA)
    cx, cy = (ex + ix * k) * f, (ey + iy * k) * f
    x0, y0 = max(0, int(cx - win)), max(0, int(cy - win))
    x1 = min(g_small.shape[1], int(cx + win) + tw + 1)
    y1 = min(g_small.shape[0], int(cy + win) + th + 1)
    region = g_small[y0:y1, x0:x1]
    if region.shape[0] < th or region.shape[1] < tw:
        return -1.0, ex, ey
    r = cv2.matchTemplate(region, t, cv2.TM_CCOEFF_NORMED)
    _, mx, _, loc = cv2.minMaxLoc(r)
    return float(mx), (x0 + loc[0]) / f - ix * k, (y0 + loc[1]) / f - iy * k


def register(gen, src, k0, ex, ey):
    """Where the cell really sits in Gemini's image (it may shift or scale its repaint a
    little): coarse scale and offset search, then finer, then at full resolution.
    Returns (score, x, y, k): the cell's corner in gen pixels and its scale."""
    g = cv2.cvtColor(np.asarray(gen), cv2.COLOR_RGB2GRAY)
    s = cv2.cvtColor(np.asarray(src), cv2.COLOR_RGB2GRAY)

    def at(f):
        return cv2.resize(g, (round(g.shape[1] * f), round(g.shape[0] * f)), interpolation=cv2.INTER_AREA)

    f = 400.0 / (src.width * k0)
    gs = at(f)
    best = max((_match(gs, f, s, k0 * sc, ex, ey, 0.06 * 400) + (k0 * sc,)
                for sc in np.linspace(0.95, 1.05, 21)), key=lambda b: b[0])
    f = 1400.0 / (src.width * k0)
    gs = at(f)
    best = max((_match(gs, f, s, best[3] * sc, best[1], best[2], 8) + (best[3] * sc,)
                for sc in np.linspace(0.995, 1.005, 11)), key=lambda b: b[0])
    fine = _match(g, 1.0, s, best[3], best[1], best[2], 4)
    return fine + (best[3],)


def lay_over(gen, src, x, y, feather):
    """Lays the cell over gen with its corner at (x, y): a soft colour correction carries the
    cell's edge colours into gen's bands (fading over a quarter of the cell), then the cell is
    pasted with a feathered edge wherever it meets a band."""
    out = np.asarray(gen, dtype=np.float64).copy()
    s = np.asarray(src, dtype=np.float64)
    H, W = out.shape[:2]
    x, y = int(round(x)), int(round(y))
    sx0, sy0 = max(0, -x), max(0, -y)
    gx0, gy0 = max(0, x), max(0, y)
    gx1, gy1 = min(W, x + s.shape[1]), min(H, y + s.shape[0])
    s = s[sy0:sy0 + gy1 - gy0, sx0:sx0 + gx1 - gx0]
    region = out[gy0:gy1, gx0:gx1].copy()
    decay = max(s.shape) * 0.25
    band = max(8, feather // 2)
    sig = max(4.0, s.shape[1] * 0.03)
    # The correction is full strength under the feathered edge too, so the blend runs from
    # the cell to an already matched band (no bump in the seam).
    if gy0 > 0:
        d = ndimage.gaussian_filter1d(s[:band].mean(axis=0) - region[:band].mean(axis=0), sig, axis=0)
        dist = np.maximum(0, gy0 - np.arange(gy0 + feather))[:, None, None]
        out[:gy0 + feather, gx0:gx1] += d[None] * np.exp(-dist / decay)
    if gy1 < H:
        d = ndimage.gaussian_filter1d(s[-band:].mean(axis=0) - region[-band:].mean(axis=0), sig, axis=0)
        dist = np.maximum(0, np.arange(gy1 - feather, H) - (gy1 - 1))[:, None, None]
        out[gy1 - feather:, gx0:gx1] += d[None] * np.exp(-dist / decay)
    if gx0 > 0:
        d = ndimage.gaussian_filter1d(s[:, :band].mean(axis=1) - region[:, :band].mean(axis=1), sig, axis=0)
        dist = np.maximum(0, gx0 - np.arange(gx0 + feather))[None, :, None]
        out[gy0:gy1, :gx0 + feather] += d[:, None] * np.exp(-dist / decay)
    if gx1 < W:
        d = ndimage.gaussian_filter1d(s[:, -band:].mean(axis=1) - region[:, -band:].mean(axis=1), sig, axis=0)
        dist = np.maximum(0, np.arange(gx1 - feather, W) - (gx1 - 1))[None, :, None]
        out[gy0:gy1, gx1 - feather:] += d[:, None] * np.exp(-dist / decay)
    ramp = 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, feather))
    wy, wx = np.ones(s.shape[0]), np.ones(s.shape[1])
    if gy0 > 0:
        wy[:feather] = np.minimum(wy[:feather], ramp)
    if gy1 < H:
        wy[-feather:] = np.minimum(wy[-feather:], ramp[::-1])
    if gx0 > 0:
        wx[:feather] = np.minimum(wx[:feather], ramp)
    if gx1 < W:
        wx[-feather:] = np.minimum(wx[-feather:], ramp[::-1])
    a = (wy[:, None] * wx[None, :])[..., None]
    out[gy0:gy1, gx0:gx1] = s * a + out[gy0:gy1, gx0:gx1] * (1.0 - a)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")


def compose(name):
    """Gemini's canvas at the cell's scale with the original cell laid back over it.
    Returns (image, (x, y, w, h) of the cell in it)."""
    n = CANVASES[name][0]
    src = cell(n)
    gen = Image.open(KEY / f"gen_{name}.png").convert("RGB")
    (W, H), box = layout(name)
    if W == src.width:  # bands above and below: the cell spans the width
        k0, ex, ey = gen.width / W, 0.0, box[1] * gen.height / H
    else:
        k0, ex, ey = gen.height / H, box[0] * gen.width / W, 0.0
    score, x, y, k = register(gen, src, k0, ex, ey)
    g = gen.resize((round(gen.width / k), round(gen.height / k)), Image.LANCZOS)
    x, y = x / k, y / k
    xi, yi = int(round(x)), int(round(y))
    over = np.asarray(g, np.float64)[max(0, yi):yi + src.height, max(0, xi):xi + src.width]
    mine = np.asarray(src, np.float64)[max(0, -yi):max(0, -yi) + over.shape[0], max(0, -xi):max(0, -xi) + over.shape[1]]
    print(f"{name}: gen {gen.size} -> {g.size}, cell at ({x:.1f}, {y:.1f}) x{k / k0:.4f}, "
          f"match {score:.3f}, mean colour gap {np.abs(over - mine).mean():.1f}")
    if score < 0.8:
        raise SystemExit(f"{name}: Gemini moved or redrew the shot (match {score:.2f}); repaint it")
    img = lay_over(g, src, x, y, feather=max(16, round(src.width * 0.03)))
    return img, (x, y, src.width, src.height)


def smear_down(img, y1, blend=60, blur0=8.0, blur1=60.0, dark=0.45):
    """Replaces everything below row y1 with the rows just above it smeared down: each new row
    is the cell's last rows blurred more and darkened more the lower it is (an out-of-focus
    foreground). The first `blend` rows above y1 ease into it."""
    a = np.asarray(img, dtype=np.float64).copy()
    H = a.shape[0]
    base = a[y1 - 8:y1].mean(axis=0)
    rows = H - y1
    for r in range(-blend, rows):
        f = max(0.0, r) / max(1, rows - 1)
        row = ndimage.gaussian_filter1d(base, blur0 + (blur1 - blur0) * f ** 0.8, axis=0, mode="nearest")
        row = row * (1.0 - dark * f ** 1.2)
        if r < 0:
            w = 0.5 - 0.5 * np.cos(np.pi * (r + blend) / blend)  # 0 at the top of the blend, 1 at y1
            a[y1 + r] = a[y1 + r] * (1.0 - w) + row * w
        else:
            a[y1 + r] = row
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")


def cover(img, size, focus=(0.5, 0.5)):
    """img scaled to cover size, cropped around focus (shares of img)."""
    W, H = size
    k = max(W / img.width, H / img.height)
    s = img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)
    x = int(np.clip(focus[0] * s.width - W / 2, 0, s.width - W))
    y = int(np.clip(focus[1] * s.height - H / 2, 0, s.height - H))
    return s.crop((x, y, x + W, y + H))


def to_portrait(img):
    """The 9:16 frame of a composed portrait canvas (Gemini's canvas is a hair off 9:16)."""
    W = img.width
    H = round(W * 16 / 9)
    y = (img.height - H) // 2
    return img.crop((0, y, W, y + H)) if img.height >= H else cover(img, (W, H))


# ---------------------------------------------------------------- icons (shot 1)

def head_mask(img):
    """The hero's head (hair, face and ears, no neck) in shot 1: the traced outline refined by
    GrabCut, smoothed, holes filled."""
    bgr = cv2.cvtColor(np.asarray(img), cv2.COLOR_RGB2BGR)
    H, W = bgr.shape[:2]
    m = np.zeros((H, W), np.uint8)
    cv2.fillPoly(m, [np.array(HEAD_POLY, np.int32)], 1)
    disc = lambda r: cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))
    gc = np.full((H, W), cv2.GC_BGD, np.uint8)
    gc[cv2.dilate(m, disc(22)) == 1] = cv2.GC_PR_BGD
    gc[m == 1] = cv2.GC_PR_FGD
    gc[cv2.erode(m, disc(14)) == 1] = cv2.GC_FGD
    cv2.setRNGSeed(7)
    cv2.grabCut(bgr, gc, None, np.zeros((1, 65)), np.zeros((1, 65)), 8, cv2.GC_INIT_WITH_MASK)
    fg = (gc == cv2.GC_FGD) | (gc == cv2.GC_PR_FGD)
    lab, n = ndimage.label(fg)
    fg = lab == 1 + int(np.argmax(ndimage.sum(fg, lab, range(1, n + 1))))
    # GrabCut frays where the jaw meets the dark neck: the traced outline (rounded) fills it
    fg |= ndimage.gaussian_filter(cv2.erode(m, disc(6)).astype(np.float64), 12.0) > 0.5
    fg = ndimage.binary_fill_holes(fg)
    disc = lambda r: cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))
    fg = cv2.morphologyEx(fg.astype(np.uint8), cv2.MORPH_CLOSE, disc(30))   # notches at the jaw
    fg = cv2.morphologyEx(fg, cv2.MORPH_OPEN, disc(16))                       # specks, frayed hair
    return ndimage.gaussian_filter(fg.astype(np.float64), 5.0) > 0.5


# Shot 1 features for the themed icon: brow and smile boxes (x0, y0, x1, y1, darker than),
# the eyes as measured ellipses (centre x, y, half-axes; the brows touch their tops).
BROWS = [(480, 310, 760, 425, 0.45), (860, 300, 1120, 425, 0.45)]
EYES = [(628, 470, 40, 52), (999, 461, 37, 49)]
SMILE = (690, 630, 980, 700, 0.55)
HAIR_BELOW = 300  # hair is the dark part of the head above this row


def face_features(img, head):
    """The themed icon's cut-outs: clean brows, eyes and smile (each a smoothed dark mark in
    its box; eyes are their convex hulls) and a thin hairline between hair and forehead."""
    lum = np.asarray(img.convert("L"), dtype=np.float64) / 255.0
    H, W = lum.shape
    out = np.zeros((H, W), bool)

    def marks(box, grow=0):
        x0, y0, x1, y1, dark = box
        m = np.zeros((H, W), bool)
        m[y0:y1, x0:x1] = lum[y0:y1, x0:x1] < dark
        lab, n = ndimage.label(m)
        if n == 0:
            return m
        m = lab == 1 + int(np.argmax(ndimage.sum(m, lab, range(1, n + 1))))
        m = ndimage.binary_fill_holes(m)
        if grow:
            m = ndimage.binary_dilation(m, iterations=grow)
        return ndimage.gaussian_filter(m.astype(np.float64), 4.0) > 0.5

    eyes = np.zeros((H, W), np.uint8)
    for cx, cy, ax, ay in EYES:
        cv2.ellipse(eyes, (cx, cy), (ax, ay), 0, 0, 360, 1, -1)
    eyes = eyes.astype(bool)
    brows = np.zeros((H, W), bool)
    for box in BROWS:
        brows |= marks(box, grow=4)
    # the brows sit on the eyes: keep a strip of face between them so each reads alone
    brows &= ~ndimage.binary_dilation(eyes, iterations=18)
    out |= eyes | (ndimage.gaussian_filter(brows.astype(np.float64), 3.0) > 0.5)
    out |= marks(SMILE, grow=7)
    hair = head & (lum < 0.5)
    hair[HAIR_BELOW:] = False
    hair = ndimage.gaussian_filter(ndimage.binary_opening(hair, iterations=4).astype(np.float64), 6.0) > 0.5
    line = ndimage.binary_dilation(hair, iterations=12) & ~hair & ndimage.binary_erosion(head, iterations=10)
    return out | line


def head_circle(mask):
    ys, xs = np.nonzero(mask)
    pts = np.stack([xs, ys], axis=1).astype(np.float32)
    (cx, cy), r = cv2.minEnclosingCircle(cv2.convexHull(pts))
    return float(cx), float(cy), float(r)


def square(img, cx, cy, side, out):
    """A side x side crop centred at (cx, cy), resized to out x out. Parts beyond the image
    are filled by stretching its edge rows and columns, fading into a hard blur (sky)."""
    x0, y0 = int(round(cx - side / 2)), int(round(cy - side / 2))
    side = int(round(side))
    pad = max(0, -x0, -y0, x0 + side - img.width, y0 + side - img.height)
    if pad > 0:
        a = np.asarray(img)
        big = np.pad(a, ((pad, pad), (pad, pad)) + (((0, 0),) if a.ndim == 3 else ()), mode="edge").astype(np.float64)
        blurred = ndimage.gaussian_filter(big, (40, 40, 0) if a.ndim == 3 else 40)
        inside = np.zeros(big.shape[:2], bool)
        inside[pad:pad + a.shape[0], pad:pad + a.shape[1]] = True
        w = np.where(inside, 1.0, ndimage.gaussian_filter(inside.astype(np.float64), 20))
        if a.ndim == 3:
            w = w[..., None]
        big = big * w + blurred * (1.0 - w)
        img = Image.fromarray(np.clip(big, 0, 255).astype(np.uint8), img.mode)
        x0, y0 = x0 + pad, y0 + pad
    return img.crop((x0, y0, x0 + side, y0 + side)).resize((out, out), Image.LANCZOS)


def icons(shot):
    head = head_mask(shot)
    feats = face_features(shot, head)
    cx, cy, r = head_circle(head)
    print(f"head circle ({cx:.0f}, {cy:.0f}) r {r:.0f}")
    # Adaptive background: the art full bleed, the head's circle inside the safe circle.
    bg = square(shot, cx, cy, 2.0 * r / (SAFE * ADAPTIVE_HEAD), 432)
    bg.save(OUT / "icon_bg.png", optimize=True)
    Image.new("RGBA", (432, 432), (0, 0, 0, 0)).save(OUT / "icon_fg.png", optimize=True)
    # Monochrome (themed icons tint its alpha): the head silhouette, the features cut out.
    sil = Image.fromarray(np.where(feats, 0, head * 255).astype(np.uint8), "L")
    side_m = 2.0 * r / MONO_HEAD
    x0, y0 = cx - side_m / 2, cy - side_m / 2
    canvas = Image.new("L", (int(np.ceil(side_m)) + 2, int(np.ceil(side_m)) + 2), 0)
    canvas.paste(sil, (int(round(-x0)), int(round(-y0))))  # beyond the cell is clear
    a = canvas.crop((0, 0, round(side_m), round(side_m))).resize((432, 432), Image.LANCZOS)
    mono = Image.merge("RGBA", [Image.new("L", (432, 432), 255)] * 3 + [a])
    mono.save(OUT / "icon_mono.png", optimize=True)
    # Play / window / legacy icon: a full square, the head big and centred (the knife's blade
    # shows in the lower right); kept inside the cell, so it shifts down if it must.
    side_p = 2.0 * r / PLAY_HEAD
    py = float(np.clip(cy, side_p / 2, shot.height - side_p / 2))
    play = square(shot, cx, py, side_p, 512).convert("RGBA")
    play.save(OUT / "icon.png", optimize=True)
    play.save(SRC / "play_icon_512.png", optimize=True)
    play.resize((192, 192), Image.LANCZOS).save(OUT / "icon_main.png", optimize=True)
    return bg, mono, play


def mask_shape(kind, n):
    """A launcher mask at n x n: circle, squircle (superellipse) or rounded square."""
    big = Image.new("L", (n * 4, n * 4), 0)
    if kind == "circle":
        ImageDraw.Draw(big).ellipse((0, 0, n * 4 - 1, n * 4 - 1), fill=255)
    elif kind == "rounded":
        ImageDraw.Draw(big).rounded_rectangle((0, 0, n * 4 - 1, n * 4 - 1), radius=round(n * 4 * 0.22), fill=255)
    else:
        u = (np.arange(n * 4) + 0.5) / (n * 2) - 1.0
        inside = (np.abs(u)[None, :] ** 5 + np.abs(u)[:, None] ** 5) <= 1.0
        big = Image.fromarray((inside * 255).astype(np.uint8), "L")
    return big.resize((n, n), Image.LANCZOS)


def visible(layer, n):
    """What a launcher shows of a 108 dp layer: its centre 72 dp, at n x n."""
    s = layer.width
    v = round(s * VISIBLE)
    o = (s - v) // 2
    return layer.crop((o, o, o + v, o + v)).resize((n, n), Image.LANCZOS)


def preview(bg, mono, play):
    """Mask sheet. Top row at 512 px: the adaptive icon under circle, squircle and rounded-
    square masks, the Play icon (Google rounds its corners) and the themed monochrome icon.
    Under each: the same at 48 px, and that 48 px icon blown up 3x. Bottom: the background
    and the monochrome layers with the 72 dp window (white) and 66 dp safe circle (yellow)."""
    gap, n = 40, 512
    W = gap + 5 * (n + gap)
    H = gap + n + gap + 160 + gap + 432 + gap
    sheet = Image.new("RGB", (W, H), (36, 38, 48))
    theme = Image.new("RGBA", (432, 432), (205, 226, 255, 255))
    tint = Image.new("RGBA", (432, 432), (20, 52, 110, 255))
    tint.putalpha(mono.getchannel("A"))
    theme.alpha_composite(tint)
    tiles = [(visible(bg, n), k) for k in ["circle", "squircle", "rounded"]]
    tiles += [(play.convert("RGB"), "rounded"), (visible(theme.convert("RGB"), n), "circle")]
    for i, (img, kind) in enumerate(tiles):
        x = gap + i * (n + gap)
        sheet.paste(img.resize((n, n), Image.LANCZOS), (x, gap), mask_shape(kind, n))
        small = img.resize((48, 48), Image.LANCZOS)
        sheet.paste(small, (x + 120, gap + n + gap + 56), mask_shape(kind, 48))
        sheet.paste(small.resize((144, 144), Image.NEAREST), (x + 240, gap + n + gap + 8),
                    mask_shape(kind, 48).resize((144, 144), Image.NEAREST))
    y = gap + n + gap + 160 + gap
    v = 432 * VISIBLE
    sr = 432 * SAFE / 2
    for i, layer in enumerate([bg.convert("RGBA"), mono]):
        tile = Image.new("RGBA", (432, 432), (70, 70, 80, 255))
        tile.alpha_composite(layer)
        d = ImageDraw.Draw(tile)
        d.rectangle(((432 - v) / 2, (432 - v) / 2, (432 + v) / 2, (432 + v) / 2), outline=(255, 255, 255, 255), width=2)
        d.ellipse((216 - sr, 216 - sr, 216 + sr, 216 + sr), outline=(255, 230, 0, 255), width=3)
        sheet.paste(tile.convert("RGB"), (gap + i * (432 + gap), y))
    sheet.save(PROOF / "icon_masks.png")
    print("preview", PROOF / "icon_masks.png")


# ---------------------------------------------------------------- the light-bar

def lightbar():
    """Re-cuts assets/brand/lightbar.png (the loading bar's front) from the v2 brand sheet
    art_src/gen/brand_logo.png (three items on flat green; the light-bar is the lower right)."""
    c = np.asarray(Image.open(GEN / "brand_logo.png").convert("RGB")).astype(np.float64)
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    green = g - np.maximum(r, b)
    alpha = np.clip((95.0 - green) / 50.0, 0.0, 1.0)
    c[..., 1] = np.where(green > 0, g - green * (1.0 - alpha * 0.6), g)
    lab, _ = ndimage.label(ndimage.binary_closing(alpha > 0.5, iterations=6))
    H, W = alpha.shape
    boxes = [sl for sl in ndimage.find_objects(lab)
             if (sl[0].stop - sl[0].start) * (sl[1].stop - sl[1].start) > 0.004 * alpha.size
             and (sl[0].start + sl[0].stop) / 2 >= H * 0.6 and (sl[1].start + sl[1].stop) / 2 >= W / 2]
    y0, y1 = min(s[0].start for s in boxes) - 8, max(s[0].stop for s in boxes) + 8
    x0, x1 = min(s[1].start for s in boxes) - 8, max(s[1].stop for s in boxes) + 8
    a = alpha[y0:y1, x0:x1]
    a = a * ndimage.binary_dilation(a > 0.5, iterations=3)
    img = Image.fromarray(np.dstack([c[y0:y1, x0:x1], a * 255]).astype(np.uint8), "RGBA")
    img.resize((512, round(img.height * 512 / img.width)), Image.LANCZOS).save(OUT / "lightbar.png")


def main():
    for d in (OUT, SRC, PROOF):
        d.mkdir(parents=True, exist_ok=True)
    charge, _ = compose("charge_portrait")
    standoff, rect = compose("standoff_portrait")
    standoff = smear_down(standoff, int(round(rect[1] + rect[3])) - 2)
    for img, name, out in [(charge, "charge_portrait", "keyart_charge.jpg"),
                           (standoff, "standoff_portrait", "keyart_standoff.jpg")]:
        img = to_portrait(img)
        img.save(PROOF / f"full_{name}.png")
        img.resize(PORTRAIT, Image.LANCZOS).save(OUT / out, quality=90, optimize=True, subsampling=0)
        print(out, PORTRAIT, (OUT / out).stat().st_size, "bytes")
    wide, rect = compose("charge_wide")
    wide.save(PROOF / "full_charge_wide.png")
    focus = ((rect[0] + rect[2] / 2) / wide.width, 0.5)
    cover(wide, (1024, 500), focus).save(SRC / "feature_graphic.png", optimize=True)
    print("feature_graphic.png", (SRC / "feature_graphic.png").stat().st_size, "bytes")
    bg, mono, play = icons(cell(1))
    preview(bg, mono, play)
    for p in ["icon.png", "icon_main.png", "icon_bg.png", "icon_fg.png", "icon_mono.png"]:
        print(p, Image.open(OUT / p).size, (OUT / p).stat().st_size, "bytes")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "crop":
        crop(sys.argv[2])
    elif len(sys.argv) > 1 and sys.argv[1] == "pads":
        pads()
    elif len(sys.argv) > 1 and sys.argv[1] == "lightbar":
        lightbar()
    else:
        main()
