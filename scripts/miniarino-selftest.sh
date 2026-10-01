#!/usr/bin/env bash
# Run as the logged-in, unprivileged user inside the XFCE desktop session.
set -uo pipefail

PASS=0
FAIL=0
WARN=0
UID_NUM="$(id -u)"
LOG_DIR="$HOME/.cache/miniarino-selftest"
mkdir -p "$LOG_DIR" || { echo 'No se pudo crear el registro del autodiagnóstico.' >&2; exit 2; }
LOG_FILE="$LOG_DIR/last.log"
EXIT_FILE="$LOG_DIR/last.exitcode"
exec > >(tee "$LOG_FILE") 2>&1
CHANNEL="miniarino-selftest-$$"
PROPERTY='/runtime/roundtrip'
CHANNEL_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/xfce4/xfconf/xfce-perchannel-xml/${CHANNEL}.xml"
TMPDIR_TEST=""

pass() { printf 'PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
warn() { printf 'WARN  %s\n' "$1"; WARN=$((WARN + 1)); }
check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}
check_command() { command -v "$1" >/dev/null 2>&1; }
check_process() { pgrep -u "$UID_NUM" -x "$1" >/dev/null 2>&1; }
cleanup() {
  if command -v xfconf-query >/dev/null 2>&1; then
    xfconf-query -c "$CHANNEL" -p "$PROPERTY" --reset >/dev/null 2>&1 || true
  fi
  rm -f -- "$CHANNEL_FILE"
  if [[ -n "$TMPDIR_TEST" && "$TMPDIR_TEST" == "${XDG_RUNTIME_DIR:-$HOME}"/miniarino-test.* ]]; then
    rm -rf -- "$TMPDIR_TEST"
  fi
  sync
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Diagnóstico MiniAriño — %s — usuario %s\n\n' "$(date --iso-8601=seconds 2>/dev/null || date)" "$(id -un)"

if (( UID_NUM == 0 )); then
  fail 'La prueba debe ejecutarse como usuario de la sesión, no como root'
else
  pass 'Ejecución como usuario sin privilegios'
fi

for app in xfce4-session xfwm4 xfce4-panel xfdesktop xfconfd xfconf-query \
           xfce4-terminal thunar firefox-esr synaptic-pkexec desktop-file-validate \
           xprop xdpyinfo xrandr dbus-send nmcli git nmap python3; do
  check "Comando instalado: $app" check_command "$app"
done

check 'LightDM activo' systemctl is-active --quiet lightdm.service
check 'NetworkManager activo' systemctl is-active --quiet NetworkManager.service
check 'Sesión XFCE activa' check_process xfce4-session
check 'Administrador de ventanas xfwm4 activo' check_process xfwm4
check 'Panel XFCE activo' check_process xfce4-panel
check 'Gestor de escritorio xfdesktop activo' check_process xfdesktop

if [[ -n "${DISPLAY:-}" ]]; then
  pass "DISPLAY definido: $DISPLAY"
  check 'Servidor X responde' xdpyinfo -display "$DISPLAY"
  if xrandr --query 2>/dev/null | grep -q ' connected'; then pass 'Pantalla detectada por RandR'; else fail 'Pantalla detectada por RandR'; fi
else
  fail 'DISPLAY definido (ejecuta esta prueba desde la sesión gráfica)'
fi

if [[ "${XDG_CURRENT_DESKTOP:-}" =~ [Xx][Ff][Cc][Ee] ]]; then
  pass "Entorno de escritorio: ${XDG_CURRENT_DESKTOP}"
else
  warn "XDG_CURRENT_DESKTOP no indica XFCE (${XDG_CURRENT_DESKTOP:-vacío})"
fi

if dbus-send --session --print-reply --dest=org.freedesktop.DBus \
     /org/freedesktop/DBus org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
  pass 'Bus D-Bus de sesión responde'
else
  fail 'Bus D-Bus de sesión responde'
fi

if xfconf-query -c xfce4-desktop -l >/dev/null 2>&1; then
  pass 'Canal de configuración del escritorio accesible'
else
  fail 'Canal de configuración del escritorio accesible'
fi

WM_ID="$(xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | sed -nE 's/.*window id # (0x[[:xdigit:]]+).*/\1/p')"
if [[ -n "$WM_ID" ]] && xprop -id "$WM_ID" _NET_WM_NAME 2>/dev/null | grep -Eiq 'xfwm4'; then
  pass 'Gestor de ventanas anuncia xfwm4 mediante EWMH'
else
  fail 'Gestor de ventanas anuncia xfwm4 mediante EWMH'
fi

WALLPAPER='/usr/share/backgrounds/miniarino-wallpaper.svg'
if [[ -r "$WALLPAPER" ]] && grep -Fq "$WALLPAPER" "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml" 2>/dev/null; then
  pass 'Wallpaper MiniAriño instalado y configurado para el usuario'
else
  fail 'Wallpaper MiniAriño instalado y configurado para el usuario'
fi

for dir in Desktop Documents Downloads Pictures; do
  if [[ -d "$HOME/$dir" && -w "$HOME/$dir" ]]; then pass "Carpeta personal disponible: $dir"; else fail "Carpeta personal disponible: $dir"; fi
done

if python3 - "$HOME/Desktop" <<'PY'
import configparser, os, pathlib, shlex, shutil, sys
base=pathlib.Path(sys.argv[1])
expected=['Archivos.desktop','Navegador.desktop','Terminal.desktop','Programas.desktop','Diagnostico.desktop']
errors=[]
for name in expected:
    p=base/name
    if not p.is_file():
        errors.append(f'no existe {name}')
        continue
    parser=configparser.ConfigParser(interpolation=None, strict=True)
    try:
        parser.read(p,encoding='utf-8')
        section=parser['Desktop Entry']
        if section.get('Type')!='Application':
            errors.append(f'{name}: Type no es Application')
        argv=shlex.split(section.get('Exec',''))
        if not argv:
            errors.append(f'{name}: Exec vacío')
        else:
            command=argv[0]
            exists=(pathlib.Path(command).is_file() and os.access(command,os.X_OK)) if command.startswith('/') else shutil.which(command)
            if not exists:
                errors.append(f'{name}: no se encuentra el ejecutable {command}')
    except Exception as e:
        errors.append(f'{name}: archivo inválido ({e})')
if errors:
    print('FAIL  Launchers de escritorio: '+'; '.join(errors))
    raise SystemExit(1)
print(f'PASS  {len(expected)} launchers tienen formato y ejecutable disponibles')
PY
then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
fi

DESKTOP_BAD=0
for launcher in "$HOME"/Desktop/*.desktop; do
  [[ -e "$launcher" ]] || continue
  if ! desktop-file-validate "$launcher" >/dev/null 2>&1; then
    printf 'FAIL  Archivo .desktop inválido: %s\n' "$launcher"
    DESKTOP_BAD=1
  fi
done
if (( DESKTOP_BAD == 0 )); then pass 'Validación freedesktop de todos los launchers'; else FAIL=$((FAIL + 1)); fi

# Use a unique temporary Xfconf channel to exercise upstream-style property
# creation, read-back and reset without touching the user's real settings.
VALUE="ok-$(date +%s)-$$"
if xfconf-query -c "$CHANNEL" -p "$PROPERTY" --create -t string -s "$VALUE" >/dev/null 2>&1; then
  readback="$(xfconf-query -c "$CHANNEL" -p "$PROPERTY" 2>/dev/null || true)"
  if [[ "$readback" = "$VALUE" ]]; then pass 'Xfconf set/get en canal temporal'; else fail 'Xfconf set/get en canal temporal'; fi
  if xfconf-query -c "$CHANNEL" -p "$PROPERTY" --reset >/dev/null 2>&1 \
     && ! xfconf-query -c "$CHANNEL" -p "$PROPERTY" >/dev/null 2>&1; then
    pass 'Xfconf reset elimina la propiedad temporal'
  else
    fail 'Xfconf reset elimina la propiedad temporal'
  fi
else
  fail 'Xfconf permite crear una propiedad temporal'
fi
cleanup

# Exercise temporary file access and symlink resolution, mirroring Thunar's
# upstream category without altering files outside a private scratch folder.
RUNTIME_BASE="${XDG_RUNTIME_DIR:-$HOME}"
TMPDIR_TEST="$(mktemp -d "$RUNTIME_BASE/miniarino-test.XXXXXX" 2>/dev/null || true)"
if [[ -n "$TMPDIR_TEST" ]]; then
  printf 'MiniAriño selftest\n' > "$TMPDIR_TEST/original.txt"
  if ln -s original.txt "$TMPDIR_TEST/alias.txt" 2>/dev/null \
     && [[ "$(realpath "$TMPDIR_TEST/alias.txt" 2>/dev/null)" = "$TMPDIR_TEST/original.txt" ]] \
     && [[ "$(cat "$TMPDIR_TEST/alias.txt")" = 'MiniAriño selftest' ]]; then
    pass 'Archivo temporal y resolución de enlace simbólico'
  else
    fail 'Archivo temporal y resolución de enlace simbólico'
  fi
else
  fail 'Creación de directorio temporal para prueba de archivos'
fi

check 'Versión de Thunar disponible' thunar --version
check 'Versión de Terminal XFCE disponible' xfce4-terminal --version
check 'Versión de Firefox ESR disponible' firefox-esr --version
check 'Git disponible' git --version
check 'Nmap disponible' nmap --version
check 'NetworkManager responde a nmcli' nmcli general status

printf '\nResumen: %d PASS, %d FAIL, %d WARN\n' "$PASS" "$FAIL" "$WARN"
RESULT=0
if (( FAIL > 0 )); then RESULT=1; fi
printf '%s\n' "$RESULT" > "$EXIT_FILE"
sync
exit "$RESULT"
