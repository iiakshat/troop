"""Cuts the pointing hand (spec v2 §11) out of art_src/gen/hand.png (a 2x2 Gemini sheet on
magenta; cell 0 is used), adds a soft drop shadow and writes assets/ui/hand.png. Prints the
fingertip as a share of the image size; config/hints.json "hand.tip" must match it.
  python -I tools/make_hand.py [cell 0-3]
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from slice_icons import key_alpha, remove_specks  # noqa: E402

SIZE = 256          # output side (px)
SHADOW = (10, 14)   # shadow offset at SIZE (px)


def main() -> None:
    cell = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    a = np.asarray(Image.open(ROOT / "art_src/gen/hand.png").convert("RGB")).astype(float)
    h, w = a.shape[:2]
    r, c = divmod(cell, 2)
    sub = a[r * h // 2:(r + 1) * h // 2, c * w // 2:(c + 1) * w // 2]
    rgb, alpha = key_alpha(sub)
    alpha = remove_specks(alpha, 400)
    lab, n = ndimage.label(alpha > 0.5)
    if n > 1:  # keep the biggest shape only
        sizes = ndimage.sum(np.ones_like(alpha), lab, range(1, n + 1))
        alpha = alpha * ndimage.binary_dilation(lab == (int(np.argmax(sizes)) + 1), iterations=3)
    ys, xs = np.where(alpha > 0.05)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    rgba = np.dstack([rgb, alpha * 255]).astype(np.uint8)[y0:y1, x0:x1]
    hand = Image.fromarray(rgba, "RGBA")
    # Square canvas with room for the shadow (down-right), hand in the upper left part.
    side = int(max(hand.width, hand.height) * 1.1)
    k = SIZE / side
    pad = int(side * 0.02)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sh = Image.new("RGBA", hand.size, (12, 16, 40, 0))
    sh.putalpha(hand.getchannel("A").point(lambda v: int(v * 0.45)))
    off = (pad + int(SHADOW[0] / k), pad + int(SHADOW[1] / k))
    canvas.alpha_composite(sh, off)
    canvas = canvas.filter(ImageFilter.GaussianBlur(int(6 / k)))
    canvas.alpha_composite(hand, (pad, pad))
    out = canvas.resize((SIZE, SIZE), Image.LANCZOS)
    out.save(ROOT / "assets/ui/hand.png")
    # Fingertip: the opaque hand pixel furthest up-left (the finger points up-left).
    al = np.asarray(hand.getchannel("A")) > 128
    yy, xx = np.where(al)
    i = int(np.argmin(xx + yy))
    tip = ((xx[i] + pad) / side, (yy[i] + pad) / side)
    print("tip %.3f %.3f" % tip)


if __name__ == "__main__":
    main()
