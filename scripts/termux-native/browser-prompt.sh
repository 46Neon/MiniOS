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
printf 'MiniAriño — navegador web\nSi Chromium está instalado, la página se abrirá dentro de XFCE; si no, se entregará al navegador Android.\nURL (http:// o https://): '
IFS= read -r URL || { printf 'No se recibió una URL.\n' >&2; exit 2; }
[[ "$URL" =~ ^https?://[^[:space:]]+$ ]] || {
  printf 'URL no válida; usa http:// o https:// sin espacios.\n' >&2
  exit 2
}
if [[ -n "${DISPLAY:-}" ]] && command -v chromium-browser >/dev/null 2>&1; then
  nohup chromium-browser "$URL" >/dev/null 2>&1 </dev/null &
  printf 'URL abierta en Chromium dentro de XFCE.\n'
elif command -v termux-open-url >/dev/null 2>&1; then
  termux-open-url "$URL"
  printf 'URL entregada a Android.\n'
else
  printf 'No hay Chromium con DISPLAY activo ni termux-open-url disponible.\n' >&2
  exit 2
fi
