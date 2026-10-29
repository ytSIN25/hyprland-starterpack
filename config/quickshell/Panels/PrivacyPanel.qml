import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Privacy panel: which apps are using the camera and the microphone right
// now, a mic mute switch and a force-quit button per app.
// Data: Services/Privacy.qml.
Popout {
    id: panel
    ns: "qs-privacy"
    cardWidth: 420
    cardMinWidth: 320
    shown: Globals.privacyOpen

    // ── Camera ──────────────────────────────────────────────────────────────
    AiCard {
        Layout.fillHeight: false
        AiCardTitle {
            text: I18n.tr("Camera")
            badge: Privacy.cameraInUse ? I18n.tr("in use") : I18n.tr("off")
            badgeColor: Privacy.cameraInUse ? Theme.green : Theme.fgDim
            Text { anchors.centerIn: parent; text: "\u{f0100}"; color: Privacy.cameraInUse ? Theme.green : Theme.fgDim; font.family: Theme.fontFamily; font.pixelSize: Theme.dp(18) }
        }
        Text {
            visible: !Privacy.cameraInUse
            text: I18n.tr("No app is using the camera.")
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        Repeater {
            model: Privacy.cameraApps
            AppRow {
                required property var modelData
                dotColor: Theme.green
                title: modelData.name
                subtitle: "PID " + modelData.pid
                pid: modelData.pid
            }
        }
    }

    // ── Microphone ──────────────────────────────────────────────────────────
    AiCard {
        Layout.fillHeight: false
        AiCardTitle {
            text: I18n.tr("Microphone")
            badge: !Privacy.micInUse ? I18n.tr("off") : Privacy.micMuted ? I18n.tr("muted") : I18n.tr("in use")
            badgeColor: !Privacy.micInUse || Privacy.micMuted ? Theme.fgDim : Theme.orange
            Text { anchors.centerIn: parent; text: Privacy.micMuted ? "\u{f036d}" : "\u{f036c}"; color: Privacy.micInUse && !Privacy.micMuted ? Theme.orange : Theme.fgDim; font.family: Theme.fontFamily; font.pixelSize: Theme.dp(18) }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.dp(10)
            Text {
                Layout.fillWidth: true
                text: I18n.tr("Mute microphone")
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
            Switch {
                checked: Privacy.micMuted
                onColor: Theme.red
                onToggled: Privacy.toggleMicMute()
            }
        }
        Text {
            visible: !Privacy.micInUse
            text: I18n.tr("No app is recording audio.")
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        Repeater {
            model: Privacy.micStreams
            AppRow {
                required property var modelData
                dotColor: Privacy.micMuted ? Theme.fgDim : Theme.orange
                title: Privacy.streamName(modelData)
                subtitle: (modelData.properties?.["media.name"] ?? "")
                pid: Privacy.streamPid(modelData)
            }
        }
    }

    // One app: FwRow (dot, name, detail) + force-quit button when the PID is known.
    component AppRow: RowLayout {
        property alias dotColor: row.dotColor
        property alias title: row.title
        property alias subtitle: row.subtitle
        property int pid: 0
        Layout.fillWidth: true
        spacing: Theme.dp(8)
        FwRow { id: row }
        TextButton {
            visible: parent.pid > 0
            text: I18n.tr("Force quit")
            onClicked: Privacy.forceQuit(parent.pid)
        }
    }
}
