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
MANIFEST = ROOT / "app/src/main/AndroidManifest.xml"
LORIE_NATIVE = ROOT / "vendor/termux-x11/lorie/src/main/cpp/lorie/cmdentrypoint.cpp"
PACKAGES_URL = "https://deb.debian.org/debian/dists/bookworm/main/binary-arm64/Packages.xz"
EXPECTED = {"xfce4", "xfce4-terminal", "thunar", "dbus-x11", "dbus-bin", "xkb-data"}


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
    manifest = MANIFEST.read_text(encoding="utf-8")
    lorie_native = LORIE_NATIVE.read_text(encoding="utf-8")
    for command in ("xfce4 xfce4-terminal thunar dbus-x11", "dbus-launch", "dbus-send", "startxfce4", "thunar", "xfce4-terminal"):
        if command not in session:
            raise SystemExit(f"Desktop launcher is missing expected package or command: {command}")
    if "MINIARINO_XFCE_SESSION_READY" not in session or "DESKTOP_READY_MARKER" not in runtime:
        raise SystemExit("Desktop readiness marker is not shared by launcher and Android runtime")
    if "org.xfce.SessionManager" not in session:
        raise SystemExit("Desktop readiness is not gated on XFCE session-manager registration")
    if "xkb-data" not in session or "MINIARINO_XFCE_PREPARED" not in session:
        raise SystemExit("XKB keyboard data must be installed and verified before starting the embedded X server")
    if '"DISPLAY", ":0"' not in runtime or '"TMPDIR", "/tmp"' not in runtime:
        raise SystemExit("PRoot desktop must target Lorie :0 and use the Debian rootfs /tmp socket directory")
    if 'new File(rootfs, "tmp")' not in runtime or 'new File(rootfs, "usr/share/X11/xkb")' not in runtime:
        raise SystemExit("Lorie must use the Debian rootfs paths for its shared socket and XKB data")
    if 'XKB_CONFIG_ROOT is not set.' not in lorie_native or 'XkbBaseDirectory = getenv("XKB_CONFIG_ROOT")' not in lorie_native:
        raise SystemExit("Pinned Lorie source no longer exposes the startup requirement this app configures")
    if '"XKB_CONFIG_ROOT", xkb.getAbsolutePath()' not in activity or '"TMPDIR", tmp.getAbsolutePath()' not in activity:
        raise SystemExit("The standalone app must set Lorie's required XKB and guest /tmp paths")
    if "Copy/share diagnostics" not in activity:
        raise SystemExit("The standalone UI must expose a copy/share diagnostics control")
    if 'android:name="com.termux.x11.MainActivity"' not in manifest or 'android:exported="false"' not in manifest:
        raise SystemExit("The embedded display activity must remain internal to the MiniAriño APK")
    if "awaitXfceSession(process, logFile)" not in activity or "You are still on the MiniAriño home screen" not in activity:
        raise SystemExit("Android UI must wait for XFCE readiness and remain on the home screen after failure")
    ordered = ["linuxRuntime.provision(", "linuxRuntime.prepareXfceDesktop(", "awaitXfcePreparation(", "startEmbeddedXServer()", "linuxRuntime.startXfceDesktop(logFile)", "awaitXfceSession(process, logFile)"]
    positions = [activity.index(token, activity.index("private void installAndLaunchXfceDesktop()")) for token in ordered]
    if positions != sorted(positions):
        raise SystemExit("Debian/XKB preparation must finish before Lorie starts; XFCE must be ready before its display opens")
    if activity.index("awaitXfceSession(process, logFile)") > activity.index("openReadyDesktopDisplay();", activity.index("awaitXfceSession(process, logFile)")):
        raise SystemExit("Android UI must not navigate to the display before the XFCE session is ready")
    subprocess.check_call(["sh", "-n", str(SESSION)])
    print("Bookworm ARM64 package availability and XFCE/PRoot startup contract passed.")
    for name in sorted(EXPECTED):
        print(f"{name}: {packages[name].get('Version')} ({packages[name].get('Architecture')})")


if __name__ == "__main__":
    main()
