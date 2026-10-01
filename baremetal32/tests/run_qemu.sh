#!/bin/sh
set -eu
IMAGE=${1:-build/os.img}
QEMU=${QEMU:-qemu-system-i386}
LOG=build/qemu-serial.log
mkdir -p build
rm -f "$LOG"
command -v "$QEMU" >/dev/null 2>&1 || { echo "missing QEMU executable: $QEMU" >&2; exit 2; }
# timeout's 124 is expected: the smoke kernel halts forever after its markers.
set +e
timeout 12s "$QEMU" \
    -machine pc -cpu qemu32 -m 128M -boot c \
    -drive "file=$IMAGE,format=raw,if=ide,index=0" \
    -vga std -display none -serial "file:$LOG" \
    -monitor none -no-reboot -no-shutdown
rc=$?
set -e
if [ "$rc" -ne 124 ] && [ "$rc" -ne 137 ]; then
    echo "QEMU exited unexpectedly (status $rc)" >&2
    cat "$LOG" 2>/dev/null || true
    exit 1
fi
cat "$LOG"
grep -q 'BAREMETAL32:KERNEL' "$LOG" || { echo 'kernel marker missing' >&2; exit 1; }
grep -Eq 'E820:count=[1-9][0-9]* entry_size=24 addr=0x5000' "$LOG" || { echo 'E820 marker/count missing' >&2; exit 1; }
grep -q 'VBE:640x480x24' "$LOG" || { echo 'normal SeaBIOS run did not enable 640x480x24 LFB' >&2; exit 1; }
grep -q 'GATE:BOOTINFO_OK' "$LOG" || { echo 'boot-info validation marker missing' >&2; exit 1; }
echo 'QEMU BIOS/IDE boot smoke test passed (kernel, E820, VBE, boot-info).'
