"""Night window masks for the painted facades.

For each assets/env/tex/facade_N.png writes assets/env/tex/facade_N_night.png: a small
grayscale emission mask where every pane of window glass gets its own brightness (most lit
warm, some dark), so World can switch the windows on at dusk and night with a plain
StandardMaterial3D emission texture. Deterministic (fixed seed per facade).

usage: python -I tools/make_window_masks.py [debug_sheet.png]
"""
import random
import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter

TEX = Path(__file__).resolve().parent.parent / "assets" / "env" / "tex"
W, H = 256, 640          # mask size (the facades are 1024 x 2560)
MIN_AREA = 40            # pixels at mask size; smaller blobs are reflections or noise
LIT_SHARE = 0.72         # share of panes that are lit


def is_glass(p):
    r, g, b = p
    return b - r >= 18 and b - g >= 7 and g >= r - 4 and 60 <= b <= 205


def components(mask):
    seen = bytearray(W * H)
    out = []
    for start in range(W * H):
        if not mask[start] or seen[start]:
            continue
        q = deque([start])
        seen[start] = 1
        pix = []
        while q:
            i = q.popleft()
            pix.append(i)
            x, y = i % W, i // W
            for j in ((i - 1) if x > 0 else -1, (i + 1) if x < W - 1 else -1,
                      (i - W) if y > 0 else -1, (i + W) if y < H - 1 else -1):
                if j >= 0 and mask[j] and not seen[j]:
                    seen[j] = 1
                    q.append(j)
        out.append(pix)
    return out


def make(n):
    src = Image.open(TEX / f"facade_{n}.png").convert("RGB").resize((W, H), Image.BILINEAR)
    px = src.load()
    glass = bytearray(1 if is_glass(px[i % W, i // W]) else 0 for i in range(W * H))
    # Panes of one window share its light: group them by joining across thin frames.
    grow = Image.frombytes("L", (W, H), bytes(v * 255 for v in glass)).filter(ImageFilter.MaxFilter(7))
    joined = bytearray(1 if v else 0 for v in grow.tobytes())
    rng = random.Random(1000 + n)
    out = bytearray(W * H)
    for window in components(joined):
        comp = [i for i in window if glass[i]]
        xs = [i % W for i in comp]
        ys = [i // W for i in comp]
        if len(comp) < MIN_AREA or max(xs) - min(xs) < 5 or max(ys) - min(ys) < 5:
            continue
        y0, y1 = min(ys), max(ys)
        lit = rng.random() < LIT_SHARE
        level = rng.uniform(0.6, 1.0) if lit else rng.uniform(0.0, 0.07)
        for i in comp:
            # a lamp inside: a touch brighter towards the top of the pane
            t = (i // W - y0) / max(y1 - y0, 1)
            out[i] = int(255 * level * (1.0 - 0.25 * t))
    img = Image.frombytes("L", (W, H), bytes(out)).filter(ImageFilter.GaussianBlur(0.8))
    img.save(TEX / f"facade_{n}_night.png", optimize=True)
    return src, img


def main():
    pairs = [make(n) for n in range(1, 5)]
    if len(sys.argv) > 1:
        sheet = Image.new("RGB", (W * 8, H))
        for k, (src, img) in enumerate(pairs):
            sheet.paste(src, (k * 2 * W, 0))
            sheet.paste(img.convert("RGB"), ((k * 2 + 1) * W, 0))
        sheet.resize((W * 4, H // 2)).save(sys.argv[1])


if __name__ == "__main__":
    main()
