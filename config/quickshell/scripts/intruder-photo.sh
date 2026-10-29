#!/usr/bin/env bash
# Foto con la webcam tras varios desbloqueos fallidos (Services/AuthWatch.qml).
# Guarda en ~/Pictures/Intruders/intruder-AAAAMMDD-HHMMSS.jpg e imprime la ruta.
# Se descartan los primeros fotogramas: la cámara tarda en ajustar la exposición.
dir="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Intruders"
mkdir -p "$dir"
out="$dir/intruder-$(date +%Y%m%d-%H%M%S).jpg"
for dev in /dev/video0 /dev/video1 /dev/video2; do
    [ -e "$dev" ] || continue
    for size in "-video_size 1280x720" ""; do
        # shellcheck disable=SC2086
        timeout 8 ffmpeg -loglevel error -y -f v4l2 $size -i "$dev" \
            -vf "select=gte(n\,20)" -frames:v 1 -q:v 3 "$out" </dev/null && [ -s "$out" ] && {
            echo "$out"; exit 0; }
    done
done
exit 1
