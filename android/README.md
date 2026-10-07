# MiniAriño Android integration spike

This is an early Android integration milestone, **not a usable Linux desktop APK yet**. It pins the upstream Termux:X11 source as a recursive Git submodule and packages its `:lorie` library into one Android package with application ID `org.miniarino.desktop`.

The host app now exposes a MiniAriño home screen, attempts to start the embedded Lorie X server in an app-owned `app_process`, opens the embedded display activity, and provides basic create / navigate / delete-empty-folder operations confined to its private workspace. Shared-folder selection uses Android's Storage Access Framework and persists the granted URI permission. These paths are code/build-validated only; physical Android testing is still required, especially to confirm process startup, display connection and SAF behavior.

This APK still does **not** contain or provision a Linux root filesystem or PRoot, so it cannot run a Linux desktop, terminal, XFCE, Godot, Chromium or Blender. The X display alone is blank until an X client session can be started. Do not use this build as the requested finished desktop.

## Build

GitHub Actions builds an ARM64 debug APK and checks its Android package identity. The upstream Lorie source is GPL-3.0; the upstream source is pinned by the submodule commit and must remain available with its license when distributing binaries.

## Follow-up milestones

1. Start and render an X11 session from the host app, then verify it on an ARM64 device.
2. Add an app-private ARM64 Linux userland and PRoot-based first-run provisioning without QEMU.
3. Install XFCE, terminal and file manager; add Godot 4, Chromium and Blender through verified ARM64 sources.
4. Add safe app-private folder creation/deletion and Android Storage Access Framework access for user-selected shared folders.
5. Build/install/test the full flow on-device before calling it complete.
