import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Reloj central: hora + fecha. Click abre el Dashboard.
// La hora sale del singleton Time; aquí solo se formatea en cada tick.
Pill {
    id: root
    interactive: true
    active: Globals.dashboardOpen
    onClicked: Globals.toggleDashboard()


    Text {
        visible: !Theme.barVertical   // en vertical, solo la hora apilada
        text: "󰅐"
        color: Globals.dashboardOpen ? Theme.accent2 : Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.barIconSize
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
    Text {
        // En la barra vertical la hora se apila (09 / 18 / PM) para caber
        // en el ancho de la píldora.
        readonly property string formatted: Qt.formatDateTime(Time.now, Time.clockFormat)
        text: Theme.barVertical ? formatted.replace(/[:\s]+/g, "\n") : formatted
        horizontalAlignment: Text.AlignHCenter
        lineHeight: 0.9
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
    }
    Rectangle {
        visible: Settings.clockShowDate && !Theme.barVertical
        implicitWidth: Theme.barVertical ? Theme.dp(14) : Theme.hairline
        implicitHeight: Theme.barVertical ? Theme.hairline : Theme.dp(14)
        color: Theme.overlay
    }
    Text {
        visible: Settings.clockShowDate && !Theme.barVertical
        text: Time.dateString   // precalculada en el singleton, una vez al día
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
    }
}
