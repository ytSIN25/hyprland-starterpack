#!/bin/bash
# Removes the root lock (run as root).
set -u
for f in sudo su su-l; do
    p=/etc/pam.d/$f
    [[ -f $p.pre-rootlock ]] && mv -f "$p.pre-rootlock" "$p"
    [[ -f $p ]] && sed -i '/qs-remote-guard/d' "$p"
done
rm -f /etc/polkit-1/rules.d/00-qs-remote-lock.rules
systemctl disable --now qs-remote-watch 2>/dev/null
rm -f /etc/systemd/system/qs-remote-watch.service /usr/local/sbin/qs-remote-guard
rm -rf /run/qs-remote
systemctl daemon-reload
if [[ -f /etc/ssh/sshd_config.d/10-qs-hardening.conf ]]; then
    rm -f /etc/ssh/sshd_config.d/10-qs-hardening.conf
    systemctl is-active -q sshd && systemctl reload sshd
fi
echo "Root lock removed."
