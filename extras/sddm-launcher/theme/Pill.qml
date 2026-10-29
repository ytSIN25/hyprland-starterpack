import QtQuick

// The launcher's mode-switcher button: capsule, dim text, accent when active.
Rectangle {
    id: root
    property string text
    property bool active: false
    property real s: 1
    property color cIdle
    property color cActive
    property color cText
    property color cOnActive
    property string fontFamily
    signal clicked()

    implicitHeight: label.implicitHeight + 18 * s
    implicitWidth: label.implicitWidth + 28 * s
    radius: height / 2
    color: active || area.containsMouse ? cActive : cIdle
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        x: 14 * root.s
        text: root.text
        font.family: root.fontFamily
        font.pixelSize: 14 * root.s
        color: root.active || area.containsMouse ? root.cOnActive : root.cText
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
