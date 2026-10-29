#!/bin/bash
# One-time root setup for Wazuh (Docker, single-node) + the Quickshell bar toggle.
set -euo pipefail

USER_NAME="playera"
PROJECT_DIR="/home/$USER_NAME/Security/wazuh-docker/single-node"
HELPER_SRC="/home/$USER_NAME/.config/quickshell/scripts/quickshell-wazuh"

# 1. Docker. Not enabled at boot on purpose: the bar button starts it on demand,
#    so Wazuh (~4-6 GB RAM) only runs when you switch it on.
pacman -S --needed --noconfirm docker docker-compose
systemctl start docker

# 2. TLS certificates for the indexer/dashboard/manager (first run only).
cd "$PROJECT_DIR"
if [ ! -d config/wazuh_indexer_ssl_certs ] || [ -z "$(ls -A config/wazuh_indexer_ssl_certs 2>/dev/null)" ]; then
    docker compose -f generate-indexer-certs.yml run --rm generator
fi

# 3. Download the images (a few GB) and start the stack.
docker compose pull
docker compose up -d

# 4. Bar toggle helper + a sudoers rule limited to its two commands.
install -o root -g root -m 755 "$HELPER_SRC" /usr/local/bin/quickshell-wazuh
TMP=$(mktemp)
echo "$USER_NAME ALL=(root) NOPASSWD: /usr/local/bin/quickshell-wazuh status, /usr/local/bin/quickshell-wazuh toggle" > "$TMP"
visudo -cf "$TMP"
install -m 440 -o root -g root "$TMP" /etc/sudoers.d/quickshell-wazuh
rm -f "$TMP"

echo
echo "Done. Wazuh is starting (the dashboard takes 1-2 minutes)."
echo "Dashboard: https://localhost   user: admin   password: SecretPassword"
