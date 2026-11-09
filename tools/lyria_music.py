"""Music for Troop: generate with Google Lyria, then cut seamless game loops.

The key is GOOGLE_API_KEY in Troop/.env and it is SHARED (art uses it too), so keep
generation requests few (budget: 6 per round). Worktrees have no .env: set TROOP_ENV to
the main checkout's .env. The key is sent in a header and never printed.

  python -I tools/lyria_music.py info [model]                  model metadata (no generation)
  python -I tools/lyria_music.py make <track> [model] [api]     generate raw audio
        track = menu | level | boss (prompts below), api = interactions (default) | generate
        writes _local/music_raw/<track>_<n>.mp3 plus .json (response shape, audio replaced
        by its length) and .txt (any text the model returned)
  python -I tools/lyria_music.py analyse <raw.mp3> [bpm_hint]   tempo, beat grid, loop candidates
  python -I tools/lyria_music.py loop <raw.mp3> <out.ogg> <bpm_hint> <bars> [start_bar]
        cut <bars> whole bars starting at bar <start_bar> (default: the best-matching seam),
        crossfade the loop point, normalise to -14 LUFS and write OGG Vorbis

The shipped loops: music_menu / music_level / music_boss.ogg in assets/audio (see
docs/assets_audio.md for the exact commands). Needs ffmpeg (FFMPEG env or the winget path
below) and numpy.
"""
import base64, json, os, subprocess, sys, time, urllib.error, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
API = "https://generativelanguage.googleapis.com/v1beta"
API_REVISION = "2026-05-20"
MODEL = "lyria-3-clip-preview"
RAW_DIR = ROOT / "_local" / "music_raw"
FFMPEG = os.environ.get("FFMPEG") or (
    "C:/Users/Akshat/AppData/Local/Microsoft/WinGet/Packages/"
    "Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-9.0.2-full_build/bin/ffmpeg.exe")
SR = 44100
TARGET_LUFS = -14.0
PEAK_CEILING_DB = -1.0
VORBIS_QUALITY = "4"  # ~128 kbps stereo

# One hook family for all three tracks: same tempo, same key, same whistle motif.
HOOK = ("THE HOOK: a cheeky, instantly hummable two-bar whistled melody (real human "
        "whistle doubled by a bright plucky synth) that bounces up a minor-pentatonic "
        "figure, answers itself one step lower, and repeats every four bars so it gets "
        "stuck in your head like a ringtone.")
COMMON = ("Original instrumental for a mobile arcade game about a street squad. Tempo "
          "104 BPM, steady and unchanging, key of A minor with a bright, playful feel. "
          "Strictly instrumental: no sung words or lyrics, only short wordless group "
          "shouts like 'hey!' and hums. No fade-in, no fade-out, no tempo changes, no "
          "silence; the groove must stay consistent so it can be looped. ")
PROMPTS = {
    "menu": COMMON + HOOK + (
        " Style: catchy urban hip-hop meets electro-pop, sunny city streets, skateboard "
        "swagger. Bouncy head-nod beat with a crisp snare, snappy claps and swung "
        "hi-hats, warm round sub bass, marimba and plucked synth counter-melody, a few "
        "vinyl scratches as ear candy. Medium energy, confident, cheerful and addictive."),
    "level": COMMON + HOOK + (
        " Style: high-energy hip-hop chase beat for running and shooting through city "
        "streets, the same playful vibe as a menu theme but pushed harder: punchy "
        "boom-bap kick and cracking snare with trap hi-hat rolls, big bouncy 808 bass, "
        "hand claps, marimba and steel-drum counter-melody, the whistle hook doubled by a "
        "bright synth lead, DJ scratches and group 'hey!' shouts. Not four-on-the-floor, "
        "not disco, not EDM: a skate-park street groove with relentless energy, euphoric "
        "and addictive like the best endless-runner themes, no breakdowns."),
    "boss": COMMON + HOOK.replace("cheeky, instantly hummable", "menacing, darker") + (
        " Style: tense boss-battle version of the same urban electro hip-hop theme. "
        "Heavier, distorted 808 bass and huge punchy drums with big tom hits and "
        "trap-style rolling hats, low brass-like synth stabs, ticking-clock percussion, "
        "the whistle motif played in a darker register by a gritty synth, a wordless "
        "low male chant. Dangerous but still catchy and groovy, not orchestral, not "
        "horror. Constant high intensity."),
}
# Lyria 3.5 makes ~2-minute songs stitched from chunks (its beat grid jumps by a 16th note
# every ~15-30 s), so loops cut from it are risky. The clip model makes one 30 s piece on a
# rock-steady grid: ask it for a single loopable section and cut whole bars from it.
FORM = {
    "clip": (" Form: one continuous 30-second loopable section. Start on the first "
             "downbeat at full arrangement (no intro, no build-up), keep the same groove "
             "and the hook throughout in strict 4-bar phrases, and stop mid-groove (no "
             "ending, no fade)."),
    "song": (" Form: a 2-minute track. [0:00 - 0:04] straight into the groove; [0:04 - 2:00] "
             "full groove, the hook every 8 bars with small variations, answer phrases in "
             "between, no breakdowns."),
}


# ---------------------------------------------------------------- generation

def key() -> str:
    env = Path(os.environ.get("TROOP_ENV") or (ROOT / ".env"))
    if not env.exists():
        raise SystemExit(f"no .env at {env}; set TROOP_ENV to the main checkout's .env")
    for line in env.read_text(encoding="utf-8").splitlines():
        if line.startswith("GOOGLE_API_KEY="):
            return line.split("=", 1)[1].strip()
    raise SystemExit("GOOGLE_API_KEY missing from .env")


def call(url: str, body: dict | None = None, timeout: int = 900) -> dict:
    headers = {"x-goog-api-key": key(), "Api-Revision": API_REVISION}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method="POST" if body is not None else "GET",
                                 headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code}: {e.read().decode(errors='replace')[:600]}")


def shape(x):
    """The response with long strings (audio) replaced by their length, for inspection."""
    if isinstance(x, dict):
        return {k: shape(v) for k, v in x.items()}
    if isinstance(x, list):
        return [shape(v) for v in x]
    if isinstance(x, str) and len(x) > 300:
        return f"<str len {len(x)}>"
    return x


def find_audio(x, found: list, texts: list) -> None:
    """Collect (mime, base64) audio blobs and text from either API's response."""
    if isinstance(x, dict):
        blob = x.get("inlineData") or x.get("inline_data")
        if isinstance(blob, dict) and "data" in blob:
            found.append((blob.get("mimeType") or blob.get("mime_type") or "", blob["data"]))
        elif x.get("type") == "audio" and isinstance(x.get("data"), str):
            found.append((x.get("mime_type") or x.get("mimeType") or "", x["data"]))
        if isinstance(x.get("text"), str):
            texts.append(x["text"])
        for k, v in x.items():
            if k not in ("inlineData", "inline_data"):
                find_audio(v, found, texts)
    elif isinstance(x, list):
        for v in x:
            find_audio(v, found, texts)


def info(model: str) -> None:
    m = call(f"{API}/models/{model}")
    print(json.dumps({k: m.get(k) for k in ("name", "displayName", "description",
                                             "supportedGenerationMethods",
                                             "inputTokenLimit", "outputTokenLimit")}, indent=1))


def make(track: str, model: str, api: str) -> None:
    prompt = PROMPTS[track] + FORM["clip" if "clip" in model else "song"]
    if api == "generate":
        data = call(f"{API}/models/{model}:generateContent",
                    {"contents": [{"parts": [{"text": prompt}]}]})
    else:
        # Interactions API (the documented route for Lyria 3); sync unless still running.
        data = call(f"{API}/interactions", {"model": model, "input": prompt})
        t0 = time.time()
        while data.get("status") in ("in_progress", "queued", "running") and data.get("id"):
            if time.time() - t0 > 900:
                raise SystemExit("timed out waiting for interaction " + str(data.get("id")))
            time.sleep(10)
            data = call(f"{API}/interactions/{data['id']}")  # polling, not a new generation
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    n = 1
    while (RAW_DIR / f"{track}_{n}.json").exists():
        n += 1
    base = RAW_DIR / f"{track}_{n}"
    base.with_suffix(".json").write_text(json.dumps(shape(data), indent=1), encoding="utf-8")
    base.with_suffix(".prompt").write_text(f"{model}\n{prompt}\n", encoding="utf-8")
    found, texts = [], []
    find_audio(data, found, texts)
    if texts:
        base.with_suffix(".txt").write_text("\n\n".join(texts), encoding="utf-8")
    if not found:
        raise SystemExit(f"no audio in response; shape saved to {base}.json")
    for i, (mime, b64) in enumerate(found):
        raw = base64.b64decode(b64)
        ext = ".wav" if ("wav" in mime or raw[:4] == b"RIFF") else ".mp3"
        out = base.with_name(base.name + (f"_{i}" if i else "") + ext)
        out.write_bytes(raw)
        print("wrote", out, mime, len(raw), "bytes")


# ---------------------------------------------------------------- analysis

def decode(path: str):
    import numpy as np
    pcm = subprocess.run([FFMPEG, "-v", "error", "-i", path, "-f", "f32le", "-ac", "2",
                          "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    return np.frombuffer(pcm, dtype=np.float32).reshape(-1, 2).copy()


HOP = 64  # 1.45 ms frames: fine enough to line loop points up with drum hits
NFFT = 1024


def features(x):
    """Per-frame onset strength (total and per band) and an 8-band log spectrum."""
    import numpy as np
    mono = x.mean(axis=1)
    frames = 1 + (len(mono) - NFFT) // HOP
    freqs = np.fft.rfftfreq(NFFT, 1.0 / SR)
    edges = np.geomspace(40, 16000, 9)
    masks = [(freqs >= lo) & (freqs < hi) for lo, hi in zip(edges[:-1], edges[1:])]
    win = np.hanning(NFFT)
    parts = []
    for c0 in range(0, frames, 4096):  # chunked to keep memory low
        c1 = min(frames, c0 + 4096)
        idx = np.arange(NFFT)[None, :] + HOP * np.arange(c0, c1)[:, None]
        spec = np.abs(np.fft.rfft(mono[idx] * win, axis=1))
        parts.append(np.log1p(np.stack([spec[:, m].sum(axis=1) for m in masks], axis=1) * 5.0))
    logb = np.concatenate(parts)
    bflux = np.maximum(np.diff(logb, axis=0, prepend=logb[:1]), 0.0)
    flux = bflux.sum(axis=1)
    flux = np.maximum(flux - np.convolve(flux, np.ones(400) / 400, mode="same"), 0.0)
    return flux, bflux, logb


def frame_time(i):
    return (i + NFFT / 2 / HOP) * HOP / SR


def tempo(flux, hint: float) -> float:
    """BPM from the onset autocorrelation, refined on the longest whole-bar lag."""
    import numpy as np
    fps = SR / HOP
    N = len(flux)
    f = np.fft.rfft(flux - flux.mean(), 2 * N)
    ac = np.fft.irfft(f * np.conj(f))[:N]
    bpm = hint
    for bars in (1, 2, 4, 8, 16):
        lag0 = bars * 240.0 / bpm * fps
        if lag0 * 1.02 >= N * 0.7:
            break
        lo, hi = int(lag0 * 0.985), int(lag0 * 1.015) + 1
        k = lo + int(np.argmax(ac[lo:hi]))
        y0, y1, y2 = ac[k - 1], ac[k], ac[k + 1]
        lag = (k + 0.5 * (y0 - y2) / (y0 - 2 * y1 + y2 + 1e-12)) / fps
        bpm = bars * 240.0 / lag
    return float(bpm)


def grid_phase(flux, bpm: float, t0: float = 0.0, t1: float = 1e9, div: int = 1) -> float:
    """Time of the first beat (mod one grid step) by complex demodulation of the onsets."""
    import numpy as np
    t = frame_time(np.arange(len(flux)))
    period = 60.0 / bpm / div
    m = (t >= t0) & (t < t1)
    z = (flux[m] * np.exp(-2j * np.pi * t[m] / period)).sum()
    return float((np.angle(z) / (2 * np.pi) * period) % period)


def grid_drift(flux, bpm: float, win: float = 2.0) -> float:
    """Largest offset of the 16th-note grid in any 2 s window (ms). Chunk seams show here."""
    import numpy as np
    dur = frame_time(len(flux))
    period = 15.0 / bpm
    ref = grid_phase(flux, bpm, div=4)
    devs = [abs((grid_phase(flux, bpm, c, c + win, div=4) - ref + period / 2) % period
                - period / 2) for c in np.arange(0.0, dur - win, win)]
    return 1000.0 * max(devs) if devs else 0.0


def downbeat(logb, flux, bpm: float, phase: float, dur: float) -> float:
    """Pick which beat is beat 1: the sound changes most across bar lines."""
    import numpy as np
    fps = SR / HOP
    beat = 60.0 / bpm
    h = int(beat * fps)
    best = (-1.0, phase)
    for k in range(4):
        start = phase + k * beat
        score, cnt = 0.0, 0
        t = start + 4 * beat
        while t + 2 * beat < dur:
            i = int(t * fps)
            score += float(np.abs(logb[i:i + h].mean(axis=0) - logb[i - h:i].mean(axis=0)).sum())
            cnt += 1
            t += 4 * beat
        if cnt and score / cnt > best[0]:
            best = (score / cnt, start % (4 * beat))
    return best[1]


def seam_score(bflux, logb, a: float, b: float, length: float) -> float:
    """How alike the music after times a and b is (1 = identical)."""
    import numpy as np
    fps = SR / HOP
    ia, ib, n = int(round(a * fps)), int(round(b * fps)), int(length * fps)
    if min(ia, ib) < 0 or max(ia, ib) + n > len(logb) or n <= 0:
        return -1.0
    fa, fb = bflux[ia:ia + n], bflux[ib:ib + n]
    c1 = (fa * fb).sum() / (np.linalg.norm(fa) * np.linalg.norm(fb) + 1e-9)
    la, lb = logb[ia:ia + n], logb[ib:ib + n]
    la, lb = la - la.mean(axis=0), lb - lb.mean(axis=0)
    c2 = (la * lb).sum() / (np.linalg.norm(la) * np.linalg.norm(lb) + 1e-9)
    return float(0.6 * c1 + 0.4 * c2)


def grid(x, bpm_hint: float):
    """(bpm, first downbeat time, bar length, flux, band flux, log bands)."""
    flux, bflux, logb = features(x)
    bpm = tempo(flux, bpm_hint)
    phase = grid_phase(flux, bpm)
    db = downbeat(logb, flux, bpm, phase, len(x) / SR)
    return bpm, db, 240.0 / bpm, flux, bflux, logb


def loop_candidates(x, bpm, db, bar, bflux, logb, bars: int):
    """(score, pre, post, start_bar) for every whole-bar loop of length `bars`, best first.
    pre compares the bar before the start with the bar before the end, post the bar after."""
    dur = len(x) / SR
    out = []
    i = 0
    while db + (i + bars) * bar + 60.0 / bpm <= dur:
        S, E = db + i * bar, db + (i + bars) * bar
        post = seam_score(bflux, logb, S, E, min(bar, dur - E - 0.03))
        pre = seam_score(bflux, logb, S - bar, E - bar, bar) if S >= bar else post
        out.append((0.5 * (pre + post), pre, post, i))
        i += 1
    return sorted(out, reverse=True)


def lufs(x) -> float:
    """Integrated loudness via ffmpeg's EBU R128 meter."""
    import numpy as np
    p = subprocess.run([FFMPEG, "-hide_banner", "-nostats", "-f", "f32le", "-ac", "2",
                        "-ar", str(SR), "-i", "-", "-af", "ebur128=peak=true", "-f", "null",
                        "-"], input=x.astype(np.float32).tobytes(), capture_output=True)
    txt = p.stderr.decode(errors="replace")
    for line in txt[txt.rfind("Summary:"):].splitlines():
        if line.strip().startswith("I:"):
            return float(line.split()[1])
    raise SystemExit("could not measure loudness")


def analyse(path: str, bpm_hint: float) -> None:
    import numpy as np
    x = decode(path)
    dur = len(x) / SR
    bpm, db, bar, flux, bflux, logb = grid(x, bpm_hint)
    print(f"{path}: {dur:.2f} s, peak {20*np.log10(np.abs(x).max()+1e-9):.2f} dBFS, "
          f"{lufs(x):.1f} LUFS")
    print(f"tempo {bpm:.3f} BPM (bar {bar:.4f} s), first downbeat {db:.3f} s, worst "
          f"16th-grid drift {grid_drift(flux, bpm):.0f} ms (above ~25 = chunk seams)")
    nb = int((dur - db) / bar)
    rms = [10 * np.log10((x[int((db + i * bar) * SR):int((db + (i + 1) * bar) * SR)] ** 2)
                         .mean() + 1e-12) for i in range(nb)]
    print("bar RMS dB:", " ".join(f"{i}:{r:.0f}" for i, r in enumerate(rms)))
    for bars in (4, 6, 8, 10, 12, 16, 24):
        c = loop_candidates(x, bpm, db, bar, bflux, logb, bars)
        if c:
            print(f"{bars:2d} bars ({bars*bar:5.1f} s):", ", ".join(
                f"bar {i} {s:.3f} (pre {p:.2f} post {q:.2f})" for s, p, q, i in c[:4]))


def loop(path: str, out: str, bpm_hint: float, bars: int, start_bar: int | None) -> None:
    import numpy as np
    x = decode(path)
    bpm, db, bar, flux, bflux, logb = grid(x, bpm_hint)
    cands = loop_candidates(x, bpm, db, bar, bflux, logb, bars)
    if start_bar is None:
        start_bar = cands[0][3]
    score = next(c[0] for c in cands if c[3] == start_bar)
    a = int(round((db + start_bar * bar) * SR))
    L = int(round(bars * bar * SR))
    F = int(round(60.0 / bpm / 2 * SR))  # half-beat crossfade
    seg = x[a:a + L + F]
    if len(seg) < L + F:
        raise SystemExit("loop runs past the end of the audio")
    head, tail = seg[:F], seg[L:L + F]
    corr = float((head * tail).sum() / (np.sqrt((head ** 2).sum() * (tail ** 2).sum()) + 1e-9))
    t = np.linspace(0.0, 1.0, F, endpoint=False)[:, None]
    if corr > 0.5:  # alike: constant-amplitude fade
        fi, fo = 0.5 - 0.5 * np.cos(np.pi * t), 0.5 + 0.5 * np.cos(np.pi * t)
    else:           # different: constant-power fade
        fi, fo = np.sin(0.5 * np.pi * t), np.cos(0.5 * np.pi * t)
    y = seg[:L].copy()
    y[:F] = head * fi + tail * fo
    # The wrap goes y[L-1] = x[a+L-1] -> y[0] ~ x[a+L]: continuous by construction, then
    # the first half beat fades from the continuation into the loop start.
    gain = 10 ** ((TARGET_LUFS - lufs(np.concatenate([y, y]))) / 20.0)
    y *= gain
    ceiling = 10 ** (PEAK_CEILING_DB / 20.0)
    k = ceiling * 0.9
    over = np.abs(y) > k
    if over.any():  # stateless soft knee (no limiter memory), so the loop stays seamless
        r = ceiling - k
        y = np.where(over, np.sign(y) * (k + r * np.tanh((np.abs(y) - k) / r)), y)
    steps = np.abs(np.diff(y, axis=0)).max(axis=1)
    wrap = float(np.abs(y[0] - y[-1]).max())
    print(f"{bpm:.3f} BPM, loop from {(db + start_bar * bar):.3f}s (bar {start_bar}), {bars} "
          f"bars = {L / SR:.3f}s, seam score {score:.3f}, head/tail corr {corr:.2f}, gain "
          f"{20 * np.log10(gain):+.1f} dB, peak {20 * np.log10(np.abs(y).max()):.2f} dBFS, "
          f"wrap step {wrap:.4f} (99.9th pct step {np.percentile(steps, 99.9):.4f})")
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([FFMPEG, "-v", "error", "-y", "-f", "f32le", "-ac", "2", "-ar", str(SR),
                    "-i", "-", "-c:a", "libvorbis", "-q:a", VORBIS_QUALITY, out],
                   input=y.astype(np.float32).tobytes(), check=True)
    z = decode(out)
    print("wrote", out, f"{Path(out).stat().st_size / 1024:.0f} KB, {len(z) / SR:.3f} s, "
          f"{lufs(z):.1f} LUFS, peak {20 * np.log10(np.abs(z).max()):.2f} dBFS")


def main() -> None:
    a = sys.argv[1:]
    if not a:
        raise SystemExit(__doc__)
    if a[0] == "info":
        info(a[1] if len(a) > 1 else MODEL)
    elif a[0] == "make":
        make(a[1], a[2] if len(a) > 2 else MODEL, a[3] if len(a) > 3 else "interactions")
    elif a[0] == "analyse":
        analyse(a[1], float(a[2]) if len(a) > 2 else 104.0)
    elif a[0] == "loop":
        loop(a[1], a[2], float(a[3]), int(a[4]), int(a[5]) if len(a) > 5 else None)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
