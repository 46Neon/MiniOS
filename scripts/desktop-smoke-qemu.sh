#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="${1:-$ROOT/build/os.img}"
[[ "$IMG" = /* ]] || IMG="$ROOT/$IMG"
[[ -r "$IMG" && -w "$IMG" ]] || { echo "La imagen debe ser legible y escribible por el usuario de QEMU: $IMG" >&2; exit 1; }

WORK="$ROOT/build/desktop-smoke"
mkdir -p "$WORK"
SERIAL="$WORK/serial.log"
QEMU_LOG="$WORK/qemu.log"
MONITOR="$WORK/monitor.sock"
PPM="$WORK/desktop.ppm"
PNG="$WORK/desktop.png"
rm -f "$SERIAL" "$QEMU_LOG" "$MONITOR" "$PPM" "$PNG"

qemu-system-x86_64 \
  -machine pc -accel tcg,thread=multi -m 2048 -smp 2 -cpu max \
  -drive "file=$IMG,format=raw,if=ide" \
  -netdev user,id=net0 -device e1000,netdev=net0 \
  -vga std -display vnc=127.0.0.1:3 \
  -serial "file:$SERIAL" \
  -monitor "unix:$MONITOR,server=on,wait=off" \
  -no-reboot -no-shutdown >"$QEMU_LOG" 2>&1 &
PID=$!
cleanup() {
  set +e
  kill "$PID" 2>/dev/null
  wait "$PID" 2>/dev/null
}
trap cleanup EXIT

# Wait for Linux to finish booting and emit the configured serial greeting.
for _ in $(seq 1 240); do
  if grep -q 'MiniAriño bienvenido' "$SERIAL" 2>/dev/null; then break; fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "QEMU se cerró antes del saludo. Consola:" >&2
    cat "$SERIAL" "$QEMU_LOG" 2>/dev/null || true
    exit 1
  fi
  sleep 1
done
if ! grep -q 'MiniAriño bienvenido' "$SERIAL"; then
  echo "Linux no emitió el saludo dentro del límite. Consola:" >&2
  cat "$SERIAL" "$QEMU_LOG" 2>/dev/null || true
  exit 1
fi

# Give systemd, LightDM, the XFCE session, and its first-login setup time to settle.
sleep 90

python3 - "$MONITOR" "$PPM" <<'PY'
import socket, sys, time
sock_path, screenshot = sys.argv[1:]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(5)
s.connect(sock_path)
time.sleep(0.5)
try:
    while True:
        data = s.recv(4096)
        if not data or b'(qemu)' in data:
            break
except socket.timeout:
    pass
s.sendall(f'screendump {screenshot}\n'.encode())
response = bytearray()
end = time.time() + 10
while time.time() < end:
    try:
        data = s.recv(4096)
    except socket.timeout:
        break
    if not data:
        break
    response.extend(data)
    if b'(qemu)' in response:
        break
s.close()
if b'Error' in response or b'failed' in response.lower():
    raise SystemExit(response.decode(errors='replace'))
print(response.decode(errors='replace').strip())
PY

python3 - "$PPM" "$PNG" "$SERIAL" <<'PY'
from PIL import Image
import sys
ppm, png, serial = sys.argv[1:]
im = Image.open(ppm).convert('RGB')
if im.width < 320 or im.height < 200:
    raise SystemExit(f'Resolución de captura inesperada: {im.size}')
im.save(png)
colors = im.getcolors(maxcolors=1_000_000)
unique = len(colors) if colors is not None else 1_000_001
print(f'Captura: {png}; resolución {im.width}x{im.height}; colores distintos {unique}.')
text = open(serial, encoding='utf-8', errors='replace').read()
for needle in ('lightdm.service', 'xfce'):
    print(f'Consola contiene {needle!r}: {needle.lower() in text.lower()}')
if unique < 8:
    raise SystemExit('La captura está vacía o casi sin contenido gráfico.')
PY
