#!/usr/bin/env bash
# Read-only diagnostics. Never invokes pkg, creates files, or changes Xfce settings.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/termux-native/common.sh
source "$SCRIPT_DIR/common.sh"
[[ $# -eq 0 ]] || native_die 'doctor.sh no acepta argumentos.'
native_require_termux

printf 'MiniAriño Termux/XFCE doctor (solo lectura)\n'
printf 'Termux: %s\nArquitectura: %s\nPREFIX: %s\n' "$TERMUX_VERSION" "$(uname -m)" "$PREFIX"
failures=0
for item in termux-x11 xfce4-session xfce4-panel dbus-launch thunar xfce4-terminal; do
  if command -v "$item" >/dev/null 2>&1; then
    printf 'OK      %s -> %s\n' "$item" "$(command -v "$item")"
  else
    printf 'FALTA   %s\n' "$item"
    failures=$((failures + 1))
  fi
done

if command -v chromium-browser >/dev/null 2>&1; then
  printf 'NAVEGADOR XFCE: Chromium Termux disponible en %s (solo inicia dentro de XFCE con DISPLAY activo).\n' "$(command -v chromium-browser)"
elif command -v termux-open-url >/dev/null 2>&1; then
  printf 'NAVEGADOR: Chromium no detectado; MiniAriño entregará URLs al navegador Android (puede abrir fuera de XFCE).\n'
else
  printf 'AVISO   no se detectó Chromium ni termux-open-url; abre un navegador manualmente.\n'
fi

if [[ -x "$PREFIX/bin/blender-5.2" ]]; then
  printf 'BLENDER: disponible en %s; aceleración gráfica y estabilidad aún requieren prueba física.\n' "$PREFIX/bin/blender-5.2"
else
  printf 'BLENDER: no instalado (opcional; requiere autorizar el repositorio externo TUR con install.sh --install-blender).\n'
fi

if [[ -d "$HOME/storage/shared" ]]; then
  printf 'Almacenamiento Android: existe %s (la accesibilidad depende de permisos Android).\n' "$HOME/storage/shared"
else
  printf 'Almacenamiento Android: no enlazado. Si hace falta, ejecuta termux-setup-storage manualmente y acepta el permiso Android.\n'
fi

PROFILE_MARKER="$HOME/.config/miniarino-native/profile.enabled"
if [[ -L "$PROFILE_MARKER" ]]; then
  printf 'FALTA   el marcador del perfil móvil es un enlace simbólico; revísalo manualmente.\n'
  failures=$((failures + 1))
elif [[ -f "$PROFILE_MARKER" ]] && grep -Fxq 'mobile-v1' "$PROFILE_MARKER"; then
  printf 'PERFIL  MiniAriño móvil opt-in activo; configuración aislada en ~/.config/miniarino-native (requiere probarse visualmente).\n'
else
  printf 'PERFIL  inactivo; la configuración XFCE existente no se modifica.\n'
fi

STATE_DIR="$(native_state_dir)"
if [[ -L "$STATE_DIR" ]]; then
  printf 'FALTA   directorio de estado es un enlace simbólico; no se accederá.\n'
  failures=$((failures + 1))
elif native_active_session "$STATE_DIR"; then
  printf 'SESIÓN  activa: PID %s, display según inicio (log %s/session.log).\n' "$NATIVE_PID" "$STATE_DIR"
else
  printf 'SESIÓN  detenida o sin registrar.\n'
fi

printf 'DISPLAY predeterminado: %s (puede cambiarse con MINIOS_X11_DISPLAY).\n' "${MINIOS_X11_DISPLAY:-:1}"
printf 'Termux:X11 requiere también la app Android instalada y abierta; solo se comprueba el comando compañero.\n'
printf 'Termux:X11 es local al dispositivo: MiniAriño no configura VNC/RDP ni expone un escritorio por Internet.\n'
if ((failures)); then
  printf 'Resultado: faltan %s comprobaciones requeridas. Usa install.sh --check; no se instalaron paquetes.\n' "$failures"
  exit 1
fi
printf 'Resultado: comandos requeridos presentes. Aún faltan las pruebas visuales y de interacción en el teléfono.\n'
