#!/bin/bash
# Installs the firewall rules (blocklist + stealth-scan logging) and the
# Block-IP helper for the bar. Run once:  sudo bash install-fw-block.sh
# Undo the helper:  sudo rm /usr/local/sbin/qs-fw-block /etc/sudoers.d/qs-fw-block
set -euo pipefail
here="$(dirname "$(readlink -f "$0")")"
[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }

# 1. Firewall rules (check they parse before touching anything)
nft -c -f "$here/qs-firewall.nft"
install -m 644 "$here/qs-firewall.nft" /etc/qs-firewall.nft
systemctl reload qs-firewall
echo "Firewall rules installed."

# 2. Helper + password-less sudo for it (and only it)
install -m 755 -o root -g root "$here/qs-fw-block" /usr/local/sbin/qs-fw-block
tmp=$(mktemp)
echo "@USER@ ALL=(root) NOPASSWD: /usr/local/sbin/qs-fw-block" > "$tmp"
visudo -cf "$tmp" >/dev/null
install -m 440 -o root -g root "$tmp" /etc/sudoers.d/qs-fw-block
rm -f "$tmp"
echo "Block helper installed."

# 3. Root lock: let the bar block IPs even while someone is connected remotely
for g in /usr/local/sbin/qs-remote-guard @HOME@/.config/qs-firewall/qs-remote-guard; do
    [[ -f $g ]] || continue
    grep -q '/usr/local/sbin/qs-fw-block' "$g" && continue
    sed -i 's|^\(\s*\)/usr/local/sbin/quickshell-fan-curve$|&\n\1/usr/local/sbin/qs-fw-block|' "$g"
done

# Quick self-test: list must work, and garbage must be refused
/usr/local/sbin/qs-fw-block list >/dev/null && echo "list: ok"
/usr/local/sbin/qs-fw-block add '1.2.3.4}; flush ruleset' 5 2>/dev/null && echo "BAD: accepted garbage" || echo "garbage refused: ok"
