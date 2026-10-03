#!/usr/bin/env bash
# Safe host tests. All Termux commands are isolated under a temporary fake HOME/PREFIX.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/scripts/termux-native"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

while IFS= read -r -d '' file; do
  bash -n "$file"
done < <(find "$ROOT/scripts" "$ROOT/tests" -type f -name '*.sh' -print0)
printf 'PASS: shell syntax checks\n'

# With no stale PID files, metadata cleanup must still succeed under set -e;
# start.sh calls this before launching the session supervisor.
source "$SCRIPTS/common.sh"
mkdir -p "$TMP/empty-session-state"
native_remove_meta "$TMP/empty-session-state"
printf 'PASS: empty session metadata cleanup is successful\n'

FAKE_HOME="$TMP/home"
FAKE_PREFIX="$TMP/prefix"
mkdir -p "$FAKE_HOME" "$FAKE_PREFIX/bin" "$TMP/mock-bin"
cat > "$FAKE_PREFIX/bin/pkg" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >> "$PKG_CALL_LOG"
exit 0
EOF
chmod +x "$FAKE_PREFIX/bin/pkg"
export PKG_CALL_LOG="$TMP/pkg-calls.log"
export HOME="$FAKE_HOME"
export PATH="$TMP/mock-bin:$FAKE_PREFIX/bin:$PATH"

expect_termux_refusal() {
  local name="$1"; shift
  local output status=0
  output="$(TERMUX_VERSION= PREFIX="$FAKE_PREFIX" bash "$@" 2>&1)" || status=$?
  if [[ "$status" -ne 2 || "$output" != *'solo se puede usar desde Termux'* ]]; then
    printf 'FAIL: %s did not refuse safely (status=%s)\n%s\n' "$name" "$status" "$output" >&2
    exit 1
  fi
}

expect_termux_refusal 'installer check' "$SCRIPTS/install.sh" --check
expect_termux_refusal 'installer install' "$SCRIPTS/install.sh" --install
expect_termux_refusal 'doctor' "$SCRIPTS/doctor.sh"
expect_termux_refusal 'start' "$SCRIPTS/start.sh"
expect_termux_refusal 'stop' "$SCRIPTS/stop.sh"
expect_termux_refusal 'browser handoff' "$SCRIPTS/browser.sh" https://example.org
expect_termux_refusal 'mobile profile' "$SCRIPTS/mobile-profile.sh" --apply
[[ ! -e "$PKG_CALL_LOG" ]]
[[ ! -e "$FAKE_PREFIX/var/run/minios-native-xfce" ]]
printf 'PASS: all commands reject non-Termux before package, session, or profile changes\n'

# Check/status/doctor modes are read-only and leave the fake package log untouched.
TERMUX_VERSION=mock PREFIX="$FAKE_PREFIX" bash "$SCRIPTS/install.sh" --check >/dev/null
TERMUX_VERSION=mock PREFIX="$FAKE_PREFIX" bash "$SCRIPTS/mobile-profile.sh" --status >/dev/null
[[ ! -e "$FAKE_HOME/.config" ]]
for item in termux-x11 xfce4-session xfce4-panel dbus-launch thunar xfce4-terminal; do
  printf '#!/usr/bin/env sh\nexit 0\n' > "$TMP/mock-bin/$item"
  chmod +x "$TMP/mock-bin/$item"
done
TERMUX_VERSION=mock PREFIX="$FAKE_PREFIX" bash "$SCRIPTS/doctor.sh" >/dev/null
[[ ! -e "$PKG_CALL_LOG" ]]
printf 'PASS: check/status/doctor modes are read-only and never call pkg\n'

# Installation cancellation must never call even the fake pkg executable.
output="$(printf 'n\n' | TERMUX_VERSION=mock PREFIX="$FAKE_PREFIX" bash "$SCRIPTS/install.sh" --install 2>&1)"
[[ "$output" == *'Cancelado'* ]]
[[ ! -e "$PKG_CALL_LOG" ]]
printf 'PASS: installer cancellation is side-effect free\n'

# Affirmative install exercises only the documented selected package calls.
printf 'y\n' | TERMUX_VERSION=mock PREFIX="$FAKE_PREFIX" bash "$SCRIPTS/install.sh" --install >/dev/null
[[ "$(cat "$PKG_CALL_LOG")" == $'install x11-repo\ninstall termux-x11-nightly xfce' ]]
! grep -Eiq 'upgrade|remove|tur' "$PKG_CALL_LOG"
printf 'PASS: explicit install calls pkg only for x11-repo and selected XFCE packages\n'

# Optional Chromium install is separate, explicit, and never upgrades/removes or adds TUR.
: > "$PKG_CALL_LOG"
output="$(printf 'n\n' | TERMUX_VERSION=mock PREFIX="$FAKE_PREFIX" bash "$SCRIPTS/install.sh" --install-chromium 2>&1)"
[[ "$output" == *'Cancelado'* ]] || { printf 'FAIL: Chromium cancellation prompt did not cancel:\n%s\n' "$output" >&2; exit 1; }
[[ ! -s "$PKG_CALL_LOG" ]] || { printf 'FAIL: pkg called after Chromium cancellation:\n%s\n' "$(cat "$PKG_CALL_LOG")" >&2; exit 1; }
printf 'PASS: optional Chromium cancellation is side-effect free\n'
printf 'y\n' | TERMUX_VERSION=mock PREFIX="$FAKE_PREFIX" bash "$SCRIPTS/install.sh" --install-chromium >/dev/null
[[ "$(cat "$PKG_CALL_LOG")" == $'install x11-repo chromium' ]] || { printf 'FAIL: unexpected Chromium pkg calls:\n%s\n' "$(cat "$PKG_CALL_LOG")" >&2; exit 1; }
if grep -Eiq 'upgrade|remove|tur|host-tools' "$PKG_CALL_LOG"; then
  printf 'FAIL: Chromium installer called a forbidden package action:\n%s\n' "$(cat "$PKG_CALL_LOG")" >&2
  exit 1
fi
printf 'install x11-repo\ninstall termux-x11-nightly xfce\n' > "$PKG_CALL_LOG"
printf 'PASS: Chromium install is optional, confirmed, and limited to official x11-repo package\n'

# Mock the external Android browser handoff; no browser or network is run.
cat > "$TMP/mock-bin/termux-open-url" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$1" >> "$URL_CALL_LOG"
EOF
chmod +x "$TMP/mock-bin/termux-open-url"
export URL_CALL_LOG="$TMP/url-calls.log"
env -u DISPLAY TERMUX_VERSION=mock PREFIX="$FAKE_PREFIX" bash "$SCRIPTS/browser.sh" https://example.org/path >/dev/null
[[ "$(cat "$URL_CALL_LOG")" == 'https://example.org/path' ]]

# In an X11 session, prefer the Termux-native Chromium executable, not Android handoff.
cat > "$TMP/mock-bin/chromium-browser" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >> "$CHROMIUM_CALL_LOG"
EOF
chmod +x "$TMP/mock-bin/chromium-browser"
export CHROMIUM_CALL_LOG="$TMP/chromium-calls.log"
DISPLAY=:1 TERMUX_VERSION=mock PREFIX="$FAKE_PREFIX" bash "$SCRIPTS/browser.sh" https://example.org/native >/dev/null
for _ in {1..50}; do
  [[ -s "$CHROMIUM_CALL_LOG" ]] && break
  sleep 0.1
done
[[ -s "$CHROMIUM_CALL_LOG" ]] || { printf 'FAIL: Chromium launcher did not start the mocked browser within 5 seconds\n' >&2; exit 1; }
[[ "$(cat "$CHROMIUM_CALL_LOG")" == 'https://example.org/native' ]]
[[ "$(cat "$URL_CALL_LOG")" == 'https://example.org/path' ]]

if TERMUX_VERSION=mock PREFIX="$FAKE_PREFIX" bash "$SCRIPTS/browser.sh" 'javascript:alert(1)' >/dev/null 2>&1; then
  printf 'FAIL: browser handoff accepted a non-HTTP(S) URL\n' >&2
  exit 1
fi
printf 'PASS: browser opens Chromium inside X11 and falls back to Android handoff outside X11\n'

# Prepare a pre-existing private profile target to prove backup and restoration.
PANEL="$FAKE_HOME/.config/miniarino-native/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
mkdir -p "$(dirname "$PANEL")"
printf 'pre-existing-profile-setting\n' > "$PANEL"
# Opt-in cancellation leaves that file untouched and installs no profile marker.
output="$(printf 'n\n' | TERMUX_VERSION=mock PREFIX="$FAKE_PREFIX" bash "$SCRIPTS/mobile-profile.sh" --apply 2>&1)"
[[ "$output" == *'Cancelado'* ]]
[[ "$(cat "$PANEL")" == 'pre-existing-profile-setting' ]]
[[ ! -e "$FAKE_HOME/.config/miniarino-native/profile.enabled" ]]

# Apply is confirmed, writes only isolated profile assets, and creates a backup.
output="$(printf 'y\n' | TERMUX_VERSION=mock PREFIX="$FAKE_PREFIX" bash "$SCRIPTS/mobile-profile.sh" --apply 2>&1)"
[[ "$output" == *'Copia de seguridad:'* ]]
[[ "$(cat "$FAKE_HOME/.config/miniarino-native/profile.enabled")" == 'mobile-v1' ]]
grep -Fq 'MiniAriño' "$PANEL"
grep -Fq 'miniarino-browser-handoff.desktop' "$PANEL"
grep -Fq 'Name=MiniAriño — Terminal' "$FAKE_HOME/.local/share/miniarino-native/applications/miniarino-terminal.desktop"
grep -Fq 'termux-open-url' "$FAKE_HOME/.local/share/miniarino-native/bin/miniarino-browser-prompt"
[[ "$(cat "$PKG_CALL_LOG")" == $'install x11-repo\ninstall termux-x11-nightly xfce' ]]
printf 'PASS: confirmed mobile profile is isolated, branded, touch-sized, and backed up\n'

# Restore must refuse to overwrite profile files that changed after activation.
printf '\n# post-apply user edit\n' >> "$PANEL"
output="$(printf 'y\n' | TERMUX_VERSION=mock PREFIX="$FAKE_PREFIX" bash "$SCRIPTS/mobile-profile.sh" --restore 2>&1)" && {
  printf 'FAIL: profile restore should reject a modified managed file\n' >&2
  exit 1
}
[[ "$output" == *'no se sobreescribió'* ]]
grep -Fq 'post-apply user edit' "$PANEL"

backup="$(find "$FAKE_HOME/.local/share/miniarino-native-backups" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[[ -n "$backup" ]]
cp "$backup/generated/config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" "$PANEL"
output="$(printf 'y\n' | TERMUX_VERSION=mock PREFIX="$FAKE_PREFIX" bash "$SCRIPTS/mobile-profile.sh" --restore 2>&1)"
[[ "$output" == *'Perfil revertido'* ]]
[[ "$(cat "$PANEL")" == 'pre-existing-profile-setting' ]]
[[ ! -e "$FAKE_HOME/.config/miniarino-native/profile.enabled" ]]
[[ ! -e "$FAKE_HOME/.local/share/miniarino-native/applications/miniarino-terminal.desktop" ]]
[[ ! -e "$FAKE_HOME/.local/share/miniarino-native/bin/miniarino-browser-prompt" ]]
[[ -d "$backup" ]]
printf 'PASS: restore preserves post-apply edits by refusing conflicts and restores original files\n'
printf 'PASS: host-safe native tests complete; no Android GUI was tested\n'
