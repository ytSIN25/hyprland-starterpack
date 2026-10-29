import QtQuick
import QtQuick.Layouts
import qs.Config

// Título de sección del panel del firewall: punto de estado · TEXTO · valor a la derecha.
RowLayout {
    property alias text: titleText.text
    property color dot: Theme.accent
    property string value: ""
    Layout.fillWidth: true
    spacing: Theme.dp(8)
    Rectangle {
        implicitWidth: Theme.dp(7); implicitHeight: Theme.dp(7)
        radius: width / 2
        color: parent.dot
    }
    Text {
        id: titleText
        Layout.fillWidth: true
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        font.bold: true
        font.letterSpacing: 1.5
    }
    Text {
        text: parent.value
        color: parent.dot
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 3
        font.bold: true
        font.letterSpacing: 1
    }
}
