#!/usr/bin/env bash
# Stop only the supervisor whose private PID/token metadata matches this session.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/termux-native/common.sh
source "$SCRIPT_DIR/common.sh"
[[ $# -eq 0 ]] || native_die 'stop.sh no acepta argumentos.'
native_require_termux
STATE_DIR="$(native_state_dir)"

if [[ -L "$STATE_DIR" ]]; then
  native_die "el directorio de estado es un enlace simbólico; no se detuvo ningún proceso: $STATE_DIR"
fi
if [[ ! -d "$STATE_DIR" ]]; then
  printf 'No hay una sesión MiniOS XFCE registrada.\n'
  exit 0
fi

if ! native_read_meta "$STATE_DIR"; then
  if [[ -L "$STATE_DIR/session.pid" || -L "$STATE_DIR/session.token" ]]; then
    native_die 'los metadatos de sesión contienen un enlace simbólico; no se detuvo ningún proceso.'
  fi
  native_remove_meta "$STATE_DIR"
  printf 'No hay una sesión MiniOS XFCE activa (se limpiaron solo metadatos regulares obsoletos).\n'
  exit 0
fi
PID="$NATIVE_PID"
TOKEN="$NATIVE_TOKEN"
if ! kill -0 "$PID" 2>/dev/null || ! native_pid_has_token "$PID" "$TOKEN"; then
  native_stop_children_for_token "$STATE_DIR" "$TOKEN"
  native_remove_meta_if_owner "$STATE_DIR" "$PID" "$TOKEN"
  printf 'La sesión ya había terminado; no se señalizó ningún otro proceso.\n'
  exit 0
fi

kill -TERM "$PID" 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if ! kill -0 "$PID" 2>/dev/null || ! native_pid_has_token "$PID" "$TOKEN"; then
    native_remove_meta_if_owner "$STATE_DIR" "$PID" "$TOKEN"
    printf 'Sesión MiniOS XFCE detenida; solo se solicitó terminar su supervisor identificado.\n'
    exit 0
  fi
  sleep 1
done
printf 'El supervisor sigue activo tras SIGTERM; no se usó SIGKILL para evitar dejar hijos huérfanos. Revisa %s/session.log antes de actuar.\n' "$STATE_DIR" >&2
exit 1
