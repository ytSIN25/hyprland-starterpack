#!/bin/bash
# Installs the root-lock "Allow" option: updated qs-remote-guard (honours a
# time-limited unlock) + qs-rootlock-allow helper with password-less sudo.
# Run once:  sudo bash install-rootlock-allow.sh
# Undo:  sudo rm /usr/local/sbin/qs-rootlock-allow /etc/sudoers.d/qs-rootlock-allow /run/qs-remote/allow
#        sudo install -m 755 ~/.config/qs-firewall/qs-remote-guard.pre-allow /usr/local/sbin/qs-remote-guard
set -euo pipefail
here="$(dirname "$(readlink -f "$0")")"
[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }

guard=/home/playera/.config/qs-firewall/qs-remote-guard
bash -n "$guard"
bash -n "$here/qs-rootlock-allow"
install -m 755 -o root -g root "$guard" /usr/local/sbin/qs-remote-guard
install -m 755 -o root -g root "$here/qs-rootlock-allow" /usr/local/sbin/qs-rootlock-allow

tmp=$(mktemp)
echo "playera ALL=(root) NOPASSWD: /usr/local/sbin/qs-rootlock-allow" > "$tmp"
visudo -cf "$tmp" >/dev/null
install -m 440 -o root -g root "$tmp" /etc/sudoers.d/qs-rootlock-allow
rm -f "$tmp"
echo "Installed."

# Self-test: from here (a root shell, not through sudo from the desktop) "allow" must refuse
/usr/local/sbin/qs-rootlock-allow allow 5 </dev/null 2>/dev/null && echo "BAD: unlocked without sudo/password" \
    || echo "refuses outside the desktop: ok"
echo "status: $(/usr/local/sbin/qs-rootlock-allow status) s unlocked"
