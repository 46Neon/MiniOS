#!/bin/sh
# Select the widest practical mode exposed by the virtual VGA adapter.
# Termux:X11/QEMU should be launched in landscape and with zoom-to-fit enabled.
command -v xrandr >/dev/null 2>&1 || exit 0
modes="$(xrandr --query 2>/dev/null || true)"
for mode in 1280x720 1280x800 1024x768 800x600 640x480; do
    if printf '%s\n' "$modes" | grep -Eq "^[[:space:]]*${mode}([[:space:]]|$)"; then
        xrandr -s "$mode" >/dev/null 2>&1 || true
        exit 0
    fi
done
# Preserve the mode chosen by Xorg if QEMU advertises something unexpected.
exit 0
