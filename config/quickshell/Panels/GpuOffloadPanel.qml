import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Config
import qs.Services

Popout {
    id: panel
    ns: "qs-gpu-offload"
    cardWidth: 400
    cardMinWidth: 320
    shown: Globals.gpuOffloadOpen

    property string search: ""
    property var searchResults: []

    onShownChanged: {
        if (shown) {
            search = ""
            searchInput.text = ""
            searchResults = []
            focusTimer.restart()
        }
    }

    function runSearch() {
        const q = search.trim().toLowerCase()
        searchResults = q === "" ? [] : AppCatalog.entries
            .filter(a => a.searchText.includes(q) && !GpuOffload.isTracked(a.entry.id))
            .slice(0, 6)
    }

    onSearchChanged: searchDebounce.restart()

    Timer { id: searchDebounce; interval: 80; onTriggered: panel.runSearch() }
    Timer { id: focusTimer; interval: 60; onTriggered: searchInput.input.forceActiveFocus() }

    Text {
        Layout.fillWidth: true
        text: I18n.tr("GPU offload apps")
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize + 2
        font.bold: true
    }

    Text {
        Layout.fillWidth: true
        text: I18n.tr("Apps toggled on always launch through the dedicated GPU.")
        color: Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        wrapMode: Text.WordWrap
    }

    SearchField {
        id: searchInput
        Layout.fillWidth: true
        input.focus: true
        placeholder: I18n.tr("Add an app…")
        onTextChanged: panel.search = text
        onEscapePressed: (event) => {
            if (panel.search !== "") { searchInput.clear(); event.accepted = true }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.space4
        visible: panel.searchResults.length > 0

        Repeater {
            model: panel.searchResults
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: Theme.dp(36)
                radius: Theme.pillRadius
                color: resMa.containsMouse ? Theme.surfaceHi : Theme.surface

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space8
                    anchors.rightMargin: Theme.space8
                    spacing: Theme.space8

                    Text {
                        Layout.fillWidth: true
                        text: modelData.entry.name ?? ""
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        elide: Text.ElideRight
                    }
                    Text {
                        text: "+"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                }

                MouseArea {
                    id: resMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        GpuOffload.addApp(modelData.entry)
                        searchInput.clear()
                        panel.search = ""
                        panel.searchResults = []
                    }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: GpuOffload.apps.length === 0
        text: I18n.tr("No apps added yet")
        color: Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.space4

        Repeater {
            model: GpuOffload.apps
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: Theme.dp(44)
                radius: Theme.pillRadius
                color: Theme.surface
                border.width: Theme.hairline
                border.color: Theme.withAlpha(Theme.overlay, 0.28)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space10
                    anchors.rightMargin: Theme.space8
                    spacing: Theme.space10

                    readonly property string iconSrc:
                        (modelData.icon ?? "") !== "" ? Quickshell.iconPath(modelData.icon, true) : ""

                    Image {
                        visible: parent.iconSrc !== ""
                        source: parent.iconSrc
                        Layout.preferredWidth: Theme.dp(22)
                        Layout.preferredHeight: Theme.dp(22)
                    }

                    Text {
                        Layout.fillWidth: true
                        text: modelData.name
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        elide: Text.ElideRight
                    }

                    Switch {
                        checked: modelData.enabled
                        onToggled: GpuOffload.setEnabled(modelData.id, !modelData.enabled)
                    }

                    IconButton {
                        icon: "󰆴"
                        iconColor: Theme.fgMuted
                        hoverIconColor: Theme.red
                        hoverColor: Theme.withAlpha(Theme.red, 0.22)
                        onClicked: GpuOffload.removeApp(modelData.id)
                    }
                }
            }
        }
    }
}
