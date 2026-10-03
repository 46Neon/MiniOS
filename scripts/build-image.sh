#!/usr/bin/env bash
# LEGACY Debian/QEMU path; not used by the native Termux desktop.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_ARG="${1:-build/os.img}"
OUT="$OUT_ARG"
[[ "$OUT" = /* ]] || OUT="$ROOT/$OUT"
OUT_DIR="$(dirname "$OUT")"
TMP="$OUT.new"
WORK="$ROOT/build/work"
MNT="$WORK/root"
SUITE="${DEBIAN_SUITE:-trixie}"
IMAGE_GIB="${MINIARINO_IMAGE_GIB:-16}"
if [[ ! "$IMAGE_GIB" =~ ^[1-9][0-9]*$ ]] || (( IMAGE_GIB > 2048 )); then
  echo "MINIARINO_IMAGE_GIB debe ser un entero entre 1 y 2048 (límite MBR)." >&2
  exit 2
fi
IMAGE_SIZE="${IMAGE_GIB}G"
IMAGE_SECTORS=$((IMAGE_GIB * 2097152))
PARTITION_SECTORS=$((IMAGE_SECTORS - 2048))
DEFAULT_PASSWORD="${MINIARINO_PASSWORD:-miniarino}"
DEBIAN_KEYRING="${DEBIAN_KEYRING:-/usr/share/keyrings/debian-archive-keyring.gpg}"
LOOP=""

if (( EUID != 0 )); then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo -E env DEBIAN_SUITE="$SUITE" DEBIAN_KEYRING="$DEBIAN_KEYRING" MINIARINO_PASSWORD="$DEFAULT_PASSWORD" "$0" "$OUT"
  fi
  echo "La creación de la imagen necesita root y los dispositivos loop." >&2
  exit 1
fi

for cmd in debootstrap sfdisk losetup mkfs.ext4 mount umount chroot blkid sha256sum; do
  command -v "$cmd" >/dev/null || { echo "Falta la herramienta del constructor: $cmd" >&2; exit 1; }
done
[[ -r "$DEBIAN_KEYRING" ]] || { echo "Falta el keyring Debian verificado del host: $DEBIAN_KEYRING" >&2; exit 1; }
[[ "$(dpkg --print-architecture)" = amd64 ]] || { echo "Construye en un host Linux amd64; Termux/ARM no sirve para debootstrap amd64 nativo." >&2; exit 1; }
[[ -n "$DEFAULT_PASSWORD" ]] || { echo "MINIARINO_PASSWORD no puede estar vacía." >&2; exit 1; }

mkdir -p "$OUT_DIR" "$ROOT/build" "$ROOT/reference/images"
rm -rf -- "$WORK"
mkdir -p "$MNT"
rm -f -- "$TMP"

cleanup() {
  set +e
  for mountpoint in "$MNT/run" "$MNT/dev/pts" "$MNT/dev" "$MNT/proc" "$MNT/sys" "$MNT"; do
    mountpoint -q "$mountpoint" && umount -lf "$mountpoint"
  done
  [[ -n "$LOOP" ]] && losetup -d "$LOOP"
  rm -rf -- "$WORK"
  if [[ -f "$TMP" ]]; then rm -f -- "$TMP"; fi
}
trap cleanup EXIT

# Create a fresh sparse raw image; all partitioning is confined to this new file.
truncate -s "$IMAGE_SIZE" "$TMP"
cat <<SFDISK | sfdisk --wipe always "$TMP"
label: dos
unit: sectors
sector-size: 512
start=2048, size=${PARTITION_SECTORS}, type=83, bootable
SFDISK

LOOP="$(losetup --find --show --partscan "$TMP")"
PART="${LOOP}p1"
for _ in $(seq 1 30); do [[ -b "$PART" ]] && break; sleep 1; done
[[ -b "$PART" ]] || { echo "No apareció la partición $PART" >&2; exit 1; }
mkfs.ext4 -F -L MINIARINO_ROOT "$PART"
mount "$PART" "$MNT"

DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
debootstrap --keyring="$DEBIAN_KEYRING" --include=ca-certificates --arch=amd64 --variant=minbase "$SUITE" "$MNT" "$DEBIAN_MIRROR"
rm -f "$MNT/etc/apt/sources.list"

cat > "$MNT/etc/apt/sources.list.d/debian.sources" <<EOF
Types: deb
URIs: https://deb.debian.org/debian
Suites: $SUITE $SUITE-updates
Components: main contrib non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://security.debian.org/debian-security
Suites: $SUITE-security
Components: main contrib non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

cp /etc/resolv.conf "$MNT/etc/resolv.conf" 2>/dev/null || true
for path in dev dev/pts proc sys run; do mkdir -p "$MNT/$path"; done
mount --rbind /dev "$MNT/dev"
mount --make-rslave "$MNT/dev"
mount -t proc proc "$MNT/proc"
mount -t sysfs sysfs "$MNT/sys"
mount --bind /run "$MNT/run"

mapfile -t PACKAGES < <(grep -hEv '^[[:space:]]*(#|$)' "$ROOT"/packages/*.txt | sort -u)
DEBIAN_FRONTEND=noninteractive chroot "$MNT" apt-get update
DEBIAN_FRONTEND=noninteractive chroot "$MNT" apt-get install -y --no-install-recommends "${PACKAGES[@]}"

printf 'miniarino\n' > "$MNT/etc/hostname"
cat > "$MNT/etc/hosts" <<'EOF'
127.0.0.1 localhost
127.0.1.1 miniarino
::1 localhost ip6-localhost ip6-loopback
EOF
ROOT_UUID="$(blkid -s UUID -o value "$PART")"
printf 'UUID=%s / ext4 defaults,noatime,errors=remount-ro 0 1\n' "$ROOT_UUID" > "$MNT/etc/fstab"
printf 'America/Caracas\n' > "$MNT/etc/timezone"
ln -sf /usr/share/zoneinfo/America/Caracas "$MNT/etc/localtime"

chroot "$MNT" useradd --create-home --shell /bin/bash --groups sudo,audio,video,plugdev miniarino
printf 'miniarino:%s\n' "$DEFAULT_PASSWORD" | chroot "$MNT" chpasswd
printf 'es_VE.UTF-8 UTF-8\nen_US.UTF-8 UTF-8\n' > "$MNT/etc/locale.gen"
chroot "$MNT" locale-gen
printf 'LANG=es_VE.UTF-8\n' > "$MNT/etc/default/locale"

mkdir -p "$MNT/etc/lightdm/lightdm.conf.d"
install -m 0644 "$ROOT/config/lightdm/50-miniarino.conf" "$MNT/etc/lightdm/lightdm.conf.d/50-miniarino.conf"
mkdir -p "$MNT/etc/systemd/system/multi-user.target.wants"
ln -sf /lib/systemd/system/NetworkManager.service "$MNT/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
install -m 0644 "$ROOT/config/systemd/miniarino-welcome.service" "$MNT/etc/systemd/system/miniarino-welcome.service"
ln -sf ../miniarino-welcome.service "$MNT/etc/systemd/system/multi-user.target.wants/miniarino-welcome.service"
chroot "$MNT" systemctl enable lightdm NetworkManager systemd-timesyncd

install -d -m 0755 "$MNT/usr/share/backgrounds" "$MNT/usr/local/bin" "$MNT/etc/xdg/autostart" "$MNT/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml"
install -m 0644 "$ROOT/config/xfce/miniarino-wallpaper.svg" "$MNT/usr/share/backgrounds/miniarino-wallpaper.svg"
install -m 0644 "$ROOT/config/xfce/xfce4-desktop.xml" "$MNT/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
install -m 0644 "$ROOT/config/xfce/xfce4-keyboard-shortcuts.xml" "$MNT/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"
install -d -m 0755 "$MNT/home/miniarino/.config/xfce4/xfconf/xfce-perchannel-xml"
install -m 0644 "$ROOT/config/xfce/xfce4-desktop.xml" "$MNT/home/miniarino/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
install -m 0644 "$ROOT/config/xfce/xfce4-keyboard-shortcuts.xml" "$MNT/home/miniarino/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"
install -m 0755 "$ROOT/config/xfce/set-display-mode.sh" "$MNT/usr/local/bin/miniarino-set-display-mode"
install -m 0755 "$ROOT/scripts/miniarino-selftest.sh" "$MNT/usr/local/bin/miniarino-selftest"
install -m 0644 "$ROOT/config/xfce/miniarino-resolution.desktop" "$MNT/etc/xdg/autostart/miniarino-resolution.desktop"
install -d -m 0755 "$MNT/home/miniarino/Desktop" "$MNT/home/miniarino/Downloads" "$MNT/home/miniarino/Documents" "$MNT/home/miniarino/Pictures"
for launcher in "$ROOT"/config/xfce/desktop/*.desktop; do
  install -m 0755 "$launcher" "$MNT/home/miniarino/Desktop/$(basename "$launcher")"
done
chroot "$MNT" chown -R miniarino:miniarino /home/miniarino

# One custom GRUB menu entry for Linux plus reboot and power-off; no recovery submenu.
for script in 10_linux 20_linux_xen 30_os-prober 30_uefi-firmware; do
  [[ ! -e "$MNT/etc/grub.d/$script" ]] || chmod -x "$MNT/etc/grub.d/$script"
done
sed "s/@ROOT_UUID@/$ROOT_UUID/g" "$ROOT/config/grub/default" > "$MNT/etc/default/grub"

# Use Debian's own GRUB modules and write only to this image's loop device.
sed "s/@ROOT_UUID@/$ROOT_UUID/g" "$ROOT/config/grub/10_miniarino" > "$MNT/etc/grub.d/10_miniarino"
chmod 0755 "$MNT/etc/grub.d/10_miniarino"
chroot "$MNT" grub-install --target=i386-pc --recheck "$LOOP"
chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg

# Assert the expected kernel and initramfs exist before committing the new image.
compgen -G "$MNT/boot/vmlinuz-*" >/dev/null || { echo "No se instaló kernel Linux." >&2; exit 1; }
compgen -G "$MNT/boot/initrd.img-*" >/dev/null || { echo "No se creó initramfs." >&2; exit 1; }
chroot "$MNT" update-initramfs -u -k all

sync
umount -lf "$MNT/run" "$MNT/dev/pts" "$MNT/dev" "$MNT/proc" "$MNT/sys" "$MNT"
losetup -d "$LOOP"
LOOP=""

"$ROOT/scripts/verify-image.sh" "$TMP"

# Preserve any previous image byte-for-byte before atomically replacing it.
if [[ -f "$OUT" ]]; then
  OLD_HASH="$(sha256sum "$OUT" | awk '{print $1}')"
  ARCHIVE="$ROOT/reference/images/os.img-$OLD_HASH"
  if [[ ! -e "$ARCHIVE" ]]; then mv -- "$OUT" "$ARCHIVE"; fi
  chmod 0644 "$ARCHIVE"
fi
mv -- "$TMP" "$OUT"
# The build may have escalated through sudo; QEMU and artifact upload run as the invoking user.
chmod 0755 "$OUT_DIR"
chmod 0644 "$OUT"
sha256sum "$OUT"
printf 'Imagen construida: %s\n' "$OUT"
