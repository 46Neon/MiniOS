#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_QEMU="$ROOT/scripts/run-qemu.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAKE_QEMU="$TMP/fake-qemu"
IMAGE="$TMP/os.img"
ARGS_FILE="$TMP/qemu-args"
OUTPUT="$TMP/output"
: > "$IMAGE"

cat > "$FAKE_QEMU" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${1:-}" == -display && "${2:-}" == help ]]; then
  printf '%s\n' "${FAKE_QEMU_DISPLAYS:-}"
  exit 0
fi
if [[ "${1:-}" == -device && "${2:-}" == help ]]; then
  printf '%s\n' "${FAKE_QEMU_DEVICES:-}"
  exit 0
fi
printf '%s\n' "$@" > "$FAKE_QEMU_ARGS_FILE"
MOCK
chmod 0755 "$FAKE_QEMU"

assert_arg() {
  grep -Fxq -- "$1" "$ARGS_FILE" || { echo "Falta el argumento QEMU: $1" >&2; cat "$ARGS_FILE" >&2; exit 1; }
}
assert_common_contract() {
  assert_arg '-machine'
  assert_arg 'pc'
  assert_arg '-accel'
  assert_arg 'tcg,thread=multi'
  assert_arg "file=$IMAGE,format=raw,if=ide,index=0"
  assert_arg '-device'
  assert_arg 'e1000,netdev=n0'
}
run_case() {
  : > "$ARGS_FILE"
  env "$@" QEMU="$FAKE_QEMU" FAKE_QEMU_ARGS_FILE="$ARGS_FILE" \
    "$RUN_QEMU" "$IMAGE" >"$OUTPUT" 2>&1
}

# Termux:X11 path: use SDL when the backend and display environment exist.
run_case DISPLAY=:0 QEMU_DISPLAY=auto QEMU_USB_INPUT=auto \
  FAKE_QEMU_DISPLAYS=$'sdl\ngtk\nnone' \
  FAKE_QEMU_DEVICES=$'name "qemu-xhci" bus PCI\nname "usb-tablet" bus usb-bus\nname "usb-kbd" bus usb-bus'
assert_common_contract
assert_arg 'sdl,show-cursor=on'
assert_arg 'qemu-xhci'
assert_arg 'usb-tablet'
assert_arg 'usb-kbd'
echo 'PASS: auto elige SDL y entrada USB cuando están disponibles.'

# Termux portrait mode: GTK fullscreen scales the guest and keeps the pointer visible.
run_case DISPLAY=:0 QEMU_DISPLAY=gtk QEMU_FULLSCREEN=on QEMU_USB_INPUT=auto \
  FAKE_QEMU_DISPLAYS=$'gtk\nnone' \
  FAKE_QEMU_DEVICES=$'name "qemu-xhci" bus PCI\nname "usb-tablet" bus usb-bus\nname "usb-kbd" bus usb-bus'
assert_common_contract
assert_arg 'gtk,show-cursor=on,full-screen=on,zoom-to-fit=on'
assert_arg 'usb-tablet'
echo 'PASS: GTK maximizes/scales the guest and enables the absolute tablet.'

run_case DISPLAY=:0 QEMU_DISPLAY=sdl QEMU_FULLSCREEN=on QEMU_USB_INPUT=off \
  FAKE_QEMU_DISPLAYS=$'sdl\nnone' FAKE_QEMU_DEVICES=''
assert_common_contract
assert_arg 'sdl,show-cursor=on'
assert_arg '-full-screen'
echo 'PASS: SDL starts fullscreen with the mouse cursor visible.'

# If SDL is absent, auto may use GTK when an X11/Wayland display exists.
run_case DISPLAY=:0 QEMU_DISPLAY=auto QEMU_USB_INPUT=auto \
  FAKE_QEMU_DISPLAYS=$'gtk\nnone' FAKE_QEMU_DEVICES=''
assert_common_contract
assert_arg 'gtk,show-cursor=on'
if grep -Fxq 'qemu-xhci' "$ARGS_FILE"; then echo 'No debía agregar USB si faltan dispositivos.' >&2; exit 1; fi
echo 'PASS: auto usa GTK y cae a PS/2 si no están los USB.'

# Headless Termux path: use loopback-only VNC when no X11/Wayland display exists.
env -u DISPLAY -u WAYLAND_DISPLAY QEMU="$FAKE_QEMU" QEMU_DISPLAY=auto \
  QEMU_USB_INPUT=auto \
  FAKE_QEMU_DISPLAYS=$'sdl\ngtk\nnone' \
  FAKE_QEMU_DEVICES=$'name "qemu-xhci" bus PCI\nname "usb-tablet" bus usb-bus\nname "usb-kbd" bus usb-bus' \
  FAKE_QEMU_ARGS_FILE="$ARGS_FILE" "$RUN_QEMU" "$IMAGE" >"$OUTPUT" 2>&1
assert_common_contract
assert_arg 'none'
assert_arg '-vnc'
assert_arg '127.0.0.1:1'
echo 'PASS: auto usa VNC local si no hay display gráfico.'

# Explicit GTK remains available; users can disable the optional USB devices.
run_case DISPLAY=:0 QEMU_DISPLAY=gtk QEMU_USB_INPUT=off \
  FAKE_QEMU_DISPLAYS=$'gtk\nnone' FAKE_QEMU_DEVICES=''
assert_common_contract
assert_arg 'gtk,show-cursor=on'
if grep -Fxq 'qemu-xhci' "$ARGS_FILE"; then echo 'USB debía estar desactivado.' >&2; exit 1; fi
echo 'PASS: respeta backend GTK y QEMU_USB_INPUT=off.'

# A requested backend that QEMU lacks fails before launch with an explanation.
: > "$ARGS_FILE"
if env DISPLAY=:0 QEMU="$FAKE_QEMU" QEMU_DISPLAY=gtk QEMU_USB_INPUT=off \
  FAKE_QEMU_DISPLAYS=$'sdl\nnone' FAKE_QEMU_DEVICES='' FAKE_QEMU_ARGS_FILE="$ARGS_FILE" \
  "$RUN_QEMU" "$IMAGE" >"$OUTPUT" 2>&1; then
  echo 'Se esperaba fallo por backend GTK no disponible.' >&2
  exit 1
fi
grep -q "no ofrece el backend gráfico 'gtk'" "$OUTPUT"
[[ ! -s "$ARGS_FILE" ]] || { echo 'QEMU no debía arrancarse.' >&2; exit 1; }
echo 'PASS: informa si el backend pedido no existe.'

# Forced USB mode fails clearly when the QEMU build lacks the devices.
: > "$ARGS_FILE"
if env DISPLAY=:0 QEMU="$FAKE_QEMU" QEMU_DISPLAY=sdl QEMU_USB_INPUT=on \
  FAKE_QEMU_DISPLAYS=$'sdl\nnone' FAKE_QEMU_DEVICES='' FAKE_QEMU_ARGS_FILE="$ARGS_FILE" \
  "$RUN_QEMU" "$IMAGE" >"$OUTPUT" 2>&1; then
  echo 'Se esperaba fallo por periféricos USB no disponibles.' >&2
  exit 1
fi
grep -q 'QEMU no incluye qemu-xhci' "$OUTPUT"
[[ ! -s "$ARGS_FILE" ]] || { echo 'QEMU no debía arrancarse.' >&2; exit 1; }
echo 'PASS: QEMU_USB_INPUT=on falla con una explicación útil.'

echo 'Todas las pruebas del lanzador QEMU pasaron.'
