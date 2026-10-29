# Wazuh toggle for Quickshell

This patch adds a Wazuh logo button immediately to the right of the OpenVPN
button in `Bar.qml`. The logo uses its normal muted/blue-dot appearance when
the Docker Compose stack is off and turns green when the stack is running.
Clicking the button starts/stops the Wazuh Compose stack and the local
`wazuh-agent` service.

## Install the helper (Arch Linux)

The Quickshell service calls a small root-owned helper without an interactive
password prompt. This is needed because Quickshell processes do not have a
terminal for a sudo password prompt.

1. Copy this project’s `scripts/quickshell-wazuh` helper to `/usr/local/bin`:

   ```bash
   sudo install -o root -g root -m 755 \
     ~/.config/quickshell/scripts/quickshell-wazuh \
     /usr/local/bin/quickshell-wazuh
   ```

   If you extracted this archive somewhere else, adjust the source path to the
   extracted `quickshell/scripts/quickshell-wazuh` file.

2. Create a narrow sudoers rule with `visudo`:

   ```bash
   sudo visudo -f /etc/sudoers.d/quickshell-wazuh
   ```

   Add this single line:

   ```sudoers
   @USER@ ALL=(root) NOPASSWD: /usr/local/bin/quickshell-wazuh status, /usr/local/bin/quickshell-wazuh toggle
   ```

3. Validate the rule:

   ```bash
   sudo chmod 0440 /etc/sudoers.d/quickshell-wazuh
   sudo visudo -cf /etc/sudoers.d/quickshell-wazuh
   sudo -n /usr/local/bin/quickshell-wazuh status
   ```

   The last command should print `ON` or `OFF`.

4. Copy the updated Quickshell files into your existing `~/.config/quickshell`
   folder, keeping the directory structure, then reload/restart Quickshell.

## Notes

- The helper is deliberately fixed to `@HOME@/Security/wazuh-docker/single-node`.
  If your project lives elsewhere, edit `PROJECT_DIR` in the helper before
  installing it.
- The button reports the state of the Docker Compose stack. It polls every
  five seconds so changes made from a terminal are reflected in the icon.
- Stopping the stack preserves its containers and data; do not use `docker
  compose down -v` for this toggle.
- The helper starts/stops `wazuh-agent` as well as the server stack.
