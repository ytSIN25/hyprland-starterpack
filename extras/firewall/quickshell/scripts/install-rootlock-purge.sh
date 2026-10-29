#!/bin/bash
# Root lock: end root sessions that were opened before the lock engaged.
# Installs the updated qs-remote-guard and restarts its watcher.
# Run once:  sudo bash ~/.config/quickshell/scripts/install-rootlock-purge.sh
# Undo:      sudo install -m 755 ~/.config/qs-firewall/qs-remote-guard.pre-purge /usr/local/sbin/qs-remote-guard
#            sudo install -m 755 ~/.config/quickshell/scripts/qs-rootlock-allow.pre-purge /usr/local/sbin/qs-rootlock-allow
#            sudo systemctl restart qs-remote-watch
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }
guard=@HOME@/.config/qs-firewall/qs-remote-guard
allow=@HOME@/.config/quickshell/scripts/qs-rootlock-allow
bash -n "$guard"
bash -n "$allow"
install -m 755 -o root -g root "$guard" /usr/local/sbin/qs-remote-guard
install -m 755 -o root -g root "$allow" /usr/local/sbin/qs-rootlock-allow
systemctl restart qs-remote-watch
echo "Installed. Root lock now ends sudo/su/pkexec/run0 root sessions while someone is connected."
echo "Test: open 'sudo -i' in another terminal, then click 'End root shells' in the firewall panel"
echo "      (or SSH/VNC in from the Mac): that root shell should close within ~1 s."
