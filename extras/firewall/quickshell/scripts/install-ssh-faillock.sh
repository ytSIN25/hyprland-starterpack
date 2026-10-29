#!/bin/bash
# Count wrong SSH passwords apart from local ones. Arch's faillock locks the
# account after 3 wrong passwords for 10 min, for EVERYTHING (sudo, su, login),
# so anyone guessing your SSH password could lock you out of sudo on your own
# PC. With this, SSH failures go to /run/faillock-ssh: SSH locks after 5
# tries, but sudo/su/the lock screen keep working.
# Run once:  sudo bash install-ssh-faillock.sh
# Undo:      sudo cp /etc/pam.d/sshd.pre-qs /etc/pam.d/sshd
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }

for m in pam_shells pam_nologin pam_faillock pam_unix pam_permit pam_env; do
    [[ -e /usr/lib/security/$m.so ]] || { echo "Missing $m.so, not touching PAM."; exit 1; }
done

# Tally dir for SSH (in /run, so recreated at every boot)
echo 'd /run/faillock-ssh 0755 root root -' > /etc/tmpfiles.d/qs-faillock-ssh.conf
systemd-tmpfiles --create /etc/tmpfiles.d/qs-faillock-ssh.conf

[[ -e /etc/pam.d/sshd.pre-qs ]] || cp -a /etc/pam.d/sshd /etc/pam.d/sshd.pre-qs
tmp=$(mktemp)
cat > "$tmp" <<'EOF'
#%PAM-1.0
# qs (install-ssh-faillock.sh): same as system-remote-login, but wrong SSH
# passwords are counted in /run/faillock-ssh (lock after 5), so they can't lock you out of
# sudo/su/login on this PC. Original: /etc/pam.d/sshd.pre-qs
auth       required                    pam_shells.so
auth       requisite                   pam_nologin.so
auth       required                    pam_faillock.so      preauth dir=/run/faillock-ssh deny=5
-auth      [success=2 default=ignore]  pam_systemd_home.so
auth       [success=1 default=bad]     pam_unix.so          try_first_pass nullok
auth       [default=die]               pam_faillock.so      authfail dir=/run/faillock-ssh deny=5
auth       optional                    pam_permit.so
auth       required                    pam_env.so
auth       required                    pam_faillock.so      authsucc dir=/run/faillock-ssh

account    include   system-remote-login
password   include   system-remote-login
session    include   system-remote-login
EOF
install -m 644 -o root -g root "$tmp" /etc/pam.d/sshd
rm -f "$tmp"

# Clear the lock that SSH failures already put on local logins
faillock --user "${SUDO_USER:-@USER@}" --reset

echo "Installed. SSH lockouts now: faillock --dir /run/faillock-ssh --user ${SUDO_USER:-@USER@}"
echo "Test: ssh in from the Mac with the right password; it should still work."
