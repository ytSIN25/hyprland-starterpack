#!/bin/sh
# Muestra/oculta Duolingo (ventana --app de Chromium en special:duolingo).
# Si no está abierta la lanza; la regla de Hyprland la coloca bajo la barra.
cls='chrome-www.duolingo.com__learn-Default'
if ! hyprctl clients -j | grep -q "\"class\": \"$cls\""; then
    chromium --app=https://www.duolingo.com/learn \
        --user-data-dir="$HOME/.local/share/duolingo-panel" >/dev/null 2>&1 &
    for _ in $(seq 50); do
        hyprctl clients -j | grep -q "\"class\": \"$cls\"" && break
        sleep 0.2
    done
fi
hyprctl dispatch 'hl.dsp.workspace.toggle_special("duolingo")' >/dev/null
