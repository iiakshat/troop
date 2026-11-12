"""Prepares the Android Gradle build (v2: the AdMob and Firebase plugins need it). Run by build_apk.bat.

1. Installs Godot's Android build template into android/build when it is missing or from another
   Godot version. This is exactly what the editor's Project > Install Android Build Template does:
   android/.build_version holds the template version, android/build/.gdignore keeps the editor out,
   and android_source.zip (from tools/setup_android.py) is unpacked into android/build/.
2. Patches android/build/build.gradle for Firebase: the google-services Gradle plugin, applied only
   when android/build/google-services.json exists. The Firebase export plugin copies the owner's
   google-services.json from the project root into android/build/ at export time. That file is
   git-ignored everywhere and never committed; without it the APK still builds, and Firebase simply
   cannot start (the game then keeps its local analytics log only).

android/build/ and android/.build_version are generated (git-ignored). The Firebase plugin's own
.aar files in android/firebase_*/ are committed. Safe to re-run.
Run: python -I tools/android_template.py [--force]
"""
import os, shutil, sys, zipfile
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


def main():
    install(force="--force" in sys.argv)
    patch_gradle()


if __name__ == "__main__":
    sys.exit(main())
