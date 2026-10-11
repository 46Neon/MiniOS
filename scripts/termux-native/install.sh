#!/usr/bin/env bash
# Explicit, repeatable setup for the Termux:X11 companion package + native XFCE.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/termux-native/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'EOF'
Uso:
  scripts/termux-native/install.sh --check    # solo inspecciona; no instala
  scripts/termux-native/install.sh --install  # solicita confirmación e instala

Requiere que la aplicación Android Termux:X11 ya esté instalada. Este script
no descarga ni instala APKs y no modifica la configuración del escritorio.
EOF
}

MODE="${1:---check}"
case "$MODE" in
  --check|--install) ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 2; }
native_require_termux

missing=()
for item in termux-x11 xfce4-session xfce4-panel dbus-launch thunar xfce4-terminal; do
  command -v "$item" >/dev/null 2>&1 || missing+=("$item")
done
if ((${#missing[@]} == 0)); then
  printf 'Herramientas requeridas encontradas: termux-x11, XFCE, D-Bus, Thunar y terminal.\n'
else
  printf 'Herramientas por instalar o revisar: %s\n' "${missing[*]}"
fi

if [[ "$MODE" == --check ]]; then
  cat <<'EOF'
Modo --check: no se ejecutó pkg ni se cambió ningún archivo.
Para instalar explícitamente el paquete nativo xfce y el compañero Termux:X11:
  scripts/termux-native/install.sh --install
EOF
  exit 0
fi

cat <<'EOF'
Esta acción opt-in añadirá el repositorio oficial x11-repo de Termux (necesario
para Termux:X11) y solicitará a pkg instalar los paquetes seleccionados
termux-x11-nightly y xfce. No se añade TUR ni otro repositorio de terceros.
No se ejecuta pkg upgrade, no se eliminan paquetes, no se instala ningún APK y
no se cambian archivos de configuración personales.
EOF
if ! IFS= read -r -p '¿Continuar? [y/N] ' answer; then
  printf 'Cancelado; no se instaló ningún paquete.\n'
  exit 0
fi
case "$answer" in
  y|Y|yes|YES|s|S|si|SI|sí|Sí) ;;
  *) printf 'Cancelado; no se instaló ningún paquete.\n'; exit 0 ;;
esac

"$PREFIX/bin/pkg" install x11-repo
"$PREFIX/bin/pkg" install termux-x11-nightly xfce

printf '\nInstalación solicitada. Ejecuta doctor.sh para comprobar comandos y abre la aplicación Termux:X11 antes de start.sh.\n'
