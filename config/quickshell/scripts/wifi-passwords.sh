#!/usr/bin/env bash
# Contraseñas WiFi guardadas en NetworkManager (equivalente Linux del
# "netsh wlan show profile key=clear" de Windows). Sin root: NM entrega los
# secretos al usuario de la sesión activa.
#   wifi-passwords.sh          lista numerada, elige una y la muestra
#   wifi-passwords.sh --tsv    nombre<TAB>secreto<TAB>tipo (psk|eap|open), para la barra

set -euo pipefail

list() {
    nmcli -e no -t -f UUID,TYPE connection show | while IFS=: read -r uuid type; do
        [[ $type == 802-11-wireless ]] || continue
        name=$(nmcli -e no -g connection.id connection show "$uuid")
        mgmt=$(nmcli -e no -s -g 802-11-wireless-security.key-mgmt connection show "$uuid" 2>/dev/null || true)
        case $mgmt in
            wpa-eap|wpa-eap-suite-b-192)
                kind=eap
                secret=$(nmcli -e no -s -g 802-1x.password connection show "$uuid" 2>/dev/null || true) ;;
            "")
                kind=open; secret="" ;;
            *)
                kind=psk
                secret=$(nmcli -e no -s -g 802-11-wireless-security.psk connection show "$uuid" 2>/dev/null || true) ;;
        esac
        printf '%s\t%s\t%s\n' "$name" "$secret" "$kind"
    done
}

if [[ ${1:-} == --tsv ]]; then
    list
    exit 0
fi

mapfile -t rows < <(list)
(( ${#rows[@]} )) || { echo "No saved WiFi networks."; exit 1; }

for i in "${!rows[@]}"; do
    IFS=$'\t' read -r name _ _ <<<"${rows[i]}"
    printf '[%d] %s\n' $((i + 1)) "$name"
done

read -rp $'\nChoose WiFi number: ' ch
[[ $ch =~ ^[0-9]+$ ]] && (( ch >= 1 && ch <= ${#rows[@]} )) || { echo "Invalid choice."; exit 1; }
IFS=$'\t' read -r name secret kind <<<"${rows[ch - 1]}"
case $kind in
    open) echo -e "\n$name is an open network (no password)." ;;
    *)    echo -e "\nPassword: ${secret:-(not stored)}" ;;
esac
