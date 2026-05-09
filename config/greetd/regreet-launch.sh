#!/usr/bin/env bash
# /etc/greetd/regreet-launch.sh
# Launch script for regreet (Rust GTK greeter) via weston kiosk shell.
# CSS is synced by Noctalia user-templates and lives at /etc/greetd/regreet.css

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

exec weston --shell=kiosk -- regreet -c /etc/greetd/regreet.css -s niri