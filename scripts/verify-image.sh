#!/usr/bin/env bash
# LEGACY Debian/QEMU path; not used by the native Termux desktop.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="${1:-$ROOT/build/os.img}"
[[ "$IMG" = /* ]] || IMG="$ROOT/$IMG"
[[ -f "$IMG" ]] || { echo "No existe la imagen: $IMG" >&2; exit 1; }
IMAGE_GIB="${MINIARINO_IMAGE_GIB:-16}"
if [[ ! "$IMAGE_GIB" =~ ^[1-9][0-9]*$ ]] || (( IMAGE_GIB > 2048 )); then
  echo "MINIARINO_IMAGE_GIB debe ser un entero entre 1 y 2048 (límite MBR)." >&2
  exit 2
fi

python3 - "$IMG" "$IMAGE_GIB" <<'PY'
import json, subprocess, sys
p=sys.argv[1]
image_gib=int(sys.argv[2])
size=int(subprocess.check_output(['stat','-c','%s',p],text=True).strip())
expected=image_gib*1024**3
if size != expected:
    raise SystemExit(f'Tamaño incorrecto: {size}; esperado {expected} bytes ({image_gib} GiB)')
part=subprocess.check_output(['sfdisk','--json',p],text=True)
d=json.loads(part)['partitiontable']
if d.get('label') != 'dos':
    raise SystemExit(f'La tabla debe ser MBR/dos, no {d.get("label")}')
parts=d.get('partitions',[])
if len(parts) != 1:
    raise SystemExit(f'Se esperaba una partición raíz; encontradas {len(parts)}')
x=parts[0]
expected_partition_sectors=image_gib*2097152-2048
if int(x.get('start',0)) != 2048 or int(x.get('size',0)) != expected_partition_sectors:
    raise SystemExit(f'Geometría de partición inesperada: {x}; sectores esperados {expected_partition_sectors}')
if x.get('type') != '83':
    raise SystemExit(f'Tipo de partición no Linux: {x.get("type")}')
print(f'OK: raw {image_gib} GiB, MBR, partición Linux desde 1 MiB hasta el final de la imagen.')
PY

SIG="$(dd if="$IMG" bs=1 skip=510 count=2 status=none | od -An -tx1 | tr -d ' \n')"
[[ "$SIG" = 55aa ]] || { echo "Firma MBR incorrecta: $SIG (se esperaba 55aa)." >&2; exit 1; }

if (( EUID != 0 )); then
  if command -v sudo >/dev/null 2>&1; then exec sudo -E "$0" "$IMG"; fi
  echo "La verificación del contenido de la partición necesita root/loop." >&2
  exit 1
fi
WORK="$ROOT/build/verify-mount"
mkdir -p "$WORK"
LOOP=""
cleanup() { set +e; mountpoint -q "$WORK" && umount "$WORK"; [[ -n "$LOOP" ]] && losetup -d "$LOOP"; rmdir "$WORK" 2>/dev/null; }
trap cleanup EXIT
LOOP="$(losetup --find --show --partscan --read-only "$IMG")"
PART="${LOOP}p1"
for _ in $(seq 1 30); do [[ -b "$PART" ]] && break; sleep 1; done
[[ -b "$PART" ]] || { echo "No se pudo localizar la partición raíz $PART." >&2; exit 1; }
mount -o ro,noload "$PART" "$WORK"
[[ -s "$WORK/boot/grub/i386-pc/normal.mod" && -s "$WORK/boot/grub/i386-pc/biosdisk.mod" ]] || { echo "Faltan módulos de GRUB BIOS." >&2; exit 1; }
compgen -G "$WORK/boot/vmlinuz-*" >/dev/null || { echo "Falta el kernel Linux." >&2; exit 1; }
compgen -G "$WORK/boot/initrd.img-*" >/dev/null || { echo "Falta initramfs." >&2; exit 1; }
[[ -x "$WORK/usr/sbin/fsck.ext4" || -x "$WORK/sbin/fsck.ext4" ]] || { echo "Falta fsck.ext4; instala e2fsprogs para el chequeo del root en initramfs." >&2; exit 1; }
[[ -x "$WORK/usr/bin/startxfce4" ]] || { echo "Falta el arranque de XFCE." >&2; exit 1; }
[[ -x "$WORK/usr/bin/firefox-esr" ]] || { echo "Falta Firefox ESR." >&2; exit 1; }
[[ -f "$WORK/boot/grub/grub.cfg" ]] || { echo "Falta grub.cfg." >&2; exit 1; }
COUNT="$(grep -c '^menuentry ' "$WORK/boot/grub/grub.cfg" || true)"
[[ "$COUNT" = 3 ]] || { echo "GRUB debe tener 3 entradas; tiene $COUNT." >&2; exit 1; }
grep -q 'MiniAriño bienvenido' "$WORK/etc/systemd/system/miniarino-welcome.service" || { echo "Falta el saludo de arranque." >&2; exit 1; }
python3 "$ROOT/scripts/verify-xfce-image.py" "$WORK"
printf 'OK: firma MBR, GRUB BIOS, kernel, initramfs, XFCE, Firefox ESR, saludo y configuración de escritorio.\n'
