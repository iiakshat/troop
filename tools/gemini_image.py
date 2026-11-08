"""Generate one image with Gemini (key: GOOGLE_API_KEY in Troop/.env, a SHARED key).
Ask for sheets (many assets in one image) and keep requests few.

  python -I tools/gemini_image.py <out.png> <aspect e.g. 16:9> <prompt-file.txt> [model] [--ref image.png ...]

--ref attaches reference images (style guide, or a sheet to repaint); each is sent as a
downscaled JPEG so the request stays small. The key comes from Troop/.env, or from the file
named by the TROOP_ENV environment variable (git worktrees have no .env of their own).

Raw sheets go in art_src/gen/ (not exported); slicing scripts turn them into assets.
"""
import base64, io, json, os, sys, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = "gemini-3-pro-image"
REF_SIDE = 1536  # longest side of an attached reference image


def key() -> str:
    env = Path(os.environ.get("TROOP_ENV") or ROOT / ".env")
    for line in env.read_text(encoding="utf-8").splitlines():
        if line.startswith("GOOGLE_API_KEY="):
            return line.split("=", 1)[1].strip()
    raise SystemExit("GOOGLE_API_KEY missing from " + env.name)


def ref_part(path: Path) -> dict:
    from PIL import Image
    img = Image.open(path).convert("RGB")
    img.thumbnail((REF_SIDE, REF_SIDE), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=90)
    return {"inlineData": {"mimeType": "image/jpeg", "data": base64.b64encode(buf.getvalue()).decode()}}


def main() -> None:
    args, refs = [], []
    it = iter(sys.argv[1:])
    for a in it:
        if a == "--ref":
            refs.append(Path(next(it)))
        else:
            args.append(a)
    out, aspect, prompt_file = Path(args[0]), args[1], Path(args[2])
    model = args[3] if len(args) > 3 else MODEL
    parts = [ref_part(r) for r in refs] + [{"text": prompt_file.read_text(encoding="utf-8")}]
    body = {
        "contents": [{"parts": parts}],
        "generationConfig": {"responseModalities": ["IMAGE"],
                             "imageConfig": {"aspectRatio": aspect, "imageSize": "4K"}},
    }
    req = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
        data=json.dumps(body).encode(), method="POST",
        headers={"Content-Type": "application/json", "x-goog-api-key": key()})
    try:
        with urllib.request.urlopen(req, timeout=400) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code}: {e.read().decode()[:400]}")
    for cand in data.get("candidates", []):
        for part in cand.get("content", {}).get("parts", []):
            if "inlineData" in part:
                out.parent.mkdir(parents=True, exist_ok=True)
                out.write_bytes(base64.b64decode(part["inlineData"]["data"]))
                print("wrote", out)
                return
    raise SystemExit("no image in response: " + json.dumps(data)[:400])


if __name__ == "__main__":
    main()
