#!/usr/bin/env python3
"""Check pinned Bookworm ARM64 package availability and desktop startup contract."""
import lzma
import subprocess
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SESSION = ROOT / "app/src/main/assets/linux/xfce-session.sh"
RUNTIME = ROOT / "app/src/main/java/org/miniarino/desktop/LinuxRuntime.java"
ACTIVITY = ROOT / "app/src/main/java/org/miniarino/desktop/HomeActivity.java"
PACKAGES_URL = "https://deb.debian.org/debian/dists/bookworm/main/binary-arm64/Packages.xz"
EXPECTED = {"xfce4", "xfce4-terminal", "thunar", "dbus-x11", "dbus-bin"}


def package_stanzas(data):
    found = {}
    for stanza in data.split("\n\n"):
        if not stanza.startswith("Package: "):
            continue
        fields = {}
        for line in stanza.splitlines():
            if line and not line[0].isspace() and ": " in line:
                key, value = line.split(": ", 1)
                fields[key] = value
        name = fields.get("Package")
        if name in EXPECTED:
            found[name] = fields
    return found


def main():
    request = urllib.request.Request(PACKAGES_URL, headers={"User-Agent": "MiniArino Bookworm ARM64 desktop package test"})
    with urllib.request.urlopen(request, timeout=90) as response:
        packages = package_stanzas(lzma.decompress(response.read()).decode("utf-8"))
    missing = EXPECTED - packages.keys()
    if missing:
        raise SystemExit("Bookworm ARM64 package index lacks: " + ", ".join(sorted(missing)))
    for name, fields in packages.items():
        if fields.get("Architecture") not in {"all", "arm64"}:
            raise SystemExit(f"{name} is not available for Debian ARM64: {fields.get('Architecture')}")
    session = SESSION.read_text(encoding="utf-8")
    runtime = RUNTIME.read_text(encoding="utf-8")
    activity = ACTIVITY.read_text(encoding="utf-8")
    if 'xfce4 xfce4-terminal thunar dbus-x11' not in runtime:
        raise SystemExit("Android PRoot installer is missing the XFCE package set")
    for command in ("dbus-launch", "dbus-send", "startxfce4", "thunar", "xfce4-terminal"):
        if command not in session:
            raise SystemExit(f"Desktop launcher is missing expected command: {command}")
    if "MINIARINO_XFCE_SESSION_READY" not in session or "DESKTOP_READY_MARKER" not in runtime:
        raise SystemExit("Desktop readiness marker is not shared by launcher and Android runtime")
    if "org.xfce.SessionManager" not in session:
        raise SystemExit("Desktop readiness is not gated on XFCE session-manager registration")
    if '"DISPLAY", ":0"' not in runtime or 'tmpDir.getAbsolutePath() + ":/tmp"' not in runtime:
        raise SystemExit("PRoot desktop must target Lorie :0 and share its app-private /tmp socket directory")
    if '"XKB_CONFIG_ROOT"' not in activity or 'usr/share/X11/xkb' not in activity or 'X0' not in activity:
        raise SystemExit("Lorie must be given Debian's installed XKB data and its X11 socket must be awaited")
    gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
    if "targetSdkVersion 28" not in gradle:
        raise SystemExit("Writable app-private PRoot execution requires the legacy targetSdkVersion 28")
    if "applicationIdSuffix '.sdk28test'" not in gradle:
        raise SystemExit("The debug APK must use the isolated org.miniarino.desktop.sdk28test package")
    debug_label = (ROOT / "app/src/debug/res/values/strings.xml").read_text(encoding="utf-8")
    if '<string name="application_name">MiniAriño prueba</string>' not in debug_label:
        raise SystemExit("The side-by-side debug APK must have a distinct launcher label")
    app_manifest = (ROOT / "app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
    if "<provider" in app_manifest or "android:authorities" in app_manifest:
        raise SystemExit("Review provider authorities before changing the isolated debug package")
    lorie_manifest = ROOT / "vendor/termux-x11/lorie/src/main/AndroidManifest.xml"
    if lorie_manifest.exists():
        lorie_source = lorie_manifest.read_text(encoding="utf-8")
        if "<provider" in lorie_source or "android:authorities" in lorie_source:
            raise SystemExit("Review upstream provider authorities before changing the isolated debug package")
    if 'display.setClassName(getPackageName(), "com.termux.x11.MainActivity")' not in activity:
        raise SystemExit("The internal X11 activity intent must follow the installed application ID")
    if "testInstrumentationRunner 'androidx.test.runner.AndroidJUnitRunner'" not in gradle:
        raise SystemExit("The Android instrumentation runner must remain configured for the debug target")
    test_source = (ROOT / "app/src/androidTest/java/org/miniarino/desktop/LinuxRuntimeExecInstrumentedTest.java").read_text(encoding="utf-8")
    if "appPrivateProotExecutesGuestCommand" not in test_source or "proot-test-x86_64/bin/proot" not in test_source or "MINIARINO_PROOT_GUEST_OK" not in test_source:
        raise SystemExit("The Android instrumentation test must execute PRoot from private storage and run a guest command")
    if "--arch x86_64" not in (ROOT.parent / ".github/workflows/android-apk-spike.yml").read_text(encoding="utf-8"):
        raise SystemExit("The x86_64 PRoot runtime fixture must be staged for emulator runtime testing")
    if "awaitXfceSession(process, logFile)" not in activity or "showEmbeddedDesktop()" not in activity or "Copy diagnostics" not in activity:
        raise SystemExit("Android UI must show only a ready desktop and keep copy/share diagnostics available on failure")
    subprocess.check_call(["sh", "-n", str(SESSION)])
    print("Bookworm ARM64 package availability and XFCE/PRoot startup contract passed.")
    for name in sorted(EXPECTED):
        print(f"{name}: {packages[name].get('Version')} ({packages[name].get('Architecture')})")


if __name__ == "__main__":
    main()
