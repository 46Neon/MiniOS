#!/usr/bin/env bash
# Launch native Termux Chromium in an X11 session when present; otherwise hand off to Android.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/termux-native/common.sh
source "$SCRIPT_DIR/common.sh"
if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  printf 'Uso: scripts/termux-native/browser.sh https://sitio.example\nCon DISPLAY activo, abre Chromium nativo de Termux (chromium-browser) dentro de XFCE. Si no está instalado o no hay DISPLAY, entrega la URL a Android mediante termux-open-url.\n'
  exit 0
fi
[[ $# -eq 1 ]] || native_die 'indica una URL http:// o https://.'
URL="$1"
[[ "$URL" =~ ^https?://[^[:space:]]+$ ]] || native_die 'solo se aceptan URLs http:// o https:// sin espacios.'
native_require_termux
if [[ -n "${DISPLAY:-}" ]] && command -v chromium-browser >/dev/null 2>&1; then
  # Detach the GUI browser from a temporary XFCE terminal launcher.
  nohup chromium-browser "$URL" >/dev/null 2>&1 </dev/null &
  printf 'URL abierta en Chromium dentro de XFCE.\n'
elif command -v termux-open-url >/dev/null 2>&1; then
  termux-open-url "$URL"
  printf 'URL entregada al navegador Android; puede abrir fuera de XFCE.\n'
else
  native_die 'no hay Chromium con DISPLAY activo ni termux-open-url; abre un navegador manualmente.'
fi
