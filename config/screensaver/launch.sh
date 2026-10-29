#!/bin/bash
# Opens one fullscreen kitty per monitor, each running run.sh
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

# ttfx is optional: without it there is no screensaver, hypridle still locks
command -v ttfx >/dev/null || exit 0

pgrep -f '[s]creensaver.playera' >/dev/null && exit 0

focused=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true).name')

for m in $(hyprctl monitors -j | jq -r '.[].name'); do
  hyprctl dispatch "hl.dsp.focus({ monitor = \"$m\" })" >/dev/null
  setsid kitty --class screensaver.playera --start-as=fullscreen \
    -o font_size=9 -o window_padding_width=0 -o confirm_os_window_close=0 \
    -o background=#000000 -o background_opacity=1.0 -o dynamic_background_opacity=no -o hide_window_decorations=yes \
    "$HOME/.config/screensaver/run.sh" >/dev/null 2>&1 &
  sleep 0.3
done

hyprctl dispatch "hl.dsp.focus({ monitor = \"$focused\" })" >/dev/null
