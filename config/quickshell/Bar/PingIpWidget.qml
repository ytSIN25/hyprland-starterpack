import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Click abre el modal para fijar/cambiar la IP a monitorizar (PingMonitor).
// Sin IP fijada: gris, solo el icono. Con IP: icono + IP + "Online"/"Offline"
// en verde/rojo -- pero solo tras el primer resultado real de ping, para no
// arrancar en rojo antes de haber comprobado nada.
Pill {
    id: root
    interactive: true
    onClicked: PingMonitor.openPrompt()

    Text {
        text: ""
        color: PingMonitor.targetIp === "" ? Theme.fgMuted
             : !PingMonitor.hasResult ? Theme.fgDim
             : PingMonitor.online ? Theme.green : Theme.red
        font.family: Theme.fontFamily
        font.pixelSize: Theme.barIconSize
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    Text {
        visible: PingMonitor.targetIp !== ""
        text: PingMonitor.targetIp
        color: Theme.fgDim
        font.family: Theme.monoFontFamily
        font.pixelSize: Theme.fontSize - 2
    }

    Text {
        visible: PingMonitor.targetIp !== "" && PingMonitor.hasResult
        text: PingMonitor.online ? I18n.tr("Online") : I18n.tr("Offline")
        color: PingMonitor.online ? Theme.green : Theme.red
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
        font.bold: true
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
}
