"""Build Troop's sound effects from downloaded CC0 / CC BY recordings.

  python -I tools/make_sfx.py <downloads_dir> [id ...]      build all ids, or just these
  python -I tools/make_sfx.py <downloads_dir> --list         show which ids have recipes

<downloads_dir> holds the OpenGameArt packs, each unpacked into its own folder named as in
SOURCES below (URLs and licences: docs/assets_audio.md). Downloads are data: this script
only decodes them with ffmpeg, it never runs anything from them.

Each id is a list of takes (id.ogg, id2.ogg, id3.ogg ... which Sfx plays in turn). A take
is a list of layers mixed together; a layer is a slice of one recording, optionally pitched
(semitones; pitch and speed move together, like a tape), filtered, delayed and gained. The
mix is trimmed, faded, levelled to the id's loudness, kept under -1 dBFS and written as mono
44.1 kHz OGG Vorbis into assets/audio. Needs ffmpeg (FFMPEG env or the winget path), numpy
and scipy.
"""
import glob, os, subprocess, sys
from pathlib import Path

import numpy as np
from scipy import signal

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio"
FFMPEG = os.environ.get("FFMPEG") or (
    "C:/Users/Akshat/AppData/Local/Microsoft/WinGet/Packages/"
    "Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-9.0.2-full_build/bin/ffmpeg.exe")
SR = 44100
PEAK_DB = -1.0
VORBIS_Q = "5"

# Folder name -> (OpenGameArt file, author, licence). The folder holds the file, and zips/7z
# are unpacked into <folder>/x/.
SOURCES = {
    "gravity": ("Wikimedia Commons: Glass_breaking_(Gravity_Sound).wav, _2_, _3_, _4_ saved as "
                "g1..g4.wav", "Gravity Sound", "CC BY 4.0"),
    "bottle": ("Bottle%20Break.wav", "spookymodem", "CC BY 3.0"),
    "breaking75": ("sfx_breaking_and_falling.zip", "rubberduck", "CC0"),
    "ice": ("IceShatters_0.zip", "ignasd", "CC0"),
    "emopain": ("painsounds.zip", "EmoPreben", "CC0"),
    "slight": ("slightscreams.7z", "qubodup", "CC0"),
    "yell": ("yelling%20sounds.zip", "HaelDB", "CC0"),
    "qpunch": ("qubodupPunch.7z", "qubodup", "CC0"),
    "ljudhits": ("independent_nu_ljudbank-hits_and_punches.7z", "qubodup", "CC0"),
    "chunky": ("Chunky%20Explosion.mp3", "Joth", "CC0"),
    "expl_tw": ("explosion.wav", "TinyWorlds", "CC0"),
    "bangs": ("25-CC0-bang-sfx.zip", "rubberduck", "CC0"),
    "scifi": ("sci-fi_sounds.zip", "Kenney", "CC0"),
    "roar": ("monster_roar.wav", "trazzz123", "CC0"),
    "rpg80": ("80-CC0-RPG-SFX_0.zip", "rubberduck", "CC0"),
    "flame": ("flame_0.ogg", "themightyglider", "CC0"),
    "ignition": ("ignition.flac", "qubodup", "CC0"),
    "hammer": ("craft_0.ogg", "themightyglider", "CC0"),
    "woodmetal": ("100-CC0-wood-metal-SFX.zip", "rubberduck", "CC0"),
    "rd100": ("100-CC0-SFX_0.zip", "rubberduck", "CC0"),
    "starcoins": ("coins_-_starninjas.zip", "starninjas", "CC0"),
    "rpgk": ("RPGsounds_Kenney.zip", "Kenney", "CC0"),
    "iface": ("kenney_interfaceSounds.zip", "Kenney", "CC0"),
    "jingles": ("jingleSounds_Kenney.zip", "Kenney", "CC0"),
    "gem": ("gem-gather-mono-files.zip", "bobjt", "CC0"),
    "chest": ("open%20chest_0.wav", "oiboo", "CC0"),
    "fanfare": ("fanfare_3.ogg", "fvcalderan", "CC0"),
    "swishes": ("swishes.zip", "artisticdude", "CC0"),
    "guns": ("sounds.zip", "Vincent Sevedge (Tabasco)", "CC BY 3.0"),
    "thwack": ("thwack-1.0.zip", "qubodup", "CC0"),
}


def L(src, start=0.0, dur=None, delay=0.0, gain=0.0, st=0.0, hp=None, lp=None, fade=None,
      notes=None):
    """One layer: <dur> s of <src> from <start>, placed at <delay> s in the take.
    With notes = [(time s, Hz, gain 0..1)], the layer is the recording re-tuned to each note
    (tape-style, from BELL_HZ) and played at each time: a real bell turned into a chime."""
    return dict(src=src, start=start, dur=dur, delay=delay, gain=gain, st=st, hp=hp, lp=lp,
                fade=fade, notes=notes)


# The chime: one strike of a small real bell (rubberduck's bell_02, CC0), whose strongest
# partial is 2908 Hz. Every reward sound re-tunes this one bell, so they are one family.
BELL = "rd100/" + "**/bell_02.ogg"
BELL_HZ = 2908.3
# Chime notes: C major, the relative major of the music's A minor.
C6, E6, G6, A6, B6 = 1046.50, 1318.51, 1567.98, 1760.00, 1975.53
C7, D7, E7, G7 = 2093.00, 2349.32, 2637.02, 3135.96
G = "**/"  # any depth inside a pack folder
EMO = "emopain/" + G + "Painsounds v2 - Track "


def chime(notes, delay=0.0, gain=0.0):
    return L(BELL, notes=notes, delay=delay, gain=gain, hp=400)


# id -> (takes, options). Options: level (dB RMS of the loudest 50 ms, default -14), tail
# (fade-out seconds, default 0.05), max (cut the take at this length), squeeze (dB of
# peak gain the leveller may give up before it soft-clips the rest, default 4).
#
# Mix plan (loudest 50 ms of the file; callers and Sfx.TRIM_DB add their own dB on top):
#   big gameplay moments (glass, boom, roar)  -11 .. -12
#   weapons and body hits                     -12 .. -15
#   rewards and UI                            -14 .. -16  (never above the hits)
#   ticks and taps                            -19 .. -20
RECIPES = {
    # --- glass (Bottle Shot): real bottles smashing (Gravity Sound and spookymodem
    # recordings) over a soft low knock for weight, then shards settling.
    "glass_break": ([
        [L("gravity/g1.wav"),
         L("ljudhits/" + G + "hit22.mp3.flac", lp=700, gain=-12.0),
         L("breaking75/" + G + "bfh1_glass_falling_02.ogg", delay=0.32, gain=-11.0)],
        [L("gravity/g4.wav"),
         L("ljudhits/" + G + "hit24.mp3.flac", lp=700, gain=-12.0),
         L("breaking75/" + G + "bfh1_glass_falling_04.ogg", delay=0.30, gain=-11.0)],
        [L("gravity/g2.wav"),
         L("ljudhits/" + G + "hit22.mp3.flac", lp=700, gain=-12.0),
         L("ice/" + G + "LedasLuzta4.ogg", delay=0.28, gain=-13.0, hp=1500)],
        [L("bottle/Bottle_Break.wav", start=0.30, hp=150),
         L("ljudhits/" + G + "hit24.mp3.flac", lp=700, gain=-13.0)],
    ], dict(level=-13.0, tail=0.15, max=1.3, squeeze=1.0)),
    "glass_tinkle": ([
        [L("breaking75/" + G + "bfh1_glass_falling_02.ogg")],
        [L("breaking75/" + G + "bfh1_glass_falling_04.ogg")],
        [L("ice/" + G + "LedasLuzta4.ogg", hp=1500)],
    ], dict(level=-17.0, tail=0.15)),
    # --- guns the existing recordings don't cover (Tabasco's mosin and shotgun takes)
    "shot_sniper": ([
        [L("guns/" + G + "mosin.wav", start=5.92, dur=1.25)],
        [L("guns/" + G + "mosin.wav", start=8.79, dur=1.25)],
    ], dict(level=-12.0, tail=0.4)),
    "shot_shotgun": ([
        [L("guns/" + G + "shotty.wav")],
        [L("guns/" + G + "shotty.wav", st=1.0)],
    ], dict(level=-12.0, tail=0.15)),
    "snipe": ([  # the enemy sniper: a duller, distant crack
        [L("guns/" + G + "mosin.wav", start=12.12, dur=1.1, hp=200, lp=5000)],
        [L("guns/" + G + "mosin.wav", start=3.50, dur=1.1, hp=200, lp=5000)],
    ], dict(level=-13.0, tail=0.4)),
    "launcher": ([  # grenade launcher "thoomp"
        [L("bangs/" + G + "cannon_01.ogg", st=3.0, hp=90)],
        [L("bangs/" + G + "cannon_04.ogg", st=3.0, hp=90)],
    ], dict(level=-13.0, tail=0.2, max=0.7)),
    # --- explosions: a meaty boom with a crunchy top
    "boom": ([
        [L("chunky/Chunky_Explosion.mp3", dur=2.2),
         L("scifi/" + G + "explosionCrunch_000.ogg", gain=-5.0)],
        [L("scifi/" + G + "explosionCrunch_001.ogg"),
         L("scifi/" + G + "lowFrequency_explosion_001.ogg", gain=-4.0)],
        [L("expl_tw/explosion.wav"),
         L("scifi/" + G + "explosionCrunch_004.ogg", gain=-6.0)],
    ], dict(level=-11.0, tail=0.6, max=2.0)),
    # --- bodies: real punches, short impacts; a kill is a thwack, not a scream
    "punch": ([[L("qpunch/" + G + f"qubodupPunch0{i}.flac")] for i in (1, 3, 4, 5)],
              dict(level=-13.0, tail=0.08, max=0.35)),
    "hit": ([[L("ljudhits/" + G + f"hit{i}.mp3.flac", hp=120)] for i in (10, 15, 28)],
            dict(level=-15.0, tail=0.06, max=0.22)),
    "die": ([[L("thwack/" + G + f"thwack-{i:02d}.wav", hp=90)] for i in (3, 5, 6)],
            dict(level=-14.0, tail=0.06, max=0.25)),
    "hurt": ([[L("slight/" + G + f"slightscream-{i:02d}.flac", hp=110)] for i in (1, 3, 8)],
             dict(level=-15.0, tail=0.08, max=0.45)),
    "blocked": ([[L("woodmetal/" + G + f"metal_hit_0{i}.ogg", hp=300)] for i in (1, 3)],
                dict(level=-15.0, tail=0.08, max=0.4)),
    "pothole": ([  # a heavy thud and a groan
        [L("ljudhits/" + G + "hit22.mp3.flac", hp=60),
         L(EMO + "3*", delay=0.07, gain=-2.0, hp=110)],
        [L("ljudhits/" + G + "hit34.mp3.flac", hp=60),
         L(EMO + "4*", delay=0.07, gain=-2.0, hp=110)],
    ], dict(level=-13.0, tail=0.12, max=0.9)),
    "boss_roar": ([  # a big angry man, pitched down, with a beast underneath
        [L("yell/" + G + "yell4.wav", st=-3.0, hp=80),
         L("roar/monster_roar.wav", start=0.35, dur=1.5, gain=-6.0, fade=0.4)],
        [L("yell/" + G + "yell2.wav", st=-3.0, hp=80),
         L("rpg80/" + G + "creature_roar_02.ogg", gain=-6.0)],
    ], dict(level=-11.0, tail=0.35, max=1.9)),
    # --- fire, shield, knife
    "fire": ([
        [L("flame/flame_0.ogg"), L("ignition/ignition.flac", gain=-8.0)],
        [L("rpg80/" + G + "spell_fire_06.ogg")],
        [L("rpg80/" + G + "spell_fire_04.ogg")],
    ], dict(level=-14.0, tail=0.25, max=1.2)),
    "shield": ([[L("scifi/" + G + "forceField_002.ogg")]], dict(level=-15.0, tail=0.2)),
    # One take, one pitch (Sfx gives the knife no pitch spread): the owner wants the same
    # clean whoosh every throw.
    "knife": ([[L("swishes/" + G + "swish-9.wav", hp=250)]], dict(level=-16.0, tail=0.03)),
    # --- city building
    "build": ([
        [L("hammer/craft_0.ogg")],
        [L("woodmetal/" + G + "wood_hammer_01.ogg"),
         L("woodmetal/" + G + "hammer_02.ogg", delay=0.2, gain=-2.0),
         L("woodmetal/" + G + "wood_hammer_02.ogg", delay=0.4)],
    ], dict(level=-14.0, tail=0.08)),
    "build_done": ([  # the last hammer blow, then the chime rings out
        [L("woodmetal/" + G + "hammer_01.ogg", gain=-3.0),
         chime([(0.0, C6, 0.8), (0.08, E6, 0.85), (0.16, G6, 0.9), (0.24, C7, 1.0)],
               delay=0.12)],
    ], dict(level=-13.0, tail=0.3)),
    # --- rewards: the same real bell, re-tuned, over real coins
    "coin": ([
        [L("starcoins/" + G + "coin.2.ogg", gain=-6.0, hp=1500),
         chime([(0.0, B6, 0.8), (0.06, E7, 1.0)])],
    ], dict(level=-16.0, tail=0.15, max=0.7)),
    "coin_bag": ([
        [L("rpgk/" + G + "handleCoins.ogg"),
         chime([(0.05, E7, 0.6), (0.11, G7, 0.7)], gain=-4.0)],
    ], dict(level=-14.0, tail=0.15)),
    "collect": ([
        [L("rpg80/" + G + "item_coins_02.ogg", hp=300),
         chime([(0.0, E6, 0.7), (0.07, G6, 0.8), (0.14, C7, 1.0)], gain=-3.0)],
    ], dict(level=-14.0, tail=0.2)),
    "star1": ([[chime([(0.0, C6, 1.0), (0.0, C7, 0.35)]),
                L("gem/" + G + "gem-gather-orig.wav", gain=-12.0)]], dict(level=-14.0, tail=0.4)),
    "star2": ([[chime([(0.0, E6, 1.0), (0.0, E7, 0.35)]),
                L("gem/" + G + "gem-gather-orig.wav", gain=-12.0)]], dict(level=-14.0, tail=0.4)),
    "star3": ([[chime([(0.0, G6, 1.0), (0.0, G7, 0.3), (0.1, C7, 0.9)]),
                L("gem/" + G + "gem-gather-reverb.wav", delay=0.08, gain=-9.0)]],
              dict(level=-13.0, tail=0.5)),
    "unlock": ([[L("woodmetal/" + G + "lock_open_01.ogg", hp=300),
                 chime([(0.0, G6, 0.8), (0.08, C7, 1.0)], delay=0.5)]],
               dict(level=-14.0, tail=0.3)),
    "chest_open": ([[L("chest/open_chest_0.wav", dur=0.75, gain=14.0, fade=0.2),
                     chime([(0.0, C6, 0.7), (0.06, E6, 0.8), (0.12, G6, 0.9), (0.18, C7, 1.0)],
                           delay=0.3),
                     L("gem/" + G + "gem-gather-reverb.wav", delay=0.3, gain=-8.0)]],
                   dict(level=-13.0, tail=0.4)),
    "spin_tick": ([[L("iface/" + G + "tick_001.ogg")]], dict(level=-20.0, tail=0.02)),
    "spin_win": ([[L("fanfare/fanfare_3.ogg", dur=2.2, fade=0.5),
                   L("rpg80/" + G + "item_coins_04.ogg", delay=0.6, gain=-9.0, hp=300)]],
                 dict(level=-13.0, tail=0.4)),
    "daily_claim": ([[L("rpgk/" + G + "handleCoins.ogg", gain=-6.0),
                      chime([(0.0, C6, 0.7), (0.07, E6, 0.75), (0.14, G6, 0.8), (0.21, C7, 0.9),
                             (0.28, E7, 1.0)])]],
                    dict(level=-14.0, tail=0.4)),
    "mission_done": ([[chime([(0.0, E6, 0.8), (0.1, G6, 0.85), (0.2, C7, 1.0), (0.2, E7, 0.5)]),
                       L("gem/" + G + "gem-gather-reverb.wav", delay=0.2, gain=-8.0)]],
                     dict(level=-14.0, tail=0.4)),
    "rank_up": ([[L("jingles/" + G + "jingles_SAX02.ogg")]], dict(level=-13.0, tail=0.2)),
    "gate_bad": ([[L("jingles/" + G + "jingles_HIT01.ogg")]], dict(level=-14.0, tail=0.1)),
}


# ---------------------------------------------------------------- processing

_cache = {}


def find(dl: Path, pattern: str) -> str:
    hits = sorted(glob.glob(str(dl / pattern), recursive=True))
    hits = [h for h in hits if "__MACOSX" not in h]
    if not hits:
        raise SystemExit(f"missing source: {pattern}")
    return hits[0]


def decode(path: str):
    if path not in _cache:
        pcm = subprocess.run([FFMPEG, "-v", "error", "-i", path, "-f", "f32le", "-ac", "1",
                              "-ar", str(SR), "-"], capture_output=True, check=True).stdout
        _cache[path] = np.frombuffer(pcm, dtype=np.float32).astype(np.float64)
    return _cache[path]


def retune(y, hz: float):
    """Tape-style re-tune of a bell strike so its main partial (BELL_HZ) lands on hz."""
    r = hz / BELL_HZ
    n = max(1, int(len(y) / r))
    return np.interp(np.arange(n) * r, np.arange(len(y)), y)


def chime_layer(x, ly: dict):
    on = max(0, int(np.argmax(np.abs(x) > np.abs(x).max() * 0.1)) - int(0.002 * SR))
    strike = x[on:] - x[on:].mean()
    if ly["hp"]:
        strike = signal.sosfilt(signal.butter(2, ly["hp"], "highpass", fs=SR, output="sos"), strike)
    notes = [(int(t * SR), retune(strike, hz) * g) for t, hz, g in ly["notes"]]
    out = np.zeros(max(d + len(y) for d, y in notes))
    for d, y in notes:
        out[d:d + len(y)] += y
    return out * 10 ** (ly["gain"] / 20.0), int(ly["delay"] * SR)


def layer(dl: Path, ly: dict):
    x = decode(find(dl, ly["src"]))
    if ly["notes"]:
        return chime_layer(x, ly)
    a = int(ly["start"] * SR)
    b = len(x) if ly["dur"] is None else min(len(x), a + int(ly["dur"] * SR))
    y = x[a:b].copy()
    y -= y.mean() if len(y) > SR // 20 else 0.0  # remove DC offset
    if ly["st"]:
        r = 2 ** (ly["st"] / 12.0)  # tape-style: higher and shorter
        n = max(1, int(len(y) / r))
        y = np.interp(np.arange(n) * r, np.arange(len(y)), y)
    if ly["hp"]:
        y = signal.sosfilt(signal.butter(2, ly["hp"], "highpass", fs=SR, output="sos"), y)
    if ly["lp"]:
        y = signal.sosfilt(signal.butter(2, ly["lp"], "lowpass", fs=SR, output="sos"), y)
    if ly["fade"]:
        n = min(len(y), int(ly["fade"] * SR))
        y[-n:] *= np.cos(np.linspace(0, np.pi / 2, n)) ** 2
    return y * 10 ** (ly["gain"] / 20.0), int(ly["delay"] * SR)


def mix(dl: Path, take: list, opts: dict):
    parts = [layer(dl, ly) for ly in take]
    n = max(d + len(y) for y, d in parts)
    out = np.zeros(n)
    for y, d in parts:
        out[d:d + len(y)] += y
    # trim: leading silence (keep 3 ms) and trailing silence
    env = np.abs(out)
    pk = env.max() + 1e-12
    on = np.where(env > pk * 10 ** (-40 / 20))[0]
    a = max(0, on[0] - int(0.003 * SR))
    off = np.where(env > pk * 10 ** (-56 / 20))[0]
    out = out[a:off[-1] + 1]
    if opts.get("max"):
        out = out[:int(opts["max"] * SR)]
    # fades: 2 ms in, tail out
    fi = min(len(out), int(0.002 * SR))
    out[:fi] *= np.linspace(0, 1, fi)
    fo = min(len(out), int(opts.get("tail", 0.05) * SR))
    out[-fo:] *= np.cos(np.linspace(0, np.pi / 2, fo)) ** 2
    return out


def loudest_50ms(x) -> float:
    w = int(0.05 * SR)
    if len(x) <= w:
        return 10 * np.log10((x ** 2).mean() + 1e-12)
    c = np.concatenate([[0.0], np.cumsum(x ** 2)])
    return 10 * np.log10(((c[w:] - c[:-w]) / w).max() + 1e-12)


def level(x, target_db: float, squeeze: float = 4.0):
    g = 10 ** ((target_db - loudest_50ms(x)) / 20.0)
    y = x * g
    ceiling = 10 ** (PEAK_DB / 20.0)
    pk = np.abs(y).max()
    if pk > ceiling:  # transient peaks: trade up to <squeeze> dB of gain, soft-knee the rest
        y *= max(ceiling / pk, 10 ** (-squeeze / 20.0))
        k = ceiling * 0.8
        over = np.abs(y) > k
        r = ceiling - k
        y = np.where(over, np.sign(y) * (k + r * np.tanh((np.abs(y) - k) / r)), y)
    return y


def write(path: Path, x) -> None:
    subprocess.run([FFMPEG, "-v", "error", "-y", "-f", "f32le", "-ac", "1", "-ar", str(SR),
                    "-i", "-", "-c:a", "libvorbis", "-q:a", VORBIS_Q, str(path)],
                   input=x.astype(np.float32).tobytes(), check=True)


def build(dl: Path, sid: str) -> None:
    takes, opts = RECIPES[sid]
    for i, take in enumerate(takes):
        x = level(mix(dl, take, opts), opts.get("level", -14.0), opts.get("squeeze", 4.0))
        name = sid + (str(i + 1) if i else "") + ".ogg"
        write(OUT / name, x)
        print(f"{name:20s} {len(x) / SR:5.2f} s  peak {20 * np.log10(np.abs(x).max()):5.1f} dBFS"
              f"  loudest 50 ms {loudest_50ms(x):5.1f} dB")
    # drop stale extra takes from an earlier build
    i = len(takes) + 1
    while (OUT / f"{sid}{i}.ogg").exists():
        (OUT / f"{sid}{i}.ogg").unlink()
        imp = OUT / f"{sid}{i}.ogg.import"
        if imp.exists():
            imp.unlink()
        print("removed", f"{sid}{i}.ogg")
        i += 1


def main() -> None:
    a = sys.argv[1:]
    if not a:
        raise SystemExit(__doc__)
    dl = Path(a[0])
    if a[1:] == ["--list"]:
        print(" ".join(sorted(RECIPES)))
        return
    for sid in (a[1:] or sorted(RECIPES)):
        if sid not in RECIPES:
            raise SystemExit(f"no recipe for {sid}")
        build(dl, sid)


if __name__ == "__main__":
    main()
