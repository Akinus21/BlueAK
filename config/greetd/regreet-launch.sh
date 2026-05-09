#!/usr/bin/env bash
# /etc/greetd/regreet-launch.sh
# Launch regreet inside weston kiosk compositor

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

exec weston --backend=drm --shell=kiosk --tty=1 -- regreet -c /etc/greetd/regreet.css -s niri