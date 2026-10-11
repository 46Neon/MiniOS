#!/usr/bin/env bash
# Interactive browser handoff copied into the opt-in profile's private bin dir.
set -Eeuo pipefail
if [[ -z "${TERMUX_VERSION:-}" || -z "${PREFIX:-}" || ! -x "${PREFIX:-/nonexistent}/bin/pkg" ]]; then
  printf 'MiniAriño: este acceso solo funciona dentro de Termux.\n' >&2
  exit 2
fi
command -v termux-open-url >/dev/null 2>&1 || {
  printf 'MiniAriño: termux-open-url no está disponible; abre el navegador Android manualmente.\n' >&2
  exit 2
}
printf 'MiniAriño — navegador Android\nLa página se abrirá fuera de XFCE con el navegador elegido por Android.\nURL (http:// o https://): '
IFS= read -r URL || { printf 'No se recibió una URL.\n' >&2; exit 2; }
[[ "$URL" =~ ^https?://[^[:space:]]+$ ]] || {
  printf 'URL no válida; usa http:// o https:// sin espacios.\n' >&2
  exit 2
}
termux-open-url "$URL"
printf 'URL entregada a Android.\n'
