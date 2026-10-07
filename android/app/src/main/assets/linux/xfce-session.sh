#!/bin/sh
# Runs inside the app-private Debian ARM64 rootfs under PRoot.
set -eu

export DISPLAY="${DISPLAY:-:0}"
export HOME=/root
export LANG=C.UTF-8
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-runtime}"
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=XFCE
export DESKTOP_SESSION=xfce
mkdir -p "$XDG_RUNTIME_DIR" /root/.cache /root/.config
chmod 700 "$XDG_RUNTIME_DIR"

required_commands="startxfce4 xfce4-session xfce4-terminal thunar dbus-launch dbus-send"
needs_install=0
for command_name in $required_commands; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        needs_install=1
        break
    fi
done
if [ "$needs_install" -eq 1 ] || [ ! -f /root/.miniarino-xfce-packages-ready ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends xfce4 xfce4-terminal thunar dbus-x11
    for command_name in $required_commands; do
        command -v "$command_name" >/dev/null 2>&1 || {
            echo "Required XFCE command is missing after package installation: $command_name" >&2
            exit 20
        }
    done
    touch /root/.miniarino-xfce-packages-ready
fi

# dbus-launch creates a private session bus; wait for XFCE's session-manager name
# rather than treating a still-running PRoot process as proof of a working desktop.
exec dbus-launch --exit-with-session /bin/sh -c '
    set -eu
    startxfce4 >/tmp/miniarino-xfce-session.log 2>&1 &
    session_pid=$!
    attempt=0
    while [ "$attempt" -lt 90 ]; do
        if ! kill -0 "$session_pid" 2>/dev/null; then
            wait "$session_pid" || exit $?
            echo "XFCE session process exited before registering its D-Bus service" >&2
            exit 21
        fi
        if dbus-send --session --dest=org.freedesktop.DBus --type=method_call --print-reply \
            /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null |
            grep -Fq "org.xfce.SessionManager"; then
            break
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    if [ "$attempt" -ge 90 ]; then
        echo "XFCE session manager did not register on the D-Bus session bus" >&2
        cat /tmp/miniarino-xfce-session.log >&2 || true
        exit 22
    fi

    thunar >/tmp/miniarino-thunar.log 2>&1 &
    thunar_pid=$!
    xfce4-terminal --disable-server >/tmp/miniarino-terminal.log 2>&1 &
    terminal_pid=$!
    sleep 2
    if ! kill -0 "$terminal_pid" 2>/dev/null; then
        echo "XFCE terminal did not remain open" >&2
        cat /tmp/miniarino-terminal.log >&2 || true
        exit 23
    fi
    if ! kill -0 "$thunar_pid" 2>/dev/null; then
        echo "Thunar file manager did not remain open" >&2
        cat /tmp/miniarino-thunar.log >&2 || true
        exit 24
    fi
    if ! kill -0 "$session_pid" 2>/dev/null; then
        echo "XFCE session stopped during desktop app startup" >&2
        cat /tmp/miniarino-xfce-session.log >&2 || true
        exit 25
    fi
    echo MINIARINO_XFCE_SESSION_READY
    wait "$session_pid"
'
