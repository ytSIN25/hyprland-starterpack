import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.Components
import qs.Config

// Batería (UPower). Oculta en equipos sin batería.
Pill {
    id: root

    readonly property var dev: {
        const devices = UPower.devices ?? []
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i]
            if (d && ((d.type === "Battery") || (d.isLaptopBattery ?? false)))
                return d
        }
        return UPower.displayDevice
    }
    readonly property bool present: dev && ((dev.type === "Battery") || (dev.isLaptopBattery ?? false))
    readonly property int percent: Math.max(0, Math.min(100, Math.round((dev?.percentage ?? 0) * 100)))
    readonly property bool charging: (dev?.state ?? 0) === UPowerDeviceState.Charging
                                     || (dev?.state ?? 0) === UPowerDeviceState.PendingCharge

    // Solo en portátiles (con batería) y si está activado en ajustes.
    visible: present && Settings.showBattery

    interactive: true
    active: Globals.batteryOpen
    onClicked: Globals.toggleBattery()

    readonly property color levelColor:
        percent <= 15 ? Theme.red
      : percent <= 35 ? Theme.yellow
      : Theme.green

    GridLayout {
        flow: Theme.barVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: Theme.dp(6)
        rowSpacing: Theme.dp(3)

        // Indicador de nivel: un punto de color, o un rayo si está cargando.
        // Un punto/rectángulo dibujado no depende de que la fuente tenga el
        // glifo — evita el problema del icono en blanco.
        Item {
            Layout.preferredWidth: Theme.dp(8)
            Layout.preferredHeight: Theme.dp(8)
            Layout.alignment: Qt.AlignCenter

            Rectangle {
                anchors.fill: parent
                visible: !root.charging
                radius: width / 2
                color: root.levelColor
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }

            Text {
                anchors.centerIn: parent
                visible: root.charging
                text: "\u26A1" // rayo — símbolo Unicode estándar, no requiere Nerd Font
                color: Theme.cyan
                font.pixelSize: Theme.dp(10)
            }
        }

        Text {
            Layout.alignment: Qt.AlignCenter
            text: root.percent + "%"
            color: root.charging ? Theme.fgDim
                 : root.percent <= 35 ? root.levelColor
                 : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: root.percent <= 15 && !root.charging
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
    }
}
