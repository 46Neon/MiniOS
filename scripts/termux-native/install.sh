#!/usr/bin/env bash
# Explicit, repeatable setup for the Termux:X11 companion package + native XFCE.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/termux-native/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'EOF'
Uso:
  scripts/termux-native/install.sh --check             # solo inspecciona; no instala
  scripts/termux-native/install.sh --install           # solicita instalar XFCE y Termux:X11
  scripts/termux-native/install.sh --install-chromium  # instala Chromium opcional para XFCE

Requiere que la aplicación Android Termux:X11 ya esté instalada. Este script
no descarga ni instala APKs y no modifica la configuración del escritorio.
EOF
}

MODE="${1:---check}"
case "$MODE" in
  --check|--install|--install-chromium) ;;
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
Para instalar Chromium de forma opcional y separada:
  scripts/termux-native/install.sh --install-chromium
EOF
  exit 0
fi

if [[ "$MODE" == --install-chromium ]]; then
  if [[ -x "$PREFIX/bin/chromium-browser" ]]; then
    printf 'Chromium ya está disponible: %s\n' "$PREFIX/bin/chromium-browser"
    exit 0
  fi
  cat <<'EOF'
Esta acción opt-in instalará Chromium desde el repositorio oficial x11-repo.
Puede descargar muchos paquetes; revisa el resumen que muestre pkg antes de aceptar.
No instala chromium-host-tools ni carbonyl-host-tools, no añade TUR y no ejecuta pkg upgrade.
Si aparecen errores de bibliotecas incompatibles, detente y revisa dpkg --audit; no se repara automáticamente.
EOF
  if ! IFS= read -r -p '¿Instalar Chromium para XFCE? [y/N] ' answer; then
    printf 'Cancelado; no se instaló Chromium.\n'
    exit 0
  fi
  case "$answer" in
    y|Y|yes|YES|s|S|si|SI|sí|Sí) ;;
    *) printf 'Cancelado; no se instaló Chromium.\n'; exit 0 ;;
  esac
  "$PREFIX/bin/pkg" install x11-repo chromium
  printf 'Instalación de Chromium solicitada. En XFCE se abrirá con chromium-browser y DISPLAY activo.\n'
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
