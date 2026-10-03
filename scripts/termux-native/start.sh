#!/usr/bin/env bash
# Start one owned Termux:X11 + XFCE session on display :1 by default.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/termux-native/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'EOF'
Uso: scripts/termux-native/start.sh
Opciones de entorno: MINIOS_X11_DISPLAY=:1 (o :2...), MINIOS_X11_DPI=120 (opcional).
Inicia Termux:X11 en el dispositivo local y XFCE nativo de Termux; no usa QEMU,
PRoot ni una distribución Linux. No habilita un servidor remoto.
EOF
}
[[ $# -eq 0 ]] || { usage >&2; exit 2; }
native_require_termux
DISPLAY_ID="$(native_validate_display "${MINIOS_X11_DISPLAY:-:1}")"
if [[ -n "${MINIOS_X11_DPI:-}" && ! "${MINIOS_X11_DPI}" =~ ^[7-9][0-9]$|^[1-3][0-9]{2}$|^400$ ]]; then
  native_die 'MINIOS_X11_DPI debe ser un número entre 70 y 400.'
fi

missing=()
for item in termux-x11 dbus-launch xfce4-session xfce4-panel; do
  command -v "$item" >/dev/null 2>&1 || missing+=("$item")
done
if ((${#missing[@]})); then
  printf 'Faltan comandos: %s\nEjecuta scripts/termux-native/install.sh --check y, si procede, --install.\n' "${missing[*]}" >&2
  exit 1
fi

STATE_DIR="$(native_ensure_state_dir)"
if native_active_session "$STATE_DIR"; then
  printf 'La sesión MiniOS XFCE ya está activa (display %s, controlador PID %s).\n' "$DISPLAY_ID" "$NATIVE_PID"
  exit 0
fi
if [[ -L "$STATE_DIR/start.lock" ]]; then
  native_die "el bloqueo de inicio es un enlace simbólico; revísalo manualmente: $STATE_DIR/start.lock"
fi
if ! mkdir -- "$STATE_DIR/start.lock" 2>/dev/null; then
  native_die "ya hay un inicio en curso o quedó un bloqueo tras un cierre abrupto: $STATE_DIR/start.lock. Revisa la sesión antes de borrarlo."
fi
printf '%s\n' "$$" > "$STATE_DIR/start.lock/owner"
release_lock() {
  if [[ ! -L "$STATE_DIR/start.lock/owner" && -f "$STATE_DIR/start.lock/owner" ]] && \
     [[ "$(cat -- "$STATE_DIR/start.lock/owner" 2>/dev/null || true)" == "$$" ]]; then
    rm -f -- "$STATE_DIR/start.lock/owner"
    rmdir -- "$STATE_DIR/start.lock" 2>/dev/null || true
  fi
}
trap release_lock EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# Drop stale metadata only after checking that it does not describe a live,
# token-matching supervisor. Do not touch any other process.
if native_read_meta "$STATE_DIR"; then
  if kill -0 "$NATIVE_PID" 2>/dev/null && native_pid_has_token "$NATIVE_PID" "$NATIVE_TOKEN"; then
    printf 'La sesión ya está activa (display %s, controlador PID %s).\n' "$DISPLAY_ID" "$NATIVE_PID"
    exit 0
  fi
  # If Android killed the supervisor abruptly, stop only recorded children
  # that still carry the prior session's token before launching a new display.
  native_stop_children_for_token "$STATE_DIR" "$NATIVE_TOKEN"
fi
native_remove_meta "$STATE_DIR"

TOKEN="native-$$-$(date +%s)-$RANDOM"
LOG_FILE="$STATE_DIR/session.log"
# The session supervisor writes its own PID/token and manages only the two
# child processes it launched, which inherit this unique session token.
nohup env "MINIOS_NATIVE_SESSION_TOKEN=$TOKEN" "$SCRIPT_DIR/session.sh" "$DISPLAY_ID" "$STATE_DIR" >> "$LOG_FILE" 2>&1 < /dev/null &
LAUNCH_PID=$!

for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if native_read_meta "$STATE_DIR" && [[ "$NATIVE_PID" == "$LAUNCH_PID" && "$NATIVE_TOKEN" == "$TOKEN" ]] && \
     native_pid_has_token "$LAUNCH_PID" "$TOKEN" && \
     [[ -f "$STATE_DIR/session.ready" && ! -L "$STATE_DIR/session.ready" ]] && \
     grep -Fxq -- "$TOKEN" "$STATE_DIR/session.ready"; then
    printf 'MiniOS XFCE inició en Termux:X11 (%s). Log: %s\n' "$DISPLAY_ID" "$LOG_FILE"
    printf 'Para detener esta sesión usa scripts/termux-native/stop.sh.\n'
    exit 0
  fi
  if ! kill -0 "$LAUNCH_PID" 2>/dev/null; then
    break
  fi
  sleep 1
done

if kill -0 "$LAUNCH_PID" 2>/dev/null && native_pid_has_token "$LAUNCH_PID" "$TOKEN"; then
  native_stop_child_if_owned "$LAUNCH_PID" "$TOKEN"
fi
native_remove_meta_if_owner "$STATE_DIR" "$LAUNCH_PID" "$TOKEN"
printf 'No se confirmó que XFCE arrancara. No se dejaron procesos de sesión controlados; revisa el log: %s\n' "$LOG_FILE" >&2
exit 1
