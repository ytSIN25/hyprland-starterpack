#!/bin/bash
# Starship prompt for root shells ("root" in red, the rest as yours) (bash: sudo su / sudo -i,
# fish: sudo -s). Run once:  sudo bash install-root-prompt.sh
# Undo: sudo rm /etc/starship-root.toml /root/.config/fish/conf.d/qs-root-prompt.fish
#       and delete the "qs root prompt" block from /root/.bashrc
set -euo pipefail
here="$(dirname "$(readlink -f "$0")")"
[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }

STARSHIP_CONFIG="$here/starship-root.toml" starship print-config >/dev/null
install -m 644 -o root -g root "$here/starship-root.toml" /etc/starship-root.toml

# bash (root's login shell)
touch /root/.bashrc
sed -i '/# >>> qs root prompt >>>/,/# <<< qs root prompt <<</d' /root/.bashrc
cat >> /root/.bashrc <<'EOF'
# >>> qs root prompt >>>
if [[ $- == *i* ]] && [[ -x /usr/bin/starship ]]; then
    export STARSHIP_CONFIG=/etc/starship-root.toml
    eval "$(/usr/bin/starship init bash)"
fi
# <<< qs root prompt <<<
EOF
# sudo -i is a login shell: make it read .bashrc too
grep -qs 'bashrc' /root/.bash_profile || echo '[[ -f ~/.bashrc ]] && . ~/.bashrc' >> /root/.bash_profile

# fish (sudo -s keeps your $SHELL)
install -d -m 700 /root/.config /root/.config/fish /root/.config/fish/conf.d
cat > /root/.config/fish/conf.d/qs-root-prompt.fish <<'EOF'
if status is-interactive; and test -x /usr/bin/starship
    set -gx STARSHIP_CONFIG /etc/starship-root.toml
    /usr/bin/starship init fish | source
end
EOF
echo "Installed. Try: sudo su"
