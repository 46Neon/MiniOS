#!/usr/bin/env bash
# LEGACY Debian/QEMU path; not used by the native Termux desktop.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Never delete build/os.img here: the next successful build archives it first.
rm -rf -- "$ROOT/build/work" "$ROOT/build/os.img.new" "$ROOT/build/os.img.tmp"
mkdir -p "$ROOT/build"
printf 'Se limpiaron temporales; la imagen existente se conservó.\n'
