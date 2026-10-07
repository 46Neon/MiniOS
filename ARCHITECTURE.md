# MiniAriño Android desktop architecture

## Decision status

**Recommended target architecture — proposal/decision, not implemented or validated.** This document records the recommended direction for MiniAriño's eventual single-APK desktop. It is not a description of working Wayland support. The current APK prototype remains an Lorie/X11-based implementation; it has not been replaced by this design. There is no physical-device XFCE validation, and the existing CI evidence is limited to an x86_64 emulator PRoot smoke test. See [`docs/APK_DESKTOP_ROADMAP.md`](docs/APK_DESKTOP_ROADMAP.md) for the verified status and staged acceptance plan.

## Product and system boundary

The product target is **one Android APK** that provisions and presents its desktop from its own UI and private app storage. The final experience must not require a separately installed or launched Termux, Termux:X11, VNC, or another desktop/display application. It must not require developer options. A fixed 16 GB QEMU image is not the product storage model.

Recommended target stack:

1. **Android application and host compositor:** the APK owns the Android Activity, lifecycle, native `Surface`, touch/keyboard input, and an Android/NDK-hosted Wayland compositor. The compositor renders into Android's native surface and exposes its Wayland socket to the guest. This host compositor is application-side native code; it is not labwc.
2. **Guest environment:** an ARM64 PRoot userland stored in app-private, incrementally provisioned files. Debian Trixie ARM64 is the preferred first rootfs candidate to evaluate. Arch ARM64 is a comparison candidate, not the default.
3. **Guest graphical session:** first prove a minimal Wayland client in the PRoot guest can connect to the host compositor and render/input correctly. Then evaluate labwc as the guest nested compositor/session component, and only after that bring up XFCE 4.20 or later over Wayland on labwc. XFCE 4.20 Wayland support is experimental; the Wayland session must not be called working until it passes the defined tests. The current official Debian Trixie package index lists `xfce4-session` version `4.20.2-2`; that package listing establishes a candidate to evaluate, not a successful session.
4. **Optional X11 compatibility:** Xwayland may be added later for legacy X11 applications if required. It is optional and is not a foundation for the Wayland-first target.

The final architecture does not depend on a build-time Lorie patch or transform. That is a target-state constraint, **not** a claim that the present Lorie/X11 prototype or its build integration has already been removed. Existing code and route remain until a separately implemented and validated replacement is ready.

## Compositor responsibilities and first proof of concept

The first graphics proof must test the Android-side host Wayland server, not labwc in isolation. The initial PoC must:

- build/run a host-side Wayland compositor component inside the Android app using the NDK and render through Android's native surface;
- provide a usable Wayland socket from that app-side server to a minimal Wayland client process running in the ARM64 PRoot guest (including proving the socket/path and access arrangement across the guest boundary);
- render a solid-color/test window produced by the guest client on the Android surface; and
- deliver Android touch and keyboard input through the host compositor to that guest client, with observable input acknowledgement.

A successful PoC requires evidence of both rendering and input, plus clean lifecycle/error behavior. Only after this gate passes should labwc be introduced as the guest nested compositor/session component; XFCE comes after labwc. **labwc is not the Android-side host Wayland server and must not be used alone as the first Android compositor test.**

This work is substantially more than drawing a bitmap or desktop mockup on an Android `Canvas`: it requires a real Wayland server and protocol/client interaction, surface/buffer exchange and composition, input-device/event translation, socket access across PRoot, synchronization, lifecycle, and diagnostics. Canvas-only output does not satisfy the PoC.

## Rootfs, storage, and first-run setup

Use an app-private, incrementally provisioned ARM64 filesystem rather than a monolithic 16 GB image. Keep the verified base separate from mutable package/update state, user configuration/files, caches, and any staged installation or rollback copy. Pin source/version and validate downloaded content before activation. Install and update transactionally so interruption cannot promote a partial rootfs or destroy user data.

The app must prepare a usable session automatically, including a **non-root guest user and session setup** as a product requirement. This is a requirement for future implementation, not a claim that automatic user creation, `sudo`, or session setup already exists in the prototype. Do not make `sudo` availability a promise; select and test a privilege model appropriate to PRoot and package management.

Before downloading or extracting, the Android app must perform a storage preflight using Android `StatFs` for the actual app-private destination volume. The plan must use measured values for at least:

- compressed rootfs download;
- expanded base rootfs;
- installed XFCE, labwc, and their dependencies;
- temporary download, package-cache, and extraction/staging space; and
- a rollback/recovery reserve while a previous base or user data must be retained.

Report download size separately from installed and peak temporary space. Recheck available space before large phases and explain whether cleanup, retry, or cancellation is safe. Initial estimates are not release measurements: record real measurements from supported ARM64 devices before claiming a space requirement.

First-run setup must resume after process death or device restart from verified checkpoints, detect and clean up or recover incomplete staging safely, preserve user data, and give clear in-app progress and error UI. Define online and offline behavior explicitly: online installation fetches only pinned/verified inputs; offline setup may proceed only from already available and validated inputs, otherwise explain what is missing and offer a retry path. Do not direct users to a developer-options switch, external terminal, or ad hoc user-run Python/shell preflight script.

## Candidate host/guest boundary

The Android app owns rendering to the native surface and host input capture. A Wayland socket connects the host compositor to guest clients. The first PoC should keep the guest client deliberately minimal so that failure points are attributable: native surface creation, compositor startup, protocol support, socket exposure/permissions, guest connection, rendering, touch, keyboard, and lifecycle. Record the chosen socket transport/path and its PRoot bind/access behavior. Do not infer that a successful native window or an emulator smoke test proves the complete chain.

Once the direct test client passes, evaluate labwc as the nested guest compositor attached to the host Wayland compositor. Then evaluate XFCE's experimental Wayland session on that guest labwc environment. Xwayland is a later optional compatibility layer for X11 applications and must not block validation of the Wayland-first base.

## Current implementation and evidence (preserved facts)

- The current APK prototype still uses Lorie/X11 and declares `targetSdk 28`.
- Existing CI is an **x86_64 emulator PRoot smoke only**. It does not establish ARM64 PRoot or rootfs operation, integrated graphics, Wayland/X11 desktop rendering, touch/keyboard delivery, or a usable XFCE session on a physical device.
- There is no physical-device XFCE validation.
- The proposed Android-hosted Wayland architecture, its NDK compositor, guest socket handoff, labwc session, and XFCE Wayland path are **not yet code** and are not validated.
- Keep existing prototype files and route intact until replacement code has been implemented and validated. Documentation of the target does not silently replace or deprecate working-in-progress prototype components.

## Acceptance order

1. Implement and test the Android/NDK host-side Wayland compositor PoC with the guest solid-color client and touch/keyboard round trip.
2. Test the socket, PRoot ARM64 boundary, lifecycle, cancellation, error reporting, and measured storage preparation on a physical ARM64 device.
3. Add labwc as the guest nested compositor and pass its own launch/render/input checks.
4. Add a non-root guest-user/session bootstrap and evaluate Debian Trixie ARM64 XFCE 4.20+ Wayland; demonstrate, rather than assume, session, panel, terminal, and file-manager usability.
5. Consider optional Xwayland and additional applications only after the Wayland-first base is stable.

Each gate requires actual implementation artifacts and runtime evidence. Architecture text, package-index availability, emulator-only results, and a Canvas test are not substitutes for those gates.
