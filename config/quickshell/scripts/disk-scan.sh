#!/usr/bin/env bash
# Limpiador de disco (Services/DiskClean.qml): calcula cuánto se puede liberar.
# Sin root. Salida: una línea por categoría "clave<TAB>bytes<TAB>detalle".
# Solo hay categorías que se regeneran solas o son copias descargables:
# borrarlas no rompe nada (ver scripts/disk-clean.sh).
shopt -s nullglob
C="${XDG_CACHE_HOME:-$HOME/.cache}"

dub() { du -sb "$@" 2>/dev/null | awk '{s+=$1} END {print s+0}'; }
# "1.2 GiB" (paccache) → bytes
tobytes() {
    awk -v v="$1" -v u="$2" 'BEGIN {
        m = 1; if (u ~ /^K/) m = 1024; else if (u ~ /^M/) m = 1024^2
        else if (u ~ /^G/) m = 1024^3; else if (u ~ /^T/) m = 1024^4
        printf "%d", v * m }'
}

# Papelera
printf 'trash\t%s\t%s\n' "$(dub "$HOME/.local/share/Trash/files" "$HOME/.local/share/Trash/info")" \
    "$(find "$HOME/.local/share/Trash/files" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)"

# Compilaciones de AUR (yay / paru): fuentes y paquetes ya instalados
printf 'aur\t%s\t\n' "$(dub "$C/yay" "$C/paru")"

# Caché de pacman: versiones antiguas (deja las 2 últimas) + desinstalados
pc=0
if command -v paccache >/dev/null; then
    for args in "-dk2" "-duk0"; do
        line=$(paccache $args 2>/dev/null | grep -o 'disk space saved: [0-9.]* [A-Za-z]*')
        [ -n "$line" ] || continue
        set -- $line
        pc=$((pc + $(tobytes "$4" "$5")))
    done
fi
printf 'pacman\t%s\t\n' "$pc"

# Journal: se deja en 100 MiB
jb=$(journalctl --disk-usage 2>/dev/null | grep -o '[0-9.]*[KMGT]' | head -1)
jbytes=0
[ -n "$jb" ] && jbytes=$(tobytes "${jb%?}" "${jb: -1}")
keep=$((100 * 1024 * 1024))
printf 'journal\t%s\t\n' "$(( jbytes > keep ? jbytes - keep : 0 ))"

# Volcados de fallos
printf 'coredumps\t%s\t\n' "$(dub /var/lib/systemd/coredump)"

# Cachés de descargas de desarrollo (no los entornos ni el store de pnpm)
dev=("$C/pip" "$C/go-build" "$C/pnpm" "$C/yarn" "$HOME/.npm/_cacache" "$HOME/.cargo/registry/cache")
printf 'dev\t%s\t\n' "$(dub "${dev[@]}")"

# Miniaturas de imágenes/vídeos
printf 'thumbnails\t%s\t\n' "$(dub "$C/thumbnails")"
