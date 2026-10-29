import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Logs: cómo acabó cada sesión (normal / botón de encendido / cuelgue) y qué
// falló en ella. Pulsar una sesión despliega sus fallos y los últimos
// mensajes antes de que terminara, con botones para abrir el log completo.
Popout {
    id: panel
    ns: "qs-logs"
    cardWidth: 520
    cardMinWidth: 380
    scrollable: true
    shown: Globals.openPanel === "logs"

    property int openIndex: -1          // sesión desplegada (índice de boot)

    onShownChanged: {
        if (!shown) return
        CrashLog.refresh()
        CrashLog.ack()
        // Se despliega sola la última sesión rara.
        const b = CrashLog.boots.find(x => x.status === "power" || x.status === "crash")
        openIndex = b ? b.index : -1
    }

    function statusLabel(s) {
        return ({ running: I18n.tr("Running now"), clean: I18n.tr("Shut down normally"),
                  power: I18n.tr("Forced off with power button"),
                  crash: I18n.tr("Ended suddenly (freeze, crash or power loss)") })[s] ?? s
    }
    function statusColor(s) {
        return ({ running: Theme.accent, clean: Theme.green, power: Theme.yellow, crash: Theme.red })[s] ?? Theme.fgMuted
    }
    function kindIcon(k) {
        return ({ app: "󰚌", oom: "󰍛", kernel: "󰻠" })[k] ?? "󰀦"
    }
    function fmtRange(b) {
        const s = new Date(b.start), e = new Date(b.end)
        const day = Qt.formatDate(s, "ddd d MMM")
        const tf = Settings.clock24h ? "HH:mm" : "h:mm AP"
        return day + " · " + Qt.formatTime(s, tf) + " – " + Qt.formatTime(e, tf)
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space8
        Text {
            Layout.fillWidth: true
            text: I18n.tr("System logs")
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
            font.bold: true
        }
        Text {
            id: logSpinner
            visible: CrashLog.loading
            text: "󰑮"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            RotationAnimation on rotation {
                from: 0; to: 360
                duration: 1000
                loops: Animation.Infinite
                running: logSpinner.visible
            }
        }
        IconButton {
            icon: "󰑐"
            iconColor: Theme.fgMuted
            hoverIconColor: Theme.accent
            hoverColor: Theme.withAlpha(Theme.accent, 0.16)
            onClicked: CrashLog.refresh()
        }
    }

    Text {
        Layout.fillWidth: true
        text: I18n.tr("Each session since boot. Click one to see what went wrong.")
        color: Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
        wrapMode: Text.Wrap
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.space4

        Repeater {
            model: CrashLog.boots
            delegate: Rectangle {
                id: bootRow
                required property var modelData
                readonly property bool open: panel.openIndex === modelData.index
                readonly property color sc: panel.statusColor(modelData.status)
                Layout.fillWidth: true
                implicitHeight: bootCol.implicitHeight + Theme.space8 * 2
                radius: Theme.pillRadius
                color: headMa.containsMouse && !open ? Theme.surfaceHi : Theme.surface
                border.width: Theme.hairline
                border.color: open ? Theme.withAlpha(sc, 0.55) : Theme.withAlpha(Theme.overlay, 0.28)
                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                ColumnLayout {
                    id: bootCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.space8
                    anchors.leftMargin: Theme.space10
                    anchors.rightMargin: Theme.space10
                    spacing: Theme.space6

                    // Cabecera de la sesión
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: headRow.implicitHeight
                        MouseArea {
                            id: headMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.openIndex = bootRow.open ? -1 : bootRow.modelData.index
                        }
                        RowLayout {
                            id: headRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: Theme.space10
                            Rectangle {
                                implicitWidth: Theme.dp(9); implicitHeight: Theme.dp(9)
                                radius: width / 2
                                color: bootRow.sc
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: panel.fmtRange(bootRow.modelData)
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: panel.statusLabel(bootRow.modelData.status)
                                    color: bootRow.modelData.status === "clean" ? Theme.fgMuted : bootRow.sc
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                    elide: Text.ElideRight
                                }
                            }
                            // Nº de fallos
                            Rectangle {
                                visible: bootRow.modelData.events.length > 0
                                implicitWidth: evCount.implicitWidth + Theme.space10
                                implicitHeight: Theme.dp(18)
                                radius: height / 2
                                color: Theme.withAlpha(Theme.red, 0.18)
                                Text {
                                    id: evCount
                                    anchors.centerIn: parent
                                    text: "󰀦 " + bootRow.modelData.events.length
                                    color: Theme.red
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                    font.bold: true
                                }
                            }
                            Text {
                                text: bootRow.open ? "󰅀" : "󰅂"
                                color: Theme.fgMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.iconSize
                            }
                        }
                    }

                    // Detalle
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: bootRow.open
                        spacing: Theme.space6

                        Text {
                            Layout.fillWidth: true
                            visible: bootRow.modelData.events.length === 0
                            text: I18n.tr("No crashes, memory kills or driver errors in this session.")
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            wrapMode: Text.Wrap
                        }
                        Repeater {
                            model: bootRow.modelData.events
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Theme.space8
                                Text {
                                    text: panel.kindIcon(modelData.kind)
                                    color: modelData.kind === "app" ? Theme.yellow : Theme.red
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                }
                                Text {
                                    text: Qt.formatTime(new Date(modelData.t), Settings.clock24h ? "HH:mm" : "h:mm AP")
                                    color: Theme.fgMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.text
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

                        // Últimos mensajes antes de que acabara
                        Text {
                            visible: bootRow.modelData.tail.length > 0
                            Layout.topMargin: Theme.space4
                            text: I18n.tr("Last messages before it ended")
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: true
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            visible: bootRow.modelData.tail.length > 0
                            implicitHeight: tailText.implicitHeight + Theme.space8 * 2
                            radius: Theme.dp(8)
                            color: Theme.withAlpha("black", 0.35)
                            TextEdit {
                                id: tailText
                                anchors.fill: parent
                                anchors.margins: Theme.space8
                                text: bootRow.modelData.tail.map(l => l.replace(/^(\w+ \d+ )/, "").replace(/ archlinux /, " ")).join("\n")
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                                color: Theme.fgDim
                                selectionColor: Theme.withAlpha(Theme.accent, 0.4)
                                font.family: Theme.monoFontFamily || Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 4
                            }
                        }

                        RowLayout {
                            spacing: Theme.space6
                            TextButton {
                                text: I18n.tr("Full log")
                                onClicked: CrashLog.openLog(bootRow.modelData.index, false)
                            }
                            TextButton {
                                text: I18n.tr("Errors only")
                                onClicked: CrashLog.openLog(bootRow.modelData.index, true)
                            }
                        }
                    }
                }
            }
        }
    }
}
