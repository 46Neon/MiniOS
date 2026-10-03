#!/usr/bin/env bash
# Shared, read-only checks and state helpers for the native Termux XFCE scaffold.
set -Eeuo pipefail

NATIVE_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_REPO_ROOT="$(cd -- "$NATIVE_SCRIPT_DIR/../.." && pwd)"

native_die() {
  printf 'MiniOS Termux XFCE: %s\n' "$*" >&2
  exit 2
}

native_require_termux() {
  if [[ -z "${TERMUX_VERSION:-}" || -z "${PREFIX:-}" || ! -d "${PREFIX:-/nonexistent}" || ! -x "${PREFIX:-/nonexistent}/bin/pkg" ]]; then
    native_die 'este comando solo se puede usar desde Termux (se requieren TERMUX_VERSION, PREFIX y pkg). No se modificó ningún paquete.'
  fi
}

native_validate_display() {
  local display="${1:-:1}"
  [[ "$display" =~ ^:[0-9]{1,2}$ ]] || native_die 'display no válido; usa :1, :2, etc. (MINIOS_X11_DISPLAY).'
  printf '%s' "$display"
}

native_state_dir() {
  printf '%s/var/run/minios-native-xfce' "$PREFIX"
}

native_ensure_state_dir() {
  local dir
  dir="$(native_state_dir)"
  [[ ! -L "$dir" ]] || native_die "la ruta de estado es un enlace simbólico; revísala manualmente: $dir"
  mkdir -p -- "$dir"
  chmod 700 -- "$dir"
  printf '%s' "$dir"
}

native_meta_is_safe() {
  local dir="$1"
  [[ ! -L "$dir/session.pid" && ! -L "$dir/session.token" && -f "$dir/session.pid" && -f "$dir/session.token" ]]
}

native_read_meta() {
  local dir="$1"
  NATIVE_PID=''
  NATIVE_TOKEN=''
  native_meta_is_safe "$dir" || return 1
  IFS= read -r NATIVE_PID < "$dir/session.pid" || return 1
  IFS= read -r NATIVE_TOKEN < "$dir/session.token" || return 1
  [[ "$NATIVE_PID" =~ ^[0-9]{1,10}$ && "$NATIVE_PID" -gt 1 ]] || return 1
  [[ "$NATIVE_TOKEN" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || return 1
}

native_pid_has_token() {
  local pid="$1" token="$2"
  [[ "$pid" =~ ^[0-9]{1,10}$ && "$pid" -gt 1 && -r "/proc/$pid/environ" ]] || return 1
  grep -aFq -- "MINIOS_NATIVE_SESSION_TOKEN=$token" "/proc/$pid/environ" 2>/dev/null
}

native_active_session() {
  local dir="$1"
  native_read_meta "$dir" || return 1
  kill -0 "$NATIVE_PID" 2>/dev/null && native_pid_has_token "$NATIVE_PID" "$NATIVE_TOKEN"
}

native_remove_meta() {
  local dir="$1" name
  # Only unlink regular metadata files, never follow or remove symlinks.
  for name in session.pid session.token session.ready x11.pid desktop.pid; do
    [[ ! -L "$dir/$name" && -f "$dir/$name" ]] && rm -f -- "$dir/$name"
  done
  return 0
}

native_stop_children_for_token() {
  local dir="$1" token="$2" name pid
  for name in x11.pid desktop.pid; do
    [[ ! -L "$dir/$name" && -f "$dir/$name" ]] || continue
    IFS= read -r pid < "$dir/$name" || continue
    [[ "$pid" =~ ^[0-9]{1,10}$ && "$pid" -gt 1 ]] || continue
    native_stop_child_if_owned "$pid" "$token"
  done
}

native_remove_meta_if_owner() {
  local dir="$1" pid="$2" token="$3"
  if native_read_meta "$dir" && [[ "$NATIVE_PID" == "$pid" && "$NATIVE_TOKEN" == "$token" ]]; then
    native_remove_meta "$dir"
  fi
}

native_stop_child_if_owned() {
  local pid="${1:-}" token="${2:-}"
  [[ "$pid" =~ ^[0-9]{1,10}$ && "$pid" -gt 1 ]] || return 0
  if kill -0 "$pid" 2>/dev/null && native_pid_has_token "$pid" "$token"; then
    kill -TERM "$pid" 2>/dev/null || true
    local n
    for n in 1 2 3 4 5; do
      kill -0 "$pid" 2>/dev/null || return 0
      native_pid_has_token "$pid" "$token" || return 0
      sleep 1
    done
    # Escalate only if the same process still carries this session's token.
    if kill -0 "$pid" 2>/dev/null && native_pid_has_token "$pid" "$token"; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
}
