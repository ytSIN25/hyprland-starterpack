#!/bin/bash
# Root lock: nobody can become root while someone is connected over SSH/VNC.
#
# Run from a ROOT shell and keep it open until you've tested:
#     sudo -i
#     bash @HOME@/.config/qs-firewall/install-rootlock.sh
#   then, in a NEW terminal:  sudo true   -> must still work (nobody connected)
#   If it doesn't, undo from the root shell:
#     bash @HOME@/.config/qs-firewall/uninstall-rootlock.sh
set -euo pipefail
here="$(dirname "$(readlink -f "$0")")"
[[ $EUID -eq 0 ]] || { echo "Run as root (sudo -i first)."; exit 1; }

install -m 755 -o root -g root "$here/qs-remote-guard" /usr/local/sbin/qs-remote-guard

# 1. Watcher that tells polkit whether someone is connected
cat > /etc/systemd/system/qs-remote-watch.service <<'EOF'
[Unit]
Description=Root lock: track remote (SSH/VNC) connections for polkit

[Service]
ExecStart=/usr/local/sbin/qs-remote-guard --watch
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now qs-remote-watch
sleep 2
[[ $(cat /run/qs-remote/state) == clear ]] || echo "Note: a remote connection is active right now, so root is locked."

# 2. sudo / su / su-l: check before asking for a password (auth) and on every
#    use, including cached passwords and password-less rules (account)
for f in sudo su su-l; do
    p=/etc/pam.d/$f
    [[ -f $p ]] || continue
    grep -q qs-remote-guard "$p" && continue
    cp -a "$p" "$p.pre-rootlock"
    sed -i '0,/^\(auth\|account\)/s||auth       requisite  pam_exec.so quiet stdout /usr/local/sbin/qs-remote-guard\naccount    requisite  pam_exec.so quiet /usr/local/sbin/qs-remote-guard\n&|' "$p"
done

# 3. polkit (pkexec, run0, systemctl, ...)
install -m 644 "$here/00-qs-remote-lock.rules" /etc/polkit-1/rules.d/00-qs-remote-lock.rules

# 4. SSH hardening: no root login, only @USER@, no forwarding
install -m 644 "$here/10-qs-hardening.conf" /etc/ssh/sshd_config.d/10-qs-hardening.conf
if sshd -t; then
    systemctl is-active -q sshd && systemctl reload sshd
else
    echo "sshd config check failed, leaving SSH hardening out"
    rm /etc/ssh/sshd_config.d/10-qs-hardening.conf
fi

echo
echo "Root lock installed. Keep this root shell open and run 'sudo true' in a new terminal."
