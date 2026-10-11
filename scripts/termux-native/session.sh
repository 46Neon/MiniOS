#!/usr/bin/env bash
# Internal supervisor started by start.sh. It owns only its X11/desktop children.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/termux-native/common.sh
source "$SCRIPT_DIR/common.sh"
native_require_termux

# The mobile profile is opt-in and kept in dedicated XDG directories. Without
# its explicit marker, start XFCE with Termux's normal user configuration.
PROFILE_MARKER="$HOME/.config/miniarino-native/profile.enabled"
if [[ -L "$PROFILE_MARKER" ]]; then
  native_die "marcador de perfil es un enlace simbólico; revísalo: $PROFILE_MARKER"
elif [[ -f "$PROFILE_MARKER" ]]; then
  grep -Fxq 'mobile-v1' "$PROFILE_MARKER" || native_die 'marcador de perfil no reconocido.'
  CONFIG_ROOT="$HOME/.config/miniarino-native"
  DATA_ROOT="$HOME/.local/share/miniarino-native"
  [[ ! -L "$CONFIG_ROOT" && ! -L "$DATA_ROOT" && -d "$CONFIG_ROOT" && -d "$DATA_ROOT" ]] || native_die 'directorios del perfil móvil ausentes o inseguros.'
  export XDG_CONFIG_HOME="$CONFIG_ROOT"
  export XDG_DATA_HOME="$DATA_ROOT"
  export XDG_DATA_DIRS="$DATA_ROOT:$PREFIX/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  export XDG_CONFIG_DIRS="$PREFIX/etc/xdg:${XDG_CONFIG_DIRS:-/etc/xdg}"
  export PATH="$DATA_ROOT/bin:$PATH"
fi

DISPLAY_ID="$(native_validate_display "${1:-:1}")"
STATE_DIR="${2:-$(native_ensure_state_dir)}"
TOKEN="${MINIOS_NATIVE_SESSION_TOKEN:-}"
[[ "$TOKEN" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || native_die 'token interno de sesión no válido.'
[[ ! -L "$STATE_DIR" && -d "$STATE_DIR" ]] || native_die 'directorio de estado ausente o inseguro.'

X11_PID=''
DESKTOP_PID=''
cleanup() {
  local status=$?
  trap - EXIT INT TERM HUP
  native_stop_child_if_owned "$DESKTOP_PID" "$TOKEN"
  native_stop_child_if_owned "$X11_PID" "$TOKEN"
  [[ ! -L "$STATE_DIR/session.ready" && -f "$STATE_DIR/session.ready" ]] && rm -f -- "$STATE_DIR/session.ready"
  native_remove_meta_if_owner "$STATE_DIR" "$$" "$TOKEN"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

umask 077
printf '%s\n' "$TOKEN" > "$STATE_DIR/session.token.tmp.$$"
mv -f -- "$STATE_DIR/session.token.tmp.$$" "$STATE_DIR/session.token"
printf '%s\n' "$$" > "$STATE_DIR/session.pid.tmp.$$"
mv -f -- "$STATE_DIR/session.pid.tmp.$$" "$STATE_DIR/session.pid"

LOG_FILE="$STATE_DIR/session.log"
: >> "$LOG_FILE"
chmod 600 -- "$LOG_FILE"
write_child_pid() {
  local name="$1" pid="$2"
  printf '%s\n' "$pid" > "$STATE_DIR/$name.tmp.$$"
  mv -f -- "$STATE_DIR/$name.tmp.$$" "$STATE_DIR/$name"
}

# Official Termux:X11 flow: start its local X server, then attach an XFCE
# session on the same display using dbus-launch --exit-with-session.
X11_ARGS=("$DISPLAY_ID")
if [[ -n "${MINIOS_X11_DPI:-}" ]]; then
  [[ "${MINIOS_X11_DPI}" =~ ^([7-9][0-9]|[1-3][0-9]{2}|400)$ ]] || native_die 'MINIOS_X11_DPI debe ser un número entre 70 y 400.'
  X11_ARGS+=(-dpi "$MINIOS_X11_DPI")
fi
termux-x11 "${X11_ARGS[@]}" >> "$LOG_FILE" 2>&1 &
X11_PID=$!
write_child_pid x11.pid "$X11_PID"
sleep 1
if ! kill -0 "$X11_PID" 2>/dev/null; then
  printf 'No se pudo mantener termux-x11; revisa %s\n' "$LOG_FILE" >&2
  exit 1
fi

printf '%s\n' "$TOKEN" > "$STATE_DIR/session.ready.tmp.$$"
mv -f -- "$STATE_DIR/session.ready.tmp.$$" "$STATE_DIR/session.ready"

DISPLAY="$DISPLAY_ID" dbus-launch --exit-with-session xfce4-session >> "$LOG_FILE" 2>&1 &
DESKTOP_PID=$!
write_child_pid desktop.pid "$DESKTOP_PID"
wait "$DESKTOP_PID"
