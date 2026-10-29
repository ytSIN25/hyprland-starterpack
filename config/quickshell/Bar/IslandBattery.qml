import QtQuick
import qs.Config

// Batería dibujada como la de iOS (dynamic island): cuerpo translúcido +
// relleno + polo, con rayo si está cargando.
Row {
    id: root
    property int pct: 0
    property bool charging: false
    property color tint: "white"
    spacing: Theme.dp(1)

    Rectangle {
        id: body
        width: Theme.dp(26); height: Theme.dp(13)
        radius: Theme.dp(4)
        color: Theme.withAlpha(root.tint, 0.3)
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(body.radius, body.width * Math.min(100, root.pct) / 100)
            radius: body.radius
            color: root.tint
        }
        Text {
            anchors.centerIn: parent
            visible: root.charging
            text: "󱐋"
            color: "black"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.dp(10)
        }
    }
    Rectangle {
        width: Theme.dp(2); height: Theme.dp(5)
        radius: Theme.dp(1)
        color: Theme.withAlpha(root.tint, 0.4)
        anchors.verticalCenter: parent.verticalCenter
    }
}
