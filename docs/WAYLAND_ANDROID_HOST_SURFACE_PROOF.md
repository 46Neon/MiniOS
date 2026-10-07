# MiniAriño Android-hosted Wayland proof slice

Status: **source/build gate in progress; runtime render not yet evidenced**. This debug-only slice adds an Android-owned libwayland server and a deliberately separate libwayland client connection. It does not replace the default embedded Lorie/X11 desktop route and does not rely on an external Termux runtime.

## What this slice implements

- A debug-only Home screen action opens `WaylandProofActivity`; the existing default Home and XFCE/Lorie flow remain unchanged. The Activity is registered only by `src/debug/AndroidManifest.xml`.
- A JNI host creates a real `wl_display`, `wl_compositor`, and `wl_shm` global, listening on `files/tmp/wayland-0` inside MiniAriño's private app data. `ANativeWindow_fromSurface()` binds that server to an Android `SurfaceView`.
- The button starts the test peer using the real libwayland client API. The peer connects through the Unix socket, discovers `wl_compositor` and `wl_shm`, creates an ARGB8888 shared-memory buffer, attaches it to a `wl_surface`, and commits it. The host copies the submitted pixels into the acquired `ANativeWindow` buffer and posts it. The test reports PASS only after the frame callback and host post counter confirm this path.
- The peer currently runs as another thread in the app process, but it uses a distinct `wl_display_connect()` client connection and the actual Unix-domain socket. It is **not** an in-memory protocol or Canvas mock.
- The pinned libwayland 1.24.0 / libffi API-26 ARM64 cross-build now also compiles `libwayland_android_host.so`, stages its SONAME dependencies and runtime notices into the debug APK source set, and validates the JNI ELF as AArch64/API 26. No APK should be treated as a runtime result merely because it assembles.

## Explicit acceptance gates

1. **Native build/package gate:** pinned dependencies and JNI host/client compile; the server, client, libffi, and JNI ELF checks pass; notices are included; an ARM64-only debug APK assembles with `minSdk 26`, `targetSdk 28`, and `.sdk28test` identity. This is a build/package check only.
2. **Host protocol/surface gate:** open the debug-only screen on an ARM64 Android runtime, press the test-client button, and verify the vivid green surface and PASS status. The current in-process peer can only establish this host socket/protocol/ANativeWindow slice. An x86_64 emulator build/package check does not satisfy this gate.
3. **Following guest gate:** run an ARM64 Wayland client from the existing Debian ARM64 PRoot rootfs, with the app-private host socket exposed through the existing PRoot `/tmp` bind. Verify a guest process connects, submits a `wl_shm` frame, and receives its frame callback. The current code does not implement this bind, and no guest connection is claimed.
4. **Immediate next acceptance gate after a verified host surface:** implement and test Android touch/keyboard-to-Wayland seat forwarding with a meaningful client acknowledgement path. There is currently no `wl_seat`, pointer, keyboard, or input forwarding.
5. **Physical-device evidence:** capture a real ARM64 device run proving the submitted pixels were visibly rendered. No physical-device run or input round trip has been performed or is implied by CI.

The isolated dependency workflow must build and package only after its compile and ELF checks pass. Existing x86_64 emulator testing is kept separate from ARM64 JNI/runtime coverage. PolarBear is not used or vendored; the upstream Wayland and libffi notices are retained with the packaged debug dependencies.
