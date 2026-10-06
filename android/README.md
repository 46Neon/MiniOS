# MiniAriño Android integration spike

This is a build-only integration experiment, not a usable desktop APK yet. It pins the upstream Termux:X11 source as a recursive Git submodule and packages its `:lorie` library into one Android package with application ID `org.miniarino.desktop`.

The current spike does **not** include a Linux root filesystem, PRoot, XFCE, terminal session, Godot, Chromium, Blender, or MiniAriño folder-management UI. Do not use this build as the requested desktop app. Its purpose is to prove that the upstream X11 Android component can be built into a single APK without installing the Termux:X11 APK separately.

## Build

GitHub Actions builds an ARM64 debug APK and checks its Android package identity. The upstream Lorie source is GPL-3.0; the upstream source is pinned by the submodule commit and must remain available with its license when distributing binaries.

## Follow-up milestones

1. Start and render an X11 session from the host app, then verify it on an ARM64 device.
2. Add an app-private ARM64 Linux userland and PRoot-based first-run provisioning without QEMU.
3. Install XFCE, terminal and file manager; add Godot 4, Chromium and Blender through verified ARM64 sources.
4. Add safe app-private folder creation/deletion and Android Storage Access Framework access for user-selected shared folders.
5. Build/install/test the full flow on-device before calling it complete.
