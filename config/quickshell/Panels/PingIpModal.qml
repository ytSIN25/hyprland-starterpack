import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Config
import qs.Services

// Modal minimo: un campo para la IP a monitorizar (PingMonitor). Mismo
// patron que IpSettingsModal.qml, solo que con un unico campo.
PanelWindow {
    id: modal

    property var modelData
    screen: modelData
    visible: PingMonitor.open

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-pingip"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }

    property string draft: ""
    Component.onCompleted: if (visible) _init()
    onVisibleChanged: if (visible) _init()
    function _init() {
        draft = PingMonitor.targetIp
        ipField.forceFocus()
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: modal.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        MouseArea { anchors.fill: parent; onClicked: PingMonitor.closePrompt() }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Theme.panelWidth(screen, 340, 300, 0.88)
        height: content.implicitHeight + Theme.space18 * 2
        radius: Theme.barRadius + Theme.space2
        color: Theme.bgAlt
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.5)

        opacity: modal.visible ? 1 : 0
        scale: modal.visible ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.space18 }
            spacing: Theme.space12

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space10
                Text {
                    text: ""   // nf-fa-server
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 6
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Monitor a host")
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }
            }

            TextField {
                id: ipField
                Layout.fillWidth: true
                label: I18n.tr("IP address")
                placeholder: "10.10.123.45"
                value: modal.draft
                invalid: modal.draft !== "" && !NetConfig.validIp(modal.draft)
                onEdited: (t) => modal.draft = t
                onAccepted: if (!invalid && modal.draft !== "") PingMonitor.setIp(modal.draft)
                onCanceled: PingMonitor.closePrompt()
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space2
                spacing: Theme.space8

                TextButton {
                    visible: PingMonitor.targetIp !== ""
                    text: I18n.tr("Stop monitoring")
                    onClicked: { PingMonitor.clear(); PingMonitor.closePrompt() }
                }
                Item { Layout.fillWidth: true }
                TextButton {
                    text: I18n.tr("Cancel")
                    onClicked: PingMonitor.closePrompt()
                }
                TextButton {
                    text: I18n.tr("Save")
                    primary: true
                    enabled: modal.draft !== "" && NetConfig.validIp(modal.draft)
                    onClicked: PingMonitor.setIp(modal.draft)
                }
            }
        }
    }
}
