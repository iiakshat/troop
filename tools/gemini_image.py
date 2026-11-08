"""Generate one image with Gemini (key: GOOGLE_API_KEY in Troop/.env, a SHARED key).
Ask for sheets (many assets in one image) and keep requests few.

  python -I tools/gemini_image.py <out.png> <aspect e.g. 16:9> <prompt-file.txt> [model]

Raw sheets go in art_src/gen/ (not exported); slicing scripts turn them into assets.
"""
import base64, json, sys, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = "gemini-3-pro-image"


def key() -> str:
    for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
        if line.startswith("GOOGLE_API_KEY="):
            return line.split("=", 1)[1].strip()
    raise SystemExit("GOOGLE_API_KEY missing from .env")


def main() -> None:
    out, aspect, prompt_file = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
    model = sys.argv[4] if len(sys.argv) > 4 else MODEL
    body = {
        "contents": [{"parts": [{"text": prompt_file.read_text(encoding="utf-8")}]}],
        "generationConfig": {"responseModalities": ["IMAGE"],
                             "imageConfig": {"aspectRatio": aspect, "imageSize": "4K"}},
    }
    req = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
        data=json.dumps(body).encode(), method="POST",
        headers={"Content-Type": "application/json", "x-goog-api-key": key()})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
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
