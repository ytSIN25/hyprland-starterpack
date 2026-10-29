import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Click abre el modal con las contraseñas WiFi guardadas (WifiPasswords).
Pill {
    id: root
    interactive: true
    hoverHighlight: true
    active: WifiPasswords.open
    onClicked: WifiPasswords.open ? WifiPasswords.closePanel() : WifiPasswords.openPanel()

    Text {
        text: "󰤪"   // nf-md-wifi_lock
        color: WifiPasswords.open ? Theme.accent : Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.barIconSize
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
}
