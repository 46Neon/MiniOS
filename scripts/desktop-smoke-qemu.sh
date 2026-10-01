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
SELFTEST_PPM="$WORK/selftest.ppm"
SELFTEST_PNG="$WORK/selftest.png"
SELFTEST_LOG="$WORK/selftest.log"
SELFTEST_EXIT="$WORK/selftest.exitcode"
MOUNT="$WORK/rootfs"
LOOP=""
rm -f "$SERIAL" "$QEMU_LOG" "$MONITOR" "$PPM" "$PNG" "$SELFTEST_PPM" "$SELFTEST_PNG" "$SELFTEST_LOG" "$SELFTEST_EXIT"
mkdir -p "$MOUNT"

qemu-system-x86_64 \
  -machine pc -accel tcg,thread=multi -m 2048 -smp 2 -cpu max \
  -drive "file=$IMG,format=raw,if=ide" \
  -netdev user,id=net0 -device e1000,netdev=net0 \
  -vga std -display vnc=127.0.0.1:3 \
  -serial "file:$SERIAL" \
  -monitor "unix:$MONITOR,server=on,wait=off" \
  -no-reboot -no-shutdown >"$QEMU_LOG" 2>&1 &
PID=$!
stop_qemu() {
  set +e
  kill "$PID" 2>/dev/null
  wait "$PID" 2>/dev/null
  set -e
}
cleanup() {
  set +e
  mountpoint -q "$MOUNT" && sudo -n umount "$MOUNT"
  [[ -n "$LOOP" ]] && sudo -n losetup -d "$LOOP"
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

# Open XFCE's standard application finder and type the diagnostic command.
# The configured Ctrl+Alt+M binding remains available for interactive use, but
# this smoke test avoids depending on an unverified keybinding in headless QEMU.
# It still runs with the live user's X11, D-Bus and XFCE session, not in a chroot.
python3 - "$MONITOR" "$SELFTEST_PPM" <<'PY'
import socket, sys, time
sock_path, screenshot = sys.argv[1:]
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.settimeout(5); s.connect(sock_path)
def prompt(timeout=10):
    data=bytearray(); deadline=time.time()+timeout
    while time.time()<deadline:
        try: part=s.recv(4096)
        except socket.timeout: continue
        if not part: break
        data.extend(part)
        if b'(qemu)' in data: return bytes(data)
    raise RuntimeError('QEMU monitor prompt timeout: '+data.decode(errors='replace'))
def command(text, timeout=10):
    s.sendall((text+'\n').encode()); return prompt(timeout)
prompt()
command('sendkey alt-f2')
time.sleep(2)
# XFCE appfinder accepts this command as ordinary text. Type it using QEMU's
# key names for lowercase letters, digits, spaces and minus signs.
for char in 'xfce4-terminal --hold -x miniarino-selftest':
    key = 'spc' if char == ' ' else 'minus' if char == '-' else char
    if not (key in ('spc', 'minus') or key.isalnum()):
        raise RuntimeError(f'No QEMU key mapping for {char!r}')
    command(f'sendkey {key}', timeout=3)
command('sendkey ret')
# The diagnostic checks versions, services, X11/D-Bus and Xfconf, then saves a
# full report under the miniarino user's cache directory. --hold keeps its
# terminal visible for the diagnostic screenshot.
time.sleep(25)
result=command(f'screendump {screenshot}')
if b'Error' in result or b'failed' in result.lower(): raise RuntimeError(result.decode(errors='replace'))
command('system_powerdown')
end=time.time()+60
while time.time()<end:
    state=command('info status').lower()
    if b'shutdown' in state: break
    time.sleep(1)
else:
    raise RuntimeError('El sistema no se apagó limpiamente tras la prueba del escritorio')
s.close()
PY

python3 - "$SELFTEST_PPM" "$SELFTEST_PNG" <<'PY'
from PIL import Image
import sys
im=Image.open(sys.argv[1]).convert('RGB')
if im.width < 320 or im.height < 200: raise SystemExit(f'Captura del diagnóstico inválida: {im.size}')
im.save(sys.argv[2])
print(f'Captura durante el autodiagnóstico: {sys.argv[2]} ({im.width}x{im.height})')
PY

# QEMU has received the guest's clean ACPI shutdown; stop its paused process and
# read the report from the image for an actual pass/fail gate.
stop_qemu
LOOP="$(sudo -n losetup --find --show --partscan --read-only "$IMG")"
PART="${LOOP}p1"
for _ in $(seq 1 30); do [[ -b "$PART" ]] && break; sleep 1; done
[[ -b "$PART" ]] || { echo "No se pudo abrir la partición para leer el autodiagnóstico: $PART" >&2; exit 1; }
sudo -n mount -o ro,noload "$PART" "$MOUNT"
sudo -n cat "$MOUNT/home/miniarino/.cache/miniarino-selftest/last.log" > "$SELFTEST_LOG"
sudo -n cat "$MOUNT/home/miniarino/.cache/miniarino-selftest/last.exitcode" > "$SELFTEST_EXIT"
sudo -n umount "$MOUNT"
sudo -n losetup -d "$LOOP"
LOOP=""
cat "$SELFTEST_LOG"
if [[ "$(tr -d '[:space:]' < "$SELFTEST_EXIT")" != 0 ]] \
   || ! grep -Eq 'Resumen: [0-9]+ PASS, 0 FAIL, [0-9]+ WARN' "$SELFTEST_LOG"; then
  echo "El autodiagnóstico dentro de MiniAriño no pasó; revisa $SELFTEST_LOG." >&2
  exit 1
fi
printf 'OK: autodiagnóstico XFCE ejecutado dentro de la sesión gráfica.\n'
