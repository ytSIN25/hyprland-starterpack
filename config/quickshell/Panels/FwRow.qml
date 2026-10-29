import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config

// One line in FirewallPanel: colored dot, title + muted subtitle, right-side tag,
// optional text button (actionText → actionClicked()) and optional × button
// (removable) that emits removeClicked().
RowLayout {
    property color dotColor: Theme.accent
    property string title: ""
    property string subtitle: ""
    property string detail: ""          // extra lines under the subtitle (wrapped)
    property string tag: ""
    property color tagColor: Theme.fgDim
    property bool removable: false
    property string actionText: ""
    signal removeClicked()
    signal actionClicked()
    Layout.fillWidth: true
    spacing: Theme.dp(10)

    Rectangle {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: Theme.dp(6)
        implicitWidth: Theme.dp(8); implicitHeight: Theme.dp(8)
        radius: width / 2
        color: parent.dotColor
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.dp(1)
        Text {
            Layout.fillWidth: true
            text: parent.parent.title
            color: Theme.fg
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }
        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: parent.parent.subtitle
            color: Theme.fgMuted
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }
        Text {
            Layout.fillWidth: true
            Layout.topMargin: Theme.dp(3)
            visible: text !== ""
            text: parent.parent.detail
            color: Theme.fg
            wrapMode: Text.Wrap
            lineHeight: 1.15
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }
    }
    Rectangle {
        Layout.alignment: Qt.AlignTop
        visible: parent.tag !== ""
        implicitWidth: tagText.implicitWidth + Theme.dp(14)
        implicitHeight: tagText.implicitHeight + Theme.dp(4)
        radius: height / 2
        color: Theme.withAlpha(parent.tagColor, 0.16)
        Text {
            id: tagText
            anchors.centerIn: parent
            text: parent.parent.tag
            color: parent.parent.tagColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            font.bold: true
        }
    }
    TextButton {
        Layout.alignment: Qt.AlignVCenter
        visible: parent.actionText !== ""
        text: parent.actionText
        implicitHeight: Theme.dp(26)
        onClicked: parent.actionClicked()
    }
    IconButton {
        Layout.alignment: Qt.AlignTop
        visible: parent.removable
        icon: "\u{f0156}"   // close
        diameter: Theme.dp(22)
        iconPixelSize: Theme.fontSize
        baseColor: "transparent"
        hoverColor: Theme.withAlpha(Theme.red, 0.85)
        iconColor: Theme.fgMuted
        onClicked: parent.removeClicked()
    }
}
