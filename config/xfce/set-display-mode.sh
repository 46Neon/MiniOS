#!/bin/sh
# Try the required first-test mode; keep the desktop usable if the virtual VGA
# backend does not advertise it.
xrandr -s 640x480 >/dev/null 2>&1 || true
exit 0
