# Android-hosted Wayland PoC dependency audit

**Current status:** pinned dependency and JNI host/client build wiring is implemented on `android-apk-desktop`. The source now contains a bounded debug-only host-surface proof slice; actual compilation, APK assembly, Android execution, visible render, guest connection, and input round trip must be established by their separate gates. See [the acceptance gates](WAYLAND_ANDROID_HOST_SURFACE_PROOF.md). This document supersedes the pre-implementation audit below and is not device-runtime evidence.

## Pinned dependency inputs

The app uses upstream **libwayland 1.24.0**, commit `736d12ac67c20c60dc406dc49bb06be878501f86`, plus **libffi 3.4.8**. `scripts/build_wayland_android_poc.sh` verifies source archive SHA-256 hashes, builds with the pinned NDK `29.0.14206865` for `aarch64-linux-android26`, carries the original Wayland/libffi notices into the debug APK assets, and validates ELF64/AArch64/Android-ident API 26 for the server, client, and JNI host. CI packages each shared object by its actual SONAME and checks the resulting ARM64 APK closure.

- Wayland source and license: <https://github.com/wayland-mirror/wayland/tree/736d12ac67c20c60dc406dc49bb06be878501f86>
- libffi source: <https://github.com/libffi/libffi/releases/tag/v3.4.8>
- The repository root has no project-wide `LICENSE`/`COPYING`; this change does not invent or modify one.
- PolarBear is discontinued/GPL-3.0 and is not copied or vendored. labwc is not used as the Android host server.

## What the code does—and does not—prove

The Android JNI host owns an app-private Unix socket and Android `Surface`/`ANativeWindow`; an opt-in debug Activity starts an independent libwayland client connection which submits an ARGB8888 `wl_shm` buffer. The peer is currently another thread in the same process, but it uses the real client library and socket. Its PASS result requires the host to post a native window buffer and deliver a frame callback. It is an executable **host protocol/surface** gate, not an in-memory mock and not a PRoot guest test.

The existing Lorie/X11 route remains the default. The host does not advertise `wl_seat`, and touch/keyboard forwarding is not implemented. The test socket is app-private and is not yet bound into the Debian guest. The follow-on guest gate and immediate next input-acceptance gate are described in the proof document. An x86_64 emulator is not evidence for the ARM64 JNI path or physical-device rendering.

No physical-device render or input result is claimed by this source change. A successful compile/package job would establish only its explicitly labeled build gate; a visible surface, ARM64 PRoot client, and input round trip remain separately unverified until actually exercised.
