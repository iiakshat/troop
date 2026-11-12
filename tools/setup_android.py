"""One-time setup for local Android builds. Installs only what Godot's non-Gradle export needs:

  ../_tools/android-sdk/platform-tools   (adb)                ~8 MB download
  ../_tools/android-sdk/build-tools/36.0.0 (apksigner)        ~59 MB
  ../_tools/jre-17                        (runs apksigner, keytool) ~45 MB
  %APPDATA%/Godot/export_templates/4.7.2.stable/android_*.apk  only these files are pulled
                                          out of the 1 GB template pack (HTTP range requests)
  %APPDATA%/Godot/keystores/debug.keystore  standard Android debug key (not secret)

Gradle build (v2: the AdMob and Firebase plugins need it), also:
  ../_tools/jdk-17                        (Gradle compiles Java/Kotlin) ~190 MB
  ../_tools/android-sdk/platforms/android-36, build-tools/36.1.0   ~120 MB
  %APPDATA%/Godot/export_templates/4.7.2.stable/android_source.zip  (the Gradle build template)
  Gradle itself and the Maven libraries are fetched by the first build into %USERPROFILE%/.gradle.

No Android Studio, no sdkmanager, no NDK. Safe to re-run: finished parts are skipped.
Every download is checked (SHA-1 from Google's repo index, SHA-256 from Adoptium, CRC from the zip).
Run: python -I tools/setup_android.py
"""
import hashlib, io, json, os, re, shutil, subprocess, sys, tempfile, urllib.request, zipfile
from pathlib import Path

GODOT = "4.7.2"
BUILD_TOOLS = "36.0.0"
GRADLE_BUILD_TOOLS = "36.1.0"  # android_source.zip config.gradle: buildTools
GRADLE_PLATFORM = "android-36"  # config.gradle: compileSdk
def _tools_root():
    """../_tools next to the project; from a git worktree (.claude/worktrees/x) the same folder."""
    here = Path(__file__).resolve()
    for p in here.parents:
        if (p / "_tools" / "godot").is_dir():
            return p / "_tools"
    return here.parents[2] / "_tools"


ROOT = _tools_root()
SDK = ROOT / "android-sdk"
JRE = ROOT / "jre-17"
JDK = ROOT / "jdk-17"
GODOT_DATA = Path(os.environ["APPDATA"]) / "Godot"
TEMPLATES = GODOT_DATA / "export_templates" / f"{GODOT}.stable"
KEYSTORE = GODOT_DATA / "keystores" / "debug.keystore"
GOOGLE = "https://dl.google.com/android/repository/"
UA = {"User-Agent": "troop-setup"}


def say(msg):
    print(msg, flush=True)


def fetch(url, dest, algo=None, digest=None):
    """Stream a URL to a file (never held in memory) and check its hash."""
    h = hashlib.new(algo) if algo else None
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA)) as r, open(dest, "wb") as f:
        while chunk := r.read(1 << 20):
            f.write(chunk)
            if h:
                h.update(chunk)
    if h and h.hexdigest().lower() != digest.lower():
        raise SystemExit(f"Checksum mismatch for {url}")


def unzip_strip(zip_path, dest, top):
    """Extract a zip whose files sit under `top/` into dest/ (dropping that prefix)."""
    with zipfile.ZipFile(zip_path) as z:
        for info in z.infolist():
            name = info.filename
            if not name.startswith(top + "/") or name.endswith("/"):
                continue
            out = dest / name[len(top) + 1:]
            out.parent.mkdir(parents=True, exist_ok=True)
            with z.open(info) as src, open(out, "wb") as dst:
                shutil.copyfileobj(src, dst, 1 << 20)


def google_packages(tmp):
    """{path: (url, sha1)} for the Windows archives we need, read from Google's repo index."""
    import xml.etree.ElementTree as ET
    index = tmp / "repo.xml"
    fetch(GOOGLE + "repository2-3.xml", index)
    found = {}
    for pkg in ET.parse(index).getroot().iter():
        if not pkg.tag.endswith("remotePackage"):
            continue
        path = pkg.get("path")
        if path not in ("platform-tools", f"build-tools;{BUILD_TOOLS}",
                        f"build-tools;{GRADLE_BUILD_TOOLS}", f"platforms;{GRADLE_PLATFORM}"):
            continue
        for arc in pkg.iter():
            if not arc.tag.endswith("archive"):
                continue
            host = arc.find(".//host-os")
            if host is not None and host.text != "windows":
                continue
            c = arc.find(".//complete")
            found[path] = (GOOGLE + c.find("url").text, c.find("checksum").text)
    return found


def install_sdk(tmp):
    adb = SDK / "platform-tools" / "adb.exe"
    bt = SDK / "build-tools" / BUILD_TOOLS / "apksigner.bat"
    if adb.exists() and bt.exists():
        say("Android SDK: already installed")
        return
    pk = google_packages(tmp)
    if not adb.exists():
        say("Android SDK: platform-tools")
        url, sha = pk["platform-tools"]
        fetch(url, tmp / "pt.zip", "sha1", sha)
        unzip_strip(tmp / "pt.zip", SDK / "platform-tools", "platform-tools")
        (tmp / "pt.zip").unlink()
    if not bt.exists():
        say(f"Android SDK: build-tools {BUILD_TOOLS}")
        url, sha = pk[f"build-tools;{BUILD_TOOLS}"]
        fetch(url, tmp / "bt.zip", "sha1", sha)
        with zipfile.ZipFile(tmp / "bt.zip") as z:
            top = z.namelist()[0].split("/")[0]  # e.g. android-16
        unzip_strip(tmp / "bt.zip", SDK / "build-tools" / BUILD_TOOLS, top)
        (tmp / "bt.zip").unlink()


def install_gradle_sdk(tmp):
    """The SDK parts the Gradle build template compiles against."""
    parts = {f"build-tools;{GRADLE_BUILD_TOOLS}": SDK / "build-tools" / GRADLE_BUILD_TOOLS,
             f"platforms;{GRADLE_PLATFORM}": SDK / "platforms" / GRADLE_PLATFORM}
    todo = {k: v for k, v in parts.items() if not (v / "source.properties").exists()}
    if not todo:
        say("Android SDK (Gradle): already installed")
        return
    pk = google_packages(tmp)
    for path, dest in todo.items():
        say(f"Android SDK (Gradle): {path}")
        url, sha = pk[path]
        fetch(url, tmp / "part.zip", "sha1", sha)
        with zipfile.ZipFile(tmp / "part.zip") as z:
            top = z.namelist()[0].split("/")[0]
        unzip_strip(tmp / "part.zip", dest, top)
        (tmp / "part.zip").unlink()


def install_jdk(tmp):
    """A full JDK 17 (Gradle needs javac; the JRE above only runs apksigner/keytool)."""
    if (JDK / "bin" / "javac.exe").exists():
        say("Java 17 JDK: already installed")
        return
    say("Java 17 JDK (Temurin)")
    api = ("https://api.adoptium.net/v3/assets/latest/17/hotspot"
           "?architecture=x64&image_type=jdk&os=windows&vendor=eclipse")
    with urllib.request.urlopen(urllib.request.Request(api, headers=UA)) as r:
        assets = json.load(r)
    pkg = next(a["binary"]["package"] for a in assets if a["binary"]["package"]["name"].endswith(".zip"))
    fetch(pkg["link"], tmp / "jdk.zip", "sha256", pkg["checksum"])
    with zipfile.ZipFile(tmp / "jdk.zip") as z:
        top = z.namelist()[0].split("/")[0]
    unzip_strip(tmp / "jdk.zip", JDK, top)
    (tmp / "jdk.zip").unlink()


def install_jre(tmp):
    if (JRE / "bin" / "java.exe").exists():
        say("Java 17 runtime: already installed")
        return
    say("Java 17 runtime (Temurin JRE)")
    api = ("https://api.adoptium.net/v3/assets/latest/17/hotspot"
           "?architecture=x64&image_type=jre&os=windows&vendor=eclipse")
    with urllib.request.urlopen(urllib.request.Request(api, headers=UA)) as r:
        assets = json.load(r)
    pkg = next(a["binary"]["package"] for a in assets if a["binary"]["package"]["name"].endswith(".zip"))
    fetch(pkg["link"], tmp / "jre.zip", "sha256", pkg["checksum"])
    with zipfile.ZipFile(tmp / "jre.zip") as z:
        top = z.namelist()[0].split("/")[0]
    unzip_strip(tmp / "jre.zip", JRE, top)
    (tmp / "jre.zip").unlink()


class RemoteFile(io.RawIOBase):
    """Seekable read-only view of a URL using HTTP Range requests, with a read-ahead buffer."""

    def __init__(self, url, chunk=4 << 20):
        req = urllib.request.Request(url, method="HEAD", headers=UA)
        with urllib.request.urlopen(req) as r:
            self.url = r.url  # follow GitHub's redirect once
            self.size = int(r.headers["Content-Length"])
        self.pos, self.chunk, self.buf_start, self.buf = 0, chunk, 0, b""

    def readable(self): return True
    def seekable(self): return True
    def tell(self): return self.pos

    def seek(self, off, whence=0):
        self.pos = {0: off, 1: self.pos + off, 2: self.size + off}[whence]
        return self.pos

    def readinto(self, b):
        if self.pos >= self.size:
            return 0
        end = self.buf_start + len(self.buf)
        if not (self.buf_start <= self.pos < end):
            last = min(self.size, self.pos + max(self.chunk, len(b))) - 1
            req = urllib.request.Request(self.url, headers={**UA, "Range": f"bytes={self.pos}-{last}"})
            with urllib.request.urlopen(req) as r:
                self.buf = r.read()
            self.buf_start = self.pos
        i = self.pos - self.buf_start
        n = min(len(b), len(self.buf) - i)
        b[:n] = self.buf[i:i + n]
        self.pos += n
        return n


def install_templates():
    # android_source.zip is the Gradle build template (AdMob/Firebase plugins need a Gradle build).
    want = ["android_debug.apk", "android_release.apk", "android_source.zip", "version.txt"]
    missing = [w for w in want if not (TEMPLATES / w).exists()]
    if not missing:
        say("Godot Android templates: already installed")
        return
    say("Godot Android templates (only the Android files from the pack): " + ", ".join(missing))
    url = (f"https://github.com/godotengine/godot/releases/download/{GODOT}-stable/"
           f"Godot_v{GODOT}-stable_export_templates.tpz")
    remote = io.BufferedReader(RemoteFile(url), buffer_size=1 << 20)
    TEMPLATES.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(remote) as z:
        for w in missing:
            with z.open("templates/" + w) as src, open(TEMPLATES / (w + ".part"), "wb") as dst:
                shutil.copyfileobj(src, dst, 1 << 20)  # zipfile checks the CRC at the end
            os.replace(TEMPLATES / (w + ".part"), TEMPLATES / w)
    if (TEMPLATES / "version.txt").read_text().strip() != f"{GODOT}.stable":
        raise SystemExit("Template version mismatch")


def make_keystore():
    if KEYSTORE.exists():
        say("Debug keystore: already there")
        return
    say("Debug keystore")
    KEYSTORE.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(JRE / "bin" / "keytool.exe"), "-genkeypair", "-keystore", str(KEYSTORE),
                    "-storepass", "android", "-alias", "androiddebugkey", "-keypass", "android",
                    "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000",
                    "-dname", "CN=Android Debug,O=Android,C=US"], check=True, capture_output=True)


def point_godot():
    """Write the SDK, Java and keystore paths into Godot's editor settings (other lines kept)."""
    path = GODOT_DATA / "editor_settings-4.7.tres"
    want = {
        "export/android/android_sdk_path": SDK.as_posix(),
        # The JDK when present (Gradle build); it also runs apksigner and keytool.
        "export/android/java_sdk_path": (JDK if (JDK / "bin" / "javac.exe").exists() else JRE).as_posix(),
        "export/android/debug_keystore": KEYSTORE.as_posix(),
        "export/android/debug_keystore_user": "androiddebugkey",
        "export/android/debug_keystore_pass": "android",
    }
    text = path.read_text(encoding="utf-8") if path.exists() else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
    for key, val in want.items():
        line = f'{key} = "{val}"'
        pat = re.compile(rf"^{re.escape(key)} = .*$", re.M)
        text = pat.sub(line, text) if pat.search(text) else text.rstrip("\n") + "\n" + line + "\n"
    path.write_text(text, encoding="utf-8")
    say("Godot editor settings: Android paths set")


def main():
    ROOT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        install_sdk(tmp)
        install_jre(tmp)
        install_gradle_sdk(tmp)
        install_jdk(tmp)
    install_templates()
    make_keystore()
    point_godot()
    say("Done. Build with: build_apk.bat")


if __name__ == "__main__":
    sys.exit(main())
