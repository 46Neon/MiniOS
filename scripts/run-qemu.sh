#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="${1:-$ROOT/build/os.img}"
[[ "$IMG" = /* ]] || IMG="$ROOT/$IMG"
[[ -f "$IMG" ]] || { echo "No se encontró $IMG; primero construye la imagen." >&2; exit 1; }
QEMU_BIN="${QEMU:-}"
if [[ -z "$QEMU_BIN" ]]; then
  for candidate in qemu-system-x86_64 qemu-system-x86-64; do
    if command -v "$candidate" >/dev/null 2>&1; then QEMU_BIN="$candidate"; break; fi
  done
fi
[[ -n "$QEMU_BIN" ]] && command -v "$QEMU_BIN" >/dev/null 2>&1 || { echo "Instala QEMU x86-64 en Termux/Linux o define QEMU=/ruta/al/ejecutable." >&2; exit 1; }
RAM="${RAM:-2048}"
SMP="${SMP:-2}"
DISPLAY_BACKEND="${QEMU_DISPLAY:-sdl}"
ARGS=(-machine pc -accel "${QEMU_ACCEL:-tcg,thread=multi}" -m "$RAM" -smp "$SMP" -cpu max
      -drive "file=$IMG,format=raw,if=ide,index=0" -netdev user,id=n0 -device e1000,netdev=n0
      -vga std -display "$DISPLAY_BACKEND" -serial stdio -monitor none)
if [[ "${DEBUG:-0}" = 1 ]]; then
  mkdir -p "$ROOT/build"
  ARGS+=(-d int,cpu_reset -D "$ROOT/build/qemu-debug.log" -no-reboot)
fi
exec "$QEMU_BIN" "${ARGS[@]}"
