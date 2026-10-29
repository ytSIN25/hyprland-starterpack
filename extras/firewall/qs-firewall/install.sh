#!/bin/bash
# Installs the Quickshell firewall. Run once:  sudo bash install.sh
# Undo:  sudo systemctl disable --now qs-firewall
#        sudo rm /etc/qs-firewall.nft /etc/systemd/system/qs-firewall.service /etc/polkit-1/rules.d/51-qs-firewall.rules
set -euo pipefail
here="$(dirname "$(readlink -f "$0")")"

# Check the rules parse before touching anything
nft -c -f "$here/qs-firewall.nft"

install -m 644 "$here/qs-firewall.nft" /etc/qs-firewall.nft

cat > /etc/systemd/system/qs-firewall.service <<'EOF'
[Unit]
Description=Quickshell firewall (nftables table inet qs_firewall)
Wants=network-pre.target
Before=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/nft -f /etc/qs-firewall.nft
ExecReload=/usr/bin/nft -f /etc/qs-firewall.nft
ExecStop=/usr/bin/nft delete table inet qs_firewall

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/polkit-1/rules.d/51-qs-firewall.rules <<'EOF'
// Let @USER@ turn the Quickshell firewall on/off from the bar without a password.
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        action.lookup("unit") == "qs-firewall.service" &&
        (action.lookup("verb") == "start" || action.lookup("verb") == "stop") &&
        subject.user == "@USER@") {
        return polkit.Result.YES;
    }
});
EOF
chmod 644 /etc/polkit-1/rules.d/51-qs-firewall.rules

systemctl daemon-reload
systemctl enable --now qs-firewall
echo "Firewall installed and on (also starts at boot)."
