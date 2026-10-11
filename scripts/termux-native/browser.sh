#!/usr/bin/env bash
# Hand an HTTP(S) URL to Android's selected browser; no X11 browser is bundled.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/termux-native/common.sh
source "$SCRIPT_DIR/common.sh"
if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  printf 'Uso: scripts/termux-native/browser.sh https://sitio.example\nEntrega una URL al navegador Android mediante termux-open-url; puede abrir fuera de XFCE. No instala ni configura navegadores.\n'
  exit 0
fi
[[ $# -eq 1 ]] || native_die 'indica una URL http:// o https://.'
URL="$1"
[[ "$URL" =~ ^https?://[^[:space:]]+$ ]] || native_die 'solo se aceptan URLs http:// o https:// sin espacios.'
native_require_termux
command -v termux-open-url >/dev/null 2>&1 || native_die 'termux-open-url no está disponible; abre el navegador Android manualmente. No se instaló ningún navegador.'
termux-open-url "$URL"
printf 'URL entregada al navegador Android; puede abrir fuera de XFCE. No hay un navegador X11 de Termux verificado por este proyecto.\n'
