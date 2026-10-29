import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

Popout {
    id: panel
    ns: "qs-updates"
    cardWidth: 420
    cardMinWidth: 340
    scrollable: true
    shown: Globals.updatesOpen

    onShownChanged: if (shown) PackageUpdates.refresh()

    function sourceLabel(s) {
        return s === "aur" ? "AUR" : s === "flatpak" ? "Flatpak" : "Pacman"
    }
    function sourceColor(s) {
        return s === "aur" ? Theme.magenta : s === "flatpak" ? Theme.green : Theme.cyan
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space8

        Text {
            Layout.fillWidth: true
            text: I18n.tr("Updates")
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
            font.bold: true
        }

        Text {
            id: updSpinner
            visible: PackageUpdates.loading
            text: "󰑮"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            RotationAnimation on rotation {
                from: 0; to: 360
                duration: 1000
                loops: Animation.Infinite
                running: updSpinner.visible
            }
        }

        IconButton {
            icon: "󰑐"   // md-refresh
            iconColor: Theme.fgMuted
            hoverIconColor: Theme.accent
            hoverColor: Theme.withAlpha(Theme.accent, 0.16)
            enabled: !PackageUpdates.loading
            onClicked: PackageUpdates.refresh()
        }
    }

    Text {
        Layout.fillWidth: true
        visible: !PackageUpdates.hasCheckupdates
        text: I18n.tr("Install pacman-contrib for repo update checks (pacman -S pacman-contrib).")
        color: Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        wrapMode: Text.WordWrap
    }

    TextButton {
        Layout.fillWidth: false
        text: I18n.tr("Update all (%1)").arg(PackageUpdates.count)
        primary: true
        visible: PackageUpdates.count > 0
        onClicked: PackageUpdates.updateAll()
    }

    Text {
        Layout.fillWidth: true
        visible: PackageUpdates.checkedOnce && !PackageUpdates.loading && PackageUpdates.count === 0
        text: I18n.tr("Everything is up to date")
        color: Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.space4

        Repeater {
            model: PackageUpdates.packages
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: Theme.dp(48)
                radius: Theme.pillRadius
                color: Theme.surface
                border.width: Theme.hairline
                border.color: Theme.withAlpha(Theme.overlay, 0.28)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space10
                    anchors.rightMargin: Theme.space8
                    spacing: Theme.space8

                    Rectangle {
                        implicitWidth: srcLabel.implicitWidth + Theme.space8
                        implicitHeight: Theme.dp(18)
                        radius: Theme.pillRadius
                        color: Theme.withAlpha(panel.sourceColor(modelData.source), 0.22)
                        Text {
                            id: srcLabel
                            anchors.centerIn: parent
                            text: panel.sourceLabel(modelData.source)
                            color: panel.sourceColor(modelData.source)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: modelData.name
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.oldVer + " → " + modelData.newVer
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            elide: Text.ElideRight
                        }
                    }

                    TextButton {
                        text: I18n.tr("Update")
                        onClicked: PackageUpdates.updatePackage(modelData)
                    }
                }
            }
        }
    }
}
