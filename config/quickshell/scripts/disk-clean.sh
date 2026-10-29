#!/usr/bin/env bash
# Limpiador de disco: borra las categorías pedidas (claves de disk-scan.sh).
# Se abre en una terminal (Services/DiskClean.qml) para que sudo pida la
# contraseña y se vea qué se borra. Uso: disk-clean.sh trash aur pacman …
#
# Solo se borra lo que se regenera solo o se vuelve a descargar:
#   trash       ~/.local/share/Trash (lo que ya tiraste; no se puede deshacer)
#   aur         ~/.cache/yay, ~/.cache/paru (fuentes/compilaciones de AUR)
#   pacman      paccache -rk2 (deja 2 versiones de cada paquete para poder
#               volver atrás) + -ruk0 (paquetes ya desinstalados)
#   journal     logs del sistema, se dejan los últimos 100 MiB
#   coredumps   /var/lib/systemd/coredump
#   dev         descargas en caché de pip/go/npm/pnpm/yarn/cargo (no toca
#               virtualenvs, node_modules, el store de pnpm ni ~/go/pkg)
#   thumbnails  ~/.cache/thumbnails
# Si el programa dueño de la caché está en marcha, ese paso se salta.
shopt -s nullglob
C="${XDG_CACHE_HOME:-$HOME/.cache}"
bold=$'\e[1m'; dim=$'\e[2m'; green=$'\e[32m'; yellow=$'\e[33m'; off=$'\e[0m'

free_bytes() { df -B1 --output=avail / | tail -1 | tr -d ' '; }
human() { numfmt --to=iec-i --suffix=B "$1" 2>/dev/null || echo "$1 B"; }
step() { printf '\n%s==> %s%s\n' "$bold" "$1" "$off"; }
# Salta el paso si alguno de esos procesos está corriendo.
busy() {
    local p
    p=$(pgrep -x "$1" | head -1)
    [ -z "$p" ] && return 1
    printf '%sSkipped: %s is running (try again when it finishes).%s\n' "$yellow" "$(ps -o comm= -p "$p")" "$off"
}

before=$(free_bytes)

for key in "$@"; do
    case "$key" in
    trash)
        step "Emptying Trash"
        rm -rf "$HOME/.local/share/Trash/files/"* "$HOME/.local/share/Trash/files/".[!.]* \
               "$HOME/.local/share/Trash/info/"* "$HOME/.local/share/Trash/expunged/"* 2>/dev/null
        ;;
    aur)
        step "Removing AUR build files (yay/paru cache)"
        busy 'yay|paru|makepkg|pacman' && continue
        for d in "$C/yay" "$C/paru"; do
            [ -d "$d" ] || continue
            # makepkg deja carpetas pkg/ sin permiso de escritura: se arreglan antes.
            chmod -R u+w "$d" 2>/dev/null
            rm -rf "${d:?}/"* 2>/dev/null || sudo rm -rf "${d:?}/"*
        done
        ;;
    pacman)
        step "Cleaning pacman cache (keeping the 2 newest versions, dropping uninstalled)"
        busy 'pacman|yay|paru' && continue
        sudo paccache -rk2 && sudo paccache -ruk0
        ;;
    journal)
        step "Trimming system logs to 100M"
        sudo journalctl --vacuum-size=100M
        ;;
    coredumps)
        step "Deleting crash dumps"
        sudo find /var/lib/systemd/coredump -type f -delete
        ;;
    dev)
        step "Clearing developer download caches (pip, go, npm, pnpm, yarn, cargo)"
        busy 'pip|pip3|go|npm|pnpm|yarn|cargo' && continue
        rm -rf "$C/pip" "$C/go-build" "$C/pnpm" "$C/yarn" "$HOME/.npm/_cacache" "$HOME/.cargo/registry/cache"
        ;;
    thumbnails)
        step "Clearing thumbnails"
        rm -rf "$C/thumbnails"
        ;;
    esac
done

after=$(free_bytes)
freed=$(( after - before ))
(( freed < 0 )) && freed=0
printf '\n%s%sFreed %s%s  %s(%s free now)%s\n' "$bold" "$green" "$(human "$freed")" "$off" "$dim" "$(human "$after")" "$off"
qs ipc call disk rescan >/dev/null 2>&1
printf '\n%sPress Enter to close…%s' "$dim" "$off"
read -r _
