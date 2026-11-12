"""Cuts the Gemini brand sheet (art_src/gen/brand_logo.png, three items on flat green) into
the brand assets, and builds the icons and the Play feature graphic from them.

  python -I tools/slice_brand.py

Writes:
  assets/brand/siren_squad_logo.png   the logo (transparent, 1024 wide)
  assets/brand/lightbar.png           the light-bar alone (loading screen)
  assets/brand/icon_fg.png            adaptive icon foreground, 432x432 (badge in the safe zone)
  assets/brand/icon_bg.png            adaptive icon background, 432x432 (police-blue burst)
  assets/brand/icon_main.png          legacy launcher icon, 192x192 (fg over bg)
  assets/brand/icon.png               window / Play icon, 512x512
  art_src/brand/play_icon_512.png     Play Console hi-res icon (same as icon.png)
  art_src/brand/feature_graphic.png   1024x500; the scene from art_src/gen/brand_feature.png
                                      when it exists, else a drawn siren-light backdrop
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
SHEET = ROOT / "art_src" / "gen" / "brand_logo.png"
SCENE = ROOT / "art_src" / "gen" / "brand_feature.png"
OUT = ROOT / "assets" / "brand"
SRC = ROOT / "art_src" / "brand"
NAVY = (11, 20, 48)
BLUE = (28, 79, 184)


def key_green(c):
    """Alpha from 'greenness' (G - max(R, B)): the flat green background goes clear."""
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    green = g - np.maximum(r, b)
    alpha = np.clip((95.0 - green) / 50.0, 0.0, 1.0)  # >=95 clear, <=45 solid
    # De-spill: green-tinted edge pixels lose their extra green.
    out = c.copy()
    out[..., 1] = np.where(green > 0, g - green * (1.0 - alpha * 0.6), g)
    # Dark green pixels are the art's drop shadow on the green backdrop (nothing in the
    # brand art is green): turn them into a navy shadow whose opacity is how much darker
    # than the backdrop they are.
    back = np.median(g[green >= 95]) if (green >= 95).any() else 255.0
    shade = (green > 8) & (g < back * 0.85)
    alpha = np.where(shade, np.minimum(alpha, np.clip(1.0 - g / back, 0.0, 1.0)), alpha)
    out = np.where(shade[..., None], np.array([6.0, 12.0, 30.0]), out)
    # The dark navy outline picked up a teal cast from the backdrop (green ~ blue): dark
    # pixels keep green at most 0.7 of blue, like the rest of the outline.
    dark = out.max(axis=-1) < 120
    out[..., 1] = np.where(dark, np.minimum(out[..., 1], out[..., 2] * 0.7), out[..., 1])
    return np.clip(out, 0, 255), alpha


def items(alpha):
    """The three items as (y0, y1, x0, x1) boxes: logo (top), badge (bottom left), light-bar."""
    solid = ndimage.binary_closing(alpha > 0.5, iterations=6)
    lab, n = ndimage.label(solid)
    boxes = []
    for sl in ndimage.find_objects(lab):
        h, w = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
        if h * w > 0.004 * alpha.size:
            boxes.append((sl[0].start, sl[0].stop, sl[1].start, sl[1].stop))
    H, W = alpha.shape
    top = [b for b in boxes if (b[0] + b[1]) / 2 < H * 0.6]
    low = [b for b in boxes if (b[0] + b[1]) / 2 >= H * 0.6]
    merge = lambda bs: (min(b[0] for b in bs), max(b[1] for b in bs), min(b[2] for b in bs), max(b[3] for b in bs))
    left = [b for b in low if (b[2] + b[3]) / 2 < W / 2]
    right = [b for b in low if (b[2] + b[3]) / 2 >= W / 2]
    return merge(top), merge(left), merge(right)


def cut(c, alpha, box, pad=8):
    y0, y1, x0, x1 = box
    y0, x0 = max(0, y0 - pad), max(0, x0 - pad)
    y1, x1 = min(alpha.shape[0], y1 + pad), min(alpha.shape[1], x1 + pad)
    a = alpha[y0:y1, x0:x1].copy()
    rgb = c[y0:y1, x0:x1]
    # Keep only the shapes of this item: drop specks from neighbours and the faint keying
    # noise in the clear area (even when the item is a single shape).
    lab, n = ndimage.label(a > 0.5)
    sizes = ndimage.sum(np.ones_like(a), lab, range(1, n + 1))
    keep = np.zeros(n + 1, bool)
    keep[1:] = sizes > sizes.max() * 0.02
    solid = keep[lab]
    a = a * ndimage.binary_dilation(solid, iterations=3)
    return Image.fromarray(np.dstack([rgb, a * 255]).astype(np.uint8), "RGBA")


def fit_width(img, w):
    return img.resize((w, round(img.height * w / img.width)), Image.LANCZOS)


def square(img, side, content):
    """img scaled so its longest side is `content`, centred on a clear side x side canvas."""
    k = content / max(img.width, img.height)
    s = img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(s, ((side - s.width) // 2, (side - s.height) // 2))
    return canvas


def burst(w, h, centre, rays=18):
    """Police-blue radial backdrop with soft light rays (the icon background)."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    cx, cy = centre
    d = np.hypot(xx - cx, yy - cy) / np.hypot(w, h)
    ang = np.arctan2(yy - cy, xx - cx)
    ray = (np.cos(ang * rays) > 0.55) * 0.10 * np.clip(1.0 - d * 1.4, 0, 1)
    t = np.clip(d * 1.7, 0, 1)[..., None]
    inner, outer = np.array([63, 140, 255.0]), np.array(NAVY, float)
    col = inner * (1 - t) + outer * t + ray[..., None] * 255
    return Image.fromarray(np.dstack([np.clip(col, 0, 255), np.full((h, w), 255.0)]).astype(np.uint8), "RGBA")


def glow(w, h, cx, cy, r, rgb, strength):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    a = np.clip(1.0 - np.hypot(xx - cx, yy - cy) / r, 0, 1) ** 2 * strength
    return Image.fromarray(np.dstack([np.full((h, w), c, float) for c in rgb] + [a * 255]).astype(np.uint8), "RGBA")


def feature(logo, badge):
    W, H = 1024, 500
    if SCENE.exists():
        sc = Image.open(SCENE).convert("RGBA")
        k = max(W / sc.width, H / sc.height)
        sc = sc.resize((round(sc.width * k), round(sc.height * k)), Image.LANCZOS)
        y = (sc.height - H) // 2
        x = sc.width - W  # keep the squad (right edge) whole
        img = sc.crop((x, y, x + W, y + H))
        # darken the left so the logo reads
        shade = np.clip(1.0 - np.linspace(0, 1, W) * 1.6, 0, 1) * 0.55
        dark = Image.fromarray(np.dstack([np.full((H, W), c, float) for c in NAVY]
                                         + [np.tile(shade * 255, (H, 1))]).astype(np.uint8), "RGBA")
        img.alpha_composite(dark)
        lx, lw = 40, 470
    else:
        img = burst(W, H, (W / 2, H * 0.55), 28)
        img.alpha_composite(glow(W, H, 120, 120, 420, (40, 120, 255), 0.6))
        img.alpha_composite(glow(W, H, W - 120, 120, 420, (255, 50, 50), 0.55))
        lx, lw = (W - 560) // 2, 560
    lg = fit_width(logo, lw)
    shadow = Image.new("RGBA", lg.size, (0, 0, 0, 0))
    shadow.putalpha(lg.getchannel("A").point(lambda v: v * 0.5))
    shadow = shadow.filter(ImageFilter.GaussianBlur(10))
    ly = (H - lg.height) // 2
    img.alpha_composite(shadow, (lx + 6, ly + 10))
    img.alpha_composite(lg, (lx, ly))
    return img.convert("RGB")


def main():
    c = np.asarray(Image.open(SHEET).convert("RGB")).astype(np.float64)
    c, alpha = key_green(c)
    logo_box, badge_box, bar_box = items(alpha)
    OUT.mkdir(parents=True, exist_ok=True)
    SRC.mkdir(parents=True, exist_ok=True)
    logo = cut(c, alpha, logo_box)
    badge = cut(c, alpha, badge_box)
    bar = cut(c, alpha, bar_box)
    fit_width(logo, 1024).save(OUT / "siren_squad_logo.png")
    fit_width(bar, 512).save(OUT / "lightbar.png")
    badge.save(SRC / "badge.png")
    # Adaptive icon: 108 dp layers; the launcher mask may show only the centre 72 dp (288 of
    # 432 px) and the safe circle is 66 dp (264 px), so the badge (star tips included) fits in it.
    fg = square(badge, 432, 258)
    fg.save(OUT / "icon_fg.png")
    bg = burst(432, 432, (216, 200))
    bg.convert("RGB").save(OUT / "icon_bg.png")
    full = bg.copy()
    full.alpha_composite(square(badge, 432, 330))
    full.resize((192, 192), Image.LANCZOS).save(OUT / "icon_main.png")
    full.resize((512, 512), Image.LANCZOS).save(OUT / "icon.png")
    full.resize((512, 512), Image.LANCZOS).convert("RGB").save(SRC / "play_icon_512.png")
    feature(logo, badge).save(SRC / "feature_graphic.png")
    for p in ["siren_squad_logo.png", "lightbar.png", "icon_fg.png", "icon_bg.png", "icon_main.png", "icon.png"]:
        print(p, Image.open(OUT / p).size)
    print("feature_graphic.png", Image.open(SRC / "feature_graphic.png").size)


if __name__ == "__main__":
    main()
