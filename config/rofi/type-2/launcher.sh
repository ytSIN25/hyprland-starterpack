#!/usr/bin/env bash
# App launcher — theme: quickshell.rasi (colors follow the wallpaper theme).
# Old adi1090x launcher: launcher.sh.pre-rice

dir="$HOME/.config/rofi/type-2"
theme='quickshell'

# Small cached preview of the current wallpaper for the left panel
# (scaling a 4K image on every launch makes rofi open slowly).
wall=$(jq -r '.wallpaperCurrent // empty' "$HOME/.config/quickshell/settings.json" 2>/dev/null)
cache="${XDG_CACHE_HOME:-$HOME/.cache}/rofi-wall"
img=""
# Fondo animado (vídeo): se usa su fotograma (lo genera Quickshell al aplicarlo).
case "${wall,,}" in
    *.mp4|*.webm|*.mkv|*.mov|*.m4v|*.avi)
        frame="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/wallframes/$(printf '%s' "$wall" | sed 's/[^A-Za-z0-9._-]/_/g').jpg"
        [[ -s "$frame" ]] || { mkdir -p "${frame%/*}"; ffmpeg -loglevel error -y -ss 0.5 -i "$wall" -frames:v 1 -q:v 2 "$frame" </dev/null; }
        wall="$frame" ;;
esac
if [[ -f "$wall" ]]; then
    mkdir -p "$cache"
    img="$cache/$(stat -c '%Y' "$wall")-$(basename "${wall%.*}").png"
    [[ -f "$img" ]] || vipsthumbnail "$wall" --size x900 -o "$img" 2>/dev/null || img="$wall"
fi

# Hide apps without an icon (re-checked in the background, so new installs
# are handled from the next launch on). Undo: rofi-hide-iconless --undo
"$HOME/.local/bin/rofi-hide-iconless" &

pkill -x rofi || rofi \
    -show drun \
    -theme "${dir}/${theme}.rasi" \
    ${img:+-theme-str "imagebox { background-image: url(\"$img\", height); }"}
