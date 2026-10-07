# MiniAriño single-APK XFCE integration spike

This branch advances the single ARM64 Android APK prototype from the Debian `xmessage` build probe to an app-private XFCE session launch flow. The APK embeds the Android UI and Lorie X11 server; on first desktop launch it downloads a pinned Debian Bookworm-slim ARM64 OCI rootfs into private internal storage, then Debian's Bookworm APT repositories install XFCE, `xfce4-terminal`, Thunar, and D-Bus support. PRoot shares the app-owned temporary directory with guest `/tmp` and starts the session on Lorie display `:0`. No QEMU, amd64 image, separate Termux/Termux:X11 app, or TUR is used.

This remains an **integration spike, not a device-verified desktop**. The CI contract check can verify repository package metadata and startup wiring but cannot run Android PRoot, validate the phone's SELinux/ptrace behavior, confirm the Lorie Unix socket, display XFCE windows, or exercise Android lifecycle handling. Do not claim that the desktop works on a physical device until those checks are performed.

## First desktop launch

1. Tap **Start / open X11** or **Install XFCE desktop + start session**. The app-owned Lorie display is opened in the same APK.
2. The latter flow downloads/verifies/extracts the pinned Debian ARM64 rootfs if necessary, then runs the packaged guest launcher. It installs these official Bookworm packages with `apt-get update` and `apt-get install --no-install-recommends`:
   - `xfce4` (desktop/session components)
   - `xfce4-terminal` (terminal)
   - `thunar` (file manager)
   - `dbus-x11` (D-Bus X11 session launcher)
3. The guest environment exports `DISPLAY=:0`, binds the app-private X11 temporary/socket directory as Debian `/tmp`, creates a private XDG runtime directory, starts `dbus-launch --exit-with-session startxfce4`, and launches Thunar and an XFCE terminal.
4. The app reports that the session is running only after its log contains a readiness marker emitted after (a) `org.xfce.SessionManager` registers on the private D-Bus session bus, (b) the terminal and Thunar processes remain alive, and (c) the session process remains alive. Early exit and timeout are reported as failures; logs are `xfce-desktop.log` and `x11-server.log` in app-private storage. **Stop X server** also signals the tracked PRoot session and Lorie process.

The first download and APT installation require network access and substantial free app-private storage. Packages come from the Debian Bookworm repositories configured in the pinned Debian rootfs; their Debian revisions may be updated by that suite over time. The CI contract test fetches the Bookworm ARM64 package index and confirms that each requested package exists for `arm64` or `all`, and syntax-checks the guest launcher.

## Runtime design and pinned inputs

- ABI/userland: Android ARM64 (`arm64-v8a`) and Debian ARM64 on the Android host kernel.
- PRoot: Termux package `5.1.107.96`, source/build metadata commit [`de39661946f7e8175b5dd0755121fa28cb0aebd1`](https://github.com/termux/termux-packages/commit/de39661946f7e8175b5dd0755121fa28cb0aebd1). The fixed ARM64 `.deb` package URLs, SHA-256 checks, architecture checks, and APK asset staging are in `scripts/fetch_proot_runtime.py`. The exact hashes are checked in the build workflow before APK packaging. PRoot is GPL-2.0; `libtalloc` is GPL-3.0; `libandroid-shmem` is BSD-3-Clause. License texts are bundled under `app/src/main/assets/proot-licenses/`.
- Debian: official Docker Library `debian:bookworm-slim`, ARM64 OCI manifest `sha256:a1b86db52ce3daef089e45aabe36dfec4091f82464c25c1fdcf03de197cbe82a`; the app verifies its manifest hash and expected one-layer descriptor. The 28,137,179-byte compressed layer must match `sha256:c75f989a229d12b2d2613a5997de9ff3546f664c22da9248720033a2410220f6` before extraction. Both digests are recorded in the private installation marker.
- Rootfs, downloaded layer, APT state, session script, and logs remain under app-private `getFilesDir()` storage. Shared folders are exposed only through Android's Storage Access Framework picker.

## What passing CI verifies

The workflow builds a debug APK and verifies its package identity, ARM64 native libraries, expected pinned PRoot assets/licenses, and artifact SHA-256. It also:

- downloads Debian's Bookworm `binary-arm64/Packages.xz` index and checks that `xfce4`, `xfce4-terminal`, `thunar`, `dbus-x11`, and `dbus-bin` are available for ARM64 or as architecture-independent packages;
- runs `sh -n` on the guest startup script and checks the package list, `DISPLAY=:0`/`/tmp` binding, shared XFCE readiness marker, D-Bus session-manager gate, and Android UI's wait/failure handling;
- compiles and packages the Android application with the embedded Lorie sources.

CI does **not** boot or install the APK on an Android device, provision the rootfs under Android, run `apt-get` inside PRoot, prove that the host and guest see the same X11 socket, or observe an XFCE/terminal/Thunar window. Required phone validation remains: install on the target ARM64 Android version, complete rootfs download/extraction and package installation, verify all three windows on Lorie `:0`, confirm keyboard/input and app switching, stop/restart the session and server, and check behavior after Android pauses or reclaims the app. Godot, Chromium, and Blender are not part of this milestone and are not claimed as installed.
