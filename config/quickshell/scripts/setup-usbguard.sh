#!/usr/bin/env bash
# Instala y configura USBGuard para la isla de Quickshell (Services/UsbGuard.qml).
# Ejecutar UNA vez:  sudo ~/.config/quickshell/scripts/setup-usbguard.sh
#  - Permite todo lo que está conectado AHORA (teclado, cámara, BT internos…)
#    y los hubs; cualquier USB nuevo queda bloqueado hasta que lo permitas.
#  - Deja a tu usuario usar `usbguard` sin sudo (para los botones de la isla).
# Deshacer:  sudo systemctl disable --now usbguard   (todo vuelve a funcionar)
set -euo pipefail
[ "$EUID" -eq 0 ] || exec sudo "$0" "$@"
user="${SUDO_USER:-$(logname 2>/dev/null || echo @USER@)}"

pacman -S --needed --noconfirm usbguard

rules=/etc/usbguard/rules.conf
if [ ! -s "$rules" ]; then
    echo "==> Allowing the USB devices connected right now"
    {
        echo "# Generado por setup-usbguard.sh ($(date -I)). Hubs siempre permitidos."
        echo 'allow with-interface equals { 09:00:* }'
        usbguard generate-policy
    } > "$rules"
    chmod 600 "$rules"
else
    echo "==> Keeping existing $rules"
fi

conf=/etc/usbguard/usbguard-daemon.conf
cp -n "$conf" "$conf.orig" || true
set_opt() {
    if grep -q "^$1=" "$conf"; then sed -i "s|^$1=.*|$1=$2|" "$conf"
    else echo "$1=$2" >> "$conf"; fi
}
set_opt ImplicitPolicyTarget block
set_opt PresentDevicePolicy apply-policy
set_opt PresentControllerPolicy keep
set_opt InsertedDevicePolicy apply-policy
set_opt IPCAllowedUsers "root $user"
# Permisos IPC del usuario: ver y permitir dispositivos, y escuchar eventos.
usbguard add-user "$user" --devices modify,list,listen --policy list,modify --exceptions listen || true

systemctl enable --now usbguard.service
systemctl restart usbguard.service
echo
echo "==> USBGuard is on. Allowed devices:"
usbguard list-devices --allowed | sed 's/ hash .*//' | head -30
echo
echo "New USB devices will now ask in the dynamic island."
