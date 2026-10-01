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
DISPLAY_BACKEND="${QEMU_DISPLAY:-auto}"
DISPLAY_HELP="$("$QEMU_BIN" -display help 2>&1 || true)"
supports_display() {
  local backend="$1"
  [[ "$backend" =~ ^[a-z0-9_-]+$ ]] || return 1
  grep -Eiq "^[[:space:]]*${backend}([[:space:],]|$)" <<<"$DISPLAY_HELP"
}
DISPLAY_ARGS=()
case "$DISPLAY_BACKEND" in
  auto)
    if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && supports_display sdl; then
      DISPLAY_BACKEND=sdl
    elif [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && supports_display gtk; then
      DISPLAY_BACKEND=gtk
    else
      DISPLAY_BACKEND=vnc
    fi
    ;;
  vnc)
    ;;
  *)
    if ! supports_display "$DISPLAY_BACKEND"; then
      echo "QEMU no ofrece el backend gráfico '$DISPLAY_BACKEND'. Disponibles:" >&2
      printf '%s\n' "$DISPLAY_HELP" >&2
      exit 1
    fi
    ;;
esac

if [[ "$DISPLAY_BACKEND" == vnc ]]; then
  VNC_ENDPOINT="${QEMU_VNC:-127.0.0.1:1}"
  DISPLAY_ARGS=(-display none -vnc "$VNC_ENDPOINT")
  printf 'Sin backend de ventana disponible; VNC escuchará en %s (puerto 5901 si usas :1).\n' "$VNC_ENDPOINT"
else
  DISPLAY_ARGS=(-display "$DISPLAY_BACKEND")
  printf 'Backend gráfico QEMU: %s.\n' "$DISPLAY_BACKEND"
  if [[ "$DISPLAY_BACKEND" == sdl || "$DISPLAY_BACKEND" == gtk ]] && [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    echo "No hay DISPLAY/WAYLAND_DISPLAY definido; inicia Termux:X11 y exporta DISPLAY=:0, o usa QEMU_DISPLAY=vnc." >&2
  fi
fi

USB_INPUT_MODE="${QEMU_USB_INPUT:-auto}"
USB_ARGS=()
case "$USB_INPUT_MODE" in
  off)
    ;;
  auto|on)
    DEVICE_HELP="$("$QEMU_BIN" -device help 2>&1 || true)"
    has_device() { grep -Fq "name \"$1\"" <<<"$DEVICE_HELP"; }
    if has_device qemu-xhci && has_device usb-tablet && has_device usb-kbd; then
      USB_ARGS=(-device qemu-xhci -device usb-tablet -device usb-kbd)
      echo "Entrada USB habilitada: tableta y teclado."
    elif [[ "$USB_INPUT_MODE" == on ]]; then
      echo "QEMU no incluye qemu-xhci, usb-tablet y usb-kbd; usa QEMU_USB_INPUT=auto o off." >&2
      exit 1
    else
      echo "QEMU no ofrece tableta/teclado USB completos; se conserva la entrada estándar PS/2."
    fi
    ;;
  *)
    echo "QEMU_USB_INPUT debe ser auto, on o off (recibido: $USB_INPUT_MODE)." >&2
    exit 2
    ;;
esac

ARGS=(-machine pc -accel "${QEMU_ACCEL:-tcg,thread=multi}" -m "$RAM" -smp "$SMP" -cpu max
      -drive "file=$IMG,format=raw,if=ide,index=0" -netdev user,id=n0 -device e1000,netdev=n0
      -vga std "${DISPLAY_ARGS[@]}" "${USB_ARGS[@]}" -serial stdio -monitor none)
if [[ "${DEBUG:-0}" = 1 ]]; then
  mkdir -p "$ROOT/build"
  ARGS+=(-d int,cpu_reset -D "$ROOT/build/qemu-debug.log" -no-reboot)
fi
exec "$QEMU_BIN" "${ARGS[@]}"
