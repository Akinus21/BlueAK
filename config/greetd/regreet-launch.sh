#!/usr/bin/env bash
export XDG_RUNTIME_DIR=/run/user/$(id -u greeter)
mkdir -p "$XDG_RUNTIME_DIR"
weston --backend=drm --shell=kiosk \
    --log=/var/lib/greeter/weston.log &
WESTON_PID=$!
sleep 1
WAYLAND_DISPLAY=wayland-1 regreet -c /etc/greetd/regreet.css -s niri
kill $WESTON_PID