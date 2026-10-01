#!/usr/bin/env python3
"""Validate the installed XFCE/LightDM configuration inside a MiniAriño rootfs."""
from __future__ import annotations

import configparser
import os
import pathlib
import shlex
import subprocess
import sys
import xml.etree.ElementTree as ET


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} ROOTFS", file=sys.stderr)
        return 2
    root = pathlib.Path(sys.argv[1]).resolve()
    if not root.is_dir():
        print(f"FAIL root filesystem not found: {root}", file=sys.stderr)
        return 2
    failures: list[str] = []
    passed = 0

    def check(label: str, condition: bool, detail: str = "") -> None:
        nonlocal passed
        if condition:
            passed += 1
            print(f"PASS  {label}")
        else:
            failures.append(label)
            print(f"FAIL  {label}" + (f": {detail}" if detail else ""))

    def path(p: str) -> pathlib.Path:
        return root / p.lstrip("/")

    # The installed image is Debian binary packages, not an upstream source build.
    installed: set[str] = set()
    status_file = path("/var/lib/dpkg/status")
    if status_file.is_file():
        for stanza in status_file.read_text(errors="replace").split("\n\n"):
            fields = {}
            for line in stanza.splitlines():
                if line and not line[0].isspace() and ": " in line:
                    key, value = line.split(": ", 1)
                    fields[key] = value
            if fields.get("Status") == "install ok installed":
                installed.add(fields.get("Package", ""))
    required_packages = {
        "lightdm", "xfce4", "xfce4-goodies", "thunar", "xfce4-terminal",
        "firefox-esr", "desktop-file-utils", "x11-utils", "x11-xserver-utils",
        "dbus-x11", "network-manager",
    }
    missing = sorted(required_packages - installed)
    check("Required Debian desktop packages installed", not missing, ", ".join(missing))

    required_bins = [
        "/usr/bin/startxfce4", "/usr/sbin/lightdm", "/usr/bin/xfce4-session",
        "/usr/bin/xfwm4", "/usr/bin/xfce4-panel", "/usr/bin/xfdesktop",
        "/usr/bin/xfconf-query", "/usr/bin/thunar", "/usr/bin/xfce4-terminal",
        "/usr/bin/firefox-esr", "/usr/bin/synaptic-pkexec", "/usr/bin/desktop-file-validate",
        "/usr/bin/xprop", "/usr/bin/xdpyinfo", "/usr/bin/xrandr", "/usr/bin/dbus-send",
    ]
    absent_bins = [p for p in required_bins if not (path(p).is_file() and os.access(path(p), os.X_OK))]
    check("XFCE, diagnostics and application executables installed", not absent_bins, ", ".join(absent_bins))

    passwd = path("/etc/passwd").read_text(errors="replace") if path("/etc/passwd").is_file() else ""
    account = next((row.split(":") for row in passwd.splitlines() if row.startswith("miniarino:")), None)
    check("miniarino account has the expected home and shell",
          bool(account and len(account) >= 7 and account[5] == "/home/miniarino" and account[6] == "/bin/bash"),
          "missing account or unexpected home/shell")

    lightdm_file = path("/etc/lightdm/lightdm.conf.d/50-miniarino.conf")
    cfg = configparser.ConfigParser()
    try:
        cfg.read(lightdm_file, encoding="utf-8")
        seat = cfg["Seat:*"]
        lightdm_ok = (seat.get("autologin-user") == "miniarino"
                      and seat.get("autologin-session") == "xfce"
                      and seat.get("user-session") == "xfce")
    except (OSError, KeyError, configparser.Error):
        lightdm_ok = False
    check("LightDM autologin and XFCE session configuration", lightdm_ok)

    session_file = path("/usr/share/xsessions/xfce.desktop")
    session_ok = session_file.is_file()
    if session_ok:
        session_cfg = configparser.ConfigParser(interpolation=None)
        try:
            session_cfg.read(session_file, encoding="utf-8")
            session = session_cfg["Desktop Entry"]
            session_ok = (session.get("Type") == "Application"
                          and bool(session.get("Exec"))
                          and session.get("Exec", "").split()[0] in {"startxfce4", "/usr/bin/startxfce4"})
        except (KeyError, configparser.Error):
            session_ok = False
    check("XFCE X session is registered with LightDM", session_ok)

    # Validate the generated enablement links rather than assuming systemctl's
    # host-side view can inspect a read-only mounted guest filesystem.
    service_links = {
        "/etc/systemd/system/multi-user.target.wants/NetworkManager.service": {
            "/lib/systemd/system/NetworkManager.service", "/usr/lib/systemd/system/NetworkManager.service"},
        "/etc/systemd/system/multi-user.target.wants/miniarino-welcome.service": {"../miniarino-welcome.service"},
        "/etc/systemd/system/display-manager.service": {
            "/lib/systemd/system/lightdm.service", "/usr/lib/systemd/system/lightdm.service"},
    }
    for link, targets in service_links.items():
        full = path(link)
        actual = os.readlink(full) if full.is_symlink() else ""
        target_path = path(actual) if actual.startswith("/") else full.parent / actual
        check(f"Enabled systemd service link: {link}", actual in targets and target_path.is_file(),
              f"unexpected or dangling target: {actual or 'missing'}")
    check("MiniAriño welcome service installed", path("/etc/systemd/system/miniarino-welcome.service").is_file())

    wallpaper = path("/usr/share/backgrounds/miniarino-wallpaper.svg")
    check("MiniAriño wallpaper installed", wallpaper.is_file() and wallpaper.stat().st_size > 0)
    xfce_xml = path("/home/miniarino/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml")
    try:
        xml_root = ET.parse(xfce_xml).getroot()
        configured_wallpaper = xml_root.find(".//property[@name='last-image']")
        wallpaper_config_ok = (configured_wallpaper is not None
                               and configured_wallpaper.get("value") == "/usr/share/backgrounds/miniarino-wallpaper.svg")
    except (OSError, ET.ParseError):
        wallpaper_config_ok = False
    check("User XFCE configuration selects MiniAriño wallpaper", wallpaper_config_ok)
    check("XFCE skeleton configuration installed", path("/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml").is_file())

    uid = int(account[2]) if account and account[2].isdigit() else -1
    gid = int(account[3]) if account and account[3].isdigit() else -1
    for folder in ("Desktop", "Documents", "Downloads", "Pictures"):
        d = path(f"/home/miniarino/{folder}")
        owned = False
        if d.is_dir() and uid >= 0 and gid >= 0:
            st = d.stat()
            owned = st.st_uid == uid and st.st_gid == gid and bool(st.st_mode & 0o200)
        check(f"User folder present and writable: {folder}", owned)

    launcher_names = ("Archivos.desktop", "Navegador.desktop", "Terminal.desktop",
                      "Programas.desktop", "Diagnostico.desktop")
    command_errors: list[str] = []
    launcher_errors: list[str] = []
    search_dirs = ("/usr/local/bin", "/usr/bin", "/usr/sbin", "/bin", "/sbin")
    for name in launcher_names:
        guest_path = f"/home/miniarino/Desktop/{name}"
        launcher = path(guest_path)
        if not launcher.is_file():
            launcher_errors.append(f"missing {name}")
            continue
        result = subprocess.run(["chroot", str(root), "desktop-file-validate", guest_path],
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if result.returncode:
            launcher_errors.append(f"{name}: {result.stdout.strip() or 'desktop-file-validate rejected it'}")
        parser = configparser.ConfigParser(interpolation=None, strict=True)
        try:
            parser.read(launcher, encoding="utf-8")
            entry = parser["Desktop Entry"]
            argv = shlex.split(entry.get("Exec", ""))
            if entry.get("Type") != "Application" or not argv:
                raise ValueError("invalid Type or empty Exec")
            command = argv[0]
            if command.startswith("/"):
                available = path(command).is_file() and os.access(path(command), os.X_OK)
            else:
                available = any((path(f"{directory}/{command}").is_file()
                                 and os.access(path(f"{directory}/{command}"), os.X_OK))
                                for directory in search_dirs)
            if not available:
                command_errors.append(f"{name}: command not installed: {command}")
        except (OSError, KeyError, ValueError, configparser.Error) as exc:
            launcher_errors.append(f"{name}: {exc}")
    check("All desktop launchers pass desktop-file-validate", not launcher_errors,
          "; ".join(launcher_errors))
    check("Desktop launcher commands resolve inside the image", not command_errors,
          "; ".join(command_errors))
    check("Installed diagnostic can run as an ordinary user",
          path("/usr/local/bin/miniarino-selftest").is_file()
          and os.access(path("/usr/local/bin/miniarino-selftest"), os.X_OK))

    print(f"\nMiniAriño XFCE image check: {passed} PASS, {len(failures)} FAIL")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
