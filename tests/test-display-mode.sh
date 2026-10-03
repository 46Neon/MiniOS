#!/usr/bin/env bash
# LEGACY Debian/QEMU path; not used by the native Termux desktop.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"
mkdir -p "$BIN"
cat > "$BIN/xrandr" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${1:-}" == --query ]]; then
  printf '%s\n' "${FAKE_XRANDR_MODES:-}"
else
  printf '%s\n' "$*" >> "$FAKE_XRANDR_ARGS"
fi
MOCK
chmod +x "$BIN/xrandr"

FAKE_XRANDR_ARGS="$TMP/args" FAKE_XRANDR_MODES=$'Screen 0: current 640 x 480\n  1280x720 60.00\n  640x480 60.00' \
  PATH="$BIN:$PATH" "$ROOT/config/xfce/set-display-mode.sh"
grep -Fxq -- '-s 1280x720' "$TMP/args" || { echo 'No eligió el modo panorámico disponible.' >&2; exit 1; }

: > "$TMP/args"
FAKE_XRANDR_ARGS="$TMP/args" FAKE_XRANDR_MODES=$'Screen 0: current 640 x 480\n  640x480 60.00' \
  PATH="$BIN:$PATH" "$ROOT/config/xfce/set-display-mode.sh"
grep -Fxq -- '-s 640x480' "$TMP/args" || { echo 'No cayó al modo compatible.' >&2; exit 1; }

echo 'PASS: selecciona resolución panorámica cuando existe y conserva fallback.'
