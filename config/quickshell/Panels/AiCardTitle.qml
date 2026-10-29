import QtQuick
import QtQuick.Layouts
import qs.Config

// Card header for AiUsagePanel: icon slot, title, optional tinted badge.
RowLayout {
    property string text: ""
    property string badge: ""
    property color badgeColor: Theme.accent
    default property alias icon: iconSlot.data
    Layout.fillWidth: true
    spacing: Theme.dp(10)
    Item {
        id: iconSlot
        implicitWidth: Theme.dp(20); implicitHeight: Theme.dp(20)
    }
    Text {
        text: parent.text
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize + 2
        font.bold: true
    }
    Item { Layout.fillWidth: true }
    Rectangle {
        visible: parent.badge !== ""
        implicitWidth: badgeText.implicitWidth + Theme.dp(16)
        implicitHeight: badgeText.implicitHeight + Theme.dp(6)
        radius: height / 2
        color: Theme.withAlpha(parent.badgeColor, 0.18)
        Text {
            id: badgeText
            anchors.centerIn: parent
            text: parent.parent.badge
            color: parent.parent.badgeColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            font.bold: true
        }
    }
}
