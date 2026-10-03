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
  scripts/termux-native/install.sh --install-blender   # instala Blender 5 opcional (TUR, terceros)

Requiere que la aplicación Android Termux:X11 ya esté instalada. Este script
no descarga ni instala APKs y no modifica la configuración del escritorio.
EOF
}

MODE="${1:---check}"
case "$MODE" in
  --check|--install|--install-chromium|--install-blender) ;;
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
Para instalar Blender 5 desde TUR (tercero), de forma opt-in:
  scripts/termux-native/install.sh --install-blender
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

if [[ "$MODE" == --install-blender ]]; then
  [[ "$(uname -m)" == aarch64 ]] || native_die 'la opción blender5 de TUR disponible para este flujo requiere aarch64.'
  [[ -x "$PREFIX/bin/termux-x11" && -x "$PREFIX/bin/xfce4-session" ]] || native_die 'instala primero Termux:X11 y XFCE con install.sh --install.'
  if [[ -x "$PREFIX/bin/blender-5.2" ]]; then
    printf 'Blender ya está disponible: %s\n' "$PREFIX/bin/blender-5.2"
    exit 0
  fi
  cat <<'EOF'
Esta opción experimental habilitará el repositorio de terceros TUR y solicitará instalar blender5 (AArch64, componente tur-on-device).
El paquete y sus dependencias son grandes; no se garantiza aceleración GPU ni compatibilidad hasta probarlo en este teléfono.
TUR no es un repositorio oficial de Termux. No se añade al flujo normal; solo se activa tras esta confirmación.
No se ejecuta pkg upgrade ni se eliminan paquetes. Si pkg reporta incompatibilidades, detente; TUR puede quedar habilitado y deberás revisarlo aparte.
EOF
  if ! IFS= read -r -p '¿Habilitar TUR e instalar Blender 5? [y/N] ' answer; then
    printf 'Cancelado; no se habilitó TUR ni se instaló Blender.\n'
    exit 0
  fi
  case "$answer" in
    y|Y|yes|YES|s|S|si|SI|sí|Sí) ;;
    *) printf 'Cancelado; no se habilitó TUR ni se instaló Blender.\n'; exit 0 ;;
  esac
  "$PREFIX/bin/pkg" install tur-repo
  "$PREFIX/bin/pkg" install blender5
  printf 'Instalación de Blender solicitada. Comprueba doctor.sh y el menú Gráficos de XFCE; el binario del paquete actual es blender-5.2.\n'
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
