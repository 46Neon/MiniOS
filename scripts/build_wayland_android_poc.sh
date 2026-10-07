#!/usr/bin/env bash
# Compile-only, pinned Android ARM64 dependency gate for the Wayland PoC.
# This deliberately does not stage anything into the Android app or APK.
set -euo pipefail

readonly WAYLAND_COMMIT='736d12ac67c20c60dc406dc49bb06be878501f86'
readonly WAYLAND_SHA256='3caeb8cbc1391d050e1dfa3f7622bd6d66ed770897e25bad2515261cba9d7ebd'
readonly LIBFFI_VERSION='3.4.8'
readonly LIBFFI_SHA256='bc9842a18898bfacb0ed1252c4febcc7e78fa139fd27fdc7a3e30d9d9356119b'
readonly NDK_VERSION='29.0.14206865'
readonly ANDROID_API='26'
readonly ARCH='aarch64'

: "${ANDROID_HOME:?ANDROID_HOME must point to the Android SDK}"
NDK="${ANDROID_NDK_HOME:-${ANDROID_HOME}/ndk/${NDK_VERSION}}"
[[ -f "$NDK/source.properties" ]] || { echo "NDK source.properties missing: $NDK" >&2; exit 1; }
grep -Fq "Pkg.Revision = ${NDK_VERSION}" "$NDK/source.properties" || {
  echo "Expected Android NDK ${NDK_VERSION}" >&2; cat "$NDK/source.properties"; exit 1;
}
readonly TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
readonly CC="$TOOLCHAIN/aarch64-linux-android${ANDROID_API}-clang"
readonly CXX="$TOOLCHAIN/aarch64-linux-android${ANDROID_API}-clang++"
readonly AR="$TOOLCHAIN/llvm-ar"
readonly RANLIB="$TOOLCHAIN/llvm-ranlib"
readonly STRIP="$TOOLCHAIN/llvm-strip"
readonly READELF="$TOOLCHAIN/llvm-readelf"
readonly WORK="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/wayland-android-api26"
readonly ARTIFACT="${GITHUB_WORKSPACE:-$PWD}/artifacts/wayland-android-arm64-api26"
readonly HOST_PREFIX="$WORK/host-prefix"
readonly TARGET_PREFIX="$WORK/target-prefix"
readonly WAYLAND_ARCHIVE="$WORK/wayland-${WAYLAND_COMMIT}.tar.gz"
readonly LIBFFI_ARCHIVE="$WORK/libffi-${LIBFFI_VERSION}.tar.gz"

for tool in "$CC" "$CXX" "$AR" "$RANLIB" "$STRIP" "$READELF" meson ninja pkg-config sha256sum; do
  command -v "$tool" >/dev/null || { echo "Required tool not found: $tool" >&2; exit 1; }
done
mkdir -p "$WORK/src" "$ARTIFACT/lib" "$ARTIFACT/notices"
rm -f "$ARTIFACT/lib/"* "$ARTIFACT/notices/"*

{
  echo '=== Host runner ==='
  uname -a
  meson --version
  ninja --version
  pkg-config --version
  "$CC" --version | head -n 1
  "$CXX" --version | head -n 1
  grep -E '^(Pkg.Desc|Pkg.Revision) =' "$NDK/source.properties"
  echo '=== Android target ==='
  echo "NDK C compiler: $CC"
  "$CC" -dumpmachine
  echo "NDK C++ compiler: $CXX"
  "$CXX" -dumpmachine
  echo "Android API: $ANDROID_API"
} | tee "$ARTIFACT/build-metadata.txt"

curl --fail --location --retry 3 \
  "https://codeload.github.com/wayland-mirror/wayland/tar.gz/${WAYLAND_COMMIT}" \
  --output "$WAYLAND_ARCHIVE"
curl --fail --location --retry 3 \
  "https://github.com/libffi/libffi/releases/download/v${LIBFFI_VERSION}/libffi-${LIBFFI_VERSION}.tar.gz" \
  --output "$LIBFFI_ARCHIVE"
printf '%s  %s\n' "$WAYLAND_SHA256" "$WAYLAND_ARCHIVE" | sha256sum --check
printf '%s  %s\n' "$LIBFFI_SHA256" "$LIBFFI_ARCHIVE" | sha256sum --check

tar -xzf "$WAYLAND_ARCHIVE" -C "$WORK/src"
tar -xzf "$LIBFFI_ARCHIVE" -C "$WORK/src"
readonly WAYLAND_SRC="$WORK/src/wayland-${WAYLAND_COMMIT}"
readonly LIBFFI_SRC="$WORK/src/libffi-${LIBFFI_VERSION}"
[[ -f "$WAYLAND_SRC/COPYING" && -f "$LIBFFI_SRC/LICENSE" ]]
grep -Fq "version: '1.24.0'" "$WAYLAND_SRC/meson.build" || {
  echo 'Pinned Wayland archive does not identify itself as version 1.24.0' >&2; exit 1;
}

# Upstream Meson enables libraries by default, requires libffi and probes
# signalfd, timerfd, and CLOCK_MONOTONIC. Scanner generation is a native build
# tool, so build that exact upstream scanner natively first, then cross-compile
# the libraries with tests/docs/DTD validation disabled for Android.
meson setup "$WORK/host-scanner-build" "$WAYLAND_SRC" \
  --prefix="$HOST_PREFIX" \
  -Ddefault_library=static -Dlibraries=false -Dscanner=true \
  -Dtests=false -Ddocumentation=false -Ddtd_validation=false
meson compile -C "$WORK/host-scanner-build"
meson install -C "$WORK/host-scanner-build"

export CC CXX AR RANLIB STRIP
export CFLAGS='-O2 -fPIC'
export CXXFLAGS='-O2 -fPIC'
export CPPFLAGS=''
export PKG_CONFIG_PATH="$TARGET_PREFIX/lib/pkgconfig"
( cd "$LIBFFI_SRC" && ./configure \
  --build="$(sh ./config.guess)" \
  --host=aarch64-linux-android \
  --prefix="$TARGET_PREFIX" \
  --enable-shared --disable-static --disable-docs \
  --disable-multi-os-directory )
make -C "$LIBFFI_SRC" -j"$(nproc)"
make -C "$LIBFFI_SRC" install

# Meson asks for target-machine libffi through pkg-config and the native scanner
# through its installed native pkg-config file. The target prefix does not
# contain host libraries; only the native scanner's .pc directory is added to
# PKG_CONFIG_PATH.
HOST_TRIPLET="$(gcc -print-multiarch)"
export PKG_CONFIG_PATH="$TARGET_PREFIX/lib/pkgconfig:$HOST_PREFIX/lib/$HOST_TRIPLET/pkgconfig:$HOST_PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$TARGET_PREFIX/lib/pkgconfig:$HOST_PREFIX/lib/$HOST_TRIPLET/pkgconfig"
# Confirm Meson's native build-time generator is visible before entering the
# Android cross build; this prevents a silent host/target pkg-config mix-up.
pkg-config --modversion wayland-scanner
SCANNER="$(pkg-config --variable=wayland_scanner wayland-scanner)"
[[ -x "$SCANNER" ]] || { echo "Native wayland-scanner not executable: $SCANNER" >&2; exit 1; }
cat > "$WORK/android-aarch64.ini" <<EOF
[binaries]
c = '$CC'
ar = '$AR'
strip = '$STRIP'
pkg-config = '$(command -v pkg-config)'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
needs_exe_wrapper = true
pkg_config_libdir = ['$TARGET_PREFIX/lib/pkgconfig', '$HOST_PREFIX/lib/$HOST_TRIPLET/pkgconfig']
EOF
meson setup "$WORK/wayland-build" "$WAYLAND_SRC" \
  --cross-file "$WORK/android-aarch64.ini" \
  --prefix="$TARGET_PREFIX" \
  -Ddefault_library=shared -Dlibraries=true -Dscanner=false \
  -Dtests=false -Ddocumentation=false -Ddtd_validation=false
meson compile -C "$WORK/wayland-build"
meson install -C "$WORK/wayland-build"

# Preserve the original third-party notices in the inspection artifact.
cp "$WAYLAND_SRC/COPYING" "$ARTIFACT/notices/libwayland-COPYING-MIT-Expat.txt"
cp "$LIBFFI_SRC/LICENSE" "$ARTIFACT/notices/libffi-LICENSE.txt"
cp "$TARGET_PREFIX"/lib/libwayland-server.so* "$ARTIFACT/lib/"
cp "$TARGET_PREFIX"/lib/libwayland-client.so* "$ARTIFACT/lib/"
cp "$TARGET_PREFIX"/lib/libffi.so* "$ARTIFACT/lib/"

# Every copied shared object must be an Android ARM64 ELF with an Android
# ident note whose first little-endian uint32 descriptor is exactly API 26.
# llvm-readelf renders that descriptor as bytes (for API 26: 1a 00 00 00),
# not as a textual "API: 26" field.
validate_android_shared_library() {
  local name="$1" library="$ARTIFACT/lib/$1" header="$WORK/$1-elf-header.txt" notes="$WORK/$1-elf-notes.txt"
  [[ -s "$library" ]] || { echo "Expected Android shared library missing: $library" >&2; ls -la "$ARTIFACT/lib"; exit 1; }
  file "$library" | tee -a "$ARTIFACT/build-metadata.txt"
  "$READELF" --file-header "$library" | tee "$header"
  grep -Eq 'Class:[[:space:]]+ELF64' "$header"
  grep -Eq 'Data:[[:space:]]+2.s complement, little endian' "$header"
  grep -Eq 'Machine:[[:space:]]+AArch64' "$header"
  "$READELF" --notes "$library" | tee "$notes"
  python3 - "$notes" "$ANDROID_API" "$name" <<'PYVALIDATE'
import re
import sys

path, expected_text, name = sys.argv[1:]
text = open(path, encoding="utf-8").read()
if not re.search(r"^\s*Android\s+0x[0-9a-fA-F]+\s+NT_ANDROID_TYPE_IDENT\s*$", text, re.MULTILINE):
    raise SystemExit(f"{name}: missing NT_ANDROID_TYPE_IDENT note")
match = re.search(r"^\s*description data:\s*((?:[0-9a-fA-F]{2}\s*)+)$", text, re.MULTILINE)
if not match:
    raise SystemExit(f"{name}: cannot parse raw Android ident descriptor bytes")
descriptor = bytes(int(token, 16) for token in re.findall(r"[0-9a-fA-F]{2}", match.group(1)))
if len(descriptor) < 4:
    raise SystemExit(f"{name}: Android ident descriptor is shorter than 4 bytes")
api = int.from_bytes(descriptor[:4], byteorder="little", signed=False)
expected = int(expected_text, 10)
if api != expected:
    raise SystemExit(f"{name}: Android ELF API descriptor is {api}, expected {expected}")
print(f"{name}: verified Android ELF API {api} from descriptor bytes {descriptor[:4].hex(' ')}")
PYVALIDATE
}

SERVER="$ARTIFACT/lib/libwayland-server.so"
CLIENT="$ARTIFACT/lib/libwayland-client.so"
LIBFFI="$ARTIFACT/lib/libffi.so"
validate_android_shared_library libwayland-server.so
validate_android_shared_library libwayland-client.so
validate_android_shared_library libffi.so
"$READELF" --dynamic-table "$SERVER" | tee "$WORK/server-dynamic.txt"
grep -Eq 'Shared library: \[libffi\.so(\.8)?\]' "$WORK/server-dynamic.txt"
grep -Fq 'Shared library: [libc.so]' "$WORK/server-dynamic.txt"

{
  echo
  echo '=== Pinned inputs ==='
  echo "libwayland version: 1.24.0"
  echo "libwayland commit: $WAYLAND_COMMIT"
  echo "libwayland archive SHA-256: $WAYLAND_SHA256"
  echo "libffi version: $LIBFFI_VERSION"
  echo "libffi source archive SHA-256: $LIBFFI_SHA256"
  echo "NDK: $NDK_VERSION"
  echo "Android minimum API target: $ANDROID_API"
  echo 'Validation: libwayland server/client and libffi are ELF64 little-endian AArch64; their Android ident descriptors encode API 26; server links libffi.so and libc.so.'
} | tee -a "$ARTIFACT/build-metadata.txt"
find "$ARTIFACT" -type f -print0 | sort -z | xargs -0 sha256sum > "$ARTIFACT/SHA256SUMS"
cat "$ARTIFACT/SHA256SUMS"
