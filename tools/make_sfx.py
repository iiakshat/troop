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
    "bottle": ("Bottle%20Break.wav", "spookymodem", "CC BY 3.0"),
    "glass_tw": ("glass_breaking.wav", "TinyWorlds", "CC0"),
    "breaking75": ("sfx_breaking_and_falling.zip", "rubberduck", "CC0"),
    "ice": ("IceShatters_0.zip", "ignasd", "CC0"),
    "emopain": ("painsounds.zip", "EmoPreben", "CC0"),
    "slight": ("slightscreams.7z", "qubodup", "CC0"),
    "yell": ("yelling%20sounds.zip", "HaelDB", "CC0"),
    "qpunch": ("qubodupPunch.7z", "qubodup", "CC0"),
    "ljudhits": ("independent_nu_ljudbank-hits_and_punches.7z", "qubodup", "CC0"),
    "chunky": ("Chunky%20Explosion.mp3", "Joth", "CC0"),
    "expl_tw": ("explosion.wav", "TinyWorlds", "CC0"),
    "expl_dull": ("explosion_dull.flac", "qubodup", "CC0"),
    "bangs": ("25-CC0-bang-sfx.zip", "rubberduck", "CC0"),
    "scifi": ("sci-fi_sounds.zip", "Kenney", "CC0"),
    "roar": ("monster_roar.wav", "trazzz123", "CC0"),
    "troll": ("troll-roars_0.ogg", "darsycho", "CC0"),
    "creature": ("80-CC0-creature-SFX_0.zip", "rubberduck", "CC0"),
    "rpg80": ("80-CC0-RPG-SFX_0.zip", "rubberduck", "CC0"),
    "flame": ("flame_0.ogg", "themightyglider", "CC0"),
    "ignition": ("ignition.flac", "qubodup", "CC0"),
    "hammer": ("craft_0.ogg", "themightyglider", "CC0"),
    "woodmetal": ("100-CC0-wood-metal-SFX.zip", "rubberduck", "CC0"),
    "rd100": ("100-CC0-SFX_0.zip", "rubberduck", "CC0"),
    "rd100b": ("sfx_100_v2.zip", "rubberduck", "CC0"),
    "starcoins": ("coins_-_starninjas.zip", "starninjas", "CC0"),
    "coinsplash": ("coinsplash_0.ogg", "LordTomorrow", "CC0"),
    "goldsack": ("gold_sack.wav", "Amarikah", "CC0"),
    "rpgk": ("RPGsounds_Kenney.zip", "Kenney", "CC0"),
    "casino": ("kenney_casino-audio.zip", "Kenney", "CC0"),
    "iface": ("kenney_interfaceSounds.zip", "Kenney", "CC0"),
    "uisfx": ("UI_SFX_Set.zip", "Kenney", "CC0"),
    "jingles": ("jingleSounds_Kenney.zip", "Kenney", "CC0"),
    "gem": ("gem-gather-mono-files.zip", "bobjt", "CC0"),
    "chest": ("open%20chest_0.wav", "oiboo", "CC0"),
    "achieve": ("achievement.wav", "mdkieran", "CC0"),
    "fanfare": ("fanfare_3.ogg", "fvcalderan", "CC0"),
    "dings": ("bell_ding1.wav ... bell_ding4.wav", "pwl", "CC0"),
    "wobble": ("SoundPack01.zip", "wobbleboxx", "CC0"),
    "swishes": ("swishes.zip", "artisticdude", "CC0"),
    "guns": ("sounds.zip", "Vincent Sevedge (Tabasco)", "CC BY 3.0"),
}


def L(src, start=0.0, dur=None, delay=0.0, gain=0.0, st=0.0, hp=None, lp=None, fade=None,
      notes=None):
    """One layer: <dur> s of <src> from <start>, placed at <delay> s in the take.
    src "glock" is our own synthesised mallet chime: notes = [(time s, Hz, gain)]."""
    return dict(src=src, start=start, dur=dur, delay=delay, gain=gain, st=st, hp=hp, lp=lp,
                fade=fade, notes=notes)


# Chime notes: C major, the relative major of the music's A minor.
C5, E5, G5, B5 = 523.25, 659.26, 783.99, 987.77
C6, D6, E6, G6, A6, B6 = 1046.50, 1174.66, 1318.51, 1567.98, 1760.00, 1975.53
C7, E7, G7 = 2093.00, 2637.02, 3135.96
G = "**/"  # any depth inside a pack folder
EMO = "emopain/" + G + "Painsounds v2 - Track "

# id -> (takes, options). Options: level (dB RMS of the loudest 50 ms, default -14), tail
# (fade-out seconds, default 0.05), max (cut the take at this length).
RECIPES = {
    # --- glass (Bottle Shot): a real bottle smash with body, then the falling shards
    "glass_break": ([
        [L("bottle/Bottle_Break.wav", start=0.30, hp=150)],
        [L("glass_tw/glass_breaking.wav", hp=120)],
        [L("glass_tw/glass_breaking.wav", st=2.0, hp=120),
         L("breaking75/" + G + "bfh1_glass_breaking_06.ogg", delay=0.10, gain=-9.0)],
    ], dict(level=-12.0, tail=0.12)),
    "glass_tinkle": ([
        [L("breaking75/" + G + "bfh1_glass_breaking_06.ogg")],
        [L("breaking75/" + G + "bfh1_glass_falling_02.ogg")],
        [L("ice/" + G + "LedasLuzta4.ogg", hp=1500)],
    ], dict(level=-17.0, tail=0.15)),
    # --- guns the existing recordings don't cover (Tabasco's mosin and shotgun takes)
    "shot_sniper": ([
        [L("guns/" + G + "mosin.wav", start=5.92, dur=1.25)],
        [L("guns/" + G + "mosin.wav", start=8.79, dur=1.25)],
    ], dict(level=-11.0, tail=0.4)),
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
    ], dict(level=-14.0, tail=0.2, max=0.7)),
    # --- explosions: a meaty boom with a crunchy top
    "boom": ([
        [L("chunky/Chunky_Explosion.mp3", dur=2.2),
         L("scifi/" + G + "explosionCrunch_000.ogg", gain=-5.0)],
        [L("scifi/" + G + "explosionCrunch_001.ogg"),
         L("scifi/" + G + "lowFrequency_explosion_001.ogg", gain=-4.0)],
        [L("expl_tw/explosion.wav"),
         L("scifi/" + G + "explosionCrunch_004.ogg", gain=-6.0)],
    ], dict(level=-11.0, tail=0.6, max=2.0)),
    # --- bodies: real punches, short impacts, grunts that aren't silly
    "punch": ([[L("qpunch/" + G + f"qubodupPunch0{i}.flac")] for i in range(1, 6)],
              dict(level=-13.0, tail=0.08)),
    "hit": ([[L("ljudhits/" + G + f"hit{i}.mp3.flac", hp=120)] for i in (10, 15, 28)],
            dict(level=-15.0, tail=0.06, max=0.22)),
    "die": ([
        [L(EMO + "1*", hp=110)],
        [L(EMO + "2*", hp=110)],
        [L(EMO + "5*", hp=110)],
        [L("yell/" + G + "3grunt1.wav", hp=110)],
        [L("yell/" + G + "3grunt5.wav", hp=110)],
    ], dict(level=-15.0, tail=0.1, max=0.6)),
    "hurt": ([[L("slight/" + G + f"slightscream-{i:02d}.flac", hp=110)] for i in (1, 3, 8, 14)],
             dict(level=-15.0, tail=0.08, max=0.5)),
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
    "knife": ([[L("swishes/" + G + f"swish-{i}.wav", hp=250)] for i in (4, 9, 10)],
              dict(level=-17.0, tail=0.03)),
    # --- city building
    "build": ([
        [L("hammer/craft_0.ogg")],
        [L("woodmetal/" + G + "wood_hammer_01.ogg"),
         L("woodmetal/" + G + "hammer_02.ogg", delay=0.2, gain=-2.0),
         L("woodmetal/" + G + "wood_hammer_02.ogg", delay=0.4)],
    ], dict(level=-14.0, tail=0.08)),
    "build_done": ([  # the last hammer blow, then a steel-drum ta-da
        [L("woodmetal/" + G + "hammer_01.ogg", gain=-3.0),
         L("jingles/" + G + "jingles_STEEL02.ogg", delay=0.12)],
    ], dict(level=-13.0, tail=0.25)),
    # --- rewards: bright chimes (our own synth) over real coins
    "coin": ([
        [L("glock", notes=[(0.0, B5, 0.8), (0.06, E6, 1.0)], dur=0.5),
         L("rpg80/" + G + "item_coins_01.ogg", gain=-14.0, hp=2500)],
    ], dict(level=-15.0, tail=0.15)),
    "collect": ([
        [L("rpg80/" + G + "item_coins_02.ogg", hp=300),
         L("glock", notes=[(0.0, E6, 0.7), (0.07, G6, 0.8), (0.14, C7, 1.0)], dur=0.7,
           gain=-3.0)],
    ], dict(level=-13.0, tail=0.2)),
    "star1": ([[L("glock", notes=[(0.0, C6, 1.0), (0.0, C7, 0.35)], dur=1.0),
                L("gem/" + G + "gem-gather-orig.wav", gain=-12.0)]], dict(level=-13.0, tail=0.4)),
    "star2": ([[L("glock", notes=[(0.0, E6, 1.0), (0.0, E7, 0.35)], dur=1.0),
                L("gem/" + G + "gem-gather-orig.wav", gain=-12.0)]], dict(level=-13.0, tail=0.4)),
    "star3": ([[L("glock", notes=[(0.0, G6, 1.0), (0.0, G7, 0.3), (0.1, C7, 0.9)], dur=1.4),
                L("gem/" + G + "gem-gather-reverb.wav", delay=0.08, gain=-9.0)]],
              dict(level=-12.0, tail=0.5)),
    "unlock": ([[L("woodmetal/" + G + "lock_open_01.ogg", hp=300),
                 L("glock", notes=[(0.0, G6, 0.8), (0.08, C7, 1.0)], dur=0.8, delay=0.5)]],
               dict(level=-13.0, tail=0.3)),
    "chest_open": ([[L("chest/open_chest_0.wav", dur=0.75, gain=14.0, fade=0.2),
                     L("glock", notes=[(0.0, C6, 0.7), (0.06, E6, 0.8), (0.12, G6, 0.9),
                                       (0.18, C7, 1.0)], dur=1.1, delay=0.3),
                     L("gem/" + G + "gem-gather-reverb.wav", delay=0.3, gain=-8.0)]],
                   dict(level=-12.0, tail=0.4)),
    "spin_tick": ([[L("iface/" + G + "tick_001.ogg")]], dict(level=-17.0, tail=0.02)),
    "spin_win": ([[L("fanfare/fanfare_3.ogg", dur=2.2, fade=0.5),
                   L("rpg80/" + G + "item_coins_04.ogg", delay=0.6, gain=-9.0, hp=300)]],
                 dict(level=-12.0, tail=0.4)),
    "daily_claim": ([[L("jingles/" + G + "jingles_STEEL10.ogg"),
                      L("rpgk/" + G + "handleCoins.ogg", delay=0.05, gain=-8.0)]],
                    dict(level=-12.0, tail=0.3)),
    "mission_done": ([[L("achieve/achievement.wav", dur=1.6, fade=0.4)]],
                     dict(level=-12.0, tail=0.3)),
    "rank_up": ([[L("jingles/" + G + "jingles_SAX02.ogg")]], dict(level=-12.0, tail=0.2)),
    "gate_bad": ([[L("jingles/" + G + "jingles_HIT01.ogg")]], dict(level=-13.0, tail=0.1)),
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


def layer(dl: Path, ly: dict):
    x = decode(find(dl, ly["src"]))
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


def level(x, target_db: float):
    g = 10 ** ((target_db - loudest_50ms(x)) / 20.0)
    y = x * g
    ceiling = 10 ** (PEAK_DB / 20.0)
    pk = np.abs(y).max()
    if pk > ceiling:  # transient peaks: trade up to 4 dB of gain, soft-knee the rest
        y *= max(ceiling / pk, 10 ** (-4 / 20.0))
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
        x = level(mix(dl, take, opts), opts.get("level", -14.0))
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
