import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Limpiador de disco: uso de / + categorías con lo que se liberaría. Se
// marcan las que se quieren borrar y "Clean" abre la terminal (sudo).
Popout {
    id: panel
    ns: "qs-diskclean"
    cardWidth: 440
    cardMinWidth: 340
    scrollable: true
    shown: Globals.openPanel === "disk"

    onShownChanged: if (shown) DiskClean.scan()

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space8

        Text {
            Layout.fillWidth: true
            text: I18n.tr("Disk cleaner")
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
            font.bold: true
        }
        Text {
            id: scanSpinner
            visible: DiskClean.scanning
            text: "󰑮"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            RotationAnimation on rotation {
                from: 0; to: 360
                duration: 1000
                loops: Animation.Infinite
                running: scanSpinner.visible
            }
        }
        IconButton {
            icon: "󰑐"
            iconColor: Theme.fgMuted
            hoverIconColor: Theme.accent
            hoverColor: Theme.withAlpha(Theme.accent, 0.16)
            enabled: !DiskClean.scanning
            onClicked: DiskClean.scan()
        }
    }

    // Uso del disco
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.space4
        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: I18n.tr("%1 free of %2").arg(DiskClean.human(DiskClean.diskFree)).arg(DiskClean.human(DiskClean.diskTotal))
                color: DiskClean.lowSpace ? Theme.red : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
            Text {
                text: Math.round(DiskClean.diskUsedFrac * 100) + "%"
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.dp(6)
            radius: height / 2
            color: Theme.surface
            Rectangle {
                width: parent.width * DiskClean.diskUsedFrac
                height: parent.height
                radius: parent.radius
                color: DiskClean.lowSpace ? Theme.red : Theme.accent
                Behavior on width { NumberAnimation { duration: Theme.animNormal } }
            }
            // Lo que se liberaría con la selección actual.
            Rectangle {
                x: parent.width * DiskClean.diskUsedFrac - width
                width: DiskClean.diskTotal > 0
                       ? Math.min(parent.width * DiskClean.diskUsedFrac, parent.width * DiskClean.selectedBytes / DiskClean.diskTotal) : 0
                height: parent.height
                radius: parent.radius
                color: Theme.green
                opacity: 0.85
                Behavior on width { NumberAnimation { duration: Theme.animNormal } }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: !DiskClean.scannedOnce
        text: I18n.tr("Scanning…")
        color: Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.space4

        Repeater {
            model: DiskClean.items
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool sel: DiskClean.isSelected(modelData.key)
                readonly property bool empty: modelData.bytes === 0
                Layout.fillWidth: true
                implicitHeight: Theme.dp(50)
                radius: Theme.pillRadius
                color: rowMa.containsMouse && !empty ? Theme.surfaceHi : Theme.surface
                border.width: Theme.hairline
                border.color: sel && !empty ? Theme.withAlpha(Theme.accent, 0.5) : Theme.withAlpha(Theme.overlay, 0.28)
                opacity: empty ? 0.55 : 1
                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: row.empty ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: if (!row.empty) DiskClean.toggle(row.modelData.key)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space10
                    anchors.rightMargin: Theme.space10
                    spacing: Theme.space10

                    // Casilla
                    Rectangle {
                        implicitWidth: Theme.dp(18); implicitHeight: Theme.dp(18)
                        radius: Theme.dp(5)
                        color: row.sel && !row.empty ? Theme.accent : "transparent"
                        border.width: Math.max(1, Theme.hairline)
                        border.color: row.sel && !row.empty ? Theme.accent : Theme.withAlpha(Theme.overlay, 0.6)
                        Text {
                            anchors.centerIn: parent
                            visible: row.sel && !row.empty
                            text: "󰄬"
                            color: Theme.bg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                    Text {
                        text: row.modelData.icon
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        RowLayout {
                            spacing: Theme.space6
                            Text {
                                text: row.modelData.title
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                            }
                            // Pide contraseña (sudo)
                            Text {
                                visible: row.modelData.root
                                text: "󰌾"
                                color: Theme.fgMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.desc + (row.modelData.count > 0 ? " · " + row.modelData.count : "")
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                            elide: Text.ElideRight
                        }
                    }
                    Text {
                        text: row.empty ? "—" : DiskClean.human(row.modelData.bytes)
                        color: row.modelData.bytes > 1024 * 1024 * 1024 ? Theme.yellow : Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: row.modelData.bytes > 1024 * 1024 * 1024
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space8
        Text {
            Layout.fillWidth: true
            text: "󰌾 " + I18n.tr("asks for your password")
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
        }
        TextButton {
            text: DiskClean.selectedBytes > 0
                  ? I18n.tr("Clean %1").arg(DiskClean.human(DiskClean.selectedBytes))
                  : I18n.tr("Clean")
            primary: true
            enabled: !DiskClean.cleaning && DiskClean.items.some(i => DiskClean.isSelected(i.key) && i.bytes !== 0)
            onClicked: DiskClean.cleanSelected()
        }
    }
}
