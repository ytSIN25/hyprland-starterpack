#!/bin/bash
# One-time root setup for the battery panel: Performance power profile + fan curve.
# Run AFTER installing LenovoLegionLinux from the AUR (see the yay command).
set -euo pipefail

USER_NAME="@USER@"
HELPER_SRC="/home/$USER_NAME/.config/quickshell/scripts/quickshell-fan-curve"

# 1. power-profiles-daemon: lets the bar see and switch to Performance.
pacman -S --needed --noconfirm power-profiles-daemon python-yaml
systemctl enable --now power-profiles-daemon

# 2. Fan curve helper, root-owned so the sudoers rule below can't be abused.
install -m 755 -o root -g root "$HELPER_SRC" /usr/local/sbin/quickshell-fan-curve

# 3. Let the panel read/apply the curve without a password prompt.
TMP=$(mktemp)
echo "$USER_NAME ALL=(root) NOPASSWD: /usr/local/sbin/quickshell-fan-curve" > "$TMP"
visudo -cf "$TMP"
install -m 440 -o root -g root "$TMP" /etc/sudoers.d/quickshell-fan-curve
rm -f "$TMP"

# 4. Re-apply the saved fan curve at boot and after sleep (the controller forgets it).
install -m 644 -o root -g root "/home/$USER_NAME/.config/quickshell/scripts/quickshell-fan-curve.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable quickshell-fan-curve.service

# 5. Load the Legion driver now (it loads automatically on later boots).
modprobe legion_laptop || echo "WARNING: legion_laptop module did not load — check: sudo dmesg | grep -i legion"

echo "Done. Reopen the battery panel."
