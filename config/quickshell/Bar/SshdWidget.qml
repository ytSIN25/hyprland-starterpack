import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Toggle del servidor SSH local (sshd). Naranja/accent cuando está
// corriendo, atenuado si no -- mismo lenguaje visual que CaffeineWidget.
Pill {
    id: root
    interactive: true
    onClicked: Sshd.toggle()

    Text {
        text: ""
        color: Sshd.running ? "#de6145" : Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.barIconSize
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    // IP local, solo mientras sshd está activo: es cuando de verdad hace
    // falta para conectarse desde otro equipo de la red.
    Text {
        visible: Sshd.running && Sshd.localIp !== ""
        text: Sshd.localIp
        color: Theme.fgDim
        font.family: Theme.monoFontFamily
        font.pixelSize: Theme.fontSize - 2
    }
}
