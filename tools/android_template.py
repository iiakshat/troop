"""Prepares the Android Gradle build (v2: the AdMob and Firebase plugins need it). Run by build_apk.bat.

1. Installs Godot's Android build template into android/build when it is missing or from another
   Godot version. This is exactly what the editor's Project > Install Android Build Template does:
   android/.build_version holds the template version, android/build/.gdignore keeps the editor out,
   and android_source.zip (from tools/setup_android.py) is unpacked into android/build/.
2. Fetches the Gradle distribution the template's wrapper wants into %USERPROFILE%/.gradle (resumable,
   retried, SHA-256 checked) and gives the wrapper a longer network timeout. The wrapper's own
   download gives up after 10 s without data, which a slow connection hits.
3. Patches android/build/build.gradle for Firebase: the google-services Gradle plugin, applied only
   when android/build/google-services.json exists. The Firebase export plugin copies the owner's
   google-services.json from the project root into android/build/ at export time. That file is
   git-ignored everywhere and never committed; without it the APK still builds, and Firebase simply
   cannot start (the game then keeps its local analytics log only).

android/build/ and android/.build_version are generated (git-ignored). The Firebase plugin's own
.aar files in android/firebase_*/ are committed. Safe to re-run.
Run: python -I tools/android_template.py [--force]
"""
import hashlib, os, re, shutil, sys, time, urllib.request, zipfile
from pathlib import Path

GODOT = "4.7.2"
PROJECT = Path(__file__).resolve().parents[1]
ANDROID = PROJECT / "android"
BUILD = ANDROID / "build"
TEMPLATES = Path(os.environ["APPDATA"]) / "Godot" / "export_templates" / f"{GODOT}.stable"
SOURCE_ZIP = TEMPLATES / "android_source.zip"
GOOGLE_SERVICES = "4.4.4"
MARK = "Siren Squad (tools/android_template.py)"

HEAD = f"""// {MARK}: Firebase's google-services Gradle plugin. It is applied at the end of this
// file only when google-services.json is in this folder (the owner adds it; never committed).
buildscript {{
    repositories {{
        google()
        mavenCentral()
    }}
    dependencies {{
        classpath 'com.google.gms:google-services:{GOOGLE_SERVICES}'
    }}
}}

"""
TAIL = f"""
// {MARK}: see the buildscript block at the top.
if (file('google-services.json').exists()) {{
    apply plugin: 'com.google.gms.google-services'
}}
"""


def say(msg):
    print(msg, flush=True)


def template_version():
    return (TEMPLATES / "version.txt").read_text().strip()


def install(force=False):
    if not SOURCE_ZIP.exists():
        raise SystemExit(f"Missing {SOURCE_ZIP}. Run: python -I tools/setup_android.py")
    want = template_version()
    stamp = ANDROID / ".build_version"
    have = stamp.read_text().strip() if stamp.exists() else ""
    if not force and have == want and (BUILD / "build.gradle").exists():
        say("Android build template: installed (%s)" % want)
        return
    say("Android build template: installing %s into android/build" % want)
    keep = None
    gs = BUILD / "google-services.json"
    if gs.exists():
        keep = gs.read_bytes()
    if BUILD.exists():
        shutil.rmtree(BUILD)
    BUILD.mkdir(parents=True)
    stamp.write_text(want + "\n")
    (BUILD / ".gdignore").write_text("\n")
    with zipfile.ZipFile(SOURCE_ZIP) as z:
        for info in z.infolist():
            if info.filename.endswith("/"):
                continue
            out = BUILD / info.filename
            out.parent.mkdir(parents=True, exist_ok=True)
            with z.open(info) as src, open(out, "wb") as dst:
                shutil.copyfileobj(src, dst, 1 << 20)
    if keep is not None:
        gs.write_bytes(keep)


def patch_gradle():
    path = BUILD / "build.gradle"
    text = path.read_text(encoding="utf-8")
    if MARK in text:
        say("build.gradle: Firebase patch already there")
        return
    if "plugins {" not in text:
        raise SystemExit("build.gradle: unexpected layout (no plugins block); patch it by hand, see "
                         "docs/owner_ads_setup.md")
    path.write_text(HEAD + text.rstrip("\n") + "\n" + TAIL, encoding="utf-8")
    say("build.gradle: Firebase patch added")


def _wrapper_hash(url):
    """The folder name Gradle's wrapper uses for a distribution URL (base-36 MD5 of the URL)."""
    n = int.from_bytes(hashlib.md5(url.encode()).digest(), "big")
    digits, out = "0123456789abcdefghijklmnopqrstuvwxyz", ""
    while n:
        n, r = divmod(n, 36)
        out = digits[r] + out
    return out or "0"


def _download_resumable(url, part, tries=8):
    """Appends to `part` from where it stopped; retries with a pause on network errors."""
    for attempt in range(1, tries + 1):
        have = part.stat().st_size if part.exists() else 0
        req = urllib.request.Request(url, headers={"User-Agent": "siren-squad-build",
                                                   "Range": "bytes=%d-" % have})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                mode = "ab" if r.status == 206 else "wb"  # 200: the server ignored the range
                with open(part, mode) as f:
                    while chunk := r.read(1 << 20):
                        f.write(chunk)
            return
        except urllib.error.HTTPError as e:
            if e.code == 416:  # already complete
                return
            if attempt == tries:
                raise
        except OSError:
            if attempt == tries:
                raise
        say("  network hiccup, retrying (%d/%d)" % (attempt, tries))
        time.sleep(3 * attempt)


def prefetch_gradle():
    props = BUILD / "gradle" / "wrapper" / "gradle-wrapper.properties"
    text = props.read_text(encoding="utf-8")
    if "networkTimeout=" not in text:
        props.write_text(text.rstrip("\n") + "\nnetworkTimeout=120000\n", encoding="utf-8")
    m = re.search(r"^distributionUrl=(.+)$", text, re.M)
    if not m:
        return
    url = m.group(1).strip().replace("\\:", ":")
    name = url.rsplit("/", 1)[1]
    home = Path(os.environ.get("GRADLE_USER_HOME", Path.home() / ".gradle"))
    dist = home / "wrapper" / "dists" / name[:-4] / _wrapper_hash(url)
    zip_path = dist / name
    if (dist / (name + ".ok")).exists() or zip_path.exists():
        say("Gradle %s: ready" % name[:-4])
        return
    say("Gradle %s: downloading (resumable)" % name[:-4])
    dist.mkdir(parents=True, exist_ok=True)
    part = dist / (name + ".part")
    _download_resumable(url, part)
    with urllib.request.urlopen(urllib.request.Request(url + ".sha256", headers={"User-Agent": "x"}),
                                timeout=60) as r:
        want = r.read().decode().strip().split()[0].lower()
    h = hashlib.sha256()
    with open(part, "rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    if h.hexdigest() != want:
        part.unlink()
        raise SystemExit("Gradle download was corrupt (checksum); run build_apk.bat again")
    os.replace(part, zip_path)  # the wrapper unpacks it on the first build


def main():
    install(force="--force" in sys.argv)
    prefetch_gradle()
    patch_gradle()


if __name__ == "__main__":
    sys.exit(main())
