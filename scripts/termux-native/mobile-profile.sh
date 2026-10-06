#!/usr/bin/env bash
# Opt-in, reversible MiniAriño panel/menu profile isolated from ~/.config/xfce4.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/termux-native/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'EOF'
Uso:
  scripts/termux-native/mobile-profile.sh --status   # solo lectura
  scripts/termux-native/mobile-profile.sh --apply    # copia de seguridad + confirmación
  scripts/termux-native/mobile-profile.sh --restore  # revierte solo archivos sin cambios

El perfil es opt-in. XFCE lo carga desde XDG_CONFIG_HOME y XDG_DATA_HOME privados;
no modifica ~/.config/xfce4 ni ~/Desktop. Añade un panel con menú y accesos grandes
para terminal, archivos y navegación web: Chromium en XFCE si está instalado; en caso contrario,
entrega la URL al navegador Android. La compatibilidad
visual/táctil y la ubicación del panel deben verificarse en el teléfono. Añade un acceso
Godot al menú MiniAriño; Godot se instala por separado con install.sh --install-godot.
EOF
}
MODE="${1:-}"
case "$MODE" in
  --status|--apply|--restore) ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
[[ $# -eq 1 ]] || { usage >&2; exit 2; }
native_require_termux

CONFIG_ROOT="$HOME/.config/miniarino-native"
DATA_ROOT="$HOME/.local/share/miniarino-native"
BACKUP_ROOT="$HOME/.local/share/miniarino-native-backups"
PANEL_REL='config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml'
TERMINAL_REL='data/applications/miniarino-terminal.desktop'
FILES_REL='data/applications/miniarino-files.desktop'
BROWSER_REL='data/applications/miniarino-browser-handoff.desktop'
GODOT_REL='data/applications/miniarino-godot.desktop'
HELPER_REL='data/bin/miniarino-browser-prompt'
REL_PATHS=("$PANEL_REL" "$TERMINAL_REL" "$FILES_REL" "$BROWSER_REL" "$GODOT_REL" "$HELPER_REL")
MANIFEST="$CONFIG_ROOT/profile.manifest"
ENABLED="$CONFIG_ROOT/profile.enabled"

path_for() {
  case "$1" in
    config/*) printf '%s/%s' "$HOME/.config/miniarino-native" "${1#config/}" ;;
    data/*) printf '%s/%s' "$HOME/.local/share/miniarino-native" "${1#data/}" ;;
    *) native_die "ruta de perfil interna no permitida: $1" ;;
  esac
}

check_no_symlink() {
  local path="$1"
  [[ ! -L "$path" ]] || native_die "ruta de perfil es un enlace simbólico; no se modificó: $path"
  [[ ! -e "$path" || -d "$path" ]] || native_die "se esperaba un directorio, no se modificó: $path"
}

check_parent_chain() {
  local path="$1" parent
  parent="$(dirname -- "$path")"
  while [[ "$parent" != "$HOME" && "$parent" != / ]]; do
    [[ ! -L "$parent" ]] || native_die "directorio padre es un enlace simbólico; no se modificó: $parent"
    parent="$(dirname -- "$parent")"
  done
}

ensure_dirs() {
  local rel path parent
  umask 077
  for path in "$HOME/.config" "$HOME/.config/miniarino-native" \
              "$HOME/.local" "$HOME/.local/share" "$HOME/.local/share/miniarino-native" \
              "$BACKUP_ROOT"; do
    check_parent_chain "$path"
    check_no_symlink "$path"
    mkdir -p -- "$path"
    check_no_symlink "$path"
  done
  for rel in "$PANEL_REL" "$TERMINAL_REL" "$FILES_REL" "$BROWSER_REL" "$GODOT_REL" "$HELPER_REL"; do
    path="$(path_for "$rel")"
    parent="$(dirname -- "$path")"
    check_parent_chain "$parent"
    check_no_symlink "$parent"
    mkdir -p -- "$parent"
    check_no_symlink "$parent"
  done
}

profile_active() {
  [[ ! -L "$ENABLED" ]] || native_die "marcador de perfil es un enlace simbólico; revísalo: $ENABLED"
  [[ ! -e "$ENABLED" || -f "$ENABLED" ]] || native_die "marcador de perfil no es un archivo regular: $ENABLED"
  if [[ -f "$ENABLED" ]]; then
    grep -Fxq 'mobile-v1' "$ENABLED" || native_die "marcador de perfil no reconocido: $ENABLED"
    return 0
  fi
  return 1
}

session_must_be_stopped() {
  local state_dir
  state_dir="$(native_state_dir)"
  [[ ! -L "$state_dir" ]] || native_die "directorio de estado es un enlace simbólico: $state_dir"
  if [[ -d "$state_dir" ]] && native_active_session "$state_dir"; then
    native_die 'detén primero la sesión MiniAriño con scripts/termux-native/stop.sh.'
  fi
}

if [[ "$MODE" == --status ]]; then
  if profile_active; then
    printf 'Perfil MiniAriño móvil activo; configuración aislada en %s.\n' "$CONFIG_ROOT"
  elif [[ -f "$MANIFEST" ]]; then
    printf 'Hay una aplicación de perfil incompleta o pendiente de revertir. Revisa el respaldo y ejecuta --restore.\n'
    exit 1
  else
    printf 'Perfil MiniAriño móvil inactivo; no se modificó ~/.config/xfce4.\n'
  fi
  exit 0
fi

session_must_be_stopped
ensure_dirs

if [[ "$MODE" == --apply ]]; then
  if profile_active || [[ -e "$MANIFEST" || -L "$MANIFEST" ]]; then
    native_die 'ya hay un perfil activo o una aplicación parcial; revisa el estado y ejecuta --restore antes de volver a aplicar.'
  fi
  printf 'Se creará un panel XFCE experimental con menú MiniAriño y accesos a Terminal, Archivos y navegador web.\n'
  printf 'Solo se tocarán archivos de configuración/datos propios del perfil, con copia previa; no se instalarán paquetes.\n'
  if ! IFS= read -r -p '¿Aplicar el perfil móvil? [y/N] ' answer; then
    printf 'Cancelado; no se cambió el perfil.\n'
    exit 0
  fi
  case "$answer" in y|Y|yes|YES|s|S|si|SI|sí|Sí) ;; *) printf 'Cancelado; no se cambió el perfil.\n'; exit 0 ;; esac

  backup_id="$(date +%Y%m%dT%H%M%S)-$$"
  backup="$BACKUP_ROOT/$backup_id"
  [[ ! -e "$backup" && ! -L "$backup" ]] || native_die "el respaldo ya existe: $backup"
  mkdir -m 700 -- "$backup"
  mkdir -m 700 -- "$backup/original" "$backup/generated"
  for rel in "${REL_PATHS[@]}"; do
    mkdir -p -- "$backup/generated/$(dirname -- "$rel")"
  done
  : > "$backup/manifest"
  chmod 600 "$backup/manifest"

  for rel in "${REL_PATHS[@]}"; do
    target="$(path_for "$rel")"
    [[ ! -L "$target" ]] || native_die "el archivo destino es un enlace simbólico; no se modificó: $target"
    if [[ -e "$target" ]]; then
      [[ -f "$target" ]] || native_die "el destino ya existe y no es un archivo regular: $target"
      mkdir -p -- "$backup/original/$(dirname -- "$rel")"
      cp -p -- "$target" "$backup/original/$rel"
      printf 'EXISTS\t%s\n' "$rel" >> "$backup/manifest"
    else
      printf 'ABSENT\t%s\n' "$rel" >> "$backup/manifest"
    fi
  done

  cat > "$backup/generated/$PANEL_REL" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=10;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="icon-size" type="uint" value="40"/>
      <property name="size" type="uint" value="56"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/><value type="int" value="2"/>
        <value type="int" value="3"/><value type="int" value="4"/>
        <value type="int" value="5"/><value type="int" value="6"/>
        <value type="int" value="7"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="applicationsmenu">
      <property name="show-button-title" type="bool" value="true"/>
      <property name="button-title" type="string" value="MiniAriño"/>
    </property>
    <property name="plugin-2" type="string" value="tasklist"/>
    <property name="plugin-3" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-4" type="string" value="launcher">
      <property name="items" type="array"><value type="string" value="miniarino-terminal.desktop"/></property>
    </property>
    <property name="plugin-5" type="string" value="launcher">
      <property name="items" type="array"><value type="string" value="miniarino-files.desktop"/></property>
    </property>
    <property name="plugin-6" type="string" value="launcher">
      <property name="items" type="array"><value type="string" value="miniarino-browser-handoff.desktop"/></property>
    </property>
    <property name="plugin-7" type="string" value="clock"/>
  </property>
</channel>
EOF
  cat > "$backup/generated/$TERMINAL_REL" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=MiniAriño — Terminal
Comment=Abrir el terminal nativo de Termux dentro de XFCE
Exec=xfce4-terminal
Icon=utilities-terminal
Terminal=false
Categories=System;TerminalEmulator;
StartupNotify=true
EOF
  cat > "$backup/generated/$FILES_REL" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=MiniAriño — Archivos
Comment=Abrir Thunar en el almacenamiento disponible para Termux
Exec=thunar
Icon=system-file-manager
Terminal=false
Categories=Utility;FileManager;
StartupNotify=true
EOF
  cat > "$backup/generated/$BROWSER_REL" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=MiniAriño — Navegador web
Comment=Abrir Chromium dentro de XFCE si está instalado; si no, usar el navegador Android
Exec=xfce4-terminal --execute miniarino-browser-prompt
Icon=web-browser
Terminal=false
Categories=Network;WebBrowser;
StartupNotify=true
EOF
  cat > "$backup/generated/$GODOT_REL" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=MiniAriño — Godot Engine
Comment=Abrir el editor Godot 4 en el escritorio XFCE
Exec=godot --editor
Icon=applications-games
Terminal=false
Categories=Development;IDE;Game;
StartupNotify=true
EOF
  cp -- "$SCRIPT_DIR/browser-prompt.sh" "$backup/generated/$HELPER_REL"
  chmod 755 "$backup/generated/$HELPER_REL"
  chmod 644 "$backup/generated/$PANEL_REL" "$backup/generated/$TERMINAL_REL" \
    "$backup/generated/$FILES_REL" "$backup/generated/$BROWSER_REL" "$backup/generated/$GODOT_REL"
  printf 'backup_id=%s\n' "$backup_id" > "$MANIFEST.tmp.$$"
  chmod 600 "$MANIFEST.tmp.$$"
  mv -- "$MANIFEST.tmp.$$" "$MANIFEST"

  for rel in "${REL_PATHS[@]}"; do
    target="$(path_for "$rel")"
    temp="$target.tmp.$$"
    cp -- "$backup/generated/$rel" "$temp"
    if [[ "$rel" == "$HELPER_REL" ]]; then chmod 755 "$temp"; else chmod 644 "$temp"; fi
    mv -f -- "$temp" "$target"
  done
  printf 'mobile-v1\n' > "$ENABLED.tmp.$$"
  chmod 600 "$ENABLED.tmp.$$"
  mv -- "$ENABLED.tmp.$$" "$ENABLED"
  printf 'Perfil aplicado. Copia de seguridad: %s\n' "$backup"
  printf 'La ubicación/panel, resolución, orientación, teclado, toque y reanudación deben probarse en Android.\n'
  exit 0
fi

# --restore: refuse conflicts instead of silently overwriting settings edited
# after profile activation. The backup remains available until the user decides.
[[ -f "$MANIFEST" && ! -L "$MANIFEST" ]] || native_die 'no se encontró un manifiesto de perfil válido; no se revirtió ningún archivo.'
IFS= read -r manifest_line < "$MANIFEST" || native_die 'manifiesto vacío; no se revirtió ningún archivo.'
[[ "$manifest_line" =~ ^backup_id=([0-9]{8}T[0-9]{6}-[0-9]+)$ ]] || native_die 'manifiesto no válido; no se revirtió ningún archivo.'
backup_id="${BASH_REMATCH[1]}"
backup="$BACKUP_ROOT/$backup_id"
[[ ! -L "$backup" && -d "$backup" && ! -L "$backup/manifest" && -f "$backup/manifest" ]] || native_die 'copia de seguridad ausente o insegura; no se revirtió ningún archivo.'
check_parent_chain "$backup/manifest"
[[ ! -L "$ENABLED" && ( ! -e "$ENABLED" || -f "$ENABLED" ) ]] || native_die 'marcador de perfil inseguro; no se revirtió ningún archivo.'
if [[ -f "$ENABLED" ]]; then
  grep -Fxq 'mobile-v1' "$ENABLED" || native_die 'marcador de perfil cambió; no se revirtió ningún archivo.'
fi

declare -A BACKUP_STATES=()
while IFS=$'\t' read -r kind rel; do
  [[ "$kind" == EXISTS || "$kind" == ABSENT ]] || native_die 'manifiesto de respaldo dañado; no se revirtió ningún archivo.'
  allowed=0
  for known in "${REL_PATHS[@]}"; do [[ "$rel" == "$known" ]] && allowed=1; done
  ((allowed)) || native_die 'manifiesto contiene una ruta desconocida; no se revirtió ningún archivo.'
  [[ -z "${BACKUP_STATES[$rel]:-}" ]] || native_die 'manifiesto contiene destinos duplicados; no se revirtió ningún archivo.'
  BACKUP_STATES[$rel]="$kind"
  if [[ "$kind" == EXISTS ]]; then
    original="$backup/original/$rel"
    check_parent_chain "$original"
    [[ -f "$original" && ! -L "$original" ]] || native_die "no está la copia previa de $rel; no se revirtió ningún archivo."
  fi
done < "$backup/manifest"
for rel in "${REL_PATHS[@]}"; do
  if [[ -z "${BACKUP_STATES[$rel]:-}" ]]; then
    [[ "$rel" == "$GODOT_REL" ]] && continue
    native_die "falta una entrada de respaldo para $rel; no se revirtió ningún archivo."
  fi
  target="$(path_for "$rel")"
  generated="$backup/generated/$rel"
  check_parent_chain "$generated"
  [[ ! -L "$target" && -f "$target" && -f "$generated" && ! -L "$generated" ]] || native_die "estado incompleto o inseguro; no se revirtió ningún archivo: $target"
  cmp -s -- "$target" "$backup/generated/$rel" || native_die "el perfil cambió desde que se aplicó; no se sobreescribió $target. La copia sigue en $backup"
done
printf 'Se restaurarán únicamente los archivos gestionados que siguen idénticos al perfil instalado.\n'
if ! IFS= read -r -p '¿Restaurar la copia anterior y quitar el perfil? [y/N] ' answer; then
  printf 'Cancelado; no se cambió el perfil.\n'
  exit 0
fi
case "$answer" in y|Y|yes|YES|s|S|si|SI|sí|Sí) ;; *) printf 'Cancelado; no se cambió el perfil.\n'; exit 0 ;; esac

for rel in "${REL_PATHS[@]}"; do
  [[ -n "${BACKUP_STATES[$rel]:-}" ]] || continue
  target="$(path_for "$rel")"
  if [[ "${BACKUP_STATES[$rel]}" == EXISTS ]]; then
    original="$backup/original/$rel"
    temp="$target.restore.$$"
    cp -p -- "$original" "$temp"
    mv -f -- "$temp" "$target"
  else
    rm -- "$target"
  fi
done
[[ ! -L "$ENABLED" ]] || native_die 'marcador de perfil inseguro; archivos restaurados, pero queda por revisar el marcador.'
[[ ! -e "$ENABLED" ]] || rm -- "$ENABLED"
[[ ! -L "$MANIFEST" ]] || native_die 'manifiesto de perfil inseguro; archivos restaurados, pero queda por revisar el manifiesto.'
rm -- "$MANIFEST"
printf 'Perfil revertido. Respaldo conservado en %s\n' "$backup"
printf 'Vuelve a iniciar XFCE para que el entorno aislado deje de estar en uso.\n'
