#!/usr/bin/env bash
# /etc/greetd/start-greeter.sh
# Detects display resolution via sysfs (before Wayland starts) and sets
# GDK scaling dynamically so gtkgreet looks correct on any display.
#
# Scale logic:
#   >= 1800px vertical  →  2x HiDPI  (Surface Pro, 4K, QHD+)
#   >= 1200px vertical  →  1.5x      (1440p, 2560x1600)
#   anything else       →  1x        (1080p and below)

# Read vertical resolution from the first connected DRM output
VRES=$(cat /sys/class/drm/*/modes 2>/dev/null | head -1 | cut -dx -f2 | tr -d '[:space:]')

if [[ -n "$VRES" ]] && [[ "$VRES" -ge 1800 ]]; then
    export GDK_SCALE=2
    export GDK_DPI_SCALE=0.5
elif [[ -n "$VRES" ]] && [[ "$VRES" -ge 1200 ]]; then
    export GDK_SCALE=2
    export GDK_DPI_SCALE=0.75
else
    export GDK_SCALE=1
    export GDK_DPI_SCALE=1
fi

exec cage -s -- gtkgreet -l -s /etc/greetd/gtkgreet.css -c niri-session
