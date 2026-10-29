#!/usr/bin/env bash
# One-time install of the "launcher" SDDM theme. Run: sudo ~/.config/sddm-launcher/install.sh
# After this, Super+Shift+W (sddm-theme-picker) changes the wallpaper without sudo.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
user="${SUDO_USER:?run via sudo from your user}"
src="$(dirname "$(readlink -f "$0")")/theme"
dst=/usr/share/sddm/themes/launcher

install -d -m 755 "$dst"
install -m 644 "$src"/{Main.qml,Pill.qml,RoundedImage.qml,metadata.desktop,theme.conf} "$dst"/
# Files the picker rewrites: owned by you, world-readable for the sddm user
for f in background.jpg theme.conf.user; do
    [[ -e "$dst/$f" ]] || { [[ -e "$src/$f" ]] && cp "$src/$f" "$dst/$f" || : > "$dst/$f"; }
    chown "$user": "$dst/$f"; chmod 644 "$dst/$f"
done

install -d -m 755 /etc/sddm.conf.d
printf '[Theme]\nCurrent=launcher\n' > /etc/sddm.conf.d/theme.conf
echo "Installed to $dst and set as the SDDM theme."
