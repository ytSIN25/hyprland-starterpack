import QtQuick
import qs.Config

// Botón de glifo del notch (controles del reproductor y del timer).
Text {
    id: btn
    property bool enabled_: true
    signal activated()
    color: ma.containsMouse && enabled_ ? Theme.accent : "white"
    opacity: enabled_ ? 1 : 0.4
    font.family: Theme.fontFamily
    font.pixelSize: Theme.barIconSize
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    MouseArea {
        id: ma
        anchors.fill: parent
        anchors.margins: -Theme.dp(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (btn.enabled_) btn.activated()
    }
}
