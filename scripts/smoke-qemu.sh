#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="${1:-$ROOT/build/os.img}"
[[ "$IMG" = /* ]] || IMG="$ROOT/$IMG"
QEMU="${QEMU:-qemu-system-x86_64}"
command -v "$QEMU" >/dev/null 2>&1 || { echo "QEMU no está instalado en el runner." >&2; exit 1; }
mkdir -p "$ROOT/build"
LOG="$ROOT/build/qemu-serial.log"
rm -f "$LOG"
"$QEMU" -machine pc -accel tcg,thread=multi -m 2048 -smp 2 -cpu max \
  -drive "file=$IMG,format=raw,if=ide,index=0" -netdev user,id=n0 -device e1000,netdev=n0 \
  -vga std -display none -serial "file:$LOG" -monitor none -no-reboot &
PID=$!
finish() { kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; }
trap finish EXIT
for _ in $(seq 1 150); do
  if grep -aq 'MiniAriño bienvenido' "$LOG" 2>/dev/null; then
    echo "OK: QEMU arrancó Linux y mostró el saludo en la consola serial."
    exit 0
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "QEMU terminó antes del saludo. Consola:" >&2
    cat "$LOG" >&2 || true
    exit 1
  fi
  sleep 1
done
echo "No apareció el saludo dentro del tiempo límite. Consola:" >&2
cat "$LOG" >&2 || true
exit 1
