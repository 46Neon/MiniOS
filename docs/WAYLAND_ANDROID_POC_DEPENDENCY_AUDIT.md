# Android-hosted Wayland PoC dependency audit

**Status: dependency direction identified; no compositor implementation or build was attempted.** This is a bounded technical audit for the first Android-hosted Wayland experiment, not evidence that Wayland currently works in MiniAriño.

## Project constraints verified in this source snapshot

- The Android app uses Android Gradle Plugin, Java 17, `minSdkVersion 26`, `targetSdkVersion 28`, and NDK `29.0.14206865`; debug package ID keeps the `.sdk28test` suffix (`android/app/build.gradle`).
- The existing screen starts the embedded Lorie/X11 session; `android/scripts/prepare_x11.py` is part of the current build setup. Keep that route and script intact until a Wayland replacement passes its full gate.
- The repository root has no `LICENSE`/`COPYING` declaration. Existing bundled components have their own notices (`android/lorie/LICENSE.upstream`, `android/vendor/termux-x11/LICENSE`, and the PRoot notices under app assets). Do not assume a project-wide license or silently change one.
- The Android app manifest/source currently has no Wayland host compositor or debug Wayland test activity. The existing PRoot tests use an x86_64 emulator fixture; that is not ARM64 or physical-device evidence.

## License-compatible candidate

The first dependency to prototype is **upstream libwayland 1.24.0**, pinned for evaluation at commit `736d12ac67c20c60dc406dc49bb06be878501f86`:

- Source and tag: <https://github.com/wayland-mirror/wayland/tree/736d12ac67c20c60dc406dc49bb06be878501f86>
- Upstream `COPYING` identifies the MIT/Expat license and requires retaining its copyright and permission notice: <https://github.com/wayland-mirror/wayland/blob/736d12ac67c20c60dc406dc49bb06be878501f86/COPYING>
- Upstream Meson configuration builds `libwayland-server` and `libwayland-client`; it requires `libffi` when libraries are enabled and checks for Linux facilities including `epoll`, `CLOCK_MONOTONIC`, `signalfd`/`SFD_CLOEXEC`, and `timerfd`/`TFD_CLOEXEC`: <https://github.com/wayland-mirror/wayland/blob/736d12ac67c20c60dc406dc49bb06be878501f86/meson.build>

This is a permissive, real Wayland protocol/server library—not a compositor backend and not a finished Android port. It is the most credible component to evaluate with the Android NDK because it is C code and its Meson feature checks make platform assumptions explicit. The app would still need its own small compositor/backend that owns an Android `Surface`/`ANativeWindow`, implements the minimal shell and `wl_shm` surface lifecycle, composites received buffers, and translates Android touch/key events into Wayland seat events. A Debian ARM64 guest can supply the minimal test client and protocol tools. `libffi` must also be cross-built or otherwise supplied for ARM64 with its license notice preserved; a Meson cross build and linkage against the selected Android API level must be demonstrated before calling this path buildable.

Use a pinned libwayland source archive and include its upstream `COPYING` notice in the app's third-party notices if bundled. Record and preserve the separate license/notices for libffi and any generated protocol source. Do not copy PolarBear code: that repository is discontinued and GPL-3.0, and this audit used architecture findings only. Do not adopt labwc as a substitute for the Android-side server.

## Concrete next implementation slice

1. On a toolchain-equipped runner, add a pinned Meson cross-build for libwayland 1.24.0 and a license-compatible libffi build for `arm64-v8a`, targeting Android API 26. Add a compile-only CI job first; package the notices and verify the resulting ELF ABI/minimum API.
2. Add an **opt-in debug-only** Android test activity/native entry point. It should create a real server-side Wayland display and Unix socket, render client-submitted `wl_shm` pixels to the Android native surface, and log protocol lifecycle/errors. Do not alter the default home screen/session route.
3. Build a tiny ARM64 Wayland client for the existing Debian ARM64 PRoot guest. Bind/expose the host socket into that guest and prove a real client connection and submitted surface; then add touch and keyboard events with client acknowledgement.
4. Keep each acceptance item separate: native library compile; APK assemble/install; Android host socket; ARM64 PRoot guest client connection; rendered surface on a physical ARM64 device; touch/key round trip. An x86_64 emulator test is useful for app packaging only and must not satisfy ARM64 or physical-device gates.

## Evidence and blockers for this audit

No Java executable, Android SDK/NDK toolchain, `clang`, CMake, Meson, Ninja, `adb`, or `sdkmanager` is available in the current execution environment/PATH; Android SDK environment variables are unset. The Gradle wrapper exits before project configuration because Java is unavailable. Therefore no native library was compiled, no APK was assembled or installed, and no socket/client/render/input test ran. No implementation scaffolding was added because none could be compiled or checked here. The exact next gate is to run the pinned libwayland + libffi Android API 26 cross-build on a configured CI runner and resolve any Bionic/NDK incompatibilities before wiring it into the APK.
