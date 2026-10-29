import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Toggle de la VPN de TryHackMe (OpenVPN). Dos imágenes estáticas en vez de
// un glifo o un tinte: el logo a color (naranja/azul oficial) cuando está
// desconectada, y el logo negro (Assets/openvpn-black.svg) cuando está
// conectada. Construido sobre Pill (no IconPill: eso solo acepta glifos).
Pill {
    id: root
    interactive: true
    onClicked: Vpn.toggle()

    Item {
        implicitWidth: Theme.barIconSize + 2
        implicitHeight: Theme.barIconSize + 2

        Image {
            anchors.centerIn: parent
            width: Theme.barIconSize
            height: Theme.barIconSize
            source: "../Assets/openvpn-black.svg"
            sourceSize.width: Theme.barIconSize
            sourceSize.height: Theme.barIconSize
            smooth: true
            visible: Vpn.connected
        }

        Image {
            anchors.centerIn: parent
            width: Theme.barIconSize
            height: Theme.barIconSize
            source: "../Assets/openvpn-color.png"
            sourceSize.width: Theme.barIconSize
            sourceSize.height: Theme.barIconSize
            smooth: true
            visible: !Vpn.connected
        }
    }
}
