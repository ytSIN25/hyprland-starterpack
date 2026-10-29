import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Config
import qs.Services

// Lista de redes WiFi guardadas con su contraseña. Ocultas por defecto
// (el ojo de cada fila o "Show all" las revela); click en la fila copia.
// Mismo patron de modal que PingIpModal.qml.
PanelWindow {
    id: modal

    property var modelData
    screen: modelData
    visible: WifiPasswords.open

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-wifipass"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }

    property bool revealAll: false
    property var revealed: ({})
    property string copiedName: ""
    onVisibleChanged: if (!visible) { revealAll = false; revealed = {}; copiedName = "" }

    function isShown(name) { return revealAll || revealed[name] === true }
    function toggle(name) {
        const r = Object.assign({}, revealed)
        r[name] = !r[name]
        revealed = r
    }

    Timer { id: copiedTimer; interval: 1500; onTriggered: modal.copiedName = "" }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: WifiPasswords.closePanel()
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: modal.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        MouseArea { anchors.fill: parent; onClicked: WifiPasswords.closePanel() }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Theme.panelWidth(screen, 440, 320, 0.9)
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
                    text: "󰤪"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 6
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Saved WiFi passwords")
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }
            }

            Text {
                visible: WifiPasswords.loading || WifiPasswords.entries.length === 0
                text: WifiPasswords.loading ? I18n.tr("Loading…") : I18n.tr("No saved networks")
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, Theme.dp(360))
                clip: true
                spacing: Theme.space4
                boundsBehavior: Flickable.StopAtBounds
                model: WifiPasswords.entries

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool hasSecret: modelData.secret !== ""
                    readonly property bool copied: modal.copiedName === modelData.name

                    width: list.width
                    implicitHeight: Theme.dp(40)
                    radius: Theme.pillRadius
                    color: rowMa.containsMouse && hasSecret ? Theme.surfaceHi : Theme.surface
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: row.hasSecret ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (!row.hasSecret) return
                            WifiPasswords.copy(row.modelData.secret)
                            modal.copiedName = row.modelData.name
                            copiedTimer.restart()
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space12
                        anchors.rightMargin: Theme.space6
                        spacing: Theme.space10

                        Text {
                            text: "[" + (row.index + 1) + "]"
                            color: Theme.accent
                            font.family: Theme.monoFontFamily
                            font.pixelSize: Theme.fontSize - 1
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            text: row.modelData.name
                            elide: Text.ElideRight
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            text: row.copied ? I18n.tr("Copied")
                                : row.modelData.kind === "open" ? I18n.tr("open network")
                                : !row.hasSecret ? I18n.tr("not stored")
                                : modal.isShown(row.modelData.name) ? row.modelData.secret
                                : "••••••••"
                            color: row.copied ? Theme.green : row.hasSecret ? Theme.fgDim : Theme.fgMuted
                            font.family: Theme.monoFontFamily
                            font.pixelSize: Theme.fontSize - 1
                        }
                        IconButton {
                            visible: row.hasSecret
                            diameter: Theme.dp(28)
                            iconPixelSize: Theme.iconSize - 2
                            baseColor: "transparent"
                            icon: modal.isShown(row.modelData.name) ? "󰈉" : "󰈈"
                            onClicked: modal.toggle(row.modelData.name)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space2
                spacing: Theme.space8

                TextButton {
                    text: modal.revealAll ? I18n.tr("Hide all") : I18n.tr("Show all")
                    enabled: WifiPasswords.entries.length > 0
                    onClicked: modal.revealAll = !modal.revealAll
                }
                Item { Layout.fillWidth: true }
                TextButton {
                    text: I18n.tr("Close")
                    primary: true
                    onClicked: WifiPasswords.closePanel()
                }
            }
        }
    }
}
